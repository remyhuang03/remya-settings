//! The seed color of Remya's Material schemes. It is an application preference, so
//! a missing file means "unchanged default" and never triggers a write.
use material_colors::{color::Rgb, image::extract_color};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const DEFAULT_COLOR: &str = "#8054C9";

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Accent {
    pub version: u8,
    pub source: String,
    pub color: String,
    /// The background the sampled color came from, to resample after it changes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sampled_from: Option<String>,
}

impl Default for Accent {
    fn default() -> Self {
        Self {
            version: 1,
            source: "custom".into(),
            color: DEFAULT_COLOR.into(),
            sampled_from: None,
        }
    }
}

pub fn normalize_color(value: &str) -> Option<String> {
    let hex = value.strip_prefix('#')?;
    (hex.len() == 6 && hex.chars().all(|c| c.is_ascii_hexdigit()))
        .then(|| format!("#{}", hex.to_ascii_uppercase()))
}

pub fn load(path: &Path) -> Result<Accent, String> {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Accent::default()),
        Err(e) => return Err(e.to_string()),
    };
    let accent: Accent =
        toml::from_str(&text).map_err(|e| format!("Invalid accent configuration: {e}"))?;
    if accent.version != 1
        || !["custom", "background"].contains(&accent.source.as_str())
        || normalize_color(&accent.color).as_deref() != Some(accent.color.as_str())
    {
        return Err("Invalid accent configuration".into());
    }
    Ok(accent)
}

/// Material color utilities' source color: Celebi quantization, then Score's top choice.
pub fn seed_from_pixels(rgba: &[u8]) -> Result<String, String> {
    let pixels = rgba
        .as_chunks::<4>()
        .0
        .iter()
        .filter(|[.., alpha]| *alpha == 255)
        .map(|[red, green, blue, _]| Rgb::new(*red, *green, *blue))
        .collect::<Vec<_>>();
    if pixels.is_empty() {
        return Err("The background has no opaque pixels to sample".into());
    }
    let seed = extract_color(&pixels);
    Ok(format!(
        "#{:02X}{:02X}{:02X}",
        seed.red, seed.green, seed.blue
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(r: u8, g: u8, b: u8) -> Vec<u8> {
        [r, g, b, 255].repeat(64)
    }

    #[test]
    fn sampling_follows_the_dominant_chromatic_color() {
        let mut image = solid(30, 90, 220);
        image.extend([20, 20, 20, 255].repeat(8));
        let seed = seed_from_pixels(&image).unwrap();
        let channel = |i: usize| u8::from_str_radix(&seed[i..i + 2], 16).unwrap();
        assert!(channel(5) > channel(1), "{seed} should stay blue");
        assert!(seed_from_pixels(&[0, 0, 0, 0]).is_err());
    }

    #[test]
    fn colors_are_validated_and_normalized() {
        assert_eq!(normalize_color("#a1b2c3").unwrap(), "#A1B2C3");
        for bad in ["a1b2c3", "#a1b2c", "#a1b2cz", "#a1b2c3ff"] {
            assert!(normalize_color(bad).is_none());
        }
    }

    #[test]
    fn missing_is_default_and_malformed_is_rejected() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("accent.toml");
        assert_eq!(load(&file).unwrap(), Accent::default());
        std::fs::write(&file, "version = 1\nsource = \"x\"\ncolor = \"#000000\"\n").unwrap();
        assert!(load(&file).is_err());
    }
}
