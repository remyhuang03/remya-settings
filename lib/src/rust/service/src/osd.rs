//! On-screen display (OSD) preferences for Remy'a Bar.
//! They have no system counterpart; the bar applies them live.
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

pub const VOLUME_STEP: &str = "remya-bar.volume-step";
pub const VOLUME_MAX: &str = "remya-bar.volume-max";
pub const BRIGHTNESS_STEP: &str = "remya-bar.brightness-step";
pub const GAMMA_MIN: &str = "remya-bar.gamma-min";
/// Reads every OSD preference at once.
pub const ALL: &str = "remya-bar.osd";

/// Writable IDs; each write emits `Changed` with its ID.
pub const IDS: &[&str] = &[VOLUME_STEP, VOLUME_MAX, BRIGHTNESS_STEP, GAMMA_MIN];

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
struct Preferences {
    volume_step: u8,
    volume_max: u8,
    brightness_step: u8,
    gamma_min: u8,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            volume_step: 5,
            volume_max: 150,
            brightness_step: 5,
            gamma_min: 10,
        }
    }
}

impl Preferences {
    fn valid(&self) -> bool {
        (1..=25).contains(&self.volume_step)
            && (100..=150).contains(&self.volume_max)
            && (1..=25).contains(&self.brightness_step)
            && (10..=90).contains(&self.gamma_min)
    }
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

fn path(config: &Path) -> PathBuf {
    config.with_file_name("remya-bar-osd.toml")
}

fn load(config: &Path) -> Result<Preferences, String> {
    let error = "Invalid Remy'a Bar OSD configuration";
    match std::fs::read_to_string(path(config)) {
        Ok(text) => toml::from_str::<Preferences>(&text)
            .ok()
            .filter(Preferences::valid)
            .ok_or_else(|| error.to_owned()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Preferences::default()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn is_setting(id: &str) -> bool {
    id == ALL || IDS.contains(&id)
}

pub fn get(config: &Path, id: &str) -> Result<Value, String> {
    let preferences = load(config)?;
    let all = serde_json::to_value(&preferences).map_err(|e| e.to_string())?;
    let value = match id {
        ALL => all,
        VOLUME_STEP => all["volume_step"].clone(),
        VOLUME_MAX => all["volume_max"].clone(),
        BRIGHTNESS_STEP => all["brightness_step"].clone(),
        GAMMA_MIN => all["gamma_min"].clone(),
        _ => return Err(invalid("Unknown setting")),
    };
    Ok(json!({"id":id,"availability":"available","value":value}))
}

/// Validates one change and atomically saves all preferences. A malformed
/// file is reported and left for the user to repair.
pub fn set(config: &Path, id: &str, value: &str) -> Result<Value, String> {
    let mut preferences = load(config)?;
    let percent = |min: u8, max: u8| {
        value
            .parse::<u8>()
            .ok()
            .filter(|v| (min..=max).contains(v))
            .ok_or_else(|| invalid(&format!("Use whole percent from {min} to {max}")))
    };
    match id {
        VOLUME_STEP => preferences.volume_step = percent(1, 25)?,
        VOLUME_MAX => preferences.volume_max = percent(100, 150)?,
        BRIGHTNESS_STEP => preferences.brightness_step = percent(1, 25)?,
        GAMMA_MIN => preferences.gamma_min = percent(10, 90)?,
        _ => return Err(invalid("Unknown setting")),
    }
    let text = toml::to_string(&preferences).map_err(|e| e.to_string())?;
    atomic_write(&path(config), text.as_bytes())?;
    get(config, id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_validation_persistence_and_malformed_files() {
        let root = tempfile::tempdir().unwrap();
        let config = root.path().join("config.toml");
        let value = |id| get(&config, id).unwrap()["value"].clone();
        assert_eq!(value(VOLUME_STEP), json!(5));
        assert_eq!(value(VOLUME_MAX), json!(150));
        assert_eq!(value(BRIGHTNESS_STEP), json!(5));
        assert_eq!(value(GAMMA_MIN), json!(10));
        for (id, request) in [
            (VOLUME_STEP, "2"),
            (VOLUME_MAX, "120"),
            (BRIGHTNESS_STEP, "10"),
            (GAMMA_MIN, "20"),
        ] {
            set(&config, id, request).unwrap();
        }
        assert_eq!(
            value(ALL),
            json!({"volume_step": 2, "volume_max": 120, "brightness_step": 10, "gamma_min": 20})
        );
        for (id, request) in [
            (VOLUME_STEP, "0"),
            (VOLUME_STEP, "26"),
            (VOLUME_STEP, "five"),
            (VOLUME_MAX, "99"),
            (VOLUME_MAX, "151"),
            (BRIGHTNESS_STEP, "0"),
            (BRIGHTNESS_STEP, "30"),
            (GAMMA_MIN, "9"),
            (GAMMA_MIN, "91"),
            ("remya-bar.unknown", "5"),
        ] {
            assert!(
                set(&config, id, request)
                    .unwrap_err()
                    .starts_with("InvalidArgument:"),
                "{id}"
            );
        }
        assert_eq!(value(VOLUME_STEP), json!(2));
        // Files written before volume_max existed keep loading.
        std::fs::write(path(&config), "volume_step = 3\n").unwrap();
        assert_eq!(value(VOLUME_MAX), json!(150));
        std::fs::write(path(&config), "volume_step = 0\n").unwrap();
        assert!(get(&config, VOLUME_STEP).is_err());
        assert!(set(&config, VOLUME_STEP, "5").is_err());
        assert_eq!(
            std::fs::read_to_string(path(&config)).unwrap(),
            "volume_step = 0\n"
        );
    }
}
