//! Field definitions, validation, Lua rendering, and semantic comparison.
use crate::{
    hyprland::Monitor,
    rules::{Rule, quote},
};
use std::collections::BTreeMap;

/// Stable preferences of one output, keyed by Hyprland rule field name.
pub type Prefs = BTreeMap<String, String>;

pub const FIELDS: &[&str] = &[
    "disabled",
    "mode",
    "scale",
    "transform",
    "position",
    "mirror",
    "bitdepth",
    "cm",
    "sdr_eotf",
    "vrr",
    "icc",
    "reserved_area",
    "supports_wide_color",
    "supports_hdr",
    "sdrbrightness",
    "sdrsaturation",
    "sdr_min_luminance",
    "sdr_max_luminance",
    "min_luminance",
    "max_luminance",
    "max_avg_luminance",
];

/// Fields whose wrong value can leave a display unusable.
pub const RISKY: &[&str] = &[
    "disabled",
    "mode",
    "scale",
    "transform",
    "mirror",
    "bitdepth",
    "cm",
    "supports_wide_color",
    "supports_hdr",
    "icc",
];

pub const COLOR_PRESETS: &[&str] = &[
    "auto", "srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid",
];
const SYMBOLIC_MODES: &[&str] = &["preferred", "highres", "highrr", "maxwidth"];

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Mode {
    pub width: i64,
    pub height: i64,
    pub refresh: f64,
}

pub fn parse_mode(text: &str) -> Option<Mode> {
    let (size, refresh) = text.trim_end_matches("Hz").split_once('@')?;
    let (width, height) = size.split_once('x')?;
    let mode = Mode {
        width: width.parse().ok()?,
        height: height.parse().ok()?,
        refresh: refresh.parse().ok()?,
    };
    (mode.width > 0 && mode.height > 0 && mode.refresh > 0.0).then_some(mode)
}

/// Available modes, deduplicated, ordered by size and then refresh rate.
pub fn modes(monitor: &Monitor) -> Vec<Mode> {
    let mut modes = Vec::<Mode>::new();
    for mode in monitor.available_modes.iter().filter_map(|m| parse_mode(m)) {
        if !modes.contains(&mode) {
            modes.push(mode);
        }
    }
    modes.sort_by(|a, b| {
        (b.width * b.height)
            .cmp(&(a.width * a.height))
            .then(b.width.cmp(&a.width))
            .then(b.refresh.total_cmp(&a.refresh))
    });
    modes
}

fn gcd(a: i64, b: i64) -> i64 {
    if b == 0 { a } else { gcd(b, a % b) }
}

/// Scales from 1x to 4x that Hyprland keeps unchanged: an integer logical size
/// with the scale on its 1/120 grid. Other values are silently snapped elsewhere.
pub fn scale_options(width: i64, height: i64) -> Vec<String> {
    if width <= 0 || height <= 0 {
        return vec![];
    }
    let divisor = gcd(width, height);
    (divisor / 4..=divisor)
        .rev()
        .filter(|k| *k > 0 && (divisor * 120) % k == 0)
        .map(|k| format_scale(divisor as f64 / k as f64))
        .filter(|s| s.parse::<f64>().is_ok_and(|v| (1.0..=4.0).contains(&v)))
        .collect()
}

pub fn format_float(value: f64) -> String {
    let text = format!("{value:.2}");
    text.trim_end_matches('0').trim_end_matches('.').to_owned()
}

fn format_scale(value: f64) -> String {
    let text = format!("{value:.4}");
    text.trim_end_matches('0').trim_end_matches('.').to_owned()
}

pub fn format_mode(mode: Mode) -> String {
    format!("{}x{}@{:.2}", mode.width, mode.height, mode.refresh)
}

pub fn bit_depth(format: &str) -> &'static str {
    if format.contains("2101010") || format.contains("1010102") {
        "10"
    } else {
        "8"
    }
}

fn rule_value(rule: Option<&Rule>, field: &str) -> Option<String> {
    rule.and_then(|r| r.get(field))
}

/// Combines live readback with the rule file. Hyprland reports resolved values only,
/// so symbolic choices (`auto`, `preferred`) and write-only fields come from the rule.
pub fn observe(monitor: &Monitor, rule: Option<&Rule>, all: &[Monitor]) -> Prefs {
    let from_rule =
        |field: &str, default: &str| rule_value(rule, field).unwrap_or_else(|| default.to_owned());
    let symbolic = |field: &str, test: &dyn Fn(&str) -> bool, live: String| {
        rule_value(rule, field).filter(|v| test(v)).unwrap_or(live)
    };
    let mut prefs = Prefs::new();
    let mut put = |k: &str, v: String| {
        prefs.insert(k.to_owned(), v);
    };
    let mode = format_mode(Mode {
        width: monitor.width,
        height: monitor.height,
        refresh: monitor.refresh_rate,
    });
    if monitor.disabled {
        put("mode", from_rule("mode", "preferred"));
        put("position", from_rule("position", "auto"));
        put("scale", from_rule("scale", "auto"));
    } else {
        put(
            "mode",
            symbolic("mode", &|v| SYMBOLIC_MODES.contains(&v), mode),
        );
        // Without an explicit position Hyprland places the output itself, so a
        // neighbour's change moving it is not a configuration difference.
        let explicit = rule_value(rule, "position").filter(|v| !v.starts_with("auto"));
        put(
            "position",
            match explicit {
                Some(_) => format!("{}x{}", monitor.x, monitor.y),
                None => from_rule("position", "auto"),
            },
        );
        put(
            "scale",
            symbolic("scale", &|v| v == "auto", format_scale(monitor.scale)),
        );
    }
    put("disabled", monitor.disabled.to_string());
    put("transform", monitor.transform.to_string());
    let mirror = all
        .iter()
        .find(|m| m.id.to_string() == monitor.mirror_of)
        .map(|m| m.name.clone())
        .unwrap_or_default();
    put("mirror", mirror);
    put("bitdepth", bit_depth(&monitor.current_format).to_owned());
    put(
        "cm",
        symbolic(
            "cm",
            &|v| v == "auto",
            if monitor.color_management_preset.is_empty() {
                "srgb".to_owned()
            } else {
                monitor.color_management_preset.clone()
            },
        ),
    );
    put("sdrbrightness", format_float(monitor.sdr_brightness));
    put("sdrsaturation", format_float(monitor.sdr_saturation));
    put("sdr_min_luminance", format_float(monitor.sdr_min_luminance));
    put("sdr_max_luminance", format_float(monitor.sdr_max_luminance));
    for (field, default) in [
        ("sdr_eotf", "default"),
        ("vrr", ""),
        ("icc", ""),
        ("reserved_area", "0 0 0 0"),
        ("supports_wide_color", "0"),
        ("supports_hdr", "0"),
        ("min_luminance", "-1"),
        ("max_luminance", "-1"),
        ("max_avg_luminance", "-1"),
    ] {
        put(field, from_rule(field, default));
    }
    prefs
}

/// Whether a saved and an observed value mean the same configuration.
pub fn same(field: &str, a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    match field {
        "mode" => match (parse_mode(a), parse_mode(b)) {
            (Some(x), Some(y)) => {
                x.width == y.width && x.height == y.height && (x.refresh - y.refresh).abs() < 0.1
            }
            _ => false,
        },
        "scale" | "sdrbrightness" | "sdrsaturation" | "sdr_min_luminance" | "sdr_max_luminance"
        | "min_luminance" | "max_luminance" | "max_avg_luminance" => {
            match (a.parse::<f64>(), b.parse::<f64>()) {
                (Ok(x), Ok(y)) => (x - y).abs() < 0.011,
                _ => false,
            }
        }
        _ => false,
    }
}

/// Fields that differ. A disabled or mirrored output has no meaningful geometry.
pub fn differences(saved: &Prefs, observed: &Prefs) -> Vec<String> {
    let inactive = |p: &Prefs| p.get("disabled").is_some_and(|v| v == "true");
    let mirrored = |p: &Prefs| p.get("mirror").is_some_and(|v| !v.is_empty());
    FIELDS
        .iter()
        .filter(|field| {
            if (inactive(saved) || inactive(observed)) && !["disabled", "mirror"].contains(field) {
                return false;
            }
            if (mirrored(saved) || mirrored(observed))
                && ["position", "mode", "scale", "transform"].contains(field)
            {
                return false;
            }
            !same(
                field,
                saved.get(**field).map_or("", String::as_str),
                observed.get(**field).map_or("", String::as_str),
            )
        })
        .map(|field| (*field).to_owned())
        .collect()
}

fn number(value: &str, min: f64, max: f64, name: &str) -> Result<(), String> {
    match value.parse::<f64>() {
        Ok(v) if v.is_finite() && (min..=max).contains(&v) => Ok(()),
        _ => Err(invalid(&format!("{name} must be between {min} and {max}"))),
    }
}

fn is_position(value: &str) -> bool {
    if let Some(rest) = value.strip_prefix("auto") {
        let rest = rest.strip_prefix("-center").unwrap_or(rest);
        return ["", "-up", "-down", "-left", "-right"].contains(&rest);
    }
    value
        .split_once('x')
        .is_some_and(|(x, y)| x.parse::<i64>().is_ok() && y.parse::<i64>().is_ok())
}

fn has_icc_signature(path: &std::path::Path) -> bool {
    use std::io::{Read, Seek, SeekFrom};
    let mut signature = [0u8; 4];
    std::fs::File::open(path)
        .and_then(|mut file| {
            file.seek(SeekFrom::Start(36))?;
            file.read_exact(&mut signature)
        })
        .is_ok_and(|_| &signature == b"acsp")
}

/// Validates one field against the actual monitor before anything reaches Hyprland.
pub fn validate(
    field: &str,
    value: &str,
    monitor: &Monitor,
    all: &[Monitor],
) -> Result<(), String> {
    match field {
        "disabled" => {
            if !["true", "false"].contains(&value) {
                return Err(invalid("Use true or false"));
            }
        }
        "mode" => {
            if !SYMBOLIC_MODES.contains(&value) {
                let wanted = parse_mode(value).ok_or_else(|| invalid("Invalid display mode"))?;
                if !modes(monitor).iter().any(|m| {
                    m.width == wanted.width
                        && m.height == wanted.height
                        && (m.refresh - wanted.refresh).abs() < 0.1
                }) {
                    return Err(invalid("This display does not offer that mode"));
                }
            }
        }
        "scale" => {
            if value != "auto" {
                number(value, 0.25, 10.0, "Scale")?;
            }
        }
        "transform" => {
            if !matches!(value.parse::<i64>(), Ok(0..=7)) {
                return Err(invalid("Transform must be 0 to 7"));
            }
        }
        "position" => {
            if !is_position(value) {
                return Err(invalid("Use XxY or an auto position"));
            }
        }
        "mirror" => {
            if !value.is_empty()
                && (value == monitor.name
                    || !all
                        .iter()
                        .any(|m| m.name == value && !m.disabled && m.mirror_of == "none"))
            {
                return Err(invalid("Choose another active display to mirror"));
            }
        }
        "bitdepth" => {
            if !["8", "10"].contains(&value) {
                return Err(invalid("Bit depth must be 8 or 10"));
            }
        }
        "cm" => {
            if !COLOR_PRESETS.contains(&value) {
                return Err(invalid("Unknown color preset"));
            }
            let hardware = &monitor.hardware_details;
            if ["hdr", "hdredid"].contains(&value) && !hardware.hdr {
                return Err(invalid("This display does not report HDR support"));
            }
            if ["wide", "dcip3", "dp3", "adobe", "edid"].contains(&value)
                && !(hardware.bt2020 || hardware.chroma || hardware.hdr)
            {
                return Err(invalid("This display does not report a wide color gamut"));
            }
        }
        "sdr_eotf" => {
            if !["default", "gamma22", "srgb"].contains(&value) {
                return Err(invalid("Use default, gamma22, or srgb"));
            }
        }
        "vrr" => {
            if !["", "0", "1", "2", "3"].contains(&value) {
                return Err(invalid("VRR must be empty or 0 to 3"));
            }
            if !value.is_empty() && value != "0" && !monitor.hardware_details.vrr_capable {
                return Err(invalid("This display does not report VRR support"));
            }
        }
        "icc" => {
            if !value.is_empty() {
                let path = std::path::Path::new(value);
                if !path.is_absolute() || value.contains(['\n', '"', '\\']) || !path.is_file() {
                    return Err(invalid("Choose an existing ICC file by absolute path"));
                }
                // Hyprland accepts any readable path, so check the profile signature.
                if !has_icc_signature(path) {
                    return Err(invalid("This file is not an ICC profile"));
                }
            }
        }
        "reserved_area" => {
            let sides = value.split_whitespace().collect::<Vec<_>>();
            if sides.len() != 4 || sides.iter().any(|s| s.parse::<u32>().is_err()) {
                return Err(invalid("Use four numbers: top right bottom left"));
            }
        }
        "supports_wide_color" | "supports_hdr" => {
            if !["-1", "0", "1"].contains(&value) {
                return Err(invalid("Use -1, 0, or 1"));
            }
        }
        "sdrbrightness" | "sdrsaturation" => number(value, 0.0, 5.0, "This value")?,
        "sdr_min_luminance" => number(value, 0.0, 100.0, "SDR minimum luminance")?,
        "sdr_max_luminance" => number(value, 1.0, 10000.0, "SDR maximum luminance")?,
        "min_luminance" => number(value, -1.0, 100.0, "Minimum luminance")?,
        "max_luminance" | "max_avg_luminance" => number(value, -1.0, 10000.0, "Luminance")?,
        _ => return Err(invalid("Unknown display field")),
    }
    Ok(())
}

/// The Lua literal for a value, or `None` when the rule field should be absent.
pub fn lua_value(field: &str, value: &str) -> Option<String> {
    match field {
        "mode" | "position" | "cm" | "sdr_eotf" => Some(quote(value)),
        "mirror" | "icc" => (!value.is_empty()).then(|| quote(value)),
        "scale" if value == "auto" => Some(quote(value)),
        "vrr" => (!value.is_empty()).then(|| value.to_owned()),
        "reserved_area" => {
            let sides = value.split_whitespace().collect::<Vec<_>>();
            if sides.iter().all(|s| *s == "0") {
                return None;
            }
            Some(format!(
                "{{ top = {}, right = {}, bottom = {}, left = {} }}",
                sides.first()?,
                sides.get(1)?,
                sides.get(2)?,
                sides.get(3)?
            ))
        }
        _ => Some(value.to_owned()),
    }
}

/// One `hl.monitor` statement for live application. Clearing `mirror` needs an empty
/// string, `vrr` falls back to the global option, and `icc` cannot be cleared live.
pub fn live_statement(name: &str, changes: &[(String, String)], global_vrr: i64) -> Option<String> {
    let mut fields = vec![format!("output={}", quote(name))];
    for (field, value) in changes {
        let literal = match (field.as_str(), value.as_str()) {
            ("mirror", "") => "\"\"".to_owned(),
            ("vrr", "") => global_vrr.to_string(),
            ("icc", "") => continue,
            ("reserved_area", _) if lua_value(field, value).is_none() => "0".to_owned(),
            _ => lua_value(field, value)?,
        };
        fields.push(format!("{field}={literal}"));
    }
    (fields.len() > 1).then(|| format!("hl.monitor({{{}}})", fields.join(",")))
}

/// Whether live readback confirms a request. Symbolic and write-only fields have no
/// readable equivalent. Scale may be snapped by Hyprland and is adopted from readback.
pub fn confirmed(field: &str, wanted: &str, observed: &Prefs, monitor: &Monitor) -> bool {
    let got = observed.get(field).map_or("", String::as_str);
    match field {
        "mode" => {
            SYMBOLIC_MODES.contains(&wanted)
                || parse_mode(wanted).is_some_and(|w| {
                    w.width == monitor.width
                        && w.height == monitor.height
                        && (w.refresh - monitor.refresh_rate).abs() < 0.5
                })
        }
        "scale" => {
            wanted == "auto"
                || wanted
                    .parse::<f64>()
                    .is_ok_and(|w| (w - monitor.scale).abs() < 0.25)
        }
        "position" => {
            wanted.starts_with("auto")
                || wanted == format!("{}x{}", monitor.x, monitor.y)
                || monitor.mirror_of != "none"
        }
        "cm" => wanted == "auto" || monitor.color_management_preset == wanted,
        "disabled" | "mirror" | "transform" | "bitdepth" | "sdrbrightness" | "sdrsaturation"
        | "sdr_min_luminance" | "sdr_max_luminance" => same(field, wanted, got),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::parse;

    fn monitor() -> Monitor {
        Monitor {
            id: 0,
            name: "A".into(),
            width: 1920,
            height: 1080,
            refresh_rate: 60.0,
            scale: 1.3333334,
            mirror_of: "none".into(),
            current_format: "XRGB8888".into(),
            color_management_preset: "srgb".into(),
            sdr_brightness: 1.0,
            sdr_saturation: 1.0,
            sdr_min_luminance: 0.2,
            sdr_max_luminance: 80.0,
            available_modes: vec![
                "1280x720@60.00Hz".into(),
                "1920x1080@60.00Hz".into(),
                "1920x1080@60.00Hz".into(),
                "1920x1080@144.00Hz".into(),
            ],
            ..Default::default()
        }
    }

    #[test]
    fn scales_match_hyprland_snapping() {
        let options = scale_options(1920, 1080);
        for expected in ["1", "1.25", "1.3333", "1.5", "1.6", "2"] {
            assert!(
                options.iter().any(|o| o == expected),
                "{expected} {options:?}"
            );
        }
        // Verified on Hyprland 0.57: 1.5 on 1280x720 is snapped to 1.6.
        let small = scale_options(1280, 720);
        assert!(!small.iter().any(|o| o == "1.5"));
        assert!(small.iter().any(|o| o == "1.6"));
        assert!(scale_options(0, 0).is_empty());
    }

    #[test]
    fn modes_are_unique_and_largest_first() {
        let list = modes(&monitor());
        assert_eq!(list.len(), 3);
        assert_eq!(list[0].refresh, 144.0);
        assert_eq!(list[2].width, 1280);
    }

    #[test]
    fn symbolic_rule_values_do_not_conflict_with_resolved_readback() {
        let file = parse("hl.monitor({output=\"A\",scale=\"auto\",position=\"auto-right\",vrr=2})")
            .unwrap();
        let monitor = monitor();
        let observed = observe(&monitor, file.find("A", ""), std::slice::from_ref(&monitor));
        assert_eq!(observed["scale"], "auto");
        assert_eq!(observed["position"], "auto-right");
        assert_eq!(observed["mode"], "1920x1080@60.00");
        assert_eq!(observed["vrr"], "2");
        let bare = observe(&monitor, None, std::slice::from_ref(&monitor));
        assert_eq!(bare["position"], "auto");
        let mut saved = observed.clone();
        saved.insert("mode".into(), "1920x1080@60.0".into());
        assert!(differences(&saved, &observed).is_empty());
        saved.insert("transform".into(), "1".into());
        assert_eq!(differences(&saved, &observed), ["transform"]);
    }

    #[test]
    fn disabled_outputs_compare_only_their_state() {
        let mut live = monitor();
        live.disabled = true;
        let observed = observe(&live, None, std::slice::from_ref(&live));
        assert_eq!(observed["mode"], "preferred");
        let mut saved = observed.clone();
        saved.insert("transform".into(), "3".into());
        assert!(differences(&saved, &observed).is_empty());
        saved.insert("disabled".into(), "false".into());
        assert_eq!(differences(&saved, &observed), ["disabled"]);
    }

    #[test]
    fn validation_rejects_values_the_hardware_cannot_use() {
        let m = monitor();
        let all = std::slice::from_ref(&m);
        assert!(validate("mode", "1920x1080@144", &m, all).is_ok());
        assert!(validate("mode", "preferred", &m, all).is_ok());
        assert!(validate("mode", "800x600@60", &m, all).is_err());
        assert!(validate("mode", "x; os.exit()", &m, all).is_err());
        assert!(validate("position", "-100x20", &m, all).is_ok());
        assert!(validate("position", "auto-center-left", &m, all).is_ok());
        assert!(validate("position", "1x\"", &m, all).is_err());
        assert!(validate("cm", "hdr", &m, all).unwrap_err().contains("HDR"));
        assert!(validate("vrr", "1", &m, all).is_err());
        assert!(validate("vrr", "", &m, all).is_ok());
        assert!(validate("mirror", "A", &m, all).is_err());
        assert!(validate("icc", "relative.icc", &m, all).is_err());
        assert!(validate("icc", "", &m, all).is_ok());
        let dir = tempfile::tempdir().unwrap();
        let profile = dir.path().join("p.icc");
        std::fs::write(&profile, b"not a profile").unwrap();
        assert!(validate("icc", profile.to_str().unwrap(), &m, all).is_err());
        let mut bytes = vec![0u8; 36];
        bytes.extend_from_slice(b"acsp");
        std::fs::write(&profile, &bytes).unwrap();
        assert!(validate("icc", profile.to_str().unwrap(), &m, all).is_ok());
        assert!(validate("reserved_area", "1 2 3", &m, all).is_err());
        assert!(validate("scale", "0", &m, all).is_err());
        assert!(validate("unknown", "1", &m, all).is_err());
    }

    #[test]
    fn live_statements_render_clears_and_quote_values() {
        assert_eq!(
            live_statement(
                "A",
                &[("mirror".into(), "".into()), ("vrr".into(), "".into())],
                1
            )
            .unwrap(),
            "hl.monitor({output=\"A\",mirror=\"\",vrr=1})"
        );
        assert_eq!(
            live_statement("A", &[("scale".into(), "auto".into())], 0).unwrap(),
            "hl.monitor({output=\"A\",scale=\"auto\"})"
        );
        assert!(live_statement("A", &[("icc".into(), "".into())], 0).is_none());
        assert_eq!(lua_value("reserved_area", "0 0 0 0"), None);
        assert_eq!(
            lua_value("reserved_area", "1 2 3 4").unwrap(),
            "{ top = 1, right = 2, bottom = 3, left = 4 }"
        );
    }
}
