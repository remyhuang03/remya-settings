//! XDG default handlers. GIO owns association lookup and writes; Settings owns reconciliation.
use gio::prelude::*;
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

pub const TYPE_SEARCH: &str = "defaults.b131ac5a";
pub const APP_SEARCH: &str = "defaults.897fdfef";
pub const IDS: [&str; 10] = [
    TYPE_SEARCH,
    APP_SEARCH,
    "defaults.ccac113f",
    "defaults.3adc9929",
    "defaults.c0b97974",
    "defaults.e7fe6be6",
    "defaults.audio",
    "defaults.text",
    "defaults.pdf",
    "defaults.file-manager",
];
pub const GROUPS: [(&str, &str, &[&str]); 8] = [
    (
        IDS[2],
        "Web browser",
        &["x-scheme-handler/http", "x-scheme-handler/https"],
    ),
    (IDS[3], "Mail", &["x-scheme-handler/mailto"]),
    (
        IDS[4],
        "Photos",
        &[
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/avif",
            "image/svg+xml",
        ],
    ),
    (
        IDS[5],
        "Video",
        &["video/mp4", "video/webm", "video/x-matroska", "video/ogg"],
    ),
    (
        IDS[6],
        "Audio",
        &[
            "audio/mpeg",
            "audio/flac",
            "audio/ogg",
            "audio/x-wav",
            "audio/mp4",
        ],
    ),
    (IDS[7], "Text editor", &["text/plain"]),
    (IDS[8], "PDF", &["application/pdf"]),
    (IDS[9], "File manager", &["inode/directory"]),
];
type Defaults = BTreeMap<String, String>;
type Writer = fn(&Path, &[u8]) -> Result<(), String>;
fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

fn validate_type(value: &str) -> Result<(), String> {
    if value.len() > 255
        || !value
            .split_once('/')
            .is_some_and(|(a, b)| !a.is_empty() && !b.is_empty() && !b.contains('/'))
        || !value
            .bytes()
            .all(|b| b.is_ascii_alphabetic() || b.is_ascii_digit() || b"!#$&^_.+-/".contains(&b))
    {
        return Err(invalid(
            "Use a registered MIME type or x-scheme-handler/<scheme>",
        ));
    }
    Ok(())
}
fn validate_desktop(value: &str) -> Result<(), String> {
    if value.len() > 255
        || !value.ends_with(".desktop")
        || value.starts_with('.')
        || value.contains(['/', '\\'])
        || value.chars().any(char::is_control)
    {
        return Err(invalid("Use an installed desktop application ID"));
    }
    Ok(())
}

pub use remya_settings_applications::Application;
pub trait Desktop: Send {
    fn applications(&self) -> Result<Vec<Application>, String>;
    fn handler(&self, _id: &str, _mime: &str) -> Option<Application> {
        None
    }
    fn types(&self) -> BTreeSet<String>;
    fn default(&self, mime: &str) -> Result<String, String>;
    fn set(&self, mime: &str, application: &str) -> Result<(), String>;
}
pub struct RealDesktop;

// GIO's read API has no error channel. Validate readable association files before accepting unset values.
fn check_association_files() -> Result<(), String> {
    let dirs = xdg::BaseDirectories::new();
    let desktops = std::env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .split(':')
        .map(str::to_ascii_lowercase)
        .filter(|s| {
            !s.is_empty()
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
        })
        .collect::<Vec<_>>();
    let mut roots = dirs.get_config_dirs();
    if let Some(home) = dirs.get_config_home() {
        roots.push(home);
    }
    roots.extend(
        dirs.get_data_dirs()
            .into_iter()
            .map(|p| p.join("applications")),
    );
    if let Some(home) = dirs.get_data_home() {
        roots.push(home.join("applications"));
    }
    for root in roots {
        for filename in std::iter::once("mimeapps.list".into())
            .chain(desktops.iter().map(|d| format!("{d}-mimeapps.list")))
        {
            let path = root.join(filename);
            match fs::read_to_string(&path) {
                Ok(text) => gio::glib::KeyFile::new()
                    .load_from_data(&text, gio::glib::KeyFileFlags::NONE)
                    .map_err(|e| format!("Cannot parse {}: {e}", path.display()))?,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
                Err(e) => return Err(format!("Cannot read {}: {e}", path.display())),
            }
        }
    }
    Ok(())
}
impl Desktop for RealDesktop {
    fn applications(&self) -> Result<Vec<Application>, String> {
        check_association_files()?;
        let apps = remya_settings_applications::desktop_applications()
            .into_iter()
            .filter(|a| validate_desktop(&a.id).is_ok())
            .map(|mut a| {
                a.types.retain(|s| validate_type(s).is_ok());
                a
            })
            .collect();
        Ok(apps)
    }
    fn handler(&self, id: &str, mime: &str) -> Option<Application> {
        let app = gio::AppInfo::default_for_type(mime, mime.starts_with("x-scheme-handler/"))?;
        if app.id().as_deref() != Some(id) {
            return None;
        }
        Some(Application {
            id: id.into(),
            name: app.display_name().to_string(),
            icon: app
                .icon()
                .and_then(|i| i.to_string())
                .map(|s| s.to_string()),
            types: app
                .supported_types()
                .into_iter()
                .map(|s| s.to_string())
                .collect(),
        })
    }
    fn types(&self) -> BTreeSet<String> {
        gio::content_types_get_registered()
            .into_iter()
            .map(|s| s.to_string())
            .filter(|s| validate_type(s).is_ok())
            .collect()
    }
    fn default(&self, mime: &str) -> Result<String, String> {
        Ok(
            gio::AppInfo::default_for_type(mime, mime.starts_with("x-scheme-handler/"))
                .and_then(|a| a.id())
                .map(|s| s.to_string())
                .unwrap_or_default(),
        )
    }
    fn set(&self, mime: &str, application: &str) -> Result<(), String> {
        gio::DesktopAppInfo::new(application)
            .ok_or_else(|| invalid("Application is no longer installed"))?
            .set_as_default_for_type(mime)
            .map_err(|e| e.to_string())
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u8,
    defaults: Defaults,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Change {
    application: String,
    #[serde(default)]
    types: Vec<String>,
}

fn extension_map() -> BTreeMap<String, BTreeSet<String>> {
    let mut result = BTreeMap::<String, BTreeSet<String>>::new();
    for dir in gio::content_type_get_mime_dirs() {
        if let Ok(text) = fs::read_to_string(Path::new(dir.as_str()).join("globs2")) {
            for line in text.lines().filter(|l| !l.starts_with('#')) {
                let fields = line.split(':').collect::<Vec<_>>();
                if fields.len() >= 3
                    && let Some(ext) = fields[2].strip_prefix("*.")
                    && !ext.is_empty()
                    && ext
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"._+-".contains(&b))
                {
                    result
                        .entry(fields[1].into())
                        .or_default()
                        .insert(format!(".{ext}"));
                }
            }
        }
    }
    result
}

pub struct DefaultApps<D: Desktop> {
    desktop: D,
    path: PathBuf,
    writer: Writer,
    saved: Option<Defaults>,
    system: Defaults,
    apps: Vec<Application>,
    handlers: BTreeMap<String, Application>,
    extensions: BTreeMap<String, BTreeSet<String>>,
    types: BTreeSet<String>,
    read_error: Option<String>,
    operation_error: Option<String>,
}
impl<D: Desktop> DefaultApps<D> {
    pub fn new(desktop: D, path: PathBuf) -> Self {
        Self {
            desktop,
            path,
            writer: atomic_write,
            saved: None,
            system: Defaults::new(),
            apps: vec![],
            handlers: BTreeMap::new(),
            extensions: BTreeMap::new(),
            types: BTreeSet::new(),
            read_error: None,
            operation_error: None,
        }
    }
    fn persist(&self, defaults: &Defaults) -> Result<(), String> {
        let text = toml::to_string(&Config {
            version: 1,
            defaults: defaults.clone(),
        })
        .map_err(|e| e.to_string())?;
        (self.writer)(&self.path, text.as_bytes())
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = (|| {
            let apps = self.desktop.applications()?;
            let loaded = match fs::read_to_string(&self.path) {
                Ok(text) => {
                    let c: Config = toml::from_str(&text)
                        .map_err(|e| format!("Invalid default apps configuration: {e}"))?;
                    if c.version != 1 {
                        return Err("Unsupported default apps configuration version".into());
                    }
                    for (t, a) in &c.defaults {
                        validate_type(t)?;
                        if !a.is_empty() {
                            validate_desktop(a)?;
                        }
                    }
                    Some(c.defaults)
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e.to_string()),
            };
            let mut types = self.desktop.types();
            types.extend(apps.iter().flat_map(|a| a.types.iter().cloned()));
            types.extend(
                GROUPS
                    .iter()
                    .flat_map(|(_, _, ts)| ts.iter().map(|s| s.to_string())),
            );
            types.extend(loaded.iter().flat_map(|m| m.keys().cloned()));
            let system = types
                .iter()
                .map(|t| Ok((t.clone(), self.desktop.default(t)?)))
                .collect::<Result<Defaults, String>>()?;
            self.handlers = apps.iter().map(|a| (a.id.clone(), a.clone())).collect();
            for (mime, id) in &system {
                if !id.is_empty()
                    && !self.handlers.contains_key(id)
                    && let Some(app) = self.desktop.handler(id, mime)
                {
                    self.handlers.insert(id.clone(), app);
                }
            }
            self.extensions = extension_map();
            self.apps = apps;
            self.types = types;
            self.system = system;
            if let Some(saved) = loaded {
                self.saved = Some(saved);
            } else {
                self.persist(&self.system)?;
                self.saved = Some(self.system.clone());
            }
            Ok(())
        })();
        self.read_error = result.as_ref().err().cloned();
        result
    }
    fn conflict(&self) -> bool {
        self.saved
            .as_ref()
            .is_some_and(|s| s.iter().any(|(t, a)| self.system.get(t) != Some(a)))
    }
    fn group_types(&self, id: &str, fallback: &[&str]) -> BTreeSet<String> {
        let prefix = match id {
            "defaults.c0b97974" => Some("image/"),
            "defaults.e7fe6be6" => Some("video/"),
            "defaults.audio" => Some("audio/"),
            _ => None,
        };
        if let Some(prefix) = prefix {
            self.types
                .iter()
                .filter(|t| t.starts_with(prefix))
                .cloned()
                .collect()
        } else {
            fallback.iter().map(|s| s.to_string()).collect()
        }
    }
    pub fn state(&self) -> Value {
        json!({"api_version":1,"initialized":self.saved.is_some(),"writable":self.saved.is_some() && self.read_error.is_none(),"saved":self.saved,"system":self.system,"handlers":self.handlers,"extensions":self.extensions,"conflict":self.conflict(),"error":self.read_error.as_ref().or(self.operation_error.as_ref()),"groups":GROUPS.iter().map(|(id,title,types)|json!({"id":id,"title":title,"types":self.group_types(id,types)})).collect::<Vec<_>>()})
    }
    pub fn applications(&mut self, query: &str) -> Result<Value, String> {
        self.refresh()?;
        let q = query.to_lowercase();
        Ok(
            json!({"applications":self.apps.iter().filter(|a|a.name.to_lowercase().contains(&q)||a.id.to_lowercase().contains(&q)).collect::<Vec<_>>()}),
        )
    }
    pub fn search(&mut self, query: &str) -> Result<Value, String> {
        self.refresh()?;
        let q = query.trim().to_lowercase();
        if q.len() > 255 {
            return Err(invalid("Search is too long"));
        }
        let extension = q.strip_prefix('.');
        let mut matches = BTreeSet::new();
        if let Some(ext) = extension {
            for dir in gio::content_type_get_mime_dirs() {
                if let Ok(text) = fs::read_to_string(Path::new(dir.as_str()).join("globs2")) {
                    for line in text.lines().filter(|l| !l.starts_with('#')) {
                        let fields = line.split(':').collect::<Vec<_>>();
                        if fields.len() >= 3 && fields[2] == format!("*.{ext}") {
                            matches.insert(fields[1].to_string());
                        }
                    }
                }
            }
        }
        Ok(
            json!({"types":self.types.iter().filter(|t|t.to_lowercase().contains(&q)||matches.contains(*t)).map(|t|json!({"type":t,"application":self.system[t]})).collect::<Vec<_>>()}),
        )
    }
    pub fn candidates(&mut self, types: &[String]) -> Result<Value, String> {
        self.refresh()?;
        for t in types {
            validate_type(t)?;
        }
        Ok(
            json!({"applications":self.apps.iter().filter(|a|types.iter().any(|t|a.types.contains(t))).collect::<Vec<_>>()}),
        )
    }
    pub fn set(&mut self, id: &str, payload: &str) -> Result<Value, String> {
        let result = (|| {
            let change: Change = serde_json::from_str(payload)
                .map_err(|e| invalid(&format!("Expected application and types: {e}")))?;
            validate_desktop(&change.application)?;
            self.refresh()?;
            if self.conflict() {
                return Err(
                    "Conflict:Resolve saved and system default apps before changing associations"
                        .into(),
                );
            }
            let app = self
                .apps
                .iter()
                .find(|a| a.id == change.application)
                .ok_or_else(|| invalid("Unknown application"))?;
            let types: BTreeSet<String> =
                if let Some((_, _, types)) = GROUPS.iter().find(|(key, _, _)| *key == id) {
                    if !change.types.is_empty() {
                        return Err(invalid("Shortcut types are fixed; omit types"));
                    }
                    let types = self
                        .group_types(id, types)
                        .into_iter()
                        .filter(|t| app.types.contains(t))
                        .collect::<BTreeSet<_>>();
                    if id == IDS[2] && types.len() != 2 {
                        return Err(invalid("Browser must support both HTTP and HTTPS"));
                    }
                    types
                } else if [TYPE_SEARCH, APP_SEARCH].contains(&id) {
                    change.types.into_iter().collect()
                } else {
                    return Err(invalid("Unknown default apps setting"));
                };
            if types.is_empty() || types.len() > 256 {
                return Err(invalid("Select between 1 and 256 supported types"));
            }
            for t in &types {
                validate_type(t)?;
                if !self.types.contains(t) || !app.types.contains(t) {
                    return Err(invalid(
                        "Application does not declare support for every selected type",
                    ));
                }
            }
            let targets = types
                .into_iter()
                .map(|t| (t, change.application.clone()))
                .collect();
            self.apply(&targets)?;
            let mut saved = self.saved.clone().ok_or("Default apps are uninitialized")?;
            saved.extend(targets);
            self.persist(&saved)?;
            self.saved = Some(saved);
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        result.map(|()| self.state())
    }
    fn apply(&mut self, targets: &Defaults) -> Result<(), String> {
        let mut changed = Vec::<(String, String)>::new();
        for (t, a) in targets {
            if a.is_empty() {
                return Err("Cannot apply an unset saved association; adopt system configuration or choose an application".into());
            }
            if !self
                .apps
                .iter()
                .any(|app| app.id == *a && app.types.contains(t))
            {
                return Err(format!(
                    "Saved application missing or no longer supports {t}: {a}"
                ));
            }
        }
        let result = (|| {
            for (t, a) in targets {
                let before = self.desktop.default(t)?;
                if self.system.get(t) != Some(&before) {
                    return Err(format!(
                        "Conflict:{t} changed externally; refresh before applying"
                    ));
                }
                if before == *a {
                    continue;
                }
                changed.push((t.clone(), before));
                self.desktop.set(t, a)?;
                if self.desktop.default(t)? != *a {
                    return Err(format!("Default handler readback differs for {t}"));
                }
            }
            Ok(())
        })();
        if let Err(error) = result {
            let mut failures = vec![];
            for (t, before) in changed.into_iter().rev() {
                if self.desktop.default(&t).ok().as_ref() == Some(&before) {
                    continue;
                }
                if before.is_empty() {
                    failures.push(format!(
                        "{t}: previously unset; cannot safely reset other associations"
                    ));
                } else if let Err(e) = self.desktop.set(&t, &before).and_then(|()| {
                    if self.desktop.default(&t)? == before {
                        Ok(())
                    } else {
                        Err("rollback readback differs".into())
                    }
                }) {
                    failures.push(format!("{t}: {e}"));
                }
            }
            let _ = self.refresh();
            return Err(format!(
                "{error}{}",
                if failures.is_empty() {
                    String::new()
                } else {
                    format!("; incomplete rollback: {}", failures.join(", "))
                }
            ));
        }
        self.refresh()?;
        Ok(())
    }
    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let result = (|| {
            self.refresh()?;
            match source {
                "system" => {
                    self.persist(&self.system)?;
                    self.saved = Some(self.system.clone());
                }
                "settings" => {
                    let targets: Defaults = self
                        .saved
                        .as_ref()
                        .ok_or("Default apps are uninitialized")?
                        .iter()
                        .filter(|(t, a)| self.system.get(*t) != Some(*a))
                        .map(|(t, a)| (t.clone(), a.clone()))
                        .collect();
                    self.apply(&targets)?;
                }
                _ => return Err(invalid("Unknown resolution")),
            }
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        result.map(|()| self.state())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    #[derive(Default)]
    struct Machine {
        values: Defaults,
        fail_read: bool,
        fail_type: String,
        wrong_readback: bool,
        writes: usize,
    }
    struct Fake(Arc<Mutex<Machine>>);
    impl Desktop for Fake {
        fn applications(&self) -> Result<Vec<Application>, String> {
            if self.0.lock().unwrap().fail_read {
                return Err("offline".into());
            }
            Ok(["a.desktop", "b.desktop"]
                .into_iter()
                .map(|id| Application {
                    id: id.into(),
                    name: id.into(),
                    icon: None,
                    types: GROUPS
                        .iter()
                        .flat_map(|(_, _, ts)| ts.iter().map(|s| s.to_string()))
                        .collect(),
                })
                .collect())
        }
        fn types(&self) -> BTreeSet<String> {
            BTreeSet::new()
        }
        fn default(&self, t: &str) -> Result<String, String> {
            Ok(self
                .0
                .lock()
                .unwrap()
                .values
                .get(t)
                .cloned()
                .unwrap_or_default())
        }
        fn set(&self, t: &str, a: &str) -> Result<(), String> {
            let mut m = self.0.lock().unwrap();
            m.writes += 1;
            if m.fail_type == t {
                return Err("denied".into());
            }
            if !m.wrong_readback {
                m.values.insert(t.into(), a.into());
            }
            Ok(())
        }
    }
    fn payload(a: &str) -> String {
        json!({"application":a}).to_string()
    }
    fn denied(_: &Path, _: &[u8]) -> Result<(), String> {
        Err("read-only configuration".into())
    }
    #[test]
    fn initializes_from_system_and_resolves_both_directions_without_losing_failures() {
        assert!(validate_type("audio/AMR").is_ok());
        let extensions = extension_map();
        assert!(
            extensions
                .get("image/jpeg")
                .is_some_and(|exts| exts.contains(".jpg") && exts.contains(".jpeg"))
        );
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("apps.toml");
        let machine = Arc::new(Mutex::new(Machine::default()));
        let mut manager = DefaultApps::new(Fake(machine.clone()), file.clone());
        machine.lock().unwrap().fail_read = true;
        assert!(manager.refresh().is_err());
        assert!(!file.exists());
        machine.lock().unwrap().fail_read = false;
        machine
            .lock()
            .unwrap()
            .values
            .insert("text/plain".into(), "a.desktop".into());
        manager.refresh().unwrap();
        assert_eq!(machine.lock().unwrap().writes, 0);
        assert_eq!(manager.state()["saved"]["text/plain"], "a.desktop");
        machine
            .lock()
            .unwrap()
            .values
            .insert("text/plain".into(), "b.desktop".into());
        manager.refresh().unwrap();
        assert!(manager.conflict());
        assert!(
            manager
                .set(IDS[7], &payload("a.desktop"))
                .unwrap_err()
                .contains("Conflict")
        );
        manager.resolve("settings").unwrap();
        assert!(!manager.conflict());
        assert_eq!(machine.lock().unwrap().values["text/plain"], "a.desktop");
        machine
            .lock()
            .unwrap()
            .values
            .insert("text/plain".into(), "b.desktop".into());
        manager.resolve("system").unwrap();
        assert_eq!(manager.state()["saved"]["text/plain"], "b.desktop");
        manager.writer = denied;
        assert!(manager.set(IDS[7], &payload("a.desktop")).is_err());
        assert!(manager.conflict());
        assert_eq!(manager.state()["saved"]["text/plain"], "b.desktop");
        assert!(
            manager.state()["error"]
                .as_str()
                .unwrap()
                .contains("read-only")
        );
        assert!(manager.resolve("system").is_err());
        assert!(manager.conflict());
        manager.writer = atomic_write;
        manager.resolve("system").unwrap();
        let valid = fs::read_to_string(&file).unwrap();
        fs::write(&file, "invalid [").unwrap();
        assert!(manager.refresh().is_err());
        assert!(!manager.state()["writable"].as_bool().unwrap());
        assert_eq!(manager.state()["saved"]["text/plain"], "a.desktop");
        fs::write(file, valid).unwrap();
        manager.refresh().unwrap();
        assert!(
            manager
                .set(
                    TYPE_SEARCH,
                    r#"{"application":"../../evil.desktop","types":["text/plain"]}"#
                )
                .is_err()
        );
        assert!(
            manager
                .set(
                    TYPE_SEARCH,
                    r#"{"application":"a.desktop","types":["invalid"]}"#
                )
                .is_err()
        );
        assert!(
            manager
                .set(
                    TYPE_SEARCH,
                    r#"{"application":"a.desktop","types":["application/unknown"]}"#
                )
                .is_err()
        );
        assert!(
            manager
                .set(
                    IDS[2],
                    r#"{"application":"a.desktop","types":["text/plain"]}"#
                )
                .is_err()
        );
    }
    #[test]
    fn batch_failure_restores_known_defaults_and_reports_unset_and_wrong_readback() {
        let dir = tempfile::tempdir().unwrap();
        let machine = Arc::new(Mutex::new(Machine::default()));
        for t in ["x-scheme-handler/http", "x-scheme-handler/https"] {
            machine
                .lock()
                .unwrap()
                .values
                .insert(t.into(), "a.desktop".into());
        }
        let mut manager = DefaultApps::new(Fake(machine.clone()), dir.path().join("apps.toml"));
        manager.refresh().unwrap();
        machine.lock().unwrap().fail_type = "x-scheme-handler/https".into();
        assert!(
            manager
                .set(IDS[2], &payload("b.desktop"))
                .unwrap_err()
                .contains("denied")
        );
        assert_eq!(
            machine.lock().unwrap().values["x-scheme-handler/http"],
            "a.desktop"
        );
        assert!(!manager.conflict());
        machine
            .lock()
            .unwrap()
            .values
            .remove("x-scheme-handler/http");
        manager.resolve("system").unwrap();
        assert!(
            manager
                .set(IDS[2], &payload("b.desktop"))
                .unwrap_err()
                .contains("incomplete rollback")
        );
        assert!(manager.conflict());
        assert_eq!(manager.state()["saved"]["x-scheme-handler/http"], "");
        assert!(manager.resolve("settings").unwrap_err().contains("unset"));
        assert!(manager.conflict());
        manager.resolve("system").unwrap();
        machine.lock().unwrap().fail_type.clear();
        machine.lock().unwrap().wrong_readback = true;
        assert!(
            manager
                .set(IDS[7], &payload("a.desktop"))
                .unwrap_err()
                .contains("readback")
        );
        assert_eq!(manager.state()["saved"]["text/plain"], "");
    }
}
