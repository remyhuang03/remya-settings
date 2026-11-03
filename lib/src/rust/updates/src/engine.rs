use crate::{
    Candidate, Privilege, held_packages, installed_packages, nvidia_loaded, process,
    protocol::{self, BridgeRequest, Operation, Output},
};
use std::{
    io::BufReader,
    net::Shutdown,
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::Command,
    sync::Arc,
    thread,
};

pub(crate) trait Backend: Send + Sync {
    fn held(&self, all: bool) -> Result<Vec<String>, String>;
    fn check(&self, root: &Path, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String>;
    fn upgrade(
        &self,
        root: &Path,
        held: &[String],
        privilege: Arc<dyn Privilege>,
        output: &mut dyn FnMut(&str),
    ) -> Result<i32, String>;
}
pub(crate) struct RealBackend {
    pub bridge: PathBuf,
}
impl Backend for RealBackend {
    fn held(&self, all: bool) -> Result<Vec<String>, String> {
        let loaded = nvidia_loaded();
        let packages = if loaded && !all {
            installed_packages()?
        } else {
            vec![]
        };
        Ok(held_packages(all, loaded, &packages))
    }
    fn check(&self, root: &Path, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
        let mut candidates = Vec::new();
        for (program, args, source) in [
            ("/usr/bin/checkupdates", vec!["--nocolor"], "repository"),
            (
                "/usr/bin/yay",
                vec![
                    "-Qua",
                    "--color",
                    "never",
                    "--pacman",
                    "/usr/bin/pacman",
                    "--config",
                    "/etc/pacman.conf",
                ],
                "AUR",
            ),
        ] {
            output(&format!("Checking {source} updates…\n"));
            let mut command = Command::new(program);
            command
                .args(args)
                .env("LC_ALL", "C.UTF-8")
                .env("CHECKUPDATES_DB", root.join("check-database"));
            let mut captured = String::new();
            let mut overflow = false;
            let code = process::run(command, None, |text| {
                if captured.len() + text.len() <= 2 * 1024 * 1024 {
                    captured.push_str(text);
                } else {
                    overflow = true;
                }
                output(text);
            })?;
            if overflow {
                return Err(
                    "Update inventory exceeded its output limit; previous results were retained"
                        .into(),
                );
            }
            if !check_succeeded(program, code, &captured) {
                return Err(check_error(source, code, &captured));
            }
            candidates.extend(parse_candidates(&captured, source));
        }
        candidates.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(candidates)
    }
    fn upgrade(
        &self,
        root: &Path,
        held: &[String],
        privilege: Arc<dyn Privilege>,
        output: &mut dyn FnMut(&str),
    ) -> Result<i32, String> {
        if !self.bridge.is_file() {
            return Err("The installed updater authorization bridge is missing; rebuild and reinstall Settings".into());
        }
        let job = root
            .file_name()
            .and_then(|p| p.to_str())
            .ok_or("Invalid update job directory")?
            .to_owned();
        let (socket, child) = UnixStream::pair().map_err(|e| e.to_string())?;
        let stop = socket.try_clone().map_err(|e| e.to_string())?;
        let broker = thread::spawn(move || broker(socket, &job, privilege));
        let mut args = vec![
            "-Syu".into(),
            "--noconfirm".into(),
            "--sudo".into(),
            self.bridge.to_string_lossy().into_owned(),
            "--sudoflags".into(),
            String::new(),
            "--nosudoloop".into(),
            "--noremovemake".into(),
            "--builddir".into(),
            root.join("build").to_string_lossy().into_owned(),
            "--pacman".into(),
            "/usr/bin/pacman".into(),
            "--makepkg".into(),
            "/usr/bin/makepkg".into(),
            "--git".into(),
            "/usr/bin/git".into(),
            "--gpg".into(),
            "/usr/bin/gpg".into(),
            "--config".into(),
            "/etc/pacman.conf".into(),
        ];
        if !held.is_empty() {
            args.extend(["--ignore".into(), held.join(",")]);
        }
        let mut command = process::pty_command("/usr/bin/yay", &args);
        command
            .current_dir(root)
            .env("LC_ALL", "C.UTF-8")
            .env("TERM", "xterm")
            .env_remove("PACMAN_AUTH")
            .env("REMYA_UPDATE_JOB", root.file_name().unwrap());
        let result = process::run(command, Some(child), output);
        let _ = stop.shutdown(Shutdown::Both);
        let bridged = broker.join().map_err(|_| "Updater broker stopped")?;
        match result {
            Ok(0) => {
                bridged?;
                Ok(0)
            }
            other => other,
        }
    }
}
fn broker(socket: UnixStream, job: &str, privilege: Arc<dyn Privilege>) -> Result<(), String> {
    let mut writer = socket.try_clone().map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(socket);
    loop {
        let line = match protocol::read_frame(&mut reader) {
            Ok(Some(line)) => line,
            Ok(None) => return Ok(()),
            Err(error) if error.contains("Connection reset") || error.contains("Broken pipe") => {
                return Ok(());
            }
            Err(error) => return Err(error),
        };
        let request = serde_json::from_str::<BridgeRequest>(&line).map_err(|e| e.to_string())?;
        if request.job != job {
            return Err("Updater bridge job identity mismatch".into());
        }
        let mut connected = true;
        let result = if request.operation == Operation::Ping {
            Ok(0)
        } else {
            privilege.run(job, &request.operation, &mut |text| {
                if connected {
                    connected =
                        protocol::write_frame(&mut writer, &Output::Text { text: text.into() })
                            .is_ok();
                }
            })
        };
        if !connected {
            return Ok(());
        }
        let result = match result {
            Ok(code) => Output::Exit { code },
            Err(message) => Output::Error { message },
        };
        protocol::write_frame(&mut writer, &result)?;
    }
}
fn check_error(source: &str, code: i32, captured: &str) -> String {
    let mut terminal = crate::terminal::Log::default();
    terminal.push(captured);
    let mut lines = terminal
        .lines()
        .into_iter()
        .filter(|line| !line.trim().is_empty())
        .rev()
        .take(8)
        .collect::<Vec<_>>();
    lines.reverse();
    let diagnostic = lines.join("\n").chars().take(2000).collect::<String>();
    format!(
        "{source} update check failed (exit {code}): {}",
        if diagnostic.is_empty() {
            "The command returned no diagnostic output."
        } else {
            &diagnostic
        }
    )
}
fn check_succeeded(program: &str, code: i32, output: &str) -> bool {
    code == 0 || (program == "/usr/bin/checkupdates" && code == 2)
        // Yay uses an empty error / exit 1 when its upgrade graph is empty.
        || (program == "/usr/bin/yay" && code == 1 && output.trim().is_empty())
}
fn parse_candidates(text: &str, source: &str) -> Vec<Candidate> {
    text.lines()
        .filter_map(|line| {
            let words = line.split_whitespace().collect::<Vec<_>>();
            (words.len() >= 4 && words[2] == "->" && protocol::valid_package(words[0])).then(|| {
                Candidate {
                    name: words[0].into(),
                    installed: words[1].into(),
                    available: words[3].into(),
                    source: source.into(),
                    held: false,
                }
            })
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn update_candidates_ignore_diagnostics_instead_of_inventing_packages() {
        let result = parse_candidates(
            "warning: stale data\nexample 1.0-1 -> 2.0-1 [2 days ago]\nno package updates\n",
            "AUR",
        );
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].name, "example");
        assert_eq!(result[0].source, "AUR");
    }
    struct DrainingPrivilege(std::sync::mpsc::Sender<()>);
    impl Privilege for DrainingPrivilege {
        fn begin(&self, _: &str, _: bool) -> Result<Vec<String>, String> {
            unreachable!()
        }
        fn end(&self, _: &str) -> Result<(), String> {
            unreachable!()
        }
        fn run(&self, _: &str, _: &Operation, output: &mut dyn FnMut(&str)) -> Result<i32, String> {
            output("transaction started\n");
            thread::sleep(std::time::Duration::from_millis(25));
            output("transaction finished\n");
            self.0.send(()).unwrap();
            Ok(0)
        }
    }
    #[test]
    fn disconnected_output_observer_does_not_interrupt_an_authorized_transaction() {
        let (server, mut client) = UnixStream::pair().unwrap();
        let (finished, receive) = std::sync::mpsc::channel();
        let job = "remya-settings-update-abcdef";
        let broker =
            thread::spawn(move || broker(server, job, Arc::new(DrainingPrivilege(finished))));
        protocol::write_frame(
            &mut client,
            &BridgeRequest {
                job: job.into(),
                operation: Operation::Sync {
                    refresh: true,
                    upgrade: true,
                    packages: vec![],
                    dependencies: false,
                    needed: false,
                },
            },
        )
        .unwrap();
        let mut reader = BufReader::new(client.try_clone().unwrap());
        assert!(matches!(
            serde_json::from_str::<Output>(&protocol::read_frame(&mut reader).unwrap().unwrap())
                .unwrap(),
            Output::Text { .. }
        ));
        client.shutdown(Shutdown::Both).unwrap();
        receive
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap();
        broker.join().unwrap().unwrap();
    }
    #[test]
    fn empty_aur_graph_is_not_an_error_but_real_diagnostics_are_retained() {
        assert!(check_succeeded("/usr/bin/yay", 1, ""));
        assert!(!check_succeeded("/usr/bin/yay", 1, "error: request failed"));
        assert!(!check_succeeded("/usr/bin/checkupdates", 1, ""));
        assert!(check_succeeded("/usr/bin/checkupdates", 2, ""));
    }
    #[test]
    fn failed_check_summary_contains_bounded_real_terminal_diagnostics() {
        let message = check_error(
            "AUR",
            1,
            "\x1b[31merror: Get https://aur.archlinux.org/rpc: connection refused\x1b[0m\n",
        );
        assert!(message.contains("connection refused"));
        assert!(!message.contains('\x1b'));
        assert!(check_error("AUR", 1, &"diagnostic ".repeat(1000)).len() < 2200);
        assert!(check_error("AUR", 1, "").contains("no diagnostic"));
    }
}
