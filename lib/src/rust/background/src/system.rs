//! External tools behind the background feature. Everything here is a separate
//! process; mpvpaper and ffmpeg are runtime tools, never linked into Settings.
use crate::video::UNIT;
use remya_settings_display::{Hyprctl, run_bytes};
use serde_json::Value;
use std::{collections::BTreeMap, path::Path, thread, time::Duration};
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, Signal, System, UpdateKind};

const QUICK: Duration = Duration::from_secs(5);
const MEDIA: Duration = Duration::from_secs(30);
const HYPRPAPER_UNIT: &str = "hyprpaper.service";
pub const SAMPLE_EDGE: u32 = 128;

pub trait Desktop: Send {
    fn monitors(&self) -> Result<Vec<String>, String>;
    fn apply_image(&self, monitor: &str, path: &str, fit: &str) -> Result<(), String>;
    /// What hyprpaper reports it is showing on each output.
    fn active_images(&self) -> Result<BTreeMap<String, String>, String>;
    fn layers(&self) -> Result<Value, String>;
    fn reload_units(&self) -> Result<(), String>;
    fn unit_enabled(&self) -> bool;
    fn unit_active(&self) -> bool;
    fn start_unit(&self) -> Result<(), String>;
    fn stop_unit(&self) -> Result<(), String>;
    /// Running mpvpaper processes as (pid, arguments), excluding the managed unit's.
    fn other_players(&self) -> Vec<(u32, Vec<String>)>;
    fn stop_process(&self, pid: u32);
    /// Replaces this session's hyprpaper; it reads its configuration only at start.
    fn restart_hyprpaper(&self, config: &Path) -> Result<(), String>;
    fn mime_type(&self, path: &Path) -> Result<String, String>;
    /// RGBA pixels of the first frame, at most [`SAMPLE_EDGE`] on each side.
    fn sample_pixels(&self, path: &str) -> Result<Vec<u8>, String>;
    fn write_preview(&self, path: &str, output: &Path) -> Result<(), String>;
}

pub struct RealDesktop;

fn hyprctl(args: &[&str]) -> Result<String, String> {
    // `hyprctl hyprpaper` ignores `-i`; the instance must come from the environment.
    let instance = Hyprctl::instance()?;
    let bytes = run_bytes(
        "hyprctl",
        args,
        &[("HYPRLAND_INSTANCE_SIGNATURE", instance.as_str())],
        QUICK,
    )?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

fn systemctl(args: &[&str]) -> Result<String, String> {
    let mut all = vec!["--user"];
    all.extend_from_slice(args);
    let bytes = run_bytes("systemctl", &all, &[], Duration::from_secs(15))?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

fn systemctl_status(args: &[&str], expected: &str) -> bool {
    systemctl(args).is_ok_and(|reply| reply.trim() == expected)
}

/// Processes of this Hyprland session only; another session's are never touched.
/// Names are scanned first: reading every process's command line and environment
/// costs the resident service tens of megabytes on each scan.
fn session_processes(name: &str, instance: &str) -> Vec<(Pid, Vec<String>)> {
    let Ok(mut system) = System::new() else {
        return Vec::new();
    };
    system.refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing());
    let named = system
        .processes()
        .iter()
        .filter(|(_, process)| process.name() == name && process.thread_kind().is_none())
        .map(|(pid, _)| *pid)
        .collect::<Vec<_>>();
    if named.is_empty() {
        return Vec::new();
    }
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&named),
        true,
        ProcessRefreshKind::nothing()
            .with_cmd(UpdateKind::Always)
            .with_environ(UpdateKind::Always),
    );
    let marker = format!("HYPRLAND_INSTANCE_SIGNATURE={instance}");
    named
        .into_iter()
        .filter_map(|pid| {
            let process = system.process(pid)?;
            process
                .environ()
                .iter()
                .any(|entry| *entry == *marker)
                .then(|| {
                    let args = process
                        .cmd()
                        .iter()
                        .map(|part| part.to_string_lossy().into_owned())
                        .collect();
                    (pid, args)
                })
        })
        .collect()
}

fn hyprpaper_pids(instance: &str) -> Vec<Pid> {
    session_processes("hyprpaper", instance)
        .into_iter()
        .map(|(pid, _)| pid)
        .collect()
}

/// A Lua string holding a shell-quoted argument for `hl.exec_cmd`. Slashes use a Lua
/// escape because hyprctl sends any request containing `/hyprpaper` to hyprpaper's
/// socket instead of Hyprland's, and the configuration path normally does.
fn exec_request(config: &Path) -> Result<String, String> {
    let path = config.to_str().ok_or("Unsupported configuration path")?;
    let shell = format!("'{}'", path.replace('\'', "'\\''"));
    let lua = format!("hyprpaper -c {shell}")
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('/', "\\47");
    Ok(format!("hl.exec_cmd(\"{lua}\")"))
}

/// Main PID of the managed unit, so it is not mistaken for an unrelated player.
fn unit_pid() -> Option<u32> {
    systemctl(&["show", "--property=MainPID", "--value", UNIT])
        .ok()?
        .trim()
        .parse()
        .ok()
        .filter(|pid| *pid != 0)
}

impl Desktop for RealDesktop {
    fn monitors(&self) -> Result<Vec<String>, String> {
        let reply: Value = serde_json::from_str(&hyprctl(&["-j", "monitors"])?)
            .map_err(|e| format!("hyprctl monitors: {e}"))?;
        Ok(reply
            .as_array()
            .ok_or("Invalid monitor list")?
            .iter()
            .filter_map(|m| m["name"].as_str().map(str::to_owned))
            .collect())
    }
    fn apply_image(&self, monitor: &str, path: &str, fit: &str) -> Result<(), String> {
        let request = format!("{monitor},{path},{fit}");
        let reply = hyprctl(&["hyprpaper", "wallpaper", &request])?;
        match reply.trim() {
            "" | "ok" => Ok(()),
            other => Err(format!("hyprpaper rejected {monitor}: {other}")),
        }
    }
    fn active_images(&self) -> Result<BTreeMap<String, String>, String> {
        Ok(parse_active(&hyprctl(&["hyprpaper", "listactive"])?))
    }
    fn layers(&self) -> Result<Value, String> {
        serde_json::from_str(&hyprctl(&["-j", "layers"])?)
            .map_err(|e| format!("hyprctl layers: {e}"))
    }
    fn reload_units(&self) -> Result<(), String> {
        systemctl(&["daemon-reload"]).map(|_| ())
    }
    fn unit_enabled(&self) -> bool {
        systemctl_status(&["is-enabled", UNIT], "enabled")
    }
    fn unit_active(&self) -> bool {
        systemctl_status(&["is-active", UNIT], "active")
    }
    fn start_unit(&self) -> Result<(), String> {
        systemctl(&["enable", UNIT])?;
        systemctl(&["restart", UNIT]).map(|_| ())?;
        // A bad file or missing mpvpaper fails shortly after the start returns.
        thread::sleep(Duration::from_millis(800));
        if self.unit_active() {
            Ok(())
        } else {
            let log = systemctl(&["status", "--no-pager", "--lines=5", UNIT]).unwrap_or_default();
            Err(format!("mpvpaper did not keep running\n{log}"))
        }
    }
    fn stop_unit(&self) -> Result<(), String> {
        systemctl(&["disable", "--now", UNIT]).map(|_| ())
    }
    fn other_players(&self) -> Vec<(u32, Vec<String>)> {
        let managed = unit_pid();
        let Ok(instance) = Hyprctl::instance() else {
            return Vec::new();
        };
        session_processes("mpvpaper", &instance)
            .into_iter()
            .filter(|(pid, _)| Some(pid.as_u32()) != managed)
            .map(|(pid, args)| (pid.as_u32(), args))
            .collect()
    }
    fn stop_process(&self, pid: u32) {
        let target = Pid::from_u32(pid);
        let Ok(mut system) = System::new() else {
            return;
        };
        system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[target]),
            true,
            ProcessRefreshKind::nothing(),
        );
        if let Some(process) = system.process(target) {
            process.kill_with(Signal::Term);
        }
    }
    fn restart_hyprpaper(&self, config: &Path) -> Result<(), String> {
        let instance = Hyprctl::instance()?;
        let managed = systemctl_status(&["is-enabled", HYPRPAPER_UNIT], "enabled")
            || systemctl_status(&["is-active", HYPRPAPER_UNIT], "active");
        if managed {
            systemctl(&["stop", HYPRPAPER_UNIT])?;
        }
        // Stopping every instance also clears duplicates from two autostart entries.
        for pid in hyprpaper_pids(&instance) {
            self.stop_process(pid.as_u32());
        }
        for _ in 0..40 {
            if hyprpaper_pids(&instance).is_empty() {
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
        if !hyprpaper_pids(&instance).is_empty() {
            return Err("hyprpaper did not stop".into());
        }
        if managed {
            return systemctl(&["start", HYPRPAPER_UNIT]).map(|_| ());
        }
        // Started by the compositor so it inherits the session like an autostart entry.
        let reply = hyprctl(&["eval", &exec_request(config)?])?;
        match reply.trim() {
            "ok" | "" => Ok(()),
            other => Err(format!("Hyprland could not start hyprpaper: {other}")),
        }
    }
    fn mime_type(&self, path: &Path) -> Result<String, String> {
        let path = path.to_str().ok_or("Unsupported file path")?;
        let bytes = run_bytes("file", &["--brief", "--mime-type", "--", path], &[], QUICK)?;
        Ok(String::from_utf8_lossy(&bytes).trim().to_owned())
    }
    fn sample_pixels(&self, path: &str) -> Result<Vec<u8>, String> {
        let filter =
            format!("scale={SAMPLE_EDGE}:{SAMPLE_EDGE}:force_original_aspect_ratio=decrease");
        let pixels = run_bytes(
            "ffmpeg",
            &[
                "-v",
                "error",
                "-i",
                path,
                "-frames:v",
                "1",
                "-vf",
                &filter,
                "-f",
                "rawvideo",
                "-pix_fmt",
                "rgba",
                "-",
            ],
            &[],
            MEDIA,
        )?;
        if pixels.is_empty() {
            return Err("ffmpeg produced no frame".into());
        }
        Ok(pixels)
    }
    fn write_preview(&self, path: &str, output: &Path) -> Result<(), String> {
        let output = output.to_str().ok_or("Unsupported cache path")?;
        run_bytes(
            "ffmpeg",
            &[
                "-y",
                "-v",
                "error",
                "-i",
                path,
                "-frames:v",
                "1",
                "-vf",
                "scale=960:-2:force_original_aspect_ratio=decrease",
                output,
            ],
            &[],
            MEDIA,
        )
        .map(|_| ())
    }
}

fn parse_active(reply: &str) -> BTreeMap<String, String> {
    reply
        .lines()
        .filter_map(|line| {
            let (monitor, path) = line.split_once(": ")?;
            path.starts_with('/')
                .then(|| (monitor.to_owned(), path.to_owned()))
        })
        .collect()
}

/// Facts that would otherwise make a successful change look like it did nothing.
pub fn layer_warnings(layers: &Value) -> Vec<String> {
    let mut instances = false;
    let mut covering = std::collections::BTreeSet::new();
    let Some(outputs) = layers.as_object() else {
        return Vec::new();
    };
    for output in outputs.values() {
        let level = |index: &str| {
            output["levels"][index]
                .as_array()
                .cloned()
                .unwrap_or_default()
        };
        let background = level("0");
        let papers = background
            .iter()
            .filter(|l| l["namespace"] == "hyprpaper")
            .collect::<Vec<_>>();
        instances |= papers.len() > 1;
        let Some(paper) = papers.first() else {
            continue;
        };
        for layer in level("1") {
            let name = layer["namespace"].as_str().unwrap_or("");
            if name != "mpvpaper" && layer["w"] == paper["w"] && layer["h"] == paper["h"] {
                covering.insert(name.to_owned());
            }
        }
    }
    let mut warnings = Vec::new();
    if instances {
        warnings.push(
            "Several hyprpaper instances are running. Changes reach only one of them, so another may keep showing the old image. Keep one autostart entry for hyprpaper.".to_owned(),
        );
    }
    for name in covering {
        warnings.push(format!(
            "The full-screen layer {name} is drawn above the background and may hide it."
        ));
    }
    warnings
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn exec_request_quotes_for_the_shell_and_lua() {
        let request = exec_request(Path::new("/a b/hyprpaper/it's.conf")).unwrap();
        assert_eq!(
            request,
            r#"hl.exec_cmd("hyprpaper -c '\47a b\47hyprpaper\47it'\\''s.conf'")"#
        );
        assert!(!request.contains("/hyprpaper"));
    }

    #[test]
    fn active_list_ignores_errors_and_keeps_paths() {
        let parsed = parse_active("DP-1: /a b.png\nerror: Invalid request\n");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed["DP-1"], "/a b.png");
    }

    #[test]
    fn duplicate_instances_and_covering_layers_are_reported() {
        let paper = json!({"namespace":"hyprpaper","w":100,"h":50});
        let layers = json!({"DP-1":{"levels":{
            "0":[paper,paper],
            "1":[{"namespace":"quickshell:background","w":100,"h":50},{"namespace":"mpvpaper","w":100,"h":50}],
            "2":[{"namespace":"quickshell:bar","w":100,"h":10}],
        }}});
        let warnings = layer_warnings(&layers);
        assert_eq!(warnings.len(), 2);
        assert!(warnings[0].contains("Several hyprpaper"));
        assert!(warnings[1].contains("quickshell:background"));
        assert!(layer_warnings(&json!({"DP-1":{"levels":{"0":[paper]}}})).is_empty());
    }
}
