//! Text size: GNOME's `text-scaling-factor`, which GTK 3, GTK 4 and Flutter apps
//! follow. Settings keeps its own copy in `text-size.toml` for reconciliation.
use crate::system_theme::{AppearancePlan, Context, setting_change};
use gio::glib::variant::ToVariant;
use gio::prelude::*;
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs;
use std::path::PathBuf;

pub const FEATURE: &str = "text-size";
pub const SCALE: &str = "text-size.scale";
/// The range GNOME's schema accepts.
pub const SCALES: std::ops::RangeInclusive<f64> = 0.5..=3.0;
const KEY: &str = "text-scaling-factor";

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Prefs {
    text_scaling_factor: f64,
}

fn read_context(context: &Context) -> Result<f64, String> {
    let settings = context
        .gnome
        .as_ref()
        .ok_or("The GNOME interface settings schema is not installed")?;
    let schema = settings.settings_schema().ok_or("Missing GNOME schema")?;
    if !schema.has_key(KEY) {
        return Err(format!("GNOME interface settings have no {KEY} key"));
    }
    Ok(settings.double(KEY))
}

fn apply_context(context: &Context, scale: f64) -> Result<(), String> {
    let _lock = context.lock()?;
    let settings = context.gnome.as_ref().ok_or("Missing GNOME settings")?;
    let settings_changes: Vec<_> = setting_change(settings, KEY, scale.to_variant())?
        .into_iter()
        .collect();
    AppearancePlan {
        settings_changes,
        files: vec![],
        targets: vec![],
    }
    .apply(context)?;
    if read_context(context)? != scale {
        return Err("The text size did not read back".into());
    }
    Ok(())
}

/// Saved and live text scaling factor.
pub struct TextSize {
    saved_path: PathBuf,
    saved: Option<f64>,
    system: Option<f64>,
    error: Option<String>,
}

pub fn is_setting(id: &str) -> bool {
    id == SCALE
}

impl TextSize {
    pub fn new(saved_path: PathBuf) -> Self {
        Self {
            saved_path,
            saved: None,
            system: None,
            error: None,
        }
    }

    fn read(&mut self, context: Result<&Context, &String>) -> Result<(), String> {
        let system = context.map_err(String::clone).and_then(read_context);
        self.system = system.as_ref().ok().copied();
        self.saved = match fs::read_to_string(&self.saved_path) {
            Ok(text) => Some(
                toml::from_str::<Prefs>(&text)
                    .map_err(|e| format!("{}: {e}", self.saved_path.display()))?
                    .text_scaling_factor,
            ),
            // First use saves what the system uses now and changes nothing.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let system = system.clone()?;
                self.save(system)?;
                Some(system)
            }
            Err(e) => return Err(format!("{}: {e}", self.saved_path.display())),
        };
        system.map(|_| ())
    }

    fn refresh_with(&mut self, context: Result<&Context, &String>) -> Result<(), String> {
        let result = self.read(context);
        self.error = result.as_ref().err().cloned();
        result
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        self.refresh_with(Context::current().as_ref())
    }

    fn save(&self, scale: f64) -> Result<(), String> {
        let text = toml::to_string(&Prefs {
            text_scaling_factor: scale,
        })
        .map_err(|e| e.to_string())?;
        atomic_write(&self.saved_path, text.as_bytes())
    }

    fn conflict(&self) -> bool {
        matches!((self.saved, self.system), (Some(a), Some(b)) if a != b)
    }

    pub fn state(&self) -> Value {
        let by_id = |v: Option<f64>| v.map(|v| json!({ SCALE: v }));
        json!({
            "options": by_id(self.saved),
            "saved": by_id(self.saved),
            "system": by_id(self.system),
            "conflict": self.conflict(),
            "conflicts": if self.conflict() { vec![SCALE] } else { vec![] },
            "range": [SCALES.start(), SCALES.end()],
            "error": self.error,
        })
    }

    pub fn setting_value(&self) -> Value {
        json!(self.saved)
    }

    fn change(&mut self, context: &Context, value: &Value) -> Result<(), String> {
        let scale = value
            .as_f64()
            .filter(|v| SCALES.contains(v))
            .ok_or_else(|| {
                format!(
                    "InvalidArgument:Use a text scaling factor from {} to {}",
                    SCALES.start(),
                    SCALES.end()
                )
            })?;
        self.refresh_with(Ok(context))?;
        if self.conflict() {
            return Err("Resolve the text size conflict first".into());
        }
        apply_context(context, scale)?;
        self.save(scale)
    }

    fn set_with(
        &mut self,
        context: Result<&Context, &String>,
        input: &str,
    ) -> Result<Value, String> {
        let result = serde_json::from_str::<Value>(input)
            .map_err(|_| "InvalidArgument:Expected JSON".to_owned())
            .and_then(|value| self.change(context.map_err(String::clone)?, &value));
        let _ = self.refresh_with(context);
        if let Err(error) = &result
            && !error.starts_with("InvalidArgument:")
        {
            self.error = Some(error.clone());
        }
        result.map(|()| self.state())
    }

    pub fn set(&mut self, input: &str) -> Result<Value, String> {
        self.set_with(Context::current().as_ref(), input)
    }

    fn resolve_with(&mut self, context: &Context, source: &str) -> Result<Value, String> {
        self.refresh_with(Ok(context))?;
        let system = self.system.ok_or("The system text size cannot be read")?;
        match source {
            "system" => self.save(system)?,
            "settings" => {
                let saved = self.saved.ok_or("Nothing is saved yet")?;
                if let Err(error) = apply_context(context, saved) {
                    self.error = Some(error.clone());
                    return Err(error);
                }
            }
            _ => return Err("InvalidArgument:Unknown resolution".into()),
        }
        self.refresh_with(Ok(context))?;
        Ok(self.state())
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        self.resolve_with(&Context::current()?, source)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_use_adopts_then_conflicts_resolve_both_ways_and_failures_stay() {
        let dir = tempfile::tempdir().unwrap();
        let context = crate::system_theme::tests::context(&dir.path().join("config"));
        let gnome = context.gnome.as_ref().unwrap();
        gnome.set_double(KEY, 1.25).unwrap();
        let path = dir.path().join("text-size.toml");
        let mut text = TextSize::new(path.clone());
        let ctx = Ok(&context);

        // First use saves the system value and writes nothing.
        text.refresh_with(ctx).unwrap();
        assert_eq!(text.state()["options"][SCALE], 1.25);
        assert!(fs::read_to_string(&path).unwrap().contains("1.25"));

        text.set_with(ctx, "1.5").unwrap();
        assert_eq!(gnome.double(KEY), 1.5);
        assert!(
            text.set_with(ctx, "3.5")
                .unwrap_err()
                .starts_with("InvalidArgument:")
        );
        assert!(text.set_with(ctx, "\"big\"").is_err());
        assert_eq!(gnome.double(KEY), 1.5);

        // Another tool changes the system: both values are kept until resolved.
        gnome.set_double(KEY, 2.0).unwrap();
        text.refresh_with(ctx).unwrap();
        let state = text.state();
        assert_eq!(state["conflicts"], json!([SCALE]));
        assert_eq!(
            (
                state["saved"][SCALE].clone(),
                state["system"][SCALE].clone()
            ),
            (json!(1.5), json!(2.0))
        );
        assert!(text.set_with(ctx, "1.0").unwrap_err().contains("conflict"));
        assert!(text.state()["error"].as_str().unwrap().contains("conflict"));
        assert_eq!(gnome.double(KEY), 2.0);
        text.resolve_with(&context, "settings").unwrap();
        assert_eq!(gnome.double(KEY), 1.5);
        gnome.set_double(KEY, 0.75).unwrap();
        text.resolve_with(&context, "system").unwrap();
        assert_eq!(text.state()["options"][SCALE], 0.75);
        assert_eq!(text.state()["conflict"], false);

        // Failed detection leaves a fresh configuration uninitialized.
        let mut fresh = TextSize::new(dir.path().join("fresh.toml"));
        assert!(fresh.refresh_with(Err(&"no schema".to_owned())).is_err());
        assert!(!dir.path().join("fresh.toml").exists());
        assert_eq!(fresh.state()["error"], "no schema");
    }
}
