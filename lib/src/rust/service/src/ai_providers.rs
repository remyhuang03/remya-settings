use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

pub const ID: &str = "ai-providers.tracking";

fn config_path() -> Result<PathBuf, String> {
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

fn cli(path: &Path, args: &[&str]) -> Result<Value, String> {
    let output = Command::new("codexbar")
        .args(args)
        .args(["--format", "json"])
        .env("CODEXBAR_CONFIG", path)
        .stdin(Stdio::null())
        .output()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => {
                "Unavailable:Install codexbar-cli to manage AI providers.".into()
            }
            _ => format!("Unavailable:Cannot run CodexBar: {error}"),
        })?;
    if !output.status.success() {
        return Err("Unavailable:CodexBar could not read or update its configuration.".into());
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|_| "Unavailable:Invalid CodexBar response.".into())
}

fn configured(path: &Path) -> Result<bool, String> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(format!(
            "Unavailable:Cannot inspect CodexBar configuration: {error}"
        )),
    }
}

fn providers(path: &Path) -> Result<Vec<Value>, String> {
    cli(path, &["config", "providers"])?
        .as_array()
        .map(|rows| {
            rows.iter()
                .filter_map(|row| {
                    Some(json!({
                        "id":row["provider"].as_str()?,
                        "name":row["displayName"].as_str()?,
                        "enabled":row["enabled"].as_bool()?,
                        "editable":row["authentication"].is_object(),
                    }))
                })
                .collect()
        })
        .ok_or_else(|| "Unavailable:Invalid CodexBar provider list.".into())
}

fn first_config(providers: &[Value], id: &str, enabled: bool) -> Value {
    json!({"version":1,"providers":providers.iter().filter(|row| row["editable"] == true)
        .map(|row| json!({"id":row["id"],"enabled":row["id"] != id || enabled}))
        .collect::<Vec<_>>()})
}

fn initialize(path: &Path, providers: &[Value], id: &str, enabled: bool) -> Result<(), String> {
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

pub fn tracking(request: Option<&str>) -> Result<Value, String> {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Change {
        id: String,
        enabled: bool,
    }
    let path = config_path()?;
    let mut automatic = !configured(&path)?;
    if !automatic {
        cli(&path, &["config", "validate"])?;
    }
    let mut rows = providers(&path)?;
    if let Some(request) = request {
        let change: Change = serde_json::from_str(request)
            .map_err(|_| "InvalidArgument:Expected a provider ID and enabled boolean.")?;
        if !rows
            .iter()
            .any(|row| row["id"] == change.id && row["editable"] == true)
        {
            return Err("InvalidArgument:Unknown or unsupported AI provider.".into());
        }
        if automatic {
            initialize(&path, &rows, &change.id, change.enabled)?;
            automatic = false;
        } else {
            let action = if change.enabled { "enable" } else { "disable" };
            cli(&path, &["config", action, "--provider", &change.id])?;
        }
        rows = providers(&path)?;
        if !rows
            .iter()
            .any(|row| row["id"] == change.id && row["enabled"] == change.enabled)
        {
            return Err("Unavailable:CodexBar did not retain the requested provider state.".into());
        }
    }
    if automatic {
        for row in &mut rows {
            row["enabled"] = json!(true);
        }
    }
    Ok(json!({"id":ID,"availability":"available","value":{"automatic":automatic,"providers":rows}}))
}

#[cfg(test)]
mod tests {
    #[test]
    fn first_edit_preserves_default_tracking_for_other_providers() {
        let providers = [
            serde_json::json!({"id":"claude","editable":true,"enabled":false}),
            serde_json::json!({"id":"gemini","editable":true,"enabled":false}),
        ];
        assert_eq!(
            super::first_config(&providers, "claude", false)["providers"],
            serde_json::json!([{"id":"claude","enabled":false},{"id":"gemini","enabled":true}])
        );
    }
}
