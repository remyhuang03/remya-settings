pub mod history;
pub mod idle;
use gio::{
    glib::{Variant, variant::ToVariant},
    prelude::*,
};
use remya_settings_display::{Compositor, Hyprctl, atomic_write, brightness::BrightnessBackend};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::HashMap, path::PathBuf};
const BUS: &str = "org.freedesktop.UPower.PowerProfiles";
const PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
pub const IDS: &[&str] = &[
    "power.5a4f0131",
    "power.5e3af39c",
    "power.8b4c8522",
    "battery-saver.743773bd",
    "battery-saver.9b0caf70",
    "battery-saver.07945503",
    "battery-saver.power-source",
];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}
fn proxy(bus: &str, path: &str, interface: &str) -> Result<gio::DBusProxy, String> {
    let p = gio::DBusProxy::for_bus_sync(
        gio::BusType::System,
        gio::DBusProxyFlags::NONE,
        None,
        bus,
        path,
        interface,
        gio::Cancellable::NONE,
    )
    .map_err(|e| e.to_string())?;
    p.set_default_timeout(5000);
    Ok(p)
}
fn property<T: gio::glib::variant::FromVariant>(
    p: &gio::DBusProxy,
    key: &str,
) -> Result<T, String> {
    p.cached_property(key)
        .and_then(|v| v.get())
        .ok_or_else(|| format!("Missing {key}"))
}
fn profile() -> Result<(String, Vec<String>, String), String> {
    let p = proxy(BUS, PATH, BUS)?;
    let profiles: Vec<HashMap<String, Variant>> = property(&p, "Profiles")?;
    Ok((
        property(&p, "ActiveProfile")?,
        profiles
            .iter()
            .filter_map(|v| v.get("Profile").and_then(|v| v.get::<String>()))
            .collect(),
        property(&p, "PerformanceDegraded")?,
    ))
}
fn set_profile(wanted: &str) -> Result<(), String> {
    let (_, profiles, _) = profile()?;
    if !profiles.iter().any(|p| p == wanted) {
        return Err("Unsupported power profile".into());
    }
    let p = proxy(BUS, PATH, "org.freedesktop.DBus.Properties")?;
    p.call_sync(
        "Set",
        Some(&(BUS, "ActiveProfile", wanted.to_variant()).to_variant()),
        gio::DBusCallFlags::NONE,
        5000,
        gio::Cancellable::NONE,
    )
    .map_err(|e| e.to_string())?;
    if profile()?.0 != wanted {
        return Err("Power profile readback mismatch".into());
    }
    Ok(())
}
fn battery() -> Result<Value, String> {
    let p = proxy(
        "org.freedesktop.UPower",
        "/org/freedesktop/UPower",
        "org.freedesktop.UPower",
    )?;
    let on_battery: bool = property(&p, "OnBattery")?;
    let d = proxy(
        "org.freedesktop.UPower",
        "/org/freedesktop/UPower/devices/DisplayDevice",
        "org.freedesktop.UPower.Device",
    )?;
    let present: bool = property(&d, "IsPresent")?;
    if !present {
        return Ok(json!({"present":false,"on_battery":on_battery}));
    }
    let percentage: f64 = property(&d, "Percentage")?;
    if !percentage.is_finite() || !(0.0..=100.0).contains(&percentage) {
        return Err("Invalid battery percentage".into());
    }
    Ok(
        json!({"present":true,"percentage":percentage,"state":property::<u32>(&d,"State")?,"on_battery":on_battery}),
    )
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Saved {
    profile: String,
    timeouts: idle::Timeouts,
    #[serde(default)]
    threshold: u32,
    #[serde(default)]
    include_ac: bool,
    #[serde(default)]
    dim: bool,
}
#[derive(Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Runtime {
    restore: Option<String>,
    manual_restore: Option<String>,
    dimmed: Vec<(String, u32, u32)>,
    condition: Option<bool>,
    manual: bool,
}
pub struct Power {
    file: PathBuf,
    idle: PathBuf,
    saved: Option<Saved>,
    system: Value,
    error: Option<String>,
    invalid_config: bool,
    history: Option<history::History>,
    history_error: Option<String>,
    restore: Option<String>,
    manual_restore: Option<String>,
    dimmed: Vec<(String, u32, u32)>,
    condition: Option<bool>,
    manual: bool,
    ticks: u32,
    sleeping: bool,
}
impl Power {
    pub fn new(file: PathBuf, idle: PathBuf, database: PathBuf) -> Self {
        let loaded = std::fs::read(&file);
        let (saved, mut error) = match loaded {
            Ok(b) => match serde_json::from_slice(&b) {
                Ok(s) => (Some(s), None),
                Err(e) => (None, Some(e.to_string())),
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (None, None),
            Err(e) => (None, Some(e.to_string())),
        };
        let runtime = match std::fs::read(file.with_extension("runtime.json")) {
            Ok(bytes) => match serde_json::from_slice::<Runtime>(&bytes) {
                Ok(r) => r,
                Err(e) => {
                    error = Some(e.to_string());
                    Runtime::default()
                }
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Runtime::default(),
            Err(e) => {
                error = Some(e.to_string());
                Runtime::default()
            }
        };
        let (history, history_error) = match history::History::open(&database) {
            Ok(h) => (Some(h), None),
            Err(e) => (None, Some(e)),
        };
        Self {
            file,
            idle,
            invalid_config: error.is_some(),
            saved,
            system: json!({}),
            error,
            history,
            history_error,
            restore: runtime.restore,
            manual_restore: runtime.manual_restore,
            dimmed: runtime.dimmed,
            condition: runtime.condition,
            manual: runtime.manual,
            ticks: 0,
            sleeping: false,
        }
    }
    fn persist_runtime(&self) -> Result<(), String> {
        let value = Runtime {
            restore: self.restore.clone(),
            manual_restore: self.manual_restore.clone(),
            dimmed: self.dimmed.clone(),
            condition: self.condition,
            manual: self.manual,
        };
        let path = self.file.with_extension("runtime.json");
        let bytes = serde_json::to_vec_pretty(&value).map_err(|e| e.to_string())?;
        if std::fs::read(&path).is_ok_and(|existing| existing == bytes) {
            return Ok(());
        }
        atomic_write(&path, &bytes)
    }
    fn persist(&self, saved: &Saved) -> Result<(), String> {
        atomic_write(
            &self.file,
            &serde_json::to_vec_pretty(saved).map_err(|e| e.to_string())?,
        )
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.read_system();
        if let Err(e) = &result {
            self.error = Some(e.clone())
        } else {
            self.error = None
        }
        result
    }
    fn read_system(&mut self) -> Result<(), String> {
        let (active, profiles, degraded) = profile()?;
        let timeouts =
            idle::read(&std::fs::read_to_string(&self.idle).map_err(|e| e.to_string())?)?;
        self.system = json!({"profile":active,"profiles":profiles,"degraded":degraded,"timeouts":timeouts,"battery":battery().unwrap_or_else(|e|json!({"error":e})),"has_backlight":std::fs::read_dir("/sys/class/backlight").is_ok_and(|mut d|d.next().is_some())});
        if self.invalid_config {
            return Err("Power configuration is unreadable; preserve it for repair".into());
        }
        if let Some(s) = &self.saved {
            if !["power-saver", "balanced", "performance"].contains(&s.profile.as_str())
                || ![0, 10, 20, 30, 50, 100].contains(&s.threshold)
                || s.timeouts.screen > 86400
                || s.timeouts.sleep > 86400
            {
                return Err("Invalid saved power configuration".into());
            }
        }
        if self.saved.is_none() {
            if self.invalid_config {
                return Err("Power configuration is unreadable; preserve it for repair".into());
            }
            let s = Saved {
                profile: active.clone(),
                timeouts,
                threshold: 0,
                include_ac: false,
                dim: false,
            };
            self.persist(&s)?;
            self.saved = Some(s);
        }
        if self.restore.is_some() && active != "power-saver" {
            self.restore = None;
            self.manual = true;
            self.adjust_brightness(false)?;
        }
        Ok(())
    }
    fn conflict(&self) -> bool {
        self.saved.as_ref().is_some_and(|s| {
            let expected = if self.restore.is_some() {
                "power-saver"
            } else {
                &s.profile
            };
            self.system["profile"] != expected || self.system["timeouts"] != json!(s.timeouts)
        })
    }
    pub fn state(&self) -> Value {
        json!({"available":!self.system.is_null() && self.system["profile"].is_string(),"saved":self.saved,"system":self.system,"conflict":self.conflict(),"error":self.error,"history_error":self.history_error})
    }
    pub fn read_setting(&mut self, id: &str) -> Value {
        let mut state = self.read();
        state["id"] = json!(id);
        state["availability"] = json!("available");
        state["value"] = match id {
            "power.5a4f0131" => state["system"]["profile"].clone(),
            "power.5e3af39c" => state["system"]["timeouts"]["screen"].clone(),
            "power.8b4c8522" => state["system"]["timeouts"]["sleep"].clone(),
            "battery-saver.743773bd" => json!(state["system"]["profile"] == "power-saver"),
            "battery-saver.9b0caf70" => state["saved"]["threshold"].clone(),
            "battery-saver.power-source" => state["saved"]["include_ac"].clone(),
            _ => state["saved"]["dim"].clone(),
        };
        state
    }
    pub fn read(&mut self) -> Value {
        let _ = self.refresh();
        self.state()
    }
    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        self.refresh()?;
        let mut s = self
            .saved
            .clone()
            .ok_or("Power configuration not initialized")?;
        match source {
            "system" => {
                s.profile = self.system["profile"]
                    .as_str()
                    .ok_or("Missing profile")?
                    .into();
                s.timeouts = serde_json::from_value(self.system["timeouts"].clone())
                    .map_err(|e| e.to_string())?;
            }
            "settings" => {
                set_profile(&s.profile)?;
                idle::apply(&self.idle, &s.timeouts)?;
            }
            _ => return Err("InvalidArgument: expected system or settings".into()),
        }
        self.persist(&s)?;
        self.saved = Some(s);
        self.restore = None;
        self.refresh()?;
        self.persist_runtime()?;
        Ok(self.state())
    }
    pub fn set(&mut self, id: &str, input: &str) -> Result<Value, String> {
        if self.invalid_config {
            return Err("Power configuration is unreadable; preserve it for repair".into());
        }
        let result = self.set_inner(id, input);
        let persisted = self.persist_runtime();
        if let Err(e) = result {
            self.error = Some(e.clone());
            return Err(e);
        }
        persisted?;
        result
    }
    fn set_inner(&mut self, id: &str, input: &str) -> Result<Value, String> {
        self.refresh()?;
        if self.conflict() {
            return Err("Resolve power configuration conflict first".into());
        }
        let v: Value = serde_json::from_str(input).map_err(|e| e.to_string())?;
        let mut s = self
            .saved
            .clone()
            .ok_or("Uninitialized power configuration")?;
        match id {
            "power.5a4f0131" => {
                let p = v.as_str().ok_or("Expected profile string")?;
                if p == "power-saver" && self.system["profile"] != "power-saver" {
                    self.manual_restore = self.system["profile"].as_str().map(str::to_owned);
                }
                set_profile(p)?;
                s.profile = p.into();
                self.restore = None;
                self.manual = true;
            }
            "power.5e3af39c" | "power.8b4c8522" => {
                let seconds = v
                    .as_u64()
                    .filter(|v| *v <= 86400)
                    .ok_or("Expected seconds in 0..86400")? as u32;
                if id == "power.5e3af39c" {
                    s.timeouts.screen = seconds
                } else {
                    s.timeouts.sleep = seconds
                }
                idle::apply(&self.idle, &s.timeouts)?;
            }
            "battery-saver.743773bd" => {
                let enabled = v.as_bool().ok_or("Expected boolean")?;
                let p = if enabled {
                    "power-saver".to_owned()
                } else {
                    self.manual_restore
                        .clone()
                        .or_else(|| self.restore.clone())
                        .unwrap_or_else(|| "balanced".into())
                };
                if enabled && self.system["profile"] != "power-saver" {
                    self.manual_restore = self.system["profile"].as_str().map(str::to_owned)
                }
                set_profile(&p)?;
                s.profile = p;
                self.restore = None;
                self.manual = true;
            }
            "battery-saver.9b0caf70" => {
                s.threshold = v
                    .as_u64()
                    .filter(|v| [0, 10, 20, 30, 50, 100].contains(v))
                    .ok_or("Invalid threshold")? as u32;
                self.manual = false;
                self.condition = None;
            }
            "battery-saver.power-source" => {
                s.include_ac = v.as_bool().ok_or("Expected boolean")?;
                self.manual = false;
                self.condition = None;
            }
            "battery-saver.07945503" => {
                s.dim = v.as_bool().ok_or("Expected boolean")?;
            }
            _ => return Err("Unknown power setting".into()),
        }
        if ["power.5a4f0131", "battery-saver.743773bd"].contains(&id) {
            self.condition = Some(eligible(s.threshold, s.include_ac, &self.system["battery"]));
        }
        self.persist(&s)?;
        self.saved = Some(s);
        self.refresh()?;
        if ["battery-saver.9b0caf70", "battery-saver.power-source"].contains(&id) {
            self.automatic()?;
            self.refresh()?;
        }
        self.adjust_brightness(self.system["profile"] == "power-saver")?;
        Ok(self.state())
    }
    fn adjust_brightness(&mut self, enabled: bool) -> Result<(), String> {
        let dim = enabled && self.saved.as_ref().is_some_and(|s| s.dim);
        let mut backend = BrightnessBackend::default();
        let monitors = Hyprctl.monitors()?;
        let outputs = monitors.iter().map(|m| m.name.clone()).collect::<Vec<_>>();
        if dim && self.dimmed.is_empty() {
            for m in monitors
                .iter()
                .filter(|m| m.name.starts_with("eDP-") || m.name.starts_with("LVDS-"))
            {
                let b = backend.read(&m.name, &outputs);
                if b.backend == Some("backlight") {
                    if let Some(original) = b.percent {
                        let wanted = (original * 70 / 100).max(1);
                        let actual = backend.set(&m.name, &outputs, wanted)?;
                        self.dimmed.push((m.name.clone(), original, actual));
                    }
                }
            }
        } else if !dim {
            let mut remaining = vec![];
            let mut failure = None;
            for (output, original, actual) in self.dimmed.drain(..) {
                if backend.read(&output, &outputs).percent == Some(actual) {
                    if let Err(e) = backend.set(&output, &outputs, original) {
                        remaining.push((output, original, actual));
                        failure = Some(e);
                    }
                }
            }
            self.dimmed = remaining;
            if let Some(e) = failure {
                return Err(e);
            }
        }
        Ok(())
    }
    pub fn sleep(&mut self, sleeping: bool) {
        self.sleeping = sleeping;
        if let Some(h) = &mut self.history {
            if let Err(e) = h.sleeping(sleeping) {
                self.history_error = Some(e)
            }
        }
    }
    pub fn tick(&mut self) {
        if self.sleeping {
            return;
        }
        self.ticks = self.ticks.wrapping_add(1);
        let b = if self.history.as_ref().is_some_and(|h| h.due()) {
            battery().unwrap_or_else(|e| json!({"error":e}))
        } else {
            Value::Null
        };
        let screen = match Hyprctl.monitors() {
            Ok(ms) if !ms.is_empty() => {
                if ms.iter().any(|m| !m.disabled && m.dpms_status) {
                    "screen-on"
                } else {
                    "screen-off"
                }
            }
            _ => "unknown",
        };
        if let Some(h) = &mut self.history {
            if let Err(e) = h.observe(screen, b) {
                self.history_error = Some(e)
            }
        }
        if self.ticks.is_multiple_of(10) {
            if let Err(e) = self.automatic().and_then(|_| self.persist_runtime()) {
                self.error = Some(e)
            }
        }
    }
    fn automatic(&mut self) -> Result<(), String> {
        self.refresh()?;
        if self.conflict() {
            return Ok(());
        }
        let s = self
            .saved
            .clone()
            .ok_or("Uninitialized power configuration")?;
        let b = &self.system["battery"];
        if !b["error"].is_null() {
            return Err(format!("Battery detection failed: {}", b["error"]));
        }
        let condition = eligible(s.threshold, s.include_ac, b);
        if self.condition != Some(condition) {
            self.manual = false;
            self.condition = Some(condition)
        }
        if self.manual {
            return self.adjust_brightness(self.system["profile"] == "power-saver");
        }
        if condition && self.system["profile"] != "power-saver" {
            let previous = self.system["profile"]
                .as_str()
                .ok_or("Missing profile")?
                .to_owned();
            set_profile("power-saver")?;
            self.restore = Some(previous);
            self.adjust_brightness(true)?;
        } else if !condition {
            if let Some(previous) = self.restore.clone() {
                set_profile(&previous)?;
                self.restore = None;
                self.adjust_brightness(false)?;
            }
        }
        self.adjust_brightness(profile()?.0 == "power-saver")?;
        Ok(())
    }
    pub fn shutdown(&mut self) {
        self.history = None;
    }
    pub fn query(&self, request: &str) -> Result<Value, String> {
        self.history
            .as_ref()
            .ok_or_else(|| {
                self.history_error
                    .clone()
                    .unwrap_or("History unavailable".into())
            })?
            .query(request)
    }
}
fn eligible(threshold: u32, include_ac: bool, b: &Value) -> bool {
    threshold > 0
        && b["present"] == true
        && (include_ac || b["on_battery"] == true)
        && b["percentage"]
            .as_f64()
            .is_some_and(|p| p <= threshold as f64)
}
