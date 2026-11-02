//! Night light through hyprsunset: `hyprsunset.conf` holds the stable preference and
//! its native profiles run the schedule; the running process holds the current state.
use crate::{Hyprctl, atomic_write, run_bytes};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

pub const ENABLED: &str = "night-light.e32be03e";
pub const TEMPERATURE: &str = "night-light.temperature";
pub const SCHEDULE: &str = "night-light.7e6239c9";
pub const START: &str = "night-light.e8868af6";
pub const END: &str = "night-light.a0bb9f49";
const UNIT: &str = "hyprsunset.service";
const MIN_KELVIN: u32 = 1000;
const MAX_KELVIN: u32 = 6500;
const DEFAULT_KELVIN: u32 = 6000;
const DEFAULT_START: &str = "19:00";
const DEFAULT_END: &str = "06:30";

pub fn is_night_light_setting(id: &str) -> bool {
    [ENABLED, TEMPERATURE, SCHEDULE, START, END].contains(&id)
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub temperature: u32,
    /// Meaningful only without a schedule, which decides the state otherwise.
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
struct Config {
    prefs: Prefs,
    max_gamma: Option<u32>,
}

/// Normalizes to `HH:MM`; hyprsunset itself accepts sloppier values.
fn parse_time(text: &str) -> Option<String> {
    let (hour, minute) = text.split_once(':')?;
    let hour = hour.parse::<u32>().ok().filter(|h| *h < 24)?;
    let minute = minute.parse::<u32>().ok().filter(|m| *m < 60)?;
    Some(format!("{hour:02}:{minute:02}"))
}

fn valid_kelvin(kelvin: u32) -> bool {
    (MIN_KELVIN..=MAX_KELVIN).contains(&kelvin)
}

#[derive(Debug, PartialEq)]
struct Profile {
    time: String,
    temperature: u32,
    identity: bool,
}

/// Accepts only the shapes this feature writes, so nothing it cannot express is lost.
fn parse(text: &str) -> Result<Config, String> {
    let unsafe_line = |line: &str| format!("Settings cannot safely edit this line: {line}");
    let mut max_gamma = None;
    let mut profiles = Vec::new();
    let mut current: Option<Profile> = None;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line == "profile {" && current.is_none() {
            current = Some(Profile {
                time: "00:00".into(),
                temperature: DEFAULT_KELVIN,
                identity: false,
            });
            continue;
        }
        if line == "}" {
            profiles.push(current.take().ok_or_else(|| unsafe_line(line))?);
            continue;
        }
        let (key, value) = line.split_once('=').ok_or_else(|| unsafe_line(line))?;
        let (key, value) = (key.trim(), value.trim());
        match (key, current.as_mut()) {
            ("max-gamma", None) => {
                max_gamma = Some(value.parse().map_err(|_| unsafe_line(line))?);
            }
            ("time", Some(profile)) => {
                profile.time = parse_time(value).ok_or_else(|| unsafe_line(line))?;
            }
            ("temperature", Some(profile)) => {
                profile.temperature = value.parse().map_err(|_| unsafe_line(line))?;
            }
            ("identity", Some(profile)) => {
                profile.identity = match value {
                    "true" | "1" | "yes" | "on" => true,
                    "false" | "0" | "no" | "off" => false,
                    _ => return Err(unsafe_line(line)),
                };
            }
            ("gamma", Some(_)) if value.parse::<f32>() == Ok(1.0) => {}
            _ => return Err(unsafe_line(line)),
        }
    }
    if current.is_some() {
        return Err("The hyprsunset configuration has an unterminated profile".into());
    }
    let prefs = match profiles.as_slice() {
        [] => Prefs {
            temperature: DEFAULT_KELVIN,
            enabled: false,
            start: None,
            end: None,
        },
        [only] => Prefs {
            temperature: only.temperature,
            enabled: !only.identity,
            start: None,
            end: None,
        },
        [a, b]
            if a.identity != b.identity && a.temperature == b.temperature && a.time != b.time =>
        {
            let (warm, plain) = if a.identity { (b, a) } else { (a, b) };
            Prefs {
                temperature: warm.temperature,
                enabled: false,
                start: Some(warm.time.clone()),
                end: Some(plain.time.clone()),
            }
        }
        _ => return Err("Settings cannot express these hyprsunset profiles".into()),
    };
    if !valid_kelvin(prefs.temperature) {
        return Err(format!(
            "hyprsunset temperature {} is outside {MIN_KELVIN}-{MAX_KELVIN} K",
            prefs.temperature
        ));
    }
    Ok(Config { prefs, max_gamma })
}

fn render(config: &Config) -> String {
    let profile = |time: &str, identity: bool| {
        format!(
            "profile {{\n    time = {time}\n    temperature = {}\n    identity = {identity}\n}}\n",
            config.prefs.temperature
        )
    };
    let mut text = String::from("# Managed by Remy'a Settings. Change Night light in Settings.\n");
    if let Some(gamma) = config.max_gamma {
        text += &format!("max-gamma = {gamma}\n");
    }
    match (&config.prefs.start, &config.prefs.end) {
        (Some(start), Some(end)) => {
            text += &profile(start, false);
            text += &profile(end, true);
        }
        _ => text += &profile("00:00", !config.prefs.enabled),
    }
    text
}

/// The running hyprsunset, reached through `hyprctl hyprsunset`.
pub trait Sunset: Send {
    /// The reply to a request; fails when hyprsunset is not reachable.
    fn request(&self, args: &[&str]) -> Result<String, String>;
    /// Starts hyprsunset under its unit, or replaces the running one.
    fn restart(&self) -> Result<(), String>;
}

pub struct RealSunset;

fn systemctl(args: &[&str]) -> Result<(), String> {
    let mut all = vec!["--user"];
    all.extend_from_slice(args);
    run_bytes("systemctl", &all, &[], Duration::from_secs(15)).map(drop)
}

impl Sunset for RealSunset {
    fn request(&self, args: &[&str]) -> Result<String, String> {
        // `hyprctl hyprsunset` ignores `-i`; the instance must come from the environment.
        let instance = Hyprctl::instance()?;
        let mut all = vec!["hyprsunset"];
        all.extend_from_slice(args);
        let reply = run_bytes(
            "hyprctl",
            &all,
            &[("HYPRLAND_INSTANCE_SIGNATURE", instance.as_str())],
            Duration::from_secs(5),
        )?;
        let reply = String::from_utf8_lossy(&reply).trim().to_owned();
        if reply.starts_with("Couldn't") || reply.contains("invalid command") {
            return Err(format!("hyprsunset is not running: {reply}"));
        }
        Ok(reply)
    }

    fn restart(&self) -> Result<(), String> {
        systemctl(&["enable", UNIT])?;
        // Quick successive changes would otherwise hit the unit's start rate limit.
        let _ = systemctl(&["reset-failed", UNIT]);
        systemctl(&["restart", UNIT])?;
        let started = Instant::now();
        while started.elapsed() < Duration::from_secs(3) {
            if self.request(&["identity", "get"]).is_ok() {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(50));
        }
        Err(format!(
            "{UNIT} did not start; another hyprsunset may still be running"
        ))
    }
}

/// What the process is doing now, which Bar and hotkeys may change at any time.
#[derive(Clone, Debug, PartialEq)]
struct Live {
    enabled: bool,
    temperature: u32,
    gamma: String,
}

pub struct NightLight<S> {
    sunset: S,
    config_path: PathBuf,
    saved_path: PathBuf,
    saved: Option<Prefs>,
    system: Option<Config>,
    live: Option<Live>,
    write_blocked: Option<String>,
    error: Option<String>,
}

impl<S: Sunset> NightLight<S> {
    pub fn new(sunset: S, config_path: PathBuf, saved_path: PathBuf) -> Self {
        Self {
            sunset,
            config_path,
            saved_path,
            saved: None,
            system: None,
            live: None,
            write_blocked: None,
            error: None,
        }
    }

    fn read_live(&self) -> Result<Live, String> {
        Ok(Live {
            enabled: self.sunset.request(&["identity", "get"])? == "false",
            temperature: self
                .sunset
                .request(&["temperature"])?
                .parse()
                .map_err(|_| "hyprsunset reported an invalid temperature")?,
            gamma: self.sunset.request(&["gamma"])?,
        })
    }

    fn read(&mut self) -> Result<(), String> {
        self.write_blocked = None;
        self.system = None;
        self.live = self.read_live().ok();
        let text = match fs::read_to_string(&self.config_path) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(format!("{}: {e}", self.config_path.display())),
        };
        match parse(&text) {
            Ok(config) => self.system = Some(config),
            Err(message) => {
                self.write_blocked = Some(message.clone());
                return Err(message);
            }
        }
        self.saved = match fs::read_to_string(&self.saved_path) {
            Ok(text) => {
                let saved: Prefs = toml::from_str(&text)
                    .map_err(|e| format!("{}: {e}", self.saved_path.display()))?;
                Some(saved)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let prefs = self.system.as_ref().map(|c| c.prefs.clone());
                if let Some(prefs) = &prefs {
                    self.save(prefs)?;
                }
                prefs
            }
            Err(e) => return Err(format!("{}: {e}", self.saved_path.display())),
        };
        Ok(())
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.read();
        self.error = result.as_ref().err().cloned();
        result
    }

    fn save(&self, prefs: &Prefs) -> Result<(), String> {
        let text = toml::to_string(prefs).map_err(|e| e.to_string())?;
        atomic_write(&self.saved_path, text.as_bytes())
    }

    fn has_conflict(&self) -> bool {
        match (&self.saved, &self.system) {
            (Some(saved), Some(system)) => *saved != system.prefs,
            _ => false,
        }
    }

    pub fn state(&self) -> Value {
        let system = self.system.as_ref().map(|c| &c.prefs);
        let shown = self.saved.as_ref().or(system);
        json!({
            "saved": self.saved,
            "system": system,
            "conflict": self.has_conflict(),
            "running": self.live.is_some(),
            // Without hyprsunset no filter is on the screen, whatever is configured.
            "enabled": self.live.as_ref().is_some_and(|live| live.enabled),
            "temperature": shown.map(|p| p.temperature),
            "live_temperature": self.live.as_ref().map(|live| live.temperature),
            "schedule": shown.is_some_and(|p| p.start.is_some()),
            "start": shown.and_then(|p| p.start.as_ref()),
            "end": shown.and_then(|p| p.end.as_ref()),
            "write_blocked": self.write_blocked,
            "error": self.error,
        })
    }

    pub fn setting_value(&self, key: &str) -> Value {
        let state = self.state();
        match key {
            ENABLED => state["enabled"].clone(),
            TEMPERATURE => state["temperature"].clone(),
            SCHEDULE => state["schedule"].clone(),
            START => state["start"].clone(),
            _ => state["end"].clone(),
        }
    }

    /// The reply must confirm the request; hyprsunset answers refusals in plain text.
    fn command(&self, args: &[&str]) -> Result<(), String> {
        match self.sunset.request(args)?.as_str() {
            "ok" => Ok(()),
            reply => Err(format!("hyprsunset: {reply}")),
        }
    }

    /// hyprsunset cannot reload, and its profile thread would reapply the old values
    /// at the next boundary, so every configuration change needs a restart. Gamma and
    /// a manual override are process state that must survive it.
    fn restart_with(&self, identity: Option<bool>, gamma: Option<&str>) -> Result<(), String> {
        self.sunset.restart()?;
        if let Some(identity) = identity {
            self.command(&["identity", if identity { "true" } else { "false" }])?;
            let reply = self.sunset.request(&["identity", "get"])?;
            if reply != identity.to_string() {
                return Err("hyprsunset did not apply the requested state".into());
            }
        }
        if let Some(gamma) = gamma.filter(|g| *g != "100") {
            self.command(&["gamma", gamma])?;
        }
        Ok(())
    }

    /// Writes the configuration, verifies it by parsing, then applies it.
    fn write(&mut self, prefs: Prefs, identity: Option<bool>) -> Result<(), String> {
        let previous = self.read_live().ok();
        let config = Config {
            prefs: prefs.clone(),
            max_gamma: self.system.as_ref().and_then(|c| c.max_gamma),
        };
        let text = render(&config);
        if parse(&text).as_ref() != Ok(&config) {
            return Err("Refusing to write a configuration that does not read back".into());
        }
        let before = fs::read(&self.config_path).ok();
        atomic_write(&self.config_path, text.as_bytes())?;
        if let Err(message) =
            self.restart_with(identity, previous.as_ref().map(|l| l.gamma.as_str()))
        {
            // A failed application must not leave the file agreeing with Settings.
            match before {
                Some(bytes) => atomic_write(&self.config_path, &bytes)?,
                None => fs::remove_file(&self.config_path).map_err(|e| e.to_string())?,
            }
            return Err(message);
        }
        self.save(&prefs)?;
        self.saved = Some(prefs);
        Ok(())
    }

    fn current(&mut self) -> Result<Prefs, String> {
        self.refresh()?;
        if let Some(reason) = &self.write_blocked {
            return Err(reason.clone());
        }
        if self.has_conflict() {
            return Err("Resolve the Night light conflict first".into());
        }
        self.saved
            .clone()
            .ok_or_else(|| "Night light is not initialized".into())
    }

    fn apply(&mut self, key: &str, value: &str) -> Result<(), String> {
        let mut next = self.current()?;
        let scheduled = next.start.is_some();
        let live = self.live.as_ref().map(|l| !l.enabled);
        match key {
            ENABLED => {
                let enabled = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err(invalid("Use true or false")),
                };
                if scheduled {
                    // Stays until the next boundary, when the schedule takes over.
                    self.command(&["identity", if enabled { "false" } else { "true" }])?;
                    let reply = self.sunset.request(&["identity", "get"])?;
                    if reply == enabled.to_string() {
                        return Err("hyprsunset did not apply the requested state".into());
                    }
                    return Ok(());
                }
                next.enabled = enabled;
                self.write(next, None)
            }
            TEMPERATURE => {
                let kelvin: u32 = value
                    .parse()
                    .ok()
                    .filter(|k| valid_kelvin(*k))
                    .ok_or_else(|| invalid(&format!("Use {MIN_KELVIN}-{MAX_KELVIN} K")))?;
                next.temperature = kelvin;
                self.write(next, live)
            }
            SCHEDULE => {
                match value {
                    "true" if !scheduled => {
                        next.start = Some(DEFAULT_START.into());
                        next.end = Some(DEFAULT_END.into());
                        next.enabled = false;
                    }
                    "false" if scheduled => {
                        next.start = None;
                        next.end = None;
                        // Without a schedule, Night light is simply on until turned off.
                        next.enabled = true;
                    }
                    "true" | "false" => return Ok(()),
                    _ => return Err(invalid("Use true or false")),
                }
                self.write(next, None)
            }
            START | END => {
                if !scheduled {
                    return Err(invalid("Turn on the schedule first"));
                }
                let time = parse_time(value).ok_or_else(|| invalid("Use HH:MM"))?;
                let slot = if key == START {
                    &mut next.start
                } else {
                    &mut next.end
                };
                *slot = Some(time);
                if next.start == next.end {
                    return Err(invalid("Start and end must differ"));
                }
                self.write(next, None)
            }
            _ => Err(invalid("Unknown setting")),
        }
    }

    pub fn set(&mut self, key: &str, value: &str) -> Result<Value, String> {
        let result = self.apply(key, value);
        let _ = self.refresh();
        if let Err(message) = &result
            && !message.starts_with("InvalidArgument:")
        {
            self.error = Some(message.clone());
        }
        result.map(|_| self.state())
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let result = (|| {
            self.refresh()?;
            match source {
                "system" => {
                    let prefs = self
                        .system
                        .as_ref()
                        .map(|c| c.prefs.clone())
                        .ok_or("The hyprsunset configuration cannot be read")?;
                    self.save(&prefs)
                }
                "settings" => {
                    let saved = self.saved.clone().ok_or("Nothing is saved yet")?;
                    self.write(saved, None)
                }
                _ => Err(invalid("Unknown resolution")),
            }
        })();
        let _ = self.refresh();
        if let Err(message) = &result
            && !message.starts_with("InvalidArgument:")
        {
            self.error = Some(message.clone());
        }
        result.map(|_| self.state())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct World {
        identity: bool,
        kelvin: u32,
        gamma: String,
        restarts: u32,
        down: bool,
        fail_restart: bool,
        config: PathBuf,
    }

    #[derive(Clone, Default)]
    struct Fake(Arc<Mutex<World>>);

    impl Sunset for Fake {
        fn request(&self, args: &[&str]) -> Result<String, String> {
            let mut world = self.0.lock().unwrap();
            if world.down {
                return Err("hyprsunset is not running".into());
            }
            Ok(match args {
                ["identity", "get"] => world.identity.to_string(),
                ["temperature"] => world.kelvin.to_string(),
                ["gamma"] => world.gamma.clone(),
                ["identity", value] => {
                    world.identity = *value == "true";
                    "ok".into()
                }
                ["gamma", value] => {
                    world.gamma = (*value).to_owned();
                    "ok".into()
                }
                _ => "unexpected".into(),
            })
        }

        fn restart(&self) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            if world.fail_restart {
                return Err("restart failed".into());
            }
            let config = parse(&fs::read_to_string(&world.config).unwrap()).unwrap();
            world.restarts += 1;
            world.down = false;
            world.kelvin = config.prefs.temperature;
            world.gamma = "100".into();
            // Daytime in this fake: a schedule starts in its plain profile.
            world.identity = config.prefs.start.is_some() || !config.prefs.enabled;
            Ok(())
        }
    }

    const WARM: &str = "# keep warm\nprofile {\n    time = 00:00\n    temperature = 2600\n    identity = false\n}\n";

    fn manager(text: Option<&str>) -> (tempfile::TempDir, Fake, NightLight<Fake>) {
        let root = tempfile::tempdir().unwrap();
        let config = root.path().join("hyprsunset.conf");
        if let Some(text) = text {
            fs::write(&config, text).unwrap();
        }
        let fake = Fake::default();
        {
            let mut world = fake.0.lock().unwrap();
            world.config = config.clone();
            world.kelvin = 2600;
            world.gamma = "100".into();
        }
        let manager = NightLight::new(fake.clone(), config, root.path().join("saved.toml"));
        (root, fake, manager)
    }

    #[test]
    fn parser_round_trips_every_written_shape() {
        for (temperature, enabled, start, end) in [
            (2600, true, None, None),
            (6000, false, None, None),
            (3000, false, Some("19:00"), Some("06:30")),
        ] {
            let config = Config {
                prefs: Prefs {
                    temperature,
                    enabled,
                    start: start.map(str::to_owned),
                    end: end.map(str::to_owned),
                },
                max_gamma: Some(150),
            };
            assert_eq!(parse(&render(&config)).unwrap(), config);
        }
    }

    #[test]
    fn parser_refuses_what_it_cannot_express() {
        for text in [
            "exec = rm -rf /\n",
            "profile {\n time = 00:00\n",
            "profile {\n time = 25:00\n}\n",
            "profile {\n gamma = 0.8\n}\n",
            "profile {\n temperature = 9000\n}\n",
            "profile {\n time = 01:00\n}\nprofile {\n time = 02:00\n}\n",
            "profile {\n time = 01:00\n}\nprofile {\n time = 02:00\n}\nprofile {\n time = 03:00\n identity = true\n}\n",
        ] {
            assert!(parse(text).is_err(), "{text}");
        }
        assert!(!parse("").unwrap().prefs.enabled);
    }

    #[test]
    fn first_use_adopts_the_system_without_writing_to_it() {
        let (root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        let state = night.state();
        assert_eq!(state["saved"]["temperature"], 2600);
        assert_eq!(state["enabled"], true);
        assert_eq!(state["conflict"], false);
        assert_eq!(fake.0.lock().unwrap().restarts, 0);
        assert_eq!(
            fs::read_to_string(root.path().join("hyprsunset.conf")).unwrap(),
            WARM
        );
        assert!(root.path().join("saved.toml").exists());
    }

    #[test]
    fn unreadable_configuration_stays_uninitialized_and_blocks_writes() {
        let (root, _, mut night) = manager(Some("exec = x\n"));
        assert!(night.refresh().is_err());
        assert!(!root.path().join("saved.toml").exists());
        assert!(night.state()["write_blocked"].is_string());
        assert!(night.set(TEMPERATURE, "3000").is_err());
        assert_eq!(
            fs::read_to_string(root.path().join("hyprsunset.conf")).unwrap(),
            "exec = x\n"
        );
    }

    #[test]
    fn toggle_without_schedule_persists_and_restarts() {
        let (root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        fake.0.lock().unwrap().gamma = "70".into();
        let state = night.set(ENABLED, "false").unwrap();
        assert_eq!(state["enabled"], false);
        assert_eq!(state["saved"]["enabled"], false);
        assert_eq!(fake.0.lock().unwrap().gamma, "70");
        let text = fs::read_to_string(root.path().join("hyprsunset.conf")).unwrap();
        assert!(text.contains("identity = true"));
    }

    #[test]
    fn toggle_with_schedule_only_overrides_the_process() {
        let (root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        night.set(SCHEDULE, "true").unwrap();
        let path = root.path().join("hyprsunset.conf");
        let before = fs::read_to_string(&path).unwrap();
        let restarts = fake.0.lock().unwrap().restarts;
        let state = night.set(ENABLED, "true").unwrap();
        assert_eq!(state["enabled"], true);
        assert_eq!(state["conflict"], false);
        assert_eq!(fs::read_to_string(&path).unwrap(), before);
        assert_eq!(fake.0.lock().unwrap().restarts, restarts);
    }

    #[test]
    fn temperature_change_keeps_a_manual_override() {
        let (_root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        night.set(SCHEDULE, "true").unwrap();
        night.set(ENABLED, "true").unwrap();
        let state = night.set(TEMPERATURE, "3200").unwrap();
        assert_eq!(state["temperature"], 3200);
        assert_eq!(state["enabled"], true);
        assert!(!fake.0.lock().unwrap().identity);
    }

    #[test]
    fn schedule_rejects_bad_times_and_writes_two_profiles() {
        let (root, _, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        assert!(night.set(START, "20:00").is_err());
        night.set(SCHEDULE, "true").unwrap();
        for (key, value) in [(START, "24:00"), (START, "x"), (START, "06:30")] {
            assert!(
                night
                    .set(key, value)
                    .unwrap_err()
                    .starts_with("InvalidArgument:")
            );
        }
        let state = night.set(START, "20:15").unwrap();
        assert_eq!(state["start"], "20:15");
        assert_eq!(state["end"], "06:30");
        let text = fs::read_to_string(root.path().join("hyprsunset.conf")).unwrap();
        assert_eq!(text.matches("profile {").count(), 2);
        let state = night.set(SCHEDULE, "false").unwrap();
        assert_eq!(state["schedule"], false);
        assert_eq!(state["enabled"], true);
        assert_eq!(state["saved"]["enabled"], true);
    }

    #[test]
    fn conflict_is_preserved_until_either_resolution() {
        let (root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        let path = root.path().join("hyprsunset.conf");
        let edited = WARM.replace("2600", "4000");
        fs::write(&path, &edited).unwrap();
        night.refresh().unwrap();
        assert_eq!(night.state()["conflict"], true);
        assert!(night.set(TEMPERATURE, "3000").is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), edited);

        // A failed application must keep the conflict visible.
        fake.0.lock().unwrap().fail_restart = true;
        assert!(night.resolve("settings").is_err());
        fake.0.lock().unwrap().fail_restart = false;
        assert_eq!(fs::read_to_string(&path).unwrap(), edited);
        assert_eq!(night.state()["conflict"], true);
        assert!(night.state()["error"].is_string());

        let state = night.resolve("settings").unwrap();
        assert_eq!(state["conflict"], false);
        assert_eq!(state["system"]["temperature"], 2600);

        fs::write(&path, &edited).unwrap();
        let state = night.resolve("system").unwrap();
        assert_eq!(state["conflict"], false);
        assert_eq!(state["saved"]["temperature"], 4000);
    }

    #[test]
    fn live_changes_are_not_a_conflict() {
        let (_root, fake, mut night) = manager(Some(WARM));
        night.refresh().unwrap();
        fake.0.lock().unwrap().identity = true;
        night.refresh().unwrap();
        let state = night.state();
        assert_eq!(state["enabled"], false);
        assert_eq!(state["conflict"], false);
    }

    #[test]
    fn stopped_hyprsunset_is_reported_and_started_by_a_write() {
        let (_root, fake, mut night) = manager(Some(WARM));
        fake.0.lock().unwrap().down = true;
        night.refresh().unwrap();
        assert_eq!(night.state()["running"], false);
        assert_eq!(night.state()["enabled"], false);
        let state = night.set(TEMPERATURE, "3000").unwrap();
        assert_eq!(state["running"], true);
    }
}
