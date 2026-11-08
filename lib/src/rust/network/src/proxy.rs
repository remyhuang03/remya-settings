//! The desktop proxy in GSettings `org.gnome.system.proxy`, read by GIO, libproxy,
//! Chromium and Firefox. Proxy tools switch it routinely, so it follows live state.
use gio::prelude::*;
use serde_json::{Value, json};

pub const MODE: &str = "proxy.mode";
pub const SCRIPT: &str = "proxy.script";
pub const HTTP: &str = "proxy.http";
pub const HTTPS: &str = "proxy.https";
pub const SOCKS: &str = "proxy.socks";
pub const IGNORE: &str = "proxy.ignore";
pub const IDS: &[&str] = &[MODE, SCRIPT, HTTP, HTTPS, SOCKS, IGNORE];

const SCHEMA: &str = "org.gnome.system.proxy";

/// Opens the schema on each call: `gio::Settings` cannot move between service threads.
#[derive(Default)]
pub struct Proxy;

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

/// A host name or address without a scheme, path or whitespace.
fn valid_host(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= 253
        && !host.contains("://")
        && !host
            .chars()
            .any(|c| c.is_whitespace() || "/?#@".contains(c))
}

/// `host:port`, `[v6]:port`, or empty to clear.
fn parse_server(value: &str) -> Result<(String, i32), String> {
    if value.is_empty() {
        return Ok((String::new(), 0));
    }
    let problem = || invalid("Use host:port with a port from 1 to 65535");
    let (host, port) = value.rsplit_once(':').ok_or_else(problem)?;
    let host = host
        .strip_prefix('[')
        .and_then(|h| h.strip_suffix(']'))
        .unwrap_or(host);
    let port: u16 = port.parse().map_err(|_| problem())?;
    if port == 0 || !valid_host(host) {
        return Err(problem());
    }
    Ok((host.to_owned(), port.into()))
}

fn server(settings: &gio::Settings, protocol: &str) -> Value {
    let child = settings.child(protocol);
    let host = child.string("host");
    let port = child.int("port");
    if host.is_empty() {
        Value::Null
    } else if host.contains(':') {
        json!(format!("[{host}]:{port}"))
    } else {
        json!(format!("{host}:{port}"))
    }
}

fn open() -> Result<gio::Settings, String> {
    gio::SettingsSchemaSource::default()
        .and_then(|source| source.lookup(SCHEMA, true))
        .map(|schema| gio::Settings::new_full(&schema, None::<&gio::SettingsBackend>, None))
        .ok_or_else(|| "Unavailable:The GSettings proxy schema is not installed".into())
}

impl Proxy {
    pub fn new() -> Self {
        Self
    }

    pub fn read(&self) -> Value {
        match open() {
            Ok(settings) => read(&settings),
            Err(_) => json!({"api_version":1,"available":false,
                "error":"Install gsettings-desktop-schemas to use the desktop proxy"}),
        }
    }

    pub fn get(&self, id: &str) -> Result<Value, String> {
        let state = self.read();
        let key = id.trim_start_matches("proxy.");
        Ok(
            json!({"id":id,"availability":"available","reason":"Uses the desktop proxy in GSettings.",
            "value":state[key],"error":state["error"]}),
        )
    }

    pub fn set(&self, id: &str, value: &str) -> Result<Value, String> {
        set(&open()?, id, value)
    }
}

fn read(settings: &gio::Settings) -> Value {
    let url = settings.string("autoconfig-url");
    // GNOME's "auto" with an empty URL is WPAD detection.
    let mode = match settings.string("mode").as_str() {
        "manual" => "manual",
        "auto" if url.is_empty() => "detect",
        "auto" => "script",
        _ => "none",
    };
    json!({"api_version":1,"available":true,"error":null,"mode":mode,"script":url.as_str(),
            "http":server(settings,"http"),"https":server(settings,"https"),
            "socks":server(settings,"socks"),
            "ignore":settings.strv("ignore-hosts").iter().map(|s| s.as_str()).collect::<Vec<_>>()})
}

fn set(settings: &gio::Settings, id: &str, value: &str) -> Result<Value, String> {
    let write = |result: Result<(), gio::glib::BoolError>| {
        result.map_err(|_| "GSettings refused the proxy change".to_owned())
    };
    let expected: Value = match id {
        MODE => {
            let (mode, clear_url) = match value {
                "none" => ("none", false),
                "detect" => ("auto", true),
                "script" => {
                    if settings.string("autoconfig-url").is_empty() {
                        return Err(invalid("Enter the setup script address first"));
                    }
                    ("auto", false)
                }
                "manual" => ("manual", false),
                _ => return Err(invalid("Use none, detect, script or manual")),
            };
            if clear_url {
                write(settings.set_string("autoconfig-url", ""))?;
            }
            write(settings.set_string("mode", mode))?;
            json!(value)
        }
        SCRIPT => {
            let lower = value.to_ascii_lowercase();
            if !(lower.starts_with("http://")
                || lower.starts_with("https://")
                || lower.starts_with("file:///"))
                || value.chars().any(char::is_whitespace)
            {
                return Err(invalid("Use an http, https or file address"));
            }
            write(settings.set_string("autoconfig-url", value))?;
            write(settings.set_string("mode", "auto"))?;
            json!(value)
        }
        HTTP | HTTPS | SOCKS => {
            let (host, port) = parse_server(value)?;
            let child = settings.child(id.trim_start_matches("proxy."));
            write(child.set_string("host", &host))?;
            write(child.set_int("port", port))?;
            if value.is_empty() {
                Value::Null
            } else {
                server(settings, id.trim_start_matches("proxy."))
            }
        }
        IGNORE => {
            let hosts: Vec<String> = serde_json::from_str(value)
                .map_err(|_| invalid("Expected a list of host names"))?;
            if hosts
                .iter()
                .any(|h| h.is_empty() || h.len() > 253 || h.chars().any(char::is_whitespace))
            {
                return Err(invalid("Host names cannot be empty or contain spaces"));
            }
            let refs: Vec<&str> = hosts.iter().map(String::as_str).collect();
            write(settings.set_strv("ignore-hosts", refs.as_slice()))?;
            json!(hosts)
        }
        _ => return Err("ReadOnly:This proxy setting cannot be changed".into()),
    };
    gio::Settings::sync();
    let state = read(settings);
    if state[id.trim_start_matches("proxy.")] != expected {
        return Err("GSettings readback does not match the requested proxy value".into());
    }
    Ok(state)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Memory(gio::Settings);

    impl Memory {
        fn read(&self) -> Value {
            read(&self.0)
        }
        fn set(&self, id: &str, value: &str) -> Result<Value, String> {
            set(&self.0, id, value)
        }
    }

    fn proxy() -> Memory {
        let schema = gio::SettingsSchemaSource::default()
            .and_then(|source| source.lookup(SCHEMA, true))
            .expect("gsettings-desktop-schemas is required for these tests");
        let memory = gio::memory_settings_backend_new();
        Memory(gio::Settings::new_full(&schema, Some(&memory), None))
    }

    #[test]
    fn modes_map_to_gnome_mode_and_url() {
        let proxy = proxy();
        assert_eq!(proxy.read()["mode"], "none");
        assert!(proxy.set(MODE, "script").is_err());
        proxy.set(SCRIPT, "http://wpad.example/proxy.pac").unwrap();
        assert_eq!(proxy.read()["mode"], "script");
        proxy.set(MODE, "detect").unwrap();
        let state = proxy.read();
        assert_eq!(state["mode"], "detect");
        assert_eq!(state["script"], "");
        assert!(proxy.set(MODE, "pac").is_err());
        assert!(proxy.set(SCRIPT, "javascript:alert(1)").is_err());
    }

    #[test]
    fn servers_validate_and_clear() {
        let proxy = proxy();
        proxy.set(HTTP, "127.0.0.1:7897").unwrap();
        proxy.set(SOCKS, "[::1]:1080").unwrap();
        let state = proxy.set(MODE, "manual").unwrap();
        assert_eq!(state["http"], "127.0.0.1:7897");
        assert_eq!(state["socks"], "[::1]:1080");
        for bad in ["host", "host:0", "host:70000", "http://h:80", "a b:1"] {
            assert!(
                proxy
                    .set(HTTPS, bad)
                    .unwrap_err()
                    .starts_with("InvalidArgument:")
            );
        }
        assert_eq!(proxy.set(HTTP, "").unwrap()["http"], Value::Null);
    }

    #[test]
    fn ignore_hosts_round_trip() {
        let proxy = proxy();
        let state = proxy.set(IGNORE, r#"["localhost","10.0.0.0/8"]"#).unwrap();
        assert_eq!(state["ignore"], json!(["localhost", "10.0.0.0/8"]));
        assert!(proxy.set(IGNORE, r#"["a b"]"#).is_err());
        assert!(proxy.set(IGNORE, "nope").is_err());
    }
}
