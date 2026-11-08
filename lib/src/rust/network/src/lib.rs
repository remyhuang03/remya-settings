//! Network status, Wi-Fi and known networks through NetworkManager.
pub mod airplane;
pub mod nm;

use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    path::PathBuf,
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
pub const CHANGE_PASSWORD: &str = "known-networks.change-password";
pub const FORGET: &str = "known-networks.forget";
pub const SIGN_IN: &str = "network-status.sign-in";

const PERMISSION: &str = "org.freedesktop.NetworkManager.";
const REASON_WAIT: Duration = Duration::from_secs(2);

pub fn is_network_setting(id: &str) -> bool {
    ["wifi.", "known-networks.", "network-status."]
        .iter()
        .any(|prefix| id.starts_with(prefix))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Security {
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

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Profile {
    #[serde(skip)]
    pub path: String,
    pub uuid: String,
    pub name: String,
    pub ssid: String,
    #[serde(skip)]
    pub raw: Vec<u8>,
    pub security: Security,
    pub autoconnect: bool,
    pub metered: String,
    pub hidden: bool,
    pub last_connected: u64,
    pub active: bool,
    pub read_only: bool,
    #[serde(skip)]
    pub unsaved: bool,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
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
    pub connectivity_check: bool,
    pub check_uri: Option<String>,
    pub wifi_enabled: bool,
    pub wifi_hardware_enabled: bool,
    pub primary_uuid: Option<String>,
    pub permissions: BTreeMap<String, String>,
    pub devices: Vec<Device>,
    pub profiles: Vec<Profile>,
    pub active: Vec<Active>,
}

/// Merges access points per network, links saved profiles and fixes display order.
pub fn finish_snapshot(mut snapshot: Snapshot) -> Snapshot {
    for profile in &mut snapshot.profiles {
        profile.active = snapshot.active.iter().any(|a| a.uuid == profile.uuid);
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
                .find(|p| p.raw == network.raw && !p.unsaved)
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
}

impl NewNetwork {
    fn ssid_name(&self) -> String {
        String::from_utf8_lossy(&self.ssid).into_owned()
    }
}

#[derive(Debug, PartialEq)]
pub enum Change {
    Autoconnect(bool),
    Metered(String),
    Password(String),
}

pub trait Backend: Send {
    fn read(&self) -> Result<Snapshot, String>;
    fn set_wifi(&self, enabled: bool) -> Result<(), String>;
    fn scan(&self, device: &str) -> Result<(), String>;
    fn disconnect(&self, device: &str) -> Result<(), String>;
    fn activate(&self, profile: &str, device: &str) -> Result<String, String>;
    /// Returns the profile and active connection paths.
    fn add_activate(&self, spec: &NewNetwork, device: &str) -> Result<(String, String), String>;
    fn add(&self, spec: &NewNetwork) -> Result<(), String>;
    fn update(&self, profile: &str, change: &Change) -> Result<(), String>;
    fn forget(&self, profile: &str) -> Result<(), String>;
    fn save(&self, profile: &str) -> Result<(), String>;
    fn open(&self, uri: &str) -> Result<(), String>;
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct Prefs {
    autoconnect: bool,
    metered: String,
}

impl From<&Profile> for Prefs {
    fn from(p: &Profile) -> Self {
        Self {
            autoconnect: p.autoconnect,
            metered: p.metered.clone(),
        }
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u8,
    profiles: BTreeMap<String, Prefs>,
}

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

pub struct Manager<B> {
    backend: B,
    path: PathBuf,
    saved: Option<BTreeMap<String, Prefs>>,
    snapshot: Option<Snapshot>,
    read_error: Option<String>,
    config_error: Option<String>,
    failure: Option<Value>,
    pending: Option<Pending>,
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
            selected: None,
        }
    }

    fn persist(&self, profiles: &BTreeMap<String, Prefs>) -> Result<(), String> {
        let bytes = toml::to_string(&Config {
            version: 1,
            profiles: profiles.clone(),
        })
        .map_err(|e| e.to_string())?;
        atomic_write(&self.path, bytes.as_bytes())
    }

    fn observed_prefs(snapshot: &Snapshot) -> BTreeMap<String, Prefs> {
        snapshot
            .profiles
            .iter()
            .filter(|p| !p.unsaved)
            .map(|p| (p.uuid.clone(), p.into()))
            .collect()
    }

    fn load_saved(&mut self, observed: &BTreeMap<String, Prefs>) -> Result<(), String> {
        if self.saved.is_some() {
            return Ok(());
        }
        match fs::read_to_string(&self.path) {
            Ok(text) => {
                let config: Config = toml::from_str(&text)
                    .map_err(|e| format!("Invalid network configuration: {e}"))?;
                if config.version != 1 {
                    return Err("Unsupported network configuration version".into());
                }
                self.saved = Some(config.profiles);
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
    fn adopt_inventory(&mut self, observed: &BTreeMap<String, Prefs>) -> Result<(), String> {
        let Some(saved) = &mut self.saved else {
            return Ok(());
        };
        let before = saved.len();
        saved.retain(|uuid, _| observed.contains_key(uuid));
        let mut changed = saved.len() != before;
        for (uuid, prefs) in observed {
            if !saved.contains_key(uuid) {
                saved.insert(uuid.clone(), prefs.clone());
                changed = true;
            }
        }
        if changed {
            let copy = saved.clone();
            return self.persist(&copy);
        }
        Ok(())
    }

    fn settle_pending(&mut self) {
        let Some(snapshot) = &self.snapshot else {
            return;
        };
        let Some(pending) = &self.pending else {
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
        let pending = self.pending.take().unwrap();
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
        let needs_password = matches!(pending.reason, Some(7 | 8));
        let message = match pending.reason {
            Some(7 | 8) => format!("Could not connect to {}: check the password", pending.ssid),
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
        let observed = Self::observed_prefs(&snapshot);
        self.snapshot = Some(snapshot);
        let result = self
            .load_saved(&observed)
            .and_then(|()| self.adopt_inventory(&observed));
        self.config_error = result.err();
        self.settle_pending();
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
        for profile in &snapshot.profiles {
            let Some(prefs) = saved.get(&profile.uuid) else {
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

    fn profile(&self, uuid: &str) -> Result<Profile, String> {
        self.snapshot()?
            .profiles
            .iter()
            .find(|p| p.uuid == uuid)
            .cloned()
            .ok_or_else(|| invalid("Unknown network"))
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
        match id {
            "network-status.connection" => state["connectivity"].clone(),
            "network-status.traffic" => self.traffic(),
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
                json!(
                    state["devices"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter(|d| d["physical"] == physical)
                        .collect::<Vec<_>>()
                )
            }
            WIFI_ENABLED => state["wifi_enabled"].clone(),
            WIFI_ADAPTER => state["adapter"].clone(),
            "wifi.current" => json!(
                self.adapter()
                    .and_then(|d| d.networks.iter().find(|n| n.in_use))
            ),
            "wifi.networks" => json!(self.adapter().map(|d| &d.networks)),
            _ => Value::Null,
        }
    }

    fn change_profile(&mut self, uuid: &str, change: Change) -> Result<Value, String> {
        self.refresh()?;
        if !self.writable() {
            return Err("Network configuration is not writable".into());
        }
        if self.conflict() {
            return Err(
                "Conflict:Resolve the saved and system network conflict before changing it".into(),
            );
        }
        self.allowed("settings.modify.system", "change saved networks")?;
        let profile = self.profile(uuid)?;
        if profile.read_only {
            return Err("Unavailable:This saved network is read-only".into());
        }
        self.backend.update(&profile.path, &change)?;
        self.refresh()?;
        let after = self.profile(uuid)?;
        let matches = match &change {
            Change::Autoconnect(value) => after.autoconnect == *value,
            Change::Metered(value) => after.metered == *value,
            Change::Password(_) => true,
        };
        if !matches {
            return Err("NetworkManager readback does not match the requested value".into());
        }
        let saved = self.saved.as_mut().ok_or("Network configuration missing")?;
        saved.insert(uuid.to_owned(), (&after).into());
        let copy = saved.clone();
        self.persist(&copy)?;
        Ok(self.state())
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
                    .find(|profile| profile.raw == ssid)
                    .map(|profile| profile.uuid.clone())
            } else {
                network.and_then(|network| network.known_uuid.clone())
            }
        });
        if let Some(uuid) = uuid {
            let profile = self.profile(&uuid)?;
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
            if ssid.is_empty() || ssid.len() > 32 {
                return Err(invalid("Use 1 to 32 bytes for the network name"));
            }
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

    pub fn set(&mut self, key: &str, value: &str) -> Result<Value, String> {
        self.failure = None;
        match key {
            WIFI_ENABLED => {
                let enabled = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err(invalid("Expected true or false")),
                };
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
                if request.ssid.is_empty() || request.ssid.len() > 32 {
                    return Err(invalid("Use 1 to 32 bytes for the network name"));
                }
                if !request.security.creatable() {
                    return Err("Unavailable:Settings cannot create this type of network".into());
                }
                validate_password(request.security, request.password.as_deref())?;
                self.refresh()?;
                self.allowed("settings.modify.system", "change saved networks")?;
                let ssid = request.ssid.into_bytes();
                if self.snapshot()?.profiles.iter().any(|p| p.raw == ssid) {
                    return Err(invalid("This network is already saved"));
                }
                self.backend.add(&NewNetwork {
                    ssid: ssid.clone(),
                    security: request.security,
                    password: request.password,
                    hidden: request.hidden,
                    autoconnect: request.autoconnect,
                })?;
                self.refresh()?;
                if !self.snapshot()?.profiles.iter().any(|p| p.raw == ssid) {
                    return Err("NetworkManager did not save the network".into());
                }
            }
            AUTOCONNECT | METERED | CHANGE_PASSWORD => {
                #[derive(Deserialize)]
                #[serde(deny_unknown_fields)]
                struct Request {
                    uuid: String,
                    value: Value,
                }
                let request: Request =
                    serde_json::from_str(value).map_err(|_| invalid("Expected uuid and value"))?;
                let change = match key {
                    AUTOCONNECT => Change::Autoconnect(
                        request
                            .value
                            .as_bool()
                            .ok_or_else(|| invalid("Expected true or false"))?,
                    ),
                    METERED => {
                        let value = request.value.as_str().unwrap_or_default();
                        if !["automatic", "yes", "no"].contains(&value) {
                            return Err(invalid("Use automatic, yes or no"));
                        }
                        Change::Metered(value.to_owned())
                    }
                    _ => {
                        let password = request.value.as_str().unwrap_or_default().to_owned();
                        self.refresh()?;
                        let security = self.profile(&request.uuid)?.security;
                        if !security.personal() {
                            return Err(
                                "Unavailable:Settings changes personal network passwords only"
                                    .into(),
                            );
                        }
                        validate_password(security, Some(&password))?;
                        Change::Password(password)
                    }
                };
                return self.change_profile(&request.uuid, change);
            }
            FORGET => {
                self.refresh()?;
                self.allowed("settings.modify.system", "change saved networks")?;
                let profile = self.profile(value)?;
                if profile.read_only {
                    return Err("Unavailable:This saved network is read-only".into());
                }
                self.backend.forget(&profile.path)?;
                self.refresh()?;
                if self.snapshot()?.profiles.iter().any(|p| p.uuid == value) {
                    return Err("NetworkManager did not remove the network".into());
                }
            }
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
        self.refresh()?;
        if !self.writable() {
            return Err("Network configuration is not writable".into());
        }
        match source {
            "system" => {
                let observed = Self::observed_prefs(self.snapshot()?);
                self.persist(&observed)?;
                self.saved = Some(observed);
            }
            "settings" => {
                self.allowed("settings.modify.system", "change saved networks")?;
                let saved = self.saved.clone().unwrap_or_default();
                for profile in self.snapshot()?.profiles.clone() {
                    let Some(prefs) = saved.get(&profile.uuid) else {
                        continue;
                    };
                    if prefs.autoconnect != profile.autoconnect {
                        self.backend
                            .update(&profile.path, &Change::Autoconnect(prefs.autoconnect))?;
                    }
                    if prefs.metered != profile.metered {
                        self.backend
                            .update(&profile.path, &Change::Metered(prefs.metered.clone()))?;
                    }
                }
                self.refresh()?;
                if self.conflict() {
                    return Err("NetworkManager readback does not match the saved values".into());
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

    fn profile(uuid: &str, ssid: &str, security: Security) -> Profile {
        Profile {
            path: format!("/c/{uuid}"),
            uuid: uuid.into(),
            name: ssid.into(),
            ssid: ssid.into(),
            raw: ssid.into(),
            security,
            autoconnect: true,
            metered: "automatic".into(),
            hidden: false,
            last_connected: 0,
            active: false,
            read_only: false,
            unsaved: false,
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
            hardware_address: None,
            connection: None,
            uuid: None,
            speed_mbps: None,
            ipv4: vec![],
            gateway: None,
            dns: vec![],
            ipv6: vec![],
            networks,
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
            world
                .snapshot
                .profiles
                .push(profile("added", &spec.ssid_name(), spec.security));
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
            match change {
                Change::Autoconnect(v) => target.autoconnect = *v,
                Change::Metered(v) => target.metered = v.clone(),
                Change::Password(_) => {}
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
}
