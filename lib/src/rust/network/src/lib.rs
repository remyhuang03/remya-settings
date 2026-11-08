//! Network status, Wi-Fi, Ethernet, VPN, hotspot and saved connections through NetworkManager.
pub mod airplane;
pub mod nm;
pub mod proxy;

use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    net::{IpAddr, Ipv4Addr},
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

pub const WIFI_ENABLED: &str = "wifi.enabled";
pub const WIFI_ADAPTER: &str = "wifi.adapter";
pub const WIFI_DISCONNECT: &str = "wifi.disconnect";
pub const WIFI_REFRESH: &str = "wifi.refresh";
pub const WIFI_CONNECT: &str = "wifi.connect";
pub const ADD: &str = "known-networks.add";
pub const AUTOCONNECT: &str = "known-networks.autoconnect";
pub const METERED: &str = "known-networks.metered";
pub const PRIORITY: &str = "known-networks.priority";
pub const MAC: &str = "known-networks.mac";
pub const KNOWN_IP: &str = "known-networks.ip";
pub const KNOWN_DNS: &str = "known-networks.dns";
pub const CHANGE_PASSWORD: &str = "known-networks.change-password";
pub const FORGET: &str = "known-networks.forget";
pub const SIGN_IN: &str = "network-status.sign-in";
pub const CONNECTIVITY_CHECK: &str = "network-status.connectivity-check";
pub const ETHERNET_CONNECT: &str = "ethernet.connect";
pub const ETHERNET_AUTOCONNECT: &str = "ethernet.autoconnect";
pub const ETHERNET_METERED: &str = "ethernet.metered";
pub const ETHERNET_IP: &str = "ethernet.ip";
pub const ETHERNET_DNS: &str = "ethernet.dns";
pub const VPN_CONNECT: &str = "vpn.connect";
pub const VPN_IMPORT: &str = "vpn.import";
pub const VPN_REMOVE: &str = "vpn.remove";
pub const HOTSPOT_ENABLED: &str = "hotspot.enabled";
pub const HOTSPOT_CONFIGURE: &str = "hotspot.configure";

const PERMISSION: &str = "org.freedesktop.NetworkManager.";
const REASON_WAIT: Duration = Duration::from_secs(2);
const MAX_IMPORT_BYTES: u64 = 1 << 20;

pub fn is_network_setting(id: &str) -> bool {
    [
        "wifi.",
        "known-networks.",
        "network-status.",
        "ethernet.",
        "vpn.",
        "hotspot.",
    ]
    .iter()
    .any(|prefix| id.starts_with(prefix))
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Security {
    #[default]
    Open,
    Owe,
    Wep,
    Wpa,
    Wpa2,
    Wpa3Transition,
    Wpa3,
    Enterprise,
}

impl Security {
    fn key_mgmt(self) -> Option<&'static str> {
        nm::security_key_mgmt(self)
    }
    fn personal(self) -> bool {
        matches!(
            self,
            Self::Wpa | Self::Wpa2 | Self::Wpa3Transition | Self::Wpa3
        )
    }
    fn creatable(self) -> bool {
        !matches!(self, Self::Enterprise | Self::Wep)
    }
}

/// NM80211ApFlags and NM80211ApSecurityFlags from the access point's beacon.
pub fn security_of(flags: u32, wpa: u32, rsn: u32) -> Security {
    const PSK: u32 = 0x100;
    const EAP: u32 = 0x200;
    const SAE: u32 = 0x400;
    const OWE: u32 = 0x800;
    const OWE_TRANSITION: u32 = 0x1000;
    const SUITE_B: u32 = 0x2000;
    let all = wpa | rsn;
    if all & (EAP | SUITE_B) != 0 {
        Security::Enterprise
    } else if all & SAE != 0 && all & PSK != 0 {
        Security::Wpa3Transition
    } else if all & SAE != 0 {
        Security::Wpa3
    } else if rsn & PSK != 0 {
        Security::Wpa2
    } else if wpa & PSK != 0 {
        Security::Wpa
    } else if all & (OWE | OWE_TRANSITION) != 0 {
        Security::Owe
    } else if flags & 1 != 0 {
        Security::Wep
    } else {
        Security::Open
    }
}

pub fn security_of_profile(key_mgmt: Option<&str>) -> Security {
    match key_mgmt {
        None => Security::Open,
        Some("wpa-psk") => Security::Wpa2,
        Some("sae") => Security::Wpa3,
        Some("owe") => Security::Owe,
        Some("none") => Security::Wep,
        Some(_) => Security::Enterprise,
    }
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Network {
    pub ssid: String,
    #[serde(skip)]
    pub raw: Vec<u8>,
    pub signal: u8,
    pub frequency: u32,
    pub security: Security,
    pub in_use: bool,
    pub known_uuid: Option<String>,
}

/// Addressing and name resolution of one profile, in NetworkManager's terms.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Ip {
    /// `ipv4.method`; Settings writes `auto` or `manual`.
    pub ipv4: String,
    /// `address/prefix`.
    pub addresses: Vec<String>,
    pub gateway: String,
    /// The inverse of `ignore-auto-dns`.
    pub auto_dns: bool,
    /// IPv4 and IPv6 servers, in order.
    pub dns: Vec<String>,
    /// `ipv6.method`; Settings writes `auto` or `disabled`.
    pub ipv6: String,
    /// `default`, `no`, `opportunistic` or `yes`; applies with systemd-resolved.
    pub dns_over_tls: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Hotspot {
    pub ssid: String,
    /// `auto`, `2.4` or `5`.
    pub band: String,
}

#[derive(Clone, Debug, Default, Serialize, PartialEq)]
pub struct Profile {
    #[serde(skip)]
    pub path: String,
    pub uuid: String,
    pub name: String,
    /// `wifi`, `hotspot`, `ethernet`, `vpn` or `wireguard`.
    pub kind: String,
    pub interface: Option<String>,
    pub vpn_type: Option<String>,
    pub ssid: String,
    #[serde(skip)]
    pub raw: Vec<u8>,
    pub security: Security,
    pub autoconnect: bool,
    pub metered: String,
    pub priority: i32,
    /// `assigned-mac-address`, empty for the NetworkManager default.
    pub mac: String,
    pub ip: Ip,
    pub hotspot: Option<Hotspot>,
    pub hidden: bool,
    pub last_connected: u64,
    pub active: bool,
    pub activating: bool,
    pub read_only: bool,
    #[serde(skip)]
    pub unsaved: bool,
}

#[derive(Clone, Debug, Default, Serialize, PartialEq)]
pub struct Device {
    #[serde(skip)]
    pub path: String,
    pub interface: String,
    pub kind: String,
    pub state: String,
    pub physical: bool,
    pub hardware_address: Option<String>,
    pub connection: Option<String>,
    pub uuid: Option<String>,
    pub speed_mbps: Option<u32>,
    pub ipv4: Vec<String>,
    pub gateway: Option<String>,
    pub dns: Vec<String>,
    pub ipv6: Vec<String>,
    pub networks: Vec<Network>,
    /// Wi-Fi access point mode.
    pub ap: bool,
    /// Wi-Fi bands: `2.4` and `5`.
    pub bands: Vec<String>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Active {
    #[serde(skip)]
    pub path: String,
    pub uuid: String,
    pub name: String,
    pub kind: String,
    pub state: u32,
}

#[derive(Clone, Debug, Default, Serialize, PartialEq)]
pub struct Snapshot {
    pub connectivity: String,
    pub connectivity_check_available: bool,
    pub connectivity_check_enabled: bool,
    pub check_uri: Option<String>,
    pub wifi_enabled: bool,
    pub wifi_hardware_enabled: bool,
    /// `wpa_supplicant` or `iwd`.
    pub wifi_backend: String,
    /// NetworkManager's DNS plugin, such as `systemd-resolved` or `default`.
    pub dns_mode: String,
    pub primary_uuid: Option<String>,
    pub permissions: BTreeMap<String, String>,
    pub devices: Vec<Device>,
    pub profiles: Vec<Profile>,
    pub active: Vec<Active>,
}

/// Merges access points per network, links saved profiles and fixes display order.
pub fn finish_snapshot(mut snapshot: Snapshot) -> Snapshot {
    for profile in &mut snapshot.profiles {
        let states = snapshot.active.iter().filter(|a| a.uuid == profile.uuid);
        profile.active = states.clone().next().is_some();
        profile.activating = states.into_iter().any(|a| a.state == 1);
    }
    snapshot.profiles.sort_by(|a, b| {
        (b.active, b.last_connected, &a.name).cmp(&(a.active, a.last_connected, &b.name))
    });
    let profiles = snapshot.profiles.clone();
    for device in &mut snapshot.devices {
        device.networks.sort_by_key(|n| (!n.in_use, 255 - n.signal));
        let mut merged: Vec<Network> = vec![];
        for mut network in std::mem::take(&mut device.networks) {
            if merged
                .iter()
                .any(|n| n.raw == network.raw && n.security == network.security)
            {
                continue;
            }
            network.known_uuid = profiles
                .iter()
                .find(|p| p.kind == "wifi" && p.raw == network.raw && !p.unsaved)
                .map(|p| p.uuid.clone());
            merged.push(network);
        }
        device.networks = merged;
    }
    snapshot
        .devices
        .sort_by(|a, b| (!a.physical, &a.interface).cmp(&(!b.physical, &b.interface)));
    snapshot
}

pub struct NewNetwork {
    pub ssid: Vec<u8>,
    pub security: Security,
    pub password: Option<String>,
    pub hidden: bool,
    pub autoconnect: bool,
    /// An access point on this band instead of a client profile.
    pub hotspot_band: Option<String>,
}

impl NewNetwork {
    fn ssid_name(&self) -> String {
        String::from_utf8_lossy(&self.ssid).into_owned()
    }
}

/// The stable preferences of one profile, saved for reconciliation.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub autoconnect: bool,
    pub metered: String,
    pub priority: i32,
    pub mac: String,
    pub ip: Ip,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hotspot: Option<Hotspot>,
}

impl From<&Profile> for Prefs {
    fn from(p: &Profile) -> Self {
        Self {
            autoconnect: p.autoconnect,
            metered: p.metered.clone(),
            priority: p.priority,
            mac: p.mac.clone(),
            ip: p.ip.clone(),
            hotspot: p.hotspot.clone(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum Change {
    Prefs(Prefs),
    Password(String),
}

pub trait Backend: Send {
    fn read(&self) -> Result<Snapshot, String>;
    fn set_wifi(&self, enabled: bool) -> Result<(), String>;
    fn set_connectivity_check(&self, enabled: bool) -> Result<(), String>;
    fn scan(&self, device: &str) -> Result<(), String>;
    fn disconnect(&self, device: &str) -> Result<(), String>;
    /// `profile` or `device` may be `/` to let NetworkManager choose.
    fn activate(&self, profile: &str, device: &str) -> Result<String, String>;
    fn deactivate(&self, active: &str) -> Result<(), String>;
    /// Applies the profile's saved addressing to the device without reconnecting.
    fn reapply(&self, device: &str) -> Result<(), String>;
    /// Returns the profile and active connection paths.
    fn add_activate(&self, spec: &NewNetwork, device: &str) -> Result<(String, String), String>;
    fn add(&self, spec: &NewNetwork) -> Result<(), String>;
    /// Imports a VPN file of a NetworkManager import type.
    fn import(&self, kind: &str, path: &Path) -> Result<(), String>;
    fn update(&self, profile: &str, change: &Change) -> Result<(), String>;
    fn forget(&self, profile: &str) -> Result<(), String>;
    fn save(&self, profile: &str) -> Result<(), String>;
    fn open(&self, uri: &str) -> Result<(), String>;
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u8,
    connectivity_check: bool,
    profiles: BTreeMap<String, Prefs>,
}

const CONFIG_VERSION: u8 = 2;

struct Pending {
    active: String,
    profile: String,
    ssid: String,
    uuid: Option<String>,
    new_profile: bool,
    device: String,
    reason: Option<u32>,
    started: Instant,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ConnectRequest {
    ssid: Option<String>,
    uuid: Option<String>,
    password: Option<String>,
    hidden_security: Option<Security>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AddRequest {
    ssid: String,
    security: Security,
    password: Option<String>,
    #[serde(default)]
    hidden: bool,
    #[serde(default = "enabled")]
    autoconnect: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct HotspotRequest {
    ssid: String,
    band: String,
    password: Option<String>,
}

fn enabled() -> bool {
    true
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

fn validate_password(security: Security, password: Option<&str>) -> Result<(), String> {
    if !security.personal() {
        return if password.is_some() {
            Err(invalid("This network does not use a password"))
        } else {
            Ok(())
        };
    }
    let password = password.ok_or_else(|| invalid("Enter the network password"))?;
    let hex = password.len() == 64 && password.bytes().all(|b| b.is_ascii_hexdigit());
    if !hex && !(8..=63).contains(&password.len()) {
        return Err(invalid("Use 8 to 63 characters for the password"));
    }
    Ok(())
}

fn validate_ssid(ssid: &str) -> Result<(), String> {
    if ssid.is_empty() || ssid.len() > 32 {
        return Err(invalid("Use 1 to 32 bytes for the network name"));
    }
    Ok(())
}

/// Settings edits automatic and manual IPv4 and automatic or disabled IPv6; other
/// methods set elsewhere may be kept as they are.
fn validate_ip(current: &Ip, ip: &Ip) -> Result<(), String> {
    if !["auto", "manual"].contains(&ip.ipv4.as_str()) && ip.ipv4 != current.ipv4 {
        return Err(invalid("Use automatic or manual IPv4 addressing"));
    }
    for address in &ip.addresses {
        let valid = address.split_once('/').is_some_and(|(addr, prefix)| {
            addr.parse::<Ipv4Addr>().is_ok()
                && prefix.parse::<u8>().is_ok_and(|p| (1..=32).contains(&p))
        });
        if !valid {
            return Err(invalid(
                "Use an IPv4 address with a prefix length from 1 to 32",
            ));
        }
    }
    if ip.ipv4 == "manual" && ip.addresses.is_empty() {
        return Err(invalid("Manual IPv4 needs an address"));
    }
    if !ip.gateway.is_empty() && ip.gateway.parse::<Ipv4Addr>().is_err() {
        return Err(invalid("Use an IPv4 address for the gateway"));
    }
    if ip
        .dns
        .iter()
        .any(|server| server.parse::<IpAddr>().is_err())
    {
        return Err(invalid("Use IPv4 or IPv6 addresses for DNS servers"));
    }
    if !ip.auto_dns && ip.dns.is_empty() {
        return Err(invalid("Manual DNS needs at least one server"));
    }
    if !["auto", "disabled"].contains(&ip.ipv6.as_str()) && ip.ipv6 != current.ipv6 {
        return Err(invalid("Use automatic or disabled IPv6"));
    }
    if !["default", "no", "opportunistic", "yes"].contains(&ip.dns_over_tls.as_str()) {
        return Err(invalid(
            "Use default, no, opportunistic or yes for DNS over TLS",
        ));
    }
    Ok(())
}

pub struct Manager<B> {
    backend: B,
    path: PathBuf,
    saved: Option<Config>,
    snapshot: Option<Snapshot>,
    read_error: Option<String>,
    config_error: Option<String>,
    failure: Option<Value>,
    pending: Option<Pending>,
    tunnel: Option<Pending>,
    selected: Option<String>,
}

pub type NetworkManager = Manager<nm::RealNm>;

impl NetworkManager {
    pub fn real(path: PathBuf) -> Self {
        Self::new(nm::RealNm, path)
    }
}

impl<B: Backend> Manager<B> {
    pub fn new(backend: B, path: PathBuf) -> Self {
        Self {
            backend,
            path,
            saved: None,
            snapshot: None,
            read_error: None,
            config_error: None,
            failure: None,
            pending: None,
            tunnel: None,
            selected: None,
        }
    }

    fn persist(&self, config: &Config) -> Result<(), String> {
        let bytes = toml::to_string(config).map_err(|e| e.to_string())?;
        atomic_write(&self.path, bytes.as_bytes())
    }

    fn observed(snapshot: &Snapshot) -> Config {
        Config {
            version: CONFIG_VERSION,
            connectivity_check: snapshot.connectivity_check_enabled,
            profiles: snapshot
                .profiles
                .iter()
                .filter(|p| !p.unsaved)
                .map(|p| (p.uuid.clone(), p.into()))
                .collect(),
        }
    }

    fn load_saved(&mut self, observed: &Config) -> Result<(), String> {
        if self.saved.is_some() {
            return Ok(());
        }
        match fs::read_to_string(&self.path) {
            Ok(text) => {
                let invalid = |e: toml::de::Error| format!("Invalid network configuration: {e}");
                let raw: toml::Table = toml::from_str(&text).map_err(invalid)?;
                if raw.get("version").and_then(toml::Value::as_integer)
                    != Some(CONFIG_VERSION.into())
                {
                    return Err(
                        "The saved network configuration is from another Settings version".into(),
                    );
                }
                self.saved = Some(toml::from_str(&text).map_err(invalid)?);
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                self.persist(observed)?;
                self.saved = Some(observed.clone());
            }
            Err(e) => return Err(e.to_string()),
        }
        Ok(())
    }

    /// Profile inventory belongs to NetworkManager: a saved entry cannot recreate
    /// a deleted profile without its secrets, so additions and removals are adopted.
    fn adopt_inventory(&mut self, observed: &Config) -> Result<(), String> {
        let Some(saved) = &mut self.saved else {
            return Ok(());
        };
        let before = saved.profiles.len();
        saved
            .profiles
            .retain(|uuid, _| observed.profiles.contains_key(uuid));
        let mut changed = saved.profiles.len() != before;
        for (uuid, prefs) in &observed.profiles {
            if !saved.profiles.contains_key(uuid) {
                saved.profiles.insert(uuid.clone(), prefs.clone());
                changed = true;
            }
        }
        if changed {
            let copy = saved.clone();
            return self.persist(&copy);
        }
        Ok(())
    }

    fn settle(&mut self, tunnel: bool) {
        let Some(snapshot) = &self.snapshot else {
            return;
        };
        let slot = if tunnel { &self.tunnel } else { &self.pending };
        let Some(pending) = slot else {
            return;
        };
        let state = snapshot
            .active
            .iter()
            .find(|a| a.path == pending.active)
            .map(|a| a.state);
        // Still activating, or ended with its failure reason still on the way: a
        // reader's refresh can overtake the debounced device signal.
        if state == Some(1)
            || (state != Some(2)
                && pending.reason.is_none()
                && pending.started.elapsed() < REASON_WAIT)
        {
            return;
        }
        let pending = if tunnel {
            self.tunnel.take()
        } else {
            self.pending.take()
        }
        .unwrap();
        if state == Some(2) {
            if pending.new_profile
                && let Err(error) = self.backend.save(&pending.profile)
            {
                self.failure = Some(
                    json!({"message":error,"ssid":pending.ssid,"uuid":null,"needs_password":false}),
                );
            }
            return;
        }
        if pending.new_profile {
            let _ = self.backend.forget(&pending.profile);
        }
        // NM_DEVICE_STATE_REASON no-secrets and supplicant-disconnect.
        let needs_password = !tunnel && matches!(pending.reason, Some(7 | 8));
        let message = match pending.reason {
            Some(7 | 8) if !tunnel => {
                format!("Could not connect to {}: check the password", pending.ssid)
            }
            Some(11) => format!("Connecting to {} timed out", pending.ssid),
            _ => format!("Could not connect to {}", pending.ssid),
        };
        self.failure = Some(
            json!({"message":message,"ssid":pending.ssid,"uuid":pending.uuid,"needs_password":needs_password}),
        );
    }

    /// The failure reason of a device, reported by its state signal.
    pub fn device_failed(&mut self, device: &str, reason: u32) {
        if let Some(pending) = &mut self.pending
            && pending.device == device
        {
            pending.reason = Some(reason);
        }
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let snapshot = match self.backend.read() {
            Ok(snapshot) => snapshot,
            Err(error) => {
                self.snapshot = None;
                self.read_error = Some(error.clone());
                return Err(error);
            }
        };
        self.read_error = None;
        let observed = Self::observed(&snapshot);
        self.snapshot = Some(snapshot);
        let result = self
            .load_saved(&observed)
            .and_then(|()| self.adopt_inventory(&observed));
        self.config_error = result.err();
        self.settle(false);
        self.settle(true);
        Ok(())
    }

    fn snapshot(&self) -> Result<&Snapshot, String> {
        self.snapshot.as_ref().ok_or_else(|| {
            self.read_error
                .clone()
                .unwrap_or_else(|| "NetworkManager is unavailable".into())
        })
    }

    fn adapter(&self) -> Option<&Device> {
        let wifi = || {
            self.snapshot
                .iter()
                .flat_map(|s| &s.devices)
                .filter(|d| d.kind == "wifi")
        };
        wifi()
            .find(|d| Some(&d.interface) == self.selected.as_ref())
            .or_else(|| wifi().find(|d| d.state == "connected"))
            .or_else(|| wifi().next())
    }

    fn require_adapter(&self) -> Result<Device, String> {
        self.snapshot()?;
        self.adapter()
            .cloned()
            .ok_or_else(|| "Unavailable:No Wi-Fi adapter was detected".to_owned())
    }

    fn allowed(&self, permission: &str, action: &str) -> Result<(), String> {
        let key = format!("{PERMISSION}{permission}");
        if self.snapshot()?.permissions.get(&key).map(String::as_str) == Some("no") {
            return Err(format!(
                "Unavailable:You are not allowed to {action} on this system"
            ));
        }
        Ok(())
    }

    fn conflicts(&self) -> Vec<Value> {
        let (Some(saved), Some(snapshot)) = (&self.saved, &self.snapshot) else {
            return vec![];
        };
        let mut result = vec![];
        if saved.connectivity_check != snapshot.connectivity_check_enabled {
            result.push(json!({"uuid":null,"name":"Internet connectivity check",
                "saved":saved.connectivity_check,"system":snapshot.connectivity_check_enabled}));
        }
        for profile in &snapshot.profiles {
            let Some(prefs) = saved.profiles.get(&profile.uuid) else {
                continue;
            };
            let actual = Prefs::from(profile);
            if *prefs != actual {
                result.push(
                    json!({"uuid":profile.uuid,"name":profile.name,"saved":prefs,"system":actual}),
                );
            }
        }
        result
    }

    pub fn conflict(&self) -> bool {
        !self.conflicts().is_empty()
    }

    fn writable(&self) -> bool {
        self.saved.is_some() && self.read_error.is_none() && self.config_error.is_none()
    }

    /// Preference writes need a valid saved configuration that agrees with the system.
    fn guard_preferences(&mut self) -> Result<(), String> {
        self.refresh()?;
        if !self.writable() {
            return Err("Network configuration is not writable".into());
        }
        if self.conflict() {
            return Err(
                "Conflict:Resolve the saved and system network conflict before changing it".into(),
            );
        }
        Ok(())
    }

    fn profile(&self, uuid: &str) -> Result<Profile, String> {
        self.snapshot()?
            .profiles
            .iter()
            .find(|p| p.uuid == uuid)
            .cloned()
            .ok_or_else(|| invalid("Unknown connection"))
    }

    fn hotspot_profile(&self) -> Option<Profile> {
        self.snapshot()
            .ok()?
            .profiles
            .iter()
            .find(|p| p.kind == "hotspot")
            .cloned()
    }

    fn active_of(&self, uuid: &str) -> Option<Active> {
        self.snapshot()
            .ok()?
            .active
            .iter()
            .find(|a| a.uuid == uuid)
            .cloned()
    }

    pub fn state(&self) -> Value {
        let mut value = self
            .snapshot
            .as_ref()
            .map_or_else(|| json!({}), |s| serde_json::to_value(s).unwrap());
        if let (Some(pending), Some(list)) = (
            &self.pending,
            value.get_mut("profiles").and_then(Value::as_array_mut),
        ) {
            // A profile on trial appears only once it has connected.
            if pending.new_profile {
                let path_uuid = self.snapshot.as_ref().and_then(|s| {
                    s.profiles
                        .iter()
                        .find(|p| p.path == pending.profile)
                        .map(|p| p.uuid.clone())
                });
                list.retain(|p| p["uuid"].as_str() != path_uuid.as_deref());
            }
        }
        value["api_version"] = json!(1);
        value["available"] = json!(self.snapshot.is_some());
        value["initialized"] = json!(self.saved.is_some());
        value["writable"] = json!(self.writable());
        let conflicts = self.conflicts();
        value["conflict"] = json!(!conflicts.is_empty());
        value["conflicts"] = json!(conflicts);
        value["config_invalid"] = json!(self.read_error.is_none() && self.config_error.is_some());
        value["error"] = json!(self.read_error.as_ref().or(self.config_error.as_ref()));
        value["failure"] = json!(self.failure);
        value["connecting"] = json!(self.pending.as_ref().map(|p| &p.ssid));
        value["adapter"] = json!(self.adapter().map(|d| &d.interface));
        value
    }

    /// Byte counters of the active adapter since it came up; clients derive speeds.
    pub fn traffic(&self) -> Value {
        let interface = self.snapshot.as_ref().and_then(|s| {
            s.devices
                .iter()
                .find(|d| d.uuid.is_some() && d.uuid == s.primary_uuid)
                .map(|d| d.interface.clone())
        });
        let counter = |name: &str| {
            let path = format!("/sys/class/net/{}/statistics/{name}", interface.as_deref()?);
            fs::read_to_string(path).ok()?.trim().parse::<u64>().ok()
        };
        json!({"interface":interface,"rx_bytes":counter("rx_bytes"),"tx_bytes":counter("tx_bytes")})
    }

    /// `Get(<control-id>)` value for a readable control.
    pub fn read_value(&self, id: &str) -> Value {
        let state = self.state();
        let primary = self.snapshot.as_ref().and_then(|s| {
            s.devices
                .iter()
                .find(|d| d.uuid.is_some() && d.uuid == s.primary_uuid)
        });
        let primary_field = |field: fn(&Device) -> Value| primary.map_or(Value::Null, field);
        let filter = |key: &str, keep: &dyn Fn(&Value) -> bool| {
            json!(
                state[key]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|v| keep(v))
                    .collect::<Vec<_>>()
            )
        };
        match id {
            "network-status.connection" => state["connectivity"].clone(),
            "network-status.traffic" | "network-status.usage" => self.traffic(),
            "network-status.name" => primary_field(|d| json!(d.connection)),
            "network-status.type" => primary_field(|d| json!(d.kind)),
            "network-status.ipv4" => primary_field(|d| json!(d.ipv4)),
            "network-status.gateway" => primary_field(|d| json!(d.gateway)),
            "network-status.dns" => primary_field(|d| json!(d.dns)),
            "network-status.ipv6" => primary_field(|d| json!(d.ipv6)),
            "network-status.link-speed" => primary_field(|d| json!(d.speed_mbps)),
            "network-status.hardware-address" => primary_field(|d| json!(d.hardware_address)),
            "network-status.adapters" | "network-status.virtual-adapters" => {
                let physical = id == "network-status.adapters";
                filter("devices", &|d| d["physical"] == physical)
            }
            CONNECTIVITY_CHECK => state["connectivity_check_enabled"].clone(),
            WIFI_ENABLED => state["wifi_enabled"].clone(),
            WIFI_ADAPTER => state["adapter"].clone(),
            "wifi.current" => json!(
                self.adapter()
                    .and_then(|d| d.networks.iter().find(|n| n.in_use))
            ),
            "wifi.networks" => json!(self.adapter().map(|d| &d.networks)),
            "ethernet.status" | "ethernet.details" => filter("devices", &|d| {
                d["kind"] == "ethernet" && d["physical"] == true
            }),
            "vpn.connections" => filter("profiles", &|p| {
                p["kind"] == "vpn" || p["kind"] == "wireguard"
            }),
            "vpn.external" => filter("devices", &|d| {
                ["tun", "wireguard"].contains(&d["kind"].as_str().unwrap_or_default())
                    && d["state"] == "unmanaged"
            }),
            HOTSPOT_ENABLED => json!(self.hotspot_profile().is_some_and(|p| p.active)),
            "hotspot.name" | "hotspot.band" => {
                json!(self.hotspot_profile().and_then(|p| p.hotspot))
            }
            "hotspot.source" => primary_field(|d| json!(d.connection)),
            _ => Value::Null,
        }
    }

    /// Writes one profile's preferences, verifies readback and saves them.
    fn change_profile(&mut self, uuid: &str, prefs: Prefs) -> Result<Value, String> {
        self.guard_preferences()?;
        self.allowed("settings.modify.system", "change saved connections")?;
        let profile = self.profile(uuid)?;
        if profile.read_only {
            return Err("Unavailable:This saved connection is read-only".into());
        }
        let ip_changed = prefs.ip != profile.ip;
        self.backend
            .update(&profile.path, &Change::Prefs(prefs.clone()))?;
        self.refresh()?;
        let after = self.profile(uuid)?;
        if Prefs::from(&after) != prefs {
            return Err("NetworkManager readback does not match the requested value".into());
        }
        let saved = self.saved.as_mut().ok_or("Network configuration missing")?;
        saved.profiles.insert(uuid.to_owned(), prefs);
        let copy = saved.clone();
        self.persist(&copy)?;
        if ip_changed {
            self.reapply(uuid)?;
        }
        Ok(self.state())
    }

    /// Applies new addressing to a connected device; the profile is already saved.
    fn reapply(&mut self, uuid: &str) -> Result<(), String> {
        let device = self
            .snapshot()?
            .devices
            .iter()
            .find(|d| d.uuid.as_deref() == Some(uuid))
            .map(|d| d.path.clone());
        if let Some(device) = device {
            self.backend
                .reapply(&device)
                .map_err(|e| format!("Saved; reconnect to apply it: {e}"))?;
            self.refresh()?;
        }
        Ok(())
    }

    fn begin_connect(&mut self, request: ConnectRequest) -> Result<(), String> {
        self.refresh()?;
        let adapter = self.require_adapter()?;
        if !self.snapshot()?.wifi_enabled {
            return Err("Unavailable:Wi-Fi is turned off".into());
        }
        self.allowed("network-control", "change network connections")?;
        let network = request
            .ssid
            .as_ref()
            .and_then(|ssid| adapter.networks.iter().find(|n| &n.ssid == ssid));
        let hidden = request.hidden_security.is_some();
        let uuid = request.uuid.or_else(|| {
            if hidden {
                let ssid = request.ssid.as_deref()?.as_bytes();
                self.snapshot()
                    .ok()?
                    .profiles
                    .iter()
                    .find(|profile| profile.kind == "wifi" && profile.raw == ssid)
                    .map(|profile| profile.uuid.clone())
            } else {
                network.and_then(|network| network.known_uuid.clone())
            }
        });
        if let Some(uuid) = uuid {
            let profile = self.profile(&uuid)?;
            if profile.kind != "wifi" {
                return Err(invalid("This connection is not a Wi-Fi network"));
            }
            if request
                .hidden_security
                .is_some_and(|security| security != profile.security)
            {
                return Err(invalid("The saved network uses a different security type"));
            }
            if let Some(password) = &request.password {
                if !profile.security.personal() {
                    return Err(invalid("This network cannot use a password here"));
                }
                validate_password(profile.security, Some(password))?;
                self.backend
                    .update(&profile.path, &Change::Password(password.clone()))?;
            }
            let active = self.backend.activate(&profile.path, &adapter.path)?;
            self.drop_trial();
            self.pending = Some(Pending {
                active,
                profile: profile.path,
                ssid: profile.ssid,
                uuid: Some(uuid),
                new_profile: false,
                device: adapter.path,
                reason: None,
                started: Instant::now(),
            });
            return Ok(());
        }
        let (ssid, raw, security) = if let Some(security) = request.hidden_security {
            let ssid = request
                .ssid
                .as_deref()
                .ok_or_else(|| invalid("Hidden networks require an SSID"))?;
            validate_ssid(ssid)?;
            (ssid, ssid.as_bytes(), security)
        } else {
            let network = network.ok_or_else(|| invalid("Network not found; refresh the list"))?;
            (
                network.ssid.as_str(),
                network.raw.as_slice(),
                network.security,
            )
        };
        if !security.creatable() {
            return Err("Unavailable:Settings cannot create this type of network".into());
        }
        validate_password(security, request.password.as_deref())?;
        let ssid = ssid.to_owned();
        let spec = NewNetwork {
            ssid: raw.to_owned(),
            security,
            password: request.password,
            hidden,
            autoconnect: true,
            hotspot_band: None,
        };
        let (profile, active) = self.backend.add_activate(&spec, &adapter.path)?;
        self.drop_trial();
        self.pending = Some(Pending {
            active,
            profile,
            ssid,
            uuid: None,
            new_profile: true,
            device: adapter.path,
            reason: None,
            started: Instant::now(),
        });
        Ok(())
    }

    /// A newer attempt replaces an unconfirmed profile.
    fn drop_trial(&mut self) {
        if let Some(previous) = self.pending.take()
            && previous.new_profile
        {
            let _ = self.backend.forget(&previous.profile);
        }
    }

    fn profile_request<T: serde::de::DeserializeOwned>(
        value: &str,
        message: &str,
    ) -> Result<(String, T), String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request<T> {
            uuid: String,
            value: T,
        }
        // Messages from the parser could quote a password.
        let request: Request<T> = serde_json::from_str(value).map_err(|_| invalid(message))?;
        Ok((request.uuid, request.value))
    }

    /// Changes one preference of a saved connection of one of `kinds`.
    fn edit(
        &mut self,
        value: &str,
        kinds: &[&str],
        apply: impl FnOnce(&Profile, &Snapshot, &mut Prefs, Value) -> Result<(), String>,
    ) -> Result<Value, String> {
        let (uuid, requested): (String, Value) =
            Self::profile_request(value, "Expected uuid and value")?;
        self.refresh()?;
        let profile = self.profile(&uuid)?;
        if !kinds.contains(&profile.kind.as_str()) {
            return Err(invalid("This setting does not apply to this connection"));
        }
        let mut prefs = Prefs::from(&profile);
        apply(&profile, self.snapshot()?, &mut prefs, requested)?;
        self.change_profile(&uuid, prefs)
    }

    fn set_tunnel(&mut self, value: &str) -> Result<(), String> {
        let (uuid, connect): (String, bool) =
            Self::profile_request(value, "Expected uuid and true or false")?;
        self.refresh()?;
        let profile = self.profile(&uuid)?;
        if !["vpn", "wireguard"].contains(&profile.kind.as_str()) {
            return Err(invalid("This connection is not a VPN"));
        }
        self.allowed("network-control", "change network connections")?;
        if connect {
            let active = self.backend.activate(&profile.path, "/")?;
            self.tunnel = Some(Pending {
                active,
                profile: profile.path,
                ssid: profile.name,
                uuid: Some(uuid),
                new_profile: false,
                device: "/".into(),
                reason: None,
                started: Instant::now(),
            });
        } else if let Some(active) = self.active_of(&uuid) {
            self.tunnel = None;
            self.backend.deactivate(&active.path)?;
        }
        Ok(())
    }

    /// Imports through `nmcli`; the new VPN stays disconnected until it is chosen.
    fn import(&mut self, value: &str) -> Result<(), String> {
        let path = Path::new(value);
        let kind = match path.extension().and_then(|e| e.to_str()) {
            Some("conf") => "wireguard",
            Some("ovpn") => "openvpn",
            _ => return Err(invalid("Choose a WireGuard .conf or OpenVPN .ovpn file")),
        };
        let metadata = fs::metadata(path).map_err(|_| invalid("Choose an existing file"))?;
        if !path.is_absolute() || !metadata.is_file() || metadata.len() > MAX_IMPORT_BYTES {
            return Err(invalid(
                "Choose a VPN file of at most 1 MiB by its full path",
            ));
        }
        self.refresh()?;
        self.allowed("settings.modify.system", "add VPN connections")?;
        let before: Vec<String> = self
            .snapshot()?
            .profiles
            .iter()
            .map(|p| p.uuid.clone())
            .collect();
        self.backend.import(kind, path)?;
        self.refresh()?;
        let added: Vec<Profile> = self
            .snapshot()?
            .profiles
            .iter()
            .filter(|p| {
                !before.contains(&p.uuid) && ["vpn", "wireguard"].contains(&p.kind.as_str())
            })
            .cloned()
            .collect();
        if added.is_empty() {
            return Err("NetworkManager did not add the VPN".into());
        }
        for profile in added {
            if let Some(active) = self.active_of(&profile.uuid) {
                self.backend.deactivate(&active.path)?;
            }
            if profile.autoconnect {
                let mut prefs = Prefs::from(&profile);
                prefs.autoconnect = false;
                self.backend.update(&profile.path, &Change::Prefs(prefs))?;
            }
        }
        // Inventory adoption records the new profiles as they now are.
        if let Some(saved) = &mut self.saved {
            saved.profiles.retain(|uuid, _| before.contains(uuid));
        }
        self.refresh()
    }

    fn set_hotspot(&mut self, enabled: bool) -> Result<(), String> {
        self.refresh()?;
        let adapter = self.require_adapter()?;
        let profile = self
            .hotspot_profile()
            .ok_or("Unavailable:Set up the hotspot name and password first")?;
        self.allowed("network-control", "change network connections")?;
        if !enabled {
            if let Some(active) = self.active_of(&profile.uuid) {
                self.backend.deactivate(&active.path)?;
            }
            return Ok(());
        }
        if !adapter.ap {
            return Err("Unavailable:This Wi-Fi adapter cannot share a hotspot".into());
        }
        if !self.snapshot()?.wifi_enabled {
            return Err("Unavailable:Wi-Fi is turned off".into());
        }
        let active = self.backend.activate(&profile.path, &adapter.path)?;
        self.tunnel = Some(Pending {
            active,
            profile: profile.path,
            ssid: profile.name,
            uuid: Some(profile.uuid),
            new_profile: false,
            device: adapter.path,
            reason: None,
            started: Instant::now(),
        });
        Ok(())
    }

    fn configure_hotspot(&mut self, value: &str) -> Result<Value, String> {
        // Messages from the parser could quote the password.
        let request: HotspotRequest = serde_json::from_str(value)
            .map_err(|_| invalid("Expected ssid, band and an optional password"))?;
        validate_ssid(&request.ssid)?;
        if !["auto", "2.4", "5"].contains(&request.band.as_str()) {
            return Err(invalid("Use auto, 2.4 or 5 for the band"));
        }
        if let Some(password) = &request.password {
            validate_password(Security::Wpa2, Some(password))?;
        }
        self.guard_preferences()?;
        let adapter = self.require_adapter()?;
        if !adapter.ap {
            return Err("Unavailable:This Wi-Fi adapter cannot share a hotspot".into());
        }
        if request.band != "auto" && !adapter.bands.contains(&request.band) {
            return Err(invalid("This Wi-Fi adapter does not support that band"));
        }
        self.allowed("settings.modify.system", "change saved connections")?;
        let hotspot = Hotspot {
            ssid: request.ssid.clone(),
            band: request.band,
        };
        let Some(profile) = self.hotspot_profile() else {
            if request.password.is_none() {
                return Err(invalid("Enter a hotspot password"));
            }
            self.backend.add(&NewNetwork {
                ssid: request.ssid.into_bytes(),
                security: Security::Wpa2,
                password: request.password,
                hidden: false,
                autoconnect: false,
                hotspot_band: Some(hotspot.band),
            })?;
            self.refresh()?;
            if self.hotspot_profile().is_none() {
                return Err("NetworkManager did not save the hotspot".into());
            }
            return Ok(self.state());
        };
        if let Some(password) = request.password {
            self.backend
                .update(&profile.path, &Change::Password(password))?;
        }
        let mut prefs = Prefs::from(&profile);
        prefs.hotspot = Some(hotspot);
        let state = self.change_profile(&profile.uuid, prefs)?;
        // A running access point picks up its new name, band or password on restart.
        if profile.active {
            self.backend.activate(&profile.path, &adapter.path)?;
            self.refresh()?;
            return Ok(self.state());
        }
        Ok(state)
    }

    pub fn set(&mut self, key: &str, value: &str) -> Result<Value, String> {
        self.failure = None;
        let flag = || match value {
            "true" => Ok(true),
            "false" => Ok(false),
            _ => Err(invalid("Expected true or false")),
        };
        match key {
            WIFI_ENABLED => {
                let enabled = flag()?;
                self.refresh()?;
                if !self.snapshot()?.wifi_hardware_enabled {
                    return Err("Unavailable:Wi-Fi is blocked by a hardware switch".into());
                }
                self.allowed("enable-disable-wifi", "turn Wi-Fi on or off")?;
                self.backend.set_wifi(enabled)?;
                self.refresh()?;
                if self.snapshot()?.wifi_enabled != enabled {
                    return Err("NetworkManager readback does not match the requested value".into());
                }
            }
            CONNECTIVITY_CHECK => {
                let enabled = flag()?;
                self.guard_preferences()?;
                if !self.snapshot()?.connectivity_check_available {
                    return Err(
                        "Unavailable:NetworkManager has no connectivity check address".into(),
                    );
                }
                self.allowed(
                    "enable-disable-connectivity-check",
                    "change connectivity checking",
                )?;
                self.backend.set_connectivity_check(enabled)?;
                self.refresh()?;
                if self.snapshot()?.connectivity_check_enabled != enabled {
                    return Err("NetworkManager readback does not match the requested value".into());
                }
                let saved = self.saved.as_mut().ok_or("Network configuration missing")?;
                saved.connectivity_check = enabled;
                let copy = saved.clone();
                self.persist(&copy)?;
            }
            WIFI_ADAPTER => {
                self.refresh()?;
                let known = self
                    .snapshot()?
                    .devices
                    .iter()
                    .any(|d| d.kind == "wifi" && d.interface == value);
                if !known {
                    return Err(invalid("Choose a detected Wi-Fi adapter"));
                }
                self.selected = Some(value.to_owned());
            }
            WIFI_DISCONNECT => {
                self.refresh()?;
                let adapter = self.require_adapter()?;
                self.allowed("network-control", "change network connections")?;
                self.backend.disconnect(&adapter.path)?;
                self.refresh()?;
            }
            WIFI_REFRESH => {
                self.refresh()?;
                let adapter = self.require_adapter()?;
                if !self.snapshot()?.wifi_enabled {
                    return Err("Unavailable:Wi-Fi is turned off".into());
                }
                self.allowed("wifi.scan", "scan for networks")?;
                self.backend.scan(&adapter.path)?;
            }
            WIFI_CONNECT => {
                // Messages from the parser could quote the password.
                let request: ConnectRequest = serde_json::from_str(value)
                    .map_err(|_| invalid("Expected ssid or uuid, and an optional password"))?;
                if request.ssid.is_some() == request.uuid.is_some()
                    || (request.hidden_security.is_some() && request.ssid.is_none())
                {
                    return Err(invalid("Provide either ssid or uuid"));
                }
                self.begin_connect(request)?;
                self.refresh()?;
            }
            ADD => {
                let request: AddRequest = serde_json::from_str(value)
                    .map_err(|_| invalid("Expected ssid, security, and an optional password"))?;
                validate_ssid(&request.ssid)?;
                if !request.security.creatable() {
                    return Err("Unavailable:Settings cannot create this type of network".into());
                }
                validate_password(request.security, request.password.as_deref())?;
                self.refresh()?;
                self.allowed("settings.modify.system", "change saved networks")?;
                let ssid = request.ssid.into_bytes();
                let saved =
                    |s: &Snapshot| s.profiles.iter().any(|p| p.kind == "wifi" && p.raw == ssid);
                if saved(self.snapshot()?) {
                    return Err(invalid("This network is already saved"));
                }
                self.backend.add(&NewNetwork {
                    ssid: ssid.clone(),
                    security: request.security,
                    password: request.password,
                    hidden: request.hidden,
                    autoconnect: request.autoconnect,
                    hotspot_band: None,
                })?;
                self.refresh()?;
                if !saved(self.snapshot()?) {
                    return Err("NetworkManager did not save the network".into());
                }
            }
            AUTOCONNECT | ETHERNET_AUTOCONNECT => {
                let kinds: &[&str] = if key == AUTOCONNECT {
                    &["wifi"]
                } else {
                    &["ethernet"]
                };
                return self.edit(value, kinds, |_, _, prefs, v| {
                    prefs.autoconnect = v
                        .as_bool()
                        .ok_or_else(|| invalid("Expected true or false"))?;
                    Ok(())
                });
            }
            METERED | ETHERNET_METERED => {
                let kinds: &[&str] = if key == METERED {
                    &["wifi"]
                } else {
                    &["ethernet"]
                };
                return self.edit(value, kinds, |_, _, prefs, v| {
                    let v = v.as_str().unwrap_or_default();
                    if !["automatic", "yes", "no"].contains(&v) {
                        return Err(invalid("Use automatic, yes or no"));
                    }
                    prefs.metered = v.to_owned();
                    Ok(())
                });
            }
            PRIORITY => {
                return self.edit(value, &["wifi"], |_, snapshot, prefs, v| {
                    if snapshot.wifi_backend == "iwd" {
                        return Err("Unavailable:iwd chooses networks itself".into());
                    }
                    prefs.priority = v
                        .as_i64()
                        .filter(|p| (-999..=999).contains(p))
                        .ok_or_else(|| invalid("Use a priority from -999 to 999"))?
                        as i32;
                    Ok(())
                });
            }
            MAC => {
                return self.edit(value, &["wifi"], |profile, snapshot, prefs, v| {
                    if snapshot.wifi_backend == "iwd" {
                        return Err("Unavailable:iwd randomizes addresses itself".into());
                    }
                    let v = v.as_str().unwrap_or("-");
                    if !["", "permanent", "stable", "random"].contains(&v) && v != profile.mac {
                        return Err(invalid("Use default, permanent, stable or random"));
                    }
                    prefs.mac = v.to_owned();
                    Ok(())
                });
            }
            KNOWN_IP | KNOWN_DNS | ETHERNET_IP | ETHERNET_DNS => {
                let kinds: &[&str] = if key.starts_with("known-") {
                    &["wifi"]
                } else {
                    &["ethernet"]
                };
                return self.edit(value, kinds, |profile, _, prefs, v| {
                    let ip: Ip = serde_json::from_value(v)
                        .map_err(|_| invalid("Expected ipv4, addresses, gateway, auto_dns, dns, ipv6 and dns_over_tls"))?;
                    validate_ip(&profile.ip, &ip)?;
                    prefs.ip = ip;
                    Ok(())
                });
            }
            CHANGE_PASSWORD => {
                let (uuid, password): (String, String) =
                    Self::profile_request(value, "Expected uuid and value")?;
                self.guard_preferences()?;
                self.allowed("settings.modify.system", "change saved networks")?;
                let profile = self.profile(&uuid)?;
                if !profile.security.personal() || profile.kind != "wifi" {
                    return Err(
                        "Unavailable:Settings changes personal network passwords only".into(),
                    );
                }
                if profile.read_only {
                    return Err("Unavailable:This saved connection is read-only".into());
                }
                validate_password(profile.security, Some(&password))?;
                self.backend
                    .update(&profile.path, &Change::Password(password))?;
                self.refresh()?;
            }
            FORGET | VPN_REMOVE => {
                self.refresh()?;
                self.allowed("settings.modify.system", "change saved connections")?;
                let profile = self.profile(value)?;
                let tunnel = ["vpn", "wireguard"].contains(&profile.kind.as_str());
                if (key == VPN_REMOVE) != tunnel {
                    return Err(invalid("Use the matching page to remove this connection"));
                }
                if profile.read_only {
                    return Err("Unavailable:This saved connection is read-only".into());
                }
                self.backend.forget(&profile.path)?;
                self.refresh()?;
                if self.snapshot()?.profiles.iter().any(|p| p.uuid == value) {
                    return Err("NetworkManager did not remove the connection".into());
                }
            }
            ETHERNET_CONNECT => {
                #[derive(Deserialize)]
                #[serde(deny_unknown_fields)]
                struct Request {
                    interface: String,
                    value: bool,
                }
                let request: Request = serde_json::from_str(value)
                    .map_err(|_| invalid("Expected interface and true or false"))?;
                self.refresh()?;
                let device = self
                    .snapshot()?
                    .devices
                    .iter()
                    .find(|d| {
                        d.kind == "ethernet" && d.physical && d.interface == request.interface
                    })
                    .cloned()
                    .ok_or_else(|| invalid("Choose a detected Ethernet adapter"))?;
                self.allowed("network-control", "change network connections")?;
                if request.value {
                    if device.state == "unavailable" {
                        return Err("Unavailable:Plug in a network cable first".into());
                    }
                    self.backend.activate("/", &device.path)?;
                } else {
                    self.backend.disconnect(&device.path)?;
                }
                self.refresh()?;
            }
            VPN_CONNECT => {
                self.set_tunnel(value)?;
                self.refresh()?;
            }
            VPN_IMPORT => self.import(value)?,
            HOTSPOT_ENABLED => {
                self.set_hotspot(flag()?)?;
                self.refresh()?;
            }
            HOTSPOT_CONFIGURE => return self.configure_hotspot(value),
            SIGN_IN => {
                self.refresh()?;
                let snapshot = self.snapshot()?;
                if snapshot.connectivity != "portal" {
                    return Err("Unavailable:This network does not need a sign-in".into());
                }
                let uri = snapshot
                    .check_uri
                    .clone()
                    .filter(|uri| uri.starts_with("http://") || uri.starts_with("https://"))
                    .ok_or("Unavailable:NetworkManager has no sign-in address")?;
                self.backend.open(&uri)?;
            }
            _ => return Err("ReadOnly:This network setting cannot be changed".into()),
        }
        Ok(self.state())
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let _ = self.refresh();
        self.snapshot()?;
        match source {
            // Also replaces an unreadable file, by the user's explicit choice.
            "system" => {
                let observed = Self::observed(self.snapshot()?);
                self.persist(&observed)?;
                self.saved = Some(observed);
                self.config_error = None;
            }
            "settings" => {
                if !self.writable() {
                    return Err("Network configuration is not writable".into());
                }
                self.allowed("settings.modify.system", "change saved connections")?;
                let saved = self.saved.clone().ok_or("Network configuration missing")?;
                if saved.connectivity_check != self.snapshot()?.connectivity_check_enabled {
                    self.backend
                        .set_connectivity_check(saved.connectivity_check)?;
                }
                let mut reapply = vec![];
                for profile in self.snapshot()?.profiles.clone() {
                    let Some(prefs) = saved.profiles.get(&profile.uuid) else {
                        continue;
                    };
                    if *prefs != Prefs::from(&profile) {
                        self.backend
                            .update(&profile.path, &Change::Prefs(prefs.clone()))?;
                        if prefs.ip != profile.ip {
                            reapply.push(profile.uuid);
                        }
                    }
                }
                self.refresh()?;
                if self.conflict() {
                    return Err("NetworkManager readback does not match the saved values".into());
                }
                for uuid in reapply {
                    self.reapply(&uuid)?;
                }
            }
            _ => return Err(invalid("Unknown resolution")),
        }
        Ok(self.state())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct World {
        snapshot: Snapshot,
        read_error: Option<String>,
        calls: Vec<String>,
        reject: bool,
        ignore_updates: bool,
    }

    #[derive(Clone, Default)]
    struct Fake(Arc<Mutex<World>>);

    fn ip() -> Ip {
        Ip {
            ipv4: "auto".into(),
            auto_dns: true,
            ipv6: "auto".into(),
            dns_over_tls: "default".into(),
            ..Default::default()
        }
    }

    fn profile(uuid: &str, ssid: &str, security: Security) -> Profile {
        Profile {
            path: format!("/c/{uuid}"),
            uuid: uuid.into(),
            name: ssid.into(),
            kind: "wifi".into(),
            ssid: ssid.into(),
            raw: ssid.into(),
            security,
            autoconnect: true,
            metered: "automatic".into(),
            ip: ip(),
            ..Default::default()
        }
    }

    fn network(ssid: &str, security: Security, signal: u8) -> Network {
        Network {
            ssid: ssid.into(),
            raw: ssid.into(),
            signal,
            frequency: 2412,
            security,
            in_use: false,
            known_uuid: None,
        }
    }

    fn adapter(interface: &str, networks: Vec<Network>) -> Device {
        Device {
            path: format!("/d/{interface}"),
            interface: interface.into(),
            kind: "wifi".into(),
            state: "disconnected".into(),
            physical: true,
            networks,
            ap: true,
            bands: vec!["2.4".into(), "5".into()],
            ..Default::default()
        }
    }

    impl Backend for Fake {
        fn read(&self) -> Result<Snapshot, String> {
            let world = self.0.lock().unwrap();
            match &world.read_error {
                Some(error) => Err(error.clone()),
                None => Ok(finish_snapshot(world.snapshot.clone())),
            }
        }
        fn set_wifi(&self, enabled: bool) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("wifi {enabled}"));
            if world.reject {
                return Err("rejected".into());
            }
            world.snapshot.wifi_enabled = enabled;
            Ok(())
        }
        fn set_connectivity_check(&self, enabled: bool) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("check {enabled}"));
            world.snapshot.connectivity_check_enabled = enabled;
            Ok(())
        }
        fn deactivate(&self, active: &str) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("deactivate {active}"));
            world.snapshot.active.retain(|a| a.path != active);
            Ok(())
        }
        fn reapply(&self, device: &str) -> Result<(), String> {
            self.0
                .lock()
                .unwrap()
                .calls
                .push(format!("reapply {device}"));
            Ok(())
        }
        fn import(&self, kind: &str, _: &Path) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("import {kind}"));
            let mut vpn = profile("wg", "wg0", Security::Open);
            vpn.kind = "wireguard".into();
            world.snapshot.profiles.push(vpn);
            world.snapshot.active.push(Active {
                path: "/a/wg".into(),
                uuid: "wg".into(),
                name: "wg0".into(),
                kind: "wireguard".into(),
                state: 2,
            });
            Ok(())
        }
        fn scan(&self, device: &str) -> Result<(), String> {
            self.0.lock().unwrap().calls.push(format!("scan {device}"));
            Ok(())
        }
        fn disconnect(&self, device: &str) -> Result<(), String> {
            self.0
                .lock()
                .unwrap()
                .calls
                .push(format!("disconnect {device}"));
            Ok(())
        }
        fn activate(&self, profile: &str, device: &str) -> Result<String, String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("activate {profile} {device}"));
            world.snapshot.active.push(Active {
                path: "/a/1".into(),
                uuid: profile.trim_start_matches("/c/").into(),
                name: "x".into(),
                kind: "wifi".into(),
                state: 1,
            });
            Ok("/a/1".into())
        }
        fn add_activate(&self, spec: &NewNetwork, _: &str) -> Result<(String, String), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!(
                "add-activate {} {:?}",
                spec.ssid_name(),
                spec.password
            ));
            let mut new = profile("new", &spec.ssid_name(), spec.security);
            new.unsaved = true;
            new.hidden = spec.hidden;
            world.snapshot.profiles.push(new);
            world.snapshot.active.push(Active {
                path: "/a/1".into(),
                uuid: "new".into(),
                name: "x".into(),
                kind: "wifi".into(),
                state: 1,
            });
            Ok(("/c/new".into(), "/a/1".into()))
        }
        fn add(&self, spec: &NewNetwork) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("add {}", spec.ssid_name()));
            let mut added = profile("added", &spec.ssid_name(), spec.security);
            if let Some(band) = &spec.hotspot_band {
                added.kind = "hotspot".into();
                added.autoconnect = spec.autoconnect;
                added.hotspot = Some(Hotspot {
                    ssid: spec.ssid_name(),
                    band: band.clone(),
                });
            }
            world.snapshot.profiles.push(added);
            Ok(())
        }
        fn update(&self, path: &str, change: &Change) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("update {path} {change:?}"));
            if world.reject {
                return Err("rejected".into());
            }
            if world.ignore_updates {
                return Ok(());
            }
            let target = world
                .snapshot
                .profiles
                .iter_mut()
                .find(|p| p.path == path)
                .unwrap();
            if let Change::Prefs(prefs) = change {
                target.autoconnect = prefs.autoconnect;
                target.metered = prefs.metered.clone();
                target.priority = prefs.priority;
                target.mac = prefs.mac.clone();
                target.ip = prefs.ip.clone();
                target.hotspot = prefs.hotspot.clone();
            }
            Ok(())
        }
        fn forget(&self, path: &str) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("forget {path}"));
            world.snapshot.profiles.retain(|p| p.path != path);
            Ok(())
        }
        fn save(&self, path: &str) -> Result<(), String> {
            let mut world = self.0.lock().unwrap();
            world.calls.push(format!("save {path}"));
            for p in world
                .snapshot
                .profiles
                .iter_mut()
                .filter(|p| p.path == path)
            {
                p.unsaved = false;
            }
            Ok(())
        }
        fn open(&self, uri: &str) -> Result<(), String> {
            self.0.lock().unwrap().calls.push(format!("open {uri}"));
            Ok(())
        }
    }

    fn setup() -> (Fake, Manager<Fake>, tempfile::TempDir) {
        let fake = Fake::default();
        {
            let mut world = fake.0.lock().unwrap();
            world.snapshot.wifi_enabled = true;
            world.snapshot.wifi_hardware_enabled = true;
            world.snapshot.connectivity = "full".into();
            world.snapshot.profiles = vec![profile("home", "Home", Security::Wpa2)];
            world.snapshot.devices = vec![adapter(
                "wlan0",
                vec![
                    network("Home", Security::Wpa2, 50),
                    network("Cafe", Security::Wpa2, 40),
                    network("Open", Security::Open, 30),
                    network("Corp", Security::Enterprise, 20),
                    network("Old", Security::Wep, 10),
                ],
            )];
        }
        let root = tempfile::tempdir().unwrap();
        let manager = Manager::new(fake.clone(), root.path().join("network.toml"));
        (fake, manager, root)
    }

    fn calls(fake: &Fake) -> Vec<String> {
        fake.0.lock().unwrap().calls.clone()
    }

    #[test]
    fn traffic_has_no_counters_without_a_primary_connection() {
        let (_fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        let traffic = manager.traffic();
        assert_eq!(traffic["interface"], Value::Null);
        assert_eq!(traffic["rx_bytes"], Value::Null);
    }

    #[test]
    fn security_comes_from_access_point_flags() {
        assert_eq!(security_of(0, 0, 0), Security::Open);
        assert_eq!(security_of(1, 0, 0), Security::Wep);
        assert_eq!(security_of(1, 0x100, 0), Security::Wpa);
        assert_eq!(security_of(1, 0x100, 0x100), Security::Wpa2);
        assert_eq!(security_of(1, 0, 0x500), Security::Wpa3Transition);
        assert_eq!(security_of(1, 0, 0x400), Security::Wpa3);
        assert_eq!(security_of(1, 0, 0x200), Security::Enterprise);
        assert_eq!(security_of(0, 0, 0x800), Security::Owe);
    }

    #[test]
    fn access_points_merge_and_link_saved_profiles() {
        let mut snapshot = Snapshot {
            profiles: vec![profile("home", "Home", Security::Wpa2)],
            devices: vec![adapter(
                "wlan0",
                vec![
                    network("Home", Security::Wpa2, 40),
                    network("Home", Security::Wpa2, 80),
                    network("Cafe", Security::Open, 90),
                ],
            )],
            ..Default::default()
        };
        snapshot = finish_snapshot(snapshot);
        let networks = &snapshot.devices[0].networks;
        assert_eq!(networks.len(), 2);
        assert_eq!(networks[0].ssid, "Cafe");
        assert_eq!(networks[1].signal, 80);
        assert_eq!(networks[1].known_uuid.as_deref(), Some("home"));
    }

    #[test]
    fn first_use_snapshots_system_without_writes_and_failure_stays_uninitialized() {
        let (fake, mut manager, root) = setup();
        fake.0.lock().unwrap().read_error = Some("no daemon".into());
        assert!(manager.refresh().is_err());
        let state = manager.state();
        assert_eq!(state["initialized"], false);
        assert_eq!(state["error"], "no daemon");
        assert_eq!(state["available"], false);
        assert!(!root.path().join("network.toml").exists());

        fake.0.lock().unwrap().read_error = None;
        manager.refresh().unwrap();
        assert_eq!(manager.state()["initialized"], true);
        assert!(root.path().join("network.toml").exists());
        assert!(calls(&fake).is_empty());
    }

    #[test]
    fn conflicts_preserve_values_and_resolve_both_ways() {
        let (fake, mut manager, root) = setup();
        manager.refresh().unwrap();
        fake.0.lock().unwrap().snapshot.profiles[0].autoconnect = false;
        manager.refresh().unwrap();
        let state = manager.state();
        assert_eq!(state["conflict"], true);
        assert_eq!(state["conflicts"][0]["saved"]["autoconnect"], true);
        assert_eq!(state["conflicts"][0]["system"]["autoconnect"], false);
        assert!(
            manager
                .set(METERED, r#"{"uuid":"home","value":"yes"}"#)
                .unwrap_err()
                .starts_with("Conflict:")
        );
        assert!(calls(&fake).is_empty());

        manager.resolve("settings").unwrap();
        assert!(fake.0.lock().unwrap().snapshot.profiles[0].autoconnect);
        assert_eq!(manager.state()["conflict"], false);

        fake.0.lock().unwrap().snapshot.profiles[0].metered = "yes".into();
        manager.refresh().unwrap();
        manager.resolve("system").unwrap();
        assert_eq!(manager.state()["conflict"], false);
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(text.contains("metered = \"yes\""));
    }

    #[test]
    fn failed_resolution_retains_the_conflict() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        fake.0.lock().unwrap().snapshot.profiles[0].autoconnect = false;
        manager.refresh().unwrap();
        fake.0.lock().unwrap().reject = true;
        assert!(manager.resolve("settings").is_err());
        assert_eq!(manager.state()["conflict"], true);
        fake.0.lock().unwrap().reject = false;
        fake.0.lock().unwrap().ignore_updates = true;
        assert!(manager.resolve("settings").is_err());
        assert_eq!(manager.state()["conflict"], true);
    }

    #[test]
    fn inventory_changes_are_adopted_not_conflicts() {
        let (fake, mut manager, root) = setup();
        manager.refresh().unwrap();
        fake.0
            .lock()
            .unwrap()
            .snapshot
            .profiles
            .push(profile("cafe", "Cafe", Security::Wpa2));
        manager.refresh().unwrap();
        assert_eq!(manager.state()["conflict"], false);
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(text.contains("cafe"));
        fake.0.lock().unwrap().snapshot.profiles.clear();
        manager.refresh().unwrap();
        assert_eq!(manager.state()["conflict"], false);
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(!text.contains("home"));
    }

    #[test]
    fn invalid_configuration_is_kept_and_blocks_writes() {
        let (fake, mut manager, root) = setup();
        fs::write(root.path().join("network.toml"), "not toml [").unwrap();
        manager.refresh().unwrap();
        assert_eq!(manager.state()["writable"], false);
        assert!(
            manager.state()["error"]
                .as_str()
                .unwrap()
                .contains("Invalid")
        );
        assert!(
            manager
                .set(AUTOCONNECT, r#"{"uuid":"home","value":false}"#)
                .is_err()
        );
        assert_eq!(
            fs::read_to_string(root.path().join("network.toml")).unwrap(),
            "not toml ["
        );
        assert!(calls(&fake).is_empty());
    }

    #[test]
    fn preference_write_verifies_readback_and_persists() {
        let (fake, mut manager, root) = setup();
        manager.refresh().unwrap();
        manager
            .set(METERED, r#"{"uuid":"home","value":"no"}"#)
            .unwrap();
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(text.contains("metered = \"no\""));

        fake.0.lock().unwrap().ignore_updates = true;
        assert!(
            manager
                .set(AUTOCONNECT, r#"{"uuid":"home","value":false}"#)
                .unwrap_err()
                .contains("readback")
        );
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(text.contains("autoconnect = true"));
        assert!(
            manager
                .set(METERED, r#"{"uuid":"home","value":"maybe"}"#)
                .is_err()
        );
    }

    #[test]
    fn new_network_is_saved_only_after_it_connects() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        let request = r#"{"ssid":"Cafe","password":"correct-horse"}"#;
        let state = manager.set(WIFI_CONNECT, request).unwrap();
        assert_eq!(state["connecting"], "Cafe");
        assert!(
            !state["profiles"]
                .as_array()
                .unwrap()
                .iter()
                .any(|p| p["uuid"] == "new")
        );
        fake.0.lock().unwrap().snapshot.active[0].state = 2;
        manager.refresh().unwrap();
        assert!(calls(&fake).contains(&"save /c/new".to_owned()));
        assert_eq!(manager.state()["connecting"], Value::Null);
        assert!(
            !serde_json::to_string(&manager.state())
                .unwrap()
                .contains("correct-horse")
        );
    }

    #[test]
    fn hidden_network_activates_without_scan_result_and_saves_only_after_connection() {
        let (fake, mut manager, _root) = setup();
        let state = manager
            .set(
                WIFI_CONNECT,
                r#"{"ssid":"Hidden Lab","hidden_security":"wpa2","password":"correct-horse"}"#,
            )
            .unwrap();
        assert_eq!(state["connecting"], "Hidden Lab");
        {
            let mut world = fake.0.lock().unwrap();
            let trial = world
                .snapshot
                .profiles
                .iter()
                .find(|profile| profile.uuid == "new")
                .unwrap();
            assert!(trial.hidden && trial.unsaved);
            world.snapshot.active[0].state = 2;
        }
        manager.refresh().unwrap();
        assert!(calls(&fake).contains(&"save /c/new".to_owned()));
        assert!(
            manager
                .set(WIFI_CONNECT, r#"{"uuid":"home","hidden_security":"open"}"#)
                .is_err()
        );
    }

    #[test]
    fn wrong_password_removes_the_trial_profile_and_asks_again() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        manager
            .set(
                WIFI_CONNECT,
                r#"{"ssid":"Cafe","password":"wrong-password"}"#,
            )
            .unwrap();
        manager.device_failed("/d/wlan0", 7);
        fake.0.lock().unwrap().snapshot.active.clear();
        manager.refresh().unwrap();
        assert!(calls(&fake).contains(&"forget /c/new".to_owned()));
        let state = manager.state();
        assert_eq!(state["failure"]["needs_password"], true);
        assert_eq!(state["failure"]["ssid"], "Cafe");
        assert!(!state.to_string().contains("wrong-password"));
    }

    #[test]
    fn known_network_activates_its_profile_and_password_updates_it() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        manager.set(WIFI_CONNECT, r#"{"ssid":"Home"}"#).unwrap();
        assert!(calls(&fake).contains(&"activate /c/home /d/wlan0".to_owned()));
        fake.0.lock().unwrap().snapshot.active.clear();
        manager.device_failed("/d/wlan0", 7);
        manager.refresh().unwrap();
        let failure = manager.state()["failure"].clone();
        assert_eq!(failure["uuid"], "home");
        assert_eq!(failure["needs_password"], true);
        assert!(!calls(&fake).contains(&"forget /c/home".to_owned()));
        manager
            .set(WIFI_CONNECT, r#"{"uuid":"home","password":"new-password"}"#)
            .unwrap();
        assert!(
            calls(&fake)
                .iter()
                .any(|c| c.starts_with("update /c/home Password"))
        );
        assert_eq!(manager.state()["failure"], Value::Null);
    }

    #[test]
    fn enterprise_and_wep_cannot_be_created_and_passwords_are_validated() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        for ssid in ["Corp", "Old"] {
            let request = format!(r#"{{"ssid":"{ssid}","password":"long-enough"}}"#);
            assert!(
                manager
                    .set(WIFI_CONNECT, &request)
                    .unwrap_err()
                    .starts_with("Unavailable:")
            );
        }
        for request in [
            r#"{"ssid":"Cafe"}"#,
            r#"{"ssid":"Cafe","password":"short"}"#,
            r#"{"ssid":"Open","password":"not-needed"}"#,
            r#"{"ssid":"Missing","password":"long-enough"}"#,
            r#"{"ssid":"Cafe","uuid":"home"}"#,
            r#"not json with secret-text"#,
        ] {
            let error = manager.set(WIFI_CONNECT, request).unwrap_err();
            assert!(error.starts_with("InvalidArgument:"), "{error}");
            assert!(!error.contains("secret-text"));
        }
        assert!(calls(&fake).is_empty());
    }

    #[test]
    fn add_network_rejects_duplicates_and_saves_without_activating() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        assert!(
            manager
                .set(ADD, r#"{"ssid":"Home","security":"open"}"#)
                .is_err()
        );
        assert!(
            manager
                .set(ADD, r#"{"ssid":"Corp","security":"enterprise"}"#)
                .unwrap_err()
                .starts_with("Unavailable:")
        );
        manager
            .set(
                ADD,
                r#"{"ssid":"Lab","security":"wpa2","password":"long-enough","hidden":true}"#,
            )
            .unwrap();
        assert_eq!(calls(&fake), vec!["add Lab"]);
    }

    #[test]
    fn radio_verifies_readback_and_respects_hardware_and_permissions() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        assert_eq!(
            manager.set(WIFI_ENABLED, "false").unwrap()["wifi_enabled"],
            false
        );
        assert!(manager.set(WIFI_ENABLED, "maybe").is_err());
        fake.0.lock().unwrap().reject = true;
        let state = manager.set(WIFI_ENABLED, "true").unwrap_err();
        assert_eq!(state, "rejected");
        fake.0.lock().unwrap().reject = false;
        fake.0.lock().unwrap().snapshot.wifi_hardware_enabled = false;
        assert!(
            manager
                .set(WIFI_ENABLED, "true")
                .unwrap_err()
                .contains("hardware")
        );
        {
            let mut world = fake.0.lock().unwrap();
            world.snapshot.wifi_hardware_enabled = true;
            world
                .snapshot
                .permissions
                .insert(format!("{PERMISSION}enable-disable-wifi"), "no".into());
        }
        assert!(
            manager
                .set(WIFI_ENABLED, "true")
                .unwrap_err()
                .contains("not allowed")
        );
    }

    #[test]
    fn adapter_selection_scopes_operations_and_absence_is_reported() {
        let (fake, mut manager, _root) = setup();
        fake.0
            .lock()
            .unwrap()
            .snapshot
            .devices
            .push(adapter("wlan1", vec![]));
        manager.refresh().unwrap();
        assert_eq!(manager.state()["adapter"], "wlan0");
        assert!(manager.set(WIFI_ADAPTER, "eth9").is_err());
        manager.set(WIFI_ADAPTER, "wlan1").unwrap();
        manager.set(WIFI_REFRESH, "scan").unwrap();
        assert!(calls(&fake).contains(&"scan /d/wlan1".to_owned()));
        fake.0.lock().unwrap().snapshot.devices.clear();
        assert!(
            manager
                .set(WIFI_REFRESH, "scan")
                .unwrap_err()
                .contains("No Wi-Fi adapter")
        );
    }

    #[test]
    fn sign_in_opens_only_a_portal_web_address() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        assert!(manager.set(SIGN_IN, "open").is_err());
        {
            let mut world = fake.0.lock().unwrap();
            world.snapshot.connectivity = "portal".into();
            world.snapshot.check_uri = Some("file:///etc/passwd".into());
        }
        assert!(manager.set(SIGN_IN, "open").is_err());
        fake.0.lock().unwrap().snapshot.check_uri = Some("http://check.example/".into());
        manager.set(SIGN_IN, "open").unwrap();
        assert_eq!(calls(&fake), vec!["open http://check.example/"]);
    }

    #[test]
    fn forget_verifies_removal_and_read_only_profiles_refuse_changes() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        fake.0.lock().unwrap().snapshot.profiles[0].read_only = true;
        assert!(
            manager
                .set(FORGET, "home")
                .unwrap_err()
                .contains("read-only")
        );
        fake.0.lock().unwrap().snapshot.profiles[0].read_only = false;
        manager.set(FORGET, "home").unwrap();
        assert!(calls(&fake).contains(&"forget /c/home".to_owned()));
        assert!(manager.set(FORGET, "home").is_err());
    }

    fn ethernet(fake: &Fake) {
        let mut world = fake.0.lock().unwrap();
        let mut wired = profile("wired", "Wired connection 1", Security::Open);
        wired.kind = "ethernet".into();
        wired.raw.clear();
        wired.ssid.clear();
        world.snapshot.profiles.push(wired);
        let mut device = adapter("eno1", vec![]);
        device.kind = "ethernet".into();
        device.state = "connected".into();
        device.uuid = Some("wired".into());
        world.snapshot.devices.push(device);
        world.snapshot.active.push(Active {
            path: "/a/wired".into(),
            uuid: "wired".into(),
            name: "Wired connection 1".into(),
            kind: "802-3-ethernet".into(),
            state: 2,
        });
    }

    fn manual_ip() -> String {
        json!({"uuid":"wired","value":{"ipv4":"manual","addresses":["192.168.1.20/24"],
            "gateway":"192.168.1.1","auto_dns":false,"dns":["1.1.1.1","2606:4700:4700::1111"],
            "ipv6":"disabled","dns_over_tls":"default"}})
        .to_string()
    }

    #[test]
    fn ip_settings_validate_save_and_reapply_to_the_connected_device() {
        let (fake, mut manager, root) = setup();
        ethernet(&fake);
        manager.refresh().unwrap();
        for bad in [
            json!({"ipv4":"manual","addresses":[],"gateway":"","auto_dns":true,"dns":[],"ipv6":"auto","dns_over_tls":"default"}),
            json!({"ipv4":"auto","addresses":["10.0.0.1/33"],"gateway":"","auto_dns":true,"dns":[],"ipv6":"auto","dns_over_tls":"default"}),
            json!({"ipv4":"auto","addresses":[],"gateway":"x","auto_dns":true,"dns":[],"ipv6":"auto","dns_over_tls":"default"}),
            json!({"ipv4":"auto","addresses":[],"gateway":"","auto_dns":false,"dns":[],"ipv6":"auto","dns_over_tls":"default"}),
            json!({"ipv4":"shared","addresses":[],"gateway":"","auto_dns":true,"dns":[],"ipv6":"auto","dns_over_tls":"default"}),
            json!({"ipv4":"auto","addresses":[],"gateway":"","auto_dns":true,"dns":[],"ipv6":"manual","dns_over_tls":"default"}),
        ] {
            let request = json!({"uuid":"wired","value":bad}).to_string();
            assert!(
                manager
                    .set(ETHERNET_IP, &request)
                    .unwrap_err()
                    .starts_with("InvalidArgument:")
            );
        }
        assert!(
            manager.set(KNOWN_IP, &manual_ip()).is_err(),
            "Wi-Fi page edits Wi-Fi only"
        );
        let state = manager.set(ETHERNET_DNS, &manual_ip()).unwrap();
        let wired = state["profiles"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["uuid"] == "wired")
            .unwrap()
            .clone();
        assert_eq!(wired["ip"]["addresses"][0], "192.168.1.20/24");
        assert!(calls(&fake).contains(&"reapply /d/eno1".to_owned()));
        let text = fs::read_to_string(root.path().join("network.toml")).unwrap();
        assert!(text.contains("192.168.1.20/24"));
        assert_eq!(manager.state()["conflict"], false);
    }

    #[test]
    fn priority_and_mac_are_wifi_preferences_skipped_by_iwd() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        manager
            .set(PRIORITY, r#"{"uuid":"home","value":10}"#)
            .unwrap();
        manager
            .set(MAC, r#"{"uuid":"home","value":"stable"}"#)
            .unwrap();
        let world = fake.0.lock().unwrap().snapshot.profiles[0].clone();
        assert_eq!((world.priority, world.mac.as_str()), (10, "stable"));
        assert!(
            manager
                .set(PRIORITY, r#"{"uuid":"home","value":1000}"#)
                .is_err()
        );
        assert!(
            manager
                .set(MAC, r#"{"uuid":"home","value":"00:11"}"#)
                .is_err()
        );
        fake.0.lock().unwrap().snapshot.wifi_backend = "iwd".into();
        assert!(
            manager
                .set(PRIORITY, r#"{"uuid":"home","value":5}"#)
                .unwrap_err()
                .starts_with("Unavailable:")
        );
    }

    #[test]
    fn connectivity_check_is_reconciled_both_ways() {
        let (fake, mut manager, _root) = setup();
        {
            let mut world = fake.0.lock().unwrap();
            world.snapshot.connectivity_check_available = true;
            world.snapshot.connectivity_check_enabled = true;
        }
        manager.refresh().unwrap();
        manager.set(CONNECTIVITY_CHECK, "false").unwrap();
        fake.0.lock().unwrap().snapshot.connectivity_check_enabled = true;
        manager.refresh().unwrap();
        let state = manager.state();
        assert_eq!(state["conflicts"][0]["name"], "Internet connectivity check");
        manager.resolve("settings").unwrap();
        assert!(!fake.0.lock().unwrap().snapshot.connectivity_check_enabled);
        fake.0.lock().unwrap().snapshot.connectivity_check_available = false;
        assert!(
            manager
                .set(CONNECTIVITY_CHECK, "true")
                .unwrap_err()
                .starts_with("Unavailable:")
        );
    }

    #[test]
    fn invalid_configuration_is_replaced_only_by_choosing_the_system() {
        let (_fake, mut manager, root) = setup();
        fs::write(root.path().join("network.toml"), "version = 1").unwrap();
        manager.refresh().unwrap();
        assert_eq!(manager.state()["config_invalid"], true);
        assert!(
            manager.state()["error"]
                .as_str()
                .unwrap()
                .contains("another Settings version")
        );
        assert!(manager.resolve("settings").is_err());
        manager.resolve("system").unwrap();
        assert_eq!(manager.state()["writable"], true);
        assert!(
            fs::read_to_string(root.path().join("network.toml"))
                .unwrap()
                .contains("version = 2")
        );
    }

    #[test]
    fn hotspot_is_set_up_once_then_toggled_without_persisting_its_state() {
        let (fake, mut manager, _root) = setup();
        manager.refresh().unwrap();
        assert!(
            manager
                .set(HOTSPOT_ENABLED, "true")
                .unwrap_err()
                .contains("Set up")
        );
        let request = r#"{"ssid":"Remy","band":"5"}"#;
        assert!(
            manager
                .set(HOTSPOT_CONFIGURE, request)
                .unwrap_err()
                .contains("password")
        );
        let request = r#"{"ssid":"Remy","band":"5","password":"hotspot-secret"}"#;
        let state = manager.set(HOTSPOT_CONFIGURE, request).unwrap();
        assert!(!state.to_string().contains("hotspot-secret"));
        let hotspot = manager.hotspot_profile().unwrap();
        assert!(!hotspot.autoconnect);
        assert!(
            manager.state()["profiles"]
                .as_array()
                .unwrap()
                .iter()
                .any(|p| p["kind"] == "hotspot")
        );
        manager.set(HOTSPOT_ENABLED, "true").unwrap();
        assert!(calls(&fake).contains(&"activate /c/added /d/wlan0".to_owned()));
        manager
            .set(HOTSPOT_CONFIGURE, r#"{"ssid":"Remy 2","band":"auto"}"#)
            .unwrap();
        assert_eq!(
            manager.hotspot_profile().unwrap().hotspot.unwrap().ssid,
            "Remy 2"
        );
        fake.0.lock().unwrap().snapshot.devices[0].ap = false;
        assert!(
            manager
                .set(HOTSPOT_ENABLED, "true")
                .unwrap_err()
                .contains("cannot share")
        );
    }

    #[test]
    fn imported_vpn_starts_disconnected_and_can_be_removed() {
        let (fake, mut manager, root) = setup();
        manager.refresh().unwrap();
        assert!(
            manager
                .set(VPN_IMPORT, "/etc/passwd")
                .unwrap_err()
                .starts_with("InvalidArgument:")
        );
        let file = root.path().join("wg0.conf");
        fs::write(&file, "[Interface]\n").unwrap();
        manager.set(VPN_IMPORT, file.to_str().unwrap()).unwrap();
        assert!(calls(&fake).contains(&"deactivate /a/wg".to_owned()));
        let vpn = manager.profile("wg").unwrap();
        assert!(!vpn.autoconnect && !vpn.active);
        assert_eq!(manager.state()["conflict"], false);
        manager
            .set(VPN_CONNECT, r#"{"uuid":"wg","value":true}"#)
            .unwrap();
        assert!(calls(&fake).contains(&"activate /c/wg /".to_owned()));
        assert!(manager.set(FORGET, "wg").is_err());
        manager.set(VPN_REMOVE, "wg").unwrap();
        assert!(manager.profile("wg").is_err());
    }

    #[test]
    fn ethernet_connects_through_networkmanager_choice_and_needs_a_cable() {
        let (fake, mut manager, _root) = setup();
        ethernet(&fake);
        manager.refresh().unwrap();
        manager
            .set(ETHERNET_CONNECT, r#"{"interface":"eno1","value":false}"#)
            .unwrap();
        assert!(calls(&fake).contains(&"disconnect /d/eno1".to_owned()));
        fake.0.lock().unwrap().snapshot.devices[1].state = "unavailable".into();
        assert!(
            manager
                .set(ETHERNET_CONNECT, r#"{"interface":"eno1","value":true}"#)
                .unwrap_err()
                .contains("cable")
        );
        assert!(
            manager
                .set(ETHERNET_CONNECT, r#"{"interface":"wlan0","value":true}"#)
                .is_err()
        );
    }
}
