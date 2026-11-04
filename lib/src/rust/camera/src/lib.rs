//! Camera configuration owned by the ordinary-user service.
pub mod native;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::BTreeMap, fs, path::PathBuf};

pub const FIELDS: [&str; 4] = ["brightness", "contrast", "saturation", "sharpness"];
pub fn is_setting(id: &str) -> bool {
    id.strip_prefix("cameras.")
        .is_some_and(|s| FIELDS.contains(&s) || ["devices", "reset"].contains(&s))
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Control {
    pub value: f64,
    pub min: f64,
    pub max: f64,
    pub step: f64,
    pub default: f64,
    pub writable: bool,
}
impl Control {
    pub fn validate(&self, value: f64) -> Result<(), String> {
        if !self.writable
            || !value.is_finite()
            || value < self.min
            || value > self.max
            || (self.step > 0.
                && ((value - self.min) / self.step - ((value - self.min) / self.step).round())
                    .abs()
                    > 0.0001)
        {
            return Err("InvalidArgument:Unsupported camera value or read-only control".into());
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Camera {
    pub name: String,
    pub serial: u64,
    pub description: String,
    pub framerate: Option<(u32, u32)>,
    pub controls: BTreeMap<String, Control>,
}
pub trait Backend: Send {
    fn read(&mut self) -> Result<Vec<Camera>, String>;
    fn write(&mut self, camera: &Camera, values: &BTreeMap<String, f64>) -> Result<(), String>;
}
type Preferences = BTreeMap<String, BTreeMap<String, f64>>;
#[derive(Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u32,
    cameras: Preferences,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    camera: String,
    serial: u64,
    value: Option<f64>,
}
pub struct Cameras<B> {
    backend: B,
    path: PathBuf,
    saved: Preferences,
    cameras: Vec<Camera>,
    error: Option<String>,
    operation_error: Option<String>,
    initialized: bool,
}
impl<B: Backend> Cameras<B> {
    pub fn new(backend: B, path: PathBuf) -> Self {
        Self {
            backend,
            path,
            saved: Default::default(),
            cameras: vec![],
            error: None,
            operation_error: None,
            initialized: false,
        }
    }
    fn save(&mut self, cameras: Preferences) -> Result<(), String> {
        let text = toml::to_string(&Config {
            version: 1,
            cameras: cameras.clone(),
        })
        .map_err(|e| e.to_string())?;
        remya_settings_display::atomic_write(&self.path, text.as_bytes())?;
        self.saved = cameras;
        self.initialized = true;
        Ok(())
    }
    fn detect(&mut self) -> Result<(), String> {
        let cameras = self.backend.read()?;
        let mut names = std::collections::BTreeSet::new();
        if cameras
            .iter()
            .any(|c| c.name.is_empty() || !names.insert(&c.name))
        {
            return Err("Ambiguous camera identity".into());
        }
        self.cameras = cameras;
        let mut saved = match fs::read_to_string(&self.path) {
            Ok(text) => {
                let config: Config = toml::from_str(&text)
                    .map_err(|e| format!("Invalid camera configuration: {e}"))?;
                if config.version != 1
                    || config.cameras.values().any(|p| {
                        p.iter()
                            .any(|(k, v)| !FIELDS.contains(&k.as_str()) || !v.is_finite())
                    })
                {
                    return Err("Invalid camera configuration".into());
                }
                config.cameras
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Default::default(),
            Err(e) => return Err(e.to_string()),
        };
        let before = saved.clone();
        for camera in &self.cameras {
            let prefs = saved.entry(camera.name.clone()).or_default();
            for (field, control) in &camera.controls {
                if control.writable {
                    prefs.entry(field.clone()).or_insert(control.value);
                }
            }
        }
        if saved != before || !self.path.exists() {
            self.save(saved)?;
        } else {
            self.saved = saved;
            self.initialized = true;
        }
        Ok(())
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.detect();
        self.error = result.as_ref().err().cloned();
        result
    }
    fn conflicts(&self, camera: &Camera) -> bool {
        camera.controls.iter().any(|(field, c)| {
            self.saved
                .get(&camera.name)
                .and_then(|p| p.get(field))
                .is_some_and(|v| (v - c.value).abs() > 0.0001)
        })
    }
    pub fn state(&self) -> Value {
        json!({"api_version":1,"available":self.initialized && self.error.is_none(),"initialized":self.initialized,
            "devices":self.cameras,"saved":self.saved,"conflicts":self.cameras.iter().filter(|c| self.conflicts(c)).map(|c| &c.name).collect::<Vec<_>>(),
            "error":self.error.as_ref().or(self.operation_error.as_ref())})
    }
    fn apply(&mut self, camera: &Camera, values: BTreeMap<String, f64>) -> Result<(), String> {
        if values.is_empty() {
            return Err("Unavailable:This camera has no adjustable controls".into());
        }
        for (field, value) in &values {
            camera
                .controls
                .get(field)
                .ok_or("Unavailable:Camera does not support this control")?
                .validate(*value)?;
        }
        self.backend.write(camera, &values)?;
        self.cameras = self.backend.read()?;
        let observed = self
            .cameras
            .iter()
            .find(|c| c.name == camera.name && c.serial == camera.serial)
            .ok_or("Camera disconnected during the change")?;
        if values.iter().any(|(field, v)| {
            observed
                .controls
                .get(field)
                .is_none_or(|c| (c.value - v).abs() > 0.0001)
        }) {
            return Err("Camera readback did not match the requested change".into());
        }
        let mut saved = self.saved.clone();
        saved.entry(camera.name.clone()).or_default().extend(values);
        self.save(saved)
    }
    fn attempt(
        &mut self,
        action: impl FnOnce(&mut Self) -> Result<(), String>,
    ) -> Result<Value, String> {
        let result = action(self);
        self.operation_error = result.as_ref().err().cloned();
        result.map(|()| self.state())
    }
    pub fn set(&mut self, id: &str, text: &str) -> Result<Value, String> {
        self.attempt(|s| {
            if id == "cameras.devices" {
                return Err("ReadOnly:Camera inventory".into());
            }
            let request: Request =
                serde_json::from_str(text).map_err(|e| format!("InvalidArgument:{e}"))?;
            s.refresh()?;
            let camera = s
                .cameras
                .iter()
                .find(|c| c.name == request.camera && c.serial == request.serial)
                .cloned()
                .ok_or("Camera identity changed; refresh the device list")?;
            if s.conflicts(&camera) {
                return Err("Conflict:Resolve the camera configuration first".into());
            }
            let values = if id == "cameras.reset" {
                if request.value.is_some() {
                    return Err("InvalidArgument:Reset does not accept value".into());
                }
                camera
                    .controls
                    .iter()
                    .filter(|(_, c)| c.writable)
                    .map(|(k, c)| (k.clone(), c.default))
                    .collect()
            } else {
                let field = id
                    .strip_prefix("cameras.")
                    .filter(|f| FIELDS.contains(f))
                    .ok_or("InvalidArgument:Unknown camera setting")?;
                BTreeMap::from([(
                    field.into(),
                    request.value.ok_or("InvalidArgument:value is required")?,
                )])
            };
            s.apply(&camera, values)
        })
    }
    pub fn resolve(&mut self, name: &str, source: &str) -> Result<Value, String> {
        self.attempt(|s| {
            if !["system", "settings"].contains(&source) {
                return Err("InvalidArgument:Use system or settings".into());
            }
            s.refresh()?;
            let camera = s
                .cameras
                .iter()
                .find(|c| c.name == name)
                .cloned()
                .ok_or("Camera is no longer available")?;
            if source == "settings" {
                let values = s
                    .saved
                    .get(name)
                    .ok_or("Camera has no saved configuration")?
                    .iter()
                    .filter(|(k, _)| camera.controls.contains_key(*k))
                    .map(|(k, v)| (k.clone(), *v))
                    .collect();
                s.apply(&camera, values)
            } else {
                let mut saved = s.saved.clone();
                saved.insert(
                    name.into(),
                    camera
                        .controls
                        .iter()
                        .filter(|(_, c)| c.writable)
                        .map(|(k, c)| (k.clone(), c.value))
                        .collect(),
                );
                s.save(saved)
            }
        })
    }
}

#[cfg(feature = "preview")]
pub mod api;
#[cfg(feature = "preview")]
mod frb_generated;

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Clone)]
    struct Fake {
        cameras: Vec<Camera>,
        fail_read: bool,
        ignore_write: bool,
        writes: usize,
    }
    impl Backend for Fake {
        fn read(&mut self) -> Result<Vec<Camera>, String> {
            if self.fail_read {
                Err("Detection failed".into())
            } else {
                Ok(self.cameras.clone())
            }
        }
        fn write(&mut self, camera: &Camera, values: &BTreeMap<String, f64>) -> Result<(), String> {
            self.writes += 1;
            if !self.ignore_write {
                for (k, v) in values {
                    self.cameras
                        .iter_mut()
                        .find(|c| c.serial == camera.serial)
                        .unwrap()
                        .controls
                        .get_mut(k)
                        .unwrap()
                        .value = *v;
                }
            }
            Ok(())
        }
    }
    fn setup() -> (tempfile::TempDir, Cameras<Fake>) {
        let dir = tempfile::tempdir().unwrap();
        let backend = Fake {
            cameras: vec![Camera {
                name: "camera".into(),
                serial: 1,
                description: "Camera".into(),
                framerate: None,
                controls: BTreeMap::from([(
                    "brightness".into(),
                    Control {
                        value: 2.,
                        min: 0.,
                        max: 10.,
                        step: 1.,
                        default: 5.,
                        writable: true,
                    },
                )]),
            }],
            fail_read: false,
            ignore_write: false,
            writes: 0,
        };
        let manager = Cameras::new(backend, dir.path().join("cameras.toml"));
        (dir, manager)
    }
    #[test]
    fn initializes_without_writes_and_resolves_both_ways() {
        let (_dir, mut m) = setup();
        m.refresh().unwrap();
        assert_eq!(m.backend.writes, 0);
        m.backend.cameras[0]
            .controls
            .get_mut("brightness")
            .unwrap()
            .value = 4.;
        m.refresh().unwrap();
        assert!(m.conflicts(&m.cameras[0]));
        assert_eq!(m.saved["camera"]["brightness"], 2.);
        m.resolve("camera", "system").unwrap();
        assert_eq!(m.saved["camera"]["brightness"], 4.);
        m.backend.cameras[0]
            .controls
            .get_mut("brightness")
            .unwrap()
            .value = 7.;
        m.resolve("camera", "settings").unwrap();
        assert_eq!(m.cameras[0].controls["brightness"].value, 4.);
        m.set("cameras.reset", r#"{"camera":"camera","serial":1}"#)
            .unwrap();
        assert_eq!(m.saved["camera"]["brightness"], 5.);
    }
    #[test]
    fn rejects_stale_identity_unsupported_fields_and_bad_values() {
        let (_dir, mut m) = setup();
        m.refresh().unwrap();
        for (id, body) in [
            ("brightness", r#"{"camera":"camera","serial":2,"value":3}"#),
            ("contrast", r#"{"camera":"camera","serial":1,"value":3}"#),
            (
                "brightness",
                r#"{"camera":"camera","serial":1,"value":3.5}"#,
            ),
            ("brightness", r#"{"camera":"camera","serial":1,"value":11}"#),
        ] {
            assert!(m.set(&format!("cameras.{id}"), body).is_err());
        }
        assert_eq!(m.backend.writes, 0);
    }
    #[test]
    fn readback_detection_and_persistence_failures_preserve_saved_values() {
        let (dir, mut m) = setup();
        m.refresh().unwrap();
        let original = fs::read(&m.path).unwrap();
        m.backend.ignore_write = true;
        assert!(
            m.set(
                "cameras.brightness",
                r#"{"camera":"camera","serial":1,"value":3}"#
            )
            .is_err()
        );
        m.refresh().unwrap();
        assert!(m.state()["error"].is_string());
        assert_eq!(fs::read(&m.path).unwrap(), original);
        m.backend.fail_read = true;
        assert!(m.refresh().is_err());
        assert_eq!(m.saved["camera"]["brightness"], 2.);
        m.backend.fail_read = false;
        fs::write(&m.path, "invalid").unwrap();
        assert!(m.refresh().is_err());
        assert_eq!(m.saved["camera"]["brightness"], 2.);
        fs::write(&m.path, original).unwrap();
        m.refresh().unwrap();
        fs::remove_file(&m.path).unwrap();
        fs::create_dir(&m.path).unwrap();
        assert!(m.resolve("camera", "system").is_err());
        assert!(dir.path().exists());
    }
    #[test]
    fn unplugged_devices_keep_saved_preferences() {
        let (_dir, mut m) = setup();
        m.refresh().unwrap();
        m.backend.cameras.clear();
        m.refresh().unwrap();
        assert_eq!(m.saved["camera"]["brightness"], 2.);
        assert!(m.state()["conflicts"].as_array().unwrap().is_empty());
    }
}
