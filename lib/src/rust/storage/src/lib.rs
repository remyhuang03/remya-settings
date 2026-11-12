//! Live storage measurements and explicit cleanup, independent of the service state lock.
pub mod cleanup;
pub mod disks;
pub mod packages;
pub mod scan;
use cleanup::{Prefs, Trash};
use disks::Disks;
use packages::Process;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};
pub const IDS: &[&str] = &[
    "storage.usage",
    "storage.scan",
    "storage.volumes",
    "storage.mount",
    "storage.eject",
    "storage.label",
    "storage.open",
    "cleanup.trash",
    "cleanup.cache",
    "cleanup.package-cache",
    "cleanup.orphans",
    "cleanup.large-files",
    "cleanup.auto",
    "cleanup.auto-frequency",
    "cleanup.auto-trash",
    "cleanup.auto-cache",
    "cleanup.auto-downloads",
    "cleanup.run-now",
];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}
pub fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}
pub fn payload<T: serde::de::DeserializeOwned>(text: &str) -> Result<T, String> {
    serde_json::from_str(text).map_err(|e| invalid(&e.to_string()))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Empty {}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Open {
    path: PathBuf,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Cache {
    folders: Vec<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Large {
    paths: Vec<PathBuf>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TrashAction {
    action: String,
}
struct Inner {
    scan: scan::Scan,
    drives: Vec<disks::Drive>,
    disks_error: Option<String>,
    trash: Value,
    package_cache: Value,
    orphans: Value,
    prefs: Prefs,
    config_error: Option<String>,
    error: Option<String>,
    busy: bool,
    refreshing: bool,
    dirty: bool,
    started: bool,
    refreshed_at: u64,
}
#[derive(Clone)]
pub struct Storage {
    inner: Arc<Mutex<Inner>>,
    roots: Arc<scan::Roots>,
    config: PathBuf,
    disks: Arc<dyn Disks>,
    trash: Arc<dyn Trash>,
    process: Arc<dyn Process>,
}
impl Storage {
    pub fn real(config: PathBuf) -> Result<Self, String> {
        Ok(Self::new(
            scan::Roots::real()?,
            config,
            Arc::new(disks::RealDisks),
            Arc::new(cleanup::RealTrash),
            Arc::new(packages::RealProcess),
        ))
    }
    pub fn new(
        roots: scan::Roots,
        config: PathBuf,
        disks: Arc<dyn Disks>,
        trash: Arc<dyn Trash>,
        process: Arc<dyn Process>,
    ) -> Self {
        let (prefs, config_error) = match Prefs::load(&config) {
            Ok(p) => (p, None),
            Err(e) => (Prefs::default(), Some(e)),
        };
        Self {
            inner: Arc::new(Mutex::new(Inner {
                scan: scan::Scan::default(),
                drives: Vec::new(),
                disks_error: None,
                trash: Value::Null,
                package_cache: Value::Null,
                orphans: Value::Null,
                prefs,
                config_error,
                error: None,
                busy: false,
                refreshing: false,
                dirty: false,
                started: false,
                refreshed_at: 0,
            })),
            roots: Arc::new(roots),
            config,
            disks,
            trash,
            process,
        }
    }
    pub fn take_dirty(&self) -> bool {
        std::mem::take(&mut self.inner.lock().unwrap().dirty)
    }
    pub fn busy(&self) -> bool {
        self.inner.lock().unwrap().busy
    }
    pub fn state(&self, page: &str) -> Value {
        let i = self.inner.lock().unwrap();
        if page == "storage" {
            return json!({"api_version":1,"initialized":i.scan.scanned_at.is_some() && i.scan.error.is_none(),"writable":!i.busy,"conflict":false,"error":i.error.as_ref().or(i.scan.error.as_ref()),"busy":i.busy,"usage":i.scan,"drives":i.drives,"disks_error":i.disks_error,"reclaimable_bytes":reclaimable(&i)});
        }
        json!({"api_version":1,"initialized":i.config_error.is_none(),"writable":i.config_error.is_none() && !i.busy,"conflict":false,"error":i.error.as_ref().or(i.config_error.as_ref()),"busy":i.busy,"scanning":i.scan.scanning,"trash":i.trash,"cache":{"bytes":i.scan.cache.iter().map(|f|f.bytes).sum::<u64>(),"folders":i.scan.cache},"package_cache":i.package_cache,"orphans":i.orphans,"large_files":{"files":i.scan.large},"automatic":i.prefs.automatic,"last_run":i.prefs.last_run,"reclaimable_bytes":reclaimable(&i)})
    }
    pub fn read(&self, page: &str) -> Value {
        self.refresh_policy();
        let start = !self.inner.lock().unwrap().started;
        if start {
            let _ = self.start_scan();
        } else {
            self.refresh_background();
        }
        self.state(page)
    }
    fn refresh_background(&self) {
        {
            let mut i = self.inner.lock().unwrap();
            if i.busy || i.refreshing || now().saturating_sub(i.refreshed_at) < 5 {
                return;
            }
            i.refreshing = true;
        }
        let storage = self.clone();
        std::thread::spawn(move || {
            storage.refresh();
            storage.inner.lock().unwrap().refreshing = false;
        });
    }
    pub fn read_setting(&self, id: &str) -> Value {
        let page = if id.starts_with("storage.") {
            "storage"
        } else {
            "cleanup"
        };
        self.read(page);
        let i = self.inner.lock().unwrap();
        let (value, options) = if id.starts_with("cleanup.auto") {
            i.prefs.setting(id)
        } else {
            (
                match id {
                    "storage.usage" => json!(i.scan),
                    "storage.volumes" => json!(i.drives),
                    "cleanup.trash" => i.trash.clone(),
                    "cleanup.cache" => {
                        json!({"bytes":i.scan.cache.iter().map(|f|f.bytes).sum::<u64>(),"folders":i.scan.cache})
                    }
                    "cleanup.package-cache" => i.package_cache.clone(),
                    "cleanup.orphans" => i.orphans.clone(),
                    "cleanup.large-files" => json!({"files":i.scan.large}),
                    _ => Value::Null,
                },
                json!([]),
            )
        };
        let missing = if id == "cleanup.package-cache" && !self.process.exists("/usr/bin/paccache")
        {
            Some("Install pacman-contrib for paccache".to_string())
        } else if id == "cleanup.orphans" && !self.process.exists("/usr/bin/pacman") {
            Some("pacman is required".into())
        } else if [
            "storage.volumes",
            "storage.mount",
            "storage.eject",
            "storage.label",
        ]
        .contains(&id)
        {
            i.disks_error.clone()
        } else {
            None
        };
        json!({"api_version":1,"id":id,"availability":if missing.is_some() {"planned"} else {"available"},"reason":missing.unwrap_or_else(||"Verified Rust storage integration; operations use live readback".into()),"value":value,"options":options,"writable":!i.busy && !["storage.usage","storage.volumes"].contains(&id) && (!id.starts_with("cleanup.auto") || i.config_error.is_none()),"error":i.config_error})
    }
    fn launch(
        &self,
        work: impl FnOnce(&Storage) -> Result<(), String> + Send + 'static,
    ) -> Result<(), String> {
        {
            let mut i = self.inner.lock().unwrap();
            if i.busy {
                return Err("Busy:A storage operation is running".into());
            }
            i.busy = true;
            i.error = None;
            i.dirty = true;
        }
        let storage = self.clone();
        std::thread::spawn(move || {
            let result = work(&storage);
            if result.is_err() {
                storage.measure();
                storage.refresh();
            }
            let mut i = storage.inner.lock().unwrap();
            i.error = result.err();
            i.busy = false;
            i.dirty = true;
        });
        Ok(())
    }
    fn measure(&self) {
        {
            let mut i = self.inner.lock().unwrap();
            i.scan.scanning = true;
            i.started = true;
            i.dirty = true;
        }
        let scan = scan::scan(&self.roots, |p| {
            let mut i = self.inner.lock().unwrap();
            i.scan.progress = p.clone();
            i.dirty = true;
        });
        let mut i = self.inner.lock().unwrap();
        i.scan = scan;
        i.dirty = true;
    }
    fn refresh(&self) {
        let disks = self
            .disks
            .objects()
            .map(|o| disks::parse(&o, &self.roots.home));
        let trash = self.trash.list().map(
            |listing| json!({"items":listing.items.len(),"bytes":listing.items.iter().map(|t|t.bytes).sum::<u64>(),"broken":listing.broken}),
        );
        let package_cache = packages::cache(self.process.as_ref());
        let orphans = packages::orphans(self.process.as_ref())
            .map(|p| json!({"bytes":p.iter().map(|p|p.bytes).sum::<u64>(),"packages":p}));
        let volume = scan::volume(&self.roots.home);
        let mut i = self.inner.lock().unwrap();
        if let Ok(volume) = volume {
            i.scan.volume = Some(volume);
        }
        i.refreshed_at = now();
        match disks {
            Ok(d) => {
                i.drives = d;
                i.disks_error = None;
            }
            Err(e) => i.disks_error = Some(e),
        }
        i.trash = trash.unwrap_or_else(|e| json!({"error":e}));
        i.package_cache = package_cache.unwrap_or_else(|e| json!({"error":e}));
        i.orphans = orphans.unwrap_or_else(|e| json!({"error":e}));
        i.dirty = true;
    }
    pub fn start_scan(&self) -> Result<(), String> {
        if self.busy() {
            return Ok(());
        }
        {
            let mut i = self.inner.lock().unwrap();
            i.started = true;
            i.scan.scanning = true;
            i.scan.progress = scan::Progress::default();
            i.scan.volume = scan::volume(&self.roots.home).ok();
        }
        self.launch(|s| {
            s.measure();
            s.refresh();
            Ok(())
        })
    }
    pub fn set(&self, id: &str, text: &str) -> Result<Value, String> {
        self.refresh_policy();
        if ["storage.usage", "storage.volumes"].contains(&id) {
            return Err("ReadOnly:Storage measurements cannot be written".into());
        }
        if id.starts_with("cleanup.auto") {
            let mut i = self.inner.lock().unwrap();
            if i.busy {
                return Err("Busy:A cleanup operation is running".into());
            }
            if let Some(e) = &i.config_error {
                return Err(format!(
                    "Unavailable:Cleanup preferences are not writable: {e}"
                ));
            }
            let mut next = i.prefs.clone();
            next.change(id, text)?;
            next.save(&self.config)?;
            i.prefs = next;
            i.dirty = true;
            drop(i);
            return Ok(self.state("cleanup"));
        }
        if id == "storage.scan" {
            let _: Empty = payload(text)?;
            self.start_scan()?;
            return Ok(self.state("storage"));
        }
        let id = id.to_string();
        let text = text.to_string();
        // Validate all user payloads before scheduling anything destructive.
        self.validate(&id, &text)?;
        let page = if id.starts_with("storage.") {
            "storage"
        } else {
            "cleanup"
        };
        self.launch(move |s| {
            match id.as_str() {
                "storage.open" => {
                    let p: Open = payload(&text)?;
                    s.disks.open(&p.path)?;
                }
                "storage.mount" | "storage.label" | "storage.eject" => {
                    let drives = disks::operate(s.disks.as_ref(), &s.roots.home, &id, &text)?;
                    s.inner.lock().unwrap().drives = drives;
                }
                "cleanup.trash" => {
                    let items = s.trash.list()?;
                    s.trash.purge(&items.items)?;
                    s.measure();
                    s.refresh();
                }
                "cleanup.cache" => {
                    let p: Cache = payload(&text)?;
                    let reported = s.inner.lock().unwrap().scan.cache.clone();
                    cleanup::remove_cache(&s.roots, &p.folders, &reported)?;
                    s.measure();
                    s.refresh();
                }
                "cleanup.large-files" => {
                    let p: Large = payload(&text)?;
                    if p.paths.is_empty() {
                        return Err(invalid("Select at least one large file"));
                    }
                    let mut seen = std::collections::HashSet::new();
                    for path in &p.paths {
                        if !seen.insert(path) {
                            return Err(invalid("Duplicate large file"));
                        }
                        if !cleanup::checked_path(&s.roots.home, path)?.is_file() {
                            return Err(invalid("Large file is no longer regular"));
                        }
                    }
                    s.trash.move_files(&p.paths)?;
                    s.measure();
                    s.refresh();
                }
                "cleanup.run-now" => {
                    s.run_policy()?;
                }
                _ => return Err(invalid("Unknown storage action")),
            }
            Ok(())
        })?;
        Ok(self.state(page))
    }
    fn validate(&self, id: &str, text: &str) -> Result<(), String> {
        match id {
            "storage.open" => {
                let p: Open = payload(text)?;
                let i = self.inner.lock().unwrap();
                if !allowed_open(&i, &p.path) {
                    return Err(invalid("Path was not reported by Storage"));
                }
            }
            "storage.mount" | "storage.label" | "storage.eject" => {
                // Validate IDs against fresh objects before accepting the job.
                let objects = self.disks.objects()?;
                let path = match id {
                    "storage.mount" => {
                        let p: disks::Mount = payload(text)?;
                        if !["mount", "unmount"].contains(&p.action.as_str()) {
                            return Err(invalid("Invalid mount action"));
                        }
                        p.volume
                    }
                    "storage.label" => {
                        let p: disks::Label = payload(text)?;
                        if !disks::valid_label(&p.label) {
                            return Err(invalid("Invalid volume label"));
                        }
                        p.volume
                    }
                    _ => {
                        let p: disks::Eject = payload(text)?;
                        if !["eject", "power-off"].contains(&p.action.as_str()) {
                            return Err(invalid("Invalid drive action"));
                        }
                        p.drive
                    }
                };
                if !objects.contains_key(&path) {
                    return Err(invalid("Unknown UDisks2 object path"));
                }
            }
            "cleanup.trash" => {
                let p: TrashAction = payload(text)?;
                if p.action != "empty" {
                    return Err(invalid("Use action empty"));
                }
            }
            "cleanup.cache" => {
                let p: Cache = payload(text)?;
                let i = self.inner.lock().unwrap();
                if p.folders.is_empty() {
                    return Err(invalid("Select at least one cache folder"));
                }
                let mut seen = std::collections::HashSet::new();
                for name in &p.folders {
                    if !seen.insert(name) {
                        return Err(invalid("Duplicate cache folder"));
                    }
                    if !cleanup::valid_folder(name) || !i.scan.cache.iter().any(|f| f.name == *name)
                    {
                        return Err(invalid("Unknown cache folder"));
                    }
                    cleanup::checked_path(&self.roots.cache, &self.roots.cache.join(name))?;
                }
            }
            "cleanup.large-files" => {
                let p: Large = payload(text)?;
                let i = self.inner.lock().unwrap();
                if p.paths.is_empty() {
                    return Err(invalid("Select at least one large file"));
                }
                let mut seen = std::collections::HashSet::new();
                for path in &p.paths {
                    if !seen.insert(path) {
                        return Err(invalid("Duplicate large file"));
                    }
                    if !i.scan.large.iter().any(|f| f.path == *path)
                        || !cleanup::checked_path(&self.roots.home, path)?.is_file()
                    {
                        return Err(invalid("Select a reported regular large file inside HOME"));
                    }
                }
            }
            "cleanup.run-now" => {
                let _: Empty = payload(text)?;
                let i = self.inner.lock().unwrap();
                if let Some(e) = &i.config_error {
                    return Err(format!("Unavailable:{e}"));
                }
            }
            _ => return Err(invalid("Unknown storage action")),
        }
        Ok(())
    }
    pub fn start_privileged(
        &self,
        work: impl FnOnce() -> Result<Value, String> + Send + 'static,
    ) -> Result<Value, String> {
        self.launch(move |s| {
            work()?;
            s.refresh();
            Ok(())
        })?;
        Ok(self.state("cleanup"))
    }
    fn run_policy(&self) -> Result<(), String> {
        let prefs = self.inner.lock().unwrap().prefs.clone();
        let run = cleanup::run_policy(&self.roots, &prefs, self.trash.as_ref());
        let mut next = prefs.clone();
        next.last_run = Some(run);
        let saved = Prefs::load(&self.config).and_then(|current| {
            if current != prefs {
                return Err(
                    "Conflict:Cleanup policy changed during the run; its file was preserved".into(),
                );
            }
            next.save(&self.config)
        });
        {
            let mut i = self.inner.lock().unwrap();
            i.prefs = next;
            if let Err(e) = saved {
                i.config_error = Some(e.clone());
                return Err(e);
            }
        }
        self.measure();
        self.refresh();
        Ok(())
    }
    fn refresh_policy(&self) {
        let mut i = self.inner.lock().unwrap();
        if i.busy {
            return;
        }
        let before = (i.prefs.clone(), i.config_error.clone());
        match Prefs::load(&self.config) {
            Ok(prefs) => {
                i.prefs = prefs;
                i.config_error = std::fs::metadata(&self.config)
                    .ok()
                    .filter(|m| m.permissions().readonly())
                    .map(|_| "Cleanup preferences are read-only".into());
            }
            Err(error) => i.config_error = Some(error),
        }
        if before != (i.prefs.clone(), i.config_error.clone()) {
            i.dirty = true;
        }
    }
    pub fn auto_tick(&self) {
        self.refresh_policy();
        let due = {
            let i = self.inner.lock().unwrap();
            if i.busy || i.config_error.is_some() {
                false
            } else {
                scan::usage(&self.roots.home).is_ok_and(|v| i.prefs.due(now(), v.free, v.total))
            }
        };
        if due {
            let _ = self.launch(|s| s.run_policy());
        }
    }
}
fn allowed_open(i: &Inner, path: &Path) -> bool {
    i.scan
        .categories
        .iter()
        .any(|c| c.path.as_deref() == Some(path))
        || i.scan.large.iter().any(|f| f.path.parent() == Some(path))
        || i.drives
            .iter()
            .flat_map(|d| &d.volumes)
            .flat_map(|v| &v.mount_points)
            .any(|p| Path::new(p) == path)
}
fn reclaimable(i: &Inner) -> u64 {
    i.trash["bytes"].as_u64().unwrap_or(0)
        + i.scan.cache.iter().map(|f| f.bytes).sum::<u64>()
        + i.package_cache["candidates"]["2"].as_u64().unwrap_or(0)
        + i.orphans["bytes"].as_u64().unwrap_or(0)
}
#[cfg(test)]
mod tests;
