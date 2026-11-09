//! The Settings-owned `remya-settings/<group>.lua` files and their one-line `require`
//! blocks in `hyprland.lua`. Only the exact shapes rendered here are accepted, so a
//! file that has been edited into something else is never overwritten.
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
    /// A one-line font family name such as `"Sans"` or `"Noto Sans"`.
    FontFamily,
    /// `"default"`, `"none"`, or an absolute `.wav`/`.ogg`/`.oga` file path.
    BellSound,
    /// `#rrggbb`, written as an opaque Hyprland `rgba(rrggbbff)` string.
    Color,
    /// A CSS-style gap: one number for every side, or `[top, right, bottom, left]`.
    Gap(i64),
    /// `#rrggbbaa`, written as a Hyprland `rgba(rrggbbaa)` string.
    Rgba,
    /// `[x, y]` whole numbers, each within the range.
    Vec2(i64, i64),
    /// `[{"layout", "variant"}]` from xkeyboard-config, written together as
    /// `kb_layout` and `kb_variant` so no mismatched pair is ever compiled.
    Layouts,
    /// Comma-separated xkeyboard-config options.
    XkbOptions,
}

pub struct Opt {
    pub id: &'static str,
    /// The `hyprctl getoption` / `descriptions` name.
    pub name: &'static str,
    pub kind: Kind,
}

impl Opt {
    /// Lua tables use underscores where some legacy option names use hyphens, and
    /// nest `col.active_border` as `col = { active_border = ... }`.
    pub fn path(&self) -> Vec<String> {
        self.name
            .split([':', '.'])
            .map(|p| p.replace('-', "_"))
            .collect()
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
            Kind::FontFamily => match value
                .as_str()
                .map(str::trim)
                .filter(|v| !v.is_empty() && plain(v, 128))
            {
                Some(v) => Ok(json!(v)),
                None => invalid("Use a font family name such as Sans or Noto Sans".into()),
            },
            Kind::BellSound => match value.as_str().map(str::trim) {
                Some("" | "none") => Ok(json!("none")),
                Some("default") => Ok(json!("default")),
                Some(v) if bell_path(v) => Ok(json!(v)),
                _ => {
                    invalid("Use default, none, or an absolute .wav, .ogg or .oga file path".into())
                }
            },
            Kind::Color => match value.as_str().and_then(hex) {
                Some(v) => Ok(json!(v)),
                None => invalid("Use a color such as #1e1e2e".into()),
            },
            Kind::Gap(max) => {
                match gap(value).filter(|s| s.iter().all(|v| (0..=max).contains(v))) {
                    Some(sides) => Ok(gap_value(sides)),
                    None => invalid(format!(
                        "Use a whole number from 0 to {max}, or four of them for top, right, bottom and left"
                    )),
                }
            }
            Kind::Rgba => match value.as_str().and_then(hex_alpha) {
                Some(v) => Ok(json!(v)),
                None => invalid("Use a color such as #1e1e2eff".into()),
            },
            Kind::Vec2(min, max) => {
                match pair(value).filter(|p| p.iter().all(|v| (min..=max).contains(v))) {
                    Some(p) => Ok(json!(p)),
                    None => invalid(format!("Use two whole numbers from {min} to {max}")),
                }
            }
            Kind::Layouts => crate::xkb::Rules::load()?
                .layouts_value(value)
                .or_else(invalid),
            Kind::XkbOptions => crate::xkb::Rules::load()?
                .options_value(value)
                .or_else(invalid),
        }
    }

    /// Converts a `descriptions` reading to the value shape `validate` produces.
    pub fn observed(&self, current: &Value) -> Value {
        match self.kind {
            Kind::Bool => json!(current.as_bool().or(current.as_i64().map(|v| v != 0))),
            Kind::Int(..) => json!(current.as_i64().or(current.as_f64().map(|v| v as i64))),
            Kind::Float(..) => json!(current.as_f64().map(round)),
            Kind::Text(_) | Kind::FontFamily | Kind::BellSound | Kind::XkbOptions => {
                json!(text(current))
            }
            // `read_options` reports layouts as `[kb_layout, kb_variant]`.
            Kind::Layouts => {
                crate::xkb::layouts_json(&crate::xkb::split(&text(&current[0]), &text(&current[1])))
            }
            // Hyprland reports colors as AARRGGBB; Settings only writes opaque ones.
            Kind::Color => json!(
                current
                    .as_str()
                    .filter(|c| c.len() == 8)
                    .and_then(|c| hex(&format!("#{}", &c[2..])))
            ),
            // `descriptions` reports CSS gaps as "top right bottom left".
            Kind::Gap(_) => {
                let sides: Option<Vec<i64>> = current
                    .as_str()
                    .map(|t| t.split_whitespace().map(|v| v.parse().ok()).collect())
                    .unwrap_or_else(|| current.as_i64().map(|v| vec![v]));
                match sides.as_deref() {
                    Some([all]) => json!(all),
                    Some(&[top, right, bottom, left]) => gap_value([top, right, bottom, left]),
                    _ => Value::Null,
                }
            }
            // Gradients are reported as "AARRGGBB[ AARRGGBB...] <angle>deg".
            // shortcut: a multi-color gradient reads as its first color; add a gradient kind if one is ever edited here.
            Kind::Rgba => json!(
                current
                    .as_str()
                    .and_then(|c| c.split_whitespace().next())
                    .filter(|c| c.len() == 8)
                    .and_then(|c| hex_alpha(&format!("#{}{}", &c[2..], &c[..2])))
            ),
            Kind::Vec2(..) => json!(current.as_array().and_then(|a| {
                let items: Vec<i64> = a
                    .iter()
                    .map(|v| v.as_f64().map(|f| f.round() as i64))
                    .collect::<Option<_>>()?;
                <[i64; 2]>::try_from(items).ok()
            })),
        }
    }
}

/// A `descriptions` string; Hyprland reports an empty one as `[[EMPTY]]`.
fn text(current: &Value) -> String {
    match current.as_str() {
        Some("[[EMPTY]]") | None => String::new(),
        Some(text) => text.to_owned(),
    }
}

/// `[x, y]` whole numbers, or None for any other shape.
fn pair(value: &Value) -> Option<[i64; 2]> {
    let items: Vec<i64> = value
        .as_array()?
        .iter()
        .map(Value::as_i64)
        .collect::<Option<_>>()?;
    items.try_into().ok()
}

/// Lowercase `#rrggbbaa`; `#rrggbb` is taken as opaque.
fn hex_alpha(text: &str) -> Option<String> {
    let digits = text.strip_prefix('#')?;
    let digits = match digits.len() {
        6 => format!("{digits}ff"),
        8 => digits.to_owned(),
        _ => return None,
    };
    digits
        .chars()
        .all(|c| c.is_ascii_hexdigit())
        .then(|| format!("#{}", digits.to_ascii_lowercase()))
}

/// The four sides of a gap value, or None for any other shape.
fn gap(value: &Value) -> Option<[i64; 4]> {
    if let Some(all) = value.as_i64() {
        return Some([all; 4]);
    }
    let sides: Vec<i64> = value
        .as_array()?
        .iter()
        .map(Value::as_i64)
        .collect::<Option<_>>()?;
    sides.try_into().ok()
}

/// Equal sides collapse to one number, so a uniform gap compares equal however it is spelled.
fn gap_value(sides: [i64; 4]) -> Value {
    if sides.iter().all(|v| *v == sides[0]) {
        json!(sides[0])
    } else {
        json!(sides)
    }
}

fn gap_lua(sides: [i64; 4]) -> String {
    let [top, right, bottom, left] = sides;
    if sides.iter().all(|v| *v == top) {
        top.to_string()
    } else {
        format!("{{ top = {top}, right = {right}, bottom = {bottom}, left = {left} }}")
    }
}

/// Lowercase `#rrggbb`, or None.
fn hex(text: &str) -> Option<String> {
    let digits = text.strip_prefix('#')?;
    (digits.len() == 6 && digits.chars().all(|c| c.is_ascii_hexdigit()))
        .then(|| format!("#{}", digits.to_ascii_lowercase()))
}

fn bell_path(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    text.starts_with('/')
        && plain(text, 1024)
        && (lower.ends_with(".wav") || lower.ends_with(".ogg") || lower.ends_with(".oga"))
}

/// Settings writes three decimals; finer readback differences are noise.
fn round(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

macro_rules! opts {
    ($table:ident: $(($id:literal, $name:expr, $kind:expr)),* $(,)?) => {
        pub const $table: &[Opt] = &[$(Opt { id: $id, name: $name, kind: $kind }),*];
    };
}
opts![INPUT_OPTIONS:
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
    ("language.keyboard-layouts", "input:kb_layout", Kind::Layouts),
    ("language.keyboard-options", "input:kb_options", Kind::XkbOptions),
];

opts![DESKTOP_OPTIONS:
    ("background.blur-enabled", "decoration:blur:enabled", Kind::Bool),
    ("background.blur-variant", "decoration:blur:variant", Kind::Int(0, 10)),
    ("background.blur-size", "decoration:blur:size", Kind::Int(1, 100)),
    ("background.blur-passes", "decoration:blur:passes", Kind::Int(1, 10)),
    ("background.blur-noise", "decoration:blur:noise", Kind::Float(0.0, 1.0)),
    ("background.blur-contrast", "decoration:blur:contrast", Kind::Float(0.0, 2.0)),
    ("background.blur-brightness", "decoration:blur:brightness", Kind::Float(0.0, 2.0)),
    ("background.blur-vibrancy", "decoration:blur:vibrancy", Kind::Float(0.0, 1.0)),
    ("background.blur-xray", "decoration:blur:xray", Kind::Bool),
    ("background.blur-popups", "decoration:blur:popups", Kind::Bool),
    ("background.blur-special", "decoration:blur:special", Kind::Bool),
    ("background.fallback-color", "misc:background_color", Kind::Color),
    ("background.hide-logo", "misc:disable_hyprland_logo", Kind::Bool),
    ("fonts.compositor-family", "misc:font_family", Kind::FontFamily),
    ("sound.compositor-bell", "misc:bell_sound", Kind::BellSound),
    ("power.wake-key", "misc:key_press_enables_dpms", Kind::Bool),
    ("power.wake-pointer", "misc:mouse_move_enables_dpms", Kind::Bool),
    ("workspaces.close-special-on-empty", "misc:close_special_on_empty", Kind::Bool),
    (
        "workspaces.hide-special-on-change",
        "binds:hide_special_on_workspace_change",
        Kind::Bool
    ),
    (
        "workspaces.initial-workspace-tracking",
        "misc:initial_workspace_tracking",
        Kind::Int(0, 2)
    ),
    ("workspaces.center-on", "binds:workspace_center_on", Kind::Int(0, 1)),
    ("workspaces.special-fallthrough", "input:special_fallthrough", Kind::Bool),
    (
        "multitasking.layout",
        "general:layout",
        Kind::Text(&["dwindle", "master", "scrolling", "monocle"])
    ),
    ("multitasking.gaps-in", "general:gaps_in", Kind::Gap(500)),
    ("multitasking.gaps-out", "general:gaps_out", Kind::Gap(500)),
    ("multitasking.border-size", "general:border_size", Kind::Int(0, 20)),
    ("multitasking.snap", "general:snap:enabled", Kind::Bool),
    ("multitasking.snap-window-gap", "general:snap:window_gap", Kind::Int(0, 100)),
    ("multitasking.snap-monitor-gap", "general:snap:monitor_gap", Kind::Int(0, 100)),
    ("multitasking.snap-respect-gaps", "general:snap:respect_gaps", Kind::Bool),
    ("multitasking.snap-border-overlap", "general:snap:border_overlap", Kind::Bool),
    ("multitasking.resize-on-border", "general:resize_on_border", Kind::Bool),
    (
        "multitasking.border-grab-area",
        "general:extend_border_grab_area",
        Kind::Int(0, 100)
    ),
    ("multitasking.border-hover-icon", "general:hover_icon_on_border", Kind::Bool),
    ("multitasking.resize-corner", "general:resize_corner", Kind::Int(0, 4)),
    ("multitasking.float-gaps", "general:float_gaps", Kind::Gap(500)),
    ("multitasking.gaps-workspaces", "general:gaps_workspaces", Kind::Int(0, 100)),
    (
        "multitasking.modal-parent-blocking",
        "general:modal_parent_blocking",
        Kind::Bool
    ),
    ("multitasking.no-focus-fallback", "general:no_focus_fallback", Kind::Bool),
    ("multitasking.allow-tearing", "general:allow_tearing", Kind::Bool),
    ("cursor.hide-on-key-press", "cursor:hide_on_key_press", Kind::Bool),
    ("cursor.inactive-timeout", "cursor:inactive_timeout", Kind::Float(0.0, 20.0)),
    ("cursor.hide-on-touch", "cursor:hide_on_touch", Kind::Bool),
    ("cursor.hide-on-tablet", "cursor:hide_on_tablet", Kind::Bool),
    ("cursor.no-warps", "cursor:no_warps", Kind::Bool),
    (
        "cursor.warp-on-change-workspace",
        "cursor:warp_on_change_workspace",
        Kind::Int(0, 2)
    ),
    ("cursor.persistent-warps", "cursor:persistent_warps", Kind::Bool),
    ("cursor.hardware", "cursor:no_hardware_cursors", Kind::Int(0, 2)),
    ("cursor.enable-hyprcursor", "cursor:enable_hyprcursor", Kind::Bool),
    ("multitasking.dwindle-force-split", "dwindle:force_split", Kind::Int(0, 2)),
    ("multitasking.dwindle-preserve-split", "dwindle:preserve_split", Kind::Bool),
    ("multitasking.dwindle-smart-split", "dwindle:smart_split", Kind::Bool),
    ("multitasking.dwindle-smart-resizing", "dwindle:smart_resizing", Kind::Bool),
    (
        "multitasking.dwindle-permanent-direction",
        "dwindle:permanent_direction_override",
        Kind::Bool
    ),
    (
        "multitasking.dwindle-special-scale",
        "dwindle:special_scale_factor",
        Kind::Float(0.0, 1.0)
    ),
    (
        "multitasking.dwindle-split-width",
        "dwindle:split_width_multiplier",
        Kind::Float(0.1, 3.0)
    ),
    ("multitasking.dwindle-use-active", "dwindle:use_active_for_splits", Kind::Bool),
    (
        "multitasking.dwindle-split-ratio",
        "dwindle:default_split_ratio",
        Kind::Float(0.1, 1.9)
    ),
    ("multitasking.dwindle-split-bias", "dwindle:split_bias", Kind::Int(0, 1)),
    ("multitasking.dwindle-precise-move", "dwindle:precise_mouse_move", Kind::Bool),
    ("window-appearance.active-border", "general:col.active_border", Kind::Rgba),
    ("window-appearance.inactive-border", "general:col.inactive_border", Kind::Rgba),
    ("window-appearance.rounding", "decoration:rounding", Kind::Int(0, 100)),
    ("window-appearance.rounding-power", "decoration:rounding_power", Kind::Float(1.0, 10.0)),
    ("window-appearance.active-opacity", "decoration:active_opacity", Kind::Float(0.0, 1.0)),
    ("window-appearance.inactive-opacity", "decoration:inactive_opacity", Kind::Float(0.0, 1.0)),
    (
        "window-appearance.fullscreen-opacity",
        "decoration:fullscreen_opacity",
        Kind::Float(0.0, 1.0)
    ),
    ("window-appearance.dim-inactive", "decoration:dim_inactive", Kind::Bool),
    ("window-appearance.dim-strength", "decoration:dim_strength", Kind::Float(0.0, 1.0)),
    ("window-appearance.dim-modal", "decoration:dim_modal", Kind::Bool),
    ("window-appearance.dim-special", "decoration:dim_special", Kind::Float(0.0, 1.0)),
    ("window-appearance.shadow", "decoration:shadow:enabled", Kind::Bool),
    ("window-appearance.shadow-color", "decoration:shadow:color", Kind::Rgba),
    ("window-appearance.shadow-range", "decoration:shadow:range", Kind::Int(0, 100)),
    ("window-appearance.shadow-render-power", "decoration:shadow:render_power", Kind::Int(1, 4)),
    ("window-appearance.shadow-offset", "decoration:shadow:offset", Kind::Vec2(-100, 100)),
    ("window-appearance.shadow-scale", "decoration:shadow:scale", Kind::Float(0.05, 2.0)),
    ("window-appearance.shadow-sharp", "decoration:shadow:sharp", Kind::Bool),
    ("window-appearance.glow", "decoration:glow:enabled", Kind::Bool),
    ("window-appearance.glow-color", "decoration:glow:color", Kind::Rgba),
    ("window-appearance.glow-range", "decoration:glow:range", Kind::Int(0, 100)),
    ("window-appearance.glow-render-power", "decoration:glow:render_power", Kind::Int(1, 4)),
    (
        "window-appearance.border-part-of-window",
        "decoration:border_part_of_window",
        Kind::Bool
    ),
    ("animations.enabled", "animations:enabled", Kind::Bool),
    ("animations.workspace-wraparound", "animations:workspace_wraparound", Kind::Bool),
    ("animations.resize", "misc:animate_manual_resizes", Kind::Bool),
    ("animations.drag", "misc:animate_mouse_windowdragging", Kind::Bool),
    ("animations.motion-blur", "decoration:motion_blur:enabled", Kind::Bool),
    ("animations.motion-blur-samples", "decoration:motion_blur:samples", Kind::Int(1, 64)),
    ("animations.wobble", "decoration:wobble:enabled", Kind::Bool),
    ("animations.wobble-intensity", "decoration:wobble:intensity", Kind::Float(0.0, 2.0)),
    ("animations.wobble-stiffness", "decoration:wobble:stiffness", Kind::Float(0.0001, 1000.0)),
    ("animations.wobble-damping", "decoration:wobble:damping", Kind::Float(0.0, 1000.0)),
    ("animations.wobble-mass", "decoration:wobble:mass", Kind::Float(0.0001, 1000.0)),
    ("animations.wobble-mesh", "decoration:wobble:mesh", Kind::Int(2, 32)),
    ("animations.wobble-value-epsilon", "decoration:wobble:value_epsilon", Kind::Float(0.0, 100.0)),
    (
        "animations.wobble-velocity-epsilon",
        "decoration:wobble:velocity_epsilon",
        Kind::Float(0.0, 1000.0)
    ),
];

/// One Settings-owned Lua file and the options it may contain.
pub struct Group {
    /// File stem, `require` module and service feature name.
    pub name: &'static str,
    pub options: &'static [Opt],
    /// Whether the file also holds `hl.bind`/`hl.unbind` shortcuts.
    pub shortcuts: bool,
    /// Whether the file also holds `hl.workspace_rule` workspace rules.
    pub rules: bool,
    pub header: &'static str,
}

pub const INPUT: Group = Group {
    name: "input",
    options: INPUT_OPTIONS,
    shortcuts: true,
    rules: false,
    header: "-- Managed by Remy'a Settings. Change Mouse, Touchpad, Keyboard shortcuts and keyboard layouts in Settings.",
};

pub const DESKTOP: Group = Group {
    name: "desktop",
    options: DESKTOP_OPTIONS,
    shortcuts: false,
    rules: true,
    header: "-- Managed by Remy'a Settings. Change Background, Cursor, Window appearance, Animations, Multitasking, Workspaces and Power & battery in Settings.",
};

impl Group {
    pub fn option(&self, id: &str) -> Option<&'static Opt> {
        self.options.iter().find(|o| o.id == id)
    }

    fn begin(&self) -> String {
        format!("-- BEGIN Remy'a Settings {}", self.name)
    }

    fn end(&self) -> String {
        format!("-- END Remy'a Settings {}", self.name)
    }

    pub fn block(&self) -> String {
        format!(
            "{}\nrequire(\"remya-settings.{}\")\n{}\n",
            self.begin(),
            self.name,
            self.end()
        )
    }
}

pub fn option(id: &str) -> Option<&'static Opt> {
    INPUT.option(id).or_else(|| DESKTOP.option(id))
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

/// One `hl.workspace_rule`: the subset of `HL.WorkspaceRuleSpec` Settings edits.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkspaceRule {
    /// A number, `name:<text>` or `special:<text>`.
    pub workspace: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub monitor: String,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub default: bool,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub persistent: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub default_name: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct File {
    pub options: BTreeMap<String, Value>,
    pub disabled: Vec<String>,
    pub shortcuts: Vec<Shortcut>,
    pub rules: Vec<WorkspaceRule>,
}

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
    if opt.kind == Kind::Layouts {
        let text = crate::xkb::join(value)
            .map(|(layouts, variants)| {
                format!(
                    "{{ kb_layout = {}, kb_variant = {} }}",
                    quote(&layouts),
                    quote(&variants)
                )
            })
            .unwrap_or_else(|| "null".into());
        return format!("hl.config({{ input = {text} }})");
    }
    let path = opt.path();
    let mut text = match (opt.kind, value) {
        // `parse` finds the value by rendering `null` in its place, so keep that spelling.
        (Kind::Color, Value::String(c)) => quote(&format!("rgba({}ff)", c.trim_start_matches('#'))),
        (Kind::Color, _) => quote("rgba(nullff)"),
        (Kind::Gap(_), value) => gap(value).map(gap_lua).unwrap_or_else(|| "null".into()),
        (Kind::Rgba, Value::String(c)) => quote(&format!("rgba({})", c.trim_start_matches('#'))),
        (Kind::Rgba, _) => quote("rgba(null)"),
        (Kind::Vec2(..), value) => pair(value)
            .map(|[x, y]| format!("{{ {x}, {y} }}"))
            .unwrap_or_else(|| "null".into()),
        _ => literal(value),
    };
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

pub fn render(group: &Group, file: &File) -> String {
    let mut text = format!("{}\n", group.header);
    for opt in group.options {
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
    for rule in &file.rules {
        text += &rule_line(rule);
        text.push('\n');
    }
    text
}

pub fn rule_line(rule: &WorkspaceRule) -> String {
    let mut fields = vec![format!("workspace = {}", quote(&rule.workspace))];
    if !rule.monitor.is_empty() {
        fields.push(format!("monitor = {}", quote(&rule.monitor)));
    }
    if rule.default {
        fields.push("default = true".into());
    }
    if rule.persistent {
        fields.push("persistent = true".into());
    }
    if !rule.default_name.is_empty() {
        fields.push(format!("default_name = {}", quote(&rule.default_name)));
    }
    format!("hl.workspace_rule({{ {} }})", fields.join(", "))
}

/// Reads a line in exactly the shape `rule_line` renders.
fn workspace_rule(line: &str) -> Option<WorkspaceRule> {
    let rest = line.strip_prefix("hl.workspace_rule({ workspace = ")?;
    let (workspace, mut rest) = string(rest)?;
    let mut rule = WorkspaceRule {
        workspace,
        ..WorkspaceRule::default()
    };
    if let Some(field) = rest.strip_prefix(", monitor = ") {
        (rule.monitor, rest) = string(field)?;
    }
    if let Some(field) = rest.strip_prefix(", default = true") {
        (rule.default, rest) = (true, field);
    }
    if let Some(field) = rest.strip_prefix(", persistent = true") {
        (rule.persistent, rest) = (true, field);
    }
    if let Some(field) = rest.strip_prefix(", default_name = ") {
        (rule.default_name, rest) = string(field)?;
    }
    (rest == " })").then_some(rule)
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
        Kind::Text(_) | Kind::XkbOptions => string(text)
            .filter(|(_, rest)| rest.is_empty())
            .map(|(s, _)| s.into()),
        Kind::FontFamily => string(text)
            .filter(|(s, rest)| {
                rest.is_empty() && !s.trim().is_empty() && plain(s, 128) && s == s.trim()
            })
            .map(|(s, _)| s.into()),
        Kind::BellSound => string(text)
            .filter(|(s, rest)| {
                rest.is_empty()
                    && (matches!(s.as_str(), "" | "none" | "default")
                        || (bell_path(s) && s == s.trim()))
            })
            .map(|(s, _)| s.into()),
        Kind::Layouts => {
            let (layouts, rest) = string(text.strip_prefix("{ kb_layout = ")?)?;
            let (variants, rest) = string(rest.strip_prefix(", kb_variant = ")?)?;
            (rest == " }")
                .then(|| crate::xkb::layouts_json(&crate::xkb::split(&layouts, &variants)))
        }
        Kind::Color => hex(&format!("#{text}")).map(Value::from),
        Kind::Rgba => (text.len() == 8)
            .then(|| hex_alpha(&format!("#{text}")))
            .flatten()
            .map(Value::from),
        Kind::Vec2(..) => {
            let (x, y) = text
                .strip_prefix("{ ")?
                .strip_suffix(" }")?
                .split_once(", ")?;
            Some(json!([x.parse::<i64>().ok()?, y.parse::<i64>().ok()?]))
        }
        Kind::Gap(_) => {
            if let Ok(all) = text.parse::<i64>() {
                return Some(json!(all));
            }
            let mut sides = vec![];
            let mut rest = text.strip_prefix("{ ")?.strip_suffix(" }")?;
            for (index, side) in ["top", "right", "bottom", "left"].iter().enumerate() {
                let field = rest.strip_prefix(&format!("{side} = "))?;
                let end = field.find(", ").unwrap_or(field.len());
                sides.push(field[..end].parse::<i64>().ok()?);
                rest = if index < 3 {
                    field.get(end + 2..)?
                } else {
                    &field[end..]
                };
            }
            rest.is_empty().then(|| json!(sides))
        }
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

pub fn parse(group: &Group, text: &str) -> Result<File, String> {
    let mut file = File::default();
    let name = group.name;
    for (number, line) in text.lines().enumerate() {
        let line = line.trim();
        let refuse = || format!("Settings cannot safely edit {name}.lua line {}", number + 1);
        if line.is_empty() || line.starts_with("--") {
            continue;
        }
        if !group.shortcuts && (line.starts_with("hl.unbind(") || line.starts_with("hl.bind(")) {
            return Err(refuse());
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
        if line.starts_with("hl.workspace_rule(") {
            if !group.rules {
                return Err(refuse());
            }
            file.rules.push(workspace_rule(line).ok_or_else(refuse)?);
            continue;
        }
        let parsed = group.options.iter().find_map(|opt| {
            let empty = option_line(opt, &Value::Null);
            let (prefix, suffix) = empty.split_once("null")?;
            let inner = line.strip_prefix(prefix)?.strip_suffix(suffix)?;
            Some((opt, value(inner, opt.kind)?))
        });
        let (opt, value) = parsed.ok_or_else(refuse)?;
        file.options.insert(opt.id.into(), value);
    }
    if render(group, &file) != format!("{}\n{}", group.header, strip_header(text)) {
        return Err(format!(
            "Settings cannot safely edit {name}.lua: it was changed outside Settings"
        ));
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
pub fn with_block(group: &Group, main: &str) -> Result<Option<String>, String> {
    let (begin, end, block) = (group.begin(), group.end(), group.block());
    match (main.find(&begin), main.find(&end)) {
        (None, None) => {
            let separator = if main.is_empty() || main.ends_with('\n') {
                ""
            } else {
                "\n"
            };
            Ok(Some(format!("{main}{separator}{block}")))
        }
        (Some(start), Some(stop)) if main[start..stop + end.len()] == block[..block.len() - 1] => {
            Ok(None)
        }
        _ => Err(format!(
            "The Remy'a Settings {} block in hyprland.lua was edited",
            group.name
        )),
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
            rules: vec![],
        }
    }

    #[test]
    fn workspace_rules_read_back_and_stay_in_the_desktop_file() {
        let file = File {
            options: BTreeMap::from([("workspaces.center-on".into(), json!(0))]),
            rules: vec![
                WorkspaceRule {
                    workspace: "1".into(),
                    monitor: "DP-1".into(),
                    default: true,
                    persistent: true,
                    default_name: "Web \"main\"".into(),
                },
                WorkspaceRule {
                    workspace: "special:notes".into(),
                    ..WorkspaceRule::default()
                },
            ],
            ..File::default()
        };
        let text = render(&DESKTOP, &file);
        assert!(text.contains(
            "hl.workspace_rule({ workspace = \"1\", monitor = \"DP-1\", default = true, persistent = true, default_name = \"Web \\\"main\\\"\" })"
        ));
        assert!(text.contains("hl.workspace_rule({ workspace = \"special:notes\" })"));
        assert_eq!(parse(&DESKTOP, &text).unwrap(), file);
        assert!(parse(&INPUT, &text).is_err());
        for foreign in [
            "hl.workspace_rule({ workspace = \"1\", gaps_in = 5 })\n",
            "hl.workspace_rule({ persistent = true, workspace = \"1\" })\n",
            "hl.workspace_rule({ workspace = \"1\", persistent = false })\n",
            "hl.workspace_rule({ workspace = \"1\" }) os.exit()\n",
            "hl.workspace_rule({ workspace = \"1\" .. x })\n",
        ] {
            assert!(parse(&DESKTOP, foreign).is_err(), "{foreign}");
        }
    }

    #[test]
    fn rendered_files_read_back_exactly() {
        let text = render(&INPUT, &sample());
        assert!(text.contains("hl.config({ input = { touchpad = { tap_to_click = false } } })"));
        assert!(text.find("hl.unbind").unwrap() < text.find("hl.bind").unwrap());
        assert_eq!(parse(&INPUT, &text).unwrap(), sample());
        assert_eq!(parse(&INPUT, "").unwrap(), File::default());
    }

    #[test]
    fn foreign_lua_is_refused() {
        for text in [
            "os.execute(\"rm -rf ~\")\n",
            "hl.config({ input = { sensitivity = 0.2 } }) os.exit()\n",
            "hl.bind(\"SUPER + K\", function() end)\n",
            "hl.bind(\"SUPER + K\", hl.dsp.exec_cmd(\"a\" .. \"b\"))\n",
            // Layouts are written only together with their variants.
            "hl.config({ input = { kb_layout = \"de\" } })\n",
            "hl.config({ input = { kb_file = \"/tmp/x\" } })\n",
        ] {
            assert!(parse(&INPUT, text).is_err(), "{text}");
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
        let added = with_block(&INPUT, main).unwrap().unwrap();
        assert!(added.ends_with(&INPUT.block()) && added.starts_with("hl.config({})\n"));
        assert_eq!(with_block(&INPUT, &added).unwrap(), None);
        assert!(with_block(&INPUT, &added.replace("require", "-- require")).is_err());
        // Each group keeps its own block beside the others.
        let both = with_block(&DESKTOP, &added).unwrap().unwrap();
        assert!(both.contains("require(\"remya-settings.desktop\")"));
        assert_eq!(with_block(&INPUT, &both).unwrap(), None);
    }

    #[test]
    fn desktop_colors_and_shortcut_refusal() {
        let color = DESKTOP.option("background.fallback-color").unwrap();
        assert_eq!(color.validate(&json!("#1E1E2E")).unwrap(), json!("#1e1e2e"));
        assert!(color.validate(&json!("red")).is_err());
        assert_eq!(color.observed(&json!("ff141318")), json!("#141318"));
        let file = File {
            options: BTreeMap::from([
                ("background.fallback-color".into(), json!("#141318")),
                ("background.blur-passes".into(), json!(3)),
            ]),
            ..File::default()
        };
        let text = render(&DESKTOP, &file);
        assert!(text.contains("hl.config({ misc = { background_color = \"rgba(141318ff)\" } })"));
        assert_eq!(parse(&DESKTOP, &text).unwrap(), file);
        assert!(parse(&DESKTOP, "hl.bind(\"SUPER + Q\", hl.dsp.window.close())\n").is_err());
        assert!(parse(&INPUT, &text).is_err());
    }

    #[test]
    fn compositor_font_and_bell_validate_and_read_back() {
        let font = DESKTOP.option("fonts.compositor-family").unwrap();
        assert_eq!(
            font.validate(&json!(" Noto Sans ")).unwrap(),
            json!("Noto Sans")
        );
        assert!(font.validate(&json!("   ")).is_err());
        assert!(font.validate(&json!("Noto\nSans")).is_err());
        let bell = DESKTOP.option("sound.compositor-bell").unwrap();
        assert_eq!(bell.validate(&json!("default")).unwrap(), json!("default"));
        assert_eq!(bell.validate(&json!("")).unwrap(), json!("none"));
        assert_eq!(
            bell.validate(&json!(
                "/usr/share/sounds/ocean/stereo/bell-window-system.oga"
            ))
            .unwrap(),
            json!("/usr/share/sounds/ocean/stereo/bell-window-system.oga")
        );
        for bad in ["beep", "relative.wav", "/tmp/bell.mp3"] {
            assert!(bell.validate(&json!(bad)).is_err(), "{bad}");
        }
        let file = File {
            options: BTreeMap::from([
                ("fonts.compositor-family".into(), json!("Noto Sans")),
                ("sound.compositor-bell".into(), json!("/tmp/bell.ogg")),
            ]),
            ..File::default()
        };
        let text = render(&DESKTOP, &file);
        assert!(text.contains("hl.config({ misc = { font_family = \"Noto Sans\" } })"));
        assert!(text.contains("hl.config({ misc = { bell_sound = \"/tmp/bell.ogg\" } })"));
        assert_eq!(parse(&DESKTOP, &text).unwrap(), file);
        assert!(parse(&DESKTOP, "hl.config({ misc = { font_family = \"\" } })\n").is_err());
        assert!(
            parse(
                &DESKTOP,
                "hl.config({ misc = { bell_sound = \"relative.wav\" } })\n"
            )
            .is_err()
        );
    }

    #[test]
    fn translucent_colors_and_offsets_read_back() {
        let border = DESKTOP.option("window-appearance.active-border").unwrap();
        assert_eq!(border.path(), ["general", "col", "active_border"]);
        assert_eq!(
            border.validate(&json!("#0DB7D4")).unwrap(),
            json!("#0db7d4ff")
        );
        assert!(border.validate(&json!("#0db7d4f")).is_err());
        // Hyprland reports AARRGGBB gradients; the first color is used.
        assert_eq!(border.observed(&json!("77938e9d 0deg")), json!("#938e9d77"));
        assert_eq!(
            border.observed(&json!("ff00ff00 ff0000ff 45deg")),
            json!("#00ff00ff")
        );
        let offset = DESKTOP.option("window-appearance.shadow-offset").unwrap();
        assert_eq!(offset.observed(&json!([0.0, 4.0])), json!([0, 4]));
        assert!(offset.validate(&json!([0, 400])).is_err());
        let file = File {
            options: BTreeMap::from([
                ("window-appearance.active-border".into(), json!("#938e9d77")),
                ("window-appearance.shadow-offset".into(), json!([-2, 4])),
            ]),
            ..File::default()
        };
        let text = render(&DESKTOP, &file);
        assert!(
            text.contains(
                "hl.config({ general = { col = { active_border = \"rgba(938e9d77)\" } } })"
            )
        );
        assert!(text.contains("hl.config({ decoration = { shadow = { offset = { -2, 4 } } } })"));
        assert_eq!(parse(&DESKTOP, &text).unwrap(), file);
    }

    #[test]
    fn gaps_accept_one_or_four_sides_and_read_back() {
        let gaps = DESKTOP.option("multitasking.gaps-out").unwrap();
        assert_eq!(gaps.validate(&json!([6, 6, 6, 6])).unwrap(), json!(6));
        assert_eq!(
            gaps.validate(&json!([4, 8, 4, 8])).unwrap(),
            json!([4, 8, 4, 8])
        );
        assert!(gaps.validate(&json!([1, 2, 3])).is_err());
        assert!(gaps.validate(&json!(-1)).is_err());
        assert_eq!(gaps.observed(&json!("4 4 4 4")), json!(4));
        assert_eq!(gaps.observed(&json!("4 8 4 8")), json!([4, 8, 4, 8]));
        let file = File {
            options: BTreeMap::from([
                ("multitasking.gaps-in".into(), json!(5)),
                ("multitasking.gaps-out".into(), json!([10, 20, 30, 40])),
                ("multitasking.layout".into(), json!("master")),
            ]),
            ..File::default()
        };
        let text = render(&DESKTOP, &file);
        assert!(text.contains("hl.config({ general = { gaps_in = 5 } })"));
        assert!(text.contains(
            "hl.config({ general = { gaps_out = { top = 10, right = 20, bottom = 30, left = 40 } } })"
        ));
        assert_eq!(parse(&DESKTOP, &text).unwrap(), file);
        assert!(
            parse(
                &DESKTOP,
                "hl.config({ general = { gaps_out = { top = 1, left = 2 } } })\n"
            )
            .is_err()
        );
    }
}
