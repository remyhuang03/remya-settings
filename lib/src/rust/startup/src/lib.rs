//! XDG autostart overrides and enabled-state reconciliation for UWSM sessions.
mod systemd;
use gio::glib::{self, KeyFile, KeyFileFlags};
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};
pub use systemd::{RealSystemd, Runtime, Systemd, Unit};

pub const IDS: [&str; 4] = [
    "startup.apps",
    "startup.add-app",
    "startup.add-command",
    "startup.remove",
];
const GROUP: &str = "Desktop Entry";
type Enabled = BTreeMap<String, bool>;
type Writer = fn(&Path, &[u8]) -> Result<(), String>;
type ApplicationFile = Box<dyn Fn(&str) -> Option<PathBuf> + Send>;
fn invalid(message: impl std::fmt::Display) -> String {
    format!("InvalidArgument:{message}")
}
pub fn validate_id(id: &str) -> Result<(), String> {
    if !id.ends_with(".desktop")
        || id.len() > 255
        || id.starts_with('.')
        || id.contains(['/', '\\'])
        || id.chars().any(char::is_control)
    {
        return Err(invalid("Use an autostart desktop file name"));
    }
    Ok(())
}

pub struct Directories {
    pub user: PathBuf,
    pub system: Vec<PathBuf>,
    pub desktops: Vec<String>,
    pub path: Vec<PathBuf>,
}
impl Directories {
    pub fn detect() -> Result<Self, String> {
        let dirs = xdg::BaseDirectories::new();
        Ok(Self {
            user: dirs
                .get_config_home()
                .filter(|p| p.is_absolute())
                .ok_or("Absolute HOME required for autostart")?
                .join("autostart"),
            system: dirs
                .get_config_dirs()
                .into_iter()
                .map(|p| p.join("autostart"))
                .collect(),
            desktops: std::env::var("XDG_CURRENT_DESKTOP")
                .unwrap_or_default()
                .split(':')
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .collect(),
            path: std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).collect(),
        })
    }
    fn executable(&self, program: &str) -> bool {
        let executable = |p: &Path| p.is_file() && glib::find_program_in_path(p).is_some();
        let p = Path::new(program);
        if p.is_absolute() {
            executable(p)
        } else if program.contains('/') {
            false
        } else {
            self.path.iter().any(|dir| executable(&dir.join(p)))
        }
    }
    fn files(&self) -> Result<BTreeMap<String, PathBuf>, String> {
        let mut files = BTreeMap::new();
        for root in std::iter::once(&self.user).chain(&self.system) {
            let entries = match fs::read_dir(root) {
                Ok(entries) => entries,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                Err(e) => return Err(format!("Cannot read {}: {e}", root.display())),
            };
            for entry in entries {
                let entry = entry.map_err(|e| e.to_string())?;
                if let Some(id) = entry
                    .file_name()
                    .to_str()
                    .filter(|id| id.ends_with(".desktop"))
                {
                    files.entry(id.to_owned()).or_insert(entry.path());
                }
            }
        }
        Ok(files)
    }
    fn system_file(&self, id: &str) -> Option<PathBuf> {
        self.system
            .iter()
            .map(|dir| dir.join(id))
            .find(|p| p.try_exists().unwrap_or(true))
    }
}
fn load(path: &Path) -> Result<KeyFile, String> {
    let key = KeyFile::new();
    key.load_from_file(
        path,
        KeyFileFlags::KEEP_COMMENTS | KeyFileFlags::KEEP_TRANSLATIONS,
    )
    .map_err(|e| format!("Cannot parse {}: {e}", path.display()))?;
    Ok(key)
}
fn string(key: &KeyFile, name: &str) -> String {
    key.string(GROUP, name)
        .map(|s| s.to_string())
        .unwrap_or_default()
}
fn boolean(key: &KeyFile, name: &str) -> Result<bool, String> {
    if !key.has_key(GROUP, name).map_err(|e| e.to_string())? {
        return Ok(false);
    }
    key.boolean(GROUP, name).map_err(|e| e.to_string())
}
#[derive(Clone, Serialize)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub comment: String,
    pub icon: Option<String>,
    pub exec: String,
    pub origin: &'static str,
    pub enabled: bool,
    pub removable: bool,
    pub status: Option<String>,
    #[serde(skip)]
    source: PathBuf,
}
fn entry(dirs: &Directories, id: &str, source: PathBuf) -> Result<Option<Entry>, String> {
    validate_id(id)?;
    let user = load(&source)?;
    let key = if source == dirs.user.join(id)
        && user.boolean(GROUP, "Hidden").unwrap_or(false)
        && let Some(system) = dirs.system_file(id)
    {
        let merged = load(&system)?;
        for group in user.groups() {
            for name in user.keys(&group).map_err(|e| e.to_string())? {
                let value = user.value(&group, &name).map_err(|e| e.to_string())?;
                merged.set_value(&group, &name, &value);
            }
        }
        merged
    } else {
        user
    };
    if string(&key, "Type") != "Application" {
        return Ok(None);
    }
    let enabled = !boolean(&key, "Hidden")?;
    let includes = |name: &str| -> Result<Option<bool>, String> {
        if !key.has_key(GROUP, name).map_err(|e| e.to_string())? {
            return Ok(None);
        }
        let list = key.string_list(GROUP, name).map_err(|e| e.to_string())?;
        Ok(Some(
            list.iter()
                .any(|s| dirs.desktops.iter().any(|d| s.as_str() == d)),
        ))
    };
    let try_exec = string(&key, "TryExec");
    if includes("OnlyShowIn")? == Some(false)
        || includes("NotShowIn")? == Some(true)
        || (!try_exec.is_empty() && !dirs.executable(&try_exec))
        || key
            .has_key(GROUP, "X-GNOME-Autostart-Phase")
            .map_err(|e| e.to_string())?
        || boolean(&key, "X-systemd-skip")?
    {
        return Ok(None);
    }
    let system = dirs.system_file(id).is_some();
    let localized = |name| {
        key.locale_string(GROUP, name, None)
            .map(|s| s.to_string())
            .unwrap_or_default()
    };
    let name = localized("Name");
    let icon = string(&key, "Icon");
    Ok(Some(Entry {
        id: id.into(),
        name: if name.is_empty() { id.into() } else { name },
        comment: localized("Comment"),
        icon: (!icon.is_empty()).then_some(icon),
        exec: string(&key, "Exec"),
        origin: if system { "system" } else { "user" },
        enabled,
        removable: !system,
        status: None,
        source,
    }))
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    version: u8,
    enabled: Enabled,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Toggle {
    id: String,
    enabled: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AddApp {
    application: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AddCommand {
    name: String,
    command: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Remove {
    id: String,
}
fn payload<T: serde::de::DeserializeOwned>(text: &str) -> Result<T, String> {
    serde_json::from_str(text).map_err(invalid)
}
fn application_file(id: &str) -> Option<PathBuf> {
    gio::DesktopAppInfo::new(id)?.filename()
}

pub struct Startup<S: Systemd> {
    dirs: Result<Directories, String>,
    systemd: S,
    config: PathBuf,
    writer: Writer,
    application_file: ApplicationFile,
    saved: Option<Enabled>,
    system: Enabled,
    entries: Vec<Entry>,
    session_autostart: Option<bool>,
    status_error: Option<String>,
    skipped_invalid: usize,
    read_error: Option<String>,
    operation_error: Option<String>,
}
impl<S: Systemd> Startup<S> {
    pub fn new(systemd: S, dirs: Result<Directories, String>, config: PathBuf) -> Self {
        Self {
            systemd,
            dirs,
            config,
            writer: atomic_write,
            application_file: Box::new(application_file),
            saved: None,
            system: Enabled::new(),
            entries: vec![],
            session_autostart: None,
            status_error: None,
            skipped_invalid: 0,
            read_error: None,
            operation_error: None,
        }
    }
    fn dirs(&self) -> Result<&Directories, String> {
        self.dirs.as_ref().map_err(Clone::clone)
    }
    fn discover(&mut self) -> Result<(), String> {
        let dirs = self.dirs()?;
        let files = dirs.files()?;
        let mut entries = vec![];
        let mut skipped = 0;
        for (id, path) in files {
            match entry(dirs, &id, path) {
                Ok(Some(entry)) => entries.push(entry),
                Ok(None) => (),
                Err(_) => skipped += 1,
            }
        }
        entries.sort_by_cached_key(|e| (e.name.to_lowercase(), e.id.clone()));
        match self.systemd.read() {
            Ok(runtime) => {
                for entry in &mut entries {
                    entry.status = Some(
                        runtime
                            .units
                            .iter()
                            .find(|u| u.source == entry.source)
                            .map_or("not-started", Unit::status)
                            .into(),
                    );
                }
                self.session_autostart = Some(runtime.session_autostart);
                self.status_error = None;
            }
            Err(error) => {
                self.session_autostart = None;
                self.status_error = Some(error);
            }
        }
        self.system = entries.iter().map(|e| (e.id.clone(), e.enabled)).collect();
        self.entries = entries;
        self.skipped_invalid = skipped;
        Ok(())
    }
    fn persist(&self, enabled: &Enabled) -> Result<(), String> {
        let text = toml::to_string(&Config {
            version: 1,
            enabled: enabled.clone(),
        })
        .map_err(|e| e.to_string())?;
        (self.writer)(&self.config, text.as_bytes())
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        let result = (|| {
            self.discover()?;
            let loaded = match fs::read_to_string(&self.config) {
                Ok(text) => {
                    let c: Config = toml::from_str(&text)
                        .map_err(|e| format!("Invalid startup configuration: {e}"))?;
                    if c.version != 1 {
                        return Err("Unsupported startup configuration version".into());
                    }
                    for id in c.enabled.keys() {
                        validate_id(id)?;
                    }
                    Some(c.enabled)
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(format!("Cannot read startup configuration: {e}")),
            };
            let adopted = self
                .system
                .iter()
                .map(|(id, system)| {
                    (
                        id.clone(),
                        loaded
                            .as_ref()
                            .and_then(|m| m.get(id))
                            .copied()
                            .unwrap_or(*system),
                    )
                })
                .collect();
            if loaded.as_ref() != Some(&adopted) {
                self.persist(&adopted)?;
            }
            self.saved = Some(adopted);
            Ok(())
        })();
        self.read_error = result.as_ref().err().cloned();
        result
    }
    fn conflicts(&self) -> Vec<Value> {
        self.entries
            .iter()
            .filter_map(|e| {
                let saved = self.saved.as_ref()?.get(&e.id)?;
                (*saved != e.enabled)
                    .then(|| json!({"id":e.id,"name":e.name,"saved":saved,"system":e.enabled}))
            })
            .collect()
    }
    pub fn state(&self) -> Value {
        let conflicts = self.conflicts();
        json!({"api_version":1,"initialized":self.saved.is_some(),
            "writable":self.saved.is_some() && self.read_error.is_none(), "entries":self.entries,
            "saved":self.saved,"system":self.system,"conflict":!conflicts.is_empty(),"conflicts":conflicts,
            "session_autostart":self.session_autostart,"status_error":self.status_error,
            "skipped_invalid":self.skipped_invalid,"error":self.read_error.as_ref().or(self.operation_error.as_ref())})
    }
    pub fn candidates(&mut self, query: &str) -> Result<Value, String> {
        self.refresh()?;
        let query = query.to_lowercase();
        Ok(
            json!({"applications":remya_settings_applications::desktop_applications().into_iter()
            .filter(|a| validate_id(&a.id).is_ok() && !self.system.contains_key(&a.id)
                && (a.name.to_lowercase().contains(&query) || a.id.to_lowercase().contains(&query)))
            .map(|a| json!({"id":a.id,"name":a.name,"icon":a.icon})).collect::<Vec<_>>()}),
        )
    }
    // atomic_write follows symlinks; autostart overrides must never change their targets.
    fn user_path(&self, id: &str) -> Result<PathBuf, String> {
        validate_id(id)?;
        let dir = &self.dirs()?.user;
        let path = dir.join(id);
        if dir.is_symlink() || path.is_symlink() {
            return Err(
                "Unavailable:Refusing to write a symlinked autostart directory or entry".into(),
            );
        }
        Ok(path)
    }
    fn write_entry(&self, id: &str, key: &KeyFile) -> Result<(), String> {
        let path = self.user_path(id)?;
        (self.writer)(&path, key.to_data().as_bytes())?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o644)).map_err(|e| e.to_string())
    }
    fn verify(&mut self, id: &str, enabled: Option<bool>) -> Result<(), String> {
        self.discover()?;
        if self.system.get(id).copied() != enabled {
            return Err(format!("Startup readback did not match {id}"));
        }
        Ok(())
    }
    fn set_enabled(&mut self, id: &str, enabled: bool) -> Result<(), String> {
        let path = self.user_path(id)?;
        if !self.system.contains_key(id) {
            return Err(invalid("Unknown startup entry"));
        }
        let system = self.dirs()?.system_file(id);
        let user_exists = path.try_exists().map_err(|e| e.to_string())?;
        let key = load(if user_exists {
            &path
        } else {
            system.as_deref().ok_or("Startup entry disappeared")?
        })?;
        if enabled
            && user_exists
            && system.is_some()
            && !key.has_key(GROUP, "Exec").map_err(|e| e.to_string())?
        {
            fs::remove_file(&path).map_err(|e| e.to_string())?;
            return self.verify(id, Some(true));
        }
        if enabled {
            let _ = key.remove_key(GROUP, "Hidden");
        } else {
            key.set_boolean(GROUP, "Hidden", true);
        }
        if key
            .has_key(GROUP, "X-GNOME-Autostart-enabled")
            .map_err(|e| e.to_string())?
        {
            key.set_boolean(GROUP, "X-GNOME-Autostart-enabled", enabled);
        }
        if enabled
            && let Some(system) = &system
            && key.to_data() == load(system)?.to_data()
        {
            if user_exists {
                fs::remove_file(&path).map_err(|e| e.to_string())?;
            }
        } else {
            self.write_entry(id, &key)?;
        }
        self.verify(id, Some(enabled))
    }
    fn add_entry(&mut self, id: &str, key: &KeyFile) -> Result<(), String> {
        self.write_entry(id, key)?;
        if let Err(error) = self.verify(id, Some(true)) {
            let path = self.user_path(id)?;
            if let Err(cleanup) = fs::remove_file(&path)
                && cleanup.kind() != std::io::ErrorKind::NotFound
            {
                return Err(format!(
                    "{error}; Cannot remove {}: {cleanup}",
                    path.display()
                ));
            }
            self.discover()?;
            return Err(error);
        }
        Ok(())
    }
    fn add_application(&mut self, id: &str) -> Result<(), String> {
        validate_id(id)?;
        if self.system.contains_key(id) {
            return Err(invalid("Startup entry already exists; enable it instead"));
        }
        if self.dirs()?.files()?.contains_key(id) {
            return Err(invalid("An autostart file already uses this ID"));
        }
        let file = (self.application_file)(id)
            .ok_or_else(|| invalid("Application is no longer installed"))?;
        let key = load(&file)?;
        let _ = key.remove_key(GROUP, "Hidden");
        self.add_entry(id, &key)
    }
    fn add_command(&mut self, name: &str, command: &str) -> Result<(), String> {
        if name.is_empty() || name.chars().count() > 100 || name.chars().any(char::is_control) {
            return Err(invalid(
                "Name must contain 1 to 100 characters without control characters",
            ));
        }
        if command.len() > 4096 || command.chars().any(char::is_control) {
            return Err(invalid(
                "Command must contain at most 4096 bytes without control characters",
            ));
        }
        let argv = glib::shell_parse_argv(command).map_err(invalid)?;
        if !argv.first().is_some_and(|p| {
            self.dirs()
                .is_ok_and(|d| d.executable(&p.to_string_lossy()))
        }) {
            return Err(invalid(
                "The first command argument must be an executable in PATH or an absolute executable",
            ));
        }
        let slug = name
            .to_ascii_lowercase()
            .split(|c: char| !c.is_ascii_alphanumeric())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join("-");
        let slug = if slug.is_empty() { "command" } else { &slug };
        let files = self.dirs()?.files()?;
        let mut id = format!("remya-{slug}.desktop");
        let mut suffix = 2;
        while files.contains_key(&id) {
            id = format!("remya-{slug}-{suffix}.desktop");
            suffix += 1;
        }
        let key = KeyFile::new();
        key.set_string(GROUP, "Type", "Application");
        key.set_string(GROUP, "Name", name);
        key.set_string(
            GROUP,
            "Exec",
            &argv
                .iter()
                .map(|s| quote_arg(&s.to_string_lossy()))
                .collect::<Vec<_>>()
                .join(" "),
        );
        self.add_entry(&id, &key)
    }
    fn remove(&mut self, id: &str) -> Result<(), String> {
        let path = self.user_path(id)?;
        if !self.entries.iter().any(|e| e.id == id && e.removable) {
            return Err(invalid(
                "Only entries added by you can be removed; system entries can only be turned off",
            ));
        }
        fs::remove_file(path).map_err(|e| e.to_string())?;
        self.verify(id, None)
    }
    pub fn set(&mut self, setting: &str, text: &str) -> Result<Value, String> {
        let result = (|| {
            self.refresh()?;
            if !self.conflicts().is_empty() {
                return Err(
                    "Conflict:Resolve saved and system startup apps before changing them".into(),
                );
            }
            match setting {
                "startup.apps" => {
                    let c: Toggle = payload(text)?;
                    self.set_enabled(&c.id, c.enabled)?;
                }
                "startup.add-app" => {
                    let c: AddApp = payload(text)?;
                    self.add_application(&c.application)?;
                }
                "startup.add-command" => {
                    let c: AddCommand = payload(text)?;
                    self.add_command(&c.name, &c.command)?;
                }
                "startup.remove" => {
                    let c: Remove = payload(text)?;
                    self.remove(&c.id)?;
                }
                _ => return Err(invalid("Unknown startup setting")),
            }
            self.persist(&self.system)?;
            self.saved = Some(self.system.clone());
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        result.map(|()| self.state())
    }
    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        let result = (|| {
            if !["system", "settings"].contains(&source) {
                return Err(invalid("Choose system or settings"));
            }
            self.refresh()?;
            if source == "settings" {
                for conflict in self.conflicts() {
                    self.set_enabled(
                        conflict["id"].as_str().unwrap(),
                        conflict["saved"].as_bool().unwrap(),
                    )?;
                }
            }
            self.persist(&self.system)?;
            self.saved = Some(self.system.clone());
            Ok(())
        })();
        self.operation_error = result.as_ref().err().cloned();
        result.map(|()| self.state())
    }
}
fn quote_arg(arg: &str) -> String {
    let arg = arg.replace('%', "%%");
    if !arg.is_empty()
        && !arg
            .chars()
            .any(|c| c.is_whitespace() || "\"'\\><~|&;$*?#()`".contains(c))
    {
        return arg;
    }
    let mut quoted = String::from("\"");
    for c in arg.chars() {
        if "\"`$\\".contains(c) {
            quoted.push('\\');
        }
        quoted.push(c);
    }
    quoted.push('"');
    quoted
}

#[cfg(test)]
mod tests;
