//! Owns display reconciliation and every write. All interfaces go through here.
use crate::{
    brightness::BrightnessBackend,
    files::atomic_write,
    hyprland::{Compositor, Monitor},
    model::{
        FIELDS, Mode, Prefs, RISKY, confirmed, differences, format_mode, live_statement, lua_value,
        modes, observe, scale_options, validate,
    },
    rules::{RuleFile, parse},
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant},
};

pub const OUTPUT: &str = "hypr-monitor-fields.output";
pub const BRIGHTNESS: &str = "display.5d419889";
pub const CM: &str = "display.af8e280d";
pub const HDR: &str = "display.0ce92088";
pub const SCALE: &str = "display.12e2ed4d";
pub const RESOLUTION: &str = "display.44f6b9b0";
pub const REFRESH: &str = "advanced-display.34d8396d";
pub const TRANSFORM: &str = "display.9843ad76";
pub const LAYOUT: &str = "display.7cb5dc06";
pub const DETECT: &str = "display.15697afc";
pub const POSITION: &str = "hypr-monitor-fields.position";
pub const BIT_DEPTH: &str = "advanced-display.91720250";
pub const VRR: &str = "advanced-display.2d80c2c4";
pub const DESKTOP_MODE: &str = "advanced-display.3b3ebb60";
pub const SIGNAL_MODE: &str = "advanced-display.761b7ac8";
pub const COLOR_SPACE: &str = "advanced-display.3278abf9";
pub const DEVICE: &str = "advanced-display.device";

/// Advanced rule fields that map one setting directly to one Hyprland field.
const DIRECT: &[(&str, &str)] = &[
    (POSITION, "position"),
    (SCALE, "scale"),
    (TRANSFORM, "transform"),
    (CM, "cm"),
    (BIT_DEPTH, "bitdepth"),
    (VRR, "vrr"),
    ("hypr-monitor-fields.sdr-eotf", "sdr_eotf"),
    ("hypr-monitor-fields.icc", "icc"),
    ("hypr-monitor-fields.reserved-area", "reserved_area"),
    (
        "hypr-monitor-fields.supports-wide-color",
        "supports_wide_color",
    ),
    ("hypr-monitor-fields.supports-hdr", "supports_hdr"),
    ("hypr-monitor-fields.sdrbrightness", "sdrbrightness"),
    ("hypr-monitor-fields.sdrsaturation", "sdrsaturation"),
    ("hypr-monitor-fields.sdr-min-luminance", "sdr_min_luminance"),
    ("hypr-monitor-fields.sdr-max-luminance", "sdr_max_luminance"),
    ("hypr-monitor-fields.min-luminance", "min_luminance"),
    ("hypr-monitor-fields.max-luminance", "max_luminance"),
    ("hypr-monitor-fields.max-avg-luminance", "max_avg_luminance"),
];
const READ_ONLY: &[&str] = &[OUTPUT, DESKTOP_MODE, SIGNAL_MODE, COLOR_SPACE, DEVICE];

pub fn is_display_setting(id: &str) -> bool {
    DIRECT.iter().any(|(setting, _)| *setting == id)
        || READ_ONLY.contains(&id)
        || [BRIGHTNESS, HDR, RESOLUTION, REFRESH, LAYOUT, DETECT].contains(&id)
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    output: String,
    value: String,
    #[serde(default)]
    confirm_seconds: u64,
}

struct Pending {
    output: String,
    changes: Vec<(String, String)>,
    previous: Vec<(String, String)>,
    deadline: Instant,
}

pub struct DisplayManager<C> {
    compositor: C,
    config_dir: PathBuf,
    saved_path: PathBuf,
    saved: BTreeMap<String, Prefs>,
    outputs: Vec<Monitor>,
    rules: RuleFile,
    write_blocked: Option<String>,
    pending: Option<Pending>,
    error: Option<String>,
    brightness: BrightnessBackend,
    readback_timeout: Duration,
}

fn loads_monitors_file(dir: &Path, depth: usize) -> bool {
    let Ok(entries) = fs::read_dir(dir) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let path = entry.path();
        if path.is_dir() {
            return depth > 0 && loads_monitors_file(&path, depth - 1);
        }
        if path.extension().is_none_or(|e| e != "lua") || path.ends_with("monitors.lua") {
            return false;
        }
        fs::read_to_string(&path).is_ok_and(|text| {
            text.lines().any(|line| {
                let code = line.split("--").next().unwrap_or("");
                code.contains("require(\"monitors\")")
                    || code.contains("require('monitors')")
                    || code.contains("require \"monitors\"")
                    || code.contains("monitors.lua")
            })
        })
    })
}

impl<C: Compositor> DisplayManager<C> {
    /// `saved_path` holds Settings' values; `config_dir` is the Hyprland config directory.
    pub fn new(compositor: C, config_dir: PathBuf, saved_path: PathBuf) -> Self {
        Self {
            compositor,
            config_dir,
            saved_path,
            saved: BTreeMap::new(),
            outputs: vec![],
            rules: RuleFile::default(),
            write_blocked: None,
            pending: None,
            error: None,
            brightness: BrightnessBackend::default(),
            readback_timeout: Duration::from_secs(5),
        }
    }

    fn rules_path(&self) -> PathBuf {
        self.config_dir.join("monitors.lua")
    }

    fn load_rules(&mut self) -> Result<(), String> {
        self.write_blocked = None;
        self.rules = RuleFile::default();
        if !self.compositor.uses_lua_config()? {
            self.write_blocked =
                Some("Display changes need a Lua Hyprland configuration (hyprland.lua)".into());
            return Ok(());
        }
        let path = self.rules_path();
        let text = match fs::read_to_string(&path) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(format!("{}: {e}", path.display())),
        };
        match parse(&text) {
            Ok(file) => self.rules = file,
            Err(error) => {
                self.write_blocked = Some(format!(
                    "{} contains content Settings cannot safely edit ({error})",
                    path.display()
                ));
                return Ok(());
            }
        }
        if !loads_monitors_file(&self.config_dir, 4) {
            self.write_blocked = Some(format!(
                "Your Hyprland configuration does not load {}; add require(\"monitors\") to hyprland.lua",
                path.display()
            ));
        }
        Ok(())
    }

    fn read_saved(&self) -> Result<Option<BTreeMap<String, Prefs>>, String> {
        let text = match fs::read_to_string(&self.saved_path) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(format!("{}: {e}", self.saved_path.display())),
        };
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct File {
            version: i64,
            #[serde(default)]
            outputs: BTreeMap<String, Prefs>,
        }
        let file: File =
            toml::from_str(&text).map_err(|e| format!("{}: {e}", self.saved_path.display()))?;
        if file.version != 1
            || file
                .outputs
                .values()
                .any(|p| p.keys().any(|k| !FIELDS.contains(&k.as_str())))
        {
            return Err("Invalid display configuration".into());
        }
        Ok(Some(file.outputs))
    }

    fn write_saved(&self, saved: &BTreeMap<String, Prefs>) -> Result<(), String> {
        let text =
            toml::to_string(&json!({"version": 1, "outputs": saved})).map_err(|e| e.to_string())?;
        atomic_write(&self.saved_path, text.as_bytes())
    }

    fn observed(&self, monitor: &Monitor) -> Prefs {
        observe(
            monitor,
            self.rules.find(&monitor.name, &monitor.description),
            &self.outputs,
        )
    }

    fn read_outputs(&mut self) -> Result<(), String> {
        let outputs = self.compositor.monitors()?;
        if outputs.is_empty() {
            return Err("Hyprland reports no displays".into());
        }
        // Waking outputs can briefly report an empty geometry; that is not a preference.
        if outputs
            .iter()
            .any(|m| !m.disabled && m.dpms_status && (m.width <= 0 || m.height <= 0))
        {
            return Err("Display readback is temporarily invalid".into());
        }
        let names = |list: &[Monitor]| list.iter().map(|m| m.name.clone()).collect::<Vec<_>>();
        if names(&outputs) != names(&self.outputs) {
            self.brightness.forget_detection();
        }
        self.outputs = outputs;
        Ok(())
    }

    fn reconcile(&mut self) -> Result<(), String> {
        self.read_outputs()?;
        self.load_rules()?;
        let loaded = self.read_saved()?;
        let existed = loaded.is_some();
        let mut saved = loaded.unwrap_or_default();
        let mut changed = !existed;
        for monitor in &self.outputs {
            let observed = self.observed(monitor);
            match saved.get_mut(&monitor.name) {
                None => {
                    saved.insert(monitor.name.clone(), observed);
                    changed = true;
                }
                Some(values) => {
                    for (field, value) in observed {
                        if let std::collections::btree_map::Entry::Vacant(entry) =
                            values.entry(field)
                        {
                            entry.insert(value);
                            changed = true;
                        }
                    }
                }
            }
        }
        if changed {
            self.write_saved(&saved)?;
        }
        self.saved = saved;
        Ok(())
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.reconcile();
        self.error = result.as_ref().err().cloned();
        result
    }

    fn monitor(&self, name: &str) -> Result<&Monitor, String> {
        self.outputs
            .iter()
            .find(|m| m.name == name)
            .ok_or_else(|| invalid("Unknown display"))
    }

    fn resolve_mode(&self, monitor: &Monitor, value: &str) -> Result<String, String> {
        if value == "preferred" {
            return Ok(value.into());
        }
        let (width, height) = value
            .split_once('x')
            .and_then(|(w, h)| Some((w.parse::<i64>().ok()?, h.parse::<i64>().ok()?)))
            .ok_or_else(|| invalid("Use WIDTHxHEIGHT or preferred"))?;
        if !(1..=32768).contains(&width) || !(1..=32768).contains(&height) {
            return Err(invalid("Width and height must be between 1 and 32768"));
        }
        let distance = |m: &crate::model::Mode| {
            (i128::from(m.width) - i128::from(width)).pow(2)
                + (i128::from(m.height) - i128::from(height)).pow(2)
        };
        let available = modes(monitor);
        let nearest = available
            .iter()
            .min_by_key(|m| distance(m))
            .ok_or_else(|| invalid("This display reports no supported modes"))?;
        let candidates = available
            .iter()
            .filter(|m| m.width == nearest.width && m.height == nearest.height)
            .collect::<Vec<_>>();
        let keeps_rate = candidates
            .iter()
            .find(|m| (m.refresh - monitor.refresh_rate).abs() < 0.1);
        keeps_rate
            .or(candidates.first())
            .map(|m| format_mode(**m))
            .ok_or_else(|| invalid("This display does not offer that resolution"))
    }

    /// Translates a setting value into rule field changes.
    fn changes(
        &self,
        id: &str,
        monitor: &Monitor,
        value: &str,
    ) -> Result<Vec<(String, String)>, String> {
        if let Some((_, field)) = DIRECT.iter().find(|(setting, _)| *setting == id) {
            return Ok(vec![((*field).to_owned(), value.to_owned())]);
        }
        Ok(match id {
            RESOLUTION => vec![("mode".into(), self.resolve_mode(monitor, value)?)],
            REFRESH => {
                let refresh = value
                    .parse::<f64>()
                    .map_err(|_| invalid("Use a refresh rate in Hz"))?;
                vec![(
                    "mode".into(),
                    format_mode(Mode {
                        width: monitor.width,
                        height: monitor.height,
                        refresh,
                    }),
                )]
            }
            HDR => match value {
                "true" => vec![("cm".into(), "hdr".into())],
                "false" => vec![("cm".into(), "srgb".into())],
                _ => return Err(invalid("Use true or false")),
            },
            LAYOUT => match value {
                "extend" => vec![
                    ("disabled".into(), "false".into()),
                    ("mirror".into(), String::new()),
                ],
                "disable" => vec![("disabled".into(), "true".into())],
                _ => {
                    let target = value
                        .strip_prefix("mirror:")
                        .ok_or_else(|| invalid("Use extend, disable, or mirror:<display>"))?;
                    vec![
                        ("disabled".into(), "false".into()),
                        ("mirror".into(), target.to_owned()),
                    ]
                }
            },
            _ => return Err(invalid("This display setting cannot be written")),
        })
    }

    /// The compositor must always keep one output that shows a desktop of its own.
    fn guard_active(&self, monitor: &Monitor, changes: &[(String, String)]) -> Result<(), String> {
        let leaves = changes.iter().any(|(field, value)| {
            (field == "disabled" && value == "true") || (field == "mirror" && !value.is_empty())
        });
        if !leaves {
            return Ok(());
        }
        let others = self
            .outputs
            .iter()
            .filter(|m| m.name != monitor.name && !m.disabled && m.mirror_of == "none")
            .count();
        if others == 0 {
            return Err(invalid("At least one display must stay in use"));
        }
        let id = monitor.id.to_string();
        if self.outputs.iter().any(|m| m.mirror_of == id) {
            return Err(invalid("Another display is mirroring this one"));
        }
        Ok(())
    }

    fn apply_live(&mut self, name: &str, changes: &[(String, String)]) -> Result<(), String> {
        let global = if changes.iter().any(|(f, v)| f == "vrr" && v.is_empty()) {
            self.compositor.global_vrr()?
        } else {
            0
        };
        if let Some(code) = live_statement(name, changes, global) {
            self.compositor.eval(&code)?;
        }
        Ok(())
    }

    /// Modesets are asynchronous, so readback is polled up to a deadline.
    fn wait_for(&mut self, name: &str, changes: &[(String, String)]) -> Result<(), String> {
        let started = Instant::now();
        loop {
            self.read_outputs()?;
            let monitor = self.monitor(name)?.clone();
            let observed = self.observed(&monitor);
            let missing = changes
                .iter()
                .find(|(field, value)| !confirmed(field, value, &observed, &monitor));
            let Some((field, _)) = missing else {
                return Ok(());
            };
            if started.elapsed() >= self.readback_timeout {
                return Err(format!("Hyprland readback does not confirm {field}"));
            }
            thread::sleep(Duration::from_millis(100));
        }
    }

    /// Writes only this output's rule, then records the readback as the saved value.
    fn commit(&mut self, name: &str, changes: &[(String, String)]) -> Result<(), String> {
        let monitor = self.monitor(name)?.clone();
        let path = self.rules_path();
        let current = match fs::read_to_string(&path) {
            Ok(text) => Some(text),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => return Err(e.to_string()),
        };
        let file = parse(current.as_deref().unwrap_or(""))
            .map_err(|e| format!("{}: {e}", path.display()))?;
        let observed = self.observed(&monitor);
        let initial = ["mode", "position", "scale"]
            .iter()
            .filter(|field| !monitor.disabled || **field != "position")
            .filter_map(|field| {
                lua_value(field, observed.get(*field)?).map(|v| ((*field).to_owned(), v))
            })
            .collect::<Vec<_>>();
        let edits = changes
            .iter()
            .map(|(field, value)| (field.clone(), lua_value(field, value)))
            .collect::<Vec<_>>();
        let text = file.with_changes(name, &monitor.description, &initial, &edits);
        parse(&text).map_err(|e| format!("Generated an invalid rule: {e}"))?;
        if let Some(previous) = &current {
            let backup = path.with_file_name("monitors.lua.remya-backup");
            if !backup.exists() {
                atomic_write(&backup, previous.as_bytes())?;
            }
        }
        atomic_write(&path, text.as_bytes())?;
        self.load_rules()?;
        let mut saved = self.saved.clone();
        saved.insert(name.to_owned(), self.observed(&monitor));
        // Non-readable fields and fresh geometry come from the file just written.
        self.read_outputs()?;
        let monitor = self.monitor(name)?.clone();
        saved.insert(name.to_owned(), self.observed(&monitor));
        self.write_saved(&saved)?;
        self.saved = saved;
        Ok(())
    }

    fn revert_live(&mut self, name: &str, previous: &[(String, String)]) -> Result<(), String> {
        self.apply_live(name, previous)?;
        self.wait_for(name, previous)
    }

    fn apply(
        &mut self,
        name: &str,
        changes: Vec<(String, String)>,
        confirm: u64,
    ) -> Result<(), String> {
        if let Some(reason) = &self.write_blocked {
            return Err(reason.clone());
        }
        if self.pending.is_some() {
            return Err("Keep or revert the previous display change first".into());
        }
        let monitor = self.monitor(name)?.clone();
        for (field, value) in &changes {
            validate(field, value, &monitor, &self.outputs)?;
        }
        self.guard_active(&monitor, &changes)?;
        let observed = self.observed(&monitor);
        let previous = changes
            .iter()
            .map(|(field, _)| {
                (
                    field.clone(),
                    observed.get(field).cloned().unwrap_or_default(),
                )
            })
            .collect::<Vec<_>>();
        self.apply_live(name, &changes)?;
        if let Err(error) = self.wait_for(name, &changes) {
            return Err(self.with_revert(name, &previous, error));
        }
        let risky = changes.iter().any(|(f, _)| RISKY.contains(&f.as_str()));
        if risky && confirm > 0 {
            self.pending = Some(Pending {
                output: name.to_owned(),
                changes,
                previous,
                deadline: Instant::now() + Duration::from_secs(confirm.min(60)),
            });
            return Ok(());
        }
        if let Err(error) = self.commit(name, &changes) {
            return Err(self.with_revert(name, &previous, error));
        }
        Ok(())
    }

    fn with_revert(&mut self, name: &str, previous: &[(String, String)], error: String) -> String {
        match self.revert_live(name, previous) {
            Ok(()) => error,
            Err(revert) => format!("{error}; restoring the previous value also failed: {revert}"),
        }
    }

    /// `Set` for every display setting. The value is a JSON request naming the output.
    pub fn set(&mut self, id: &str, value: &str) -> Result<Value, String> {
        if id == DETECT {
            if value != "detect" {
                return Err(invalid("Use detect"));
            }
            self.brightness.forget_detection();
            self.refresh()?;
            return Ok(self.state());
        }
        if READ_ONLY.contains(&id) {
            return Err(invalid("This display value is read-only"));
        }
        let request: Request = serde_json::from_str(value)
            .map_err(|_| invalid("Expected JSON with output and value"))?;
        self.refresh()?;
        if id == BRIGHTNESS {
            let percent = request
                .value
                .parse::<u32>()
                .ok()
                .filter(|p| *p <= 100)
                .ok_or_else(|| invalid("Brightness must be 0 to 100"))?;
            self.monitor(&request.output)?;
            let names = self
                .outputs
                .iter()
                .map(|m| m.name.clone())
                .collect::<Vec<_>>();
            self.brightness.set(&request.output, &names, percent)?;
            return Ok(self.brightness_state());
        }
        let monitor = self.monitor(&request.output)?.clone();
        let changes = self.changes(id, &monitor, &request.value)?;
        self.apply(&request.output, changes, request.confirm_seconds)?;
        self.error = None;
        Ok(self.state())
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        match source {
            "keep" => {
                let pending = self
                    .pending
                    .take()
                    .ok_or_else(|| invalid("No pending change"))?;
                if let Err(error) = self.commit(&pending.output, &pending.changes) {
                    return Err(self.with_revert(&pending.output, &pending.previous, error));
                }
            }
            "revert" => {
                let pending = self
                    .pending
                    .take()
                    .ok_or_else(|| invalid("No pending change"))?;
                self.revert_live(&pending.output, &pending.previous)?;
            }
            "system" => {
                self.require_no_pending()?;
                self.refresh()?;
                let mut saved = self.saved.clone();
                for monitor in &self.outputs {
                    saved.insert(monitor.name.clone(), self.observed(monitor));
                }
                self.write_saved(&saved)?;
                self.saved = saved;
            }
            "settings" => {
                self.require_no_pending()?;
                self.refresh()?;
                if let Some(reason) = &self.write_blocked {
                    return Err(reason.clone());
                }
                for monitor in self.outputs.clone() {
                    let Some(saved) = self.saved.get(&monitor.name).cloned() else {
                        continue;
                    };
                    let changes = differences(&saved, &self.observed(&monitor))
                        .into_iter()
                        .map(|field| {
                            let value = saved.get(&field).cloned().unwrap_or_default();
                            (field, value)
                        })
                        .collect::<Vec<_>>();
                    if !changes.is_empty() {
                        self.apply(&monitor.name, changes, 0)?;
                    }
                }
            }
            _ => return Err(invalid("Unknown resolution")),
        }
        self.error = None;
        self.refresh()?;
        Ok(self.state())
    }

    fn require_no_pending(&self) -> Result<(), String> {
        if self.pending.is_some() {
            return Err("Keep or revert the previous display change first".into());
        }
        Ok(())
    }

    pub fn pending_expired(&self) -> bool {
        self.pending
            .as_ref()
            .is_some_and(|p| Instant::now() >= p.deadline)
    }

    /// Restores the previous live values when a confirmation was never given.
    pub fn revert_pending(&mut self) -> Result<(), String> {
        let Some(pending) = self.pending.take() else {
            return Ok(());
        };
        let result = self.revert_live(&pending.output, &pending.previous);
        self.error = result.as_ref().err().cloned();
        result
    }

    pub fn error(&self) -> Option<&String> {
        self.error.as_ref()
    }

    pub fn brightness_state(&mut self) -> Value {
        let names = self
            .outputs
            .iter()
            .map(|m| m.name.clone())
            .collect::<Vec<_>>();
        let active = self
            .outputs
            .iter()
            .filter(|m| !m.disabled)
            .map(|m| m.name.clone())
            .collect::<Vec<_>>();
        let values = active
            .iter()
            .map(|name| self.brightness.read(name, &names))
            .collect::<Vec<_>>();
        json!({"outputs": values})
    }

    /// The value one setting reports for each connected output.
    pub fn setting_value(&self, id: &str) -> Value {
        let mut values = serde_json::Map::new();
        for monitor in &self.outputs {
            let prefs = self.observed(monitor);
            let value = if let Some((_, field)) = DIRECT.iter().find(|(s, _)| *s == id) {
                json!(prefs.get(*field))
            } else {
                match id {
                    RESOLUTION => json!(format!("{}x{}", monitor.width, monitor.height)),
                    REFRESH => json!(monitor.refresh_rate),
                    HDR => json!(["hdr", "hdredid"].contains(&prefs["cm"].as_str())),
                    LAYOUT => json!(if monitor.disabled {
                        "disable".to_owned()
                    } else if prefs["mirror"].is_empty() {
                        "extend".to_owned()
                    } else {
                        format!("mirror:{}", prefs["mirror"])
                    }),
                    DESKTOP_MODE => json!(logical_size(monitor)),
                    SIGNAL_MODE => json!(signal_mode(monitor)),
                    COLOR_SPACE => json!(color_space(monitor)),
                    DEVICE => json!(monitor.description),
                    _ => Value::Null,
                }
            };
            values.insert(monitor.name.clone(), value);
        }
        Value::Object(values)
    }

    pub fn state(&self) -> Value {
        let pending = self.pending.as_ref();
        let outputs = self
            .outputs
            .iter()
            .map(|monitor| {
                let observed = self.observed(monitor);
                let saved = self.saved.get(&monitor.name);
                let conflict_fields = match (pending, saved) {
                    (None, Some(saved)) => differences(saved, &observed),
                    _ => vec![],
                };
                let mut values = observed;
                if let Some(p) = pending.filter(|p| p.output == monitor.name) {
                    values.extend(p.changes.iter().cloned());
                }
                let current = scale_options(monitor.width, monitor.height);
                json!({
                    "name": monitor.name,
                    "description": monitor.description,
                    "make": monitor.make,
                    "model": monitor.model,
                    "serial": monitor.serial,
                    "physical_width": monitor.physical_width,
                    "physical_height": monitor.physical_height,
                    "width": monitor.width,
                    "height": monitor.height,
                    "refresh_rate": monitor.refresh_rate,
                    "x": monitor.x,
                    "y": monitor.y,
                    "scale": monitor.scale,
                    "transform": monitor.transform,
                    "disabled": monitor.disabled,
                    "vrr_active": monitor.vrr,
                    "format": monitor.current_format,
                    "desktop_mode": logical_size(monitor),
                    "signal_mode": signal_mode(monitor),
                    "color_space": color_space(monitor),
                    "modes": modes(monitor).iter().map(|m| json!({
                        "width": m.width, "height": m.height, "refresh": m.refresh,
                    })).collect::<Vec<_>>(),
                    "scale_options": current,
                    "hdr_capable": monitor.hardware_details.hdr,
                    "wide_gamut_capable": monitor.hardware_details.bt2020
                        || monitor.hardware_details.chroma
                        || monitor.hardware_details.hdr,
                    "vrr_capable": monitor.hardware_details.vrr_capable,
                    "values": values,
                    "saved": saved,
                    "conflict_fields": conflict_fields,
                })
            })
            .collect::<Vec<_>>();
        json!({
            "outputs": outputs,
            "conflict": outputs.iter().any(|o| {
                o["conflict_fields"].as_array().is_some_and(|f| !f.is_empty())
            }),
            "pending": pending.map(|p| json!({
                "output": p.output,
                "fields": p.changes.iter().map(|(f, _)| f).collect::<Vec<_>>(),
                "remaining_ms": p.deadline.saturating_duration_since(Instant::now()).as_millis() as u64,
            })),
            "write_blocked": self.write_blocked,
            "rules_path": self.rules_path(),
            "error": self.error,
        })
    }
}

fn logical_size(monitor: &Monitor) -> String {
    if monitor.disabled || monitor.scale <= 0.0 {
        return "Not in use".into();
    }
    let (width, height) = if monitor.transform % 2 == 1 {
        (monitor.height, monitor.width)
    } else {
        (monitor.width, monitor.height)
    };
    format!(
        "{} × {} logical pixels",
        (width as f64 / monitor.scale).round() as i64,
        (height as f64 / monitor.scale).round() as i64
    )
}

fn signal_mode(monitor: &Monitor) -> String {
    if monitor.disabled {
        return "Not in use".into();
    }
    format!(
        "{} × {} at {:.2} Hz",
        monitor.width, monitor.height, monitor.refresh_rate
    )
}

fn color_space(monitor: &Monitor) -> String {
    if monitor.disabled {
        return "Not in use".into();
    }
    format!(
        "{} · {}",
        monitor.color_management_preset, monitor.current_format
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct World {
        monitors: Vec<Monitor>,
        evals: Vec<String>,
        fail_eval: bool,
        ignore_eval: bool,
        lua: bool,
    }

    #[derive(Clone, Default)]
    struct Fake(Arc<Mutex<World>>);

    impl Compositor for Fake {
        fn monitors(&self) -> Result<Vec<Monitor>, String> {
            Ok(self.0.lock().unwrap().monitors.clone())
        }
        fn eval(&self, code: &str) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            if world.fail_eval {
                return Err("rejected".into());
            }
            world.evals.push(code.to_owned());
            if world.ignore_eval {
                return Ok(());
            }
            // Apply the statement the way Hyprland does: only named fields change.
            let body = code
                .strip_prefix("hl.monitor({")
                .and_then(|c| c.strip_suffix("})"))
                .unwrap();
            let mut fields = BTreeMap::new();
            for part in body.split(',') {
                let (key, value) = part.split_once('=').unwrap();
                fields.insert(key.to_owned(), value.trim_matches('"').to_owned());
            }
            let name = fields["output"].clone();
            let ids = world
                .monitors
                .iter()
                .map(|m| (m.name.clone(), m.id))
                .collect::<BTreeMap<_, _>>();
            let monitor = world.monitors.iter_mut().find(|m| m.name == name).unwrap();
            for (key, value) in fields {
                match key.as_str() {
                    "scale" => monitor.scale = value.parse().unwrap_or(1.6),
                    "transform" => monitor.transform = value.parse().unwrap(),
                    "disabled" => monitor.disabled = value == "true",
                    "cm" => monitor.color_management_preset = value,
                    "bitdepth" => {
                        monitor.current_format = if value == "10" {
                            "XRGB2101010"
                        } else {
                            "XRGB8888"
                        }
                        .into()
                    }
                    "sdrbrightness" => monitor.sdr_brightness = value.parse().unwrap(),
                    "mirror" => {
                        monitor.mirror_of =
                            ids.get(&value).map_or("none".into(), |id| id.to_string())
                    }
                    "position" => {
                        let (x, y) = value.split_once('x').unwrap();
                        monitor.x = x.parse().unwrap();
                        monitor.y = y.parse().unwrap();
                    }
                    "mode" => {
                        let mode = crate::model::parse_mode(&value).unwrap();
                        monitor.width = mode.width;
                        monitor.height = mode.height;
                        monitor.refresh_rate = mode.refresh;
                    }
                    _ => {}
                }
            }
            Ok(())
        }
        fn uses_lua_config(&self) -> Result<bool, String> {
            Ok(self.0.lock().unwrap().lua)
        }
        fn global_vrr(&self) -> Result<i64, String> {
            Ok(1)
        }
    }

    fn output(id: i64, name: &str, x: i64) -> Monitor {
        Monitor {
            id,
            name: name.into(),
            description: format!("{name} panel"),
            width: 1920,
            height: 1080,
            refresh_rate: 60.0,
            x,
            scale: 1.0,
            dpms_status: true,
            mirror_of: "none".into(),
            current_format: "XRGB8888".into(),
            color_management_preset: "srgb".into(),
            sdr_brightness: 1.0,
            sdr_saturation: 1.0,
            sdr_min_luminance: 0.2,
            sdr_max_luminance: 80.0,
            available_modes: vec![
                "1920x1080@60.00Hz".into(),
                "1920x1080@144.00Hz".into(),
                "1280x720@60.00Hz".into(),
            ],
            ..Default::default()
        }
    }

    struct Setup {
        world: Fake,
        manager: DisplayManager<Fake>,
        root: tempfile::TempDir,
    }

    fn setup() -> Setup {
        let root = tempfile::tempdir().unwrap();
        let hypr = root.path().join("hypr");
        fs::create_dir_all(&hypr).unwrap();
        fs::write(hypr.join("hyprland.lua"), "require(\"monitors\")\n").unwrap();
        let world = Fake::default();
        {
            let mut w = world.0.lock().unwrap();
            w.lua = true;
            w.monitors = vec![output(0, "A", 0), output(1, "B", 1920)];
        }
        let mut manager =
            DisplayManager::new(world.clone(), hypr, root.path().join("display.toml"));
        manager.readback_timeout = Duration::ZERO;
        Setup {
            world,
            manager,
            root,
        }
    }

    fn request(output: &str, value: &str) -> String {
        json!({"output": output, "value": value}).to_string()
    }

    fn rules(setup: &Setup) -> String {
        fs::read_to_string(setup.root.path().join("hypr/monitors.lua")).unwrap_or_default()
    }

    #[test]
    fn first_use_adopts_the_system_without_writing_to_it() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        assert!(s.world.0.lock().unwrap().evals.is_empty());
        assert_eq!(rules(&s), "");
        let saved = fs::read_to_string(s.root.path().join("display.toml")).unwrap();
        assert!(saved.contains("[outputs.A]"));
        assert_eq!(s.manager.state()["conflict"], false);
    }

    #[test]
    fn detection_failure_leaves_configuration_uninitialized() {
        let mut s = setup();
        s.world.0.lock().unwrap().monitors.clear();
        assert!(s.manager.refresh().is_err());
        assert!(!s.root.path().join("display.toml").exists());
        assert!(s.manager.state()["error"].is_string());
    }

    #[test]
    fn invalid_geometry_during_wake_is_not_a_conflict() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        s.world.0.lock().unwrap().monitors[0].width = 0;
        assert!(s.manager.refresh().unwrap_err().contains("temporarily"));
        assert_eq!(s.manager.state()["conflict"], false);
    }

    #[test]
    fn plain_set_applies_persists_and_keeps_other_rules() {
        let mut s = setup();
        let path = s.root.path().join("hypr/monitors.lua");
        fs::write(
            &path,
            "-- keep me\nhl.monitor({ output = \"HDMI-A-1\", scale = 2 })\n",
        )
        .unwrap();
        s.manager.set(TRANSFORM, &request("A", "1")).unwrap();
        let text = rules(&s);
        assert!(text.contains("-- keep me"));
        assert!(text.contains("output = \"HDMI-A-1\""));
        assert!(text.contains("transform = 1"));
        assert!(text.contains("mode = \"1920x1080@60.00\""));
        // Only the first write takes a backup of the user's original file.
        let backup = s.root.path().join("hypr/monitors.lua.remya-backup");
        assert!(
            fs::read_to_string(&backup)
                .unwrap()
                .starts_with("-- keep me")
        );
        s.manager.set(TRANSFORM, &request("A", "2")).unwrap();
        assert!(!fs::read_to_string(&backup).unwrap().contains("transform"));
        assert_eq!(s.manager.state()["conflict"], false);
    }

    #[test]
    fn external_change_is_a_conflict_with_both_resolutions() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        s.world.0.lock().unwrap().monitors[0].transform = 3;
        s.manager.refresh().unwrap();
        let state = s.manager.state();
        assert_eq!(state["conflict"], true);
        assert_eq!(state["outputs"][0]["conflict_fields"][0], "transform");
        // Both values stay visible until the user chooses.
        assert_eq!(state["outputs"][0]["saved"]["transform"], "0");
        assert_eq!(state["outputs"][0]["values"]["transform"], "3");

        let state = s.manager.resolve("settings").unwrap();
        assert_eq!(state["conflict"], false);
        assert_eq!(s.world.0.lock().unwrap().monitors[0].transform, 0);

        s.world.0.lock().unwrap().monitors[0].transform = 2;
        s.manager.refresh().unwrap();
        let state = s.manager.resolve("system").unwrap();
        assert_eq!(state["conflict"], false);
        assert_eq!(state["outputs"][0]["saved"]["transform"], "2");
        assert_eq!(s.world.0.lock().unwrap().monitors[0].transform, 2);
    }

    #[test]
    fn disconnected_outputs_keep_their_values_and_raise_no_conflict() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        s.world.0.lock().unwrap().monitors.pop();
        s.manager.refresh().unwrap();
        assert_eq!(s.manager.state()["conflict"], false);
        assert!(s.manager.saved.contains_key("B"));
    }

    #[test]
    fn failed_settings_resolution_retains_the_conflict() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        {
            let mut w = s.world.0.lock().unwrap();
            w.monitors[0].transform = 3;
            w.fail_eval = true;
        }
        assert!(s.manager.resolve("settings").is_err());
        s.manager.refresh().unwrap();
        assert_eq!(s.manager.state()["conflict"], true);
    }

    #[test]
    fn confirmation_defers_persistence_and_revert_restores() {
        let mut s = setup();
        let value = json!({"output":"A","value":"1","confirm_seconds":15}).to_string();
        let state = s.manager.set(TRANSFORM, &value).unwrap();
        assert_eq!(state["pending"]["output"], "A");
        assert_eq!(state["outputs"][0]["values"]["transform"], "1");
        assert_eq!(state["conflict"], false);
        assert_eq!(rules(&s), "");
        assert!(
            s.manager
                .set(TRANSFORM, &request("B", "1"))
                .unwrap_err()
                .contains("previous display change")
        );
        s.manager.resolve("revert").unwrap();
        assert_eq!(s.world.0.lock().unwrap().monitors[0].transform, 0);
        assert_eq!(rules(&s), "");

        s.manager.set(TRANSFORM, &value).unwrap();
        s.manager.resolve("keep").unwrap();
        assert!(rules(&s).contains("transform = 1"));
        assert_eq!(s.manager.state()["pending"], Value::Null);
    }

    #[test]
    fn expired_confirmation_reverts_without_writing() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        let value = json!({"output":"A","value":"1","confirm_seconds":15}).to_string();
        s.manager.set(TRANSFORM, &value).unwrap();
        assert!(!s.manager.pending_expired());
        s.manager.pending.as_mut().unwrap().deadline = Instant::now();
        assert!(s.manager.pending_expired());
        s.manager.revert_pending().unwrap();
        assert_eq!(s.world.0.lock().unwrap().monitors[0].transform, 0);
        assert_eq!(rules(&s), "");
    }

    #[test]
    fn safe_settings_ignore_the_confirmation_request() {
        let mut s = setup();
        let value = json!({"output":"B","value":"1920x0","confirm_seconds":15}).to_string();
        let state = s.manager.set(POSITION, &value).unwrap();
        assert_eq!(state["pending"], Value::Null);
        assert!(rules(&s).contains("position = \"1920x0\""));
    }

    #[test]
    fn mismatched_readback_is_reverted_and_not_persisted() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        s.world.0.lock().unwrap().ignore_eval = true;
        assert!(
            s.manager
                .set(TRANSFORM, &request("A", "1"))
                .unwrap_err()
                .contains("readback")
        );
        assert_eq!(rules(&s), "");
        // The change and then its revert were both sent.
        assert_eq!(s.world.0.lock().unwrap().evals.len(), 2);
    }

    #[test]
    fn rejected_changes_leave_the_system_and_saved_values_alone() {
        let mut s = setup();
        s.manager.refresh().unwrap();
        let before = fs::read_to_string(s.root.path().join("display.toml")).unwrap();
        s.world.0.lock().unwrap().fail_eval = true;
        assert!(s.manager.set(TRANSFORM, &request("A", "1")).is_err());
        assert_eq!(rules(&s), "");
        assert_eq!(
            fs::read_to_string(s.root.path().join("display.toml")).unwrap(),
            before
        );
    }

    #[test]
    fn the_last_display_cannot_be_disabled_or_mirrored_away() {
        let mut s = setup();
        s.manager.set(LAYOUT, &request("B", "disable")).unwrap();
        assert!(s.world.0.lock().unwrap().monitors[1].disabled);
        for value in ["disable", "mirror:B"] {
            assert!(
                s.manager
                    .set(LAYOUT, &request("A", value))
                    .unwrap_err()
                    .starts_with("InvalidArgument:")
            );
        }
        s.manager.set(LAYOUT, &request("B", "extend")).unwrap();
        assert!(!s.world.0.lock().unwrap().monitors[1].disabled);
        s.manager.set(LAYOUT, &request("B", "mirror:A")).unwrap();
        assert_eq!(s.world.0.lock().unwrap().monitors[1].mirror_of, "0");
        // A display that others mirror cannot leave the layout.
        assert!(s.manager.set(LAYOUT, &request("A", "disable")).is_err());
        s.manager.set(LAYOUT, &request("B", "extend")).unwrap();
        assert!(!rules(&s).contains("mirror"));
    }

    #[test]
    fn resolution_keeps_the_rate_when_possible_and_refresh_keeps_the_size() {
        let mut s = setup();
        s.manager.set(REFRESH, &request("A", "144.00")).unwrap();
        assert_eq!(s.world.0.lock().unwrap().monitors[0].refresh_rate, 144.0);
        s.manager
            .set(RESOLUTION, &request("A", "1280x720"))
            .unwrap();
        {
            let w = s.world.0.lock().unwrap();
            assert_eq!(w.monitors[0].width, 1280);
            assert_eq!(w.monitors[0].refresh_rate, 60.0);
        }
        s.manager
            .set(RESOLUTION, &request("A", "1300x730"))
            .unwrap();
        assert_eq!(s.world.0.lock().unwrap().monitors[0].width, 1280);
        for value in [
            "0x720",
            "-1x720",
            "32769x720",
            "broken",
            "9223372036854775807x1",
        ] {
            assert!(s.manager.set(RESOLUTION, &request("A", value)).is_err());
        }
        assert!(s.manager.set(REFRESH, &request("A", "999")).is_err());
    }

    #[test]
    fn writes_are_refused_without_a_loaded_lua_rule_file() {
        let mut s = setup();
        s.world.0.lock().unwrap().lua = false;
        s.manager.refresh().unwrap();
        assert!(
            s.manager.state()["write_blocked"]
                .as_str()
                .unwrap()
                .contains("Lua")
        );
        assert!(s.manager.set(TRANSFORM, &request("A", "1")).is_err());

        s.world.0.lock().unwrap().lua = true;
        fs::write(
            s.root.path().join("hypr/hyprland.lua"),
            "-- require(\"monitors\")\n",
        )
        .unwrap();
        s.manager.refresh().unwrap();
        assert!(
            s.manager.state()["write_blocked"]
                .as_str()
                .unwrap()
                .contains("does not load")
        );

        fs::write(
            s.root.path().join("hypr/hyprland.lua"),
            "require(\"monitors\")\n",
        )
        .unwrap();
        let path = s.root.path().join("hypr/monitors.lua");
        fs::write(&path, "if true then end\n").unwrap();
        s.manager.refresh().unwrap();
        assert!(
            s.manager
                .set(TRANSFORM, &request("A", "1"))
                .unwrap_err()
                .contains("line 1")
        );
        assert_eq!(fs::read_to_string(&path).unwrap(), "if true then end\n");
        assert!(s.world.0.lock().unwrap().evals.is_empty());
    }

    #[test]
    fn invalid_saved_configuration_is_reported_and_kept() {
        let mut s = setup();
        let path = s.root.path().join("display.toml");
        for bad in [
            "bad [",
            "version = 2\n",
            "version = 1\n[outputs.A]\nunknown = \"1\"\n",
        ] {
            fs::write(&path, bad).unwrap();
            assert!(s.manager.refresh().is_err(), "{bad}");
            assert_eq!(fs::read_to_string(&path).unwrap(), bad);
        }
    }

    #[test]
    fn write_only_fields_round_trip_through_the_rule_file() {
        let mut s = setup();
        s.manager
            .set(
                "hypr-monitor-fields.reserved-area",
                &request("A", "1 2 3 4"),
            )
            .unwrap();
        s.manager
            .set("hypr-monitor-fields.sdr-eotf", &request("A", "gamma22"))
            .unwrap();
        let state = s.manager.state();
        assert_eq!(state["outputs"][0]["values"]["reserved_area"], "1 2 3 4");
        assert_eq!(state["outputs"][0]["values"]["sdr_eotf"], "gamma22");
        assert_eq!(state["conflict"], false);
        s.manager
            .set(
                "hypr-monitor-fields.reserved-area",
                &request("A", "0 0 0 0"),
            )
            .unwrap();
        assert!(!rules(&s).contains("reserved_area"));
    }

    #[test]
    fn hdr_toggle_requires_hardware_support() {
        let mut s = setup();
        assert!(
            s.manager
                .set(HDR, &request("A", "true"))
                .unwrap_err()
                .contains("HDR")
        );
        s.world.0.lock().unwrap().monitors[0].hardware_details.hdr = true;
        s.manager.set(HDR, &request("A", "true")).unwrap();
        assert_eq!(s.manager.setting_value(HDR)["A"], true);
        s.manager.set(HDR, &request("A", "false")).unwrap();
        assert_eq!(s.manager.setting_value(HDR)["A"], false);
    }

    #[test]
    fn read_only_and_malformed_requests_fail_as_invalid() {
        let mut s = setup();
        for (id, value) in [
            (DESKTOP_MODE, "x"),
            (OUTPUT, "x"),
            (TRANSFORM, "not json"),
            (TRANSFORM, "{\"output\":\"A\"}"),
            (TRANSFORM, "{\"output\":\"NOPE\",\"value\":\"1\"}"),
            (DETECT, "x"),
            (BRIGHTNESS, "{\"output\":\"A\",\"value\":\"101\"}"),
        ] {
            assert!(
                s.manager
                    .set(id, value)
                    .unwrap_err()
                    .starts_with("InvalidArgument:"),
                "{id} {value}"
            );
        }
        assert!(is_display_setting(SCALE));
        assert!(!is_display_setting("date-time.format"));
    }
}
