//! AI providers: CodexBar usage and credentials, custom endpoints and the
//! Bar quota preferences, described with models.dev metadata.
mod codexbar;
mod models_dev;
mod prefs;
mod secrets;

use models_dev::Status;
use prefs::{Custom, Prefs};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime},
};

pub const PROVIDERS: &str = "ai.providers";
pub const PROVIDER_PREFIX: &str = "ai.provider/";
pub const BAR: &str = "ai.bar";
pub const CREDENTIAL: &str = "ai.credential";
pub const CUSTOM: &str = "ai.custom";
/// Settable ids; each Set emits Changed for its own id and for `ai.providers`.
pub const SET_IDS: [&str; 4] = [PROVIDERS, BAR, CREDENTIAL, CUSTOM];

const TTL: Duration = Duration::from_secs(5 * 60);
const SOURCES: &[&str] = &["auto", "web", "cli", "oauth", "api"];
const MAX_SECRET: usize = 16 << 10;

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

struct Probe {
    at: Instant,
    updated_at: String,
    version: Option<String>,
    usage: Vec<Value>,
}

struct Snapshot {
    value: Value,
    visible: Vec<Value>,
    catalog: Vec<Value>,
    /// Sanitized probe rows.
    usage: Vec<Value>,
}

pub struct Ai {
    prefs: PathBuf,
    probe: Option<Probe>,
    models: Option<(Instant, Status, Option<Value>)>,
}

/// Removes account e-mail addresses at any depth before usage leaves CodexBar.
fn strip_email(value: &mut Value) {
    match value {
        Value::Object(map) => {
            map.retain(|key, _| !key.to_ascii_lowercase().ends_with("email"));
            map.values_mut().for_each(strip_email);
        }
        Value::Array(items) => items.iter_mut().for_each(strip_email),
        _ => {}
    }
}

fn credential_configured(dump: Option<&Value>) -> bool {
    dump.is_some_and(|entry| {
        ["apiKey", "cookieHeader"]
            .iter()
            .any(|key| entry[key].as_str().is_some_and(|s| !s.is_empty()))
            || entry["tokenAccounts"]
                .as_array()
                .is_some_and(|accounts| !accounts.is_empty())
            || entry["tokenAccounts"]
                .as_object()
                .is_some_and(|accounts| !accounts.is_empty())
    })
}

#[derive(Debug, PartialEq)]
enum Visibility {
    Visible(&'static str, Option<String>),
    Catalog,
    Hidden,
}

/// Ready usage, or a configured credential, makes a provider visible. Runtime
/// failures of providers without a Linux credential path stay hidden.
fn classify(provider: &Value, dump: Option<&Value>, usage: Option<&Value>) -> Visibility {
    let auth = &provider["authentication"];
    let error = usage.map(|row| &row["error"]).filter(|e| e.is_object());
    if usage.is_some_and(|row| row["usage"].is_object()) {
        return Visibility::Visible("ready", None);
    }
    if credential_configured(dump) {
        return match error {
            Some(error) => Visibility::Visible(
                "error",
                Some(
                    error["message"]
                        .as_str()
                        .unwrap_or("Usage unavailable")
                        .into(),
                ),
            ),
            None => Visibility::Visible("needs-setup", None),
        };
    }
    let supports =
        auth["supportsConfigAPIKey"] == true || auth["supportsConfigCookieHeader"] == true;
    if error.is_some_and(|e| e["kind"] == "runtime") && !supports {
        return Visibility::Hidden;
    }
    Visibility::Catalog
}

fn models_dev_id(id: &str, catalog: Option<&Value>) -> Option<String> {
    let alias = match id {
        "claude" => Some("anthropic"),
        "codex" => Some("openai"),
        "gemini" | "antigravity" => Some("google"),
        "moonshot" => Some("moonshotai"),
        "xai" | "grok" => Some("xai"),
        "vertexai" => Some("google-vertex"),
        _ => None,
    };
    alias.map(str::to_owned).or_else(|| {
        catalog
            .is_some_and(|catalog| catalog[id].is_object())
            .then(|| id.to_owned())
    })
}

fn window_label(minutes: Option<u64>) -> Option<String> {
    match minutes? {
        10080 => Some("Week".into()),
        1440 => Some("Day".into()),
        m if m > 0 && m < 1440 && m % 60 == 0 => Some(format!("{}h", m / 60)),
        _ => None,
    }
}

fn windows(usage: Option<&Value>) -> Vec<Value> {
    let Some(row) = usage.filter(|row| row["usage"].is_object()) else {
        return Vec::new();
    };
    ["primary", "secondary", "tertiary"]
        .into_iter()
        .filter_map(|slot| {
            let window = &row["usage"][slot];
            let used = window["usedPercent"].as_f64()?;
            let minutes = window["windowMinutes"].as_u64();
            let label = row["rateWindowLabels"][slot]
                .as_str()
                .map(str::to_owned)
                .or_else(|| window_label(minutes));
            Some(json!({"slot":slot,"label":label,"windowMinutes":minutes,
                "usedPercent":used,"resetsAt":window["resetsAt"].as_str()}))
        })
        .collect()
}

struct Inputs<'a> {
    providers: &'a [Value],
    dump: &'a [Value],
    usage: &'a [Value],
    automatic: bool,
    custom: &'a [(Custom, bool)],
    models_dev: Option<&'a Value>,
}

fn codexbar_credential(provider: &Value, configured: Option<bool>) -> Value {
    let auth = &provider["authentication"];
    let mut credential = json!({"apiKey":auth["supportsConfigAPIKey"] == true,
        "cookie":auth["supportsConfigCookieHeader"] == true});
    if let Some(configured) = configured {
        credential["configured"] = json!(configured);
    }
    credential
}

fn source_modes(provider: &Value) -> Value {
    json!(
        provider["authentication"]["sourceModes"]
            .as_array()
            .cloned()
            .unwrap_or_default()
    )
}

/// Returns the visible provider rows and the addable catalog.
fn build(inputs: &Inputs) -> (Vec<Value>, Vec<Value>) {
    let mut visible = Vec::new();
    let mut catalog = Vec::new();
    let mut mapped = HashSet::new();
    for provider in inputs.providers {
        let id = provider["provider"].as_str().unwrap_or_default();
        let dump = inputs.dump.iter().find(|entry| entry["id"] == id);
        let usage = inputs.usage.iter().find(|row| row["provider"] == id);
        let models_dev = models_dev_id(id, inputs.models_dev);
        mapped.extend(models_dev.clone());
        mapped.insert(id.to_owned());
        match classify(provider, dump, usage) {
            Visibility::Visible(status, error) => {
                let ready = usage.filter(|row| row["usage"].is_object());
                let source = ready
                    .and_then(|row| row["source"].as_str())
                    .or_else(|| dump.and_then(|entry| entry["source"].as_str()))
                    .unwrap_or("auto");
                let plan = ready.and_then(|row| {
                    row["usage"]["identity"]["loginMethod"]
                        .as_str()
                        .or_else(|| row["usage"]["loginMethod"].as_str())
                });
                visible.push(json!({
                    "id":id,"name":provider["displayName"],"kind":"codexbar","status":status,
                    "enabled":inputs.automatic || provider["enabled"] == true,
                    "source":source,"plan":plan,"sourceModes":source_modes(provider),
                    "credential":codexbar_credential(provider, Some(credential_configured(dump))),
                    "envVars":provider["authentication"]["environmentVariables"].as_array().cloned().unwrap_or_default(),
                    "error":error,"baseUrl":null,"modelsDev":models_dev,"windows":windows(ready),
                }));
            }
            Visibility::Catalog => catalog.push(json!({
                "id":id,"name":provider["displayName"],"kind":"codexbar",
                "credential":codexbar_credential(provider, None),"sourceModes":source_modes(provider),
            })),
            Visibility::Hidden => {}
        }
    }
    for (custom, configured) in inputs.custom {
        visible.push(json!({
            "id":custom.id,"name":custom.name,"kind":"custom","status":"custom","enabled":true,
            "source":null,"plan":null,"sourceModes":[],
            "credential":{"apiKey":true,"cookie":false,"configured":configured},
            "envVars":[],"error":null,"baseUrl":custom.base_url,"modelsDev":custom.models_dev,"windows":[],
        }));
    }
    let mut extra: Vec<Value> = inputs
        .models_dev
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .filter(|(id, provider)| provider["api"].is_string() && !mapped.contains(*id))
        .map(|(id, provider)| {
            json!({"id":format!("models.dev:{id}"),"name":provider["name"].as_str().unwrap_or(id),
                "kind":"models-dev","baseUrl":provider["api"],"modelsDev":id})
        })
        .collect();
    extra.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    catalog.extend(extra);
    (visible, catalog)
}

fn now_iso() -> String {
    let seconds = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    gio::glib::DateTime::from_unix_utc(seconds)
        .and_then(|time| time.format("%Y-%m-%dT%H:%M:%SZ"))
        .map(|text| text.to_string())
        .unwrap_or_default()
}

fn check_secret(secret: &str) -> Result<(), String> {
    if secret.is_empty() || secret.len() > MAX_SECRET || secret.chars().any(char::is_control) {
        return Err(invalid(
            "Credentials must be non-empty, at most 16 KiB, without control characters",
        ));
    }
    Ok(())
}

impl Ai {
    pub fn new(prefs: PathBuf) -> Self {
        Self {
            prefs,
            probe: None,
            models: None,
        }
    }

    fn probe(&mut self, path: &Path) -> Result<&Probe, String> {
        if self
            .probe
            .as_ref()
            .is_none_or(|probe| probe.at.elapsed() >= TTL)
        {
            let version = codexbar::version()?;
            let mut usage = match version {
                Some(_) => codexbar::probe(path)?,
                None => Vec::new(),
            };
            usage.iter_mut().for_each(strip_email);
            self.probe = Some(Probe {
                at: Instant::now(),
                updated_at: now_iso(),
                version,
                usage,
            });
        }
        Ok(self.probe.as_ref().expect("probe cached"))
    }

    fn models_dev(&mut self) -> (Status, Option<&Value>) {
        if self
            .models
            .as_ref()
            .is_none_or(|(at, ..)| at.elapsed() >= TTL)
        {
            let cache = models_dev::cache_path();
            let (status, value) =
                models_dev::resolve(cache.as_deref(), SystemTime::now(), models_dev::fetch);
            self.models = Some((Instant::now(), status, value));
        }
        let (_, status, value) = self.models.as_ref().expect("models cached");
        (*status, value.as_ref())
    }

    fn snapshot(&mut self) -> Result<Snapshot, String> {
        let prefs = Prefs::load(&self.prefs)?;
        let path = codexbar::config_path()?;
        let probe = self.probe(&path)?;
        let (version, updated_at, usage) = (
            probe.version.clone(),
            probe.updated_at.clone(),
            probe.usage.clone(),
        );
        let (automatic, providers, dump) = if version.is_some() {
            let automatic = !codexbar::configured(&path)?;
            let dump = if automatic {
                Vec::new()
            } else {
                codexbar::cli(&path, &["config", "validate"])?;
                codexbar::dump(&path)?
            };
            (automatic, codexbar::providers(&path)?, dump)
        } else {
            (true, Vec::new(), Vec::new())
        };
        let custom: Vec<(Custom, bool)> = prefs
            .custom
            .iter()
            .map(|custom| (custom.clone(), secrets::exists(&custom.id)))
            .collect();
        let (_, models_dev) = self.models_dev();
        let (visible, catalog) = build(&Inputs {
            providers: &providers,
            dump: &dump,
            usage: &usage,
            automatic,
            custom: &custom,
            models_dev,
        });
        let value = json!({
            "codexbar":{"available":version.is_some(),"version":version},
            "updatedAt":updated_at,
            "providers":visible,
            "catalog":catalog,
            "bar":Self::bar_json(&prefs.bar),
        });
        Ok(Snapshot {
            value,
            visible,
            catalog,
            usage,
        })
    }

    fn reply(&mut self) -> Result<Value, String> {
        let value = self.snapshot()?.value;
        Ok(json!({"id":PROVIDERS,"availability":"available","value":value}))
    }

    fn bar_json(bar: &prefs::Bar) -> Value {
        json!({
            "pinned": bar.pinned,
            "lowPercent": bar.low_percent,
            "showUsed": bar.show_used,
            "ringOrder": bar.ring_order,
        })
    }

    pub fn is_get(key: &str) -> bool {
        key == PROVIDERS || key == BAR || key.starts_with(PROVIDER_PREFIX)
    }

    pub fn get(&mut self, key: &str) -> Result<Value, String> {
        if key == BAR {
            let bar = Prefs::load(&self.prefs)?.bar;
            return Ok(json!({"id":BAR,"availability":"available",
                "value":Self::bar_json(&bar)}));
        }
        let Some(id) = key.strip_prefix(PROVIDER_PREFIX) else {
            return self.reply();
        };
        let Snapshot {
            visible,
            catalog,
            usage,
            ..
        } = self.snapshot()?;
        let provider = visible
            .into_iter()
            .chain(catalog)
            .find(|row| row["id"] == id)
            .ok_or_else(|| invalid("Unknown AI provider"))?;
        let usage = usage.into_iter().find(|row| row["provider"] == id);
        let models_dev_id = provider["modelsDev"].as_str().map(str::to_owned);
        let (status, catalog) = self.models_dev();
        let entry = models_dev_id
            .as_deref()
            .and_then(|id| catalog.map(|catalog| &catalog[id]))
            .filter(|entry| entry.is_object());
        Ok(json!({"id":key,"availability":"available","value":{
            "provider":provider,"usage":usage,
            "modelsDev":{"status":status.name(),
                "provider":entry.map(models_dev::provider_summary),
                "models":entry.map(models_dev::models).unwrap_or_default()},
        }}))
    }

    pub fn set(&mut self, key: &str, request: &str) -> Result<Value, String> {
        match key {
            PROVIDERS => self.set_provider(request)?,
            // Pins change no CodexBar state, so the usage probe stays valid.
            BAR => return self.set_bar(request).and_then(|()| self.reply()),
            CREDENTIAL => self.set_credential(request)?,
            CUSTOM => self.set_custom(request)?,
            _ => return Err(invalid("Unknown setting")),
        }
        self.probe = None;
        self.reply()
    }

    fn codexbar_provider(path: &Path, id: &str) -> Result<(bool, Vec<Value>, Value), String> {
        let automatic = !codexbar::configured(path)?;
        if !automatic {
            codexbar::cli(path, &["config", "validate"])?;
        }
        let rows = codexbar::providers(path)?;
        let row = rows
            .iter()
            .find(|row| row["provider"] == id && codexbar::editable(row))
            .cloned()
            .ok_or_else(|| invalid("Unknown or unsupported AI provider"))?;
        Ok((automatic, rows, row))
    }

    fn set_provider(&mut self, request: &str) -> Result<(), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Change {
            id: String,
            enabled: Option<bool>,
            source: Option<String>,
        }
        let change: Change = serde_json::from_str(request)
            .ok()
            .filter(|c: &Change| c.enabled.is_some() || c.source.is_some())
            .ok_or_else(|| invalid("Expected a provider id with enabled and/or source"))?;
        let path = codexbar::config_path()?;
        let (automatic, rows, row) = Self::codexbar_provider(&path, &change.id)?;
        if let Some(source) = &change.source
            && (!SOURCES.contains(&source.as_str())
                || !source_modes(&row)
                    .as_array()
                    .is_some_and(|modes| modes.iter().any(|mode| mode == source)))
        {
            return Err(invalid("Unsupported source for this provider"));
        }
        if automatic {
            codexbar::initialize(&path, &rows, &change.id, change.enabled.unwrap_or(true))?;
        } else if let Some(enabled) = change.enabled {
            let action = if enabled { "enable" } else { "disable" };
            codexbar::cli(&path, &["config", action, "--provider", &change.id])?;
        }
        if let Some(source) = &change.source {
            codexbar::cli(
                &path,
                &[
                    "config",
                    "set-source",
                    "--provider",
                    &change.id,
                    "--source",
                    source,
                ],
            )?;
        }
        let enabled_kept = change.enabled.is_none_or(|enabled| {
            codexbar::providers(&path).is_ok_and(|rows| {
                rows.iter()
                    .any(|row| row["provider"] == change.id.as_str() && row["enabled"] == enabled)
            })
        });
        let source_kept = change.source.as_deref().is_none_or(|source| {
            codexbar::dump(&path).is_ok_and(|dump| {
                dump.iter().any(|entry| {
                    entry["id"] == change.id.as_str()
                        && entry["source"].as_str().unwrap_or("auto") == source
                })
            })
        });
        if !enabled_kept || !source_kept {
            return Err("Unavailable:CodexBar did not retain the requested provider state.".into());
        }
        Ok(())
    }

    fn set_bar(&mut self, request: &str) -> Result<(), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields, rename_all = "camelCase")]
        struct Change {
            pinned: Option<Vec<String>>,
            low_percent: Option<i64>,
            show_used: Option<bool>,
            ring_order: Option<prefs::RingOrder>,
        }
        let change: Change = serde_json::from_str(request)
            .ok()
            .filter(|c: &Change| {
                c.pinned.is_some()
                    || c.low_percent.is_some()
                    || c.show_used.is_some()
                    || c.ring_order.is_some()
            })
            .ok_or_else(|| invalid("Expected one of pinned, lowPercent, showUsed or ringOrder"))?;
        let mut prefs = Prefs::load(&self.prefs)?;
        if let Some(low) = change.low_percent {
            prefs.bar.low_percent = prefs::validate_low_percent(low).map_err(|e| invalid(&e))?;
        }
        if let Some(show_used) = change.show_used {
            prefs.bar.show_used = show_used;
        }
        if let Some(ring_order) = change.ring_order {
            prefs.bar.ring_order = ring_order;
        }
        if let Some(pinned) = change.pinned {
            prefs::validate_pinned(&pinned).map_err(|e| invalid(&e))?;
            let visible = self.snapshot()?.visible;
            if !pinned
                .iter()
                .all(|id| visible.iter().any(|row| row["id"] == id.as_str()))
            {
                return Err(invalid("Only visible providers can be pinned"));
            }
            prefs.bar.pinned = pinned;
        }
        prefs.save(&self.prefs)
    }

    fn set_credential(&mut self, request: &str) -> Result<(), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields, rename_all = "camelCase")]
        struct Change {
            id: String,
            api_key: Option<String>,
            cookie: Option<String>,
            #[serde(default)]
            clear: bool,
        }
        let change: Change = serde_json::from_str(request)
            .ok()
            .filter(|c: &Change| {
                [c.api_key.is_some(), c.cookie.is_some(), c.clear]
                    .iter()
                    .filter(|set| **set)
                    .count()
                    == 1
            })
            .ok_or_else(|| {
                invalid("Expected a provider id with exactly one of apiKey, cookie or clear")
            })?;
        for secret in [&change.api_key, &change.cookie].into_iter().flatten() {
            check_secret(secret)?;
        }
        if change.id.starts_with("custom-") {
            if !Prefs::load(&self.prefs)?
                .custom
                .iter()
                .any(|c| c.id == change.id)
            {
                return Err(invalid("Unknown AI provider"));
            }
            return match (&change.api_key, change.cookie.is_some()) {
                (Some(key), _) => secrets::store(&change.id, key),
                (None, true) => Err(invalid("Custom endpoints accept only an API key")),
                (None, false) => secrets::clear(&change.id),
            };
        }
        let path = codexbar::config_path()?;
        let (automatic, rows, row) = Self::codexbar_provider(&path, &change.id)?;
        let auth = &row["authentication"];
        if (change.api_key.is_some() && auth["supportsConfigAPIKey"] != true)
            || (change.cookie.is_some() && auth["supportsConfigCookieHeader"] != true)
        {
            return Err(invalid("This provider does not accept that credential"));
        }
        if automatic {
            codexbar::initialize(&path, &rows, &change.id, true)?;
        }
        let id = change.id.as_str();
        match (&change.api_key, &change.cookie) {
            (Some(key), _) => codexbar::cli_stdin(
                &path,
                &["config", "set-api-key", "--provider", id, "--stdin"],
                key,
            )?,
            (None, Some(cookie)) => codexbar::cli_stdin(
                &path,
                &["config", "set-cookie", "--provider", id, "--stdin"],
                cookie,
            )?,
            (None, None) => {
                codexbar::cli(&path, &["config", "clear-credential", "--provider", id])?
            }
        };
        let dump = codexbar::dump(&path)?;
        let entry = dump.iter().find(|entry| entry["id"] == id);
        let has = |key: &str| entry.is_some_and(|entry| entry[key].is_string());
        let kept = match (&change.api_key, &change.cookie) {
            (Some(_), _) => has("apiKey"),
            (None, Some(_)) => has("cookieHeader"),
            (None, None) => !has("apiKey") && !has("cookieHeader"),
        };
        if !kept {
            return Err("Unavailable:CodexBar did not retain the credential change.".into());
        }
        Ok(())
    }

    fn set_custom(&mut self, request: &str) -> Result<(), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields, rename_all = "camelCase")]
        struct Add {
            name: String,
            base_url: String,
            models_dev: Option<String>,
            api_key: Option<String>,
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Change {
            add: Option<Add>,
            remove: Option<String>,
        }
        let change: Change = serde_json::from_str(request)
            .ok()
            .filter(|c: &Change| c.add.is_some() != c.remove.is_some())
            .ok_or_else(|| invalid("Expected exactly one of add or remove"))?;
        let mut prefs = Prefs::load(&self.prefs)?;
        if let Some(id) = change.remove {
            let before = prefs.custom.len();
            prefs.custom.retain(|custom| custom.id != id);
            if prefs.custom.len() == before {
                return Err(invalid("Unknown custom provider"));
            }
            prefs.bar.pinned.retain(|pinned| *pinned != id);
            secrets::clear(&id)?;
            return prefs.save(&self.prefs);
        }
        let add = change.add.expect("add or remove");
        let name = prefs::validate_name(&add.name).map_err(|e| invalid(&e))?;
        let id =
            prefs::custom_id(name).ok_or_else(|| invalid("The name needs letters or digits"))?;
        prefs::validate_base_url(&add.base_url).map_err(|e| invalid(&e))?;
        if add
            .models_dev
            .as_deref()
            .is_some_and(|id| !prefs::valid_models_dev_id(id))
        {
            return Err(invalid("Invalid models.dev provider id"));
        }
        if prefs.custom.iter().any(|custom| custom.id == id) {
            return Err(invalid("A custom provider with this name already exists"));
        }
        if let Some(key) = &add.api_key {
            check_secret(key)?;
        }
        prefs.custom.push(Custom {
            id: id.clone(),
            name: name.to_owned(),
            base_url: add.base_url,
            models_dev: add.models_dev,
        });
        if let Some(key) = &add.api_key {
            secrets::store(&id, key)?;
        }
        prefs.save(&self.prefs).inspect_err(|_| {
            if add.api_key.is_some() {
                let _ = secrets::clear(&id);
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn provider(id: &str, api_key: bool, cookie: bool) -> Value {
        json!({"provider":id,"displayName":id.to_uppercase(),"enabled":false,"defaultEnabled":false,
            "authentication":{"supportsConfigAPIKey":api_key,"supportsConfigCookieHeader":cookie,
                "environmentVariables":["KEY"],"sourceModes":["api","auto"]}})
    }

    fn fixture() -> (Vec<Value>, Vec<Value>, Vec<Value>) {
        let providers = vec![
            provider("claude", false, true),
            provider("openrouter", true, false),
            provider("cursor", false, true),
            provider("macos", false, false),
            provider("zai", true, false),
        ];
        let dump = vec![
            json!({"id":"claude","enabled":true}),
            json!({"id":"openrouter","enabled":true,"apiKey":"[REDACTED]"}),
            json!({"id":"cursor","enabled":true,"cookieHeader":"[REDACTED]","cookieSource":"manual"}),
        ];
        let mut usage = vec![
            json!({"provider":"claude","source":"oauth","rateWindowLabels":{"secondary":"Weekly"},
                "usage":{"identity":{"loginMethod":"Claude Pro","accountEmail":"a@example.com"},
                "accountEmail":"a@example.com",
                "primary":{"usedPercent":22,"windowMinutes":300,"resetsAt":"2026-11-11T09:20:00Z"},
                "secondary":{"usedPercent":29.5,"windowMinutes":10080,"resetsAt":null},
                "tertiary":null}}),
            json!({"provider":"openrouter","source":"auto","error":{"kind":"provider","code":1,"message":"Bad key"}}),
            json!({"provider":"macos","source":"auto","error":{"kind":"runtime","code":1,"message":"macOS only"}}),
            json!({"provider":"zai","source":"auto","error":{"kind":"provider","code":1,"message":"No strategy"}}),
        ];
        usage.iter_mut().for_each(strip_email);
        (providers, dump, usage)
    }

    #[test]
    fn strips_emails_recursively() {
        let mut row = json!({"usage":{"identity":{"accountEmail":"x","loginMethod":"Pro"},
            "accounts":[{"email":"y","id":1}],"accountEmail":"x"}});
        strip_email(&mut row);
        assert!(!row.to_string().contains("mail"), "{row}");
        assert_eq!(row["usage"]["identity"]["loginMethod"], "Pro");
    }

    #[test]
    fn classifies_visible_catalog_and_hidden_providers() {
        let (providers, dump, usage) = fixture();
        let custom = [(
            Custom {
                id: "custom-local".into(),
                name: "Local".into(),
                base_url: "http://localhost:11434/v1".into(),
                models_dev: None,
            },
            false,
        )];
        let models = json!({"anthropic":{"api":null},"groq":{"name":"Groq","api":"https://api.groq.com/openai/v1"},
            "openrouter":{"name":"OpenRouter","api":"https://openrouter.ai/api/v1"},"nokey":{"name":"No API"}});
        let (visible, catalog) = build(&Inputs {
            providers: &providers,
            dump: &dump,
            usage: &usage,
            automatic: false,
            custom: &custom,
            models_dev: Some(&models),
        });
        let status = |id: &str| {
            visible
                .iter()
                .find(|row| row["id"] == id)
                .map(|row| row["status"].as_str().unwrap().to_owned())
        };
        assert_eq!(status("claude").as_deref(), Some("ready"));
        assert_eq!(status("openrouter").as_deref(), Some("error"));
        assert_eq!(status("cursor").as_deref(), Some("needs-setup"));
        assert_eq!(status("custom-local").as_deref(), Some("custom"));
        assert_eq!(status("zai"), None);
        let claude = visible.iter().find(|row| row["id"] == "claude").unwrap();
        assert_eq!(claude["plan"], "Claude Pro");
        assert_eq!(claude["source"], "oauth");
        assert_eq!(claude["modelsDev"], "anthropic");
        assert_eq!(
            claude["credential"],
            json!({"apiKey":false,"cookie":true,"configured":false})
        );
        assert_eq!(
            claude["windows"],
            json!([{"slot":"primary","label":"5h","windowMinutes":300,"usedPercent":22.0,"resetsAt":"2026-11-11T09:20:00Z"},
                   {"slot":"secondary","label":"Weekly","windowMinutes":10080,"usedPercent":29.5,"resetsAt":null}])
        );
        let openrouter = visible
            .iter()
            .find(|row| row["id"] == "openrouter")
            .unwrap();
        assert_eq!(openrouter["error"], "Bad key");
        assert_eq!(openrouter["credential"]["configured"], true);
        assert_eq!(openrouter["windows"], json!([]));
        let ids: Vec<_> = catalog
            .iter()
            .map(|row| row["id"].as_str().unwrap())
            .collect();
        assert_eq!(
            ids,
            ["zai", "models.dev:groq"],
            "macOS-only runtime failures stay hidden"
        );
        assert!(
            !serde_json::to_string(&visible)
                .unwrap()
                .contains("example.com")
        );
    }

    #[test]
    fn automatic_tracking_reports_every_provider_enabled() {
        let (providers, _, usage) = fixture();
        let (visible, _) = build(&Inputs {
            providers: &providers,
            dump: &[],
            usage: &usage,
            automatic: true,
            custom: &[],
            models_dev: None,
        });
        assert_eq!(visible.len(), 1);
        assert_eq!(visible[0]["enabled"], true);
        assert_eq!(visible[0]["modelsDev"], "anthropic");
    }

    #[test]
    fn custom_add_validates_url_and_unique_id() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("remya-ai.toml");
        let mut ai = Ai::new(path.clone());
        let add = |name: &str, url: &str| json!({"add":{"name":name,"baseUrl":url}}).to_string();
        ai.set_custom(&add("My Endpoint", "https://api.example.com/v1"))
            .unwrap();
        assert!(
            ai.set_custom(&add("my endpoint!", "https://other.example.com"))
                .is_err()
        );
        assert!(
            ai.set_custom(&add("Plain", "http://api.example.com"))
                .is_err()
        );
        ai.set_custom(&add("Local", "http://127.0.0.1:8080/v1"))
            .unwrap();
        assert!(
            ai.set_custom(r#"{"add":{"name":"X","baseUrl":"https://x.dev"},"remove":"custom-x"}"#)
                .is_err()
        );
        let prefs = Prefs::load(&path).unwrap();
        let ids: Vec<_> = prefs.custom.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["custom-my-endpoint", "custom-local"]);
    }

    #[test]
    fn secrets_are_validated() {
        assert!(check_secret("sk-test").is_ok());
        assert!(check_secret("").is_err());
        assert!(check_secret("a\nb").is_err());
        assert!(check_secret(&"a".repeat(MAX_SECRET + 1)).is_err());
    }

    #[test]
    fn bar_prefs_support_show_used_and_ring_order() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("remya-ai.toml");
        let mut ai = Ai::new(path.clone());
        let initial = ai.get(BAR).unwrap();
        assert_eq!(
            initial["value"],
            json!({"pinned":[],"lowPercent":20,"showUsed":false,"ringOrder":"5h-outer"})
        );
        ai.set_bar(r#"{"showUsed":true,"ringOrder":"5h-inner"}"#)
            .unwrap();
        let updated = ai.get(BAR).unwrap();
        assert_eq!(
            updated["value"],
            json!({"pinned":[],"lowPercent":20,"showUsed":true,"ringOrder":"5h-inner"})
        );
        assert!(ai.set_bar(r#"{"ringOrder":"unknown"}"#).is_err());
        assert!(ai.set_bar(r"{}").is_err());
    }
}
