use gio::glib;
use std::fs::{self, Permissions};
use std::io::{ErrorKind, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

pub(crate) struct FileChange {
    pub path: PathBuf,
    original: Option<Vec<u8>>,
    permissions: Permissions,
    pub updated: Vec<u8>,
}

impl FileChange {
    pub fn prepare(path: &Path, edits: &[(&str, Option<String>)]) -> Result<Self, String> {
        Self::prepare_group(path, "Settings", edits)
    }

    /// Edits keys of one `[group]` in a key file, keeping every other line.
    pub fn prepare_group(
        path: &Path,
        group: &str,
        edits: &[(&str, Option<String>)],
    ) -> Result<Self, String> {
        Self::prepare_text(path, |content| edit_group(content, group, edits))
    }

    pub fn prepare_text(
        path: &Path,
        edit: impl FnOnce(&str) -> Result<String, String>,
    ) -> Result<Self, String> {
        let path = if path.is_symlink() {
            fs::canonicalize(path).map_err(|error| format!("{}: {error}", path.display()))?
        } else {
            path.to_owned()
        };
        let original = read_optional(&path)?;
        let permissions = if original.is_some() {
            fs::metadata(&path)
                .map_err(|error| error.to_string())?
                .permissions()
        } else {
            Permissions::from_mode(0o600)
        };
        let content = std::str::from_utf8(original.as_deref().unwrap_or_default())
            .map_err(|error| format!("{}: {error}", path.display()))?;
        let updated = edit(content)
            .map_err(|error| format!("{}: {error}", path.display()))?
            .into_bytes();
        Ok(Self {
            path,
            original,
            permissions,
            updated,
        })
    }

    pub fn changed(&self) -> bool {
        self.original.as_deref() != Some(&self.updated)
    }

    pub fn apply(&self) -> Result<(), String> {
        if read_optional(&self.path)? != self.original {
            return Err(format!(
                "{} changed externally; not overwritten",
                self.path.display()
            ));
        }
        atomic_write(&self.path, &self.updated, &self.permissions)?;
        if read_optional(&self.path)?.as_deref() != Some(&self.updated) {
            return Err(format!("Readback failed for {}", self.path.display()));
        }
        Ok(())
    }

    pub fn rollback(&self) -> Result<(), String> {
        let current = read_optional(&self.path)?;
        if current == self.original {
            return Ok(());
        }
        if current.as_deref() != Some(&self.updated) {
            return Err(format!(
                "{} changed externally during rollback",
                self.path.display()
            ));
        }
        match &self.original {
            Some(original) => atomic_write(&self.path, original, &self.permissions),
            None => fs::remove_file(&self.path).map_err(|error| error.to_string()),
        }
    }
}

pub(crate) fn read_optional(path: &Path) -> Result<Option<Vec<u8>>, String> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == ErrorKind::NotFound && !path.is_symlink() => Ok(None),
        Err(error) => Err(format!("{}: {error}", path.display())),
    }
}

fn atomic_write(path: &Path, bytes: &[u8], permissions: &Permissions) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or("Configuration has no parent directory")?;
    fs::create_dir_all(parent).map_err(|error| format!("{}: {error}", parent.display()))?;
    let mut staged = tempfile::NamedTempFile::new_in(parent).map_err(|error| error.to_string())?;
    staged.write_all(bytes).map_err(|error| error.to_string())?;
    staged
        .as_file()
        .set_permissions(permissions.clone())
        .map_err(|error| error.to_string())?;
    staged
        .as_file()
        .sync_all()
        .map_err(|error| error.to_string())?;
    staged
        .persist(path)
        .map_err(|error| format!("{}: {error}", path.display()))?;
    fs::File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|error| error.to_string())
}

pub(crate) fn key_file(content: &str) -> Result<glib::KeyFile, String> {
    let parsed = glib::KeyFile::new();
    if !content.trim().is_empty() {
        parsed
            .load_from_data(content, glib::KeyFileFlags::KEEP_COMMENTS)
            .map_err(|error| error.to_string())?;
    }
    Ok(parsed)
}

#[cfg(test)]
fn edit_settings(content: &str, edits: &[(&str, Option<String>)]) -> Result<String, String> {
    edit_group(content, "Settings", edits)
}

fn edit_group(
    content: &str,
    group: &str,
    edits: &[(&str, Option<String>)],
) -> Result<String, String> {
    key_file(content)?;
    let header = format!("[{group}]");
    let newline = if content.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let mut lines: Vec<String> = content.split_inclusive('\n').map(str::to_owned).collect();
    let groups: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter_map(|(index, line)| (line.trim() == header).then_some(index))
        .collect();
    if groups.len() > 1 {
        return Err(format!("Duplicate {header} sections"));
    }
    if groups.is_empty() {
        if !content.is_empty() && !content.ends_with('\n') {
            lines.push(newline.into());
        }
        lines.push(format!("{header}{newline}"));
    }
    let start = groups.first().copied().unwrap_or(lines.len() - 1) + 1;
    let mut end = lines
        .iter()
        .enumerate()
        .skip(start)
        .find_map(|(index, line)| line.trim_start().starts_with('[').then_some(index))
        .unwrap_or(lines.len());
    for (key, value) in edits {
        let mut found = false;
        let mut index = start;
        while index < end {
            let line = &lines[index];
            if let Some((prefix, _)) = line.split_once('=')
                && prefix.trim() == *key
            {
                found = true;
                if let Some(value) = value {
                    let ending = if line.ends_with("\r\n") {
                        "\r\n"
                    } else if line.ends_with('\n') {
                        "\n"
                    } else {
                        ""
                    };
                    lines[index] = format!("{prefix}={value}{ending}");
                } else {
                    lines.remove(index);
                    end -= 1;
                    continue;
                }
            }
            index += 1;
        }
        if !found && let Some(value) = value {
            if end > 0 && !lines[end - 1].ends_with('\n') {
                lines[end - 1].push_str(newline);
            }
            lines.insert(end, format!("{key}={value}{newline}"));
            end += 1;
        }
    }
    Ok(lines.concat())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn updates_only_settings_keys_and_preserves_comments_and_other_groups() {
        let original = "# Keep\r\n[Other]\r\nvalue=untouched\r\n[Settings]\r\n gtk-theme-name =adw-gtk3-dark\r\n# Font\r\ngtk-font-name=Example 11\r\ngtk-application-prefer-dark-theme=1\r\n";
        let result = edit_settings(
            original,
            &[
                ("gtk-theme-name", Some("adw-gtk3".into())),
                ("gtk-application-prefer-dark-theme", None),
                ("gtk-interface-color-scheme", Some("light".into())),
            ],
        )
        .unwrap();
        assert!(result.contains("[Other]\r\nvalue=untouched\r\n"));
        assert!(
            result.contains(" gtk-theme-name =adw-gtk3\r\n# Font\r\ngtk-font-name=Example 11\r\n")
        );
        assert!(!result.contains("gtk-application-prefer-dark-theme"));
        assert!(result.ends_with("gtk-interface-color-scheme=light\r\n"));
        assert!(edit_settings("broken", &[]).is_err());
        assert!(edit_settings("[Settings]\n[Settings]\n", &[]).is_err());
    }

    #[test]
    fn atomic_changes_keep_links_modes_and_can_restore_exact_bytes() {
        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("real.ini");
        fs::write(&target, "[Settings]\n# Preserve\ngtk-font-name=Example\n").unwrap();
        fs::set_permissions(&target, Permissions::from_mode(0o640)).unwrap();
        let original = fs::read(&target).unwrap();
        let link = directory.path().join("linked.ini");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        let change = FileChange::prepare(
            &link,
            &[("gtk-application-prefer-dark-theme", Some("1".into()))],
        )
        .unwrap();
        change.apply().unwrap();
        assert!(link.is_symlink());
        assert_eq!(
            fs::metadata(&target).unwrap().permissions().mode() & 0o777,
            0o640
        );
        change.rollback().unwrap();
        assert_eq!(fs::read(&target).unwrap(), original);
    }

    #[test]
    fn external_changes_and_invalid_files_are_never_overwritten() {
        let directory = tempfile::tempdir().unwrap();
        let file = directory.path().join("settings.ini");
        let change =
            FileChange::prepare(&file, &[("gtk-theme-name", Some("Adwaita".into()))]).unwrap();
        fs::write(&file, "[Settings]\n# External edit\n").unwrap();
        assert!(change.apply().is_err());
        assert!(fs::read_to_string(&file).unwrap().contains("External edit"));
        fs::write(&file, "not a key file").unwrap();
        assert!(FileChange::prepare(&file, &[]).is_err());
        assert_eq!(fs::read_to_string(&file).unwrap(), "not a key file");
    }
}
