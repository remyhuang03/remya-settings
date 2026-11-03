use std::{
    fs::File,
    io::Read,
    os::{
        fd::{AsRawFd, OwnedFd},
        unix::{net::UnixStream, process::CommandExt},
    },
    path::Path,
    process::{Command, Stdio},
};

pub fn quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}
pub fn pty_command(program: &str, args: &[String]) -> Command {
    let command = std::iter::once(program.to_owned())
        .chain(args.iter().cloned())
        .map(|s| quote(&s))
        .collect::<Vec<_>>()
        .join(" ");
    let mut cmd = Command::new("/usr/bin/script");
    cmd.args([
        "--quiet",
        "--flush",
        "--return",
        "--command",
        &command,
        "/dev/null",
    ]);
    cmd
}
/// stdout/stderr share one stream; even a disconnected observer cannot interrupt the child transaction.
pub fn run(
    mut command: Command,
    bridge: Option<UnixStream>,
    mut output: impl FnMut(&str),
) -> Result<i32, String> {
    let (mut reader, writer) = UnixStream::pair().map_err(|e| e.to_string())?;
    let stderr = writer.try_clone().map_err(|e| e.to_string())?;
    command
        .stdin(Stdio::null())
        .stdout(Stdio::from(File::from(OwnedFd::from(writer))))
        .stderr(Stdio::from(File::from(OwnedFd::from(stderr))));
    if let Some(socket) = bridge.as_ref() {
        let fd = socket.as_raw_fd();
        // Only the private updater channel survives script -> shell -> yay -> sudo bridge.
        unsafe {
            command.pre_exec(move || {
                if fd != crate::protocol::BRIDGE_FD
                    && libc::dup2(fd, crate::protocol::BRIDGE_FD) == -1
                {
                    return Err(std::io::Error::last_os_error());
                }
                if libc::fcntl(crate::protocol::BRIDGE_FD, libc::F_SETFD, 0) == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    drop(command);
    drop(bridge);
    let mut bytes = [0u8; 512];
    let read_error = loop {
        match reader.read(&mut bytes) {
            Ok(0) => break None,
            Ok(n) => output(&String::from_utf8_lossy(&bytes[..n])),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => break Some(e.to_string()),
        }
    };
    let status = child.wait().map_err(|e| e.to_string())?;
    if let Some(error) = read_error {
        return Err(error);
    }
    Ok(status.code().unwrap_or(128))
}
pub fn fixed_environment(command: &mut Command) {
    command
        .env_clear()
        .env("PATH", "/usr/bin")
        .env("LC_ALL", "C.UTF-8")
        .env("TERM", "xterm");
}
pub fn job_base(uid: u32) -> std::path::PathBuf {
    Path::new("/var/tmp").join(format!("remya-settings-updates-{uid}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::Read, time::Duration};
    #[test]
    fn pty_captures_output_and_passes_only_the_private_bridge() {
        let (mut parent, child) = UnixStream::pair().unwrap();
        parent
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let command = pty_command(
            "/bin/sh",
            &[
                "-c".into(),
                "printf private >&3; printf 'progress\\rfinished\\n'; printf warning >&2".into(),
            ],
        );
        let mut out = String::new();
        assert_eq!(run(command, Some(child), |s| out.push_str(s)).unwrap(), 0);
        let mut data = [0; 7];
        parent.read_exact(&mut data).unwrap();
        assert_eq!(&data, b"private");
        assert!(out.contains("finished"));
        assert!(out.contains("warning"));
    }
}
