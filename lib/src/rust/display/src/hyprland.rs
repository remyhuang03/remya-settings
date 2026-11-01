use serde::{Deserialize, Serialize};
use std::{
    io::Read,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct HardwareDetails {
    pub hdr: bool,
    pub bt2020: bool,
    pub chroma: bool,
    #[serde(rename = "vrrCapable")]
    pub vrr_capable: bool,
}

/// One entry of `hyprctl monitors all -j`.
#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Monitor {
    pub id: i64,
    pub name: String,
    pub description: String,
    pub make: String,
    pub model: String,
    pub serial: String,
    pub width: i64,
    pub height: i64,
    pub physical_width: i64,
    pub physical_height: i64,
    pub refresh_rate: f64,
    pub x: i64,
    pub y: i64,
    pub scale: f64,
    pub transform: i64,
    pub dpms_status: bool,
    pub vrr: bool,
    pub disabled: bool,
    pub current_format: String,
    pub mirror_of: String,
    pub available_modes: Vec<String>,
    pub color_management_preset: String,
    pub sdr_brightness: f64,
    pub sdr_saturation: f64,
    pub sdr_min_luminance: f64,
    pub sdr_max_luminance: f64,
    pub hardware_details: HardwareDetails,
}

/// The compositor operations used by the display feature.
pub trait Compositor: Send {
    fn monitors(&self) -> Result<Vec<Monitor>, String>;
    fn eval(&self, code: &str) -> Result<(), String>;
    fn uses_lua_config(&self) -> Result<bool, String>;
    fn global_vrr(&self) -> Result<i64, String>;
}

/// Runs a command without a shell and enforces a deadline.
pub(crate) fn run(program: &str, args: &[&str], timeout: Duration) -> Result<String, String> {
    let bytes = run_bytes(program, args, &[], timeout)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

/// Like [`run`], with extra environment and raw output for binary-producing tools.
pub fn run_bytes(
    program: &str,
    args: &[&str],
    environment: &[(&str, &str)],
    timeout: Duration,
) -> Result<Vec<u8>, String> {
    let mut child = Command::new(program)
        .args(args)
        .envs(environment.iter().copied())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{program}: {e}"))?;
    let mut stdout = child.stdout.take().ok_or("Missing stdout")?;
    let mut stderr = child.stderr.take().ok_or("Missing stderr")?;
    let reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.read_to_end(&mut bytes);
        bytes
    });
    let errors = thread::spawn(move || {
        let mut text = String::new();
        let _ = stderr.read_to_string(&mut text);
        text
    });
    let started = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            break status;
        }
        if started.elapsed() > timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!("{program} timed out"));
        }
        thread::sleep(Duration::from_millis(10));
    };
    let output = reader.join().unwrap_or_default();
    let error = errors.join().unwrap_or_default();
    if !status.success() && output.iter().all(u8::is_ascii_whitespace) {
        return Err(format!("{program}: {}", error.trim()));
    }
    Ok(output)
}

#[derive(Deserialize)]
struct Instance {
    instance: String,
}

/// Picks the live instance. The inherited signature goes stale when a resident
/// service outlives a compositor restart, so it is checked against the live list.
pub(crate) fn select_instance(inherited: Option<&str>, live: &[String]) -> Result<String, String> {
    if let Some(signature) = inherited.filter(|s| live.iter().any(|i| i == s)) {
        return Ok(signature.to_owned());
    }
    match live {
        [] => Err("Hyprland is not running".into()),
        [only] => Ok(only.clone()),
        _ => Err("Several Hyprland instances are running; cannot choose one".into()),
    }
}

pub struct Hyprctl;

impl Hyprctl {
    pub fn instance() -> Result<String, String> {
        let live: Vec<Instance> =
            serde_json::from_str(&run("hyprctl", &["-j", "instances"], TIMEOUT)?)
                .map_err(|e| format!("hyprctl instances: {e}"))?;
        let live = live.into_iter().map(|i| i.instance).collect::<Vec<_>>();
        let inherited = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok();
        select_instance(inherited.as_deref(), &live)
    }

    fn call(&self, args: &[&str]) -> Result<String, String> {
        let instance = Self::instance()?;
        let mut all = vec!["-i", &instance];
        all.extend_from_slice(args);
        run("hyprctl", &all, TIMEOUT)
    }
}

impl Compositor for Hyprctl {
    fn monitors(&self) -> Result<Vec<Monitor>, String> {
        serde_json::from_str(&self.call(&["-j", "monitors", "all"])?)
            .map_err(|e| format!("hyprctl monitors: {e}"))
    }
    fn eval(&self, code: &str) -> Result<(), String> {
        let reply = self.call(&["eval", code])?;
        match reply.trim() {
            "ok" => Ok(()),
            other => Err(format!("Hyprland rejected the change: {other}")),
        }
    }
    fn uses_lua_config(&self) -> Result<bool, String> {
        Ok(parse_provider(&self.call(&["status"])?) == Some("lua"))
    }
    fn global_vrr(&self) -> Result<i64, String> {
        let reply: serde_json::Value =
            serde_json::from_str(&self.call(&["-j", "getoption", "misc:vrr"])?)
                .map_err(|e| format!("hyprctl getoption: {e}"))?;
        reply["int"].as_i64().ok_or("Invalid misc:vrr value".into())
    }
}

fn parse_provider(status: &str) -> Option<&str> {
    status
        .lines()
        .find_map(|line| line.trim().strip_prefix("configProvider:"))
        .map(str::trim)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stale_signature_falls_back_only_when_unambiguous() {
        let one = vec!["new".to_owned()];
        let two = vec!["a".to_owned(), "b".to_owned()];
        assert_eq!(select_instance(Some("stale"), &one).unwrap(), "new");
        assert_eq!(select_instance(Some("b"), &two).unwrap(), "b");
        assert!(select_instance(Some("stale"), &two).is_err());
        assert!(select_instance(None, &[]).is_err());
    }

    #[test]
    fn provider_is_read_from_status() {
        assert_eq!(
            parse_provider("\nconfigProvider: lua\nbackend: drm\n"),
            Some("lua")
        );
        assert_eq!(parse_provider("backend: drm"), None);
    }

    #[test]
    fn monitor_json_uses_hyprland_names() {
        let monitor: Monitor = serde_json::from_str(
            r#"{"name":"eDP-1","refreshRate":120.0,"availableModes":["2560x1600@120.00Hz"],
                "mirrorOf":"none","hardwareDetails":{"hdr":true,"vrrCapable":true}}"#,
        )
        .unwrap();
        assert_eq!(monitor.refresh_rate, 120.0);
        assert!(monitor.hardware_details.vrr_capable);
    }
}
