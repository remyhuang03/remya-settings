//! Hardware brightness: kernel backlight through logind, external displays through
//! the optional `ddcutil` command. Values are live state and are never persisted.
use crate::hyprland::run;
use gio::glib::variant::ToVariant;
use serde::Serialize;
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

const DDC_TIMEOUT: Duration = Duration::from_secs(8);

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Brightness {
    pub output: String,
    pub percent: Option<u32>,
    pub backend: Option<&'static str>,
    pub reason: String,
}

#[derive(Clone, Debug, PartialEq)]
struct Backlight {
    name: String,
    connector: Option<String>,
}

fn strip_card(name: &str) -> Option<&str> {
    let rest = name.strip_prefix("card")?;
    let digits = rest.find(|c: char| !c.is_ascii_digit())?;
    (digits > 0).then(|| rest[digits..].trim_start_matches('-'))
}

fn backlights(root: &Path) -> Vec<Backlight> {
    let Ok(entries) = fs::read_dir(root) else {
        return vec![];
    };
    let mut list = entries
        .flatten()
        .map(|entry| Backlight {
            name: entry.file_name().to_string_lossy().into_owned(),
            connector: fs::canonicalize(entry.path().join("device"))
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
                .and_then(|n| strip_card(&n).map(str::to_owned)),
        })
        .collect::<Vec<_>>();
    list.sort_by(|a, b| a.name.cmp(&b.name));
    list
}

fn is_internal(output: &str) -> bool {
    ["eDP", "LVDS", "DSI"].iter().any(|p| output.starts_with(p))
}

/// Connector-linked devices win; a firmware device only serves a single internal panel.
fn backlight_for<'a>(
    list: &'a [Backlight],
    output: &str,
    outputs: &[String],
) -> Option<&'a Backlight> {
    list.iter()
        .find(|b| b.connector.as_deref() == Some(output))
        .or_else(|| {
            let internal = outputs.iter().filter(|o| is_internal(o)).count();
            (is_internal(output) && internal == 1)
                .then(|| list.iter().find(|b| b.connector.is_none()))
                .flatten()
        })
}

fn read_number(path: PathBuf) -> Result<u64, String> {
    fs::read_to_string(&path)
        .map_err(|e| format!("{}: {e}", path.display()))?
        .trim()
        .parse()
        .map_err(|_| format!("Invalid value in {}", path.display()))
}

fn read_backlight(root: &Path, name: &str) -> Result<(u64, u64), String> {
    let dir = root.join(name);
    let max = read_number(dir.join("max_brightness"))?;
    if max == 0 {
        return Err(format!("{name} reports no brightness range"));
    }
    Ok((read_number(dir.join("brightness"))?, max))
}

fn percent(value: u64, max: u64) -> u32 {
    ((value as f64 * 100.0 / max as f64).round() as u32).min(100)
}

/// Keeps the panel lit: 1% is the floor because 0 turns some backlights fully off.
fn raw_value(percent: u32, max: u64) -> u32 {
    ((percent.clamp(1, 100) as f64 * max as f64 / 100.0).round() as u32).max(1)
}

fn logind_set(name: &str, value: u32) -> Result<(), String> {
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    bus.call_sync(
        Some("org.freedesktop.login1"),
        "/org/freedesktop/login1/session/auto",
        "org.freedesktop.login1.Session",
        "SetBrightness",
        Some(&("backlight", name, value).to_variant()),
        None,
        gio::DBusCallFlags::NONE,
        5000,
        gio::Cancellable::NONE,
    )
    .map_err(|e| format!("logind SetBrightness: {e}"))?;
    Ok(())
}

/// Connector name to I2C bus, from `ddcutil detect --terse`. Invalid entries are skipped.
fn parse_detect(text: &str) -> BTreeMap<String, String> {
    let mut found = BTreeMap::new();
    for block in text.split("\n\n") {
        if !block.trim_start().starts_with("Display ") {
            continue;
        }
        let value = |key: &str| {
            block
                .lines()
                .find_map(|line| line.trim().strip_prefix(key).map(|v| v.trim().to_owned()))
        };
        let bus = value("I2C bus:").and_then(|b| b.rsplit('-').next().map(str::to_owned));
        let connector = value("DRM connector:")
            .or_else(|| value("DRM_connector:"))
            .and_then(|c| strip_card(&c).map(str::to_owned));
        if let (Some(bus), Some(connector)) = (bus, connector) {
            found.insert(connector, bus);
        }
    }
    found
}

/// Reads `VCP 10 C <current> <max>`.
fn parse_vcp(text: &str) -> Option<(u64, u64)> {
    let line = text.lines().find(|l| l.starts_with("VCP 10 "))?;
    let parts = line.split_whitespace().collect::<Vec<_>>();
    match parts.as_slice() {
        ["VCP", "10", "C", current, max] => {
            let max = max.parse().ok().filter(|m| *m > 0)?;
            Some((current.parse().ok()?, max))
        }
        _ => None,
    }
}

fn ddc_read(bus: &str) -> Result<(u64, u64), String> {
    let text = run(
        "ddcutil",
        &["getvcp", "10", "--brief", "--bus", bus],
        DDC_TIMEOUT,
    )?;
    parse_vcp(&text).ok_or_else(|| "This display does not report DDC/CI brightness".to_owned())
}

/// Detection is slow and touches the I2C buses, so results are kept until the set
/// of connected outputs changes or the user asks to detect displays again.
#[derive(Default)]
pub struct BrightnessBackend {
    ddc: Option<Result<BTreeMap<String, String>, String>>,
}

impl BrightnessBackend {
    pub fn forget_detection(&mut self) {
        self.ddc = None;
    }

    fn ddc_buses(&mut self) -> Result<&BTreeMap<String, String>, String> {
        let result = self.ddc.get_or_insert_with(|| {
            run("ddcutil", &["detect", "--terse"], DDC_TIMEOUT).map(|text| parse_detect(&text))
        });
        match result {
            Ok(map) => Ok(map),
            Err(error) if error.contains("No such file") => {
                Err("Install ddcutil to control external display brightness".into())
            }
            Err(error) => Err(error.clone()),
        }
    }

    pub fn read(&mut self, output: &str, outputs: &[String]) -> Brightness {
        self.read_from(Path::new("/sys/class/backlight"), output, outputs)
    }

    pub(crate) fn read_backlight(output: &str, outputs: &[String]) -> Option<Brightness> {
        Self::read_backlight_from(Path::new("/sys/class/backlight"), output, outputs)
    }

    fn read_backlight_from(root: &Path, output: &str, outputs: &[String]) -> Option<Brightness> {
        let list = backlights(root);
        let device = backlight_for(&list, output, outputs)?;
        let (percent, reason) = match read_backlight(root, &device.name) {
            Ok((value, max)) => (Some(percent(value, max)), String::new()),
            Err(error) => (None, error),
        };
        Some(Brightness {
            output: output.to_owned(),
            percent,
            backend: Some("backlight"),
            reason,
        })
    }

    fn read_from(&mut self, root: &Path, output: &str, outputs: &[String]) -> Brightness {
        let result = |percent, backend, reason: String| Brightness {
            output: output.to_owned(),
            percent,
            backend,
            reason,
        };
        if let Some(backlight) = Self::read_backlight_from(root, output, outputs) {
            return backlight;
        }
        if is_internal(output) {
            return result(
                None,
                None,
                "This panel has no kernel backlight device".into(),
            );
        }
        let bus = match self.ddc_buses() {
            Ok(map) => map.get(output).cloned(),
            Err(error) => return result(None, None, error),
        };
        let Some(bus) = bus else {
            return result(None, None, "This display does not support DDC/CI".into());
        };
        match ddc_read(&bus) {
            Ok((value, max)) => result(Some(percent(value, max)), Some("ddc"), String::new()),
            Err(error) => result(None, None, error),
        }
    }

    pub fn set(&mut self, output: &str, outputs: &[String], wanted: u32) -> Result<u32, String> {
        let root = Path::new("/sys/class/backlight");
        let list = backlights(root);
        if let Some(device) = backlight_for(&list, output, outputs) {
            let (_, max) = read_backlight(root, &device.name)?;
            let raw = raw_value(wanted, max);
            logind_set(&device.name, raw)?;
            for _ in 0..20 {
                let (value, _) = read_backlight(root, &device.name)?;
                if value.abs_diff(raw as u64) <= max / 100 + 1 {
                    return Ok(percent(value, max));
                }
                thread::sleep(Duration::from_millis(50));
            }
            return Err("Backlight readback does not match the request".into());
        }
        if is_internal(output) {
            return Err("This panel has no kernel backlight device".into());
        }
        let bus = self
            .ddc_buses()?
            .get(output)
            .cloned()
            .ok_or("This display does not support DDC/CI")?;
        let (_, max) = ddc_read(&bus)?;
        let raw = (wanted.min(100) as u64 * max / 100).to_string();
        run(
            "ddcutil",
            &["setvcp", "10", &raw, "--bus", &bus],
            DDC_TIMEOUT,
        )?;
        let (value, max) = ddc_read(&bus)?;
        if value.to_string() != raw {
            return Err("DDC/CI readback does not match the request".into());
        }
        Ok(percent(value, max))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_output_maps_connectors_and_skips_invalid_displays() {
        let text = "Invalid display\n   I2C bus:          /dev/i2c-12\n   DRM connector:    card0-eDP-1\n\nDisplay 1\n   I2C bus:          /dev/i2c-13\n   DRM connector:    card0-DP-1\n   Monitor:          YCT:Sculptor:\n\nDisplay 2\n   I2C bus:          /dev/i2c-15\n   DRM_connector:    card1-HDMI-A-1\n";
        let map = parse_detect(text);
        assert_eq!(map.len(), 2);
        assert_eq!(map["DP-1"], "13");
        assert_eq!(map["HDMI-A-1"], "15");
    }

    #[test]
    fn vcp_output_is_parsed_strictly() {
        assert_eq!(parse_vcp("VCP 10 C 50 100\n"), Some((50, 100)));
        assert_eq!(parse_vcp("VCP 10 ERR\n"), None);
        assert_eq!(parse_vcp("VCP 10 C 5 0"), None);
    }

    #[test]
    fn percentages_keep_the_panel_lit() {
        assert_eq!(raw_value(0, 19200), 192);
        assert_eq!(raw_value(100, 19200), 19200);
        assert_eq!(raw_value(1, 10), 1);
        assert_eq!(percent(7680, 19200), 40);
    }

    #[test]
    fn backlights_resolve_through_sysfs_links() {
        let root = tempfile::tempdir().unwrap();
        let drm = root.path().join("drm/card0-eDP-1");
        let class = root.path().join("class");
        fs::create_dir_all(&drm).unwrap();
        for (name, link) in [("intel", Some(&drm)), ("acpi", None)] {
            let dir = class.join(name);
            fs::create_dir_all(&dir).unwrap();
            fs::write(dir.join("max_brightness"), "200\n").unwrap();
            fs::write(dir.join("brightness"), "50\n").unwrap();
            if let Some(link) = link {
                std::os::unix::fs::symlink(link, dir.join("device")).unwrap();
            }
        }
        let outputs = vec!["eDP-1".to_owned(), "eDP-2".to_owned()];
        let list = backlights(&class);
        assert_eq!(
            backlight_for(&list, "eDP-1", &outputs).unwrap().name,
            "intel"
        );
        // Two internal panels: a firmware device cannot be attributed to either.
        assert!(backlight_for(&list, "eDP-2", &outputs).is_none());
        let one = vec!["LVDS-1".to_owned()];
        assert_eq!(backlight_for(&list, "LVDS-1", &one).unwrap().name, "acpi");
        let mut backend = BrightnessBackend::default();
        let read = backend.read_from(&class, "eDP-1", &outputs);
        assert_eq!(read.percent, Some(25));
        assert_eq!(read.backend, Some("backlight"));
        let missing = backend.read_from(&class, "eDP-2", &outputs);
        assert_eq!(missing.percent, None);
        assert!(missing.reason.contains("no kernel backlight"));
    }
}
