//! Per-user audio through PipeWire's PulseAudio protocol; no privileged process or shell commands.
pub mod pulse;

use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::BTreeMap, fs, path::PathBuf};

pub const IDS: [&str; 12] = [
    "sound.output-device",
    "sound.output-volume",
    "sound.output-muted",
    "sound.input-device",
    "sound.input-volume",
    "sound.input-muted",
    "sound.device-volume",
    "sound.device-muted",
    "sound.stream-volume",
    "sound.stream-muted",
    "sound.stream-device",
    "sound.refresh",
];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id) || ["sound.devices", "sound.streams"].contains(&id)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Output,
    Input,
}
impl Direction {
    fn key(self) -> &'static str {
        match self {
            Self::Output => "output",
            Self::Input => "input",
        }
    }
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DevicePrefs {
    pub channels: Vec<u32>,
    pub muted: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Device {
    pub name: String,
    pub index: u32,
    pub description: String,
    pub direction: Direction,
    pub preferences: DevicePrefs,
    pub rate: u32,
    pub channels: u8,
    pub state: String,
}
impl Device {
    fn key(&self) -> String {
        format!("{}:{}", self.direction.key(), self.name)
    }
    pub fn percent(&self) -> f64 {
        volume_percent(&self.preferences.channels)
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Stream {
    pub index: u32,
    pub client: Option<u32>,
    pub name: String,
    pub application: String,
    pub direction: Direction,
    pub device: String,
    pub preferences: DevicePrefs,
    pub has_volume: bool,
    pub volume_writable: bool,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Snapshot {
    pub default_output: Option<String>,
    pub default_input: Option<String>,
    pub devices: Vec<Device>,
    pub streams: Vec<Stream>,
}
pub fn volume_percent(channels: &[u32]) -> f64 {
    channels.iter().max().copied().unwrap_or(0) as f64 * 100.0 / 65536.0
}
fn scale(channels: &[u32], percent: f64) -> Result<Vec<u32>, String> {
    if !percent.is_finite() || !(0.0..=150.0).contains(&percent) {
        return Err(invalid("Volume must be between 0 and 150 percent"));
    }
    let max = channels.iter().max().copied().unwrap_or(0);
    let wanted = (percent * 65536.0 / 100.0).round() as u32;
    Ok(channels
        .iter()
        .map(|v| {
            if max == 0 {
                wanted
            } else {
                (*v as f64 * wanted as f64 / max as f64).round() as u32
            }
        })
        .collect())
}
pub trait Backend: Send {
    fn read(&mut self) -> Result<Snapshot, String>;
    fn set_default(&mut self, direction: Direction, name: &str) -> Result<(), String>;
    fn set_device(
        &mut self,
        direction: Direction,
        name: &str,
        prefs: &DevicePrefs,
    ) -> Result<(), String>;
    fn set_stream(&mut self, stream: &Stream, operation: &str) -> Result<(), String>;
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Saved {
    version: u8,
    default_output: Option<String>,
    default_input: Option<String>,
    devices: BTreeMap<String, DevicePrefs>,
}
impl Saved {
    fn from_snapshot(snapshot: &Snapshot) -> Self {
        Self {
            version: 1,
            default_output: snapshot.default_output.clone(),
            default_input: snapshot.default_input.clone(),
            devices: snapshot
                .devices
                .iter()
                .map(|d| (d.key(), d.preferences.clone()))
                .collect(),
        }
    }
    fn differs(&self, actual: &Snapshot) -> bool {
        self.default_output != actual.default_output
            || self.default_input != actual.default_input
            || actual.devices.iter().any(|d| {
                self.devices
                    .get(&d.key())
                    .is_some_and(|p| p != &d.preferences)
            })
    }
    fn validate(&self) -> Result<(), String> {
        if self.version != 1
            || self.devices.values().any(|p| {
                p.channels.is_empty()
                    || p.channels.len() > 32
                    || p.channels.iter().any(|v| *v > 0x7fff_ffff)
            })
        {
            return Err("Invalid sound preferences".into());
        }
        Ok(())
    }
}
fn invalid(s: &str) -> String {
    format!("InvalidArgument:{s}")
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Change {
    direction: Option<Direction>,
    name: Option<String>,
    index: Option<u32>,
    client: Option<u32>,
    percent: Option<f64>,
    muted: Option<bool>,
    device: Option<String>,
}
pub struct Sound<B: Backend> {
    backend: B,
    file: PathBuf,
    saved: Option<Saved>,
    actual: Option<Snapshot>,
    error: Option<String>,
    operation_error: Option<String>,
    load_error: Option<String>,
}
impl<B: Backend> Sound<B> {
    pub fn new(backend: B, file: PathBuf) -> Self {
        let loaded = match fs::read_to_string(&file) {
            Ok(s) => toml::from_str::<Saved>(&s)
                .map(Some)
                .map_err(|e| e.to_string()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e.to_string()),
        }
        .and_then(|s| {
            if let Some(v) = &s {
                v.validate()?;
            }
            Ok(s)
        });
        let (saved, load_error) = match loaded {
            Ok(v) => (v, None),
            Err(e) => (None, Some(e)),
        };
        Self {
            backend,
            file,
            saved,
            actual: None,
            error: None,
            operation_error: None,
            load_error,
        }
    }
    fn save(&mut self, next: Saved) -> Result<(), String> {
        next.validate()?;
        atomic_write(
            &self.file,
            toml::to_string(&next)
                .map_err(|e| e.to_string())?
                .as_bytes(),
        )?;
        self.saved = Some(next);
        self.load_error = None;
        Ok(())
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = (|| {
            let snapshot = self.backend.read()?;
            self.actual = Some(snapshot.clone());
            if let Some(error) = &self.load_error {
                return Err(error.clone());
            }
            if self.saved.is_none() {
                self.save(Saved::from_snapshot(&snapshot))?;
            }
            Ok(())
        })();
        self.error = result.as_ref().err().cloned();
        result
    }
    pub fn state(&self) -> Value {
        let conflict = self
            .saved
            .as_ref()
            .zip(self.actual.as_ref())
            .is_some_and(|(s, a)| s.differs(a));
        json!({"api_version":1,"available":self.actual.is_some(),"initialized":self.saved.is_some(),"system":self.actual,"saved":self.saved,"conflict":conflict,"error":self.error.as_ref().or(self.operation_error.as_ref())})
    }
    fn write(&mut self, id: &str, text: &str) -> Result<(), String> {
        if id == "sound.refresh" {
            return self.refresh();
        }
        self.refresh()?;
        let stream_change = id.starts_with("sound.stream-");
        let actual = self
            .actual
            .as_ref()
            .ok_or("Sound service unavailable")?
            .clone();
        if !stream_change && self.saved.as_ref().is_some_and(|s| s.differs(&actual)) {
            return Err(
                "Conflict: Sound differs from saved Settings; choose which configuration to use"
                    .into(),
            );
        }
        let change: Change = serde_json::from_str(text).map_err(|e| invalid(&e.to_string()))?;
        let mut next = self
            .saved
            .clone()
            .ok_or("Sound configuration is not initialized")?;
        let direction = if id.starts_with("sound.output-") {
            Direction::Output
        } else if id.starts_with("sound.input-") {
            Direction::Input
        } else {
            change
                .direction
                .ok_or_else(|| invalid("direction is required"))?
        };
        if stream_change {
            let mut stream = actual
                .streams
                .iter()
                .find(|s| {
                    s.index == change.index.unwrap_or(u32::MAX)
                        && s.client == change.client
                        && s.direction == direction
                })
                .cloned()
                .ok_or("The audio stream has ended or changed; refresh the mixer")?;
            if id == "sound.stream-device" {
                let name = change.device.ok_or_else(|| invalid("device is required"))?;
                if !actual
                    .devices
                    .iter()
                    .any(|d| d.name == name && d.direction == direction)
                {
                    return Err("Audio device is no longer available".into());
                }
                stream.device = name;
            } else if id == "sound.stream-muted" {
                stream.preferences.muted =
                    change.muted.ok_or_else(|| invalid("muted is required"))?;
            } else if id == "sound.stream-volume" {
                if !stream.has_volume || !stream.volume_writable {
                    return Err("This stream does not allow volume changes".into());
                }
                stream.preferences.channels = scale(
                    &stream.preferences.channels,
                    change
                        .percent
                        .ok_or_else(|| invalid("percent is required"))?,
                )?;
            } else {
                return Err(invalid("Unknown sound operation"));
            }
            self.backend.set_stream(&stream, id)?;
            self.actual = Some(self.backend.read()?);
            let observed = self
                .actual
                .as_ref()
                .unwrap()
                .streams
                .iter()
                .find(|s| {
                    s.index == stream.index
                        && s.client == stream.client
                        && s.direction == stream.direction
                })
                .ok_or("The audio stream ended during the change")?;
            if observed.preferences != stream.preferences || observed.device != stream.device {
                return Err("Audio stream readback did not match the requested change".into());
            }
            return Ok(());
        }
        if id.ends_with("-device") {
            let name = change.name.ok_or_else(|| invalid("name is required"))?;
            if !actual
                .devices
                .iter()
                .any(|d| d.name == name && d.direction == direction)
            {
                return Err("Audio device is no longer available".into());
            }
            self.backend.set_default(direction, &name)?;
            match direction {
                Direction::Output => next.default_output = Some(name),
                Direction::Input => next.default_input = Some(name),
            }
        } else {
            let name = change
                .name
                .or_else(|| match direction {
                    Direction::Output => actual.default_output.clone(),
                    Direction::Input => actual.default_input.clone(),
                })
                .ok_or("No audio device is selected")?;
            let device = actual
                .devices
                .iter()
                .find(|d| d.name == name && d.direction == direction)
                .ok_or("Audio device is no longer available")?;
            let mut prefs = device.preferences.clone();
            if id.ends_with("-volume") {
                prefs.channels = scale(
                    &prefs.channels,
                    change
                        .percent
                        .ok_or_else(|| invalid("percent is required"))?,
                )?;
            } else if id.ends_with("-muted") {
                prefs.muted = change.muted.ok_or_else(|| invalid("muted is required"))?;
            } else {
                return Err(invalid("Unknown sound operation"));
            }
            self.backend.set_device(direction, &name, &prefs)?;
            next.devices.insert(device.key(), prefs);
        }
        self.actual = Some(self.backend.read()?);
        if next.differs(self.actual.as_ref().unwrap()) {
            return Err("Sound readback did not match the requested change".into());
        }
        self.save(next)
    }
    pub fn set(&mut self, id: &str, text: &str) -> Result<Value, String> {
        if text.len() > 4096 {
            return Err(invalid("Audio request exceeds 4096 bytes"));
        }
        if !is_setting(id) {
            return Err(invalid("Unknown sound operation"));
        }
        if ["sound.devices", "sound.streams"].contains(&id) {
            return Err("ReadOnly:Audio inventory is read-only".into());
        }
        let result = self.write(id, text);
        self.operation_error = result.as_ref().err().cloned();
        result.map(|_| self.state())
    }
    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let result = (|| {
            let actual = self.backend.read()?;
            self.actual = Some(actual.clone());
            match source {
                "system" => self.save(Saved::from_snapshot(&actual))?,
                "settings" => {
                    let saved = self.saved.clone().ok_or("No saved sound preferences")?;
                    for (direction, name) in [
                        (Direction::Output, &saved.default_output),
                        (Direction::Input, &saved.default_input),
                    ] {
                        if let Some(name) = name {
                            if !actual
                                .devices
                                .iter()
                                .any(|d| d.name == *name && d.direction == direction)
                            {
                                return Err(format!(
                                    "Saved {} device is no longer connected",
                                    direction.key()
                                ));
                            }
                            self.backend.set_default(direction, name)?;
                        }
                    }
                    for device in &actual.devices {
                        if let Some(prefs) = saved.devices.get(&device.key()) {
                            if prefs.channels.len() != device.preferences.channels.len() {
                                return Err(
                                    "Saved channel layout no longer matches this device".into()
                                );
                            }
                            self.backend
                                .set_device(device.direction, &device.name, prefs)?;
                        }
                    }
                    self.actual = Some(self.backend.read()?);
                    if saved.differs(self.actual.as_ref().unwrap()) {
                        return Err("Sound readback did not match saved Settings".into());
                    }
                }
                _ => return Err(invalid("Choose system or settings")),
            }
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        if result.is_ok() {
            self.error = None;
        }
        result.map(|_| self.state())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    #[derive(Clone)]
    struct Fake {
        state: Arc<Mutex<Snapshot>>,
        writes: Arc<Mutex<usize>>,
        fail: Arc<Mutex<bool>>,
        read_fail: Arc<Mutex<bool>>,
        ignore: Arc<Mutex<bool>>,
    }
    impl Backend for Fake {
        fn read(&mut self) -> Result<Snapshot, String> {
            if *self.read_fail.lock().unwrap() {
                return Err("audio server stopped".into());
            }
            Ok(self.state.lock().unwrap().clone())
        }
        fn set_default(&mut self, direction: Direction, name: &str) -> Result<(), String> {
            *self.writes.lock().unwrap() += 1;
            if *self.fail.lock().unwrap() {
                return Err("write denied".into());
            }
            if !*self.ignore.lock().unwrap() {
                let mut s = self.state.lock().unwrap();
                match direction {
                    Direction::Output => s.default_output = Some(name.into()),
                    Direction::Input => s.default_input = Some(name.into()),
                }
            }
            Ok(())
        }
        fn set_device(
            &mut self,
            direction: Direction,
            name: &str,
            prefs: &DevicePrefs,
        ) -> Result<(), String> {
            *self.writes.lock().unwrap() += 1;
            if *self.fail.lock().unwrap() {
                return Err("write denied".into());
            }
            if !*self.ignore.lock().unwrap() {
                self.state
                    .lock()
                    .unwrap()
                    .devices
                    .iter_mut()
                    .find(|d| d.name == name && d.direction == direction)
                    .unwrap()
                    .preferences = prefs.clone();
            }
            Ok(())
        }
        fn set_stream(&mut self, stream: &Stream, _operation: &str) -> Result<(), String> {
            *self.writes.lock().unwrap() += 1;
            if *self.fail.lock().unwrap() {
                return Err("write denied".into());
            }
            *self
                .state
                .lock()
                .unwrap()
                .streams
                .iter_mut()
                .find(|s| s.index == stream.index)
                .unwrap() = stream.clone();
            Ok(())
        }
    }
    fn snapshot() -> Snapshot {
        Snapshot {
            default_output: Some("speakers".into()),
            default_input: Some("microphone".into()),
            devices: vec![
                Device {
                    name: "speakers".into(),
                    index: 1,
                    description: "Speakers".into(),
                    direction: Direction::Output,
                    preferences: DevicePrefs {
                        channels: vec![65536, 32768],
                        muted: false,
                    },
                    rate: 48000,
                    channels: 2,
                    state: "Running".into(),
                },
                Device {
                    name: "microphone".into(),
                    index: 2,
                    description: "Microphone".into(),
                    direction: Direction::Input,
                    preferences: DevicePrefs {
                        channels: vec![65536],
                        muted: false,
                    },
                    rate: 48000,
                    channels: 1,
                    state: "Idle".into(),
                },
            ],
            streams: vec![Stream {
                index: 3,
                client: Some(4),
                name: "Music".into(),
                application: "Player".into(),
                direction: Direction::Output,
                device: "speakers".into(),
                preferences: DevicePrefs {
                    channels: vec![65536, 65536],
                    muted: false,
                },
                has_volume: true,
                volume_writable: true,
            }],
        }
    }
    fn fake() -> Fake {
        Fake {
            state: Arc::new(Mutex::new(snapshot())),
            writes: Arc::default(),
            fail: Arc::default(),
            read_fail: Arc::default(),
            ignore: Arc::default(),
        }
    }
    #[test]
    fn failed_detection_and_malformed_config_never_initialize_or_overwrite() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("sound.toml");
        let backend = fake();
        *backend.read_fail.lock().unwrap() = true;
        let mut sound = Sound::new(backend.clone(), path.clone());
        assert!(sound.refresh().is_err());
        assert!(!path.exists());
        assert_eq!(sound.state()["initialized"], false);
        *backend.read_fail.lock().unwrap() = false;
        fs::write(&path, "bad [").unwrap();
        let mut sound = Sound::new(backend.clone(), path.clone());
        assert!(sound.refresh().is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "bad [");
        assert_eq!(sound.state()["initialized"], false);
        assert_eq!(*backend.writes.lock().unwrap(), 0);
        sound.resolve("system").unwrap();
        let saved = fs::read_to_string(&path).unwrap();
        *backend.read_fail.lock().unwrap() = true;
        assert!(sound.refresh().is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), saved);
        assert!(sound.state()["system"]["devices"].is_array());
    }
    #[test]
    fn initializes_without_writes_and_resolves_both_conflict_directions() {
        let root = tempfile::tempdir().unwrap();
        let backend = fake();
        let mut sound = Sound::new(backend.clone(), root.path().join("sound.toml"));
        sound.refresh().unwrap();
        assert_eq!(*backend.writes.lock().unwrap(), 0);
        assert!(sound.state()["initialized"].as_bool().unwrap());
        backend.state.lock().unwrap().devices[0].preferences.muted = true;
        sound.refresh().unwrap();
        assert_eq!(sound.state()["conflict"], true);
        assert!(
            sound
                .set("sound.output-volume", r#"{"percent":20}"#)
                .unwrap_err()
                .starts_with("Conflict:")
        );
        sound.resolve("system").unwrap();
        assert_eq!(sound.state()["conflict"], false);
        assert_eq!(*backend.writes.lock().unwrap(), 0);
        backend.state.lock().unwrap().devices[0].preferences.muted = false;
        sound.refresh().unwrap();
        sound.resolve("settings").unwrap();
        assert!(backend.state.lock().unwrap().devices[0].preferences.muted);
        assert_eq!(sound.state()["conflict"], false);
    }
    #[test]
    fn volume_preserves_balance_and_failed_writes_keep_the_last_saved_preferences() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("sound.toml");
        let backend = fake();
        let mut sound = Sound::new(backend.clone(), path.clone());
        sound.refresh().unwrap();
        sound
            .set("sound.output-volume", r#"{"percent":50}"#)
            .unwrap();
        assert_eq!(
            backend.state.lock().unwrap().devices[0]
                .preferences
                .channels,
            vec![32768, 16384]
        );
        let saved = fs::read_to_string(&path).unwrap();
        *backend.fail.lock().unwrap() = true;
        assert!(
            sound
                .set("sound.output-muted", r#"{"muted":true}"#)
                .is_err()
        );
        assert_eq!(fs::read_to_string(&path).unwrap(), saved);
        assert!(sound.state()["error"].as_str().unwrap().contains("denied"));
        *backend.fail.lock().unwrap() = false;
        *backend.ignore.lock().unwrap() = true;
        assert!(
            sound
                .set("sound.output-volume", r#"{"percent":25}"#)
                .unwrap_err()
                .contains("readback")
        );
        assert_eq!(fs::read_to_string(path).unwrap(), saved);
    }
    #[test]
    fn transient_stream_changes_do_not_persist_and_stale_streams_and_invalid_values_fail() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("sound.toml");
        let backend = fake();
        let mut sound = Sound::new(backend.clone(), path.clone());
        sound.refresh().unwrap();
        let saved = fs::read_to_string(&path).unwrap();
        sound
            .set(
                "sound.stream-volume",
                r#"{"direction":"output","index":3,"client":4,"percent":25}"#,
            )
            .unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), saved);
        assert!(
            sound
                .set(
                    "sound.stream-volume",
                    r#"{"direction":"output","index":3,"client":9,"percent":25}"#
                )
                .is_err()
        );
        assert!(
            sound
                .set("sound.output-volume", r#"{"percent":151}"#)
                .is_err()
        );
        assert!(
            sound
                .set("sound.output-device", r#"{"name":"missing"}"#)
                .is_err()
        );
        backend.state.lock().unwrap().streams.clear();
        assert!(
            sound
                .set(
                    "sound.stream-muted",
                    r#"{"direction":"output","index":3,"client":4,"muted":true}"#
                )
                .is_err()
        );
    }
    #[test]
    fn persistence_failure_after_write_remains_a_conflict() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("sound.toml");
        let backend = fake();
        let mut sound = Sound::new(backend.clone(), path.clone());
        sound.refresh().unwrap();
        fs::remove_file(&path).unwrap();
        fs::create_dir(&path).unwrap();
        assert!(
            sound
                .set("sound.output-muted", r#"{"muted":true}"#)
                .is_err()
        );
        assert_eq!(sound.state()["conflict"], true);
        assert!(sound.state()["error"].is_string());
    }
    #[test]
    fn automatic_readback_retains_failed_operation_until_explicit_retry() {
        let root = tempfile::tempdir().unwrap();
        let backend = fake();
        let mut sound = Sound::new(backend.clone(), root.path().join("sound.toml"));
        sound.refresh().unwrap();
        *backend.fail.lock().unwrap() = true;
        assert!(
            sound
                .set("sound.output-muted", r#"{"muted":true}"#)
                .is_err()
        );
        sound.refresh().unwrap();
        assert_eq!(sound.state()["error"], "write denied");
        sound.set("sound.refresh", "{}").unwrap();
        assert!(sound.state()["error"].is_null());
    }
}
