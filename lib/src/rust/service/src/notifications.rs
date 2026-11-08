//! Notification preferences for the desktop notification service (Remy'a Bar).
//! They have no system counterpart; the bar applies them live.
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

pub const DND: &str = "notifications.do-not-disturb";
pub const DURATION: &str = "notifications.popup-duration";
pub const SOUNDS: &str = "notifications.sounds";
pub const SCHEDULE: &str = "quiet-schedule.enabled";
pub const START: &str = "quiet-schedule.start";
pub const END: &str = "quiet-schedule.end";
pub const REPEAT: &str = "quiet-schedule.repeat";
pub const FULLSCREEN: &str = "quiet-schedule.fullscreen";
pub const CALLS: &str = "priority-notifications.calls";
pub const APPS: &str = "priority-notifications.apps";
/// Reads every preference at once.
pub const ALL: &str = "notifications";

/// Writable IDs; each write emits `Changed` with its ID.
pub const IDS: &[&str] = &[
    DND, DURATION, SOUNDS, SCHEDULE, START, END, REPEAT, FULLSCREEN, CALLS, APPS,
];
const REPEATS: &[&str] = &["every-day", "weekdays", "weekends"];

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
struct PriorityApp {
    id: String,
    name: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
struct Preferences {
    do_not_disturb: bool,
    popup_duration: u8,
    sounds: bool,
    schedule: bool,
    schedule_start: String,
    schedule_end: String,
    schedule_repeat: String,
    fullscreen: bool,
    priority_calls: bool,
    priority_apps: Vec<PriorityApp>,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            do_not_disturb: false,
            popup_duration: 5,
            sounds: true,
            schedule: false,
            schedule_start: "22:00".into(),
            schedule_end: "07:00".into(),
            schedule_repeat: "every-day".into(),
            fullscreen: false,
            priority_calls: true,
            priority_apps: Vec::new(),
        }
    }
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

fn valid_time(value: &str) -> bool {
    let Some((hours, minutes)) = value.split_once(':') else {
        return false;
    };
    hours.len() == 2
        && minutes.len() == 2
        && hours.parse::<u8>().is_ok_and(|hours| hours < 24)
        && minutes.parse::<u8>().is_ok_and(|minutes| minutes < 60)
}

fn valid_app(app: &PriorityApp) -> bool {
    let text = |value: &str| {
        !value.trim().is_empty() && value.len() <= 256 && !value.chars().any(char::is_control)
    };
    text(&app.id) && text(&app.name)
}

impl Preferences {
    fn valid(&self) -> bool {
        (1..=60).contains(&self.popup_duration)
            && valid_time(&self.schedule_start)
            && valid_time(&self.schedule_end)
            && REPEATS.contains(&self.schedule_repeat.as_str())
            && self.priority_apps.iter().all(valid_app)
    }
}

fn path(config: &Path) -> PathBuf {
    config.with_file_name("notifications.toml")
}

fn load(config: &Path) -> Result<Preferences, String> {
    let error = "Invalid notification configuration";
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
        DND => all["do_not_disturb"].clone(),
        DURATION => all["popup_duration"].clone(),
        SOUNDS => all["sounds"].clone(),
        SCHEDULE => all["schedule"].clone(),
        START => all["schedule_start"].clone(),
        END => all["schedule_end"].clone(),
        REPEAT => all["schedule_repeat"].clone(),
        FULLSCREEN => all["fullscreen"].clone(),
        CALLS => all["priority_calls"].clone(),
        APPS => all["priority_apps"].clone(),
        _ => return Err(invalid("Unknown setting")),
    };
    Ok(json!({"id":id,"availability":"available","value":value}))
}

/// Validates one change and atomically saves all preferences. A malformed
/// file is reported and left for the user to repair.
pub fn set(config: &Path, id: &str, value: &str) -> Result<Value, String> {
    let mut preferences = load(config)?;
    let boolean = || {
        value
            .parse::<bool>()
            .map_err(|_| invalid("Use true or false"))
    };
    let one_of = |choices: &[&str]| {
        choices
            .contains(&value)
            .then(|| value.to_owned())
            .ok_or_else(|| invalid(&format!("Use one of {}", choices.join(", "))))
    };
    let time = || {
        valid_time(value)
            .then(|| value.to_owned())
            .ok_or_else(|| invalid("Use 24-hour HH:MM"))
    };
    match id {
        DND => preferences.do_not_disturb = boolean()?,
        SOUNDS => preferences.sounds = boolean()?,
        SCHEDULE => preferences.schedule = boolean()?,
        FULLSCREEN => preferences.fullscreen = boolean()?,
        CALLS => preferences.priority_calls = boolean()?,
        DURATION => {
            preferences.popup_duration = value
                .parse::<u8>()
                .ok()
                .filter(|seconds| (1..=60).contains(seconds))
                .ok_or_else(|| invalid("Use whole seconds from 1 to 60"))?
        }
        REPEAT => preferences.schedule_repeat = one_of(REPEATS)?,
        START => preferences.schedule_start = time()?,
        END => preferences.schedule_end = time()?,
        APPS => {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct Change {
                id: String,
                name: String,
                priority: bool,
            }
            let change: Change = serde_json::from_str(value)
                .map_err(|_| invalid("Expected an app id, name and priority boolean"))?;
            let app = PriorityApp {
                id: change.id,
                name: change.name,
            };
            if !valid_app(&app) {
                return Err(invalid("Invalid app id or name"));
            }
            preferences.priority_apps.retain(|item| item.id != app.id);
            if change.priority {
                preferences.priority_apps.push(app);
            }
        }
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
        assert_eq!(value(DND), json!(false));
        assert_eq!(value(DURATION), json!(5));
        assert_eq!(value(SOUNDS), json!(true));
        assert_eq!(value(CALLS), json!(true));
        for (id, request) in [
            (DND, "true"),
            (DURATION, "10"),
            (SCHEDULE, "true"),
            (START, "23:30"),
            (END, "06:15"),
            (REPEAT, "weekdays"),
            (FULLSCREEN, "true"),
            (
                APPS,
                r#"{"id":"org.telegram.desktop","name":"Telegram","priority":true}"#,
            ),
        ] {
            set(&config, id, request).unwrap();
        }
        let all = value(ALL);
        assert_eq!(all["schedule_start"], "23:30");
        assert_eq!(all["priority_apps"][0]["name"], "Telegram");
        set(
            &config,
            APPS,
            r#"{"id":"org.telegram.desktop","name":"Telegram","priority":false}"#,
        )
        .unwrap();
        assert_eq!(value(APPS), json!([]));
        for (id, request) in [
            (DND, "yes"),
            (DURATION, "0"),
            (DURATION, "61"),
            (START, "24:00"),
            (END, "7:00"),
            (REPEAT, "monthly"),
            (APPS, r#"{"id":"","name":"x","priority":true}"#),
            ("notifications.unknown", "true"),
        ] {
            assert!(
                set(&config, id, request)
                    .unwrap_err()
                    .starts_with("InvalidArgument:"),
                "{id}"
            );
        }
        assert_eq!(value(DURATION), json!(10));
        std::fs::write(path(&config), "popup_duration = 0\n").unwrap();
        assert!(get(&config, DND).is_err());
        assert!(set(&config, DND, "false").is_err());
        assert_eq!(
            std::fs::read_to_string(path(&config)).unwrap(),
            "popup_duration = 0\n"
        );
    }
}
