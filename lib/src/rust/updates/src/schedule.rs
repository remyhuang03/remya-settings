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
    active_start: String,
    active_end: String,
    /// Local date on which the last handled inactive window began.
    last_run_day: Option<String>,
    notice: Option<String>,
}
impl Default for Configuration {
    fn default() -> Self {
        Self {
            version: 2,
            enabled: false,
            active_start: "08:00".into(),
            active_end: "23:00".into(),
            last_run_day: None,
            notice: None,
        }
    }
}
impl Configuration {
    fn minutes(&self) -> Option<(u32, u32)> {
        let start = minute(&self.active_start).ok()?;
        let end = minute(&self.active_end).ok()?;
        (start != end).then_some((start, end))
    }
    fn active(&self, local: &LocalTime) -> bool {
        self.minutes().is_some_and(|(start, end)| {
            if start < end {
                (start..end).contains(&local.minute)
            } else {
                local.minute >= start || local.minute < end
            }
        })
    }
    /// The most recent inactive window started at the last occurrence of the end time.
    fn window<'a>(&self, local: &'a LocalTime) -> &'a str {
        match self.minutes() {
            Some((_, end)) if local.minute >= end => &local.day,
            _ => &local.yesterday,
        }
    }
    fn handled(&self, local: &LocalTime) -> bool {
        self.last_run_day
            .as_deref()
            .is_some_and(|day| day >= self.window(local))
    }
}
#[derive(Clone, Debug)]
pub(crate) struct LocalTime {
    pub day: String,
    pub yesterday: String,
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
        let local = |seconds: libc::time_t| {
            let mut local = std::mem::MaybeUninit::<libc::tm>::uninit();
            if unsafe { libc::localtime_r(&seconds, local.as_mut_ptr()) }.is_null() {
                return None;
            }
            Some(unsafe { local.assume_init() })
        };
        let day = |tm: &libc::tm| {
            format!(
                "{:04}-{:02}-{:02}",
                tm.tm_year + 1900,
                tm.tm_mon + 1,
                tm.tm_mday
            )
        };
        let today = local(seconds)?;
        // Noon yesterday is a calendar day earlier even across a DST change.
        let noon =
            seconds - libc::time_t::from(today.tm_hour * 3600 + today.tm_min * 60) - 12 * 3600;
        Some(Self {
            day: day(&today),
            yesterday: day(&local(noon)?),
            minute: (today.tm_hour * 60 + today.tm_min) as u32,
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
fn valid_day(day: &str) -> bool {
    day.len() == 10
        && day.bytes().enumerate().all(|(i, b)| {
            if i == 4 || i == 7 {
                b == b'-'
            } else {
                b.is_ascii_digit()
            }
        })
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
                if configuration.version == 2
                    && configuration.minutes().is_some()
                    && configuration.last_run_day.as_deref().is_none_or(valid_day) =>
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
        let c = &self.configuration;
        json!({"enabled":c.enabled,"active_start":c.active_start,"active_end":c.active_end,"last_run_day":c.last_run_day,"notice":c.notice,"error":self.error,"editable":!self.blocked})
    }
    fn persist(&mut self, next: Configuration) -> Result<(), String> {
        if let Some(path) = &self.path {
            let bytes = serde_json::to_vec_pretty(&next).map_err(|e| e.to_string())?;
            (self.write)(path, &bytes)?;
        }
        self.configuration = next;
        Ok(())
    }
    pub fn set(&mut self, id: &str, value: &str, local: &LocalTime) -> Result<(), String> {
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
            super::ACTIVE_START | super::ACTIVE_END => {
                minute(value)?;
                if id == super::ACTIVE_START {
                    next.active_start = value.into();
                } else {
                    next.active_end = value.into();
                }
                if next.minutes().is_none() {
                    return Err(
                        "InvalidArgument:Active hours must start and end at different times".into(),
                    );
                }
            }
            _ => return Err("InvalidArgument:Unknown schedule setting".into()),
        }
        // A change made during active hours is not a missed inactive window.
        if next.enabled && next.active(local) && !next.handled(local) {
            next.last_run_day = Some(next.window(local).into());
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
    /// Runs once per inactive window as soon as it begins. A window missed entirely (computer
    /// off or service stopped) is caught up at the next tick, even during active hours.
    /// A busy service waits instead of skipping.
    pub fn due(&mut self, local: &LocalTime, busy: bool, ready: bool) -> Due {
        let c = &self.configuration;
        if busy || self.error.is_some() || !c.enabled || c.handled(local) {
            return Due::None;
        }
        let mut next = c.clone();
        next.last_run_day = Some(c.window(local).into());
        next.notice = Some(if !ready {
            format!(
                "Automatic update skipped: the system updater is not installed. Run {}.",
                super::INSTALL_COMMAND
            )
        } else if c.active(local) {
            "Automatic update started during active hours because the last inactive period was missed.".into()
        } else {
            "Automatic update started.".into()
        });
        if let Err(error) = self.persist(next) {
            self.configuration.notice = Some(
                "Automatic update was not started because its schedule record could not be saved."
                    .into(),
            );
            self.error = Some(format!(
                "Cannot record scheduled run; automatic update was not started: {error}"
            ));
            return Due::Changed;
        }
        if ready { Due::Run } else { Due::Changed }
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
    use crate::{ACTIVE_END, ACTIVE_START, AUTOMATIC};
    fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
        fs::write(path, bytes).map_err(|e| e.to_string())
    }
    fn local(day: &str, yesterday: &str, hour: u32, minute: u32) -> LocalTime {
        LocalTime {
            day: day.into(),
            yesterday: yesterday.into(),
            minute: hour * 60 + minute,
        }
    }
    const D1: &str = "2026-11-01";
    const D2: &str = "2026-11-02";
    const D3: &str = "2026-11-03";
    const D4: &str = "2026-11-04";
    #[test]
    fn runs_once_when_each_inactive_window_begins_and_persists() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("updates.json");
        let mut schedule = Schedule::load(path.clone(), write);
        assert!(matches!(
            schedule.due(&local(D3, D2, 23, 0), false, true),
            Due::None
        ));
        // Enabled during active hours (08:00-23:00): last night is not "missed".
        schedule
            .set(AUTOMATIC, "true", &local(D3, D2, 10, 0))
            .unwrap();
        assert!(matches!(
            schedule.due(&local(D3, D2, 22, 59), false, true),
            Due::None
        ));
        assert!(matches!(
            schedule.due(&local(D3, D2, 23, 0), false, true),
            Due::Run
        ));
        // Same window after midnight: already handled.
        assert!(matches!(
            schedule.due(&local(D4, D3, 2, 0), false, true),
            Due::None
        ));
        let mut reopened = Schedule::load(path, write);
        assert_eq!(reopened.state()["enabled"], true);
        assert!(matches!(
            reopened.due(&local(D4, D3, 9, 0), false, true),
            Due::None
        ));
        assert!(matches!(
            reopened.due(&local(D4, D3, 23, 30), false, true),
            Due::Run
        ));
    }
    #[test]
    fn a_missed_inactive_window_is_caught_up_during_active_hours() {
        let mut schedule = Schedule::memory();
        schedule
            .set(AUTOMATIC, "true", &local(D2, D1, 23, 30))
            .unwrap();
        assert!(matches!(
            schedule.due(&local(D2, D1, 23, 30), false, true),
            Due::Run
        ));
        // Computer off from D3 23:00 to D4 08:00; the first tick at D4 09:00 catches up.
        assert!(matches!(
            schedule.due(&local(D4, D3, 9, 0), false, true),
            Due::Run
        ));
        assert!(
            schedule.state()["notice"]
                .as_str()
                .unwrap()
                .contains("during active hours")
        );
        assert!(matches!(
            schedule.due(&local(D4, D3, 12, 0), false, true),
            Due::None
        ));
    }
    #[test]
    fn overnight_active_hours_busy_waits_and_missing_updater_is_reported() {
        let mut schedule = Schedule::memory();
        let at = local(D3, D2, 12, 0);
        schedule.set(ACTIVE_START, "20:00", &at).unwrap();
        schedule.set(ACTIVE_END, "04:00", &at).unwrap();
        assert!(schedule.set(ACTIVE_END, "20:00", &at).is_err());
        schedule
            .set(AUTOMATIC, "true", &local(D3, D2, 21, 0))
            .unwrap();
        assert!(matches!(
            schedule.due(&local(D4, D3, 2, 0), false, true),
            Due::None
        ));
        assert!(matches!(
            schedule.due(&local(D4, D3, 4, 0), true, true),
            Due::None
        ));
        assert_eq!(schedule.state()["last_run_day"], D3);
        assert!(matches!(
            schedule.due(&local(D4, D3, 4, 5), false, false),
            Due::Changed
        ));
        assert!(
            schedule.state()["notice"]
                .as_str()
                .unwrap()
                .contains("not installed")
        );
        assert!(matches!(
            schedule.due(&local(D4, D3, 5, 0), false, true),
            Due::None
        ));
    }
    #[test]
    fn malformed_input_and_persistence_failure_never_enable_or_start_updates() {
        let mut schedule = Schedule::memory();
        let at = local(D3, D2, 12, 0);
        for value in ["24:00", "03:60", "3:00", "no", "00:00:00"] {
            assert!(schedule.set(ACTIVE_START, value, &at).is_err());
        }
        schedule.path = Some("/unused".into());
        schedule.write = |_, _| Err("read only".into());
        assert!(schedule.set(AUTOMATIC, "true", &at).is_err());
        assert_eq!(schedule.state()["enabled"], false);
        assert!(
            schedule.state()["error"]
                .as_str()
                .unwrap()
                .contains("read only")
        );
        assert_eq!(schedule.state()["editable"], true);
        schedule.configuration.enabled = true;
        schedule.error = None;
        assert!(matches!(
            schedule.due(&local(D3, D2, 23, 0), false, true),
            Due::Changed
        ));
        assert!(matches!(
            schedule.due(&local(D3, D2, 23, 0), false, true),
            Due::None
        ));
        schedule.write = |_, _| Ok(());
        schedule.set(AUTOMATIC, "true", &at).unwrap();
        assert!(schedule.state()["error"].is_null());
    }
    #[test]
    fn obsolete_or_invalid_files_block_the_schedule_without_rewriting() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("updates.json");
        fs::write(
            &path,
            br#"{"version":1,"enabled":true,"time":"03:00","last_run_day":null,"notice":null}"#,
        )
        .unwrap();
        let mut schedule = Schedule::load(path, |_, _| panic!("must not write"));
        assert!(schedule.state()["error"].is_string());
        assert_eq!(schedule.state()["editable"], false);
        assert!(matches!(
            schedule.due(&local(D3, D2, 23, 0), false, true),
            Due::None
        ));
    }
    #[test]
    fn local_time_reports_today_and_the_previous_calendar_day() {
        if std::env::var("REMYA_SCHEDULE_TZ_TEST").as_deref() != Ok("1") {
            assert!(
                std::process::Command::new(std::env::current_exe().unwrap())
                    .args([
                        "schedule::tests::local_time_reports_today_and_the_previous_calendar_day",
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
        let time = LocalTime::at(0).unwrap();
        assert_eq!(
            (time.day.as_str(), time.yesterday.as_str(), time.minute),
            ("1970-01-01", "1969-12-31", 0)
        );
        unsafe {
            std::env::set_var("TZ", "Asia/Taipei");
        }
        assert_eq!(LocalTime::at(0).unwrap().minute, 480);
        // 2026-03-29 01:30 UTC is just after the Europe/Berlin DST switch.
        unsafe {
            std::env::set_var("TZ", "Europe/Berlin");
        }
        let switch = LocalTime::at(1_774_747_800).unwrap();
        assert_eq!(
            (switch.day.as_str(), switch.yesterday.as_str()),
            ("2026-03-29", "2026-03-28")
        );
    }
}
