use crate::privileged::{Request, Session};
use crate::{clipboard, notifications, osd};
use gio::glib::{Variant, variant::ToVariant};
use remya_settings_appearance::api as appearance;
use remya_settings_appearance::packs::{self, ThemePacks};
use remya_settings_appearance::text_size::{self, TextSize};
use remya_settings_applications as applications;
use remya_settings_background::{
    BackgroundManager, RealDesktop, is_accent_setting, is_background_setting, manager::Paths,
};
use remya_settings_date_time::api as clock;
use remya_settings_date_time::language::{self, Language};
use remya_settings_default_apps::{self as default_apps, DefaultApps};
use remya_settings_display::{
    DisplayManager, Hyprctl, NightLight, RealSunset, atomic_write, is_display_setting,
    is_night_light_setting,
};
use remya_settings_fonts::{self as fonts, FontManager, RealFontconfig};
use remya_settings_input::{self as input, Input, RealHypr};
use remya_settings_network::{NetworkManager, is_network_setting};
use remya_settings_printers::{self as printers, Printers, RealCups};
use remya_settings_sound::{self as sound, Sound, pulse::RealPulse};
use remya_settings_startup::{self as startup, Startup};
use remya_settings_system_information::account::{self, AccountInformation};
use remya_settings_system_information::hostname::{self, HostnameManager};
use remya_settings_updates::{self as updates, Updates};
use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    process::{Child, Command},
    sync::{Arc, Mutex},
};

pub const STYLE: &str = "themes.material-style-variant";
pub const MODE: &str = "themes.material-theme-mode";
pub const BAR_FOLDED_APPS: &str = "remya-bar.folded-apps";
pub const BAR_SIDEBAR: &str = "remya-bar.sidebar-layout";
pub const BAR_LAYOUT: &str = "remya-bar.layout";
pub fn linked_page(id: &str) -> Option<&'static str> {
    match id {
        "power.743773bd" => Some("battery-saver"),
        "power.03bd05ee" => Some("battery-usage"),
        "notifications.automatic-dnd" => Some("quiet-schedule"),
        "notifications.priority" => Some("priority-notifications"),
        _ => None,
    }
}

pub const BAR_CLOCK_SECONDS: &str = "remya-bar.clock-seconds";
pub const BAR_KEY_PREVIEW: &str = "remya-bar.keyboard-preview";
pub const ZONE: &str = "date-time.fb2a23dc";
pub const MANUAL: &str = "date-time.6422d209";
pub const AUTO: &str = "date-time.db451de3";
pub const SYNC: &str = "date-time.098d06ec";
pub const SERVERS: &str = "date-time.7e33a213";
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
const BAR_PILLS: &[&str] = &[
    "notifications",
    "window",
    "resources",
    "media",
    "workspaces",
    "clock",
    "tray",
    "ai-usage",
    "battery",
    "sidebar",
];
const BAR_RESOURCES: &[&str] = &["cpu", "memory", "gpu", "network"];

fn default_bar_layout() -> Value {
    json!({
        "groups":[["notifications","window","resources"],["workspaces","clock"],["tray"],["ai-usage","battery","sidebar"]],
        "workspace_count":8,
        "resources":["cpu","memory","network"],
        "center":1,
        "window_app_name":false,
        "media_marquee":false,
    })
}

fn validate_bar_layout(value: Value) -> Result<Value, String> {
    #[derive(serde::Deserialize, serde::Serialize)]
    #[serde(deny_unknown_fields)]
    struct Layout {
        groups: Vec<Vec<String>>,
        workspace_count: u8,
        resources: Vec<String>,
        window_app_name: bool,
        #[serde(default)]
        media_marquee: bool,
        // TOML has no null: a missing center means no centered group.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        center: Option<usize>,
    }
    let error = || "Invalid Remy'a Bar layout configuration".to_owned();
    let layout: Layout = serde_json::from_value(value).map_err(|_| error())?;
    let mut seen = std::collections::HashSet::new();
    let pills_valid = layout.groups.iter().all(|group| {
        !group.is_empty()
            && group
                .iter()
                .all(|id| BAR_PILLS.contains(&id.as_str()) && seen.insert(id.as_str()))
    });
    let mut metrics = std::collections::HashSet::new();
    let resources_valid = !layout.resources.is_empty()
        && layout
            .resources
            .iter()
            .all(|id| BAR_RESOURCES.contains(&id.as_str()) && metrics.insert(id.as_str()));
    // The sidebar toggle is the bar's only route to quick settings and Settings.
    if !pills_valid
        || !seen.contains("sidebar")
        || !(1..=10).contains(&layout.workspace_count)
        || !resources_valid
        || layout
            .center
            .is_some_and(|center| center >= layout.groups.len())
    {
        return Err(error());
    }
    serde_json::to_value(layout).map_err(|e| e.to_string())
}
fn prefs(state: &clock::DateTimeState) -> Value {
    json!({"timezone":state.timezone,"ntp":state.ntp,"time_servers":state.time_servers})
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
    pub account: AccountInformation,
    config: PathBuf,
    saved: Value,
    pub theme_error: Option<String>,
    pub date_error: Option<String>,
    pub display: DisplayManager<Hyprctl>,
    pub night_light: NightLight<RealSunset>,
    pub background: BackgroundManager<RealDesktop>,
    fonts: FontManager<RealFontconfig>,
    pub default_apps: DefaultApps<default_apps::RealDesktop>,
    pub startup: Startup<startup::RealSystemd>,
    pub input: Input<RealHypr>,
    pub desktop: Input<RealHypr>,
    pub themes: ThemePacks,
    pub text_size: TextSize,
    pub language: Language<language::RealSystem>,
    pub appimages: applications::appimages::AppImages,
    pub network: NetworkManager,
    pub bluetooth: remya_settings_bluetooth::Bluetooth,
    pub proxy: remya_settings_network::proxy::Proxy,
    pub cameras: remya_settings_camera::Cameras<remya_settings_camera::native::Native>,
    pub sound: Sound<RealPulse>,
    pub power: remya_settings_power::Power,
    pub updates: Updates,
    pub storage: remya_settings_storage::Storage,
    pub printers: Printers<RealCups>,
    pub auth_error: Option<String>,
    privileged: Option<Arc<Mutex<Session>>>,
    gui: Option<Child>,
    auth_attempted: bool,
    pub restart_suggested: bool,
    pub navigation: String,
    ai: crate::ai::Ai,
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
            account: AccountInformation::new(config.with_file_name("avatar.png")),
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
            startup: Startup::new(
                startup::RealSystemd,
                startup::Directories::detect(),
                config.with_file_name("startup.toml"),
            ),
            input: Input::new(
                &input::INPUT,
                RealHypr,
                hypr_config_dir(),
                config.with_file_name("input.toml"),
            ),
            desktop: Input::new(
                &input::DESKTOP,
                RealHypr,
                hypr_config_dir(),
                config.with_file_name("desktop.toml"),
            ),
            themes: ThemePacks::new(config.with_file_name("themes.toml")),
            text_size: TextSize::new(config.with_file_name("text-size.toml")),
            language: Language::new(language::RealSystem, config.with_file_name("language.toml")),
            bluetooth: remya_settings_bluetooth::Bluetooth::new(),
            proxy: remya_settings_network::proxy::Proxy::new(),
            cameras: remya_settings_camera::Cameras::new(
                remya_settings_camera::native::Native,
                config.with_file_name("cameras.toml"),
            ),
            sound: Sound::new(RealPulse),
            power: remya_settings_power::Power::new(
                config.with_file_name("power.json"),
                hypr_config_dir().join("hypridle.conf"),
                power_history_path(&config),
            ),
            updates: Updates::new(config.with_file_name("updates.json"), atomic_write),
            storage: remya_settings_storage::Storage::real(config.with_file_name("cleanup.toml"))
                .expect("absolute HOME"),
            network: NetworkManager::real(config.with_file_name("network.toml")),
            printers: Printers::new(RealCups),
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
            ai: crate::ai::Ai::new(config.with_file_name("remya-ai.toml")),
            config,
        }
    }
    fn date_file(&self) -> PathBuf {
        self.config.with_file_name("date-time.toml")
    }
    fn bar_bool_preference(&self, id: &str, request: Option<&str>) -> Result<Value, String> {
        let (file, field) = if id == BAR_CLOCK_SECONDS {
            ("remya-bar.toml", "clock_seconds")
        } else {
            ("remya-bar-keyboard.toml", "preview")
        };
        let path = self.config.with_file_name(file);
        let mut value = match load(&path)? {
            None => true,
            Some(config) => config
                .as_object()
                .filter(|object| object.len() == 1)
                .and_then(|object| object.get(field))
                .and_then(Value::as_bool)
                .ok_or_else(|| {
                    format!("Invalid Remy'a Bar configuration: {field} must be a boolean")
                })?,
        };
        if let Some(request) = request {
            value = request
                .parse::<bool>()
                .map_err(|_| invalid("Use true or false"))?;
            write(&path, &json!({(field):value}))?;
        }
        Ok(json!({"id":id,"availability":"available","value":value}))
    }
    fn bar_folded_apps_file(&self) -> PathBuf {
        self.config.with_file_name("remya-bar-tray.toml")
    }
    fn read_bar_folded_apps(&self) -> Result<Value, String> {
        let ids: Vec<String> = match load(&self.bar_folded_apps_file())? {
            None => vec![],
            Some(config) => serde_json::from_value(config["folded_apps"].clone())
                .map_err(|_| "Invalid Remya Bar folded applications configuration")?,
        };
        Ok(json!({"id":BAR_FOLDED_APPS,"availability":"available","value":ids}))
    }
    fn set_bar_folded_app(&self, value: &str) -> Result<Value, String> {
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Change {
            id: String,
            folded: bool,
        }
        let change: Change = serde_json::from_str(value)
            .map_err(|_| invalid("Expected a tray item id and folded boolean"))?;
        if change.id.trim().is_empty()
            || change.id.len() > 256
            || change.id.chars().any(char::is_control)
        {
            return Err(invalid("Invalid tray item id"));
        }
        let mut state = self.read_bar_folded_apps()?;
        let ids = state["value"].as_array_mut().unwrap();
        ids.retain(|id| id != &change.id);
        if change.folded {
            ids.push(json!(change.id));
        }
        write(&self.bar_folded_apps_file(), &json!({"folded_apps":ids}))?;
        Ok(state)
    }
    fn bar_layout(&self, request: Option<&str>) -> Result<Value, String> {
        let path = self.config.with_file_name("remya-bar-layout.toml");
        let layout = match request {
            Some(request) => {
                let layout = serde_json::from_str(request)
                    .ok()
                    .and_then(|value| validate_bar_layout(value).ok())
                    .ok_or_else(|| invalid("Expected a valid Remy'a Bar layout"))?;
                // Refuse to replace a malformed file the user may still repair.
                load(&path)?.map(validate_bar_layout).transpose()?;
                write(&path, &layout)?;
                layout
            }
            None => match load(&path)? {
                Some(saved) => validate_bar_layout(saved)?,
                None => default_bar_layout(),
            },
        };
        Ok(json!({"id":BAR_LAYOUT,"availability":"available","value":layout}))
    }
    fn sidebar_layout(&self, request: Option<&str>) -> Result<Value, String> {
        const DEFAULT: &[&str] = &[
            "internet",
            "bluetooth",
            "audio",
            "night-light",
            "dnd",
            "power",
            "caffeine",
            "record",
            "screenshot",
            "picker",
            "dark",
            "dnd-quick",
            "airplane",
            "keyboard",
            "clipboard",
            "mic-mute",
        ];
        const RETIRED: &[&str] = &["game", "lock", "audio-switcher"];
        let validate = |tiles: &Vec<String>| {
            let mut seen = std::collections::HashSet::new();
            tiles
                .iter()
                .all(|id| DEFAULT.contains(&id.as_str()) && seen.insert(id))
        };
        let path = self.config.with_file_name("remya-bar-sidebar.toml");
        let current: Vec<String> = match load(&path)? {
            Some(config) => {
                let mut tiles: Vec<String> = serde_json::from_value(config["tiles"].clone())
                    .map_err(|_| "Invalid sidebar layout configuration")?;
                tiles.retain(|id| !RETIRED.contains(&id.as_str()));
                if let Some(index) = tiles.iter().position(|id| id == "vpn") {
                    if tiles.iter().any(|id| id == "dnd-quick") {
                        return Err("Invalid sidebar layout configuration".into());
                    }
                    tiles[index] = "dnd-quick".into();
                }
                if !validate(&tiles) {
                    return Err("Invalid sidebar layout configuration".into());
                }
                tiles
            }
            None => DEFAULT.iter().map(|id| (*id).to_owned()).collect(),
        };
        let tiles = if let Some(request) = request {
            #[derive(serde::Deserialize)]
            #[serde(deny_unknown_fields)]
            struct LayoutChange {
                expected: Vec<String>,
                tiles: Vec<String>,
            }
            let change: LayoutChange = serde_json::from_str(request)
                .map_err(|_| invalid("Expected the previous and new sidebar tile lists"))?;
            if !validate(&change.tiles) {
                return Err(invalid("Sidebar tile IDs must be known and unique"));
            }
            if current != change.expected {
                return Err("Sidebar layout changed in another view. Reopen the editor.".into());
            }
            write(&path, &json!({"tiles":change.tiles}))?;
            change.tiles
        } else {
            current
        };
        Ok(json!({"id":BAR_SIDEBAR,"availability":"available","value":tiles}))
    }

    pub fn refresh(&mut self) {
        self.theme_error = self.refresh_theme().err();
        self.date_error = self.refresh_date().err();
        let _ = self.hostname.refresh();
        let _ = self.default_apps.refresh();
        let _ = self.startup.refresh();
        let _ = self.input.refresh();
        let _ = self.desktop.refresh();
        let _ = self.themes.refresh();
        let _ = self.text_size.refresh();
        let _ = self.language.refresh();
        // Failures stay in the manager's state for every reader.
        let _ = self.network.refresh();
        // A detection failure is retained by the manager and reported in its state.
        let _ = self.display.refresh();
        // Failures stay in the manager's state for every reader.
        let _ = self.night_light.refresh();
        let _ = self.background.refresh();
        let _ = self.sound.refresh();
        let _ = self.power.refresh();
        let _ = self.cameras.refresh();
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
                || value
                    .as_object()
                    .unwrap()
                    .keys()
                    .any(|k| !["version", "timezone", "ntp", "time_servers"].contains(&k.as_str()))
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
                self.privileged = Some(Arc::new(Mutex::new(session)));
                self.auth_error = None;
                self.date_error = None;
            }
            Err(error) => self.auth_error = Some(error),
        }
    }
    fn request(&mut self, request: Request) -> Result<Value, String> {
        if self.updates.busy() {
            return Err("Busy:Wait for the system update operation to finish".into());
        }
        let shared = self
            .privileged
            .as_ref()
            .ok_or_else(|| {
                self.auth_error
                    .clone()
                    .unwrap_or("Open Settings and authorize system changes first".into())
            })?
            .clone();
        let mut session = shared
            .try_lock()
            .map_err(|_| "Busy:Another authorized operation is running")?;
        let result = session.call(&request);
        if !session.is_alive() {
            self.privileged = None;
            self.auth_error = Some("Privileged service stopped; close and reopen the Settings window to authorize again".into());
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
        json!({"appearance":{"saved":self.theme["theme"]["theme_mode"],"system":self.system["mode"],"conflict":self.theme["theme"]["theme_mode"]!=self.system["mode"],"error":self.theme_error},"date-time":date,"display":self.display.state(),"night-light":self.night_light.state(),"hostname":self.hostname_state(),"background":self.background.state(),"default-apps":self.default_apps.state(),"startup":self.startup.state(),"input":self.input.state(),"language":self.language.state(),"desktop":self.desktop.state(),"themes":self.themes.state(),"text-size":self.text_size.state(),"network":self.network.state(),"sound":self.sound.state(),"power":self.power.state(),"cameras":self.cameras.state()})
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
                    BAR_CLOCK_SECONDS | BAR_KEY_PREVIEW => self.bar_bool_preference(key, None),
                    key if key == clipboard::ALL || clipboard::IDS.contains(&key) => {
                        clipboard::get(key)
                    }
                    key if notifications::is_setting(key) => {
                        notifications::get(&self.config, key)
                    }
                    key if osd::is_setting(key) => osd::get(&self.config, key),
                    BAR_FOLDED_APPS => self.read_bar_folded_apps(),
                    BAR_SIDEBAR => self.sidebar_layout(None),
                    BAR_LAYOUT => self.bar_layout(None),
                    key if crate::ai::Ai::is_get(key) => self.ai.get(key),
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
                    "date-time" | ZONE | MANUAL | AUTO | SYNC | SERVERS => {
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
                                _ => v["time_servers"].clone(),
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
                    _ if key.starts_with("display-brightness:") => {
                        self.display.output_brightness(&key[19..])
                    }
                    remya_settings_display::night_light::GAMMA => {
                        Ok(self.night_light.gamma_state())
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
                    "airplane" => remya_settings_network::airplane::read(&self.bluetooth),
                    "proxy" => Ok(self.proxy.read()),
                    _ if remya_settings_network::proxy::IDS.contains(&key) => self.proxy.get(key),
                    remya_settings_network::airplane::ENABLED | remya_settings_network::airplane::WIFI => {
                        let state = remya_settings_network::airplane::read(&self.bluetooth)?;
                        let value = if key == remya_settings_network::airplane::ENABLED { &state["enabled"] } else { &state["wifi_enabled"] };
                        Ok(json!({"id":key,"availability":"available","value":value}))
                    }
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
                    "input" => {
                        let _ = self.input.refresh();
                        Ok(self.input.state())
                    }
                    "desktop" => {
                        let _ = self.desktop.refresh();
                        Ok(self.desktop.state())
                    }
                    _ if input::is_desktop_setting(key) => {
                        let _ = self.desktop.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses Hyprland compositor options.","value":self.desktop.setting_value(key),"error":self.desktop.state()["error"]}))
                    }
                    "themes" => {
                        let _ = self.themes.refresh();
                        Ok(self.themes.state())
                    }
                    text_size::FEATURE => {
                        let _ = self.text_size.refresh();
                        Ok(self.text_size.state())
                    }
                    language::FEATURE => {
                        let _ = self.language.refresh();
                        Ok(self.language.state())
                    }
                    _ if language::is_setting(key) => {
                        let _ = self.language.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses systemd-localed.","value":self.language.setting_value(key),"error":self.language.state()["error"]}))
                    }
                    language::LOCALES => self.language.locales(),
                    _ if key.starts_with(language::PREVIEW) => {
                        language::preview(&key[language::PREVIEW.len()..])
                    }
                    "keyboard-layouts" => Ok(input::xkb::Rules::load()?.catalog()),
                    _ if text_size::is_setting(key) => {
                        let _ = self.text_size.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses the GNOME interface text-scaling-factor.","value":self.text_size.setting_value(),"error":self.text_size.state()["error"]}))
                    }
                    _ if key.starts_with(packs::PREVIEW) => self.themes.preview(&key[packs::PREVIEW.len()..]),
                    _ if packs::is_setting(key) => {
                        let _ = self.themes.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses GNOME interface settings, GTK, KDE, XCursor and Hyprland.","value":self.themes.setting_value(key),"error":self.themes.state()["error"]}))
                    }
                    _ if key.starts_with(input::LOOKUP) => self.input.lookup(&key[input::LOOKUP.len()..]),
                    _ if input::is_setting(key) => {
                        let _ = self.input.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses Hyprland input settings and key bindings.","value":self.input.setting_value(key),"error":self.input.state()["error"]}))
                    }
                    "startup" => {
                        let _ = self.startup.refresh();
                        Ok(self.startup.state())
                    }
                    _ if key.starts_with("startup-candidates:") => self.startup.candidates(&key[19..]),
                    _ if startup::IDS.contains(&key) => {
                        let _ = self.startup.refresh();
                        Ok(json!({"id":key,"availability":"available","reason":"Uses XDG autostart entries started by UWSM.","value":self.startup.state()}))
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
                    "account-information" => self.account.read(),
                    _ if account::IDS.contains(&key) => self.account.read_setting(key),
                    "storage" | "cleanup" => Ok(self.storage.read(key)),
                    "printers" => Ok(self.printers.state()),
                    _ if printers::IDS.contains(&key) => Ok(self.printers.setting_value(key)),
                    _ if remya_settings_storage::is_setting(key) => Ok(self.storage.read_setting(key)),
                    "updates" => {
                        self.updates.refresh();
                        Ok(self.updates.state())
                    }
                    _ if updates::is_setting(key) => {
                        let mut value = self.updates.state();
                        value["id"] = json!(key);
                        // Missing tools are a host limit; a missing root updater is reported by `available`/`reason`.
                        value["availability"] = json!(if value["missing"].as_array().is_some_and(Vec::is_empty) { "available" } else { "planned" });
                        Ok(value)
                    }
                    "cameras" => {
                        let _ = self.cameras.refresh();
                        Ok(self.cameras.state())
                    }
                    _ if remya_settings_camera::is_setting(key) => {
                        let _ = self.cameras.refresh();
                        let mut value = self.cameras.state();
                        value["id"] = json!(key);
                        Ok(value)
                    }
                    "power" | "battery-saver" => Ok(self.power.read()),
                    _ if remya_settings_power::is_setting(key) => Ok(self.power.read_setting(key)),
                    _ if key.starts_with("battery-history:") => self.power.query(&key[16..]),
                    "sound" => {
                        let _ = self.sound.refresh();
        let _ = self.power.refresh();
                        Ok(self.sound.state())
                    }
                    _ if sound::is_setting(key) => {
                        let _ = self.sound.refresh();
        let _ = self.power.refresh();
                        let mut value = self.sound.state();
                        value["id"] = json!(key);
                        value["availability"] = json!("available");
                        Ok(value)
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
                        json!({"name":"Remy'a Settings","version":env!("CARGO_PKG_VERSION"),"application_id":"top.remya.settings","repository":"https://github.com/remyhuang03/remya-settings","license":"PolyForm-Noncommercial-1.0.0","api_version":1}),
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
                        .arg("https://github.com/remyhuang03/remya-settings")
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
                    self.ensure_idle();
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
            "Quit" if self.updates.busy() => Err("Busy:An update operation is running; wait for it to finish before quitting the service".into()),
            "Quit" if self.storage.busy() => Err("Busy:A storage operation is running; wait for it to finish before quitting the service".into()),
            "Quit" => Ok(json!({"quitting":true})),
            _ => Err(invalid("Unknown method")),
        }
    }
    pub fn ensure_idle(&self) {
        if let Err(error) = self.power.ensure_idle() {
            eprintln!("hypridle startup: {error}");
        }
    }

    fn set(&mut self, key: &str, value: &str) -> Result<Value, String> {
        if key == remya_settings_power::idle::START_ID {
            if value != "start" {
                return Err(invalid("Use start to ensure hypridle is running"));
            }
            self.power.ensure_idle()?;
            return Ok(json!({"running":true}));
        }
        if key == BAR_SIDEBAR {
            return self.sidebar_layout(Some(value));
        }
        if crate::ai::SET_IDS.contains(&key) {
            return self.ai.set(key, value);
        }
        if key == BAR_LAYOUT {
            return self.bar_layout(Some(value));
        }
        if key == remya_settings_display::night_light::GAMMA {
            return self.night_light.set_gamma(value);
        }
        if let Some(output) = key.strip_prefix("display-brightness:") {
            return self.display.set_output_brightness(output, value);
        }
        if remya_settings_power::is_setting(key) {
            return self.power.set(key, value);
        }
        let control = self
            .controls()
            .into_iter()
            .find(|c| c["id"] == key)
            .ok_or_else(|| invalid("Unknown setting"))?;
        if control["availability"] != "available" {
            return Err(format!("Unavailable:{}", control["reason"]));
        }
        if clipboard::IDS.contains(&key) {
            return clipboard::set(key, value);
        }
        if printers::IDS.contains(&key) {
            return self.printers.set(key, value);
        }
        if let Some(page) = linked_page(key) {
            if value != "open" {
                return Err(invalid("Use open to open the linked Settings page"));
            }
            return self.execute("Open", &[page.into()]);
        }
        if account::IDS.contains(&key) {
            return self.account.set(key, value, atomic_write);
        }
        if [
            remya_settings_network::airplane::ENABLED,
            remya_settings_network::airplane::WIFI,
        ]
        .contains(&key)
        {
            let result = remya_settings_network::airplane::set(&self.bluetooth, key, value);
            let _ = self.network.refresh();
            return result;
        }
        if remya_settings_network::proxy::IDS.contains(&key) {
            return self.proxy.set(key, value);
        }
        if remya_settings_bluetooth::is_setting(key) {
            return self.bluetooth.set(key, value);
        }
        if is_network_setting(key) {
            return self.network.set(key, value);
        }
        if input::is_setting(key) {
            return self.input.set(key, value);
        }
        if input::is_desktop_setting(key) {
            return self.desktop.set(key, value);
        }
        if packs::is_setting(key) {
            return self.themes.set(key, value);
        }
        if text_size::is_setting(key) {
            return self.text_size.set(value);
        }
        if language::is_setting(key) {
            let values = self.language.plan(key, value)?;
            let written = self.request(Request::Language { values }).map(|_| ());
            return self.language.finish(written);
        }
        if startup::IDS.contains(&key) {
            return self.startup.set(key, value);
        }
        if default_apps::IDS.contains(&key) {
            return self.default_apps.set(key, value);
        }
        if remya_settings_storage::is_setting(key) {
            if self.updates.busy() {
                return Err("Busy:Wait for the system update operation to finish".into());
            }
            let request = match key {
                "cleanup.package-cache" => {
                    let p: remya_settings_storage::packages::PackageCache =
                        remya_settings_storage::payload(value)?;
                    remya_settings_storage::packages::validate_keep(p.keep)?;
                    Some(Request::PackageCache {
                        keep: p.keep,
                        uninstalled: p.uninstalled,
                    })
                }
                "cleanup.orphans" => {
                    let p: remya_settings_storage::packages::RemovePackages =
                        remya_settings_storage::payload(value)?;
                    Some(Request::RemovePackages {
                        packages: p.packages,
                    })
                }
                _ => None,
            };
            if let Some(request) = request {
                let session = self
                    .privileged
                    .as_ref()
                    .ok_or_else(|| {
                        self.auth_error
                            .clone()
                            .unwrap_or("Open Settings and authorize system changes first".into())
                    })?
                    .clone();
                return self.storage.start_privileged(move || {
                    session
                        .try_lock()
                        .map_err(|_| "Busy:Another authorized operation is running")?
                        .call(&request)
                });
            }
            return self.storage.set(key, value);
        }
        if updates::is_setting(key) {
            if self.storage.busy() {
                return Err("Busy:Wait for the storage operation to finish".into());
            }
            return self.updates.set(key, value);
        }
        if remya_settings_camera::is_setting(key) {
            return self.cameras.set(key, value);
        }
        if sound::is_setting(key) {
            return self.sound.set(key, value);
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
        if key == BAR_FOLDED_APPS {
            return self.set_bar_folded_app(value);
        }
        if notifications::IDS.contains(&key) {
            return notifications::set(&self.config, key, value);
        }
        if osd::IDS.contains(&key) {
            return osd::set(&self.config, key, value);
        }
        if matches!(key, BAR_CLOCK_SECONDS | BAR_KEY_PREVIEW) {
            return self.bar_bool_preference(key, Some(value));
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
        self.save_date(state, &keys)
    }
    fn resolve(&mut self, feature: &str, source: &str) -> Result<Value, String> {
        if feature == "power" {
            return self.power.resolve(source);
        }
        if let Some(name) = feature.strip_prefix("cameras:") {
            return self.cameras.resolve(name, source);
        }
        if feature == "network" {
            return self.network.resolve(source);
        }
        if feature == "input" {
            return self.input.resolve(source);
        }
        if feature == "desktop" {
            return self.desktop.resolve(source);
        }
        if feature == "themes" {
            return self.themes.resolve(source);
        }
        if feature == text_size::FEATURE {
            return self.text_size.resolve(source);
        }
        if feature == language::FEATURE {
            return match self.language.resolve(source)? {
                Some(values) => {
                    let written = self.request(Request::Language { values }).map(|_| ());
                    self.language.finish(written)
                }
                None => Ok(self.language.state()),
            };
        }
        if feature == "startup" {
            return self.startup.resolve(source);
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
                    self.save_date(state, &["timezone", "ntp", "time_servers"])?;
                } else {
                    let saved = self.saved.clone();
                    self.set(ZONE, saved["timezone"].as_str().unwrap())?;
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
            if self.input.is_recording() {
                // A closed or crashed recorder must not leave compositor shortcuts suspended.
                let _ = self.input.stop_recording();
            }
            self.gui = None;
        }
    }
    pub fn reap_authorization(&mut self) -> bool {
        let dead = self.privileged.as_ref().is_some_and(|shared| {
            shared
                .try_lock()
                .is_ok_and(|mut session| !session.is_alive())
        });
        if dead {
            self.privileged = None;
            self.auth_error = Some("Privileged service stopped; close and reopen the Settings window to authorize again".into());
        }
        dead
    }
    pub fn shutdown(&mut self) {
        self.power.shutdown();
        if let Some(mut gui) = self.gui.take() {
            let _ = gui.kill();
            let _ = gui.wait();
        }
        self.privileged = None;
        self.updates.shutdown();
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
    fn bar_layout_validates_pills_options_and_requires_the_sidebar() {
        let valid = default_bar_layout();
        assert_eq!(validate_bar_layout(valid.clone()).unwrap(), valid);
        let mut saved_without_marquee = valid.clone();
        saved_without_marquee
            .as_object_mut()
            .unwrap()
            .remove("media_marquee");
        assert_eq!(validate_bar_layout(saved_without_marquee).unwrap(), valid);
        let with = |key: &str, value: Value| {
            let mut layout = valid.clone();
            layout[key] = value;
            layout
        };
        for layout in [
            with("groups", json!([["clock"]])),
            with("groups", json!([["sidebar", "sidebar"]])),
            with("groups", json!([["sidebar"], []])),
            with("groups", json!([["sidebar", "weather"]])),
            with("workspace_count", json!(0)),
            with("workspace_count", json!(11)),
            with("resources", json!([])),
            with("resources", json!(["cpu", "cpu"])),
            with("resources", json!(["disk"])),
            with("window_app_name", json!("yes")),
            with("media_marquee", json!("yes")),
            with("media_marquee", Value::Null),
            with("unknown", json!(true)),
            with("center", json!(4)),
            with("center", json!(-1)),
        ] {
            assert!(validate_bar_layout(layout).is_err());
        }
        let custom = json!({"groups":[["sidebar"],["clock","workspaces"]],"workspace_count":5,"resources":["network","cpu"],"window_app_name":false,"media_marquee":true,"center":1});
        assert_eq!(validate_bar_layout(custom.clone()).unwrap(), custom);
    }
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
    fn tray_fold_state_survives_service_restart() {
        let root = tempfile::tempdir().unwrap();
        let config = root.path().join("config.toml");
        let mut state = State::new(config.clone());
        assert_eq!(
            state.execute("Get", &[BAR_FOLDED_APPS.into()]).unwrap()["value"],
            json!([])
        );
        assert_eq!(
            state
                .execute(
                    "Set",
                    &[
                        BAR_FOLDED_APPS.into(),
                        json!({"id":"my-app","folded":true}).to_string()
                    ]
                )
                .unwrap()["value"],
            json!(["my-app"])
        );
        assert_eq!(
            State::new(config)
                .execute("Get", &[BAR_FOLDED_APPS.into()])
                .unwrap()["value"],
            json!(["my-app"])
        );
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

fn power_history_path(config: &std::path::Path) -> PathBuf {
    if config
        .file_name()
        .is_some_and(|name| name == "config.local.toml")
    {
        return config.with_file_name("power.sqlite3");
    }
    let root = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    root.join("remya/settings/power.sqlite3")
}
