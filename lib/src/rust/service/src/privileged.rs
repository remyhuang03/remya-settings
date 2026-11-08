use remya_settings_date_time::api as clock;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

#[derive(Serialize, Deserialize)]
#[serde(tag = "operation", deny_unknown_fields)]
pub enum Request {
    PackageCache {
        keep: u8,
        uninstalled: bool,
    },
    RemovePackages {
        packages: Vec<remya_settings_storage::packages::Package>,
    },
    Uninstall {
        removal: remya_settings_applications::Removal,
    },
    Hostname {
        expected_static: String,
        hostname: String,
    },
    Timezone {
        timezone: String,
    },
    Manual {
        local_time: String,
        timezone: String,
    },
    Automatic {
        enabled: bool,
    },
    Servers {
        servers: Vec<String>,
    },
    Locale {
        locale: String,
    },
    Sync {},
    Restart {},
}

const MAX_FRAME: usize = 64 * 1024;

fn read_frame(reader: &mut impl BufRead) -> Result<Option<String>, String> {
    let mut bytes = Vec::new();
    let count = reader
        .take((MAX_FRAME + 1) as u64)
        .read_until(b'\n', &mut bytes)
        .map_err(|e| e.to_string())?;
    if count == 0 {
        return Ok(None);
    }
    if count > MAX_FRAME || bytes.last() != Some(&b'\n') {
        return Err("Invalid or oversized privilege request".into());
    }
    String::from_utf8(bytes)
        .map(Some)
        .map_err(|e| e.to_string())
}

pub fn serve() -> Result<(), String> {
    let status = std::fs::read_to_string("/proc/self/status").map_err(|e| e.to_string())?;
    if status
        .lines()
        .find(|l| l.starts_with("Uid:"))
        .and_then(|l| l.split_whitespace().nth(2))
        != Some("0")
    {
        return Err("Privileged service requires root".into());
    }
    let mut input = std::io::stdin().lock();
    let mut output = std::io::stdout().lock();
    writeln!(output, "ready-v1").map_err(|e| e.to_string())?;
    output.flush().map_err(|e| e.to_string())?;
    while let Some(line) = read_frame(&mut input)? {
        let request = serde_json::from_str::<Request>(&line);
        let result = request.map_err(|e| e.to_string()).and_then(|request| {
            let state = match request {
                Request::PackageCache { keep, uninstalled } => {
                    return remya_settings_storage::packages::clean_cache(
                        &remya_settings_storage::packages::RealProcess,
                        keep,
                        uninstalled,
                    );
                }
                Request::RemovePackages { packages } => {
                    return remya_settings_storage::packages::remove_packages(
                        &remya_settings_storage::packages::RealProcess,
                        &packages,
                    );
                }
                Request::Uninstall { removal } => {
                    return remya_settings_applications::uninstall(&removal, true);
                }
                Request::Hostname {
                    expected_static,
                    hostname,
                } => {
                    return remya_settings_system_information::hostname::apply(
                        &expected_static,
                        &hostname,
                    )
                    .and_then(|state| serde_json::to_value(state).map_err(|e| e.to_string()));
                }
                Request::Timezone { timezone } => clock::set_timezone(timezone),
                Request::Manual {
                    local_time,
                    timezone,
                } => clock::set_manual_time(local_time, timezone),
                Request::Automatic { enabled } => clock::set_automatic_time(enabled),
                Request::Servers { servers } => clock::set_time_servers(servers),
                Request::Locale { locale } => clock::set_time_locale(locale),
                Request::Sync {} => clock::sync_now(),
                Request::Restart {} => {
                    return clock::restart_system().map(|_| serde_json::Value::Null);
                }
            }?;
            serde_json::to_value(state).map_err(|e| e.to_string())
        });
        serde_json::to_writer(&mut output, &result).map_err(|e| e.to_string())?;
        writeln!(output)
            .and_then(|_| output.flush())
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub struct Session {
    child: Child,
    input: Option<ChildStdin>,
    output: BufReader<ChildStdout>,
}
impl Drop for Session {
    fn drop(&mut self) {
        drop(self.input.take());
        let _ = self.child.wait();
    }
}
impl Session {
    pub fn start() -> Result<Self, String> {
        let status = Command::new("/usr/bin/systemctl")
            .args(["--user", "start", "plasma-polkit-agent.service"])
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("Cannot start authentication agent; install polkit-kde-agent".into());
        }
        let mut child = Command::new("/usr/bin/pkexec")
            .arg("--disable-internal-agent")
            .arg(std::env::current_exe().map_err(|e| e.to_string())?)
            .arg("--privileged")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| e.to_string())?;
        let mut session = Self {
            input: child.stdin.take(),
            output: BufReader::new(child.stdout.take().unwrap()),
            child,
        };
        if read_frame(&mut session.output)?.as_deref() != Some("ready-v1\n") {
            return Err("Authorization canceled or privileged service unavailable. Reopen Settings to retry.".into());
        }
        Ok(session)
    }
    pub fn is_alive(&mut self) -> bool {
        self.child.try_wait().is_ok_and(|status| status.is_none())
    }
    fn send(&mut self, request: &Request) -> Result<(), String> {
        let encoded = serde_json::to_vec(request).map_err(|e| e.to_string())?;
        if encoded.len() >= MAX_FRAME {
            return Err("InvalidArgument:Privilege request is too large".into());
        }
        let input = self.input.as_mut().ok_or("Privilege input closed")?;
        input
            .write_all(&encoded)
            .and_then(|_| input.write_all(b"\n"))
            .and_then(|_| input.flush())
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    pub fn call(&mut self, request: &Request) -> Result<serde_json::Value, String> {
        self.send(request)?;
        let line = read_frame(&mut self.output)?.ok_or(
            "Privileged service stopped; close and reopen the Settings window to authorize again",
        )?;
        serde_json::from_str::<Result<serde_json::Value, String>>(&line)
            .map_err(|e| e.to_string())?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn detects_dead_helper_and_releases_child_on_eof() {
        let mut child = Command::new("cat")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut session = Session {
            input: child.stdin.take(),
            output: BufReader::new(child.stdout.take().unwrap()),
            child,
        };
        assert!(session.is_alive());
        session.child.kill().unwrap();
        session.child.wait().unwrap();
        assert!(!session.is_alive());
    }
    #[test]
    fn framing_and_whitelist() {
        let request = Request::RemovePackages {
            packages: (0..500)
                .map(|i| remya_settings_storage::packages::Package {
                    name: format!("package-{i:03}"),
                    version: "1.0.0-1".into(),
                })
                .collect(),
        };
        let mut frame = serde_json::to_vec(&request).unwrap();
        frame.push(b'\n');
        assert!(frame.len() <= MAX_FRAME);
        assert!(read_frame(&mut frame.as_slice()).unwrap().is_some());

        assert!(
            serde_json::from_str::<Request>(
                r#"{"operation":"PackageCache","keep":2,"uninstalled":false,"path":"/tmp"}"#
            )
            .is_err()
        );
        assert!(serde_json::from_str::<Request>(r#"{"operation":"RemovePackages","packages":[{"name":"x","version":"1","command":"id"}]}"#).is_err());
        assert!(read_frame(&mut &b"abc"[..]).is_err());
        assert!(read_frame(&mut &vec![b'x'; MAX_FRAME + 1][..]).is_err());
        assert!(serde_json::from_str::<Request>(r#"{"operation":"Exec","command":"id"}"#).is_err());
        assert!(
            serde_json::from_str::<Request>(r#"{"operation":"Sync","path":"/etc/passwd"}"#)
                .is_err()
        );
        assert!(read_frame(&mut &b""[..]).unwrap().is_none());
    }
}
