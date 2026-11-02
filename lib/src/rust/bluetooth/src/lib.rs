//! BlueZ owns bonds and radio state. Settings only owns its temporary sessions.
mod runtime;
use gio::glib::{Variant, variant::ObjectPath};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    time::Duration,
};

pub const IDS: [&str; 12] = [
    "bluetooth.enabled",
    "bluetooth.adapter",
    "bluetooth.scan",
    "bluetooth.discoverable",
    "bluetooth.pair",
    "bluetooth.cancel",
    "bluetooth.respond",
    "bluetooth.connect",
    "bluetooth.disconnect",
    "bluetooth.forget",
    "bluetooth.devices",
    "bluetooth.information",
];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}
type Props = HashMap<String, Variant>;
type Objects = HashMap<ObjectPath, HashMap<String, Props>>;
const BLUEZ: &str = "org.bluez";
const ADAPTER: &str = "org.bluez.Adapter1";
const DEVICE: &str = "org.bluez.Device1";
const AGENT: &str = "org.bluez.Agent1";
const AGENT_PATH: &str = "/top/remya/settings/bluetooth_agent";
const PROPERTIES: &str = "org.freedesktop.DBus.Properties";
fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
fn string(props: &Props, key: &str) -> Option<String> {
    props.get(key)?.str().map(str::to_owned)
}
fn flag(props: &Props, key: &str) -> bool {
    props.get(key).and_then(|v| v.get()).unwrap_or(false)
}
fn rfkill(adapter: &str, root: &std::path::Path) -> (Option<bool>, Option<bool>) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return (None, None);
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let read = |name| {
            std::fs::read_to_string(path.join(name))
                .ok()
                .map(|s| s.trim().to_owned())
        };
        if read("type").as_deref() == Some("bluetooth") && read("name").as_deref() == Some(adapter)
        {
            let bit = |name| match read(name).as_deref() {
                Some("1") => Some(true),
                Some("0") => Some(false),
                _ => None,
            };
            return (bit("hard"), bit("soft"));
        }
    }
    (None, None)
}

fn snapshot(objects: &Objects) -> Value {
    let mut adapters = vec![];
    let mut devices = vec![];
    for (path, interfaces) in objects {
        if let Some(p) = interfaces.get(ADAPTER) {
            let (hardware_blocked, software_blocked) = rfkill(
                path.as_str().rsplit('/').next().unwrap_or_default(),
                std::path::Path::new("/sys/class/rfkill"),
            );
            adapters.push(json!({"id":path.as_str(), "address":string(p,"Address"),
                "name":string(p,"Alias").or_else(||string(p,"Name")), "powered":flag(p,"Powered"),
                "discovering":flag(p,"Discovering"), "discoverable":flag(p,"Discoverable"),
                "pairable":flag(p,"Pairable"), "hardware_blocked":hardware_blocked, "software_blocked":software_blocked}));
        }
        if let Some(p) = interfaces.get(DEVICE) {
            let battery = interfaces
                .get("org.bluez.Battery1")
                .and_then(|p| p.get("Percentage"))
                .and_then(|v| v.get::<u8>())
                .filter(|v| *v <= 100);
            devices.push(json!({"id":path.as_str(), "adapter":string(p,"Adapter"),
                "address":string(p,"Address"), "name":string(p,"Alias").or_else(||string(p,"Name")).or_else(||string(p,"Address")),
                "icon":string(p,"Icon"), "paired":flag(p,"Paired"), "bonded":flag(p,"Bonded"),
                "connected":flag(p,"Connected"), "blocked":flag(p,"Blocked"), "battery":battery}));
        }
    }
    adapters.sort_by_key(|a| a["address"].as_str().unwrap_or_default().to_owned());
    devices.sort_by_key(|d| {
        (
            !d["connected"].as_bool().unwrap_or(false),
            d["name"].as_str().unwrap_or_default().to_lowercase(),
            d["id"].to_string(),
        )
    });
    json!({"available":true,"adapters":adapters,"devices":devices})
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    adapter: Option<String>,
    device: Option<String>,
    enabled: Option<bool>,
    request: Option<u64>,
    accept: Option<bool>,
    pin: Option<String>,
    passkey: Option<u32>,
}
fn parse(value: &str) -> Result<Request, String> {
    // Do not echo malformed input: it may contain a pairing PIN.
    if value.len() > 4096 {
        return Err(invalid("Bluetooth request is too large"));
    }
    serde_json::from_str(value).map_err(|_| invalid("Expected a Bluetooth JSON request"))
}
struct Command {
    id: String,
    request: Request,
    reply: mpsc::SyncSender<Result<Value, String>>,
}
#[derive(Clone)]
pub struct Bluetooth {
    sender: mpsc::SyncSender<Command>,
    state: Arc<Mutex<Value>>,
    dirty: Arc<AtomicBool>,
}
impl Default for Bluetooth {
    fn default() -> Self {
        Self::new()
    }
}
impl Bluetooth {
    pub fn new() -> Self {
        let (sender, receiver) = mpsc::sync_channel(32);
        let state = Arc::new(Mutex::new(
            json!({"available":false,"adapters":[],"devices":[],"error":"Reading Bluetooth state"}),
        ));
        let dirty = Arc::new(AtomicBool::new(true));
        let output = state.clone();
        let changed = dirty.clone();
        std::thread::spawn(move || {
            if let Err(error) = runtime::run(receiver, output.clone(), changed.clone()) {
                output.lock().unwrap()["error"] = json!(error);
                changed.store(true, Ordering::Release);
            }
        });
        Self {
            sender,
            state,
            dirty,
        }
    }
    pub fn state(&self) -> Value {
        self.state.lock().unwrap().clone()
    }
    pub fn take_dirty(&self) -> bool {
        self.dirty.swap(false, Ordering::AcqRel)
    }
    fn send(&self, id: &str, request: Request) -> Result<Value, String> {
        let (reply, result) = mpsc::sync_channel(1);
        self.sender
            .try_send(Command {
                id: id.into(),
                request,
                reply,
            })
            .map_err(|_| "Bluetooth worker is unavailable or busy".to_owned())?;
        result
            .recv_timeout(Duration::from_secs(10))
            .map_err(|_| "Bluetooth worker did not respond".to_owned())?
    }
    pub fn read(&self) -> Result<Value, String> {
        self.send("read", Request::default())
    }
    pub fn set(&self, id: &str, value: &str) -> Result<Value, String> {
        if !is_setting(id) {
            return Err(invalid("Unknown Bluetooth setting"));
        }
        if [
            "bluetooth.adapter",
            "bluetooth.devices",
            "bluetooth.information",
        ]
        .contains(&id)
        {
            return Err(
                "ReadOnly:Adapter selection is local to each client; read bluetooth".into(),
            );
        }
        self.send(id, parse(value)?)
    }
    pub fn cleanup(&self) {
        let _ = self.send("cleanup", Request::default());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gio::glib::variant::ToVariant;
    #[test]
    fn snapshot_keeps_real_optional_values_and_orders_connected_first() {
        let mut objects = Objects::new();
        for (id, connected, battery) in [("a", false, None), ("b", true, Some(0u8))] {
            let props = HashMap::from([
                ("Alias".into(), id.to_variant()),
                ("Connected".into(), connected.to_variant()),
            ]);
            let mut interfaces = HashMap::from([(DEVICE.into(), props)]);
            if let Some(value) = battery {
                interfaces.insert(
                    "org.bluez.Battery1".into(),
                    HashMap::from([("Percentage".into(), value.to_variant())]),
                );
            }
            objects.insert(
                ObjectPath::try_from(format!("/org/bluez/{id}")).unwrap(),
                interfaces,
            );
        }
        let value = snapshot(&objects);
        assert_eq!(value["devices"][0]["name"], "b");
        assert_eq!(value["devices"][0]["battery"], 0);
        assert!(value["devices"][1]["battery"].is_null());
    }
    #[test]
    fn malformed_requests_never_echo_the_pin() {
        let error = parse(r#"{"pin":"secret-pin","unknown":true}"#)
            .err()
            .unwrap();
        assert!(!error.contains("secret-pin"));
        assert!(parse(&" ".repeat(4097)).is_err());
    }
    #[test]
    fn rfkill_distinguishes_hardware_software_and_unknown() {
        let root = std::env::temp_dir().join(format!("remya-rfkill-{}", std::process::id()));
        let entry = root.join("rfkill0");
        std::fs::create_dir_all(&entry).unwrap();
        for (name, value) in [
            ("type", "bluetooth"),
            ("name", "hci0"),
            ("hard", "1"),
            ("soft", "0"),
        ] {
            std::fs::write(entry.join(name), value).unwrap();
        }
        assert_eq!(rfkill("hci0", &root), (Some(true), Some(false)));
        assert_eq!(rfkill("hci1", &root), (None, None));
        std::fs::remove_file(entry.join("soft")).unwrap();
        assert_eq!(rfkill("hci0", &root), (Some(true), None));
        std::fs::remove_dir_all(root).unwrap();
    }
}
