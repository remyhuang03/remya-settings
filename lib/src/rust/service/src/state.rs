use crate::privileged::{Request, Session};
use gio::glib::{Variant, variant::ToVariant};
use remya_settings_appearance::api as appearance;
use remya_settings_applications as applications;
use remya_settings_background::{
    BackgroundManager, RealDesktop, is_accent_setting, is_background_setting, manager::Paths,
};
use remya_settings_date_time::api as clock;
use remya_settings_default_apps::{self as default_apps, DefaultApps};
use remya_settings_display::{
    DisplayManager, Hyprctl, NightLight, RealSunset, atomic_write, is_display_setting,
    is_night_light_setting,
};
use remya_settings_fonts::{self as fonts, FontManager, RealFontconfig};
use remya_settings_network::{NetworkManager, is_network_setting};
use remya_settings_system_information::hostname::{self, HostnameManager};
use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    process::{Child, Command},
};

pub const STYLE: &str = "themes.material-style-variant";
pub const MODE: &str = "themes.material-theme-mode";
pub const ZONE: &str = "date-time.fb2a23dc";
pub const MANUAL: &str = "date-time.6422d209";
pub const AUTO: &str = "date-time.db451de3";
pub const SYNC: &str = "date-time.098d06ec";
pub const SERVERS: &str = "date-time.7e33a213";
pub const LOCALE: &str = "date-time.format";
const STYLES: &[&str] = &[
    "tonal_spot",
    "fidelity",
    "monochrome",
    "neutral",
    "vibrant",
    "expressive",
    "content",
    "rainbow",
    "fruit_salad",
];
fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
fn prefs(state: &clock::DateTimeState) -> Value {
    json!({"timezone":state.timezone,"ntp":state.ntp,"time_servers":state.time_servers,"time_locale":state.time_locale})
}
fn write(path: &std::path::Path, value: &Value) -> Result<(), String> {
    atomic_write(
        path,
        toml::to_string(value)
            .map_err(|e| e.to_string())?
            .as_bytes(),
    )
}
/// `system-information` is the public name of the About page.
pub fn page_alias(page: &str) -> &str {
    if page == "system-information" {
        "about"
    } else {
        page
    }
}
fn load(path: &std::path::Path) -> Result<Option<Value>, String> {
    match fs::read_to_string(path) {
        Ok(s) => toml::from_str(&s)
            .map(Some)
            .map_err(|e| format!("{}: {e}", path.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

fn normalize_theme(value: Value) -> Result<Value, String> {
    let object = value
        .as_object()
        .ok_or("Invalid appearance configuration")?;
    if value["version"] != 1
        || object
            .keys()
            .any(|k| !["version", "theme"].contains(&k.as_str()))
    {
        return Err("Invalid appearance configuration".into());
    }
    let empty = json!({});
    let theme = if value["theme"].is_null() {
        &empty
    } else {
        &value["theme"]
    };
    if theme.as_object().is_none_or(|m| {
        m.keys()
            .any(|k| !["style_variant", "theme_mode"].contains(&k.as_str()))
    }) {
        return Err("Invalid theme table".into());
    }
    let style = if theme["style_variant"].is_null() {
        "tonal_spot"
    } else {
        theme["style_variant"]
            .as_str()
            .ok_or("Invalid Material style")?
    };
    let mode = if theme["theme_mode"].is_null() || theme["theme_mode"] == "system" {
        "light"
    } else {
        theme["theme_mode"].as_str().ok_or("Invalid theme mode")?
    };
    if !STYLES.contains(&style) || !["light", "dark"].contains(&mode) {
        return Err("Invalid Material style or theme mode".into());
    }
    Ok(json!({"version":1,"theme":{"style_variant":style,"theme_mode":mode}}))
}

/// Hyprland reads `$XDG_CONFIG_HOME/hypr`; relative XDG values are ignored.
fn hypr_config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .map(|p| p.join(".config"))
        })
        .unwrap_or_default()
        .join("hypr")
}

/// Debug builds keep owned files beside the repository's local configuration.
fn background_paths(config: &std::path::Path) -> Paths {
    let debug = config.file_name().is_some_and(|n| n == "config.local.toml");
    let dirs = xdg::BaseDirectories::new();
    let data = dirs.get_data_home().unwrap_or_default();
    let cache = dirs.get_cache_home().unwrap_or_default();
    let owned = |root: PathBuf, name: &str| {
        if debug {
            config.with_file_name(name)
        } else {
            root.join("remya/settings").join(name)
        }
    };
    Paths {
        config: config.with_file_name("background.toml"),
        accent: config.with_file_name("accent.toml"),
        media: owned(data, "backgrounds"),
        cache: owned(cache, "background-previews"),
        hyprpaper: hypr_config_dir().join("hyprpaper.conf"),
        units: dirs
            .get_config_home()
            .unwrap_or_default()
            .join("systemd/user"),
        home: std::env::var_os("HOME").map(PathBuf::from),
    }
}

pub struct State {
    pub catalog: Value,
    pub theme: Value,
    pub system: Value,
    pub date: Value,
    pub hostname: HostnameManager,
    config: PathBuf,
    saved: Value,
    pub theme_error: Option<String>,
    pub date_error: Option<String>,
    pub display: DisplayManager<Hyprctl>,
    pub night_light: NightLight<RealSunset>,
    pub background: BackgroundManager<RealDesktop>,
    fonts: FontManager<RealFontconfig>,
    pub default_apps: DefaultApps<default_apps::RealDesktop>,
    pub appimages: applications::appimages::AppImages,
    pub network: NetworkManager,
    pub bluetooth: remya_settings_bluetooth::Bluetooth,
    pub auth_error: Option<String>,
    privileged: Option<Session>,
    gui: Option<Child>,
    auth_attempted: bool,
    pub restart_suggested: bool,
    pub navigation: String,
}
impl State {
    pub fn new(config: PathBuf) -> Self {
        Self {
            catalog: serde_json::from_str(include_str!(
                "../../../../../assets/settings/catalog.json"
            ))
            .expect("catalog"),
            theme: json!({"version":1,"theme":{"style_variant":"tonal_spot","theme_mode":"light"}}),
            system: json!({"mode":null,"targets":[]}),
            date: json!({}),
            hostname: HostnameManager::new(config.with_file_name("hostname.toml"), atomic_write),
            display: DisplayManager::new(
                Hyprctl,
                hypr_config_dir(),
                config.with_file_name("display.toml"),
            ),
            night_light: NightLight::new(
                RealSunset,
                hypr_config_dir().join("hyprsunset.conf"),
                config.with_file_name("night-light.toml"),
            ),
            background: BackgroundManager::new(RealDesktop, background_paths(&config)),
            fonts: FontManager::new(
                RealFontconfig,
                fonts::user_font_directory().unwrap_or_default(),
            ),
            default_apps: DefaultApps::new(
                default_apps::RealDesktop,
                config.with_file_name("default-apps.toml"),
            ),
            bluetooth: remya_settings_bluetooth::Bluetooth::new(),
            network: NetworkManager::real(config.with_file_name("network.toml")),
            appimages: applications::appimages::AppImages::real(
                config.with_file_name("appimages.toml"),
            )
            .expect("absolute HOME"),
            saved: Value::Null,
            theme_error: None,
            date_error: None,
            auth_error: None,
            privileged: None,
            gui: None,
            auth_attempted: false,
            restart_suggested: false,
            navigation: "home".into(),
            config,
        }
    }
    fn date_file(&self) -> PathBuf {
        self.config.with_file_name("date-time.toml")
    }
    pub fn refresh(&mut self) {
        self.theme_error = self.refresh_theme().err();
        self.date_error = self.refresh_date().err();
        let _ = self.hostname.refresh();
        let _ = self.default_apps.refresh();
        // Failures stay in the manager's state for every reader.
        let _ = self.network.refresh();
        // A detection failure is retained by the manager and reported in its state.
        let _ = self.display.refresh();
        // Failures stay in the manager's state for every reader.
        let _ = self.night_light.refresh();
        let _ = self.background.refresh();
    }
    fn refresh_theme(&mut self) -> Result<(), String> {
        let system =
            serde_json::to_value(appearance::read_system_theme()?).map_err(|e| e.to_string())?;
        let loaded = if let Some(value) = load(&self.config)? {
            value
        } else {
            let mode = system["mode"]
                .as_str()
                .ok_or("System appearance cannot be detected")?;
            let v = json!({"version":1,"theme":{"style_variant":"tonal_spot","theme_mode":mode}});
            write(&self.config, &v)?;
            v
        };
        let loaded = normalize_theme(loaded)?;
        self.theme = loaded;
        self.system = system;
        Ok(())
    }
    fn refresh_date(&mut self) -> Result<(), String> {
        let observed = clock::read_date_time()?;
        let actual = prefs(&observed);
        let file = self.date_file();
        let loaded = load(&file)?;
        let mut saved = actual.clone();
        if let Some(value) = loaded.as_ref() {
            if value["version"] != 1
                || !value.is_object()
                || value.as_object().unwrap().keys().any(|k| {
                    !["version", "timezone", "ntp", "time_servers", "time_locale"]
                        .contains(&k.as_str())
                })
            {
                return Err("Invalid date/time configuration".into());
            }
            for (k, v) in value.as_object().unwrap() {
                if k != "version" {
                    saved[k] = v.clone();
                }
            }
        }
        let zone = saved["timezone"].as_str().ok_or("Invalid saved timezone")?;
        if !clock::list_timezones()?.iter().any(|z| z.id == zone)
            || !saved["ntp"].is_boolean()
            || saved["time_servers"]
                .as_array()
                .is_none_or(|v| v.iter().any(|s| s.as_str().is_none()))
            || !clock::list_time_locales()?
                .iter()
                .any(|l| Some(l.as_str()) == saved["time_locale"].as_str())
        {
            return Err("Invalid saved date/time preferences".into());
        }
        if loaded.is_none() {
            let mut initial = saved.clone();
            initial["version"] = json!(1);
            write(&file, &initial)?;
        }
        self.saved = saved;
        self.set_date(observed)?;
        Ok(())
    }
    fn set_date(&mut self, state: clock::DateTimeState) -> Result<(), String> {
        let actual = prefs(&state);
        let mut map = serde_json::to_value(&state).map_err(|e| e.to_string())?;
        map["unix_micros"] = json!(state.unix_micros.to_string());
        map["saved_timezone"] = self.saved["timezone"].clone();
        map["saved"] = self.saved.clone();
        map["conflict"] = json!(actual != self.saved);
        map["restart_suggested"] = json!(self.restart_suggested);
        map["authorized"] = json!(self.privileged.is_some());
        map["authorizing"] =
            json!(self.auth_attempted && self.privileged.is_none() && self.auth_error.is_none());
        self.date = map;
        Ok(())
    }
    fn save_date(&mut self, state: clock::DateTimeState, keys: &[&str]) -> Result<Value, String> {
        let values = prefs(&state);
        let mut next = self.saved.clone();
        for key in keys {
            next[*key] = values[*key].clone();
        }
        let mut file = next.clone();
        file["version"] = json!(1);
        write(&self.date_file(), &file)?;
        self.saved = next;
        self.date_error = None;
        self.set_date(state)?;
        Ok(self.date.clone())
    }
    pub fn begin_authorization(&mut self) -> bool {
        if self.auth_attempted {
            return false;
        }
        self.auth_attempted = true;
        true
    }
    pub fn finish_authorization(&mut self, result: Result<Session, String>) {
        match result {
            Ok(session) => {
                self.privileged = Some(session);
                self.auth_error = None;
                self.date_error = None;
            }
            Err(error) => self.auth_error = Some(error),
        }
    }
    fn request(&mut self, request: Request) -> Result<Value, String> {
        let session = self.privileged.as_mut().ok_or_else(|| {
            self.auth_error
                .clone()
                .unwrap_or("Open Settings and authorize system changes first".into())
        })?;
        let result = session.call(&request);
        if !session.is_alive() {
            self.privileged = None;
            self.auth_error=Some("Privileged service stopped; close and reopen the Settings window to authorize again".into());
        }
        result
    }
    fn privileged(&mut self, request: Request) -> Result<clock::DateTimeState, String> {
        serde_json::from_value(self.request(request)?).map_err(|e| e.to_string())
    }
    pub fn hostname_state(&self) -> Value {
        let mut value = self.hostname.state();
        value["authorized"] = json!(self.privileged.is_some());
        value["authorizing"] =
            json!(self.auth_attempted && self.privileged.is_none() && self.auth_error.is_none());
        value
    }
    fn rename_hostname(&mut self, name: &str, expected: String) -> Result<Value, String> {
        let result = self
            .request(Request::Hostname {
                expected_static: expected,
                hostname: name.into(),
            })
            .and_then(|value| serde_json::from_value(value).map_err(|e| e.to_string()));
        self.hostname.finish(name, result)?;
        Ok(self.hostname_state())
    }
    pub fn configuration(&self) -> Value {
        let mut date = self.date.clone();
        date["error"] = json!(self.date_error.as_ref().or(self.auth_error.as_ref()));
        json!({"appearance":{"saved":self.theme["theme"]["theme_mode"],"system":self.system["mode"],"conflict":self.theme["theme"]["theme_mode"]!=self.system["mode"],"error":self.theme_error},"date-time":date,"display":self.display.state(),"night-light":self.night_light.state(),"hostname":self.hostname_state(),"background":self.background.state(),"default-apps":self.default_apps.state(),"network":self.network.state()})
    }
    pub fn controls(&self) -> Vec<&Value> {
        self.catalog["pages"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|p| p["sections"].as_array().unwrap())
            .flat_map(|s| s["controls"].as_array().unwrap())
            .collect()
    }
    pub fn execute(&mut self, method: &str, args: &[String]) -> Result<Value, String> {
        match method {
            "Get" => {
                let key = args[0].as_str();
                match key {
                    "theme" => {
                        self.refresh_theme()?;
                        Ok(self.theme.clone())
                    }
                    "system" => {
                        self.refresh_theme()?;
                        Ok(self.system.clone())
                    }
                    STYLE | MODE => {
                        self.refresh_theme()?;
                        Ok(
                            json!({"id": key,"availability":"available","reason":self.controls().into_iter().find(|c|c["id"]==key).unwrap()["reason"],"value":self.theme["theme"][if key==STYLE{"style_variant"}else{"theme_mode"}]}),
                        )
                    }
                    "configuration" => {
                        self.refresh();
                        Ok(self.configuration())
                    }
                    "date-time" | ZONE | MANUAL | AUTO | SYNC | SERVERS | LOCALE => {
                        self.refresh_date()?;
                        let mut v = self.date.clone();
                        v["error"] = json!(self.date_error.as_ref().or(self.auth_error.as_ref()));
                        if key != "date-time" {
                            v["id"] = json!(key);
                            v["availability"] = json!("available");
                            v["value"] = match key {
                                ZONE => v["timezone"].clone(),
                                MANUAL => v["local_time"].clone(),
                                AUTO => v["ntp"].clone(),
                                SYNC => v["ntp_synchronized"].clone(),
                                SERVERS => v["time_servers"].clone(),
                                _ => v["time_locale"].clone(),
                            };
                        }
                        Ok(v)
                    }
                    "display" => {
                        let _ = self.display.refresh();
                        Ok(self.display.state())
                    }
                    "display-brightness" => {
                        self.display.refresh()?;
                        Ok(self.display.brightness_state())
                    }
                    _ if is_display_setting(key) => {
                        let _ = self.display.refresh();
                        let control = self
                            .controls()
                            .into_iter()
                            .find(|c| c["id"] == key)
                            .ok_or_else(|| invalid("Unknown setting"))?;
                        Ok(json!({
                            "id": key,
                            "availability": control["availability"],
                            "reason": control["reason"],
                            "value": self.display.setting_value(key),
                            "error": self.display.error(),
                        }))
                    }
                    "night-light" => {
                        let _ = self.night_light.refresh();
                        Ok(self.night_light.state())
                    }
                    _ if is_night_light_setting(key) => {
                        let _ = self.night_light.refresh();
                        let control = self
                            .controls()
                            .into_iter()
                            .find(|c| c["id"] == key)
                            .ok_or_else(|| invalid("Unknown setting"))?;
                        Ok(json!({
                            "id": key,
                            "availability": control["availability"],
                            "reason": control["reason"],
                            "value": self.night_light.setting_value(key),
                            "error": self.night_light.state()["error"],
                        }))
                    }
                    "background" => {
                        let _ = self.background.refresh();
                        Ok(self.background.state())
                    }
                    "accent" => Ok(self.background.accent_state()),
                    _ if is_background_setting(key) || is_accent_setting(key) => {
                        let _ = self.background.refresh();
                        let control = self
                            .controls()
                            .into_iter()
                            .find(|c| c["id"] == key)
                            .ok_or_else(|| invalid("Unknown setting"))?;
                        let value = if is_accent_setting(key) {
                            self.background.accent_value(key)
                        } else {
                            self.background.setting_value(key)
                        };
                        Ok(json!({
                            "id": key,
                            "availability": control["availability"],
                            "reason": control["reason"],
                            "value": value,
                            "error": self.background.error(),
                        }))
                    }
                    // Polled every second: answered from the last state, without a NM read.
                    "network-traffic" => Ok(self.network.traffic()),
                    "bluetooth" => self.bluetooth.read(),
                    _ if remya_settings_bluetooth::is_setting(key) => {
                        let state = self.bluetooth.read()?;
                        Ok(
                            json!({"id":key,"availability":"available","reason":"Uses system BlueZ.","value":state,"error":state["error"]}),
                        )
                    }
                    "network" => {
                        let _ = self.network.refresh();
                        Ok(self.network.state())
                    }
                    _ if is_network_setting(key)
                        && self
                            .controls()
                            .iter()
                            .any(|c| c["id"] == key && c["availability"] == "available") =>
                    {
                        let _ = self.network.refresh();
                        Ok(
                            json!({"id":key,"availability":"available","reason":"Uses NetworkManager through the Settings service.","value":self.network.read_value(key),"error":self.network.state()["error"]}),
                        )
                    }
                    "default-apps" => {
                        let _ = self.default_apps.refresh();
                        Ok(self.default_apps.state())
                    }
                    _ if key.starts_with("default-applications:") => {
                        self.default_apps.applications(&key[21..])
                    }
                    _ if key.starts_with("default-types:") => self.default_apps.search(&key[14..]),
                    _ if key.starts_with("default-candidates:") => self
                        .default_apps
                        .candidates(&key[19..].split(',').map(str::to_owned).collect::<Vec<_>>()),
                    _ if default_apps::IDS.contains(&key) => {
                        let _ = self.default_apps.refresh();
                        let mut state = self.default_apps.state();
                        state["id"] = json!(key);
                        state["availability"] = json!("available");
                        state["value"] = state["groups"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .find(|group| group["id"] == key)
                            .map(|group| {
                                json!(
                                    group["types"]
                                        .as_array()
                                        .unwrap()
                                        .iter()
                                        .map(|t| (
                                            t.as_str().unwrap().to_string(),
                                            state["system"][t.as_str().unwrap()].clone()
                                        ))
                                        .collect::<std::collections::BTreeMap<_, _>>()
                                )
                            })
                            .unwrap_or(Value::Null);
                        Ok(state)
                    }
                    _ if key.starts_with("calendar-date:") => Ok(
                        json!({"value":remya_settings_date_time::format_calendar_date(&key[14..])?}),
                    ),
                    "input-method-tools" => applications::external_tools::read("time"),
                    _ if key.starts_with("external-tools:") => {
                        applications::external_tools::read(&key[15..])
                    }
                    _ if applications::external_tools::IDS.contains(&key) => {
                        applications::external_tools::read_setting(key)
                    }
                    "appimages" => Ok(self.appimages.state()),
                    _ if applications::appimages::is_setting(key)
                        && self.controls().iter().any(|c| c["id"] == key) =>
                    {
                        Ok(self.appimages.read_setting(key))
                    }
                    "installed-apps" => applications::read(),
                    _ if key.starts_with("installed-apps:") => applications::search(&key[15..]),
                    _ if key.starts_with("installed-app:") => applications::details(&key[14..]),
                    _ if applications::IDS.contains(&key) => {
                        let mut state = applications::read()?;
                        state["id"] = json!(key);
                        state["availability"] = json!("available");
                        Ok(state)
                    }
                    "fonts" => self.fonts.families(),
                    _ if key.starts_with("font-search:") => self.fonts.search(&key[12..]),
                    _ if key.starts_with("font:") => self.fonts.details(&key[5..]),
                    "timezones" => {
                        let zones = clock::list_timezones()?;
                        Ok(
                            json!({"options":zones.iter().map(|z|&z.id).collect::<Vec<_>>(),"labels":zones.iter().map(|z|(z.id.clone(),json!(z.label))).collect::<serde_json::Map<_,_>>()}),
                        )
                    }
                    "time-locales" => Ok(json!({"options":clock::list_time_locales()?})),
                    "system-information" => {
                        let _ = self.hostname.refresh();
                        let mut value = remya_settings_system_information::read();
                        value["hostname"] = self.hostname_state();
                        Ok(value)
                    }
                    "hostname" | hostname::RENAME => {
                        let _ = self.hostname.refresh();
                        let mut value = self.hostname_state();
                        if key == hostname::RENAME {
                            value["id"] = json!(key);
                            value["availability"] = json!("available");
                            value["value"] = value["static_hostname"].clone();
                        }
                        Ok(value)
                    }
                    _ if remya_settings_system_information::IDS.contains(&key) => {
                        let snapshot = remya_settings_system_information::read();
                        let mut field = snapshot["values"][key].clone();
                        field["id"] = json!(key);
                        field["availability"] = json!("available");
                        field["reason"] = json!("Read-only system information");
                        Ok(field)
                    }
                    "about" => Ok(
                        json!({"name":"Remy'a Settings","version":"0.1.0+2026-10-26","application_id":"top.remya.settings","repository":"https://github.com/remyhuang03/remya_settings","license":"PolyForm-Noncommercial-1.0.0","api_version":1}),
                    ),
                    "catalog" => {
                        let mut v = self.catalog.clone();
                        v["pages"]=json!(self.catalog["pages"].as_array().unwrap().iter().map(|p|json!({"id":p["id"],"title":p["title"],"category":p["category"]})).collect::<Vec<_>>());
                        Ok(v)
                    }
                    _ if key.starts_with("page:") => self.catalog["pages"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .find(|p| p["id"] == page_alias(&key[5..]))
                        .cloned()
                        .ok_or_else(|| invalid("Unknown page")),
                    _ => {
                        let c = self
                            .controls()
                            .into_iter()
                            .find(|c| c["id"] == key)
                            .ok_or_else(|| invalid("Unknown setting"))?;
                        Ok(
                            json!({"id":key,"availability":c["availability"],"reason":c["reason"],"value":null}),
                        )
                    }
                }
            }
            "Set" => self.set(&args[0], &args[1]),
            "List" => {
                let controls = self.controls();
                let start = args[0]
                    .parse::<usize>()
                    .map_err(|_| invalid("Invalid list cursor"))?;
                if start > controls.len() {
                    return Err(invalid("Invalid list cursor"));
                }
                let end = (start + 32).min(controls.len());
                Ok(
                    json!({"api_version":1,"next_cursor":if end<controls.len(){Some(end.to_string())}else{None},"controls":controls[start..end].iter().map(|c|json!({"id":c["id"],"title":c["title"],"availability":c["availability"],"reason":c["reason"]})).collect::<Vec<_>>()}),
                )
            }
            "Search" => {
                let query = args[0].to_lowercase();
                let terms = query.split_whitespace().collect::<Vec<_>>();
                Ok(
                    json!({"pages":self.catalog["pages"].as_array().unwrap().iter().filter(|p|{let text=p.to_string().to_lowercase();terms.iter().all(|term|text.contains(term))}).map(|p|json!({"id":p["id"],"title":p["title"],"category":p["category"]})).collect::<Vec<_>>()}),
                )
            }
            "Open" => {
                let page = &args[0];
                if page == "repository" {
                    Command::new("xdg-open")
                        .arg("https://github.com/remyhuang03/remya_settings")
                        .spawn()
                        .map_err(|e| e.to_string())?;
                } else {
                    if !["home", "about", "licenses"].contains(&page.as_str())
                        && !self.catalog["pages"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .any(|p| p["id"] == page_alias(page))
                    {
                        return Err(invalid("Unknown page"));
                    }
                    self.navigation = page.clone();
                    self.open_gui()?;
                }
                Ok(json!({"opened":page}))
            }
            "Resolve" => self.resolve(&args[0], &args[1]),
            "Reload" => {
                self.refresh();
                if let Some(error) = &self.theme_error {
                    return Err(error.clone());
                }
                Ok(
                    json!({"theme":self.theme,"system":self.system,"configuration":self.configuration()}),
                )
            }
            "Restart" => {
                self.request(Request::Restart {})?;
                Ok(json!({"restarting":true}))
            }
            "Close" => {
                let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)
                    .map_err(|e| e.to_string())?;
                let owned = bus
                    .call_sync(
                        Some("org.freedesktop.DBus"),
                        "/org/freedesktop/DBus",
                        "org.freedesktop.DBus",
                        "NameHasOwner",
                        Some(&("top.remya.settings",).to_variant()),
                        None,
                        gio::DBusCallFlags::NONE,
                        5000,
                        gio::Cancellable::NONE,
                    )
                    .map_err(|e| e.to_string())?
                    .get::<(bool,)>()
                    == Some((true,));
                if owned {
                    bus.call_sync(
                        Some("top.remya.settings"),
                        "/top/remya/settings",
                        "org.gtk.Actions",
                        "Activate",
                        Some(
                            &(
                                "close",
                                Vec::<Variant>::new(),
                                std::collections::HashMap::<String, Variant>::new(),
                            )
                                .to_variant(),
                        ),
                        None,
                        gio::DBusCallFlags::NONE,
                        5000,
                        gio::Cancellable::NONE,
                    )
                    .map_err(|e| e.to_string())?;
                }
                Ok(json!({"closed":true}))
            }
            "Quit" => Ok(json!({"quitting":true})),
            _ => Err(invalid("Unknown method")),
        }
    }
    fn set(&mut self, key: &str, value: &str) -> Result<Value, String> {
        let control = self
            .controls()
            .into_iter()
            .find(|c| c["id"] == key)
            .ok_or_else(|| invalid("Unknown setting"))?;
        if control["availability"] != "available" {
            return Err(format!("Unavailable:{}", control["reason"]));
        }
        if key == "airplane.bluetooth" {
            if value != "open" {
                return Err(invalid("Use open to open Bluetooth settings"));
            }
            return self.execute("Open", &["bluetooth".into()]);
        }
        if remya_settings_bluetooth::is_setting(key) {
            return self.bluetooth.set(key, value);
        }
        if is_network_setting(key) {
            return self.network.set(key, value);
        }
        if default_apps::IDS.contains(&key) {
            return self.default_apps.set(key, value);
        }
        if applications::appimages::is_setting(key) {
            return self.appimages.set(key, value);
        }
        if applications::external_tools::IDS.contains(&key) {
            if value != "open" {
                return Err(invalid("Use open to launch the configuration tool"));
            }
            return applications::external_tools::open(key);
        }
        if applications::IDS.contains(&key) {
            if key != applications::UNINSTALL {
                return Err("ReadOnly:Read installed-apps or installed-app:<desktop-id>".into());
            }
            let removal: applications::Removal = serde_json::from_str(value)
                .map_err(|e| invalid(&format!("Invalid uninstall request: {e}")))?;
            return if applications::needs_authorization(&removal.id) {
                self.request(Request::Uninstall { removal })
            } else {
                applications::uninstall(&removal, false)
            };
        }
        if key == hostname::RENAME {
            hostname::validate_name(value)?;
            self.hostname.refresh()?;
            let expected = self.hostname.prepare(value)?;
            return self.rename_hostname(value, expected);
        }
        if remya_settings_system_information::IDS.contains(&key) {
            return Err("ReadOnly:System information cannot be changed".into());
        }
        if is_display_setting(key) {
            return self.display.set(key, value);
        }
        if is_night_light_setting(key) {
            return self.night_light.set(key, value);
        }
        if is_background_setting(key) {
            return self.background.set(key, value);
        }
        if is_accent_setting(key) {
            return self.background.set_accent(key, value);
        }
        if fonts::IDS.contains(&key) {
            return match key {
                fonts::INSTALL => self.fonts.install(value),
                fonts::UNINSTALL => self.fonts.uninstall(value),
                _ => Err("ReadOnly:Use get font-search:<query> or get font:<family>".into()),
            };
        }
        if [STYLE, MODE].contains(&key) {
            self.refresh_theme()?;
            let before = self.theme.clone();
            let mut next = before.clone();
            if key == STYLE {
                if !STYLES.contains(&value) {
                    return Err(invalid("Invalid style"));
                }
                next["theme"]["style_variant"] = json!(value);
            } else {
                if !["light", "dark"].contains(&value) {
                    return Err(invalid("Invalid mode"));
                }
                next["theme"]["theme_mode"] = json!(value);
            }
            write(&self.config, &next)?;
            if key == MODE
                && let Err(error) = appearance::apply_system_theme(if value == "dark" {
                    appearance::SystemThemeMode::Dark
                } else {
                    appearance::SystemThemeMode::Light
                })
            {
                write(&self.config, &before)?;
                return Err(error);
            }
            self.refresh_theme()?;
            self.theme_error = None;
            return Ok(self.theme.clone());
        }
        self.refresh_date()?;
        let (request, keys) = match key {
            ZONE => {
                if !clock::list_timezones()?.iter().any(|z| z.id == value) {
                    return Err(invalid("Unknown time zone"));
                }
                (
                    Request::Timezone {
                        timezone: value.into(),
                    },
                    vec!["timezone"],
                )
            }
            AUTO => {
                let enabled = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err(invalid("Use true or false")),
                };
                (Request::Automatic { enabled }, vec!["ntp"])
            }
            SYNC => {
                if value != "sync" {
                    return Err(invalid("Use sync"));
                }
                (Request::Sync {}, vec![])
            }
            SERVERS => {
                let servers = serde_json::from_str::<Vec<String>>(value)
                    .map_err(|_| invalid("Expected JSON server array"))?;
                if servers.len() > 16
                    || servers
                        .iter()
                        .any(|s| s.is_empty() || s.contains([' ', '/', '\n']) || s.starts_with('-'))
                {
                    return Err(invalid("Invalid time servers"));
                }
                (Request::Servers { servers }, vec!["time_servers"])
            }
            LOCALE => {
                if !clock::list_time_locales()?.iter().any(|l| l == value) {
                    return Err(invalid("Choose an installed locale"));
                }
                (
                    Request::Locale {
                        locale: value.into(),
                    },
                    vec!["time_locale"],
                )
            }
            MANUAL => {
                #[derive(serde::Deserialize)]
                #[serde(deny_unknown_fields)]
                struct Manual {
                    local_time: String,
                    timezone: String,
                }
                let p: Manual = serde_json::from_str(value)
                    .map_err(|_| invalid("Expected local_time and timezone"))?;
                (
                    Request::Manual {
                        local_time: p.local_time,
                        timezone: p.timezone,
                    },
                    vec!["ntp"],
                )
            }
            _ => return Err(invalid("Unknown setting")),
        };
        let state = self.privileged(request)?;
        if key == LOCALE {
            self.restart_suggested = true;
        }
        self.save_date(state, &keys)
    }
    fn resolve(&mut self, feature: &str, source: &str) -> Result<Value, String> {
        if feature == "network" {
            return self.network.resolve(source);
        }
        if feature == "default-apps" {
            return self.default_apps.resolve(source);
        }
        if feature == "hostname" {
            self.hostname.refresh()?;
            match source {
                "system" => self.hostname.adopt()?,
                "settings" => {
                    let name = self.hostname.saved()?;
                    let expected = self.hostname.expected()?;
                    self.rename_hostname(&name, expected)?;
                }
                _ => return Err(invalid("Unknown resolution")),
            }
            return Ok(self.configuration());
        }
        if feature == "display" {
            self.display.resolve(source)?;
            return Ok(self.configuration());
        }
        if feature == "night-light" {
            self.night_light.resolve(source)?;
            return Ok(self.configuration());
        }
        if feature == "background" {
            self.background.resolve(source)?;
            return Ok(self.configuration());
        }
        if !["system", "settings"].contains(&source) {
            return Err(invalid("Unknown resolution"));
        }
        match feature {
            "appearance" => {
                self.refresh_theme()?;
                let mode = if source == "system" {
                    self.system["mode"]
                        .as_str()
                        .ok_or("Unknown system appearance")?
                        .to_owned()
                } else {
                    self.theme["theme"]["theme_mode"]
                        .as_str()
                        .unwrap()
                        .to_owned()
                };
                if source == "system" {
                    let mut value = self.theme.clone();
                    value["theme"]["theme_mode"] = json!(mode);
                    write(&self.config, &value)?;
                    self.refresh_theme()?;
                } else {
                    self.set(MODE, &mode)?;
                }
            }
            "date-time" => {
                self.refresh_date()?;
                if source == "system" {
                    let state = clock::read_date_time()?;
                    self.save_date(state, &["timezone", "ntp", "time_servers", "time_locale"])?;
                } else {
                    let saved = self.saved.clone();
                    self.set(ZONE, saved["timezone"].as_str().unwrap())?;
                    self.set(LOCALE, saved["time_locale"].as_str().unwrap())?;
                    if self.date["time_servers"] != saved["time_servers"] {
                        self.set(AUTO, "true")?;
                        self.set(SERVERS, &saved["time_servers"].to_string())?;
                    }
                    self.set(
                        AUTO,
                        if saved["ntp"] == true {
                            "true"
                        } else {
                            "false"
                        },
                    )?;
                }
            }
            _ => return Err(invalid("Unknown feature")),
        }
        Ok(self.configuration())
    }
    pub fn reap_gui(&mut self) {
        if self
            .gui
            .as_mut()
            .and_then(|p| p.try_wait().ok())
            .flatten()
            .is_some()
        {
            self.bluetooth.cleanup();
            self.gui = None;
        }
    }
    pub fn shutdown(&mut self) {
        if let Some(mut gui) = self.gui.take() {
            let _ = gui.kill();
            let _ = gui.wait();
        }
        self.privileged = None;
        self.appimages.shutdown();
        self.bluetooth.cleanup();
        // Never leave an unconfirmed display change behind when the service stops.
        let _ = self.display.revert_pending();
    }
    pub fn open_gui(&mut self) -> Result<(), String> {
        if self
            .gui
            .as_mut()
            .and_then(|p| p.try_wait().ok())
            .flatten()
            .is_some()
        {
            self.gui = None;
        }
        if self.gui.is_none() {
            if self.privileged.is_none() && self.auth_error.is_some() {
                self.auth_attempted = false;
                self.auth_error = None;
            }
            let binary = std::env::current_exe()
                .map_err(|e| e.to_string())?
                .parent()
                .and_then(|p| p.parent())
                .ok_or("Missing bundle")?
                .join("remya_settings");
            self.gui = Some(
                Command::new(binary)
                    .args(["--gui", &self.navigation])
                    .spawn()
                    .map_err(|e| e.to_string())?,
            );
        }
        Ok(())
    }
}
impl Drop for State {
    fn drop(&mut self) {
        if let Some(mut gui) = self.gui.take() {
            let _ = gui.kill();
            let _ = gui.wait();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn theme_schema_matches_existing_client_defaults_and_validation() {
        assert_eq!(
            normalize_theme(json!({"version":1})).unwrap()["theme"]["style_variant"],
            "tonal_spot"
        );
        assert_eq!(
            normalize_theme(json!({"version":1,"theme":{"theme_mode":"system"}})).unwrap()["theme"]
                ["theme_mode"],
            "light"
        );
        for value in [
            json!({"version":2}),
            json!({"version":1,"unknown":true}),
            json!({"version":1,"theme":{"unknown":true}}),
            json!({"version":1,"theme":{"theme_mode":true}}),
        ] {
            assert!(normalize_theme(value).is_err());
        }
    }
    #[test]
    fn atomic_preferences_preserve_links_permissions_and_reject_malformed_files() {
        use std::os::unix::fs::PermissionsExt;
        let root = tempfile::tempdir().unwrap();
        let target = root.path().join("config");
        let link = root.path().join("link");
        write(
            &target,
            &json!({"version":1,"theme":{"style_variant":"vibrant","theme_mode":"dark"}}),
        )
        .unwrap();
        fs::set_permissions(&target, fs::Permissions::from_mode(0o640)).unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();
        write(&link, &json!({"version":1})).unwrap();
        assert!(link.is_symlink());
        assert_eq!(
            fs::metadata(&target).unwrap().permissions().mode() & 0o777,
            0o640
        );
        fs::write(&target, "bad [").unwrap();
        assert!(load(&target).is_err());
        assert_eq!(fs::read_to_string(&target).unwrap(), "bad [");
    }
    #[test]
    fn catalog_parity_bounds_and_unknown_operations() {
        let root = tempfile::tempdir().unwrap();
        let mut state = State::new(root.path().join("config"));
        assert_eq!(
            state.execute("Get", &["page:date-time".into()]).unwrap()["id"],
            "date-time"
        );
        assert_eq!(
            state.execute("List", &["0".into()]).unwrap()["controls"]
                .as_array()
                .unwrap()
                .len(),
            32
        );
        assert!(
            state
                .execute("List", &["999999".into()])
                .unwrap_err()
                .starts_with("InvalidArgument:")
        );
        assert!(state.execute("Get", &["unknown".into()]).is_err());
        assert!(
            state
                .execute("Set", &["night-light.50840111".into(), "Set hours".into()])
                .unwrap_err()
                .starts_with("Unavailable:")
        );
    }
}
