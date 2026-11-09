use gio::{
    glib::{self, KeyFile, KeyFileFlags, MainContext},
    prelude::*,
};
use remya_settings_display::atomic_write;
use std::{
    cell::Cell,
    collections::BTreeSet,
    fs,
    io::ErrorKind,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    rc::Rc,
    time::{Duration, Instant},
};

const DEFAULTS: &str = "Default Applications";

fn filenames() -> BTreeSet<String> {
    std::iter::once("mimeapps.list".into())
        .chain(
            std::env::var("XDG_CURRENT_DESKTOP")
                .unwrap_or_default()
                .split(':')
                .map(str::to_ascii_lowercase)
                .filter(|s| {
                    !s.is_empty()
                        && s.bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
                })
                .map(|desktop| format!("{desktop}-mimeapps.list")),
        )
        .collect()
}

fn user_roots(dirs: &xdg::BaseDirectories) -> BTreeSet<PathBuf> {
    dirs.get_config_home()
        .into_iter()
        .chain(dirs.get_data_home().map(|home| home.join("applications")))
        .collect()
}

fn system_roots(dirs: &xdg::BaseDirectories) -> impl Iterator<Item = PathBuf> {
    dirs.get_config_dirs().into_iter().chain(
        dirs.get_data_dirs()
            .into_iter()
            .map(|dir| dir.join("applications")),
    )
}

fn read(path: &Path) -> Result<Option<(String, KeyFile)>, String> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) if e.kind() == ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("Cannot read {}: {e}", path.display())),
    };
    let file = KeyFile::new();
    file.load_from_data(
        &text,
        KeyFileFlags::KEEP_COMMENTS | KeyFileFlags::KEEP_TRANSLATIONS,
    )
    .map_err(|e| format!("Cannot parse {}: {e}", path.display()))?;
    Ok(Some((text, file)))
}

// GIO has no error channel for default lookups.
pub(super) fn check_association_files() -> Result<(), String> {
    let dirs = xdg::BaseDirectories::new();
    let names = filenames();
    for root in user_roots(&dirs).into_iter().chain(system_roots(&dirs)) {
        for name in &names {
            read(&root.join(name))?;
        }
    }
    Ok(())
}

struct Edit {
    path: PathBuf,
    before: String,
    after: glib::GString,
}

fn check_unchanged(path: &Path, expected: &str) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.permissions().mode() & 0o222 == 0 {
        return Err("Expected a writable regular file".into());
    }
    if fs::read_to_string(path).map_err(|e| e.to_string())? != expected {
        return Err("File changed externally".into());
    }
    Ok(())
}

fn write(path: &Path, before: &str, after: &str) -> Result<(), String> {
    check_unchanged(path, before)
        .and_then(|()| atomic_write(path, after.as_bytes()))
        .map_err(|e| format!("Cannot update {}: {e}", path.display()))
}

pub(super) fn reset_defaults() -> Result<(), String> {
    let dirs = xdg::BaseDirectories::new();
    let system_roots: BTreeSet<_> = system_roots(&dirs)
        .filter_map(|root| root.canonicalize().ok())
        .collect();
    let names = filenames();
    let mut edits = Vec::new();
    let mut seen = BTreeSet::new();
    for root in user_roots(&dirs) {
        for name in &names {
            let path = root.join(name);
            let Some((before, file)) = read(&path)? else {
                continue;
            };
            if !file.has_group(DEFAULTS) {
                continue;
            }
            let parent = root.canonicalize().map_err(|e| e.to_string())?;
            if system_roots.contains(&parent) {
                return Err(format!(
                    "Cannot reset a system association file: {}",
                    path.display()
                ));
            }
            let path = parent.join(name);
            if !seen.insert(path.clone()) {
                continue;
            }
            check_unchanged(&path, &before)
                .map_err(|e| format!("Cannot reset {}: {e}", path.display()))?;
            file.remove_group(DEFAULTS).map_err(|e| e.to_string())?;
            edits.push(Edit {
                path,
                before,
                after: file.to_data(),
            });
        }
    }
    if edits.is_empty() {
        return Ok(());
    }
    let context = MainContext::new();
    context
        .with_thread_default(|| {
            let changed = Rc::new(Cell::new(false));
            let monitor = gio::AppInfoMonitor::get();
            let handler = monitor.connect_changed({
                let changed = changed.clone();
                move |_| changed.set(true)
            });
            let mut written = Vec::<&Edit>::new();
            let result = (|| {
                for edit in &edits {
                    // Arm GIO's directory watches before editing and wait for cache invalidation.
                    gio::AppInfo::all();
                    changed.set(false);
                    write(&edit.path, &edit.before, &edit.after)?;
                    written.push(edit);
                    let deadline = Instant::now() + Duration::from_secs(3);
                    context.block_on(async {
                        while !changed.get() && Instant::now() < deadline {
                            glib::timeout_future(Duration::from_millis(10)).await;
                        }
                    });
                    if !changed.get() {
                        return Err(format!(
                            "GIO did not refresh after updating {}",
                            edit.path.display()
                        ));
                    }
                }
                for edit in &edits {
                    check_unchanged(&edit.path, &edit.after)
                        .map_err(|e| format!("Cannot verify {}: {e}", edit.path.display()))?;
                }
                Ok(())
            })();
            monitor.disconnect(handler);
            if let Err(mut error) = result {
                for edit in written.into_iter().rev() {
                    if let Err(rollback) = write(&edit.path, &edit.after, &edit.before) {
                        error.push_str(&format!(". Rollback failed: {rollback}"));
                    }
                }
                return Err(error);
            }
            Ok(())
        })
        .map_err(|e| e.to_string())?
}
