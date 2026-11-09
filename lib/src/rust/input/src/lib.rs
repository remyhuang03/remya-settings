//! Settings-owned Hyprland options: mouse, touchpad and keyboard shortcuts (`input`)
//! and window appearance, layout, cursor behavior, workspaces and their rules, blur,
//! fallback background, display wake, compositor font and compositor bell (`desktop`).
//!
//! Option values are live compositor state read through `hyprctl descriptions`.
//! Settings persists each group's changes in `hypr/remya-settings/<group>.lua`,
//! required at the end of `hyprland.lua`, and keeps its own copy in `<group>.toml`
//! for reconciliation.
pub mod config;
pub mod keys;
pub mod xkb;

pub use config::{DESKTOP, INPUT};
use config::{File, Group, Shortcut, WorkspaceRule};
use keys::{Keys, Layout};
use remya_settings_display::{Hyprctl, atomic_write, run_bytes};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

pub const ADD: &str = "keyboard-shortcuts.add";
pub const REMOVE: &str = "keyboard-shortcuts.remove";
pub const DISABLE: &str = "keyboard-shortcuts.disable";
pub const RECORD: &str = "keyboard-shortcuts.record";
pub const LIST: &str = "keyboard-shortcuts.list";
pub const LOOKUP: &str = "keyboard-shortcuts.lookup:";
const RECORD_SUBMAP: &str = "remya-settings-record";
pub const RULE_SET: &str = "workspaces.rule-set";
pub const RULE_REMOVE: &str = "workspaces.rule-remove";

pub fn is_setting(id: &str) -> bool {
    INPUT.option(id).is_some() || [ADD, REMOVE, DISABLE, RECORD, LIST].contains(&id)
}

pub fn is_desktop_setting(id: &str) -> bool {
    DESKTOP.option(id).is_some() || [RULE_SET, RULE_REMOVE].contains(&id)
}

fn invalid(message: impl std::fmt::Display) -> String {
    format!("InvalidArgument:{message}")
}

/// The compositor operations this feature needs.
pub trait Hypr: Send {
    fn request(&self, args: &[&str]) -> Result<String, String>;

    fn json(&self, what: &str) -> Result<Value, String> {
        serde_json::from_str(&self.request(&["-j", what])?)
            .map_err(|e| format!("hyprctl {what}: {e}"))
    }
    /// Callers pass only code rendered by `config` from validated values and fixed actions.
    fn eval(&self, code: &str) -> Result<(), String> {
        match self.request(&["eval", code])?.trim() {
            "ok" => Ok(()),
            other => Err(format!("Hyprland rejected the change: {other}")),
        }
    }
}

pub struct RealHypr;
impl Hypr for RealHypr {
    fn request(&self, args: &[&str]) -> Result<String, String> {
        let instance = Hyprctl::instance()?;
        let mut all = vec!["-i", instance.as_str()];
        all.extend_from_slice(args);
        let bytes = run_bytes("hyprctl", &all, &[], Duration::from_secs(5))?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub options: BTreeMap<String, Value>,
    #[serde(default)]
    pub disabled: Vec<String>,
    #[serde(default)]
    pub shortcuts: Vec<Shortcut>,
    #[serde(default)]
    pub rules: Vec<WorkspaceRule>,
}

#[derive(Clone, Debug, Default)]
struct Observed {
    options: BTreeMap<String, Value>,
    autoreload: bool,
    binds: Vec<Value>,
    devices: Value,
    layout: Layout,
    workspace_rules: Vec<Value>,
    monitors: Vec<Value>,
    workspaces: Vec<Value>,
    file: Option<File>,
}

pub struct Input<H> {
    group: &'static Group,
    hypr: H,
    hypr_dir: PathBuf,
    saved_path: PathBuf,
    saved: Option<Saved>,
    observed: Observed,
    write_blocked: Option<String>,
    error: Option<String>,
    recording: bool,
}

/// `hyprctl binds` reports either a key name or, for `code:` binds, a keycode.
fn bind_key(bind: &Value) -> Option<String> {
    match (bind["key"].as_str(), bind["keycode"].as_u64()) {
        (Some(key), _) if !key.is_empty() => Some(key.to_owned()),
        (_, Some(code)) if code > 0 => Some(format!("code:{code}")),
        _ => None,
    }
}

/// A stored combination with what the keycaps show.
fn caps(text: &str, keys: Option<&Keys>) -> Value {
    let (mask, key) = keys::parse_combo(text).unwrap_or_default();
    json!({"keys": text, "modifiers": keys::modifier_names(mask), "label": keys::label(&key, keys)})
}

fn same(a: &Value, b: &Value) -> bool {
    match (a.as_f64(), b.as_f64()) {
        (Some(x), Some(y)) => (x - y).abs() < 5e-4,
        _ => a == b,
    }
}

fn layout(devices: &Value) -> Layout {
    let keyboards = devices["keyboards"].as_array().cloned().unwrap_or_default();
    let main = keyboards
        .iter()
        .find(|k| k["main"] == true)
        .or(keyboards.first())
        .cloned()
        .unwrap_or_default();
    let text = |k: &str| main[k].as_str().unwrap_or_default().to_owned();
    Layout {
        rules: text("rules"),
        model: text("model"),
        layout: text("layout"),
        variant: text("variant"),
        options: text("options"),
    }
}

/// Plain-language names for the dispatchers `hyprctl binds` reports.
fn action_label(dispatcher: &str) -> String {
    let name = dispatcher
        .strip_prefix("HL.Dispatcher(")
        .and_then(|d| d.strip_suffix(')'))
        .unwrap_or(dispatcher);
    match name {
        "exec_cmd" | "exec" => "Run a command",
        "global" => "Desktop shell action",
        "focus" => "Move focus",
        "move" => "Move window",
        "toggle_special" => "Show or hide a special workspace",
        "drag" => "Drag window",
        "resize" => "Resize window",
        "close" => "Close window",
        "float" => "Float or tile window",
        "fullscreen" | "fullscreen_state" => "Fullscreen",
        "layout" => "Layout action",
        "pin" => "Pin window",
        "submap" => "Switch shortcut mode",
        _ if name.starts_with("function:") => "Script",
        other => other,
    }
    .to_owned()
}

/// A display's name, layout position and logical size, which is what the desktop uses.
fn monitor(m: &Value) -> Value {
    let scale = m["scale"].as_f64().filter(|s| *s > 0.0).unwrap_or(1.0);
    let (w, h) = (
        m["width"].as_f64().unwrap_or(0.0),
        m["height"].as_f64().unwrap_or(0.0),
    );
    // Odd transforms rotate the output by 90 or 270 degrees.
    let (w, h) = if m["transform"].as_i64().unwrap_or(0) % 2 == 1 {
        (h, w)
    } else {
        (w, h)
    };
    json!({
        "name": m["name"], "description": m["description"],
        "x": m["x"], "y": m["y"],
        "width": (w / scale).round(), "height": (h / scale).round(),
        "active_workspace": m["activeWorkspace"]["name"],
        "special_workspace": m["specialWorkspace"]["name"],
    })
}

/// A live `workspacerules` entry, keyed like `WorkspaceRule`.
fn rule_value(e: &Value, key: &str) -> Value {
    e[match key {
        "workspace" => "workspaceString",
        "default_name" => "defaultName",
        other => other,
    }]
    .clone()
}

/// True when Hyprland reports every saved rule and dropped the fields of removed ones.
///
/// shortcut: Hyprland merges rules for the same workspace, so a field removed here that
/// another file sets the same way never disappears and the write times out and is undone.
fn rules_match(next: &[WorkspaceRule], before: &[WorkspaceRule], live: &[Value]) -> bool {
    let entry = |w: &str| live.iter().find(|e| e["workspaceString"] == w);
    let has = |e: Option<&Value>, key: &str, v: Value| e.is_some_and(|e| rule_value(e, key) == v);
    let present = next.iter().all(|r| {
        let e = entry(&r.workspace);
        e.is_some()
            && (r.monitor.is_empty() || has(e, "monitor", json!(r.monitor)))
            && (!r.default || has(e, "default", json!(true)))
            && (!r.persistent || has(e, "persistent", json!(true)))
            && (r.default_name.is_empty() || has(e, "default_name", json!(r.default_name)))
    });
    let gone = before.iter().filter(|b| !next.contains(b)).all(|b| {
        let n = next.iter().find(|r| r.workspace == b.workspace);
        let e = entry(&b.workspace);
        (b.monitor.is_empty()
            || n.is_some_and(|n| !n.monitor.is_empty())
            || !has(e, "monitor", json!(b.monitor)))
            && (!b.default || n.is_some_and(|n| n.default) || !has(e, "default", json!(true)))
            && (!b.persistent
                || n.is_some_and(|n| n.persistent)
                || !has(e, "persistent", json!(true)))
            && (b.default_name.is_empty()
                || n.is_some_and(|n| !n.default_name.is_empty())
                || !has(e, "default_name", json!(b.default_name)))
    });
    present && gone
}

/// A checked rule and the workspace of the rule it replaces.
fn validate_rule(request: &Value) -> Result<(WorkspaceRule, Option<String>), String> {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Request {
        workspace: String,
        #[serde(default)]
        monitor: String,
        #[serde(default)]
        default: bool,
        #[serde(default)]
        persistent: bool,
        #[serde(default)]
        default_name: String,
        #[serde(default)]
        previous: Option<String>,
    }
    let r: Request = serde_json::from_value(request.clone()).map_err(|_| {
        invalid("Expected workspace, monitor, default, persistent, default_name and previous")
    })?;
    let workspace = selector(&r.workspace)
        .ok_or_else(|| invalid("Use a workspace number, name:<name> or special:<name>"))?;
    let monitor = r.monitor.trim();
    if monitor.len() > 64
        || !monitor
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c))
    {
        return Err(invalid("Use a display connector name such as DP-1"));
    }
    if r.default && (monitor.is_empty() || workspace.starts_with("special:")) {
        return Err(invalid(
            "A display can start with a regular workspace only, and needs a display chosen",
        ));
    }
    let default_name = r.default_name.trim();
    if !config::plain(default_name, 64) || (!default_name.is_empty() && workspace.contains(':')) {
        return Err(invalid("Only a numbered workspace takes a one-line name"));
    }
    Ok((
        WorkspaceRule {
            workspace,
            monitor: monitor.to_owned(),
            default: r.default,
            persistent: r.persistent,
            default_name: default_name.to_owned(),
        },
        r.previous,
    ))
}

/// A workspace selector Settings writes: a number, `name:<text>` or `special:<text>`.
fn selector(text: &str) -> Option<String> {
    let text = text.trim();
    if text.parse::<u32>().is_ok_and(|n| (1..=9999).contains(&n)) {
        return Some(text.trim_start_matches('0').to_owned());
    }
    let (kind, name) = text.split_once(':')?;
    let name = name.trim();
    (["name", "special"].contains(&kind) && !name.is_empty() && config::plain(name, 64))
        .then(|| format!("{kind}:{name}"))
}

impl<H: Hypr> Input<H> {
    pub fn new(group: &'static Group, hypr: H, hypr_dir: PathBuf, saved_path: PathBuf) -> Self {
        Self {
            group,
            hypr,
            hypr_dir,
            saved_path,
            saved: None,
            observed: Observed::default(),
            write_blocked: None,
            error: None,
            recording: false,
        }
    }

    fn file_path(&self) -> PathBuf {
        self.hypr_dir
            .join(format!("remya-settings/{}.lua", self.group.name))
    }

    fn main_path(&self) -> PathBuf {
        self.hypr_dir.join("hyprland.lua")
    }

    fn read_file(&self) -> Result<File, String> {
        match fs::read_to_string(self.file_path()) {
            Ok(text) => config::parse(self.group, &text),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(File::default()),
            Err(e) => Err(format!("{}: {e}", self.file_path().display())),
        }
    }

    fn read_options(&self) -> Result<(BTreeMap<String, Value>, bool), String> {
        let descriptions = self.hypr.json("descriptions")?;
        let current = |name: &str| {
            descriptions
                .as_array()
                .and_then(|all| all.iter().find(|d| d["name"] == name))
                .map(|d| d["current"].clone())
        };
        let mut options = BTreeMap::new();
        for opt in self.group.options {
            let value = current(opt.name)
                .ok_or_else(|| format!("Hyprland does not report {}", opt.name))?;
            let value = match opt.kind {
                config::Kind::Layouts => json!([value, current("input:kb_variant")]),
                _ => value,
            };
            options.insert(opt.id.to_owned(), opt.observed(&value));
        }
        let autoreload = current("misc:disable_autoreload").is_some_and(|v| v != true);
        Ok((options, autoreload))
    }

    fn read(&mut self) -> Result<(), String> {
        self.write_blocked = None;
        let (options, autoreload) = self.read_options()?;
        self.observed.options = options;
        self.observed.autoreload = autoreload;
        if self.group.shortcuts {
            self.observed.binds = self
                .hypr
                .json("binds")?
                .as_array()
                .cloned()
                .unwrap_or_default();
            self.observed.devices = self.hypr.json("devices")?;
            self.observed.layout = layout(&self.observed.devices);
        }
        if self.group.rules {
            let list = |what| {
                self.hypr
                    .json(what)
                    .map(|v| v.as_array().cloned().unwrap_or_default())
            };
            self.observed.workspace_rules = list("workspacerules")?;
            self.observed.monitors = list("monitors")?;
            self.observed.workspaces = list("workspaces")?;
        }
        if !self.main_path().exists() {
            self.write_blocked = Some(format!(
                "Settings saves {} settings only in a Lua hyprland.lua configuration",
                self.group.name
            ));
        }
        self.observed.file = match self.read_file() {
            Ok(file) => Some(file),
            Err(message) => {
                self.write_blocked = Some(message);
                None
            }
        };
        self.saved = match fs::read_to_string(&self.saved_path) {
            Ok(text) => {
                let mut saved: Saved = toml::from_str(&text)
                    .map_err(|e| format!("{}: {e}", self.saved_path.display()))?;
                // An option added to the group after first use starts from the system value.
                let missing: Vec<_> = self
                    .group
                    .options
                    .iter()
                    .filter(|o| !saved.options.contains_key(o.id))
                    .collect();
                if !missing.is_empty() {
                    for opt in missing {
                        saved
                            .options
                            .insert(opt.id.into(), self.observed.options[opt.id].clone());
                    }
                    self.save(&saved)?;
                }
                Some(saved)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => match &self.observed.file {
                // First use adopts what the system does now and changes nothing.
                Some(file) => {
                    let saved = self.system(file);
                    self.save(&saved)?;
                    Some(saved)
                }
                None => None,
            },
            Err(e) => return Err(format!("{}: {e}", self.saved_path.display())),
        };
        Ok(())
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.read();
        self.error = result.as_ref().err().cloned();
        result
    }

    fn system(&self, file: &File) -> Saved {
        Saved {
            options: self.observed.options.clone(),
            disabled: file.disabled.clone(),
            shortcuts: file.shortcuts.clone(),
            rules: file.rules.clone(),
        }
    }

    fn save(&self, saved: &Saved) -> Result<(), String> {
        let text = toml::to_string(saved).map_err(|e| e.to_string())?;
        atomic_write(&self.saved_path, text.as_bytes())
    }

    fn conflicts(&self) -> Vec<String> {
        let (Some(saved), Some(file)) = (&self.saved, &self.observed.file) else {
            return vec![];
        };
        let mut ids: Vec<String> = self
            .group
            .options
            .iter()
            .filter(
                |o| match (saved.options.get(o.id), self.observed.options.get(o.id)) {
                    (Some(a), Some(b)) => !same(a, b),
                    _ => false,
                },
            )
            .map(|o| o.id.to_owned())
            .collect();
        if saved.disabled != file.disabled || saved.shortcuts != file.shortcuts {
            ids.push("keyboard-shortcuts".into());
        }
        if saved.rules != file.rules {
            ids.push("workspaces".into());
        }
        ids
    }

    fn keys(&self) -> Option<Keys> {
        Keys::new(&self.observed.layout).ok()
    }

    /// Live shortcuts grouped by submap and combination, in configuration order.
    fn shortcuts(&self, keys: Option<&Keys>) -> Vec<Value> {
        let custom = self
            .saved
            .as_ref()
            .map(|s| s.shortcuts.clone())
            .unwrap_or_default();
        let mut groups: Vec<(String, String, Value)> = Vec::new();
        for bind in &self.observed.binds {
            let mask = bind["modmask"].as_u64().unwrap_or(0) as u32;
            let Some(key) = bind_key(bind) else { continue };
            let combo = keys::combo(mask, &key);
            let submap = bind["submap"].as_str().unwrap_or_default().to_owned();
            if submap == RECORD_SUBMAP {
                continue;
            }
            let description = bind["description"].as_str().unwrap_or_default();
            let action = action_label(bind["dispatcher"].as_str().unwrap_or_default());
            if let Some((_, _, entry)) = groups
                .iter_mut()
                .find(|(s, c, _)| *s == submap && *c == combo)
            {
                if entry["description"] == "" && !description.is_empty() {
                    entry["description"] = json!(description);
                }
                if !entry["actions"]
                    .as_array()
                    .unwrap()
                    .contains(&json!(action))
                {
                    entry["actions"].as_array_mut().unwrap().push(json!(action));
                }
                continue;
            }
            groups.push((
                submap.clone(),
                combo.clone(),
                json!({
                    "keys": combo,
                    "modifiers": keys::modifier_names(mask),
                    "key": key,
                    "label": keys::label(&key, keys),
                    "code": keys::key_code(&key, keys),
                    "submap": submap,
                    "description": description,
                    "actions": [action],
                    "locked": bind["locked"] == true,
                    "mouse": bind["mouse"] == true || key.starts_with("mouse"),
                    "custom": custom.iter().any(|s| keys::press(&s.keys, keys) == keys::press(&combo, keys)),
                }),
            ));
        }
        groups.into_iter().map(|(_, _, entry)| entry).collect()
    }

    /// Every live workspace rule; `settings` marks the ones Settings wrote.
    fn live_rules(&self) -> Vec<Value> {
        let saved = self.saved.as_ref().map(|s| &s.rules[..]).unwrap_or(&[]);
        self.observed
            .workspace_rules
            .iter()
            .map(|e| {
                let workspace = rule_value(e, "workspace");
                json!({
                    "workspace": workspace,
                    "monitor": rule_value(e, "monitor").as_str().unwrap_or_default(),
                    "default": rule_value(e, "default") == true,
                    "persistent": rule_value(e, "persistent") == true,
                    "default_name": rule_value(e, "default_name").as_str().unwrap_or_default(),
                    "settings": saved.iter().any(|r| workspace == r.workspace.as_str()),
                })
            })
            .collect()
    }

    pub fn state(&self) -> Value {
        let keys = self.keys();
        let keys = keys.as_ref();
        let saved = self.saved.as_ref();
        let mice = self.observed.devices["mice"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        let names = |touchpad: bool| {
            mice.iter()
                .filter_map(|m| m["name"].as_str())
                .filter(|n| n.contains("touchpad") == touchpad)
                .collect::<Vec<_>>()
        };
        let labels: BTreeMap<String, String> = keys
            .map(|k| {
                (9..=135)
                    .filter(|code| k.sym(*code).is_some())
                    .map(|code| {
                        (
                            code.to_string(),
                            keys::label(&format!("code:{code}"), Some(k)),
                        )
                    })
                    .collect()
            })
            .unwrap_or_default();
        json!({
            "options": saved.map(|s| &s.options).unwrap_or(&self.observed.options),
            "system": self.observed.options,
            "saved": saved.map(|s| &s.options),
            "conflict": !self.conflicts().is_empty(),
            "conflicts": self.conflicts(),
            "saved_shortcuts": saved.map(|s| &s.shortcuts),
            "system_shortcuts": self.observed.file.as_ref().map(|f| &f.shortcuts),
            "disabled": saved.map(|s| s.disabled.iter().map(|k| caps(k, keys)).collect::<Vec<_>>()),
            "custom": saved.map(|s| s.shortcuts.iter().map(|c| {
                let mut entry = caps(&c.keys, keys);
                entry["action"] = json!(c.action);
                entry["command"] = json!(c.command);
                entry["description"] = json!(c.description);
                entry
            }).collect::<Vec<_>>()),
            "shortcuts": self.shortcuts(keys),
            "key_labels": labels,
            "layout": self.observed.layout.layout,
            "mice": names(false),
            "touchpads": names(true),
            "recording": self.recording,
            "rules": saved.map(|s| &s.rules),
            "system_rules": self.observed.file.as_ref().map(|f| &f.rules),
            "live_rules": self.live_rules(),
            "monitors": self.observed.monitors.iter().map(monitor).collect::<Vec<_>>(),
            "workspaces": self.observed.workspaces.iter().map(|w| json!({
                "id": w["id"], "name": w["name"], "monitor": w["monitor"],
                "windows": w["windows"], "persistent": w["ispersistent"],
            })).collect::<Vec<_>>(),
            "write_blocked": self.write_blocked,
            "error": self.error,
        })
    }

    pub fn setting_value(&self, id: &str) -> Value {
        match self.group.option(id) {
            Some(_) => self.state()["options"][id].clone(),
            None => self.state(),
        }
    }

    fn current(&mut self) -> Result<(Saved, File), String> {
        self.refresh()?;
        if let Some(reason) = &self.write_blocked {
            return Err(reason.clone());
        }
        if !self.conflicts().is_empty() {
            return Err(format!(
                "Resolve the {} settings conflict first",
                self.group.name
            ));
        }
        let saved = self
            .saved
            .clone()
            .ok_or(format!("{} settings are not initialized", self.group.name))?;
        Ok((saved, self.observed.file.clone().unwrap_or_default()))
    }

    fn wait<T>(&self, mut check: impl FnMut() -> Result<Option<T>, String>) -> Result<T, String> {
        let started = Instant::now();
        loop {
            if let Some(value) = check()? {
                return Ok(value);
            }
            if started.elapsed() > Duration::from_secs(3) {
                return Err(format!(
                    "Hyprland did not load the changed {} configuration",
                    self.group.name
                ));
            }
            thread::sleep(Duration::from_millis(50));
        }
    }

    /// True when every saved shortcut is live and every turned-off combination is gone.
    fn binds_match(&self, saved: &Saved, binds: &[Value]) -> bool {
        let keys = self.keys();
        let press = |text: &str| keys::press(text, keys.as_ref());
        let live: Vec<_> = binds
            .iter()
            .filter(|b| b["submap"] == "")
            .filter_map(|b| press(&keys::combo(b["modmask"].as_u64()? as u32, &bind_key(b)?)))
            .collect();
        let present = |text: &str| press(text).is_some_and(|p| live.contains(&p));
        let custom = |text: &str| {
            saved
                .shortcuts
                .iter()
                .any(|s| press(&s.keys) == press(text))
        };
        saved.shortcuts.iter().all(|s| present(&s.keys))
            && saved.disabled.iter().all(|k| custom(k) || !present(k))
    }

    /// Persists `next`, applying option changes live first so Hyprland validates them.
    fn write(&mut self, next: Saved, mut owned: File) -> Result<(), String> {
        let live = self.observed.options.clone();
        let changed: Vec<_> = self
            .group
            .options
            .iter()
            .filter(|o| match (next.options.get(o.id), live.get(o.id)) {
                (Some(a), Some(b)) => !same(a, b),
                _ => false,
            })
            .collect();
        for opt in &changed {
            self.hypr
                .eval(&config::option_line(opt, &next.options[opt.id]))?;
            owned
                .options
                .insert(opt.id.into(), next.options[opt.id].clone());
        }
        // Binds and rules load only through a configuration reload.
        let reload = (owned.disabled != next.disabled
            || owned.shortcuts != next.shortcuts
            || owned.rules != next.rules)
            .then(|| owned.rules.clone());
        owned.disabled = next.disabled.clone();
        owned.shortcuts = next.shortcuts.clone();
        owned.rules = next.rules.clone();
        let result = (|| {
            let (options, _) = self.read_options()?;
            for opt in &changed {
                if !same(&options[opt.id], &next.options[opt.id]) {
                    return Err(format!("Hyprland did not apply {}", opt.name));
                }
            }
            self.write_files(&owned, reload.as_deref(), &next)
        })();
        if let Err(message) = result {
            // Leave the compositor as it was; the files were restored by `write_files`.
            for opt in &changed {
                let _ = self.hypr.eval(&config::option_line(opt, &live[opt.id]));
            }
            return Err(message);
        }
        self.save(&next)?;
        self.saved = Some(next);
        Ok(())
    }

    /// `reload` holds the rules the file had before, when binds or rules changed.
    fn write_files(
        &self,
        owned: &File,
        reload: Option<&[WorkspaceRule]>,
        next: &Saved,
    ) -> Result<(), String> {
        let main = fs::read_to_string(self.main_path())
            .map_err(|e| format!("{}: {e}", self.main_path().display()))?;
        let block = config::with_block(self.group, &main)?;
        let text = config::render(self.group, owned);
        if config::parse(self.group, &text).as_ref() != Ok(owned) {
            return Err("Refusing to write settings that do not read back".into());
        }
        let path = self.file_path();
        let before = fs::read(&path).ok();
        fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
        atomic_write(&path, text.as_bytes())?;
        let applied = (|| {
            // The require must exist before Hyprland reloads, or the file is ignored.
            if let Some(main) = &block {
                atomic_write(&self.main_path(), main.as_bytes())?;
            }
            if let Some(before) = reload {
                if !self.observed.autoreload {
                    self.hypr.request(&["reload"])?;
                }
                let list = |what| {
                    self.hypr
                        .json(what)
                        .map(|v| v.as_array().cloned().unwrap_or_default())
                };
                self.wait(|| {
                    let binds = !self.group.shortcuts || self.binds_match(next, &list("binds")?);
                    let rules = !self.group.rules
                        || rules_match(&next.rules, before, &list("workspacerules")?);
                    Ok((binds && rules).then_some(()))
                })?;
            }
            Ok(())
        })();
        if let Err(message) = applied {
            match before {
                Some(bytes) => atomic_write(&path, &bytes)?,
                None => fs::remove_file(&path).map_err(|e| e.to_string())?,
            }
            if block.is_some() {
                atomic_write(&self.main_path(), main.as_bytes())?;
            }
            return Err(message);
        }
        Ok(())
    }

    fn validate_shortcut(&self, request: &Value) -> Result<(Shortcut, bool), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request {
            keys: String,
            action: String,
            #[serde(default)]
            command: String,
            #[serde(default)]
            description: String,
            #[serde(default)]
            replace: bool,
            /// The combination of the shortcut being edited; read by `apply`.
            #[serde(default)]
            #[allow(dead_code)]
            previous: Option<String>,
        }
        let r: Request = serde_json::from_value(request.clone())
            .map_err(|_| invalid("Expected keys, action, command, description and replace"))?;
        let keys = self.canonical(&r.keys)?;
        if r.action == "command" {
            if r.command.trim().is_empty() || !config::plain(&r.command, 4096) {
                return Err(invalid("Enter a command on one line"));
            }
        } else if !config::ACTIONS.iter().any(|(name, _)| *name == r.action)
            || !r.command.is_empty()
        {
            return Err(invalid("Unknown shortcut action"));
        }
        if !config::plain(&r.description, 200) {
            return Err(invalid("Use a one-line description"));
        }
        Ok((
            Shortcut {
                keys,
                action: r.action,
                command: r.command.trim().to_owned(),
                description: r.description.trim().to_owned(),
            },
            r.replace,
        ))
    }

    /// Canonical spelling for a new shortcut: named keysyms rather than keycodes.
    fn canonical(&self, text: &str) -> Result<String, String> {
        let (mask, key) =
            keys::parse_combo(text).ok_or_else(|| invalid("Unknown key combination"))?;
        let keys = self.keys();
        let key = match key
            .strip_prefix("code:")
            .and_then(|c| c.parse::<u32>().ok())
        {
            Some(code) => keys
                .as_ref()
                .and_then(|k| k.sym(code))
                .map(xkbcommon::xkb::keysym_get_name)
                .unwrap_or(key),
            None if keys::parse_sym(&key).is_some() => {
                xkbcommon::xkb::keysym_get_name(keys::parse_sym(&key).unwrap())
            }
            None => return Err(invalid("Unknown key")),
        };
        if xkbcommon::xkb::keysym_from_name(&key, 0).is_modifier_key() {
            return Err(invalid(
                "Finish the combination with a key that is not a modifier",
            ));
        }
        if mask & (64 | 4 | 8) == 0 && !keys::standalone(&key) {
            return Err(invalid("Add Super, Ctrl or Alt so typing is not affected"));
        }
        Ok(keys::combo(mask, &key))
    }

    /// Live shortcuts that a new combination would collide with.
    pub fn lookup(&mut self, request: &str) -> Result<Value, String> {
        let _ = self.refresh();
        let keys_text = serde_json::from_str::<Value>(request)
            .ok()
            .and_then(|v| v["keys"].as_str().map(str::to_owned))
            .ok_or_else(|| invalid("Expected {\"keys\":\"SUPER + code:24\"}"))?;
        let canonical = self.canonical(&keys_text)?;
        let (mask, key) = keys::parse_combo(&canonical).unwrap();
        let keys = self.keys();
        let wanted = keys::press(&canonical, keys.as_ref());
        let conflicts: Vec<Value> = self
            .shortcuts(keys.as_ref())
            .into_iter()
            .filter(|s| {
                s["submap"] == ""
                    && keys::press(s["keys"].as_str().unwrap_or_default(), keys.as_ref()) == wanted
            })
            .collect();
        Ok(json!({
            "keys": canonical,
            "modifiers": keys::modifier_names(mask),
            "label": keys::label(&key, keys.as_ref()),
            "conflicts": conflicts,
        }))
    }

    fn apply(&mut self, id: &str, input: &str) -> Result<(), String> {
        let value: Value = serde_json::from_str(input).map_err(|_| invalid("Expected JSON"))?;
        if id == RECORD {
            return self.record(&value);
        }
        if id == LIST {
            return Err(invalid("The shortcut list is read-only"));
        }
        let (mut next, owned) = self.current()?;
        match id {
            ADD | REMOVE | DISABLE if !self.group.shortcuts => {
                return Err(invalid("Unknown setting"));
            }
            RULE_SET if self.group.rules => {
                let (rule, previous) = validate_rule(&value)?;
                let edited = previous.as_deref().unwrap_or(&rule.workspace);
                if edited != rule.workspace
                    && next.rules.iter().any(|r| r.workspace == rule.workspace)
                {
                    return Err(invalid(format!(
                        "Workspace {} already has a rule",
                        rule.workspace
                    )));
                }
                let at = next.rules.iter().position(|r| r.workspace == edited);
                next.rules.retain(|r| r.workspace != edited);
                // A display starts with one workspace, so the newest choice wins.
                if rule.default {
                    for other in next.rules.iter_mut().filter(|r| r.monitor == rule.monitor) {
                        other.default = false;
                    }
                }
                next.rules.insert(at.unwrap_or(next.rules.len()), rule);
            }
            RULE_REMOVE if self.group.rules => {
                let workspace = value["workspace"]
                    .as_str()
                    .ok_or_else(|| invalid("Expected {\"workspace\":...}"))?;
                let before = next.rules.len();
                next.rules.retain(|r| r.workspace != workspace);
                if before == next.rules.len() {
                    return Err(invalid("Settings has no rule for that workspace"));
                }
            }
            ADD => {
                let (shortcut, replace) = self.validate_shortcut(&value)?;
                let previous = value["previous"].as_str().map(str::to_owned);
                next.shortcuts
                    .retain(|s| Some(&s.keys) != previous.as_ref());
                let conflicts =
                    self.lookup(&json!({"keys": shortcut.keys}).to_string())?["conflicts"]
                        .as_array()
                        .cloned()
                        .unwrap_or_default();
                let foreign: Vec<_> = conflicts
                    .iter()
                    .filter(|c| c["keys"].as_str() != previous.as_deref())
                    .collect();
                if !foreign.is_empty() {
                    if !replace {
                        return Err(format!(
                            "Conflict:{} is already used. Replace it to continue.",
                            shortcut.keys
                        ));
                    }
                    for conflict in foreign {
                        let keys = conflict["keys"].as_str().unwrap_or_default().to_owned();
                        next.shortcuts.retain(|s| s.keys != keys);
                        if conflict["custom"] != true && !next.disabled.contains(&keys) {
                            next.disabled.push(keys);
                        }
                    }
                }
                next.shortcuts.push(shortcut);
            }
            REMOVE => {
                let keys = value["keys"]
                    .as_str()
                    .ok_or_else(|| invalid("Expected {\"keys\":...}"))?;
                let before = next.shortcuts.len();
                next.shortcuts.retain(|s| s.keys != keys);
                if before == next.shortcuts.len() {
                    return Err(invalid("No custom shortcut uses that combination"));
                }
            }
            DISABLE => {
                let keys = value["keys"]
                    .as_str()
                    .ok_or_else(|| invalid("Expected keys"))?;
                let disabled = value["disabled"]
                    .as_bool()
                    .ok_or_else(|| invalid("Expected disabled"))?;
                let (mask, key) =
                    keys::parse_combo(keys).ok_or_else(|| invalid("Unknown key combination"))?;
                let keys = keys::combo(mask, &key);
                if disabled {
                    if !next.disabled.contains(&keys) {
                        next.disabled.push(keys);
                    }
                } else if next.disabled.contains(&keys) {
                    next.disabled.retain(|k| *k != keys);
                } else {
                    return Err(invalid("That combination is not turned off"));
                }
            }
            _ => {
                let opt = self
                    .group
                    .option(id)
                    .ok_or_else(|| invalid("Unknown setting"))?;
                let validated = opt.validate(&value)?;
                if id == "sound.compositor-bell"
                    && let Some(path) = validated.as_str()
                    && !matches!(path, "default" | "none")
                    && !PathBuf::from(path).is_file()
                {
                    return Err(invalid(format!("{path} does not exist")));
                }
                next.options.insert(id.into(), validated);
            }
        }
        self.write(next, owned)
    }

    /// Suspends compositor shortcuts in an empty submap so the recorder sees every key.
    /// Escape, a reload or `stop` leaves it; the service also stops it when the GUI exits.
    fn record(&mut self, value: &Value) -> Result<(), String> {
        match value.as_bool() {
            Some(true) => {
                self.hypr.eval(&format!(
                    "hl.define_submap(\"{RECORD_SUBMAP}\", function() hl.bind(\"Escape\", hl.dsp.submap(\"reset\"), {{ non_consuming = true }}) end)"
                ))?;
                self.hypr
                    .eval(&format!("hl.dispatch(hl.dsp.submap(\"{RECORD_SUBMAP}\"))"))?;
                self.recording = true;
                Ok(())
            }
            Some(false) => self.stop_recording(),
            None => Err(invalid("Use true or false")),
        }
    }

    pub fn stop_recording(&mut self) -> Result<(), String> {
        self.recording = false;
        let current = self.hypr.json("submap")?;
        if current == RECORD_SUBMAP {
            self.hypr.eval("hl.dispatch(hl.dsp.submap(\"reset\"))")?;
        }
        Ok(())
    }

    pub fn is_recording(&self) -> bool {
        self.recording
    }

    fn finish(&mut self, result: Result<(), String>) -> Result<Value, String> {
        let _ = self.refresh();
        if let Err(message) = &result
            && !message.starts_with("InvalidArgument:")
            && !message.starts_with("Conflict:")
        {
            self.error = Some(message.clone());
        }
        result.map(|_| self.state())
    }

    pub fn set(&mut self, id: &str, input: &str) -> Result<Value, String> {
        let result = self.apply(id, input);
        self.finish(result)
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let result = (|| {
            self.refresh()?;
            let file = self
                .observed
                .file
                .clone()
                .ok_or_else(|| self.write_blocked.clone().unwrap_or_default())?;
            match source {
                "system" => {
                    let saved = self.system(&file);
                    // The owned file loads last, so a stale value in it would return on reload.
                    let mut owned = file.clone();
                    let mut stale = false;
                    for (id, value) in owned.options.iter_mut() {
                        if let Some(live) = saved.options.get(id).filter(|v| !v.is_null())
                            && !same(value, live)
                        {
                            *value = live.clone();
                            stale = true;
                        }
                    }
                    if stale {
                        if let Some(reason) = &self.write_blocked {
                            return Err(reason.clone());
                        }
                        self.write_files(&owned, None, &saved)?;
                    }
                    self.save(&saved)
                }
                "settings" => {
                    if let Some(reason) = &self.write_blocked {
                        return Err(reason.clone());
                    }
                    let saved = self.saved.clone().ok_or("Nothing is saved yet")?;
                    self.write(saved, file)
                }
                _ => Err(invalid("Unknown resolution")),
            }
        })();
        self.finish(result)
    }
}

#[cfg(test)]
mod tests;
