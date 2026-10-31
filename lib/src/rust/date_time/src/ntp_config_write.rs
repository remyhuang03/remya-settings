use crate::ntp_config::{read, render, validate_servers};
use std::fs::{self, File};
use std::io::Write;
use std::path::Path;

fn replace(path: &Path, bytes: Option<&[u8]>) -> Result<(), String> {
    let parent = path.parent().ok_or("Missing configuration directory")?;
    if let Some(bytes) = bytes {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        if fs::symlink_metadata(parent)
            .map_err(|e| e.to_string())?
            .file_type()
            .is_symlink()
        {
            return Err("Refusing a symlink configuration directory".into());
        }
        let mut staged = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
        use std::os::unix::fs::PermissionsExt;
        staged
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o644))
            .map_err(|e| e.to_string())?;
        staged
            .write_all(bytes)
            .and_then(|_| staged.as_file().sync_all())
            .map_err(|e| e.to_string())?;
        staged.persist(path).map_err(|e| e.to_string())?;
    } else {
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(e) => return Err(e.to_string()),
        }
    }
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|e| e.to_string())
}

pub fn apply(
    path: &Path,
    servers: &[String],
    mut reload: impl FnMut(&[String]) -> Result<(), String>,
) -> Result<(), String> {
    validate_servers(servers)?;
    let previous = read(path)?;
    let before = match fs::read(path) {
        Ok(bytes) => Some(bytes),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.to_string()),
    };
    let content = (!servers.is_empty()).then(|| render(servers));
    replace(path, content.as_deref().map(str::as_bytes))?;
    if let Err(error) = reload(servers) {
        replace(path, before.as_deref())
            .map_err(|restore| format!("{error}; restoring configuration failed: {restore}"))?;
        reload(&previous).map_err(|restore| {
            format!("{error}; restoring time synchronization failed: {restore}")
        })?;
        return Err(error);
    }
    if read(path)? != servers {
        return Err("Persistent time server readback does not match the request".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persistence_default_and_failed_reload_preserve_other_files() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("90-remya-settings.conf");
        let other = root.path().join("60-admin.conf");
        fs::write(&other, "[Time]\nFallbackNTP=example.org\n").unwrap();
        let servers = vec!["pool.ntp.org".into(), "2001:db8::1".into()];
        apply(&path, &servers, |_| Ok(())).unwrap();
        assert_eq!(read(&path).unwrap(), servers);
        assert!(
            fs::read_to_string(&path)
                .unwrap()
                .contains("[Time]\nNTP=\nNTP=pool.ntp.org 2001:db8::1\n")
        );
        let before = fs::read(&path).unwrap();
        let mut calls = 0;
        assert!(
            apply(&path, &["other.org".into()], |_| {
                calls += 1;
                if calls == 1 {
                    Err("Restart failed".into())
                } else {
                    Ok(())
                }
            })
            .is_err()
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        apply(&path, &[], |_| Ok(())).unwrap();
        assert!(!path.exists());
        assert_eq!(
            fs::read_to_string(other).unwrap(),
            "[Time]\nFallbackNTP=example.org\n"
        );
        fs::write(&path, "personal content").unwrap();
        assert!(apply(&path, &servers, |_| Ok(())).is_err());
        assert_eq!(fs::read_to_string(path).unwrap(), "personal content");
    }
    #[test]
    fn rejects_injection_and_symlink_targets() {
        for value in [
            "",
            "https://ntp.org",
            "host:123",
            "a\nNTP=evil",
            "-bad",
            "x;reboot",
            "a..b",
        ] {
            assert!(validate_servers(&[value.into()]).is_err());
        }
        for value in ["pool.ntp.org", "192.0.2.1", "2001:db8::1"] {
            assert!(validate_servers(&[value.into()]).is_ok());
        }
        let root = tempfile::tempdir().unwrap();
        let target = root.path().join("personal");
        fs::write(&target, "keep").unwrap();
        let path = root.path().join("config");
        std::os::unix::fs::symlink(&target, &path).unwrap();
        assert!(apply(&path, &[], |_| Ok(())).is_err());
        assert_eq!(fs::read_to_string(target).unwrap(), "keep");
    }
}
