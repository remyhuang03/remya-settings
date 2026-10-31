use remya_settings_date_time::api as clock;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

#[derive(Serialize, Deserialize)]
#[serde(tag = "operation", deny_unknown_fields)]
pub enum Request {
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

fn read_frame(reader: &mut impl BufRead) -> Result<Option<String>, String> {
    let mut bytes = Vec::new();
    let count = reader
        .take(8193)
        .read_until(b'\n', &mut bytes)
        .map_err(|e| e.to_string())?;
    if count == 0 {
        return Ok(None);
    }
    if count > 8192 || bytes.last() != Some(&b'\n') {
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
        let result = serde_json::from_str::<Request>(&line)
            .map_err(|e| e.to_string())
            .and_then(|request| {
                let state = match request {
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
    pub fn call(&mut self, request: &Request) -> Result<serde_json::Value, String> {
        let encoded = serde_json::to_vec(request).map_err(|e| e.to_string())?;
        if encoded.len() >= 8192 {
            return Err("InvalidArgument:Privilege request is too large".into());
        }
        let input = self.input.as_mut().ok_or("Privilege input closed")?;
        input
            .write_all(&encoded)
            .and_then(|_| input.write_all(b"\n"))
            .and_then(|_| input.flush())
            .map_err(|e| e.to_string())?;
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
        assert!(read_frame(&mut &b"abc"[..]).is_err());
        assert!(read_frame(&mut &vec![b'x'; 8193][..]).is_err());
        assert!(serde_json::from_str::<Request>(r#"{"operation":"Exec","command":"id"}"#).is_err());
        assert!(
            serde_json::from_str::<Request>(r#"{"operation":"Sync","path":"/etc/passwd"}"#)
                .is_err()
        );
        assert!(read_frame(&mut &b""[..]).unwrap().is_none());
    }
}
