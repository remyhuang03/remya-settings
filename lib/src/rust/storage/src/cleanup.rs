use crate::{
    invalid, now,
    scan::{self, Roots},
};
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::MetadataExt,
    path::{Component, Path, PathBuf},
};
const DAY: u64 = 86400;
#[derive(Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Automatic {
    pub enabled: bool,
    pub frequency: String,
    pub trash_days: u16,
    pub cache_days: u16,
    pub downloads_days: u16,
}
impl Default for Automatic {
    fn default() -> Self {
        Self {
            enabled: false,
            frequency: "low-space".into(),
            trash_days: 30,
            cache_days: 30,
            downloads_days: 0,
        }
    }
}
#[derive(Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct LastRun {
    pub at: u64,
    pub freed_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
#[derive(Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub version: u8,
    pub automatic: Automatic,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_run: Option<LastRun>,
}
impl Default for Prefs {
    fn default() -> Self {
        Self {
            version: 1,
            automatic: Automatic::default(),
            last_run: None,
        }
    }
}
impl Prefs {
    pub fn validate(&self) -> Result<(), String> {
        let a = &self.automatic;
        if self.version != 1
            || !["low-space", "daily", "weekly", "monthly"].contains(&a.frequency.as_str())
            || ![0, 1, 14, 30, 60].contains(&a.trash_days)
            || ![0, 30, 60, 90].contains(&a.cache_days)
            || ![0, 30, 60, 90].contains(&a.downloads_days)
        {
            return Err(invalid("Invalid cleanup policy"));
        }
        Ok(())
    }
    pub fn load(path: &Path) -> Result<Self, String> {
        match fs::read_to_string(path) {
            Ok(text) => {
                let p: Self =
                    toml::from_str(&text).map_err(|e| format!("Invalid cleanup.toml: {e}"))?;
                p.validate()?;
                Ok(p)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(e.to_string()),
        }
    }
    pub fn save(&self, path: &Path) -> Result<(), String> {
        self.validate()?;
        atomic_write(
            path,
            toml::to_string(self).map_err(|e| e.to_string())?.as_bytes(),
        )
    }
    pub fn change(&mut self, id: &str, value: &str) -> Result<(), String> {
        match id {
            "cleanup.auto" => self.automatic.enabled = crate::payload(value)?,
            "cleanup.auto-frequency" => self.automatic.frequency = crate::payload(value)?,
            "cleanup.auto-trash" => self.automatic.trash_days = crate::payload(value)?,
            "cleanup.auto-cache" => self.automatic.cache_days = crate::payload(value)?,
            "cleanup.auto-downloads" => self.automatic.downloads_days = crate::payload(value)?,
            _ => return Err(invalid("Unknown automatic cleanup preference")),
        }
        self.validate()
    }
    pub fn due(&self, at: u64, free: u64, total: u64) -> bool {
        if !self.automatic.enabled {
            return false;
        }
        let elapsed = at.saturating_sub(self.last_run.as_ref().map_or(0, |r| r.at));
        match self.automatic.frequency.as_str() {
            "daily" => elapsed >= DAY,
            "weekly" => elapsed >= 7 * DAY,
            "monthly" => elapsed >= 30 * DAY,
            "low-space" => total > 0 && u128::from(free) * 10 < u128::from(total) && elapsed >= DAY,
            _ => false,
        }
    }
    pub fn setting(&self, id: &str) -> (Value, Value) {
        let a = &self.automatic;
        match id {
            "cleanup.auto" => (json!(a.enabled), json!([])),
            "cleanup.auto-frequency" => (
                json!(a.frequency),
                json!(["low-space", "daily", "weekly", "monthly"]),
            ),
            "cleanup.auto-trash" => (json!(a.trash_days), json!([0, 1, 14, 30, 60])),
            "cleanup.auto-cache" => (json!(a.cache_days), json!([0, 30, 60, 90])),
            "cleanup.auto-downloads" => (json!(a.downloads_days), json!([0, 30, 60, 90])),
            _ => (Value::Null, json!([])),
        }
    }
}
#[derive(Clone)]
pub struct TrashEntry {
    pub item: trash::TrashItem,
    pub bytes: u64,
}
#[derive(Default)]
pub struct TrashListing {
    pub items: Vec<TrashEntry>,
    pub broken: u64,
}
impl TrashListing {
    pub fn read(items: Vec<trash::TrashItem>) -> Self {
        let mut listing = Self::default();
        for item in items {
            let Ok(metadata) = trash::os_limited::metadata(&item) else {
                listing.broken += 1;
                continue;
            };
            let bytes = if let Some(bytes) = metadata.size.size() {
                bytes
            } else {
                let info = Path::new(&item.id);
                let Some(path) = info
                    .parent()
                    .and_then(Path::parent)
                    .zip(info.file_stem())
                    .map(|(root, name)| root.join("files").join(name))
                else {
                    listing.broken += 1;
                    continue;
                };
                scan::walk(&path)
                    .filter_map(Result::ok)
                    .map(|(_, m)| m.blocks() * 512)
                    .sum()
            };
            listing.items.push(TrashEntry { item, bytes });
        }
        listing
    }
}
pub trait Trash: Send + Sync {
    fn list(&self) -> Result<TrashListing, String>;
    fn purge(&self, items: &[TrashEntry]) -> Result<(), String>;
    fn move_files(&self, paths: &[PathBuf]) -> Result<(), String>;
}
pub struct RealTrash;
impl Trash for RealTrash {
    fn list(&self) -> Result<TrashListing, String> {
        trash::os_limited::list()
            .map(TrashListing::read)
            .map_err(|e| e.to_string())
    }
    fn purge(&self, items: &[TrashEntry]) -> Result<(), String> {
        trash::os_limited::purge_all(items.iter().map(|entry| &entry.item))
            .map_err(|e| e.to_string())
    }
    fn move_files(&self, paths: &[PathBuf]) -> Result<(), String> {
        trash::delete_all(paths).map_err(|e| e.to_string())
    }
}
pub fn valid_folder(name: &str) -> bool {
    !name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\0'])
}
/// Reject symlink components and traversals before destructive user-file operations.
pub fn checked_path(root: &Path, path: &Path) -> Result<fs::Metadata, String> {
    let relative = path
        .strip_prefix(root)
        .map_err(|_| invalid("Path is outside the permitted directory"))?;
    if relative.as_os_str().is_empty()
        || !relative
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
    {
        return Err(invalid("Invalid relative path"));
    }
    let mut p = root.to_owned();
    if fs::symlink_metadata(root)
        .map_err(|e| e.to_string())?
        .file_type()
        .is_symlink()
    {
        return Err(invalid("Root is a symlink"));
    }
    for part in relative.components() {
        p.push(part);
        if fs::symlink_metadata(&p)
            .map_err(|e| e.to_string())?
            .file_type()
            .is_symlink()
        {
            return Err(invalid("Symlink paths cannot be cleaned"));
        }
    }
    fs::symlink_metadata(path).map_err(|e| e.to_string())
}
pub fn remove_cache(
    roots: &Roots,
    names: &[String],
    reported: &[scan::CacheFolder],
) -> Result<(), String> {
    for name in names {
        if !valid_folder(name) || !reported.iter().any(|f| f.name == *name) {
            return Err(invalid("Select a reported direct cache child"));
        }
        checked_path(&roots.cache, &roots.cache.join(name))?;
    }
    for name in names {
        let path = roots.cache.join(name);
        let m = checked_path(&roots.cache, &path)?;
        if m.is_dir() {
            fs::remove_dir_all(path)
        } else {
            fs::remove_file(path)
        }
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}
fn old(metadata: &fs::Metadata, days: u16, at: u64) -> bool {
    days > 0
        && metadata.atime().max(metadata.mtime()) >= 0
        && (metadata.atime().max(metadata.mtime()) as u64).saturating_add(u64::from(days) * DAY)
            < at
}
pub fn policy(roots: &Roots, prefs: &Prefs, trash: &dyn Trash, at: u64) -> LastRun {
    let mut freed = 0;
    let mut errors = Vec::new();
    if prefs.automatic.trash_days > 0 {
        match trash.list() {
            Ok(items) => {
                let expired = items
                    .items
                    .into_iter()
                    .filter(|entry| {
                        let deleted = entry.item.time_deleted;
                        deleted >= 0
                            && (deleted as u64)
                                .saturating_add(u64::from(prefs.automatic.trash_days) * DAY)
                                < at
                    })
                    .collect::<Vec<_>>();
                if !expired.is_empty() {
                    match trash.purge(&expired) {
                        Ok(()) => freed += expired.iter().map(|entry| entry.bytes).sum::<u64>(),
                        Err(e) => errors.push(e),
                    }
                }
            }
            Err(e) => errors.push(e),
        }
    }
    for (root, days, to_trash) in [
        (
            Some(roots.cache.as_path()),
            prefs.automatic.cache_days,
            false,
        ),
        (roots.downloads(), prefs.automatic.downloads_days, true),
    ] {
        if days == 0 {
            continue;
        }
        let Some(root) = root else {
            continue;
        };
        if !root.exists() {
            continue;
        }
        for entry in scan::walk(root) {
            match entry {
                Ok((path, m)) if m.is_file() && old(&m, days, at) => {
                    let result = checked_path(root, &path).and_then(|_| {
                        if to_trash {
                            trash.move_files(std::slice::from_ref(&path))
                        } else {
                            fs::remove_file(&path).map_err(|e| e.to_string())
                        }
                    });
                    match result {
                        Ok(()) => {
                            if !to_trash {
                                freed += m.blocks() * 512;
                            }
                        }
                        Err(e) => errors.push(e),
                    }
                }
                Err(e) => errors.push(e),
                _ => {}
            }
        }
    }
    LastRun {
        at,
        freed_bytes: freed,
        error: (!errors.is_empty()).then(|| format!("{} errors: {}", errors.len(), errors[0])),
    }
}
pub fn run_policy(roots: &Roots, prefs: &Prefs, trash: &dyn Trash) -> LastRun {
    policy(roots, prefs, trash, now())
}
