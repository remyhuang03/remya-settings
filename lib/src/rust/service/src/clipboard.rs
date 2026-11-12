//! Settings API for the Launcher-owned clipboard history.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    io::{BufRead, BufReader, Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    time::Duration,
};

pub const ALL: &str = "clipboard";
const ENABLED: &str = "clipboard.history-enabled";
const MAX_ITEMS: &str = "clipboard.max-items";
const RETENTION: &str = "clipboard.retention-days";
const CLEAR: &str = "clipboard.clear-history";
pub const IDS: &[&str] = &[ENABLED, MAX_ITEMS, RETENTION, CLEAR];

const MAX_REPLY: u64 = 4096;
const TIMEOUT: Duration = Duration::from_secs(2);
const UNAVAILABLE: &str = "Unavailable:Remya Launcher’s clipboard service is unavailable.";
const BAD_REPLY: &str = "Remya Launcher returned an invalid clipboard response.";

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Preferences {
    enabled: bool,
    max_items: u32,
    retention_days: u32,
}

impl Preferences {
    fn value(self, id: &str) -> Value {
        match id {
            ENABLED => json!(self.enabled),
            MAX_ITEMS => json!(self.max_items),
            RETENTION => json!(self.retention_days),
            CLEAR => Value::Null,
            _ => json!(self),
        }
    }
}

fn request(message: Value) -> Result<Value, String> {
    let socket = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .ok_or(UNAVAILABLE)?
        .join("remya-launcher/clipboard.sock");
    let mut stream = UnixStream::connect(socket).map_err(|_| UNAVAILABLE)?;
    stream
        .set_read_timeout(Some(TIMEOUT))
        .and_then(|_| stream.set_write_timeout(Some(TIMEOUT)))
        .and_then(|_| stream.write_all(format!("{message}\n").as_bytes()))
        .map_err(|_| UNAVAILABLE)?;

    let mut reply = Vec::new();
    BufReader::new(stream.take(MAX_REPLY + 1))
        .read_until(b'\n', &mut reply)
        .map_err(|_| UNAVAILABLE)?;
    if reply.len() as u64 > MAX_REPLY || reply.last() != Some(&b'\n') {
        return Err(BAD_REPLY.into());
    }
    let mut reply: Value = serde_json::from_slice(&reply).map_err(|_| BAD_REPLY)?;
    match reply["ok"].as_bool() {
        Some(true) if reply.get("value").is_some() => Ok(reply["value"].take()),
        Some(false) if reply["error"].is_string() => {
            Err("Remya Launcher could not complete the clipboard operation.".into())
        }
        _ => Err(BAD_REPLY.into()),
    }
}

fn effective(id: &str, reply: Value) -> Result<Value, String> {
    let preferences: Preferences = serde_json::from_value(reply).map_err(|_| BAD_REPLY)?;
    if !(1..=5000).contains(&preferences.max_items)
        || !(1..=365).contains(&preferences.retention_days)
    {
        return Err(BAD_REPLY.into());
    }
    Ok(setting(id, preferences.value(id)))
}

fn setting(id: &str, value: Value) -> Value {
    json!({"id": id, "availability": "available", "value": value})
}

pub fn get(id: &str) -> Result<Value, String> {
    effective(id, request(json!({"op": "preferences"}))?)
}

fn number(value: &str, max: u32, unit: &str) -> Result<Value, String> {
    value
        .parse::<u32>()
        .ok()
        .filter(|number| (1..=max).contains(number))
        .map(|number| json!(number))
        .ok_or_else(|| format!("InvalidArgument:Enter a whole number from 1 to {max} {unit}."))
}

pub fn set(id: &str, value: &str) -> Result<Value, String> {
    let (key, value) = match id {
        ENABLED => (
            "enabled",
            json!(
                value
                    .parse::<bool>()
                    .map_err(|_| "InvalidArgument:Use true or false.")?
            ),
        ),
        MAX_ITEMS => ("maxItems", number(value, 5000, "items")?),
        RETENTION => ("retentionDays", number(value, 365, "days")?),
        CLEAR if value == "true" => {
            let reply = request(json!({"op": "clear"}))?;
            return if reply.is_null() {
                Ok(setting(id, Value::Null))
            } else {
                Err(BAD_REPLY.into())
            };
        }
        CLEAR => {
            return Err("InvalidArgument:Use true to confirm clearing Launcher history.".into());
        }
        _ => return Err("InvalidArgument:Unknown clipboard setting.".into()),
    };
    effective(
        id,
        request(json!({"op": "setPreference", "key": key, "value": value}))?,
    )
}
