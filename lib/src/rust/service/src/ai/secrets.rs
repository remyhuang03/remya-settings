//! Custom endpoint API keys in the Secret Service through `secret-tool`.
//! The secret travels only on stdin and is never returned or logged.
use std::{
    io::{Read, Write},
    process::{Command, Stdio},
    time::{Duration, Instant},
};

const APPLICATION: &str = "top.remya.settings";

fn attributes(id: &str) -> [&str; 4] {
    ["application", APPLICATION, "ai-provider", id]
}

fn unavailable(error: std::io::Error) -> String {
    match error.kind() {
        std::io::ErrorKind::NotFound => {
            "Unavailable:Install libsecret (secret-tool) to store API keys.".into()
        }
        _ => format!("Unavailable:Cannot run secret-tool: {error}"),
    }
}

pub fn store(id: &str, secret: &str) -> Result<(), String> {
    let label = format!("Remy'a Settings AI provider {id}");
    let mut child = Command::new("secret-tool")
        .args(["store", "--label", &label])
        .args(attributes(id))
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(unavailable)?;
    let written = child
        .stdin
        .take()
        .expect("piped stdin")
        .write_all(secret.as_bytes());
    let status = child.wait().map_err(unavailable)?;
    if written.is_err() || !status.success() {
        return Err("Unavailable:The Secret Service did not store the API key.".into());
    }
    Ok(())
}

pub fn clear(id: &str) -> Result<(), String> {
    let status = Command::new("secret-tool")
        .arg("clear")
        .args(attributes(id))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(unavailable)?;
    // secret-tool clear also exits 1 when nothing matched.
    if !status.success() && exists(id) {
        return Err("Unavailable:The Secret Service did not remove the API key.".into());
    }
    Ok(())
}

/// Unreachable, hung or locked keyrings report no key rather than blocking or
/// failing the whole read.
pub fn exists(id: &str) -> bool {
    let Ok(mut child) = Command::new("secret-tool")
        .arg("lookup")
        .args(attributes(id))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut found = [0u8; 1];
                return status.success()
                    && child
                        .stdout
                        .take()
                        .is_some_and(|mut out| out.read(&mut found).is_ok_and(|n| n > 0));
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
            Err(_) => break,
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    false
}
