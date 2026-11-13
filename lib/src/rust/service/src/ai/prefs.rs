//! `remya-ai.toml`: Bar quota preferences and custom OpenAI-compatible endpoints.
use serde::{Deserialize, Serialize};
use std::{collections::HashSet, fs, path::Path};

pub const MAX_PINNED: usize = 3;
const DEFAULT_LOW_PERCENT: u8 = 20;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    #[serde(default)]
    pub bar: Bar,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub custom: Vec<Custom>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum RingOrder {
    #[default]
    #[serde(rename = "5h-outer")]
    FiveHourOuter,
    #[serde(rename = "5h-inner")]
    FiveHourInner,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bar {
    #[serde(default)]
    pub pinned: Vec<String>,
    #[serde(default = "default_low_percent")]
    pub low_percent: u8,
    #[serde(default)]
    pub show_used: bool,
    #[serde(default)]
    pub ring_order: RingOrder,
}

impl Default for Bar {
    fn default() -> Self {
        Self {
            pinned: Vec::new(),
            low_percent: DEFAULT_LOW_PERCENT,
            show_used: false,
            ring_order: RingOrder::FiveHourOuter,
        }
    }
}

fn default_low_percent() -> u8 {
    DEFAULT_LOW_PERCENT
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Custom {
    pub id: String,
    pub name: String,
    pub base_url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub models_dev: Option<String>,
}

pub fn validate_pinned(pinned: &[String]) -> Result<(), String> {
    let mut seen = HashSet::new();
    if pinned.len() > MAX_PINNED || !pinned.iter().all(|id| seen.insert(id)) {
        return Err(format!("Pin at most {MAX_PINNED} unique providers"));
    }
    Ok(())
}

pub fn validate_low_percent(value: i64) -> Result<u8, String> {
    u8::try_from(value)
        .ok()
        .filter(|value| (1..=100).contains(value))
        .ok_or_else(|| "Low quota percent must be between 1 and 100".into())
}

/// Accepts https endpoints, or http only on a loopback host. Credentials in
/// the URL are refused because the file is not secret storage.
pub fn validate_base_url(url: &str) -> Result<(), String> {
    let error = || "Base URL must be https, or http on a loopback host".to_string();
    let uri: ureq::http::Uri = url.parse().map_err(|_| error())?;
    let authority = uri.authority().ok_or_else(error)?;
    if authority.as_str().contains('@') || url.chars().any(char::is_control) {
        return Err(error());
    }
    let host = authority
        .host()
        .trim_start_matches('[')
        .trim_end_matches(']');
    let loopback = host == "localhost"
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    match uri.scheme_str() {
        Some("https") if !host.is_empty() => Ok(()),
        Some("http") if loopback => Ok(()),
        _ => Err(error()),
    }
}

pub fn valid_models_dev_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "-_.".contains(c))
}

pub fn validate_name(name: &str) -> Result<&str, String> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 64 || name.chars().any(char::is_control) {
        return Err("Name must be 1 to 64 characters without control characters".into());
    }
    Ok(name)
}

/// `custom-<slug>` from the display name; `None` when nothing usable remains.
pub fn custom_id(name: &str) -> Option<String> {
    let mut slug = String::new();
    for c in name.chars().flat_map(char::to_lowercase) {
        if c.is_ascii_alphanumeric() {
            slug.push(c);
        } else if !slug.is_empty() && !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let slug = slug.trim_end_matches('-');
    (!slug.is_empty()).then(|| format!("custom-{slug}"))
}

impl Prefs {
    pub fn validate(&self) -> Result<(), String> {
        validate_pinned(&self.bar.pinned)?;
        validate_low_percent(self.bar.low_percent.into())?;
        let mut ids = HashSet::new();
        for custom in &self.custom {
            let slug = custom.id.strip_prefix("custom-").unwrap_or_default();
            if custom_id(slug).as_deref() != Some(&custom.id[..]) || !ids.insert(&custom.id) {
                return Err("Invalid or duplicate custom provider id".into());
            }
            validate_name(&custom.name)?;
            validate_base_url(&custom.base_url)?;
            if custom
                .models_dev
                .as_deref()
                .is_some_and(|id| !valid_models_dev_id(id))
            {
                return Err("Invalid models.dev provider id".into());
            }
        }
        Ok(())
    }

    /// Missing file means defaults; an invalid file is an error so it is never overwritten.
    pub fn load(path: &Path) -> Result<Self, String> {
        let prefs: Self = match fs::read_to_string(path) {
            Ok(text) => toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(e) => return Err(e.to_string()),
        };
        prefs
            .validate()
            .map_err(|e| format!("{}: {e}", path.display()))?;
        Ok(prefs)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        self.validate()?;
        let text = toml::to_string(self).map_err(|e| e.to_string())?;
        remya_settings_display::atomic_write(path, text.as_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pins_are_capped_and_unique() {
        let ids = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(validate_pinned(&ids(&["claude", "codex", "antigravity"])).is_ok());
        assert!(validate_pinned(&ids(&["a", "b", "c", "d"])).is_err());
        assert!(validate_pinned(&ids(&["claude", "claude"])).is_err());
    }

    #[test]
    fn low_percent_bounds() {
        assert_eq!(validate_low_percent(1), Ok(1));
        assert_eq!(validate_low_percent(100), Ok(100));
        assert!(validate_low_percent(0).is_err());
        assert!(validate_low_percent(101).is_err());
        assert!(validate_low_percent(-5).is_err());
    }

    #[test]
    fn base_url_requires_https_or_loopback_http() {
        for ok in [
            "https://api.example.com/v1",
            "http://localhost:11434/v1",
            "http://127.0.0.1:8080",
            "http://[::1]:8080/v1",
        ] {
            assert!(validate_base_url(ok).is_ok(), "{ok}");
        }
        for bad in [
            "http://api.example.com/v1",
            "ftp://example.com",
            "https://user:pw@example.com",
            "example.com",
            "",
        ] {
            assert!(validate_base_url(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn custom_ids_are_slugs() {
        assert_eq!(
            custom_id("My Endpoint").as_deref(),
            Some("custom-my-endpoint")
        );
        assert_eq!(
            custom_id("  Groq (fast)!! ").as_deref(),
            Some("custom-groq-fast")
        );
        assert_eq!(custom_id("日本"), None);
    }

    #[test]
    fn toml_round_trip_and_rejection() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("remya-ai.toml");
        assert_eq!(Prefs::load(&path).unwrap(), Prefs::default());
        let prefs = Prefs {
            bar: Bar {
                pinned: vec!["claude".into(), "codex".into()],
                low_percent: 15,
                show_used: true,
                ring_order: RingOrder::FiveHourInner,
            },
            custom: vec![Custom {
                id: "custom-my-endpoint".into(),
                name: "My Endpoint".into(),
                base_url: "https://api.example.com/v1".into(),
                models_dev: Some("openrouter".into()),
            }],
        };
        prefs.save(&path).unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert!(
            text.contains("[bar]") && text.contains("[[custom]]"),
            "{text}"
        );
        assert_eq!(Prefs::load(&path).unwrap(), prefs);
        fs::write(&path, "[bar]\nring_order = \"other\"\n").unwrap();
        assert!(Prefs::load(&path).is_err());
        fs::write(&path, "[bar]\nlow_percent = 0\n").unwrap();
        assert!(Prefs::load(&path).is_err());
        fs::write(&path, "[bar]\nunknown = 1\n").unwrap();
        assert!(Prefs::load(&path).is_err());
    }
}
