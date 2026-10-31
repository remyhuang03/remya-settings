use std::process::Command;
pub(crate) fn set_servers(servers: &[String]) -> Result<(), String> {
    crate::ntp_config::validate_servers(servers)?;
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open("/run/remya-settings-time-servers.lock")
        .map_err(|e| e.to_string())?;
    lock.try_lock()
        .map_err(|_| "Another time server change is running")?;
    crate::ntp_config_write::apply(
        std::path::Path::new(crate::ntp_config::CONFIG),
        servers,
        |servers| {
            let result = Command::new("/usr/bin/systemctl")
                .args(["restart", "systemd-timesyncd.service"])
                .output()
                .map_err(|e| e.to_string())?;
            if !result.status.success() {
                return Err(format!(
                    "Time synchronization restart failed: {}",
                    String::from_utf8_lossy(&result.stderr)
                ));
            }
            if !servers.is_empty() {
                let result = Command::new("/usr/bin/busctl")
                    .args([
                        "--system",
                        "get-property",
                        "org.freedesktop.timesync1",
                        "/org/freedesktop/timesync1",
                        "org.freedesktop.timesync1.Manager",
                        "SystemNTPServers",
                    ])
                    .output()
                    .map_err(|e| e.to_string())?;
                let expected = format!(
                    "as {} {}",
                    servers.len(),
                    servers
                        .iter()
                        .map(|s| format!("\"{s}\""))
                        .collect::<Vec<_>>()
                        .join(" ")
                );
                if !result.status.success()
                    || String::from_utf8_lossy(&result.stdout).trim() != expected
                {
                    return Err(
                    "Effective NTP servers differ from the request; check later systemd drop-ins"
                        .into(),
                );
                }
            }
            Ok(())
        },
    )
}
