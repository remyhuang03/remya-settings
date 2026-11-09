//! Edit only timeouts in unambiguous listener blocks; commands stay byte-for-byte intact.
use gio::glib::variant::ToVariant;
use remya_settings_display::{atomic_write, run_bytes};
use std::time::Duration;
use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
};
pub const START_ID: &str = "power.idle-daemon";

#[derive(Clone, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Timeouts {
    pub screen: u32,
    pub sleep: u32,
    /// Seconds before `loginctl lock-session`; 0 when no lock listener is active.
    #[serde(default)]
    pub lock: u32,
    /// Whether `before_sleep_cmd` locks the session.
    #[serde(default)]
    pub lock_before_sleep: bool,
}

const LOCK: &str = "loginctl lock-session";
const BEFORE_SLEEP: &str = "before_sleep_cmd = loginctl lock-session";

/// The single top-level `general { ... }` block, if any.
fn general(text: &str) -> Result<Option<(usize, usize)>, String> {
    let mut found = None;
    let mut start = None;
    let mut offset = 0;
    for line in text.split_inclusive('\n') {
        let clean = line.split('#').next().unwrap_or("").trim();
        if clean == "general {" {
            if found.is_some() || start.is_some() {
                return Err("Ambiguous general sections".into());
            }
            start = Some(offset);
        } else if clean == "}" {
            if let Some(s) = start.take() {
                found = Some((s, offset + line.len()));
            }
        }
        offset += line.len();
    }
    Ok(found)
}

/// Whether hypridle has a `lock_cmd`, without which `loginctl lock-session` does nothing.
pub fn can_lock(text: &str) -> bool {
    general(text).ok().flatten().is_some_and(|(start, end)| {
        text[start..end]
            .lines()
            .any(|l| l.trim().starts_with("lock_cmd") && l.contains('='))
    })
}
fn listeners(text: &str) -> Result<Vec<(usize, usize, &str)>, String> {
    let mut result = vec![];
    let mut start = None;
    let mut offset = 0;
    for line in text.split_inclusive('\n') {
        let clean = line.split('#').next().unwrap_or("").trim();
        if clean == "listener {" {
            if start.is_some() {
                return Err("Nested listeners".into());
            }
            start = Some(offset);
        } else if clean == "}" {
            if let Some(s) = start.take() {
                result.push((s, offset + line.len(), &text[s..offset + line.len()]));
            }
        }
        offset += line.len();
    }
    if start.is_some() {
        return Err("Unclosed listener".into());
    }
    Ok(result)
}
fn target(block: &str) -> Option<&'static str> {
    if block
        .lines()
        .filter(|l| l.trim().starts_with("on-timeout"))
        .count()
        != 1
    {
        return None;
    }
    let action = block
        .lines()
        .find_map(|l| l.trim().strip_prefix("on-timeout ="))?
        .trim();
    if action == "$suspend_cmd" || action == "systemctl suspend" || action == "loginctl suspend" {
        Some("sleep")
    } else if action == LOCK {
        Some("lock")
    } else if action == r#"hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'"# {
        Some("screen")
    } else {
        None
    }
}
fn expanded(text: &str) -> String {
    text.split_inclusive('\n')
        .map(|l| l.strip_prefix("# remya-disabled: ").unwrap_or(l))
        .collect()
}
pub fn read(text: &str) -> Result<Timeouts, String> {
    // A turned-off lock before sleep stays as a `remya-disabled` comment.
    let lock_before_sleep = text.lines().any(|l| l.trim() == BEFORE_SLEEP);
    let expanded = expanded(text);
    let text = expanded.as_str();
    let mut screen = None;
    let mut sleep = None;
    let mut lock = None;
    if text.lines().any(|l| l.trim().starts_with("source")) {
        return Err("Included hypridle configurations cannot be edited safely".into());
    }
    if text.contains("on-timeout = $suspend_cmd") {
        let definitions = text
            .lines()
            .filter_map(|l| l.trim().strip_prefix("$suspend_cmd ="))
            .map(str::trim)
            .collect::<Vec<_>>();
        if definitions.len() != 1
            || ![
                "systemctl suspend",
                "loginctl suspend",
                "systemctl suspend || loginctl suspend",
            ]
            .contains(&definitions[0])
        {
            return Err("Cannot prove suspend command safe".into());
        }
    }
    for (_, _, block) in listeners(text)? {
        if let Some(kind) = target(block) {
            let slot = match kind {
                "screen" => &mut screen,
                "lock" => &mut lock,
                _ => &mut sleep,
            };
            if slot.is_some() {
                return Err(format!("Ambiguous {kind} listeners"));
            }
            let values = block
                .lines()
                .filter_map(|l| l.trim().strip_prefix("timeout ="))
                .collect::<Vec<_>>();
            if values.len() != 1 {
                return Err("Expected one timeout".into());
            }
            *slot = Some(
                values[0]
                    .split('#')
                    .next()
                    .unwrap()
                    .trim()
                    .parse::<u32>()
                    .map_err(|e| e.to_string())?,
            );
        }
    }
    Ok(Timeouts {
        screen: screen.ok_or("No screen listener")?,
        sleep: sleep.ok_or("No sleep listener")?,
        lock: lock.unwrap_or(0),
        lock_before_sleep,
    })
}
pub fn edit(text: &str, wanted: &Timeouts) -> Result<String, String> {
    let current = read(text)?;
    let expanded = expanded(text);
    let text = expanded.as_str();
    let mut out = text.to_owned();
    let has_lock = listeners(text)?
        .iter()
        .any(|(_, _, block)| target(block) == Some("lock"));
    for (start, end, block) in listeners(text)?.into_iter().rev() {
        if let Some(kind) = target(block) {
            let value = match kind {
                "screen" => wanted.screen,
                "lock" => wanted.lock,
                _ => wanted.sleep,
            };
            let mut changed = String::new();
            for line in block.split_inclusive('\n') {
                if line.trim().starts_with("timeout =") {
                    let indent = &line[..line.len() - line.trim_start().len()];
                    let comment = line
                        .find('#')
                        .map(|i| format!(" {}", line[i..].trim_end()))
                        .unwrap_or_default();
                    changed.push_str(&format!("{indent}timeout = {value}{comment}\n"));
                } else {
                    changed.push_str(line)
                }
            }
            if value == 0 {
                changed = changed
                    .split_inclusive('\n')
                    .map(|l| format!("# remya-disabled: {l}"))
                    .collect();
            }
            out.replace_range(start..end, &changed);
        }
    }
    if !has_lock && wanted.lock > 0 {
        let separator = if out.is_empty() || out.ends_with('\n') {
            ""
        } else {
            "\n"
        };
        out += &format!(
            "{separator}\nlistener {{\n    timeout = {}\n    on-timeout = {LOCK}\n}}\n",
            wanted.lock
        );
    }
    edit_before_sleep(out, current.lock_before_sleep, wanted.lock_before_sleep)
}

/// Turns the locking `before_sleep_cmd` on or off; other commands are never replaced.
fn edit_before_sleep(text: String, current: bool, wanted: bool) -> Result<String, String> {
    let ours = |l: &str| l.trim() == BEFORE_SLEEP;
    let present = text.lines().any(ours);
    if wanted == current && (wanted || !present) {
        return Ok(text);
    }
    if present {
        return Ok(text
            .split_inclusive('\n')
            .map(|l| {
                if ours(l) && !wanted {
                    format!("# remya-disabled: {l}")
                } else {
                    l.to_owned()
                }
            })
            .collect());
    }
    if text
        .lines()
        .any(|l| l.trim().starts_with("before_sleep_cmd"))
    {
        return Err("before_sleep_cmd already runs another command".into());
    }
    Ok(match general(&text)? {
        Some((start, _)) => {
            let open = start
                + text[start..]
                    .find('\n')
                    .map_or(text.len() - start, |i| i + 1);
            format!("{}    {BEFORE_SLEEP}\n{}", &text[..open], &text[open..])
        }
        None => format!("general {{\n    {BEFORE_SLEEP}\n}}\n\n{text}"),
    })
}
pub fn apply(path: &Path, wanted: &Timeouts) -> Result<(), String> {
    let original = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let updated = edit(&original, wanted)?;
    // Disabled listeners remain commented out so their original commands can be restored.
    atomic_write(path, updated.as_bytes())?;
    if let Err(error) = restart(path) {
        atomic_write(path, original.as_bytes())?;
        let recovery = restart(path);
        return Err(format!("{error}; restored configuration: {recovery:?}"));
    }
    if read(&std::fs::read_to_string(path).map_err(|e| e.to_string())?)? != *wanted {
        return Err("Timeout readback mismatch".into());
    }
    Ok(())
}
fn running() -> Result<Vec<String>, String> {
    use std::os::unix::fs::MetadataExt;

    let uid = std::fs::metadata("/proc/self")
        .map_err(|e| e.to_string())?
        .uid();
    Ok(std::fs::read_dir("/proc")
        .map_err(|e| e.to_string())?
        .flatten()
        .filter(|entry| {
            entry.metadata().is_ok_and(|m| m.uid() == uid)
                && std::fs::read_link(entry.path().join("exe"))
                    .is_ok_and(|path| path.file_name().is_some_and(|name| name == "hypridle"))
        })
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect())
}

fn systemd_job(method: &str, previous_pid: Option<&str>) -> Result<(), String> {
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)
        .map_err(|error| error.to_string())?;
    bus.call_sync(
        Some("org.freedesktop.systemd1"),
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        method,
        Some(&("hypridle.service", "replace").to_variant()),
        None,
        gio::DBusCallFlags::NO_AUTO_START,
        2000,
        gio::Cancellable::NONE,
    )
    .map_err(|error| format!("Cannot start the hypridle user service: {error}"))?;

    let mut seen = None;
    for _ in 0..20 {
        std::thread::sleep(Duration::from_millis(100));
        match running()?.as_slice() {
            [pid] if Some(pid.as_str()) != previous_pid => {
                if seen.as_ref() == Some(pid) {
                    return Ok(());
                }
                seen = Some(pid.clone());
            }
            [] | [_] => seen = None,
            _ => return Err("Multiple hypridle instances are running".into()),
        }
    }
    Err("The hypridle user service did not stay running".into())
}

pub fn ensure_running(path: &Path) -> Result<(), String> {
    if ["WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]
        .iter()
        .any(|name| std::env::var_os(name).is_none_or(|value| value.is_empty()))
    {
        return Err("Unavailable:hypridle requires a Hyprland session".into());
    }
    if super::keep_awake::owner().is_ok_and(|owner| owner.is_some()) {
        return Ok(());
    }
    match running()?.as_slice() {
        [_] => return Ok(()),
        [] => {}
        _ => return Err("Multiple hypridle instances are running".into()),
    }
    if !path.is_file() {
        return Err("Unavailable:No hypridle configuration found".into());
    }
    systemd_job("StartUnit", None)
}

fn restart(path: &Path) -> Result<(), String> {
    let pids = running()?;
    if pids.len() > 1 {
        return Err("Multiple hypridle instances; refusing to restart".into());
    }
    if let Some(pid) = pids.first() {
        let args = std::fs::read(format!("/proc/{pid}/cmdline")).map_err(|e| e.to_string())?;
        let args = args
            .split(|b| *b == 0)
            .filter_map(|b| std::str::from_utf8(b).ok())
            .collect::<Vec<_>>();
        let config = if let Some(i) = args.iter().position(|a| *a == "--config" || *a == "-c") {
            args.get(i + 1).map(PathBuf::from)
        } else {
            use std::os::unix::ffi::OsStrExt;
            let environment =
                std::fs::read(format!("/proc/{pid}/environ")).map_err(|e| e.to_string())?;
            let absolute = |key: &[u8]| {
                environment
                    .split(|byte| *byte == 0)
                    .find_map(|entry| entry.strip_prefix(key))
                    .map(|value| Path::new(std::ffi::OsStr::from_bytes(value)))
                    .filter(|path| path.is_absolute())
            };
            absolute(b"XDG_CONFIG_HOME=")
                .map(Path::to_path_buf)
                .or_else(|| absolute(b"HOME=").map(|home| home.join(".config")))
                .map(|root| root.join("hypr/hypridle.conf"))
        };
        if config.as_deref() != Some(path) {
            return Err("hypridle uses a different configuration".into());
        }
        let cgroup =
            std::fs::read_to_string(format!("/proc/{pid}/cgroup")).map_err(|e| e.to_string())?;
        if cgroup
            .lines()
            .any(|line| line.ends_with("/hypridle.service"))
        {
            return systemd_job("RestartUnit", Some(pid));
        }
    }
    if let Some(pid) = pids.first() {
        run_bytes("kill", &["-TERM", pid], &[], Duration::from_secs(2))?;
        for _ in 0..40 {
            if !Path::new(&format!("/proc/{pid}/exe")).exists() {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        if Path::new(&format!("/proc/{pid}/exe")).exists() {
            return Err("hypridle did not stop".into());
        }
    }
    let mut child = Command::new("hypridle")
        .arg("--config")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    std::thread::sleep(Duration::from_millis(300));
    if child.try_wait().map_err(|e| e.to_string())?.is_some() {
        return Err("hypridle failed to start".into());
    }
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserve_commands() {
        let s = "listener {\n timeout = 600 # screen\n on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'\n on-resume = custom-restore\n}\nlistener {\n timeout = 1200\n on-timeout = systemctl suspend\n}\n";
        let t = Timeouts {
            screen: 300,
            sleep: 900,
            ..Default::default()
        };
        let changed = edit(s, &t).unwrap();
        assert_eq!(read(&changed).unwrap(), t);
        assert!(changed.contains("on-resume = custom-restore"));
        assert!(read(&format!("{s}{s}")).is_err());
    }
}

#[cfg(test)]
mod regression_tests {
    use super::*;
    #[test]
    fn never_and_restore() {
        let original = "listener {\n timeout = 600\n on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'\n on-resume = restore-script\n}\nlistener {\n timeout = 1200\n on-timeout = systemctl suspend\n}\n";
        let off = edit(original, &Timeouts::default()).unwrap();
        assert!(!off.lines().any(|l| l.trim() == "listener {"));
        assert_eq!(read(&off).unwrap(), Timeouts::default());
        assert_eq!(
            edit(
                &off,
                &Timeouts {
                    screen: 600,
                    sleep: 1200,
                    ..Default::default()
                }
            )
            .unwrap(),
            original
        );
        assert!(read(&format!("source = another.conf\n{original}")).is_err());
    }
}

#[cfg(test)]
mod lock_tests {
    use super::*;
    const BASE: &str = "general {\n    lock_cmd = hyprlock\n}\n\nlistener {\n timeout = 600\n on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'\n}\nlistener {\n timeout = 1200\n on-timeout = systemctl suspend\n}\n";

    #[test]
    fn lock_listener_and_before_sleep_round_trip() {
        assert!(can_lock(BASE));
        assert!(!can_lock("listener {\n}\n"));
        let mut wanted = read(BASE).unwrap();
        assert_eq!((wanted.lock, wanted.lock_before_sleep), (0, false));
        wanted.lock = 300;
        wanted.lock_before_sleep = true;
        let on = edit(BASE, &wanted).unwrap();
        assert_eq!(read(&on).unwrap(), wanted);
        assert!(
            on.starts_with("general {\n    before_sleep_cmd = loginctl lock-session\n    lock_cmd")
        );
        // Turning both off keeps them as comments; turning them on again restores them.
        let off_wanted = Timeouts {
            lock: 0,
            lock_before_sleep: false,
            ..wanted.clone()
        };
        let off = edit(&on, &off_wanted).unwrap();
        assert_eq!(read(&off).unwrap(), off_wanted);
        assert!(off.contains("# remya-disabled: listener {"));
        let again = Timeouts {
            lock: 900,
            ..wanted.clone()
        };
        assert_eq!(read(&edit(&off, &again).unwrap()).unwrap(), again);
    }

    #[test]
    fn custom_before_sleep_and_missing_general() {
        let custom = BASE.replace(
            "lock_cmd = hyprlock",
            "lock_cmd = hyprlock\n    before_sleep_cmd = my-script",
        );
        let mut wanted = read(&custom).unwrap();
        assert!(!wanted.lock_before_sleep);
        assert_eq!(edit(&custom, &wanted).unwrap(), custom);
        wanted.lock_before_sleep = true;
        assert!(edit(&custom, &wanted).is_err());
        let bare = BASE.replace("general {\n    lock_cmd = hyprlock\n}\n\n", "");
        let mut wanted = read(&bare).unwrap();
        wanted.lock_before_sleep = true;
        let added = edit(&bare, &wanted).unwrap();
        assert!(added.starts_with("general {\n    before_sleep_cmd"));
        assert_eq!(read(&added).unwrap(), wanted);
    }
}
