//! CodexBar CLI access. Every call runs the `codexbar` process with an explicit
//! `CODEXBAR_CONFIG`; secrets reach it only through stdin.
use serde_json::{Value, json};
use std::{
    env, fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};

pub fn config_path() -> Result<PathBuf, String> {
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute());
    let expand = |value: &str| match value.strip_prefix("~/") {
        Some(relative) => home.as_ref().map(|home| home.join(relative)),
        None => Some(PathBuf::from(value)),
    };
    if let Ok(value) = env::var("CODEXBAR_CONFIG")
        && !value.trim().is_empty()
    {
        return expand(value.trim()).ok_or_else(|| "Unavailable:Absolute HOME required".into());
    }
    if let Ok(value) = env::var("XDG_CONFIG_HOME")
        && let Some(root) = expand(value.trim()).filter(|root| root.is_absolute())
    {
        return Ok(root.join("codexbar/config.json"));
    }
    let home = home.ok_or("Unavailable:Absolute HOME required")?;
    let current = home.join(".config/codexbar/config.json");
    let legacy = home.join(".codexbar/config.json");
    Ok(if !current.exists() && legacy.exists() {
        legacy
    } else {
        current
    })
}

fn run(path: &Path, args: &[&str], stdin: Option<&str>) -> Result<Output, String> {
    let mut child = Command::new("codexbar")
        .args(args)
        .env("CODEXBAR_CONFIG", path)
        .stdin(if stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => {
                "Unavailable:Install codexbar-cli to manage AI providers.".to_string()
            }
            _ => format!("Unavailable:Cannot run CodexBar: {error}"),
        })?;
    if let Some(secret) = stdin {
        // Dropping the handle closes stdin so CodexBar sees the end of the secret.
        let mut input = child.stdin.take().expect("piped stdin");
        input.write_all(secret.as_bytes()).map_err(|error| {
            format!("Unavailable:Cannot pass the credential to CodexBar: {error}")
        })?;
    }
    // Drain stdout on its own thread so a large reply cannot fill the pipe
    // while the deadline below waits for the process.
    let mut stdout = child.stdout.take().expect("piped stdout");
    let reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        stdout.read_to_end(&mut bytes).map(|_| bytes)
    });
    let deadline = Instant::now() + TIMEOUT;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(25)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Unavailable:CodexBar did not answer in time.".into());
            }
            Err(error) => return Err(format!("Unavailable:Cannot run CodexBar: {error}")),
        }
    };
    let stdout = reader
        .join()
        .map_err(|_| "Unavailable:Cannot read CodexBar output.".to_string())?
        .map_err(|error| format!("Unavailable:Cannot read CodexBar output: {error}"))?;
    Ok(Output {
        status,
        stdout,
        stderr: Vec::new(),
    })
}

/// Long enough for the all-provider usage probe, short enough not to wedge the service.
const TIMEOUT: Duration = Duration::from_secs(45);

fn cli_with(path: &Path, args: &[&str], stdin: Option<&str>) -> Result<Value, String> {
    let output = run(path, &[args, &["--format", "json"]].concat(), stdin)?;
    if !output.status.success() {
        return Err("Unavailable:CodexBar could not read or update its configuration.".into());
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|_| "Unavailable:Invalid CodexBar response.".into())
}

pub fn cli(path: &Path, args: &[&str]) -> Result<Value, String> {
    cli_with(path, args, None)
}

pub fn cli_stdin(path: &Path, args: &[&str], secret: &str) -> Result<Value, String> {
    cli_with(path, args, Some(secret))
}

/// `None` when the codexbar executable is missing.
pub fn version() -> Result<Option<String>, String> {
    match Command::new("codexbar")
        .arg("--version")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Unavailable:Cannot run CodexBar: {error}")),
        Ok(output) if output.status.success() => Ok(String::from_utf8_lossy(&output.stdout)
            .split_whitespace()
            .last()
            .map(str::to_owned)),
        Ok(_) => Err("Unavailable:CodexBar did not report its version.".into()),
    }
}

/// The usage probe exits non-zero when any provider fails, but still prints
/// one JSON row per provider.
pub fn probe(path: &Path) -> Result<Vec<Value>, String> {
    let output = run(
        path,
        &["usage", "--provider", "all", "--format", "json"],
        None,
    )?;
    serde_json::from_slice::<Value>(&output.stdout)
        .ok()
        .and_then(|rows| rows.as_array().cloned())
        .ok_or_else(|| "Unavailable:Invalid CodexBar usage response.".into())
}

pub fn configured(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(format!(
            "Unavailable:Cannot inspect CodexBar configuration: {error}"
        )),
    }
}

/// Raw `config providers` rows: `{provider, displayName, enabled, defaultEnabled, authentication?}`.
pub fn providers(path: &Path) -> Result<Vec<Value>, String> {
    cli(path, &["config", "providers"])?
        .as_array()
        .filter(|rows| {
            rows.iter().all(|row| {
                row["provider"].is_string()
                    && row["displayName"].is_string()
                    && row["enabled"].is_boolean()
            })
        })
        .cloned()
        .ok_or_else(|| "Unavailable:Invalid CodexBar provider list.".into())
}

/// Redacted `config dump` provider entries; empty without a config file.
pub fn dump(path: &Path) -> Result<Vec<Value>, String> {
    cli(path, &["config", "dump"])?["providers"]
        .as_array()
        .cloned()
        .ok_or_else(|| "Unavailable:Invalid CodexBar configuration dump.".into())
}

pub fn editable(row: &Value) -> bool {
    row["authentication"].is_object()
}

pub fn first_config(providers: &[Value], id: &str, enabled: bool) -> Value {
    json!({"version":1,"providers":providers.iter().filter(|row| editable(row))
        .map(|row| json!({"id":row["provider"],"enabled":row["provider"] != id || enabled}))
        .collect::<Vec<_>>()})
}

/// Writes CodexBar's first configuration without clobbering a file created meanwhile.
pub fn initialize(path: &Path, providers: &[Value], id: &str, enabled: bool) -> Result<(), String> {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(directory).map_err(|error| error.to_string())?;
    let mut staged =
        tempfile::NamedTempFile::new_in(directory).map_err(|error| error.to_string())?;
    staged
        .write_all(first_config(providers, id, enabled).to_string().as_bytes())
        .and_then(|()| staged.as_file().sync_all())
        .map_err(|error| error.to_string())?;
    cli(staged.path(), &["config", "validate"])?;
    staged
        .persist_noclobber(path)
        .map_err(|error| error.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn first_edit_preserves_default_tracking_for_other_providers() {
        let auth = serde_json::json!({});
        let providers = [
            serde_json::json!({"provider":"claude","authentication":auth,"enabled":false}),
            serde_json::json!({"provider":"gemini","authentication":auth,"enabled":false}),
            serde_json::json!({"provider":"local","enabled":true}),
        ];
        assert_eq!(
            super::first_config(&providers, "claude", false)["providers"],
            serde_json::json!([{"id":"claude","enabled":false},{"id":"gemini","enabled":true}])
        );
    }
}
