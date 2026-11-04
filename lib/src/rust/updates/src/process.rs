use std::{
    fs::File,
    io::Read,
    os::{fd::OwnedFd, unix::net::UnixStream},
    process::{Command, Stdio},
};

/// stdout/stderr share one stream so output stays in order.
pub fn run(mut command: Command, mut output: impl FnMut(&str)) -> Result<i32, String> {
    let (mut reader, writer) = UnixStream::pair().map_err(|e| e.to_string())?;
    let stderr = writer.try_clone().map_err(|e| e.to_string())?;
    command
        .stdin(Stdio::null())
        .stdout(Stdio::from(File::from(OwnedFd::from(writer))))
        .stderr(Stdio::from(File::from(OwnedFd::from(stderr))));
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    drop(command);
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captures_stdout_and_stderr_with_the_exit_code() {
        let mut command = Command::new("/bin/sh");
        command.args([
            "-c",
            "printf 'progress\\rfinished\\n'; printf warning >&2; exit 3",
        ]);
        let mut out = String::new();
        assert_eq!(run(command, |s| out.push_str(s)).unwrap(), 3);
        assert!(out.contains("finished") && out.contains("warning"));
    }
}
