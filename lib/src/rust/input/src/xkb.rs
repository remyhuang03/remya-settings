//! Keyboard layout, variant and option names from xkeyboard-config's evdev rules
//! list, the same data xkbcommon compiles keymaps from.
use serde_json::{Value, json};

pub const RULES: &str = "/usr/share/X11/xkb/rules/evdev.lst";
/// XKB keymaps hold at most four layout groups.
pub const MAX_LAYOUTS: usize = 4;

#[derive(Debug, Default)]
pub struct Rules {
    /// `(layout, label)`
    pub layouts: Vec<(String, String)>,
    /// `(layout, variant, label)`
    pub variants: Vec<(String, String, String)>,
    /// `(option, label)`, only full `group:name` options.
    pub options: Vec<(String, String)>,
}

impl Rules {
    pub fn load() -> Result<Self, String> {
        std::fs::read_to_string(RULES)
            .map(|text| Self::parse(&text))
            .map_err(|e| format!("{RULES}: {e}"))
    }

    pub fn parse(text: &str) -> Self {
        let mut rules = Self::default();
        let mut section = "";
        for line in text.lines() {
            if let Some(name) = line.strip_prefix("! ") {
                section = name.trim();
                continue;
            }
            let line = line.trim();
            let Some((name, label)) = line.split_once(char::is_whitespace) else {
                continue;
            };
            let label = label.trim().to_owned();
            match section {
                "layout" => rules.layouts.push((name.into(), label)),
                "variant" => {
                    if let Some((layout, label)) = label.split_once(": ") {
                        rules
                            .variants
                            .push((layout.into(), name.into(), label.into()));
                    }
                }
                "option" if name.contains(':') => rules.options.push((name.into(), label)),
                _ => {}
            }
        }
        rules
    }

    fn layout(&self, name: &str) -> bool {
        self.layouts.iter().any(|(n, _)| n == name)
    }

    fn variant(&self, layout: &str, name: &str) -> bool {
        name.is_empty()
            || self
                .variants
                .iter()
                .any(|(l, v, _)| l == layout && v == name)
    }

    /// The picker list: every layout with its variants.
    pub fn catalog(&self) -> Value {
        json!({"layouts": self.layouts.iter().map(|(name, label)| json!({
            "id": name,
            "label": label,
            "variants": self.variants.iter().filter(|(l, _, _)| l == name)
                .map(|(_, v, label)| json!({"id": v, "label": label})).collect::<Vec<_>>(),
        })).collect::<Vec<_>>()})
    }

    /// Validates `[{"layout": "us", "variant": ""}, ...]`, in order, without duplicates.
    pub fn layouts_value(&self, value: &Value) -> Result<Value, String> {
        let error = || {
            format!(
                "Use one to {MAX_LAYOUTS} different installed keyboard layouts, each with an optional variant of that layout"
            )
        };
        let items = value.as_array().ok_or_else(error)?;
        let mut out: Vec<(String, String)> = vec![];
        for item in items {
            let layout = item["layout"].as_str().ok_or_else(error)?;
            let variant = item
                .get("variant")
                .map_or(Some(""), Value::as_str)
                .ok_or_else(error)?;
            let known = item
                .as_object()
                .is_some_and(|o| o.keys().all(|k| k == "layout" || k == "variant"));
            let pair = (layout.to_owned(), variant.to_owned());
            if !known
                || !self.layout(layout)
                || !self.variant(layout, variant)
                || out.contains(&pair)
            {
                return Err(error());
            }
            out.push(pair);
        }
        if out.is_empty() || out.len() > MAX_LAYOUTS {
            return Err(error());
        }
        Ok(layouts_json(&out))
    }

    /// Validates a comma-separated option list; "" turns every option off.
    pub fn options_value(&self, value: &Value) -> Result<Value, String> {
        let text = value
            .as_str()
            .ok_or("Use comma-separated keyboard options")?;
        let mut seen = vec![];
        for option in text
            .split(',')
            .filter(|o| !text.is_empty() || !o.is_empty())
        {
            if !self.options.iter().any(|(o, _)| o == option) || seen.contains(&option) {
                return Err(format!("Unknown or repeated keyboard option: {option}"));
            }
            seen.push(option);
        }
        Ok(json!(text))
    }
}

pub fn layouts_json(pairs: &[(String, String)]) -> Value {
    json!(
        pairs
            .iter()
            .map(|(layout, variant)| json!({"layout": layout, "variant": variant}))
            .collect::<Vec<_>>()
    )
}

/// Pairs Hyprland's comma-separated `kb_layout` and `kb_variant`; missing variants are "".
pub fn split(layouts: &str, variants: &str) -> Vec<(String, String)> {
    let mut variants = variants.split(',');
    layouts
        .split(',')
        .map(|layout| {
            (
                layout.trim().to_owned(),
                variants.next().unwrap_or_default().trim().to_owned(),
            )
        })
        .collect()
}

/// The `kb_layout` and `kb_variant` strings of a validated layout list.
pub fn join(value: &Value) -> Option<(String, String)> {
    let items = value.as_array()?;
    let field =
        |key: &str| -> Option<Vec<&str>> { items.iter().map(|i| i[key].as_str()).collect() };
    let variants = field("variant")?.join(",");
    // Hyprland reports an unset variant list as empty rather than ",,".
    let variants = if variants.chars().all(|c| c == ',') {
        String::new()
    } else {
        variants
    };
    Some((field("layout")?.join(","), variants))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "! model\n  pc105           Generic 105-key PC\n\
        ! layout\n  us              English (US)\n  de              German\n\
        ! variant\n  intl            us: English (US, intl., with dead keys)\n  nodeadkeys      de: German (no dead keys)\n\
        ! option\n  grp                  Switching to another layout\n  grp:alt_shift_toggle Alt+Shift\n  caps:escape          Make Caps Lock an additional Esc\n";

    #[test]
    fn rules_list_layouts_variants_and_options() {
        let rules = Rules::parse(SAMPLE);
        assert_eq!(rules.layouts.len(), 2);
        assert_eq!(
            rules.variants[1],
            (
                "de".into(),
                "nodeadkeys".into(),
                "German (no dead keys)".into()
            )
        );
        assert_eq!(rules.options.len(), 2);
        let catalog = rules.catalog();
        assert_eq!(catalog["layouts"][1]["variants"][0]["id"], "nodeadkeys");
        // The installed list parses too.
        let installed = Rules::load().unwrap();
        assert!(installed.layout("us") && installed.variant("de", "nodeadkeys"));
        assert!(
            installed
                .options
                .iter()
                .any(|(o, _)| o == "grp:win_space_toggle")
        );
    }

    #[test]
    fn layouts_are_validated_against_their_own_variants() {
        let rules = Rules::parse(SAMPLE);
        let ok = json!([{"layout": "us"}, {"layout": "de", "variant": "nodeadkeys"}]);
        let value = rules.layouts_value(&ok).unwrap();
        assert_eq!(
            join(&value).unwrap(),
            ("us,de".into(), ",nodeadkeys".into())
        );
        for bad in [
            json!([]),
            json!([{"layout": "us", "variant": "nodeadkeys"}]),
            json!([{"layout": "fr"}]),
            json!([{"layout": "us"}, {"layout": "us"}]),
            json!([{"layout": "us,de"}]),
            json!([{"layout": "us", "extra": 1}]),
            json!([{"layout": "us"}, {"layout": "de"}, {"layout": "us", "variant": "intl"}, {"layout": "de", "variant": "nodeadkeys"}, {"layout": "us", "variant": ""}]),
            json!("us"),
        ] {
            assert!(rules.layouts_value(&bad).is_err(), "{bad}");
        }
        assert_eq!(join(&layouts_json(&split("us,de", ""))).unwrap().1, "");
        assert_eq!(
            split("us,de", "intl"),
            [("us".into(), "intl".into()), ("de".into(), String::new())]
        );
    }

    #[test]
    fn options_must_be_known_and_unique() {
        let rules = Rules::parse(SAMPLE);
        assert_eq!(rules.options_value(&json!("")).unwrap(), json!(""));
        assert!(
            rules
                .options_value(&json!("grp:alt_shift_toggle,caps:escape"))
                .is_ok()
        );
        for bad in [
            "grp",
            "caps:escape,caps:escape",
            "caps:escape,",
            "x:y",
            "caps:escape\"",
        ] {
            assert!(rules.options_value(&json!(bad)).is_err(), "{bad}");
        }
    }
}
