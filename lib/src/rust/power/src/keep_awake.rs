use gio::glib::{Variant, variant::ToVariant};
use serde_json::{Value, json};

pub const ID: &str = "power.keep-awake";
const SERVICE: &str = "org.freedesktop.ScreenSaver";
const PATH: &str = "/org/freedesktop/ScreenSaver";
const UNAVAILABLE: &str = "Keep awake requires hypridle with D-Bus inhibition enabled.";

#[derive(Default)]
pub struct KeepAwake {
    inhibitor: Option<Inhibitor>,
}

struct Inhibitor {
    bus: gio::DBusConnection,
    owner: String,
    cookie: u32,
}

impl Drop for Inhibitor {
    fn drop(&mut self) {
        // hypridle releases any remaining cookies when this connection closes.
        let _ = self.bus.close_sync(gio::Cancellable::NONE);
    }
}

pub(super) fn owner() -> Result<Option<String>, String> {
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    let call = |method, args: &Variant| {
        bus.call_sync(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            method,
            Some(args),
            None,
            gio::DBusCallFlags::NO_AUTO_START,
            2000,
            gio::Cancellable::NONE,
        )
    };
    let reply = match call("GetNameOwner", &(SERVICE,).to_variant()) {
        Ok(reply) => reply,
        Err(e) if e.matches(gio::DBusError::NameHasNoOwner) => return Ok(None),
        Err(e) => return Err(e.to_string()),
    };
    let (name,) = reply
        .get::<(String,)>()
        .ok_or("Invalid ScreenSaver owner")?;
    let reply = match call("GetConnectionUnixProcessID", &(&name,).to_variant()) {
        Ok(reply) => reply,
        Err(e) if e.matches(gio::DBusError::NameHasNoOwner) => return Ok(None),
        Err(e) => return Err(e.to_string()),
    };
    let (pid,) = reply.get::<(u32,)>().ok_or("Invalid ScreenSaver process")?;
    let is_hypridle = std::fs::read_link(format!("/proc/{pid}/exe"))
        .is_ok_and(|path| path.file_name().is_some_and(|file| file == "hypridle"));
    Ok(is_hypridle.then_some(name))
}

fn screensaver(
    bus: &gio::DBusConnection,
    owner: &str,
    method: &str,
    args: Variant,
) -> Result<Variant, String> {
    bus.call_sync(
        Some(owner),
        PATH,
        SERVICE,
        method,
        Some(&args),
        None,
        gio::DBusCallFlags::NO_AUTO_START,
        2000,
        gio::Cancellable::NONE,
    )
    .map_err(|e| e.to_string())
}

impl KeepAwake {
    fn refresh(&mut self) -> Result<Option<String>, String> {
        let owner = owner()?;
        if self.inhibitor.as_ref().is_some_and(|lease| {
            Some(lease.owner.as_str()) != owner.as_deref() || lease.bus.is_closed()
        }) {
            self.inhibitor = None;
        }
        Ok(owner)
    }

    pub fn read(&mut self) -> Value {
        match self.refresh() {
            Ok(Some(_)) => json!({
                "id": ID, "availability": "available", "value": self.inhibitor.is_some()
            }),
            status => json!({
                "id": ID, "availability": "unavailable", "value": null,
                "error": status.err().as_deref().unwrap_or(UNAVAILABLE)
            }),
        }
    }

    pub fn set(&mut self, input: &str) -> Result<Value, String> {
        let enabled = serde_json::from_str::<bool>(input)
            .map_err(|_| "InvalidArgument:Expected a boolean")?;
        if enabled {
            let owner = self
                .refresh()?
                .ok_or_else(|| format!("Unavailable:{UNAVAILABLE}"))?;
            if self.inhibitor.is_none() {
                let address = gio::dbus_address_get_for_bus_sync(
                    gio::BusType::Session,
                    gio::Cancellable::NONE,
                )
                .map_err(|e| e.to_string())?;
                let bus = gio::DBusConnection::for_address_sync(
                    &address,
                    gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
                        | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
                    None,
                    gio::Cancellable::NONE,
                )
                .map_err(|e| e.to_string())?;
                let mut inhibitor = Inhibitor {
                    bus,
                    owner,
                    cookie: 0,
                };
                let (cookie,) = screensaver(
                    &inhibitor.bus,
                    &inhibitor.owner,
                    "Inhibit",
                    ("Remya Settings", "Keep awake").to_variant(),
                )?
                .get::<(u32,)>()
                .ok_or("Invalid hypridle inhibitor cookie")?;
                inhibitor.cookie = cookie;
                self.inhibitor = Some(inhibitor);
            }
        } else if let Some(inhibitor) = self.inhibitor.take() {
            // If hypridle exited, the cookie no longer exists.
            if owner()?.as_deref() == Some(&inhibitor.owner) {
                screensaver(
                    &inhibitor.bus,
                    &inhibitor.owner,
                    "UnInhibit",
                    (inhibitor.cookie,).to_variant(),
                )?;
            }
        }
        Ok(self.read())
    }
}
