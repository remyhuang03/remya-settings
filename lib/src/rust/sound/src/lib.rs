//! Per-user audio through PipeWire's PulseAudio protocol; no privileged process or shell commands.
pub mod pulse;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

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
        operation: &str,
    ) -> Result<(), String>;
    fn set_stream(&mut self, stream: &Stream, operation: &str) -> Result<(), String>;
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
    actual: Option<Snapshot>,
    error: Option<String>,
    operation_error: Option<String>,
}
impl<B: Backend> Sound<B> {
    pub fn new(backend: B) -> Self {
        Self {
            backend,
            actual: None,
            error: None,
            operation_error: None,
        }
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self
            .backend
            .read()
            .map(|snapshot| self.actual = Some(snapshot));
        self.error = result.as_ref().err().cloned();
        result
    }
    pub fn state(&self) -> Value {
        json!({"api_version":1,"available":self.actual.is_some() && self.error.is_none(),"system":self.actual,"error":self.error.as_ref().or(self.operation_error.as_ref())})
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
        let change: Change = serde_json::from_str(text).map_err(|e| invalid(&e.to_string()))?;
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
            let matches = match id {
                "sound.stream-volume" => {
                    observed.preferences.channels == stream.preferences.channels
                }
                "sound.stream-muted" => observed.preferences.muted == stream.preferences.muted,
                "sound.stream-device" => observed.device == stream.device,
                _ => unreachable!(),
            };
            if !matches {
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
            self.actual = Some(self.backend.read()?);
            let observed = self.actual.as_ref().unwrap();
            let selected = match direction {
                Direction::Output => &observed.default_output,
                Direction::Input => &observed.default_input,
            };
            if selected.as_deref() != Some(&name) {
                return Err("Sound readback did not match the requested device".into());
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
            self.backend.set_device(direction, &name, &prefs, id)?;
            self.actual = Some(self.backend.read()?);
            let observed = self
                .actual
                .as_ref()
                .unwrap()
                .devices
                .iter()
                .find(|d| d.name == name && d.direction == direction)
                .ok_or("Audio device disappeared during the change")?;
            let matches = if id.ends_with("-volume") {
                observed.preferences.channels == prefs.channels
            } else {
                observed.preferences.muted == prefs.muted
            };
            if !matches {
                return Err("Sound readback did not match the requested change".into());
            }
        }
        Ok(())
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
        churn: Arc<Mutex<bool>>,
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
                if *self.churn.lock().unwrap() {
                    s.devices[0].preferences.muted = !s.devices[0].preferences.muted;
                }
            }
            Ok(())
        }
        fn set_device(
            &mut self,
            direction: Direction,
            name: &str,
            prefs: &DevicePrefs,
            operation: &str,
        ) -> Result<(), String> {
            *self.writes.lock().unwrap() += 1;
            if *self.fail.lock().unwrap() {
                return Err("write denied".into());
            }
            if !*self.ignore.lock().unwrap() {
                let mut state = self.state.lock().unwrap();
                let device = state
                    .devices
                    .iter_mut()
                    .find(|d| d.name == name && d.direction == direction)
                    .unwrap();
                if operation.ends_with("-volume") {
                    device.preferences.channels = prefs.channels.clone();
                    if *self.churn.lock().unwrap() {
                        device.preferences.muted = !prefs.muted;
                    }
                } else {
                    device.preferences.muted = prefs.muted;
                    if *self.churn.lock().unwrap() {
                        device.preferences.channels = vec![12345];
                    }
                }
                if *self.churn.lock().unwrap() {
                    state.default_input = None;
                }
            }
            Ok(())
        }
        fn set_stream(&mut self, stream: &Stream, operation: &str) -> Result<(), String> {
            *self.writes.lock().unwrap() += 1;
            if *self.fail.lock().unwrap() {
                return Err("write denied".into());
            }
            if !*self.ignore.lock().unwrap() {
                let mut state = self.state.lock().unwrap();
                let observed = state
                    .streams
                    .iter_mut()
                    .find(|s| s.index == stream.index)
                    .unwrap();
                *observed = stream.clone();
                if *self.churn.lock().unwrap() {
                    match operation {
                        "sound.stream-volume" => {
                            observed.preferences.muted = !stream.preferences.muted
                        }
                        "sound.stream-muted" => observed.device = "another-device".into(),
                        "sound.stream-device" => observed.preferences.channels = vec![12345],
                        _ => unreachable!(),
                    }
                }
            }
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
            churn: Arc::default(),
        }
    }
    #[test]
    fn failed_detection_keeps_last_readback_and_disables_controls() {
        let backend = fake();
        *backend.read_fail.lock().unwrap() = true;
        let mut sound = Sound::new(backend.clone());
        assert!(sound.refresh().is_err());
        assert_eq!(sound.state()["available"], false);
        assert!(sound.state()["system"].is_null());
        *backend.read_fail.lock().unwrap() = false;
        sound.refresh().unwrap();
        let last = sound.state()["system"].clone();
        *backend.read_fail.lock().unwrap() = true;
        assert!(sound.refresh().is_err());
        assert_eq!(sound.state()["available"], false);
        assert_eq!(sound.state()["system"], last);
        assert_eq!(*backend.writes.lock().unwrap(), 0);
    }
    #[test]
    fn external_changes_and_device_inventory_are_live_across_restarts() {
        let backend = fake();
        let mut sound = Sound::new(backend.clone());
        sound.refresh().unwrap();
        for key in ["saved", "conflict", "initialized"] {
            assert!(sound.state().get(key).is_none());
        }
        {
            let mut state = backend.state.lock().unwrap();
            for device in &mut state.devices {
                device.preferences.channels.fill(16384);
                device.preferences.muted = true;
            }
            state.default_output = None;
            state.default_input = None;
            state.devices.remove(0);
            let mut added = state.devices[0].clone();
            added.name = "headset".into();
            state.devices.push(added);
        }
        sound.refresh().unwrap();
        let actual = serde_json::to_value(backend.state.lock().unwrap().clone()).unwrap();
        assert_eq!(sound.state()["system"], actual);
        assert_eq!(*backend.writes.lock().unwrap(), 0);
        let mut restarted = Sound::new(backend.clone());
        restarted.refresh().unwrap();
        assert_eq!(restarted.state()["system"], actual);
        assert_eq!(*backend.writes.lock().unwrap(), 0);
        restarted
            .set(
                "sound.device-volume",
                r#"{"direction":"input","name":"headset","percent":20}"#,
            )
            .unwrap();
        assert!(restarted.state()["error"].is_null());
    }
    #[test]
    fn volume_preserves_balance_and_failures_remain_visible() {
        let backend = fake();
        let mut sound = Sound::new(backend.clone());
        sound
            .set("sound.output-volume", r#"{"percent":50}"#)
            .unwrap();
        assert_eq!(
            backend.state.lock().unwrap().devices[0]
                .preferences
                .channels,
            vec![32768, 16384]
        );
        *backend.fail.lock().unwrap() = true;
        assert!(
            sound
                .set("sound.output-muted", r#"{"muted":true}"#)
                .is_err()
        );
        assert!(sound.state()["error"].as_str().unwrap().contains("denied"));
        *backend.fail.lock().unwrap() = false;
        *backend.ignore.lock().unwrap() = true;
        for (id, text) in [
            ("sound.output-volume", r#"{"percent":25}"#),
            ("sound.output-muted", r#"{"muted":true}"#),
            ("sound.output-device", r#"{"name":"microphone"}"#),
            (
                "sound.stream-volume",
                r#"{"direction":"output","index":3,"client":4,"percent":25}"#,
            ),
            (
                "sound.stream-muted",
                r#"{"direction":"output","index":3,"client":4,"muted":true}"#,
            ),
        ] {
            // The default-device case needs another connected output.
            if id == "sound.output-device" {
                let mut extra = snapshot().devices[0].clone();
                extra.name = "microphone".into();
                backend.state.lock().unwrap().devices.push(extra);
            }
            assert!(
                sound.set(id, text).unwrap_err().contains("readback"),
                "{id}"
            );
        }
    }
    #[test]
    fn readback_checks_only_the_requested_field() {
        let backend = fake();
        *backend.churn.lock().unwrap() = true;
        let mut sound = Sound::new(backend);
        for (id, text) in [
            ("sound.output-device", r#"{"name":"speakers"}"#),
            ("sound.output-volume", r#"{"percent":25}"#),
            ("sound.output-muted", r#"{"muted":true}"#),
            (
                "sound.stream-volume",
                r#"{"direction":"output","index":3,"client":4,"percent":25}"#,
            ),
            (
                "sound.stream-muted",
                r#"{"direction":"output","index":3,"client":4,"muted":true}"#,
            ),
            (
                "sound.stream-device",
                r#"{"direction":"output","index":3,"client":4,"device":"speakers"}"#,
            ),
        ] {
            sound.set(id, text).unwrap();
        }
    }
    #[test]
    fn stale_streams_and_invalid_values_fail() {
        let backend = fake();
        let mut sound = Sound::new(backend.clone());
        sound
            .set(
                "sound.stream-volume",
                r#"{"direction":"output","index":3,"client":4,"percent":25}"#,
            )
            .unwrap();
        for (id, text) in [
            (
                "sound.stream-volume",
                r#"{"direction":"output","index":3,"client":9,"percent":25}"#,
            ),
            ("sound.output-volume", r#"{"percent":151}"#),
            ("sound.output-volume", r#"{"percent":-1}"#),
            ("sound.output-device", r#"{"name":"missing"}"#),
            ("sound.output-muted", r#"{"muted":true,"unknown":true}"#),
        ] {
            assert!(sound.set(id, text).is_err(), "{id}: {text}");
        }
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
    fn automatic_readback_retains_failed_operation_until_explicit_retry() {
        let backend = fake();
        let mut sound = Sound::new(backend.clone());
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
