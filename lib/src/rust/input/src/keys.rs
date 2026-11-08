//! Key names, labels and layout-aware matching through libxkbcommon, the library
//! Hyprland itself uses to resolve bind keys.
use xkbcommon::xkb::{self, Keysym};

pub const MODIFIERS: [(&str, u32); 8] = [
    ("SUPER", 64),
    ("CTRL", 4),
    ("ALT", 8),
    ("SHIFT", 1),
    ("CAPS", 2),
    ("MOD2", 16),
    ("MOD3", 32),
    ("MOD5", 128),
];

/// The main keyboard's RMLVO names as Hyprland reports them.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Layout {
    pub rules: String,
    pub model: String,
    pub layout: String,
    pub variant: String,
    pub options: String,
}

pub struct Keys {
    keymap: xkb::Keymap,
}

fn lower(sym: Keysym) -> Keysym {
    match sym.key_char() {
        Some(c) => Keysym::from_char(c.to_lowercase().next().unwrap_or(c)),
        None => sym,
    }
}

/// A keysym name, ignoring case like Hyprland; `None` for unknown names.
pub fn parse_sym(name: &str) -> Option<Keysym> {
    let sym = xkb::keysym_from_name(name, xkb::KEYSYM_CASE_INSENSITIVE);
    (sym.raw() != 0).then_some(sym)
}

impl Keys {
    pub fn new(layout: &Layout) -> Result<Self, String> {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let options = (!layout.options.is_empty()).then(|| layout.options.clone());
        xkb::Keymap::new_from_names(
            &context,
            &layout.rules,
            &layout.model,
            &layout.layout,
            &layout.variant,
            options,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .map(|keymap| Self { keymap })
        .ok_or_else(|| format!("Cannot compile the {} keyboard layout", layout.layout))
    }

    /// The unshifted symbol of an XKB keycode in the first layout, which is what binds match.
    pub fn sym(&self, code: u32) -> Option<Keysym> {
        self.keymap
            .key_get_syms_by_level(xkb::Keycode::new(code), 0, 0)
            .first()
            .copied()
            .filter(|s| s.raw() != 0)
    }

    pub fn code_of(&self, sym: Keysym) -> Option<u32> {
        let wanted = lower(sym);
        (8..=255).find(|code| self.sym(*code).is_some_and(|s| lower(s) == wanted))
    }
}

/// What a bind key triggers on, so equal presses compare equal whatever their spelling.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum KeyId {
    Sym(u32),
    Code(u32),
    Other(String),
}

pub fn key_id(key: &str, keys: Option<&Keys>) -> KeyId {
    if let Some(code) = key.strip_prefix("code:").and_then(|c| c.parse().ok()) {
        return match keys.and_then(|k| k.sym(code)) {
            Some(sym) => KeyId::Sym(lower(sym).raw()),
            None => KeyId::Code(code),
        };
    }
    match parse_sym(key) {
        Some(sym) if !key.contains(':') => KeyId::Sym(lower(sym).raw()),
        _ => KeyId::Other(key.to_lowercase()),
    }
}

/// What a combination triggers on: its modifiers and the pressed key.
pub fn press(text: &str, keys: Option<&Keys>) -> Option<(u32, KeyId)> {
    parse_combo(text).map(|(mask, key)| (mask, key_id(&key, keys)))
}

/// The physical key a bind lives on in the current layout, for the keyboard map.
pub fn key_code(key: &str, keys: Option<&Keys>) -> Option<u32> {
    if let Some(code) = key.strip_prefix("code:") {
        return code.parse().ok();
    }
    keys?.code_of(parse_sym(key).filter(|_| !key.contains(':'))?)
}

fn sym_label(sym: Keysym) -> String {
    let name = xkb::keysym_get_name(sym);
    let named = match name.as_str() {
        "Return" => "Enter",
        "space" => "Space",
        "Prior" => "Page Up",
        "Next" => "Page Down",
        "BackSpace" => "Backspace",
        "Escape" => "Esc",
        "Print" => "Print Screen",
        "Super_L" | "Super_R" => "Super",
        "Control_L" | "Control_R" => "Ctrl",
        "Alt_L" | "Alt_R" => "Alt",
        "Shift_L" | "Shift_R" => "Shift",
        "Caps_Lock" => "Caps Lock",
        "ISO_Left_Tab" => "Tab",
        _ => "",
    };
    if !named.is_empty() {
        return named.into();
    }
    match sym.key_char() {
        Some(c) if !c.is_control() && !c.is_whitespace() => c.to_uppercase().collect(),
        _ => name.strip_prefix("XF86").unwrap_or(&name).to_owned(),
    }
}

pub fn label(key: &str, keys: Option<&Keys>) -> String {
    if let Some(button) = key.strip_prefix("mouse:") {
        return match button {
            "272" => "Left click".into(),
            "273" => "Right click".into(),
            "274" => "Middle click".into(),
            "275" => "Back button".into(),
            "276" => "Forward button".into(),
            other => format!("Mouse button {other}"),
        };
    }
    match key {
        "mouse_up" => return "Scroll up".into(),
        "mouse_down" => return "Scroll down".into(),
        "mouse_left" => return "Scroll left".into(),
        "mouse_right" => return "Scroll right".into(),
        _ => {}
    }
    if let Some(code) = key.strip_prefix("code:").and_then(|c| c.parse().ok()) {
        return match keys.and_then(|k| k.sym(code)) {
            Some(sym) => sym_label(sym),
            None => format!("Key {code}"),
        };
    }
    parse_sym(key).map_or_else(|| key.to_owned(), sym_label)
}

pub fn modifier_names(mask: u32) -> Vec<&'static str> {
    MODIFIERS
        .iter()
        .filter(|(_, bit)| mask & bit != 0)
        .map(|(name, _)| *name)
        .collect()
}

/// `SUPER + SHIFT + q`, the spelling `hl.bind` and `hl.unbind` accept.
pub fn combo(mask: u32, key: &str) -> String {
    let mut parts = modifier_names(mask);
    parts.push(key);
    parts.join(" + ")
}

/// Splits a combination into a modifier mask and a key, accepting only names Hyprland knows.
pub fn parse_combo(text: &str) -> Option<(u32, String)> {
    let mut mask = 0;
    let parts = text.split('+').map(str::trim).collect::<Vec<_>>();
    let (key, mods) = parts.split_last()?;
    for name in mods {
        let alias = match name.to_uppercase().as_str() {
            "CONTROL" => "CTRL".to_owned(),
            "WIN" | "LOGO" | "MOD4" => "SUPER".to_owned(),
            "MOD1" => "ALT".to_owned(),
            other => other.to_owned(),
        };
        let (_, bit) = MODIFIERS.iter().find(|(n, _)| *n == alias)?;
        mask |= bit;
    }
    let valid = !key.is_empty()
        && key.len() <= 64
        && key
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_:".contains(c));
    valid.then(|| (mask, (*key).to_owned()))
}

/// Keys that may be bound without a modifier without hijacking ordinary typing.
pub fn standalone(key: &str) -> bool {
    let name = parse_sym(key).map(xkb::keysym_get_name).unwrap_or_default();
    name.starts_with("XF86")
        || name == "Print"
        || name
            .strip_prefix('F')
            .is_some_and(|n| n.parse::<u8>().is_ok_and(|n| (1..=35).contains(&n)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn us() -> Keys {
        Keys::new(&Layout {
            layout: "us".into(),
            ..Layout::default()
        })
        .unwrap()
    }

    #[test]
    fn spellings_of_one_press_compare_equal() {
        let keys = us();
        assert_eq!(key_id("Q", Some(&keys)), key_id("q", Some(&keys)));
        assert_eq!(key_id("code:24", Some(&keys)), key_id("Q", Some(&keys)));
        assert_eq!(key_id("slash", Some(&keys)), key_id("Slash", Some(&keys)));
        assert_ne!(key_id("mouse:272", Some(&keys)), key_id("q", Some(&keys)));
        assert_eq!(key_code("q", Some(&keys)), Some(24));
        assert_eq!(key_code("code:10", Some(&keys)), Some(10));
    }

    #[test]
    fn labels_are_readable() {
        let keys = us();
        assert_eq!(label("slash", Some(&keys)), "/");
        assert_eq!(label("code:10", Some(&keys)), "1");
        assert_eq!(label("Return", None), "Enter");
        assert_eq!(label("XF86AudioMute", None), "AudioMute");
        assert_eq!(label("mouse:273", None), "Right click");
        assert_eq!(label("q", None), "Q");
    }

    #[test]
    fn combinations_round_trip_and_reject_unknown_modifiers() {
        assert_eq!(parse_combo("SUPER + SHIFT + q"), Some((65, "q".into())));
        assert_eq!(combo(65, "q"), "SUPER + SHIFT + q");
        assert_eq!(parse_combo("control+Return"), Some((4, "Return".into())));
        assert!(parse_combo("HYPER + q").is_none());
        assert!(parse_combo("SUPER + \"").is_none());
        assert!(standalone("F5") && standalone("XF86AudioMute") && !standalone("q"));
    }
}
