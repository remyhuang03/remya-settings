//! Application-owned copies of selected backgrounds. Saved configuration and
//! hyprpaper only ever reference these copies, never the file the user picked.
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

const NAME_LIMIT: usize = 80;

/// Keeps a readable original name beside the content hash; commas break hyprctl input.
fn safe_name(source: &Path) -> String {
    let stem = source
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let cleaned: String = stem
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || "._-".contains(c) {
                c
            } else {
                '_'
            }
        })
        .take(NAME_LIMIT)
        .collect();
    if cleaned.is_empty() {
        "background".into()
    } else {
        cleaned
    }
}

/// Copies `source` into `dir`, reusing an identical earlier copy.
pub fn import(source: &Path, dir: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let mut input = fs::File::open(source).map_err(|e| format!("{}: {e}", source.display()))?;
    let temporary = dir.join(format!(".import-{}", std::process::id()));
    let mut output =
        fs::File::create(&temporary).map_err(|e| format!("{}: {e}", temporary.display()))?;
    let copy = (|| -> Result<String, String> {
        let mut hash = Sha256::new();
        let mut buffer = vec![0; 1 << 16];
        loop {
            let read = input.read(&mut buffer).map_err(|e| e.to_string())?;
            if read == 0 {
                break;
            }
            hash.update(&buffer[..read]);
            output
                .write_all(&buffer[..read])
                .map_err(|e| e.to_string())?;
        }
        output.sync_all().map_err(|e| e.to_string())?;
        Ok(hash.finalize()[..8]
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect())
    })();
    let hash = match copy {
        Ok(hash) => hash,
        Err(error) => {
            let _ = fs::remove_file(&temporary);
            return Err(format!("Cannot copy the background file: {error}"));
        }
    };
    let extension = source
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .filter(|e| e.chars().all(|c| c.is_ascii_alphanumeric()))
        .map(|e| format!(".{e}"))
        .unwrap_or_default();
    let target = dir.join(format!("{hash}-{}{extension}", safe_name(source)));
    let finish = fs::set_permissions(&temporary, fs::Permissions::from_mode(0o644))
        .and_then(|()| fs::rename(&temporary, &target));
    if let Err(error) = finish {
        let _ = fs::remove_file(&temporary);
        return Err(format!("Cannot save the background copy: {error}"));
    }
    Ok(target)
}

/// Removes copies nothing references. Only regular files directly in `dir` are touched.
pub fn collect_garbage(dir: &Path, keep: &[&str]) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let regular = entry.file_type().is_ok_and(|t| t.is_file());
        if regular && !keep.iter().any(|k| Path::new(k) == path) {
            let _ = fs::remove_file(path);
        }
    }
}

/// The name shown for a background, without the content hash of an owned copy.
pub fn display_name(path: &str) -> String {
    let name = Path::new(path)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_owned());
    match name.split_once('-') {
        Some((hash, rest)) if hash.len() == 16 && hash.chars().all(|c| c.is_ascii_hexdigit()) => {
            rest.to_owned()
        }
        _ => name,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_content_shares_one_copy_and_the_source_is_never_referenced() {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path().join("backgrounds");
        let source = root.path().join("my, photo.PNG");
        fs::write(&source, b"pixels").unwrap();
        let copy = import(&source, &dir).unwrap();
        assert_eq!(import(&source, &dir).unwrap(), copy);
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        assert!(copy.starts_with(&dir));
        let text = copy.to_string_lossy();
        assert!(!text.contains(',') && text.ends_with(".png"));
        assert_eq!(display_name(&text), "my__photo.png");
        fs::remove_file(&source).unwrap();
        assert_eq!(fs::read(&copy).unwrap(), b"pixels");
    }

    #[test]
    fn garbage_collection_keeps_referenced_copies() {
        let root = tempfile::tempdir().unwrap();
        let (keep, drop) = (root.path().join("keep"), root.path().join("drop"));
        fs::write(&keep, b"1").unwrap();
        fs::write(&drop, b"2").unwrap();
        fs::create_dir(root.path().join("sub")).unwrap();
        collect_garbage(root.path(), &[keep.to_str().unwrap()]);
        assert!(keep.exists() && !drop.exists() && root.path().join("sub").exists());
    }
}
