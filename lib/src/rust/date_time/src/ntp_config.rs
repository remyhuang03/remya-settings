use std::fs;
use std::path::Path;

pub const CONFIG: &str = "/etc/systemd/timesyncd.conf.d/90-remya-settings.conf";
const HEADER: &str = "# Managed by Remya Settings\n[Time]\nNTP=\nNTP=";

pub fn validate_servers(servers: &[String]) -> Result<(), String> {
    if servers.len() > 16 {
        return Err("Use at most 16 NTP servers".into());
    }
    for server in servers {
        if server.parse::<std::net::IpAddr>().is_ok() {
            continue;
        }
        let hostname = server.strip_suffix('.').unwrap_or(server);
        if hostname.len() > 253
            || hostname.split('.').any(|label| {
                label.is_empty()
                    || label.len() > 63
                    || label.starts_with('-')
                    || label.ends_with('-')
                    || !label
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'-')
            })
        {
            return Err("Use NTP host names or IP addresses, without URLs or ports".into());
        }
    }
    Ok(())
}

pub fn read(path: &Path) -> Result<Vec<String>, String> {
    let content = match fs::symlink_metadata(path) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(vec![]),
        Err(error) => return Err(error.to_string()),
        Ok(metadata) if !metadata.is_file() => {
            return Err("Refusing a non-regular time server configuration".into());
        }
        Ok(_) => fs::read_to_string(path).map_err(|e| e.to_string())?,
    };
    let servers = content.strip_prefix(HEADER).and_then(|value| value.strip_suffix('\n')).ok_or("The dedicated time server file contains unrecognized content; refusing to overwrite it")?;
    let servers: Vec<String> = servers.split_whitespace().map(str::to_owned).collect();
    validate_servers(&servers)?;
    if render(&servers) != content {
        return Err(
            "The dedicated time server file was modified externally; refusing to overwrite it"
                .into(),
        );
    }
    Ok(servers)
}

pub(super) fn render(servers: &[String]) -> String {
    format!("{HEADER}{}\n", servers.join(" "))
}
