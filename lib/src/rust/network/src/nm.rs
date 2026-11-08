//! NetworkManager over the system D-Bus. Passwords are written, never read back.
use crate::{Active, Backend, Change, Device, Network, NewNetwork, Profile, Security, Snapshot};
use gio::{
    SignalSubscription,
    glib::{Variant, variant::ObjectPath, variant::ToVariant},
};
use std::{collections::HashMap, process::Command, rc::Rc};

const NM: &str = "org.freedesktop.NetworkManager";
const ROOT: &str = "/org/freedesktop/NetworkManager";
const SETTINGS: &str = "/org/freedesktop/NetworkManager/Settings";
const PROPERTIES: &str = "org.freedesktop.DBus.Properties";
const CONNECTION: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const DEVICE: &str = "org.freedesktop.NetworkManager.Device";
const WIRELESS: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const ACCESS_POINT: &str = "org.freedesktop.NetworkManager.AccessPoint";
const WIFI_SETTING: &str = "802-11-wireless";
const SECURITY_SETTING: &str = "802-11-wireless-security";
/// Lets polkit ask for authorization only on explicit writes.
const WRITE_TIMEOUT_MS: i32 = 120_000;

type Props = HashMap<String, Variant>;
type Settings = HashMap<String, Props>;

pub struct RealNm;

fn bus() -> Result<gio::DBusConnection, String> {
    gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE).map_err(|e| e.to_string())
}

fn read_call(
    bus: &gio::DBusConnection,
    path: &str,
    interface: &str,
    method: &str,
    args: Option<&Variant>,
) -> Result<Variant, String> {
    // Reading state must not start a stopped NetworkManager through D-Bus activation.
    bus.call_sync(
        Some(NM),
        path,
        interface,
        method,
        args,
        None,
        gio::DBusCallFlags::NO_AUTO_START,
        5000,
        gio::Cancellable::NONE,
    )
    .map_err(|e| format!("Cannot read NetworkManager: {e}"))
}

fn write_call(
    path: &str,
    interface: &str,
    method: &str,
    args: &Variant,
) -> Result<Variant, String> {
    bus()?
        .call_sync(
            Some(NM),
            path,
            interface,
            method,
            Some(args),
            None,
            gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
            WRITE_TIMEOUT_MS,
            gio::Cancellable::NONE,
        )
        .map_err(|e| format!("NetworkManager rejected the change: {e}"))
}

/// Live radio preferences, including WWAN even when no modem is attached.
pub(crate) fn radios() -> Result<(bool, bool), String> {
    let reply = read_call(
        &bus()?,
        ROOT,
        PROPERTIES,
        "GetAll",
        Some(&(NM,).to_variant()),
    )?;
    let props = reply
        .get::<(Props,)>()
        .ok_or("Invalid NetworkManager radio state")?
        .0;
    Ok((
        number(&props, "WirelessEnabled").ok_or("Missing Wi-Fi radio state")?,
        number(&props, "WwanEnabled").ok_or("Missing WWAN radio state")?,
    ))
}

pub(crate) fn set_radio(property: &str, enabled: bool) -> Result<(), String> {
    if !["WirelessEnabled", "WwanEnabled"].contains(&property) {
        return Err("Invalid radio property".into());
    }
    write_call(
        ROOT,
        PROPERTIES,
        "Set",
        &(NM, property, enabled.to_variant()).to_variant(),
    )
    .map(drop)
}

fn object(path: &str) -> Result<ObjectPath, String> {
    ObjectPath::try_from(path.to_owned()).map_err(|_| format!("Invalid object path: {path}"))
}

fn string(props: &Props, key: &str) -> Option<String> {
    props
        .get(key)
        .and_then(|v| v.str())
        .filter(|s| !s.is_empty() && *s != "/")
        .map(str::to_owned)
}

fn number<T: gio::glib::variant::FromVariant>(props: &Props, key: &str) -> Option<T> {
    props.get(key).and_then(|v| v.get::<T>())
}

fn children(value: &Variant) -> impl Iterator<Item = Variant> + '_ {
    (0..value.n_children()).map(|i| value.child_value(i))
}

fn addresses(config: Option<&Props>, key: &str, value_key: &str, prefix: bool) -> Vec<String> {
    let Some(list) = config.and_then(|c| c.get(key)) else {
        return vec![];
    };
    children(list)
        .filter_map(|item| {
            let item = item.get::<Props>()?;
            let address = string(&item, value_key)?;
            Some(match number::<u32>(&item, "prefix").filter(|_| prefix) {
                Some(length) => format!("{address}/{length}"),
                None => address,
            })
        })
        .collect()
}

fn ipv6_dns(config: Option<&Props>) -> Vec<String> {
    let Some(list) = config.and_then(|c| c.get("Nameservers")) else {
        return vec![];
    };
    children(list)
        .filter_map(|item| <[u8; 16]>::try_from(item.get::<Vec<u8>>()?).ok())
        .map(|bytes| std::net::Ipv6Addr::from(bytes).to_string())
        .collect()
}

/// VMware and similar adapters look like Ethernet to NetworkManager; only real
/// hardware has a bus device in sysfs.
fn is_physical(props: &Props, interface: &str) -> bool {
    const IS_SOFTWARE: u32 = 4;
    number::<u32>(props, "Capabilities").unwrap_or(0) & IS_SOFTWARE == 0
        && std::path::Path::new("/sys/class/net")
            .join(interface)
            .join("device")
            .exists()
}

fn state_name(state: u32) -> &'static str {
    match state {
        10 => "unmanaged",
        20 => "unavailable",
        30 => "disconnected",
        40..=90 => "connecting",
        100 => "connected",
        110 => "disconnecting",
        120 => "failed",
        _ => "unknown",
    }
}

fn kind_name(kind: u32) -> &'static str {
    match kind {
        1 => "ethernet",
        2 => "wifi",
        5 => "bluetooth",
        8 => "modem",
        13 => "bridge",
        16 => "tun",
        29 => "wireguard",
        _ => "other",
    }
}

fn access_point(props: &Props, active: Option<&str>, path: &str) -> Option<Network> {
    let raw = props.get("Ssid")?.get::<Vec<u8>>()?;
    if raw.is_empty() {
        return None;
    }
    let frequency = number::<u32>(props, "Frequency").unwrap_or(0);
    Some(Network {
        ssid: String::from_utf8_lossy(&raw).into_owned(),
        raw,
        signal: number::<u8>(props, "Strength").unwrap_or(0),
        frequency,
        security: crate::security_of(
            number(props, "Flags").unwrap_or(0),
            number(props, "WpaFlags").unwrap_or(0),
            number(props, "RsnFlags").unwrap_or(0),
        ),
        in_use: active == Some(path),
        known_uuid: None,
    })
}

fn profile(path: &str, props: &Props, settings: &Settings) -> Option<Profile> {
    let connection = settings.get("connection")?;
    let wireless = settings.get(WIFI_SETTING)?;
    let raw = wireless.get("ssid")?.get::<Vec<u8>>()?;
    let security = settings
        .get(SECURITY_SETTING)
        .and_then(|s| string(s, "key-mgmt"));
    let flags = number::<u32>(props, "Flags").unwrap_or(0);
    Some(Profile {
        path: path.to_owned(),
        uuid: string(connection, "uuid")?,
        name: string(connection, "id")?,
        ssid: String::from_utf8_lossy(&raw).into_owned(),
        raw,
        security: crate::security_of_profile(security.as_deref()),
        autoconnect: number(connection, "autoconnect").unwrap_or(true),
        metered: match number::<i32>(connection, "metered").unwrap_or(0) {
            1 => "yes",
            2 => "no",
            _ => "automatic",
        }
        .into(),
        hidden: number(wireless, "hidden").unwrap_or(false),
        last_connected: number(connection, "timestamp").unwrap_or(0),
        active: false,
        // Unsaved and externally generated profiles.
        unsaved: flags & 1 != 0,
        read_only: flags & 8 != 0 || number(connection, "read-only").unwrap_or(false),
    })
}

fn new_settings(spec: &NewNetwork) -> Result<Settings, String> {
    let uuid = std::fs::read_to_string("/proc/sys/kernel/random/uuid")
        .map_err(|e| e.to_string())?
        .trim()
        .to_owned();
    let mut settings = Settings::new();
    settings.insert(
        "connection".into(),
        Props::from([
            ("id".to_owned(), spec.ssid_name().to_variant()),
            ("uuid".to_owned(), uuid.to_variant()),
            ("type".to_owned(), WIFI_SETTING.to_variant()),
            ("autoconnect".to_owned(), spec.autoconnect.to_variant()),
        ]),
    );
    settings.insert(
        WIFI_SETTING.into(),
        Props::from([
            ("ssid".to_owned(), spec.ssid.to_variant()),
            ("mode".to_owned(), "infrastructure".to_variant()),
            ("hidden".to_owned(), spec.hidden.to_variant()),
        ]),
    );
    if let Some(key_mgmt) = spec.security.key_mgmt() {
        let mut security = Props::from([("key-mgmt".to_owned(), key_mgmt.to_variant())]);
        if let Some(password) = &spec.password {
            security.insert("psk".into(), password.to_variant());
        }
        settings.insert(SECURITY_SETTING.into(), security);
    }
    Ok(settings)
}

impl Backend for RealNm {
    fn read(&self) -> Result<Snapshot, String> {
        let bus = bus()?;
        let reply = read_call(
            &bus,
            "/org/freedesktop",
            "org.freedesktop.DBus.ObjectManager",
            "GetManagedObjects",
            None,
        )?;
        let mut objects: HashMap<String, HashMap<String, Props>> = HashMap::new();
        for entry in children(&reply.child_value(0)) {
            let path = entry.child_value(0).str().unwrap_or_default().to_owned();
            let value = entry
                .child_value(1)
                .get::<HashMap<String, Props>>()
                .ok_or("Invalid NetworkManager object")?;
            objects.insert(path, value);
        }
        let manager = objects
            .get(ROOT)
            .and_then(|o| o.get(NM))
            .ok_or("NetworkManager object is missing")?;
        let permissions = read_call(&bus, ROOT, NM, "GetPermissions", None)?
            .get::<(HashMap<String, String>,)>()
            .ok_or("Invalid NetworkManager permissions")?
            .0;
        let config = |props: &Props, key: &str, interface: &str| {
            string(props, key).and_then(|path| objects.get(&path)?.get(interface))
        };
        let mut profiles = vec![];
        for (path, interfaces) in &objects {
            let Some(props) = interfaces.get(CONNECTION) else {
                continue;
            };
            let settings = read_call(&bus, path, CONNECTION, "GetSettings", None)?
                .get::<(Settings,)>()
                .ok_or("Invalid connection settings")?
                .0;
            if let Some(profile) = profile(path, props, &settings) {
                profiles.push(profile);
            }
        }
        let active: Vec<Active> = objects
            .iter()
            .filter_map(|(path, o)| {
                let props = o.get(ACTIVE)?;
                Some(Active {
                    path: path.clone(),
                    uuid: string(props, "Uuid")?,
                    name: string(props, "Id")?,
                    kind: string(props, "Type").unwrap_or_default(),
                    state: number(props, "State").unwrap_or(0),
                })
            })
            .collect();
        let mut devices = vec![];
        for (path, interfaces) in &objects {
            let Some(props) = interfaces.get(DEVICE) else {
                continue;
            };
            let kind = number::<u32>(props, "DeviceType").unwrap_or(0);
            // Loopback and the Wi-Fi P2P companion are not network adapters.
            if kind == 30 || kind == 32 || !number(props, "Real").unwrap_or(true) {
                continue;
            }
            let wireless = interfaces.get(WIRELESS);
            let current = wireless.and_then(|w| string(w, "ActiveAccessPoint"));
            let mut networks = vec![];
            if let Some(list) = wireless.and_then(|w| w.get("AccessPoints")) {
                for item in children(list) {
                    let ap_path = item.str().unwrap_or_default();
                    let ap = objects.get(ap_path).and_then(|o| o.get(ACCESS_POINT));
                    networks.extend(ap.and_then(|p| access_point(p, current.as_deref(), ap_path)));
                }
            }
            let active_path = string(props, "ActiveConnection");
            let connection = active
                .iter()
                .find(|a| Some(&a.path) == active_path.as_ref());
            let v4 = config(
                props,
                "Ip4Config",
                "org.freedesktop.NetworkManager.IP4Config",
            );
            let v6 = config(
                props,
                "Ip6Config",
                "org.freedesktop.NetworkManager.IP6Config",
            );
            let speed = wireless
                .and_then(|w| number::<u32>(w, "Bitrate").map(|kbit| kbit / 1000))
                .or_else(|| {
                    interfaces
                        .get("org.freedesktop.NetworkManager.Device.Wired")
                        .and_then(|w| number::<u32>(w, "Speed"))
                })
                .filter(|speed| *speed > 0);
            let mut dns = addresses(v4, "NameserverData", "address", false);
            dns.extend(ipv6_dns(v6));
            let interface = string(props, "Interface").unwrap_or_default();
            devices.push(Device {
                path: path.clone(),
                physical: is_physical(props, &interface),
                interface,
                kind: kind_name(kind).into(),
                state: state_name(number(props, "State").unwrap_or(0)).into(),
                hardware_address: string(props, "HwAddress"),
                connection: connection.map(|c| c.name.clone()),
                uuid: connection.map(|c| c.uuid.clone()),
                speed_mbps: speed,
                ipv4: addresses(v4, "AddressData", "address", true),
                gateway: v4
                    .and_then(|c| string(c, "Gateway"))
                    .or_else(|| v6.and_then(|c| string(c, "Gateway"))),
                dns,
                ipv6: addresses(v6, "AddressData", "address", true),
                networks,
            });
        }
        let primary = string(manager, "PrimaryConnection");
        let primary_uuid = primary
            .as_ref()
            .and_then(|path| objects.get(path)?.get(ACTIVE))
            .and_then(|props| string(props, "Uuid"));
        Ok(crate::finish_snapshot(Snapshot {
            connectivity: match number::<u32>(manager, "Connectivity").unwrap_or(0) {
                1 => "none",
                2 => "portal",
                3 => "limited",
                4 => "full",
                _ => "unknown",
            }
            .into(),
            connectivity_check: number(manager, "ConnectivityCheckAvailable").unwrap_or(false)
                && number(manager, "ConnectivityCheckEnabled").unwrap_or(false),
            check_uri: string(manager, "ConnectivityCheckUri"),
            wifi_enabled: number(manager, "WirelessEnabled").unwrap_or(false),
            wifi_hardware_enabled: number(manager, "WirelessHardwareEnabled").unwrap_or(false),
            primary_uuid,
            permissions: permissions.into_iter().collect(),
            devices,
            profiles,
            active,
        }))
    }

    fn set_wifi(&self, enabled: bool) -> Result<(), String> {
        write_call(
            ROOT,
            PROPERTIES,
            "Set",
            &(NM, "WirelessEnabled", enabled.to_variant()).to_variant(),
        )
        .map(drop)
    }

    fn scan(&self, device: &str) -> Result<(), String> {
        match write_call(
            device,
            WIRELESS,
            "RequestScan",
            &(Props::new(),).to_variant(),
        ) {
            // NetworkManager rate-limits scans; the previous results are still fresh.
            Err(e) if e.contains("NotAllowed") => Ok(()),
            result => result.map(drop),
        }
    }

    fn disconnect(&self, device: &str) -> Result<(), String> {
        bus()?
            .call_sync(
                Some(NM),
                device,
                DEVICE,
                "Disconnect",
                None,
                None,
                gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
                WRITE_TIMEOUT_MS,
                gio::Cancellable::NONE,
            )
            .map(drop)
            .map_err(|e| format!("NetworkManager rejected the change: {e}"))
    }

    fn activate(&self, profile: &str, device: &str) -> Result<String, String> {
        let reply = write_call(
            ROOT,
            NM,
            "ActivateConnection",
            &(object(profile)?, object(device)?, object("/")?).to_variant(),
        )?;
        Ok(reply.child_value(0).str().unwrap_or_default().to_owned())
    }

    fn add_activate(&self, spec: &NewNetwork, device: &str) -> Result<(String, String), String> {
        // Kept in memory until it works, so a wrong password leaves no broken profile.
        let options = Props::from([("persist".to_owned(), "memory".to_variant())]);
        let reply = write_call(
            ROOT,
            NM,
            "AddAndActivateConnection2",
            &(new_settings(spec)?, object(device)?, object("/")?, options).to_variant(),
        )?;
        let path = |i| reply.child_value(i).str().unwrap_or_default().to_owned();
        Ok((path(0), path(1)))
    }

    fn add(&self, spec: &NewNetwork) -> Result<(), String> {
        write_call(
            SETTINGS,
            "org.freedesktop.NetworkManager.Settings",
            "AddConnection",
            &(new_settings(spec)?,).to_variant(),
        )
        .map(drop)
    }

    fn update(&self, profile: &str, change: &Change) -> Result<(), String> {
        let bus = bus()?;
        let mut settings = read_call(&bus, profile, CONNECTION, "GetSettings", None)?
            .get::<(Settings,)>()
            .ok_or("Invalid connection settings")?
            .0;
        let (section, values): (&str, Vec<(&str, Variant)>) = match change {
            Change::Autoconnect(value) => ("connection", vec![("autoconnect", value.to_variant())]),
            Change::Metered(value) => {
                let code: i32 = match value.as_str() {
                    "yes" => 1,
                    "no" => 2,
                    _ => 0,
                };
                ("connection", vec![("metered", code.to_variant())])
            }
            // Flags 0 moves an agent-owned password into NetworkManager's own storage.
            Change::Password(value) => (
                SECURITY_SETTING,
                vec![
                    ("psk", value.to_variant()),
                    ("psk-flags", 0u32.to_variant()),
                ],
            ),
        };
        let target = settings.entry(section.into()).or_default();
        for (key, value) in values {
            target.insert(key.into(), value);
        }
        // GetSettings omits secrets; NetworkManager keeps stored ones when none are sent.
        write_call(profile, CONNECTION, "Update", &(settings,).to_variant()).map(drop)
    }

    fn forget(&self, profile: &str) -> Result<(), String> {
        bus()?
            .call_sync(
                Some(NM),
                profile,
                CONNECTION,
                "Delete",
                None,
                None,
                gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
                WRITE_TIMEOUT_MS,
                gio::Cancellable::NONE,
            )
            .map(drop)
            .map_err(|e| format!("NetworkManager rejected the change: {e}"))
    }

    fn save(&self, profile: &str) -> Result<(), String> {
        bus()?
            .call_sync(
                Some(NM),
                profile,
                CONNECTION,
                "Save",
                None,
                None,
                gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
                WRITE_TIMEOUT_MS,
                gio::Cancellable::NONE,
            )
            .map(drop)
            .map_err(|e| format!("Cannot save the network: {e}"))
    }

    fn open(&self, uri: &str) -> Result<(), String> {
        Command::new("xdg-open")
            .arg(uri)
            .spawn()
            .map(drop)
            .map_err(|e| e.to_string())
    }
}

/// Subscribes to every NetworkManager change except signal-strength and counter noise.
/// The returned subscriptions must stay alive for as long as changes are wanted.
pub fn subscribe(
    on_change: impl Fn(Option<(String, u32)>) + 'static,
) -> Result<[SignalSubscription; 2], String> {
    let bus = bus()?;
    let notify = Rc::new(on_change);
    let changes = notify.clone();
    let objects = bus.subscribe_to_signal(
        Some(NM),
        None,
        None,
        None,
        None,
        gio::DBusSignalFlags::NONE,
        move |signal| {
            if signal.interface_name == PROPERTIES {
                let source = signal.parameters.child_value(0);
                let source = source.str().unwrap_or_default();
                if source == ACCESS_POINT || source.ends_with(".Statistics") {
                    return;
                }
            }
            // A device's failure reason is only available from this signal.
            if signal.interface_name == DEVICE
                && signal.signal_name == "StateChanged"
                && let Some((120u32, _, reason)) = signal.parameters.get::<(u32, u32, u32)>()
            {
                changes(Some((signal.object_path.to_owned(), reason)));
                return;
            }
            changes(None);
        },
    );
    let owner = bus.subscribe_to_signal(
        Some("org.freedesktop.DBus"),
        Some("org.freedesktop.DBus"),
        Some("NameOwnerChanged"),
        Some("/org/freedesktop/DBus"),
        Some(NM),
        gio::DBusSignalFlags::NONE,
        move |_| notify(None),
    );
    Ok([objects, owner])
}

pub const fn security_key_mgmt(security: Security) -> Option<&'static str> {
    match security {
        Security::Wpa2 | Security::Wpa | Security::Wpa3Transition => Some("wpa-psk"),
        Security::Wpa3 => Some("sae"),
        Security::Owe => Some("owe"),
        Security::Open | Security::Enterprise | Security::Wep => None,
    }
}
