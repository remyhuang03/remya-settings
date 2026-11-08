use serde::Serialize;
use std::{
    collections::{BTreeMap, HashSet},
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    time::Instant,
};

#[derive(Clone, Debug)]
pub struct Roots {
    pub home: PathBuf,
    pub cache: PathBuf,
    pub trash: PathBuf,
    pub folders: Vec<(&'static str, &'static str, PathBuf)>,
}
impl Roots {
    pub fn real() -> Result<Self, String> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .ok_or("Absolute HOME required")?;
        let xdg = xdg::BaseDirectories::new();
        let cache = xdg.get_cache_home().unwrap_or_else(|| home.join(".cache"));
        let trash = xdg
            .get_data_home()
            .unwrap_or_else(|| home.join(".local/share"))
            .join("Trash");
        use gio::glib::{UserDirectory as U, user_special_dir};
        let folders = [
            ("documents", "Documents", U::Documents),
            ("pictures", "Pictures", U::Pictures),
            ("videos", "Videos", U::Videos),
            ("music", "Music", U::Music),
            ("downloads", "Downloads", U::Downloads),
            ("desktop", "Desktop", U::Desktop),
        ]
        .into_iter()
        .filter_map(|(id, label, kind)| {
            user_special_dir(kind)
                .filter(|p| p != &home && p.is_absolute())
                .map(|p| (id, label, p))
        })
        .collect();
        Ok(Self {
            home,
            cache,
            trash,
            folders,
        })
    }
    pub fn downloads(&self) -> Option<&Path> {
        self.folders
            .iter()
            .find(|f| f.0 == "downloads")
            .map(|f| f.2.as_path())
    }
}
#[derive(Clone, Default, Serialize)]
pub struct Usage {
    pub total: u64,
    pub used: u64,
    pub free: u64,
}
pub fn usage(path: &Path) -> Result<Usage, String> {
    let s = rustix::fs::statvfs(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(Usage {
        total: s.f_blocks.saturating_mul(s.f_frsize),
        used: s
            .f_blocks
            .saturating_sub(s.f_bfree)
            .saturating_mul(s.f_frsize),
        free: s.f_bavail.saturating_mul(s.f_frsize),
    })
}
#[derive(Clone, Serialize)]
pub struct Volume {
    pub mount_point: String,
    pub device: String,
    #[serde(flatten)]
    pub usage: Usage,
}
pub fn volume(home: &Path) -> Result<Volume, String> {
    let text = fs::read_to_string("/proc/self/mountinfo").map_err(|e| e.to_string())?;
    let mut found = ("/".to_string(), String::new());
    for line in text.lines() {
        if let Some((left, right)) = line.split_once(" - ") {
            let mount = left
                .split_whitespace()
                .nth(4)
                .unwrap_or("")
                .replace("\\040", " ")
                .replace("\\011", "\t")
                .replace("\\012", "\n")
                .replace("\\134", "\\");
            if !mount.is_empty() && home.starts_with(&mount) && mount.len() >= found.0.len() {
                found = (mount, right.split_whitespace().nth(1).unwrap_or("").into());
            }
        }
    }
    Ok(Volume {
        mount_point: found.0,
        device: found.1,
        usage: usage(home)?,
    })
}
#[derive(Clone, Default, Serialize)]
pub struct Progress {
    pub files: u64,
    pub bytes: u64,
}
#[derive(Clone, Serialize)]
pub struct Category {
    pub id: String,
    pub label: String,
    pub bytes: u64,
    pub path: Option<PathBuf>,
}
#[derive(Clone, Serialize)]
pub struct LargeFile {
    pub path: PathBuf,
    pub bytes: u64,
    pub modified: i64,
}
#[derive(Clone, Serialize)]
pub struct CacheFolder {
    pub name: String,
    pub bytes: u64,
}
#[derive(Clone, Default, Serialize)]
pub struct Scan {
    pub scanning: bool,
    pub progress: Progress,
    pub scanned_at: Option<u64>,
    pub volume: Option<Volume>,
    pub categories: Vec<Category>,
    pub skipped: u64,
    pub error: Option<String>,
    #[serde(skip)]
    pub cache: Vec<CacheFolder>,
    #[serde(skip)]
    pub large: Vec<LargeFile>,
}
impl Scan {
    pub(super) fn add_large(&mut self, file: LargeFile) {
        self.large.push(file);
        self.large
            .sort_by(|a, b| b.bytes.cmp(&a.bytes).then(a.path.cmp(&b.path)));
        self.large.truncate(30);
    }
}
/// jwalk prunes foreign filesystems before descending and never follows links.
pub fn walk(root: &Path) -> impl Iterator<Item = Result<(PathBuf, fs::Metadata), String>> {
    let dev = fs::symlink_metadata(root).map(|m| m.dev()).ok();
    jwalk::WalkDir::new(root)
        .follow_links(false)
        .skip_hidden(false)
        .process_read_dir(move |_, _, _, children| {
            for entry in children.iter_mut().flatten() {
                if entry.file_type.is_dir() && entry.metadata().is_ok_and(|m| Some(m.dev()) != dev)
                {
                    entry.read_children_path = None;
                }
            }
        })
        .into_iter()
        .filter_map(move |entry| match entry {
            Err(e) => Some(Err(e.to_string())),
            Ok(e) => {
                if let Some(error) = e.read_children_error {
                    return Some(Err(error.to_string()));
                }
                let path = e.path();
                match fs::symlink_metadata(&path) {
                    Ok(m) if Some(m.dev()) == dev => Some(Ok((path, m))),
                    Ok(_) => None,
                    Err(e) => Some(Err(e.to_string())),
                }
            }
        })
}
pub fn scan(roots: &Roots, mut report: impl FnMut(&Progress)) -> Scan {
    let mut result = Scan::default();
    match volume(&roots.home) {
        Ok(v) => result.volume = Some(v),
        Err(e) => result.error = Some(e),
    }
    let mut categories = roots
        .folders
        .iter()
        .map(|(id, label, path)| Category {
            id: (*id).into(),
            label: (*label).into(),
            bytes: 0,
            path: Some(path.components().collect()),
        })
        .collect::<Vec<_>>();
    for (id, label, path) in [
        ("cache", "Cached files", &roots.cache),
        ("trash", "Trash", &roots.trash),
    ] {
        categories.push(Category {
            id: id.into(),
            label: label.into(),
            bytes: 0,
            path: path
                .starts_with(&roots.home)
                .then(|| path.components().collect()),
        });
    }
    categories.push(Category {
        id: "home-other".into(),
        label: "Other home files".into(),
        bytes: 0,
        path: Some(roots.home.components().collect()),
    });
    let mut cache = BTreeMap::<String, u64>::new();
    let mut links = HashSet::new();
    let mut last = Instant::now();
    for entry in walk(&roots.home) {
        let (path, m) = match entry {
            Ok(e) => e,
            Err(_) => {
                result.skipped += 1;
                continue;
            }
        };
        if path.to_str().is_none() {
            result.skipped += 1;
            continue;
        }
        if m.file_type().is_symlink() {
            continue;
        }
        if m.nlink() > 1 && !m.is_dir() && !links.insert((m.dev(), m.ino())) {
            continue;
        }
        let bytes = m.blocks().saturating_mul(512);
        result.progress.bytes = result.progress.bytes.saturating_add(bytes);
        if m.is_file() {
            result.progress.files += 1;
        }
        // Nested XDG folders belong to the most specific category.
        let index = categories
            .iter()
            .enumerate()
            .filter(|(_, c)| {
                c.id != "home-other" && c.path.as_ref().is_some_and(|p| path.starts_with(p))
            })
            .max_by_key(|(_, c)| c.path.as_ref().unwrap().components().count())
            .map_or(categories.len() - 1, |(i, _)| i);
        categories[index].bytes += bytes;
        if let Ok(relative) = path.strip_prefix(&roots.cache)
            && let Some(name) = relative
                .components()
                .next()
                .and_then(|s| s.as_os_str().to_str())
        {
            *cache.entry(name.into()).or_default() += bytes;
        }
        if m.is_file()
            && bytes >= 100_000_000
            && path.strip_prefix(&roots.home).is_ok_and(|relative| {
                !relative.parent().is_some_and(|parent| {
                    parent
                        .components()
                        .any(|c| c.as_os_str().as_encoded_bytes().starts_with(b"."))
                })
            })
            && !path.starts_with(&roots.cache)
            && !path.starts_with(&roots.trash)
        {
            result.add_large(LargeFile {
                path,
                bytes,
                modified: m.mtime(),
            });
        }
        if last.elapsed().as_secs() >= 1 {
            report(&result.progress);
            last = Instant::now();
        }
    }
    let root_dev = fs::metadata("/").ok().map(|m| m.dev());
    let same_root = fs::metadata(&roots.home).is_ok_and(|m| Some(m.dev()) == root_dev);
    categories.push(Category {
        id: "system".into(),
        label: if same_root {
            "System and other files"
        } else {
            "Other files on this volume"
        }
        .into(),
        bytes: result
            .volume
            .as_ref()
            .map_or(0, |v| v.usage.used.saturating_sub(result.progress.bytes)),
        path: None,
    });
    result.categories = categories;
    result.cache = cache
        .into_iter()
        .map(|(name, bytes)| CacheFolder { name, bytes })
        .collect();
    if !roots.cache.starts_with(&roots.home)
        || fs::metadata(&roots.cache).ok().map(|m| m.dev())
            != fs::metadata(&roots.home).ok().map(|m| m.dev())
    {
        let mut children = BTreeMap::<String, u64>::new();
        let mut links = HashSet::new();
        for entry in walk(&roots.cache) {
            let Ok((path, m)) = entry else {
                continue;
            };
            if m.file_type().is_symlink()
                || (m.nlink() > 1 && !m.is_dir() && !links.insert((m.dev(), m.ino())))
            {
                continue;
            }
            if let Ok(relative) = path.strip_prefix(&roots.cache)
                && let Some(name) = relative
                    .components()
                    .next()
                    .and_then(|c| c.as_os_str().to_str())
            {
                *children.entry(name.into()).or_default() += m.blocks() * 512;
            }
        }
        result.cache = children
            .into_iter()
            .map(|(name, bytes)| CacheFolder { name, bytes })
            .collect();
    }
    result.cache.sort_by_key(|f| std::cmp::Reverse(f.bytes));
    result.scanned_at = Some(crate::now());
    result
}
