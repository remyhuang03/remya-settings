use std::{fs, io::Write, os::unix::fs::PermissionsExt, path::Path};

/// Replaces a file atomically, following symlinks and keeping its permissions.
pub fn atomic_write(path: &Path, content: &[u8]) -> Result<(), String> {
    let target = if path.is_symlink() {
        path.canonicalize().map_err(|e| e.to_string())?
    } else {
        path.to_owned()
    };
    let parent = target.parent().ok_or("No configuration directory")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    let mode = fs::metadata(&target)
        .map(|m| m.permissions().mode() & 0o777)
        .unwrap_or(0o600);
    file.as_file()
        .set_permissions(fs::Permissions::from_mode(mode))
        .map_err(|e| e.to_string())?;
    file.write_all(content)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|e| e.to_string())?;
    file.persist(target).map_err(|e| e.to_string())?;
    Ok(())
}
