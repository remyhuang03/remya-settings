//! Window rules (`hl.window_rule`) and session environment variables (`hl.env`) in
//! the Settings-owned `desktop.lua`. Each is rendered in one fixed line shape and read
//! back only in exactly that shape.
use crate::config::{plain, quote, string};
use serde::{Deserialize, Serialize};
use serde_json::Value;

fn invalid(message: impl std::fmt::Display) -> String {
    format!("InvalidArgument:{message}")
}

fn is_false(b: &bool) -> bool {
    !b
}

/// The subset of `hl.window_rule` Settings edits: which app or title, and what happens.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct WindowRule {
    /// The exact app class, such as `org.gnome.Nautilus`.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub class: String,
    /// Text the window title contains.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub title: String,
    #[serde(skip_serializing_if = "is_false")]
    pub float: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub center: bool,
    /// Width and height in percent of the display.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<[u8; 2]>,
    /// A workspace selector, as workspace rules use.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub workspace: String,
    /// Open on `workspace` without switching to it.
    #[serde(skip_serializing_if = "is_false")]
    pub silent: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub pin: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub maximize: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub fullscreen: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub no_initial_focus: bool,
    /// Window opacity in percent.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opacity: Option<u8>,
    #[serde(skip_serializing_if = "is_false")]
    pub no_blur: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub no_shadow: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub keep_aspect_ratio: bool,
    /// `focus`, `fullscreen` or `always`.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub idle_inhibit: String,
}

pub const IDLE_INHIBIT: &[&str] = &["focus", "fullscreen", "always"];
const FLAGS: &[&str] = &[
    "float",
    "center",
    "pin",
    "maximize",
    "fullscreen",
    "no_initial_focus",
    "no_blur",
    "no_shadow",
    "keep_aspect_ratio",
];

impl WindowRule {
    fn flag(&mut self, name: &str) -> &mut bool {
        match name {
            "float" => &mut self.float,
            "center" => &mut self.center,
            "pin" => &mut self.pin,
            "maximize" => &mut self.maximize,
            "fullscreen" => &mut self.fullscreen,
            "no_initial_focus" => &mut self.no_initial_focus,
            "no_blur" => &mut self.no_blur,
            "no_shadow" => &mut self.no_shadow,
            _ => &mut self.keep_aspect_ratio,
        }
    }

    /// Rules are identified by what they match.
    pub fn key(&self) -> (&str, &str) {
        (&self.class, &self.title)
    }

    pub fn validate(mut self, workspace: impl Fn(&str) -> Option<String>) -> Result<Self, String> {
        self.class = self.class.trim().to_owned();
        self.title = self.title.trim().to_owned();
        if self.class.is_empty() && self.title.is_empty() {
            return Err(invalid(
                "Choose an app or the text its window title contains",
            ));
        }
        if !plain(&self.class, 256) || !plain(&self.title, 256) {
            return Err(invalid("Use one line of up to 256 characters"));
        }
        if !self.float && (self.center || self.size.is_some()) {
            return Err(invalid("Centering and size apply to floating windows only"));
        }
        if self
            .size
            .is_some_and(|s| s.iter().any(|v| !(10..=100).contains(v)))
        {
            return Err(invalid(
                "Use a width and height from 10% to 100% of the display",
            ));
        }
        if !self.workspace.is_empty() {
            self.workspace = workspace(&self.workspace)
                .ok_or_else(|| invalid("Use a workspace number, name:<name> or special:<name>"))?;
            if self.workspace.ends_with(" silent") {
                return Err(invalid("A workspace name cannot end with silent"));
            }
        } else if self.silent {
            return Err(invalid("Choose a workspace to open the window on"));
        }
        if self.maximize && self.fullscreen {
            return Err(invalid("Choose maximized or full screen, not both"));
        }
        if self.opacity.is_some_and(|o| !(10..=100).contains(&o)) {
            return Err(invalid("Use an opacity from 10% to 100%"));
        }
        if !self.idle_inhibit.is_empty() && !IDLE_INHIBIT.contains(&self.idle_inhibit.as_str()) {
            return Err(invalid("Use focus, fullscreen or always"));
        }
        let effect = FLAGS.iter().any(|f| *self.clone().flag(f))
            || self.size.is_some()
            || !self.workspace.is_empty()
            || self.opacity.is_some()
            || !self.idle_inhibit.is_empty();
        if !effect {
            return Err(invalid("Choose at least one thing the rule does"));
        }
        Ok(self)
    }
}

/// Hyprland matches with RE2; Settings writes literal text only.
const META: &str = "\\.^$|?*+()[]{}";

fn escape(text: &str) -> String {
    text.chars()
        .flat_map(|c| META.contains(c).then_some('\\').into_iter().chain([c]))
        .collect()
}

fn unescape(text: &str) -> Option<String> {
    let mut out = String::new();
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => out.push(chars.next().filter(|n| META.contains(*n))?),
            c if META.contains(c) => return None,
            c => out.push(c),
        }
    }
    Some(out)
}

fn percent(v: u8) -> String {
    format!("{}", v as f64 / 100.0)
}

pub fn rule_line(rule: &WindowRule) -> String {
    let mut matches = vec![];
    if !rule.class.is_empty() {
        matches.push(format!(
            "class = {}",
            quote(&format!("^({})$", escape(&rule.class)))
        ));
    }
    if !rule.title.is_empty() {
        matches.push(format!(
            "title = {}",
            quote(&format!(".*({}).*", escape(&rule.title)))
        ));
    }
    let mut fields = vec![format!("match = {{ {} }}", matches.join(", "))];
    let mut flag = |name: &str, on: bool| on.then(|| fields.push(format!("{name} = true")));
    flag("float", rule.float);
    flag("center", rule.center);
    if let Some([w, h]) = rule.size {
        fields.push(format!(
            "size = {{ \"(monitor_w*{})\", \"(monitor_h*{})\" }}",
            percent(w),
            percent(h)
        ));
    }
    if !rule.workspace.is_empty() {
        let silent = if rule.silent { " silent" } else { "" };
        fields.push(format!(
            "workspace = {}",
            quote(&format!("{}{silent}", rule.workspace))
        ));
    }
    let mut flag = |name: &str, on: bool| on.then(|| fields.push(format!("{name} = true")));
    flag("pin", rule.pin);
    flag("maximize", rule.maximize);
    flag("fullscreen", rule.fullscreen);
    flag("no_initial_focus", rule.no_initial_focus);
    if let Some(o) = rule.opacity {
        fields.push(format!("opacity = {}", percent(o)));
    }
    let mut flag = |name: &str, on: bool| on.then(|| fields.push(format!("{name} = true")));
    flag("no_blur", rule.no_blur);
    flag("no_shadow", rule.no_shadow);
    flag("keep_aspect_ratio", rule.keep_aspect_ratio);
    if !rule.idle_inhibit.is_empty() {
        fields.push(format!("idle_inhibit = {}", quote(&rule.idle_inhibit)));
    }
    format!("hl.window_rule({{ {} }})", fields.join(", "))
}

/// The same rule turned off, so Hyprland can check it without it taking effect.
pub fn probe_line(rule: &WindowRule) -> String {
    rule_line(rule).replacen("hl.window_rule({ ", "hl.window_rule({ enabled = false, ", 1)
}

fn hundredths(text: &str) -> Option<u8> {
    let v: f64 = text.parse().ok()?;
    let p = (v * 100.0).round();
    ((0.0..=255.0).contains(&p) && percent(p as u8) == text).then_some(p as u8)
}

/// Reads a line in exactly the shape `rule_line` renders; `rule_line` confirms it.
pub fn parse_rule(line: &str) -> Option<WindowRule> {
    let mut rule = WindowRule::default();
    let mut rest = line.strip_prefix("hl.window_rule({ match = { ")?;
    if let Some(field) = rest.strip_prefix("class = ") {
        let (class, next) = string(field)?;
        rule.class = unescape(class.strip_prefix("^(")?.strip_suffix(")$")?)?;
        rest = next.strip_prefix(", ").unwrap_or(next);
    }
    if let Some(field) = rest.strip_prefix("title = ") {
        let (title, next) = string(field)?;
        rule.title = unescape(title.strip_prefix(".*(")?.strip_suffix(").*")?)?;
        rest = next;
    }
    rest = rest.strip_prefix(" }")?;
    while let Some(field) = rest.strip_prefix(", ") {
        let (name, value) = field.split_once(" = ")?;
        rest = if let Some(after) = value.strip_prefix("true") {
            if !FLAGS.contains(&name) {
                return None;
            }
            *rule.flag(name) = true;
            after
        } else {
            match name {
                "size" => {
                    let w = value.strip_prefix("{ \"(monitor_w*")?;
                    let (w, h) = w.split_once(")\", \"(monitor_h*")?;
                    let (h, after) = h.split_once(")\" }")?;
                    rule.size = Some([hundredths(w)?, hundredths(h)?]);
                    after
                }
                "workspace" => {
                    let (text, after) = string(value)?;
                    match text.strip_suffix(" silent") {
                        Some(w) => (rule.workspace, rule.silent) = (w.to_owned(), true),
                        None => rule.workspace = text,
                    }
                    after
                }
                "opacity" => {
                    let end = value.find(|c: char| c != '.' && !c.is_ascii_digit())?;
                    rule.opacity = Some(hundredths(&value[..end])?);
                    &value[end..]
                }
                "idle_inhibit" => {
                    let (text, after) = string(value)?;
                    rule.idle_inhibit = text;
                    after
                }
                _ => return None,
            }
        };
    }
    (rest == " })" && rule_line(&rule) == line).then_some(rule)
}

/// One `hl.env` variable.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnvVar {
    pub name: String,
    pub value: String,
}

/// Variables other Settings pages own or that the session itself must keep.
pub const RESERVED: &[&str] = &[
    "XCURSOR_THEME",
    "XCURSOR_SIZE",
    "XCURSOR_PATH",
    "HYPRCURSOR_THEME",
    "HYPRCURSOR_SIZE",
    "QT_QUICK_CONTROLS_MATERIAL_THEME",
    "QT_QUICK_CONTROLS_UNIVERSAL_THEME",
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "PATH",
    "DISPLAY",
    "WAYLAND_DISPLAY",
    "XDG_RUNTIME_DIR",
    "XDG_SESSION_ID",
    "XDG_SESSION_TYPE",
    "XDG_CURRENT_DESKTOP",
    "XDG_SESSION_DESKTOP",
    "DBUS_SESSION_BUS_ADDRESS",
    "HYPRLAND_INSTANCE_SIGNATURE",
    "HYPRLAND_CMD",
];

impl EnvVar {
    pub fn validate(self) -> Result<Self, String> {
        let name = self.name.trim().to_owned();
        let valid = !name.is_empty()
            && name.len() <= 128
            && !name.starts_with(|c: char| c.is_ascii_digit())
            && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
        if !valid {
            return Err(invalid(
                "Use letters, digits and underscores, not starting with a digit",
            ));
        }
        if RESERVED.contains(&name.as_str()) {
            return Err(invalid(format!(
                "{name} is managed by the session or another Settings page"
            )));
        }
        if !plain(&self.value, 4096) {
            return Err(invalid("Use a one-line value"));
        }
        Ok(Self {
            name,
            value: self.value,
        })
    }
}

pub fn env_line(var: &EnvVar) -> String {
    format!("hl.env({}, {})", quote(&var.name), quote(&var.value))
}

pub fn parse_env(line: &str) -> Option<EnvVar> {
    let (name, rest) = string(line.strip_prefix("hl.env(")?)?;
    let (value, rest) = string(rest.strip_prefix(", ")?)?;
    let var = EnvVar { name, value };
    (rest == ")" && var.clone().validate().as_ref() == Ok(&var)).then_some(var)
}

/// A JSON request with fields of `T` and an optional `previous` key, as edits send.
pub fn request<T: for<'de> Deserialize<'de>>(
    value: &Value,
    fields: &str,
) -> Result<(T, Option<Value>), String> {
    let mut value = value.clone();
    let previous = value.as_object_mut().and_then(|m| m.remove("previous"));
    let item = serde_json::from_value(value).map_err(|_| invalid(format!("Expected {fields}")))?;
    Ok((item, previous.filter(|p| !p.is_null())))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn any(w: &str) -> Option<String> {
        Some(w.to_owned())
    }

    #[test]
    fn window_rules_round_trip_with_literal_text() {
        let rule = WindowRule {
            class: "org.pulseaudio.pavucontrol".into(),
            title: "Volume (main) \"x\"".into(),
            float: true,
            center: true,
            size: Some([45, 60]),
            workspace: "special:mix".into(),
            silent: true,
            pin: true,
            opacity: Some(90),
            no_blur: true,
            idle_inhibit: "fullscreen".into(),
            ..WindowRule::default()
        };
        let line = rule_line(&rule);
        assert_eq!(
            line,
            r#"hl.window_rule({ match = { class = "^(org\\.pulseaudio\\.pavucontrol)$", title = ".*(Volume \\(main\\) \"x\").*" }, float = true, center = true, size = { "(monitor_w*0.45)", "(monitor_h*0.6)" }, workspace = "special:mix silent", pin = true, opacity = 0.9, no_blur = true, idle_inhibit = "fullscreen" })"#
        );
        assert_eq!(parse_rule(&line), Some(rule));
        let only_title = WindowRule {
            title: "Save As".into(),
            maximize: true,
            opacity: Some(100),
            ..Default::default()
        };
        assert_eq!(
            parse_rule(&rule_line(&only_title)),
            Some(only_title.clone())
        );
        assert!(probe_line(&only_title).starts_with("hl.window_rule({ enabled = false, match"));
        for foreign in [
            r#"hl.window_rule({ match = { class = "^(a.*)$" }, float = true })"#,
            r#"hl.window_rule({ match = { class = "a" }, float = true })"#,
            r#"hl.window_rule({ match = { class = "^(a)$" }, no_anim = true })"#,
            r#"hl.window_rule({ match = { class = "^(a)$" }, pin = true, float = true })"#,
            r#"hl.window_rule({ match = { class = "^(a)$" }, float = true }) os.exit()"#,
            r#"hl.window_rule({ match = { class = "^(a)$" }, opacity = 0.900 })"#,
        ] {
            assert_eq!(parse_rule(foreign), None, "{foreign}");
        }
    }

    #[test]
    fn window_rules_and_variables_are_validated() {
        let ok = |r: WindowRule| r.validate(any);
        assert!(
            ok(WindowRule {
                class: " a ".into(),
                float: true,
                ..Default::default()
            })
            .is_ok_and(|r| r.class == "a")
        );
        for bad in [
            WindowRule {
                float: true,
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                center: true,
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                float: true,
                size: Some([5, 50]),
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                silent: true,
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                maximize: true,
                fullscreen: true,
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                opacity: Some(0),
                ..Default::default()
            },
            WindowRule {
                class: "a".into(),
                idle_inhibit: "never".into(),
                ..Default::default()
            },
            WindowRule {
                class: "a\nb".into(),
                pin: true,
                ..Default::default()
            },
        ] {
            assert!(
                ok(bad.clone()).unwrap_err().starts_with("InvalidArgument:"),
                "{bad:?}"
            );
        }
        assert!(
            WindowRule {
                class: "a".into(),
                workspace: "x".into(),
                ..Default::default()
            }
            .validate(|_| None)
            .is_err()
        );

        let var = |n: &str, v: &str| EnvVar {
            name: n.into(),
            value: v.into(),
        };
        assert_eq!(
            var(" GDK_BACKEND ", "wayland,x11").validate(),
            Ok(var("GDK_BACKEND", "wayland,x11"))
        );
        for bad in [
            var("", "1"),
            var("1X", "1"),
            var("A-B", "1"),
            var("PATH", "/x"),
            var("XCURSOR_SIZE", "24"),
            var("A", "x\ny"),
        ] {
            assert!(bad.clone().validate().is_err(), "{bad:?}");
        }
        let line = env_line(&var("QT_QPA_PLATFORM", "wayland;\"xcb\""));
        assert_eq!(line, r#"hl.env("QT_QPA_PLATFORM", "wayland;\"xcb\"")"#);
        assert_eq!(
            parse_env(&line),
            Some(var("QT_QPA_PLATFORM", "wayland;\"xcb\""))
        );
        assert_eq!(parse_env(r#"hl.env("PATH", "/x")"#), None);
        assert_eq!(parse_env(r#"hl.env("A", os.getenv("B"))"#), None);
    }
}
