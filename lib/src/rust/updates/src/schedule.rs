use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
};

type Write = fn(&Path, &[u8]) -> Result<(), String>;
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Configuration {
    version: u32,
    enabled: bool,
    time: String,
    last_run_day: Option<String>,
    notice: Option<String>,
}
impl Default for Configuration {
    fn default() -> Self {
        Self {
            version: 1,
            enabled: false,
            time: "03:00".into(),
            last_run_day: None,
            notice: None,
        }
    }
}
#[derive(Clone, Debug)]
pub(crate) struct LocalTime {
    pub day: String,
    pub minute: u32,
}
impl LocalTime {
    pub fn now() -> Option<Self> {
        Self::at(unsafe { libc::time(std::ptr::null_mut()) })
    }
    fn at(seconds: libc::time_t) -> Option<Self> {
        unsafe extern "C" {
            fn tzset();
        }
        unsafe {
            tzset();
        }
        let mut local = std::mem::MaybeUninit::<libc::tm>::uninit();
        if unsafe { libc::localtime_r(&seconds, local.as_mut_ptr()) }.is_null() {
            return None;
        }
        let local = unsafe { local.assume_init() };
        Some(Self {
            day: format!(
                "{:04}-{:02}-{:02}",
                local.tm_year + 1900,
                local.tm_mon + 1,
                local.tm_mday
            ),
            minute: (local.tm_hour * 60 + local.tm_min) as u32,
        })
    }
}
pub(crate) struct Schedule {
    path: Option<PathBuf>,
    write: Write,
    configuration: Configuration,
    pub error: Option<String>,
    blocked: bool,
}
pub(crate) enum Due {
    None,
    Changed,
    Run,
}
fn minute(value: &str) -> Result<u32, String> {
    let bytes = value.as_bytes();
    if bytes.len() != 5
        || bytes[2] != b':'
        || ![bytes[0], bytes[1], bytes[3], bytes[4]]
            .iter()
            .all(u8::is_ascii_digit)
    {
        return Err("InvalidArgument:Use local time HH:mm".into());
    }
    let hour = value[..2].parse::<u32>().unwrap();
    let minute = value[3..].parse::<u32>().unwrap();
    if hour > 23 || minute > 59 {
        return Err("InvalidArgument:Time must be between 00:00 and 23:59".into());
    }
    Ok(hour * 60 + minute)
}
impl Schedule {
    pub fn load(path: PathBuf, write: Write) -> Self {
        let mut schedule = Self {
            path: Some(path.clone()),
            write,
            configuration: Configuration::default(),
            error: None,
            blocked: false,
        };
        let result = match fs::read(&path) {
            Ok(bytes) => serde_json::from_slice::<Configuration>(&bytes)
                .map(Some)
                .map_err(|e| e.to_string()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error.to_string()),
        };
        match result {
            Ok(Some(configuration))
                if configuration.version == 1
                    && minute(&configuration.time).is_ok()
                    && configuration.last_run_day.as_ref().is_none_or(|day| {
                        day.len() == 10
                            && day.bytes().enumerate().all(|(i, b)| {
                                if i == 4 || i == 7 {
                                    b == b'-'
                                } else {
                                    b.is_ascii_digit()
                                }
                            })
                    }) =>
            {
                schedule.configuration = configuration
            }
            Ok(None) => {}
            Ok(_) => {
                schedule.error = Some(
                    "Invalid automatic update configuration; automatic updates are disabled".into(),
                )
            }
            Err(error) => {
                schedule.error = Some(format!(
                    "Cannot load automatic update configuration: {error}"
                ))
            }
        }
        schedule.blocked = schedule.error.is_some();
        schedule
    }
    #[cfg(test)]
    pub fn memory() -> Self {
        Self {
            path: None,
            write: |_, _| Ok(()),
            configuration: Configuration::default(),
            error: None,
            blocked: false,
        }
    }
    pub fn state(&self) -> Value {
        json!({"enabled":self.configuration.enabled,"time":self.configuration.time,"last_run_day":self.configuration.last_run_day,"notice":self.configuration.notice,"error":self.error,"editable":!self.blocked})
    }
    fn persist(&mut self, next: Configuration) -> Result<(), String> {
        if let Some(path) = &self.path {
            let bytes = serde_json::to_vec_pretty(&next).map_err(|e| e.to_string())?;
            (self.write)(path, &bytes)?;
        }
        self.configuration = next;
        Ok(())
    }
    pub fn set(&mut self, id: &str, value: &str) -> Result<(), String> {
        if self.blocked {
            return Err(self
                .error
                .clone()
                .unwrap_or("Invalid schedule configuration".into()));
        }
        let mut next = self.configuration.clone();
        match id {
            super::AUTOMATIC => {
                next.enabled = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err("InvalidArgument:Use true or false".into()),
                }
            }
            super::TIME => {
                minute(value)?;
                next.time = value.into();
            }
            _ => return Err("InvalidArgument:Unknown schedule setting".into()),
        }
        next.notice = None;
        match self.persist(next) {
            Ok(()) => {
                self.error = None;
                Ok(())
            }
            Err(error) => {
                let message = format!(
                    "Cannot save automatic update settings; automatic updates are paused until a setting is saved successfully: {error}"
                );
                self.error = Some(message.clone());
                Err(message)
            }
        }
    }
    pub fn due(&mut self, local: &LocalTime, busy: bool, authorized: bool) -> Due {
        if self.error.is_some()
            || !self.configuration.enabled
            || minute(&self.configuration.time)
                .ok()
                .is_none_or(|minute| local.minute < minute)
            || self
                .configuration
                .last_run_day
                .as_deref()
                .is_some_and(|day| day >= local.day.as_str())
        {
            return Due::None;
        }
        let mut next = self.configuration.clone();
        next.last_run_day = Some(local.day.clone());
        let late = minute(&self.configuration.time).ok() != Some(local.minute);
        let notice = if late {
            "Automatic update time was missed while the service was stopped or paused. Check and update manually; missed runs are not replayed."
        } else if busy {
            "Automatic update time was missed because another operation was running. Check and update manually; the next scheduled run is tomorrow."
        } else if !authorized {
            "Automatic update time was missed because system changes were not authorized. Reopen Settings to authorize, then check and update manually. Authorization will not start the missed run."
        } else {
            "Scheduled update started."
        };
        next.notice = Some(notice.into());
        if let Err(error) = self.persist(next.clone()) {
            self.configuration.notice = Some(
                "Automatic update was not started because its schedule record could not be saved."
                    .into(),
            );
            self.error = Some(format!(
                "Cannot record scheduled run; automatic update was not started: {error}"
            ));
            return Due::Changed;
        }
        if late || busy || !authorized {
            Due::Changed
        } else {
            Due::Run
        }
    }
    pub fn finished(&mut self, error: Option<&str>) {
        let mut next = self.configuration.clone();
        next.notice = Some(match error {
            Some(error) => format!("Automatic update failed: {error}"),
            None => "Automatic update completed.".into(),
        });
        if let Err(error) = self.persist(next) {
            self.error = Some(format!("Cannot save automatic update result: {error}"));
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
        fs::write(path, bytes).map_err(|e| e.to_string())
    }
    fn local(day: &str, minute: u32) -> LocalTime {
        LocalTime {
            day: day.into(),
            minute,
        }
    }
    #[test]
    fn opt_in_local_minute_once_per_day_persists_and_never_catches_up() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("updates.json");
        let mut schedule = Schedule::load(path.clone(), write);
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::None
        ));
        schedule.set(super::super::AUTOMATIC, "true").unwrap();
        assert!(matches!(
            schedule.due(&local("2026-11-02", 181), false, true),
            Due::Changed
        ));
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::Run
        ));
        let mut reopened = Schedule::load(path, write);
        assert_eq!(reopened.state()["enabled"], true);
        assert!(matches!(
            reopened.due(&local("2026-11-03", 180), false, true),
            Due::None
        ));
        assert!(matches!(
            reopened.due(&local("2026-11-04", 180), false, true),
            Due::Run
        ));
    }
    #[test]
    fn authorization_and_busy_misses_are_visible_and_are_not_replayed_after_authorization() {
        let mut schedule = Schedule::memory();
        schedule.set(super::super::AUTOMATIC, "true").unwrap();
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, false),
            Due::Changed
        ));
        assert!(
            schedule.state()["notice"]
                .as_str()
                .unwrap()
                .contains("not authorized")
        );
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::None
        ));
        assert!(matches!(
            schedule.due(&local("2026-11-04", 180), true, true),
            Due::Changed
        ));
        assert!(
            schedule.state()["notice"]
                .as_str()
                .unwrap()
                .contains("another operation")
        );
    }
    #[test]
    fn malformed_input_and_persistence_failure_never_enable_or_start_updates() {
        let mut schedule = Schedule::memory();
        for value in ["24:00", "03:60", "3:00", "no", "00:00:00"] {
            assert!(schedule.set(super::super::TIME, value).is_err());
        }
        schedule.path = Some("/unused".into());
        schedule.write = |_, _| Err("read only".into());
        assert!(schedule.set(super::super::AUTOMATIC, "true").is_err());
        assert_eq!(schedule.state()["enabled"], false);
        schedule.configuration.enabled = true;
        schedule.error = None;
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::Changed
        ));
        assert!(schedule.error.is_some());
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::None
        ));
    }
    #[test]
    fn timezone_refresh_and_backward_dates_do_not_replay_a_day() {
        if std::env::var("REMYA_SCHEDULE_TZ_TEST").as_deref() != Ok("1") {
            assert!(
                std::process::Command::new(std::env::current_exe().unwrap())
                    .args([
                        "schedule::tests::timezone_refresh_and_backward_dates_do_not_replay_a_day",
                        "--exact"
                    ])
                    .env("REMYA_SCHEDULE_TZ_TEST", "1")
                    .status()
                    .unwrap()
                    .success()
            );
            return;
        }
        // This subprocess runs only this test, isolating libc's process-global timezone cache.
        unsafe {
            std::env::set_var("TZ", "UTC");
        }
        assert_eq!(LocalTime::at(0).unwrap().minute, 0);
        unsafe {
            std::env::set_var("TZ", "Asia/Taipei");
        }
        assert_eq!(LocalTime::at(0).unwrap().minute, 480);
        let mut schedule = Schedule::memory();
        schedule.set(super::super::AUTOMATIC, "true").unwrap();
        assert!(matches!(
            schedule.due(&local("2026-11-04", 180), false, true),
            Due::Run
        ));
        assert!(matches!(
            schedule.due(&local("2026-11-03", 180), false, true),
            Due::None
        ));
    }
    #[test]
    fn write_errors_remain_visible_and_explicit_retry_can_recover() {
        let mut schedule = Schedule::memory();
        schedule.path = Some("/unused".into());
        schedule.write = |_, _| Err("read-only directory".into());
        assert!(schedule.set(super::super::AUTOMATIC, "true").is_err());
        assert!(
            schedule.state()["error"]
                .as_str()
                .unwrap()
                .contains("read-only directory")
        );
        assert_eq!(schedule.state()["enabled"], false);
        assert_eq!(schedule.state()["editable"], true);
        schedule.write = |_, _| Ok(());
        schedule.set(super::super::AUTOMATIC, "true").unwrap();
        assert!(schedule.state()["error"].is_null());
    }
}
