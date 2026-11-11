//! models.dev provider catalog, cached as `$XDG_CACHE_HOME/remya/settings/models-dev.json`.
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

const URL: &str = "https://models.dev/api.json";
const MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Status {
    Fresh,
    Stale,
    Unavailable,
}

impl Status {
    pub fn name(self) -> &'static str {
        match self {
            Status::Fresh => "fresh",
            Status::Stale => "stale",
            Status::Unavailable => "unavailable",
        }
    }
}

/// Relative XDG values are ignored, as the XDG specification requires.
pub fn cache_path() -> Option<PathBuf> {
    let absolute = |name| {
        std::env::var_os(name)
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
    };
    absolute("XDG_CACHE_HOME")
        .or_else(|| absolute("HOME").map(|home| home.join(".cache")))
        .map(|root| root.join("remya/settings/models-dev.json"))
}

pub fn fetch() -> Result<Vec<u8>, String> {
    ureq::Agent::config_builder()
        .https_only(true)
        .timeout_global(Some(Duration::from_secs(10)))
        .build()
        .new_agent()
        .get(URL)
        .call()
        .and_then(|mut response| {
            response
                .body_mut()
                .with_config()
                .limit(64 << 20)
                .read_to_vec()
        })
        .map_err(|e| e.to_string())
}

fn parse(bytes: &[u8]) -> Option<Value> {
    serde_json::from_slice::<Value>(bytes)
        .ok()
        .filter(Value::is_object)
}

/// Serves a cache younger than 24 h, refreshes an older or missing one, and
/// falls back to the stale copy when `fetch` fails.
pub fn resolve(
    cache: Option<&Path>,
    now: SystemTime,
    fetch: impl FnOnce() -> Result<Vec<u8>, String>,
) -> (Status, Option<Value>) {
    let cached = cache.and_then(|path| {
        let modified = fs::metadata(path).and_then(|m| m.modified()).ok()?;
        Some((modified, parse(&fs::read(path).ok()?)?))
    });
    if let Some((modified, value)) = &cached
        && now.duration_since(*modified).unwrap_or_default() < MAX_AGE
    {
        return (Status::Fresh, Some(value.clone()));
    }
    if let Some(value) = fetch().ok().as_deref().and_then(|bytes| {
        let value = parse(bytes)?;
        if let Some(path) = cache
            && let Err(error) = remya_settings_display::atomic_write(path, bytes)
        {
            eprintln!("models.dev cache: {error}");
        }
        Some(value)
    }) {
        return (Status::Fresh, Some(value));
    }
    match cached {
        Some((_, value)) => (Status::Stale, Some(value)),
        None => (Status::Unavailable, None),
    }
}

pub fn provider_summary(provider: &Value) -> Value {
    json!({
        "id": provider["id"],
        "name": provider["name"],
        "doc": provider["doc"],
        "api": provider["api"],
        "env": provider["env"],
        "npm": provider["npm"],
    })
}

/// Newest models first.
pub fn models(provider: &Value) -> Vec<Value> {
    let mut models: Vec<Value> = provider["models"]
        .as_object()
        .into_iter()
        .flat_map(|models| models.values())
        .map(|model| {
            json!({
                "id": model["id"],
                "name": model["name"],
                "context": model["limit"]["context"],
                "output": model["limit"]["output"],
                "input_cost": model["cost"]["input"],
                "output_cost": model["cost"]["output"],
                "reasoning": model["reasoning"],
                "tool_call": model["tool_call"],
                "release_date": model["release_date"],
            })
        })
        .collect();
    models.sort_by(|a, b| {
        b["release_date"]
            .as_str()
            .cmp(&a["release_date"].as_str())
            .then_with(|| a["id"].as_str().cmp(&b["id"].as_str()))
    });
    models
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = r#"{"anthropic":{"id":"anthropic","name":"Anthropic","doc":"https://docs.anthropic.com","env":["ANTHROPIC_API_KEY"],"npm":"@ai-sdk/anthropic",
      "models":{"old":{"id":"old","name":"Old","release_date":"2024-01-01","limit":{"context":200000,"output":8192},"cost":{"input":3,"output":15},"reasoning":false,"tool_call":true},
                "new":{"id":"new","name":"New","release_date":"2026-01-01","limit":{"context":1000000,"output":128000},"cost":{"input":5,"output":25},"reasoning":true,"tool_call":true}}}}"#;

    #[test]
    fn parses_provider_and_models() {
        let catalog = parse(FIXTURE.as_bytes()).unwrap();
        let provider = &catalog["anthropic"];
        assert_eq!(
            provider_summary(provider)["env"],
            json!(["ANTHROPIC_API_KEY"])
        );
        assert_eq!(provider_summary(provider)["api"], Value::Null);
        let models = models(provider);
        assert_eq!(models[0]["id"], "new");
        assert_eq!(models[0]["context"], 1000000);
        assert_eq!(models[1]["input_cost"], 3);
        assert!(parse(b"[]").is_none());
    }

    #[test]
    fn cache_selection() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("remya/settings/models-dev.json");
        let now = SystemTime::now();
        let offline = || Err::<Vec<u8>, _>("offline".to_string());
        assert_eq!(resolve(Some(&path), now, offline).0, Status::Unavailable);
        assert_eq!(resolve(None, now, offline).0, Status::Unavailable);

        let (status, value) = resolve(Some(&path), now, || Ok(FIXTURE.as_bytes().to_vec()));
        assert_eq!(status, Status::Fresh);
        assert!(value.unwrap()["anthropic"].is_object());
        assert!(path.exists());

        let fresh = resolve(Some(&path), now, || panic!("fresh cache must not refetch"));
        assert_eq!(fresh.0, Status::Fresh);

        let later = now + MAX_AGE + Duration::from_secs(1);
        let (status, value) = resolve(Some(&path), later, offline);
        assert_eq!(status, Status::Stale);
        assert!(value.is_some());

        let (status, _) = resolve(Some(&path), later, || Ok(b"not json".to_vec()));
        assert_eq!(status, Status::Stale);
        assert!(
            parse(&fs::read(&path).unwrap()).is_some(),
            "invalid downloads must not replace the cache"
        );
    }
}
