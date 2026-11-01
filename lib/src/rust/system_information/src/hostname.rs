use gio::glib::{Variant, variant::ToVariant};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

pub const RENAME: &str = "about.0f142010";
const INTERFACE: &str = "org.freedesktop.hostname1";
const PATH: &str = "/org/freedesktop/hostname1";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct HostnameState {
    pub static_hostname: String,
    pub hostname: String,
}

pub fn validate_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name.len() > 63 || name.contains('.') {
        return Err("InvalidArgument:Use 1–63 lowercase letters, digits or hyphens; start and end with a letter or digit".into());
    }
    validate_static(name)
}

fn validate_static(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Ok(());
    }
    if name.len() > 64
        || !name.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
        })
    {
        return Err("InvalidArgument:Invalid static hostname".into());
    }
    Ok(())
}

fn read_from(bus: &gio::DBusConnection) -> Result<HostnameState, String> {
    let reply = bus
        .call_sync(
            Some(INTERFACE),
            PATH,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            Some(&(INTERFACE,).to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            5000,
            gio::Cancellable::NONE,
        )
        .map_err(|e| format!("Cannot read hostname: {e}"))?;
    let (properties,) = reply
        .get::<(HashMap<String, Variant>,)>()
        .ok_or("Invalid hostname properties")?;
    let property = |name| {
        properties
            .get(name)
            .and_then(|v| v.get::<String>())
            .ok_or_else(|| format!("Missing hostname property: {name}"))
    };
    let value = HostnameState {
        static_hostname: property("StaticHostname")?,
        hostname: property("Hostname")?,
    };
    validate_static(&value.static_hostname)?;
    if value.hostname.is_empty() {
        return Err("Running hostname is empty".into());
    }
    validate_static(&value.hostname)?;
    Ok(value)
}

pub fn read() -> Result<HostnameState, String> {
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    read_from(&bus)
}

fn apply_on(
    bus: &gio::DBusConnection,
    expected: &str,
    name: &str,
) -> Result<HostnameState, String> {
    validate_static(name)?;
    if read_from(bus)?.static_hostname != expected {
        return Err("Conflict:Hostname changed externally; refresh before renaming".into());
    }
    bus.call_sync(
        Some(INTERFACE),
        PATH,
        INTERFACE,
        "SetStaticHostname",
        Some(&(name, false).to_variant()),
        None,
        gio::DBusCallFlags::NONE,
        10000,
        gio::Cancellable::NONE,
    )
    .map_err(|e| format!("Cannot rename device: {e}"))?;
    let observed = read_from(bus)?;
    verify(name, &observed)?;
    Ok(observed)
}

/// Called only by the existing private authorized helper, never by an ordinary client.
pub fn apply(expected: &str, name: &str) -> Result<HostnameState, String> {
    let bus = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    apply_on(&bus, expected, name)
}

fn verify(expected: &str, state: &HostnameState) -> Result<(), String> {
    if state.static_hostname != expected || (!expected.is_empty() && state.hostname != expected) {
        return Err(
            "Hostname readback does not match the request; refresh to inspect the actual names"
                .into(),
        );
    }
    Ok(())
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u8,
    static_hostname: String,
}

type Writer = fn(&Path, &[u8]) -> Result<(), String>;

pub struct HostnameManager {
    path: PathBuf,
    writer: Writer,
    observed: Option<HostnameState>,
    saved: Option<String>,
    read_error: Option<String>,
    operation_error: Option<String>,
}
impl HostnameManager {
    pub fn new(path: PathBuf, writer: Writer) -> Self {
        Self {
            path,
            writer,
            observed: None,
            saved: None,
            read_error: None,
            operation_error: None,
        }
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        self.observe(read())
    }
    fn observe(&mut self, observed: Result<HostnameState, String>) -> Result<(), String> {
        let result = (|| {
            self.observed = Some(observed?);
            let config: Option<Config> = match fs::read_to_string(&self.path) {
                Ok(value) => Some(
                    toml::from_str(&value)
                        .map_err(|e| format!("Invalid hostname configuration: {e}"))?,
                ),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e.to_string()),
            };
            let name = if let Some(config) = config {
                if config.version != 1 {
                    return Err("Unsupported hostname configuration version".into());
                }
                validate_static(&config.static_hostname)?;
                config.static_hostname
            } else {
                let name = self.observed.as_ref().unwrap().static_hostname.clone();
                self.persist(&name)?;
                name
            };
            self.saved = Some(name);
            Ok(())
        })();
        self.read_error = result.as_ref().err().cloned();
        result
    }
    fn persist(&self, name: &str) -> Result<(), String> {
        let bytes = toml::to_string(&Config {
            version: 1,
            static_hostname: name.into(),
        })
        .map_err(|e| e.to_string())?;
        (self.writer)(&self.path, bytes.as_bytes())
    }
    pub fn conflict(&self) -> bool {
        self.saved
            .as_ref()
            .zip(self.observed.as_ref())
            .is_some_and(|(saved, actual)| *saved != actual.static_hostname)
    }
    pub fn prepare(&self, name: &str) -> Result<String, String> {
        validate_name(name)?;
        if self.conflict() {
            return Err(
                "Conflict:Resolve the saved and system hostname conflict before renaming".into(),
            );
        }
        self.expected()
    }
    pub fn expected(&self) -> Result<String, String> {
        if let Some(error) = &self.read_error {
            return Err(error.clone());
        }
        if self.saved.is_none() {
            return Err("Hostname configuration is uninitialized".into());
        }
        self.observed
            .as_ref()
            .map(|s| s.static_hostname.clone())
            .ok_or_else(|| "Hostname unavailable".into())
    }
    pub fn saved(&self) -> Result<String, String> {
        self.expected()?;
        self.saved
            .clone()
            .ok_or_else(|| "Hostname configuration is uninitialized".into())
    }
    pub fn adopt(&mut self) -> Result<(), String> {
        let actual = self.expected()?;
        let result = self.persist(&actual);
        if result.is_ok() {
            self.saved = Some(actual);
        }
        self.operation_error = result.as_ref().err().cloned();
        result
    }
    pub fn finish(
        &mut self,
        target: &str,
        result: Result<HostnameState, String>,
    ) -> Result<(), String> {
        let result = (|| {
            let state = result?;
            self.observed = Some(state.clone());
            verify(target, &state)?;
            self.persist(target)?;
            self.saved = Some(target.into());
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        result
    }
    pub fn state(&self) -> Value {
        json!({"static_hostname":self.observed.as_ref().map(|s|&s.static_hostname),"hostname":self.observed.as_ref().map(|s|&s.hostname),
            "saved_static_hostname":self.saved,"initialized":self.saved.is_some(),"writable":self.saved.is_some() && self.read_error.is_none(),"conflict":self.conflict(),"error":self.read_error.as_ref().or(self.operation_error.as_ref())})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state(name: &str) -> HostnameState {
        HostnameState {
            static_hostname: name.into(),
            hostname: name.into(),
        }
    }
    fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
        fs::write(path, bytes).map_err(|e| e.to_string())
    }
    #[test]
    fn validates_names_and_retains_failures_and_conflicts() {
        for name in [
            "",
            "UPPER",
            "two words",
            "-leading",
            "trailing-",
            "a.b",
            "中文",
            &"a".repeat(64),
        ] {
            assert!(validate_name(name).is_err(), "{name}");
        }
        for name in ["pc", "pc-42", &"a".repeat(63)] {
            assert!(validate_name(name).is_ok());
        }
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("hostname.toml");
        let mut manager = HostnameManager::new(file.clone(), write);
        assert!(manager.observe(Err("offline".into())).is_err());
        assert!(!file.exists());
        manager.observe(Ok(state("original"))).unwrap();
        assert!(!manager.conflict());
        manager
            .observe(Ok(HostnameState {
                static_hostname: "external".into(),
                hostname: "dynamic-name".into(),
            }))
            .unwrap();
        assert!(manager.conflict());
        let mut restarted = HostnameManager::new(file.clone(), write);
        restarted.observe(Ok(state("external"))).unwrap();
        assert!(restarted.conflict());
        assert_eq!(restarted.saved().unwrap(), "original");
        assert!(manager.prepare("new").is_err());
        manager.adopt().unwrap();
        assert_eq!(manager.saved().unwrap(), "external");
        manager.observe(Ok(state("another"))).unwrap();
        let saved = manager.saved().unwrap();
        manager.finish(&saved, Ok(state(&saved))).unwrap();
        assert!(!manager.conflict());
        assert!(
            manager
                .finish("new", Err("authorization canceled".into()))
                .is_err()
        );
        manager.observe(Ok(state(&saved))).unwrap();
        assert!(
            manager.state()["error"]
                .as_str()
                .unwrap()
                .contains("authorization")
        );
        assert_eq!(manager.saved().unwrap(), saved);
        assert!(manager.finish("new", Ok(state("different"))).is_err());
        assert!(manager.conflict());
        manager.writer = |_, _| Err("disk full".into());
        assert!(manager.finish("new", Ok(state("new"))).is_err());
        assert_eq!(manager.saved().unwrap(), saved);
        manager.writer = write;
        fs::write(&file, "invalid config").unwrap();
        assert!(manager.observe(Ok(state("new"))).is_err());
        assert_eq!(manager.state()["saved_static_hostname"], saved);
        assert_eq!(manager.state()["writable"], false);
    }
    #[test]
    fn private_hostnamed_verifies_writes_and_preserves_errors() {
        use std::{
            io::{BufRead, BufReader},
            process::{Command, Stdio},
            sync::{Arc, Mutex, mpsc},
            thread,
        };
        struct Daemon(std::process::Child);
        impl Drop for Daemon {
            fn drop(&mut self) {
                let _ = self.0.kill();
                let _ = self.0.wait();
            }
        }
        let mut daemon = Daemon(
            Command::new("dbus-daemon")
                .args(["--session", "--nofork", "--print-address=1"])
                .stdout(Stdio::piped())
                .spawn()
                .unwrap(),
        );
        let mut address = String::new();
        BufReader::new(daemon.0.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        let address = address.trim().to_owned();
        #[derive(Default)]
        struct Mock {
            name: String,
            deny: bool,
            ignore: bool,
            calls: usize,
        }
        let shared = Arc::new(Mutex::new(Mock {
            name: "original".into(),
            ..Default::default()
        }));
        let server = shared.clone();
        let server_address = address.clone();
        let (ready_tx, ready_rx) = mpsc::channel();
        thread::spawn(move || {
            let context = gio::glib::MainContext::new();
            context.with_thread_default(|| {
                let bus=gio::DBusConnection::for_address_sync(&server_address,gio::DBusConnectionFlags::AUTHENTICATION_CLIENT|gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,None,gio::Cancellable::NONE).unwrap();
                let xml=r#"<node><interface name="org.freedesktop.hostname1"><property name="Hostname" type="s" access="read"/><property name="StaticHostname" type="s" access="read"/><method name="SetStaticHostname"><arg type="s" direction="in"/><arg type="b" direction="in"/></method></interface></node>"#;
                let info=gio::DBusNodeInfo::for_xml(xml).unwrap().lookup_interface(INTERFACE).unwrap();
                let properties=server.clone();
                let _registration=bus.register_object(PATH,&info)
                    .property(move |_,_,_,_,_|properties.lock().unwrap().name.to_variant())
                    .method_call(move |_,_,_,_,method,args,invocation| {
                        assert_eq!(method,"SetStaticHostname"); let (name,interactive)=args.get::<(String,bool)>().unwrap(); assert!(!interactive);
                        let mut state=server.lock().unwrap(); state.calls+=1;
                        if state.deny { invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied","Authorization denied"); return; }
                        if !state.ignore { state.name=name; }
                        invocation.return_value(Some(&().to_variant()));
                    }).build().unwrap();
                bus.call_sync(Some("org.freedesktop.DBus"),"/org/freedesktop/DBus","org.freedesktop.DBus","RequestName",Some(&(INTERFACE,0u32).to_variant()),None,gio::DBusCallFlags::NONE,2000,gio::Cancellable::NONE).unwrap();
                ready_tx.send(()).unwrap();
                gio::glib::MainLoop::new(Some(&context),false).run();
            }).unwrap();
        });
        ready_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .unwrap();
        let bus = gio::DBusConnection::for_address_sync(
            &address,
            gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
                | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
            None,
            gio::Cancellable::NONE,
        )
        .unwrap();
        assert_eq!(read_from(&bus).unwrap(), state("original"));
        assert!(
            apply_on(&bus, "stale", "next")
                .unwrap_err()
                .starts_with("Conflict:")
        );
        assert_eq!(shared.lock().unwrap().calls, 0);
        assert_eq!(apply_on(&bus, "original", "next").unwrap(), state("next"));
        shared.lock().unwrap().deny = true;
        assert!(
            apply_on(&bus, "next", "denied")
                .unwrap_err()
                .contains("Authorization denied")
        );
        assert_eq!(read_from(&bus).unwrap(), state("next"));
        shared.lock().unwrap().deny = false;
        shared.lock().unwrap().ignore = true;
        assert!(
            apply_on(&bus, "next", "ignored")
                .unwrap_err()
                .contains("readback")
        );
        assert_eq!(read_from(&bus).unwrap(), state("next"));
    }
}
