//! The Settings-owned `remya-settings/input.lua` and its one-line `require` in
//! `hyprland.lua`. Only the exact shapes rendered here are accepted, so a file that
//! has been edited into something else is never overwritten.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    Bool,
    Int(i64, i64),
    Float(f64, f64),
    /// Writable strings. Reads may also report Hyprland's empty default.
    Text(&'static [&'static str]),
}

pub struct Opt {
    pub id: &'static str,
    /// The `hyprctl getoption` / `descriptions` name.
    pub name: &'static str,
    pub kind: Kind,
}

impl Opt {
    /// Lua tables use underscores where some legacy option names use hyphens.
    pub fn path(&self) -> Vec<String> {
        self.name.split(':').map(|p| p.replace('-', "_")).collect()
    }

    pub fn validate(&self, value: &Value) -> Result<Value, String> {
        let invalid = |m: String| Err(format!("InvalidArgument:{m}"));
        match self.kind {
            Kind::Bool => match value.as_bool() {
                Some(b) => Ok(json!(b)),
                None => invalid("Use true or false".into()),
            },
            Kind::Int(min, max) => match value.as_i64().filter(|v| (min..=max).contains(v)) {
                Some(v) => Ok(json!(v)),
                None => invalid(format!("Use a whole number from {min} to {max}")),
            },
            Kind::Float(min, max) => match value.as_f64().filter(|v| (min..=max).contains(v)) {
                Some(v) => Ok(json!(round(v))),
                None => invalid(format!("Use a number from {min} to {max}")),
            },
            Kind::Text(allowed) => match value.as_str().filter(|v| allowed.contains(v)) {
                Some(v) => Ok(json!(v)),
                None => invalid(format!("Use one of {}", allowed.join(", "))),
            },
        }
    }

    /// Converts a `descriptions` reading to the value shape `validate` produces.
    pub fn observed(&self, current: &Value) -> Value {
        match self.kind {
            Kind::Bool => json!(current.as_bool().or(current.as_i64().map(|v| v != 0))),
            Kind::Int(..) => json!(current.as_i64().or(current.as_f64().map(|v| v as i64))),
            Kind::Float(..) => json!(current.as_f64().map(round)),
            Kind::Text(_) => match current.as_str() {
                Some("[[EMPTY]]") | None => json!(""),
                Some(text) => json!(text),
            },
        }
    }
}

/// Settings writes three decimals; finer readback differences are noise.
fn round(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

macro_rules! opts {
    ($(($id:literal, $name:expr, $kind:expr)),* $(,)?) => {
        pub const OPTIONS: &[Opt] = &[$(Opt { id: $id, name: $name, kind: $kind }),*];
    };
}
opts![
    ("mouse.primary-button", "input:left_handed", Kind::Bool),
    (
        "mouse.pointer-speed",
        "input:sensitivity",
        Kind::Float(-1.0, 1.0)
    ),
    (
        "mouse.acceleration",
        "input:accel_profile",
        Kind::Text(&["adaptive", "flat"])
    ),
    ("mouse.natural-scroll", "input:natural_scroll", Kind::Bool),
    (
        "mouse.scroll-speed",
        "input:scroll_factor",
        Kind::Float(0.0, 100.0)
    ),
    ("mouse.focus-follows", "input:follow_mouse", Kind::Int(0, 3)),
    (
        "mouse.middle-click-paste",
        "misc:middle_click_paste",
        Kind::Bool
    ),
    ("mouse.refocus", "input:mouse_refocus", Kind::Bool),
    (
        "mouse.monitor-focus",
        "misc:mouse_move_focuses_monitor",
        Kind::Bool
    ),
    (
        "mouse.discrete-scroll",
        "input:emulate_discrete_scroll",
        Kind::Int(0, 2)
    ),
    (
        "mouse.scroll-outside",
        "input:off_window_axis_events",
        Kind::Int(0, 3)
    ),
    (
        "touchpad.disable-while-typing",
        "input:touchpad:disable_while_typing",
        Kind::Bool
    ),
    (
        "touchpad.tap-to-click",
        "input:touchpad:tap-to-click",
        Kind::Bool
    ),
    (
        "touchpad.tap-buttons",
        "input:touchpad:tap_button_map",
        Kind::Text(&["lrm", "lmr"])
    ),
    (
        "touchpad.tap-and-drag",
        "input:touchpad:tap-and-drag",
        Kind::Bool
    ),
    (
        "touchpad.drag-lock",
        "input:touchpad:drag_lock",
        Kind::Int(0, 2)
    ),
    (
        "touchpad.click-method",
        "input:touchpad:clickfinger_behavior",
        Kind::Bool
    ),
    (
        "touchpad.natural-scroll",
        "input:touchpad:natural_scroll",
        Kind::Bool
    ),
    (
        "touchpad.scroll-speed",
        "input:touchpad:scroll_factor",
        Kind::Float(0.0, 100.0)
    ),
    (
        "touchpad.three-finger-drag",
        "input:touchpad:drag_3fg",
        Kind::Int(0, 2)
    ),
    (
        "touchpad.middle-button",
        "input:touchpad:middle_button_emulation",
        Kind::Bool
    ),
    (
        "touchpad.swipe-distance",
        "gestures:workspace_swipe_distance",
        Kind::Int(0, 2000)
    ),
    (
        "touchpad.swipe-invert",
        "gestures:workspace_swipe_invert",
        Kind::Bool
    ),
    (
        "touchpad.swipe-create-new",
        "gestures:workspace_swipe_create_new",
        Kind::Bool
    ),
    (
        "touchpad.swipe-cancel-ratio",
        "gestures:workspace_swipe_cancel_ratio",
        Kind::Float(0.0, 1.0)
    ),
    (
        "touchpad.swipe-min-speed",
        "gestures:workspace_swipe_min_speed_to_force",
        Kind::Int(0, 200)
    ),
    (
        "touchpad.swipe-forever",
        "gestures:workspace_swipe_forever",
        Kind::Bool
    ),
    (
        "touchpad.swipe-direction-lock",
        "gestures:workspace_swipe_direction_lock",
        Kind::Bool
    ),
    (
        "keyboard-shortcuts.workspace-back-and-forth",
        "binds:workspace_back_and_forth",
        Kind::Int(0, 2)
    ),
    (
        "keyboard-shortcuts.workspace-cycles",
        "binds:allow_workspace_cycles",
        Kind::Bool
    ),
    (
        "keyboard-shortcuts.scroll-delay",
        "binds:scroll_event_delay",
        Kind::Int(0, 2000)
    ),
    (
        "keyboard-shortcuts.pass-mouse",
        "binds:pass_mouse_when_bound",
        Kind::Bool
    ),
];

pub fn option(id: &str) -> Option<&'static Opt> {
    OPTIONS.iter().find(|o| o.id == id)
}

/// The fixed actions a custom shortcut may run; nothing else reaches the Lua file.
pub const ACTIONS: &[(&str, &str)] = &[
    ("close", "hl.dsp.window.close()"),
    ("float", "hl.dsp.window.float({ action = \"toggle\" })"),
    (
        "fullscreen",
        "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })",
    ),
    (
        "maximize",
        "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })",
    ),
    ("pin", "hl.dsp.window.pin()"),
    ("scratchpad", "hl.dsp.workspace.toggle_special(\"special\")"),
];

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Shortcut {
    pub keys: String,
    pub action: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub command: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct File {
    pub options: BTreeMap<String, Value>,
    pub disabled: Vec<String>,
    pub shortcuts: Vec<Shortcut>,
}

pub const HEADER: &str =
    "-- Managed by Remy'a Settings. Change Mouse, Touchpad and Keyboard shortcuts in Settings.";
pub const BEGIN: &str = "-- BEGIN Remy'a Settings input";
pub const END: &str = "-- END Remy'a Settings input";
pub const BLOCK: &str = "-- BEGIN Remy'a Settings input\nrequire(\"remya-settings.input\")\n-- END Remy'a Settings input\n";

pub fn quote(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

/// Text Settings is willing to place inside a Lua string.
pub fn plain(text: &str, limit: usize) -> bool {
    text.len() <= limit && !text.chars().any(char::is_control)
}

pub fn literal(value: &Value) -> String {
    match value {
        Value::String(s) => quote(s),
        other => other.to_string(),
    }
}

pub fn option_line(opt: &Opt, value: &Value) -> String {
    let path = opt.path();
    let mut text = literal(value);
    for key in path.iter().rev() {
        text = format!("{{ {key} = {text} }}");
    }
    format!("hl.config({text})")
}

pub fn action_code(shortcut: &Shortcut) -> Option<String> {
    if shortcut.action == "command" {
        return Some(format!("hl.dsp.exec_cmd({})", quote(&shortcut.command)));
    }
    ACTIONS
        .iter()
        .find(|(name, _)| *name == shortcut.action)
        .map(|(_, code)| (*code).to_owned())
}

pub fn bind_line(shortcut: &Shortcut) -> String {
    let action = action_code(shortcut).unwrap_or_default();
    if shortcut.description.is_empty() {
        format!("hl.bind({}, {action})", quote(&shortcut.keys))
    } else {
        format!(
            "hl.bind({}, {action}, {{ description = {} }})",
            quote(&shortcut.keys),
            quote(&shortcut.description)
        )
    }
}

pub fn render(file: &File) -> String {
    let mut text = format!("{HEADER}\n");
    for opt in OPTIONS {
        if let Some(value) = file.options.get(opt.id) {
            text += &option_line(opt, value);
            text.push('\n');
        }
    }
    // Unbinds come first so a custom shortcut may take over a turned-off combination.
    for keys in &file.disabled {
        text += &format!("hl.unbind({})\n", quote(keys));
    }
    for shortcut in &file.shortcuts {
        text += &bind_line(shortcut);
        text.push('\n');
    }
    text
}

/// Reads one double-quoted Lua string at the start of `text`.
fn string(text: &str) -> Option<(String, &str)> {
    let mut chars = text.strip_prefix('"')?.char_indices();
    let mut out = String::new();
    while let Some((at, c)) = chars.next() {
        match c {
            '"' => return Some((out, &text[at + 2..])),
            '\\' => match chars.next()?.1 {
                c @ ('\\' | '"') => out.push(c),
                _ => return None,
            },
            c if c.is_control() => return None,
            c => out.push(c),
        }
    }
    None
}

fn value(text: &str, kind: Kind) -> Option<Value> {
    match kind {
        Kind::Bool => text.parse::<bool>().ok().map(Value::from),
        Kind::Int(..) => text.parse::<i64>().ok().map(Value::from),
        Kind::Float(..) => text.parse::<f64>().ok().map(Value::from),
        Kind::Text(_) => string(text)
            .filter(|(_, rest)| rest.is_empty())
            .map(|(s, _)| s.into()),
    }
}

fn bind(line: &str) -> Option<Shortcut> {
    let (keys, rest) = string(line.strip_prefix("hl.bind(")?)?;
    let rest = rest.strip_prefix(", ")?;
    let mut shortcut = Shortcut {
        keys,
        ..Shortcut::default()
    };
    let rest = if let Some(command) = rest.strip_prefix("hl.dsp.exec_cmd(") {
        let (command, rest) = string(command)?;
        shortcut.action = "command".into();
        shortcut.command = command;
        rest.strip_prefix(')')?
    } else {
        let (name, code) = ACTIONS.iter().find(|(_, code)| rest.starts_with(code))?;
        shortcut.action = (*name).into();
        &rest[code.len()..]
    };
    if let Some(described) = rest.strip_prefix(", { description = ") {
        let (description, rest) = string(described)?;
        (rest == " })").then_some(())?;
        shortcut.description = description;
    } else {
        (rest == ")").then_some(())?;
    }
    Some(shortcut)
}

pub fn parse(text: &str) -> Result<File, String> {
    let mut file = File::default();
    for (number, line) in text.lines().enumerate() {
        let line = line.trim();
        let refuse = || format!("Settings cannot safely edit input.lua line {}", number + 1);
        if line.is_empty() || line.starts_with("--") {
            continue;
        }
        if let Some(keys) = line.strip_prefix("hl.unbind(") {
            match string(keys) {
                Some((keys, ")")) => file.disabled.push(keys),
                _ => return Err(refuse()),
            }
            continue;
        }
        if line.starts_with("hl.bind(") {
            file.shortcuts.push(bind(line).ok_or_else(refuse)?);
            continue;
        }
        let parsed = OPTIONS.iter().find_map(|opt| {
            let empty = option_line(opt, &Value::Null);
            let (prefix, suffix) = empty.split_once("null")?;
            let inner = line.strip_prefix(prefix)?.strip_suffix(suffix)?;
            Some((opt, value(inner, opt.kind)?))
        });
        let (opt, value) = parsed.ok_or_else(refuse)?;
        file.options.insert(opt.id.into(), value);
    }
    if render(&file) != format!("{HEADER}\n{}", strip_header(text)) {
        return Err(
            "Settings cannot safely edit input.lua: it was changed outside Settings".into(),
        );
    }
    Ok(file)
}

fn strip_header(text: &str) -> String {
    text.lines()
        .filter(|l| !l.trim().is_empty() && !l.trim().starts_with("--"))
        .map(|l| format!("{}\n", l.trim()))
        .collect()
}

/// Appends the `require` block, or confirms the existing one is intact.
pub fn with_block(main: &str) -> Result<Option<String>, String> {
    match (main.find(BEGIN), main.find(END)) {
        (None, None) => {
            let separator = if main.is_empty() || main.ends_with('\n') {
                ""
            } else {
                "\n"
            };
            Ok(Some(format!("{main}{separator}{BLOCK}")))
        }
        (Some(start), Some(end)) if main[start..end + END.len()] == BLOCK[..BLOCK.len() - 1] => {
            Ok(None)
        }
        _ => Err("The Remy'a Settings input block in hyprland.lua was edited".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> File {
        File {
            options: BTreeMap::from([
                ("mouse.pointer-speed".into(), json!(0.25)),
                ("touchpad.tap-to-click".into(), json!(false)),
                ("mouse.acceleration".into(), json!("flat")),
            ]),
            disabled: vec!["SUPER + J".into()],
            shortcuts: vec![
                Shortcut {
                    keys: "SUPER + Return".into(),
                    action: "command".into(),
                    command: "foot -e \"htop\"".into(),
                    description: "Open \\ monitor".into(),
                },
                Shortcut {
                    keys: "SUPER + q".into(),
                    action: "close".into(),
                    ..Shortcut::default()
                },
            ],
        }
    }

    #[test]
    fn rendered_files_read_back_exactly() {
        let text = render(&sample());
        assert!(text.contains("hl.config({ input = { touchpad = { tap_to_click = false } } })"));
        assert!(text.find("hl.unbind").unwrap() < text.find("hl.bind").unwrap());
        assert_eq!(parse(&text).unwrap(), sample());
        assert_eq!(parse("").unwrap(), File::default());
    }

    #[test]
    fn foreign_lua_is_refused() {
        for text in [
            "os.execute(\"rm -rf ~\")\n",
            "hl.config({ input = { sensitivity = 0.2 } }) os.exit()\n",
            "hl.bind(\"SUPER + K\", function() end)\n",
            "hl.bind(\"SUPER + K\", hl.dsp.exec_cmd(\"a\" .. \"b\"))\n",
            "hl.config({ input = { kb_layout = \"de\" } })\n",
        ] {
            assert!(parse(text).is_err(), "{text}");
        }
    }

    #[test]
    fn values_are_validated_by_kind() {
        let speed = option("mouse.pointer-speed").unwrap();
        assert_eq!(speed.validate(&json!(0.12345)).unwrap(), json!(0.123));
        assert!(speed.validate(&json!(2)).is_err());
        let accel = option("mouse.acceleration").unwrap();
        assert!(accel.validate(&json!("custom 1 2")).is_err());
        assert_eq!(accel.observed(&json!("[[EMPTY]]")), json!(""));
        assert_eq!(
            option("touchpad.swipe-distance").unwrap().name,
            "gestures:workspace_swipe_distance"
        );
    }

    #[test]
    fn require_block_is_added_once_and_guarded() {
        let main = "hl.config({})";
        let added = with_block(main).unwrap().unwrap();
        assert!(added.ends_with(BLOCK) && added.starts_with("hl.config({})\n"));
        assert_eq!(with_block(&added).unwrap(), None);
        assert!(with_block(&added.replace("require", "-- require")).is_err());
    }
}
