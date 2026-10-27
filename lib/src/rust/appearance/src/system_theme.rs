use crate::api::{SystemThemeMode, SystemThemeState, ThemeTargetResult, ThemeTargetStatus};
use crate::environment::Environment;
use crate::files::{FileChange, key_file, read_optional};
use gio::glib::{self, variant::ToVariant};
use gio::prelude::*;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::process::Command;

const SCHEMA: &str = "org.gnome.desktop.interface";

struct Context {
    config: PathBuf,
    themes: Vec<PathBuf>,
    gtk4: bool,
    gnome: Option<gio::Settings>,
    verify_backend: bool,
    environment: Environment,
}

impl Context {
    fn current() -> Result<Self, String> {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute());
        let config = env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| home.as_ref().map(|path| path.join(".config")))
            .ok_or("An absolute HOME or XDG_CONFIG_HOME is required")?;
        let mut themes = vec![];
        if let Some(data) = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
        {
            themes.push(data.join("themes"));
        } else if let Some(home) = &home {
            themes.push(home.join(".local/share/themes"));
        }
        if let Some(home) = &home {
            themes.push(home.join(".themes"));
        }
        let data_dirs = env::var("XDG_DATA_DIRS")
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
        themes.extend(
            data_dirs
                .split(':')
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .map(|path| path.join("themes")),
        );
        let gtk4 = config.join("gtk-4.0/settings.ini").exists()
            || Command::new("ldconfig")
                .arg("-p")
                .output()
                .is_ok_and(|output| {
                    output.status.success()
                        && String::from_utf8_lossy(&output.stdout).contains("libgtk-4.so.1")
                });
        let gnome = gio::SettingsSchemaSource::default()
            .and_then(|source| source.lookup(SCHEMA, true))
            .map(|schema| gio::Settings::new_full(&schema, None::<&gio::SettingsBackend>, None));
        let environment = Environment::current(&config)?;
        Ok(Self {
            config,
            themes,
            gtk4,
            gnome,
            verify_backend: true,
            environment,
        })
    }

    fn lock(&self) -> Result<File, String> {
        let directory = self.config.join("remya/settings");
        fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(directory.join(".system-theme.lock"))
            .map_err(|error| error.to_string())?;
        lock.try_lock()
            .map_err(|error| format!("Another appearance update is in progress: {error}"))?;
        Ok(lock)
    }
}

impl SystemThemeMode {
    fn name(self) -> &'static str {
        match self {
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }
    fn scheme(self) -> &'static str {
        match self {
            Self::Light => "prefer-light",
            Self::Dark => "prefer-dark",
        }
    }
    fn gtk3(self) -> &'static str {
        match self {
            Self::Light => "0",
            Self::Dark => "1",
        }
    }
}

fn result(name: &str, status: ThemeTargetStatus, detail: impl Into<String>) -> ThemeTargetResult {
    ThemeTargetResult {
        name: name.into(),
        status,
        detail: detail.into(),
    }
}

fn gtk_settings(context: &Context, toolkit: &str) -> Result<glib::KeyFile, String> {
    let path = context.config.join(toolkit).join("settings.ini");
    let bytes = read_optional(&path)?.unwrap_or_default();
    let text =
        std::str::from_utf8(&bytes).map_err(|error| format!("{}: {error}", path.display()))?;
    key_file(text).map_err(|error| format!("{}: {error}", path.display()))
}

fn gtk_mode(settings: &glib::KeyFile, gtk4: bool) -> Option<SystemThemeMode> {
    if gtk4 {
        match settings
            .string("Settings", "gtk-interface-color-scheme")
            .ok()?
            .as_str()
        {
            "dark" | "2" => Some(SystemThemeMode::Dark),
            "light" | "3" => Some(SystemThemeMode::Light),
            _ => None,
        }
    } else {
        match settings
            .string("Settings", "gtk-application-prefer-dark-theme")
            .ok()
            .as_deref()
        {
            Some("1" | "true") => Some(SystemThemeMode::Dark),
            Some("0" | "false") => Some(SystemThemeMode::Light),
            _ => None,
        }
    }
}

fn read_context(context: &Context) -> Result<SystemThemeState, String> {
    let mut mode = None;
    let mut targets = vec![];
    if let Some(settings) = &context.gnome {
        if settings
            .settings_schema()
            .is_some_and(|schema| schema.has_key("color-scheme"))
        {
            let value = settings.string("color-scheme");
            mode = match value.as_str() {
                "prefer-dark" => Some(SystemThemeMode::Dark),
                "prefer-light" => Some(SystemThemeMode::Light),
                _ => None,
            };
            targets.push(result(
                "GNOME / libadwaita",
                ThemeTargetStatus::Detected,
                format!("color-scheme={value}"),
            ));
        } else {
            targets.push(result(
                "GNOME / libadwaita",
                ThemeTargetStatus::Unavailable,
                "Color-scheme schema key is not installed",
            ));
        }
    } else {
        targets.push(result(
            "GNOME / libadwaita",
            ThemeTargetStatus::Unavailable,
            "GNOME settings schema is not installed",
        ));
    }
    for (name, toolkit, is_gtk4) in [("GTK 3", "gtk-3.0", false), ("GTK 4", "gtk-4.0", true)] {
        if is_gtk4 && !context.gtk4 {
            targets.push(result(
                name,
                ThemeTargetStatus::Unavailable,
                "Toolkit is not installed",
            ));
            continue;
        }
        let settings = gtk_settings(context, toolkit)?;
        let detected = gtk_mode(&settings, is_gtk4);
        mode = mode.or(detected);
        let detail = detected
            .map(|value| format!("{} preference", value.name()))
            .unwrap_or_else(|| "No explicit user color preference".into());
        targets.push(result(name, ThemeTargetStatus::Detected, detail));
    }
    if mode.is_none()
        && let Some(settings) = &context.gnome
        && settings
            .settings_schema()
            .is_some_and(|schema| schema.has_key("gtk-theme"))
    {
        let theme = settings.string("gtk-theme");
        mode = Some(if theme.to_lowercase().ends_with("-dark") {
            SystemThemeMode::Dark
        } else {
            SystemThemeMode::Light
        });
    }
    targets.extend(context.environment.read()?);
    Ok(SystemThemeState { mode, targets })
}

fn theme_exists(name: &str, roots: &[PathBuf]) -> bool {
    if name.contains('/') || matches!(name, "." | "..") {
        return false;
    }
    matches!(name, "Adwaita" | "Adwaita-dark")
        || roots.iter().any(|root| {
            ["gtk-3.0/gtk.css", "gtk-4.0/gtk.css"]
                .iter()
                .any(|css| root.join(name).join(css).is_file())
        })
}

fn theme_variant(current: &str, mode: SystemThemeMode, roots: &[PathBuf]) -> Option<String> {
    if current.contains('/')
        || current.chars().any(char::is_control)
        || matches!(current, "." | ".." | "")
    {
        return None;
    }
    let lower = current.to_lowercase();
    let candidates = match mode {
        SystemThemeMode::Dark if lower.ends_with("-dark") => return Some(current.into()),
        SystemThemeMode::Dark => {
            let base = if lower.ends_with("-light") {
                &current[..current.len() - 6]
            } else {
                current
            };
            vec![format!("{base}-dark"), format!("{base}-Dark")]
        }
        SystemThemeMode::Light if lower.ends_with("-dark") => {
            let base = &current[..current.len() - 5];
            vec![
                base.into(),
                format!("{base}-light"),
                format!("{base}-Light"),
            ]
        }
        SystemThemeMode::Light => return Some(current.into()),
    };
    candidates
        .into_iter()
        .find(|candidate| theme_exists(candidate, roots))
}

struct SettingChange {
    key: &'static str,
    original: Option<glib::Variant>,
    previous: glib::Variant,
    value: glib::Variant,
}

fn setting_change(
    settings: &gio::Settings,
    key: &'static str,
    value: &str,
) -> Result<Option<SettingChange>, String> {
    let schema = settings
        .settings_schema()
        .ok_or("Missing GNOME settings schema")?;
    if !schema.has_key(key) {
        return Ok(None);
    }
    let value = value.to_variant();
    if settings.value(key) == value {
        return Ok(None);
    }
    if !settings.is_writable(key) {
        return Err(format!(
            "GNOME {key} is locked; no appearance settings were changed"
        ));
    }
    if !schema.key(key).range_check(&value) {
        return Err(format!("GNOME {key} rejects the requested value"));
    }
    Ok(Some(SettingChange {
        key,
        original: settings.user_value(key),
        previous: settings.value(key),
        value,
    }))
}

struct AppearancePlan {
    settings_changes: Vec<SettingChange>,
    files: Vec<FileChange>,
    targets: Vec<ThemeTargetResult>,
    mode: SystemThemeMode,
}

fn prepare_context(context: &Context, mode: SystemThemeMode) -> Result<AppearancePlan, String> {
    let mut settings_changes = vec![];
    let mut targets = vec![];
    if let Some(settings) = &context.gnome {
        let schema = settings.settings_schema().ok_or("Missing GNOME schema")?;
        if schema.has_key("color-scheme") {
            let change = setting_change(settings, "color-scheme", mode.scheme())?;
            targets.push(result(
                "GNOME / libadwaita",
                if change.is_some() {
                    ThemeTargetStatus::Applied
                } else {
                    ThemeTargetStatus::Unchanged
                },
                format!("color-scheme={}", mode.scheme()),
            ));
            settings_changes.extend(change);
        } else {
            targets.push(result(
                "GNOME / libadwaita",
                ThemeTargetStatus::Unavailable,
                "Color-scheme schema key is not installed",
            ));
        }
        if schema.has_key("gtk-theme") {
            let current = settings.string("gtk-theme");
            if let Some(name) = theme_variant(&current, mode, &context.themes) {
                let change = setting_change(settings, "gtk-theme", &name)?;
                targets.push(result(
                    "GTK theme variant",
                    if change.is_some() {
                        ThemeTargetStatus::Applied
                    } else {
                        ThemeTargetStatus::Unchanged
                    },
                    name,
                ));
                settings_changes.extend(change);
            } else {
                targets.push(result(
                    "GTK theme variant",
                    ThemeTargetStatus::Unavailable,
                    "No matching installed theme variant; the selected theme is retained",
                ));
            }
        }
    } else {
        targets.push(result(
            "GNOME / libadwaita",
            ThemeTargetStatus::Unavailable,
            "GNOME settings schema is not installed",
        ));
    }
    let mut files = vec![];
    for (name, toolkit, is_gtk4) in [("GTK 3", "gtk-3.0", false), ("GTK 4", "gtk-4.0", true)] {
        if is_gtk4 && !context.gtk4 {
            targets.push(result(
                name,
                ThemeTargetStatus::Unavailable,
                "Toolkit is not installed",
            ));
            continue;
        }
        let settings = gtk_settings(context, toolkit)?;
        let mut edits = if is_gtk4 {
            vec![
                ("gtk-interface-color-scheme", Some(mode.name().into())),
                ("gtk-application-prefer-dark-theme", None),
            ]
        } else {
            vec![(
                "gtk-application-prefer-dark-theme",
                Some(mode.gtk3().into()),
            )]
        };
        if let Ok(current) = settings.string("Settings", "gtk-theme-name")
            && let Some(name) = theme_variant(&current, mode, &context.themes)
        {
            edits.push(("gtk-theme-name", Some(name)));
        }
        let file = FileChange::prepare(&context.config.join(toolkit).join("settings.ini"), &edits)?;
        targets.push(result(
            name,
            if file.changed() {
                ThemeTargetStatus::Applied
            } else {
                ThemeTargetStatus::Unchanged
            },
            format!(
                "{}={}",
                if is_gtk4 {
                    "gtk-interface-color-scheme"
                } else {
                    "gtk-application-prefer-dark-theme"
                },
                if is_gtk4 { mode.name() } else { mode.gtk3() }
            ),
        ));
        files.push(file);
    }
    let (environment_files, environment_targets) = context.environment.prepare(mode)?;
    files.extend(environment_files);
    targets.extend(environment_targets);
    Ok(AppearancePlan {
        settings_changes,
        files,
        targets,
        mode,
    })
}

fn verify_setting(
    settings: &gio::Settings,
    key: &str,
    expected: &glib::Variant,
    fresh_process: bool,
) -> Result<(), String> {
    if settings.value(key) != *expected || read_setting(settings, key, fresh_process)? != *expected
    {
        return Err(format!("GNOME {key} readback failed"));
    }
    Ok(())
}

fn read_setting(
    settings: &gio::Settings,
    key: &str,
    fresh_process: bool,
) -> Result<glib::Variant, String> {
    if fresh_process {
        let read = Command::new("gsettings")
            .args(["get", SCHEMA, key])
            .output()
            .map_err(|error| format!("Cannot independently verify GNOME {key}: {error}"))?;
        if !read.status.success() {
            return Err(format!("Cannot independently verify GNOME {key}"));
        }
        let text = String::from_utf8(read.stdout).map_err(|error| error.to_string())?;
        glib::Variant::parse(None, text.trim()).map_err(|error| error.to_string())
    } else {
        Ok(settings.value(key))
    }
}

impl AppearancePlan {
    fn apply(self, context: &Context) -> Result<SystemThemeState, String> {
        let Self {
            settings_changes,
            files,
            targets,
            mode,
        } = self;
        let mut attempted_files = 0;
        let mut settings_attempted = false;
        let update = (|| -> Result<(), String> {
            for file in &files {
                attempted_files += 1;
                if file.changed() {
                    file.apply()?;
                }
            }
            if let Some(settings) = &context.gnome {
                for change in &settings_changes {
                    if read_setting(settings, change.key, context.verify_backend)?
                        != change.previous
                    {
                        return Err(format!(
                            "GNOME {} changed externally; not overwritten",
                            change.key
                        ));
                    }
                }
                settings.delay();
                settings_attempted = true;
                for change in &settings_changes {
                    settings
                        .set_value(change.key, &change.value)
                        .map_err(|error| error.to_string())?;
                }
                settings.apply();
                gio::Settings::sync();
                for change in &settings_changes {
                    verify_setting(settings, change.key, &change.value, context.verify_backend)?;
                }
            }
            Ok(())
        })();
        if let Err(error) = update {
            let mut rollback_errors = vec![];
            if settings_attempted && let Some(settings) = &context.gnome {
                settings.revert();
                for change in &settings_changes {
                    match read_setting(settings, change.key, context.verify_backend) {
                        Ok(current) if current == change.previous => continue,
                        Ok(current) if current == change.value => {}
                        _ => {
                            rollback_errors.push(format!(
                                "GNOME {} changed externally or cannot be read; retained",
                                change.key
                            ));
                            continue;
                        }
                    }
                    if let Some(original) = &change.original {
                        if let Err(error) = settings.set_value(change.key, original) {
                            rollback_errors.push(error.to_string());
                        }
                    } else {
                        settings.reset(change.key);
                    }
                }
                settings.apply();
                gio::Settings::sync();
                for change in &settings_changes {
                    if let Err(error) = verify_setting(
                        settings,
                        change.key,
                        &change.previous,
                        context.verify_backend,
                    ) {
                        rollback_errors.push(error);
                    }
                }
            }
            for file in files[..attempted_files]
                .iter()
                .rev()
                .filter(|file| file.changed())
            {
                if let Err(error) = file.rollback() {
                    rollback_errors.push(error);
                }
            }
            return Err(if rollback_errors.is_empty() {
                format!("{error}. Changes were rolled back")
            } else {
                format!(
                    "{error}. Rollback incomplete: {}",
                    rollback_errors.join("; ")
                )
            });
        }
        Ok(SystemThemeState {
            mode: Some(mode),
            targets,
        })
    }
}

fn apply_context(context: &Context, mode: SystemThemeMode) -> Result<SystemThemeState, String> {
    let _lock = context.lock()?;
    prepare_context(context, mode)?.apply(context)
}

pub(crate) fn read() -> Result<SystemThemeState, String> {
    read_context(&Context::current()?)
}
pub(crate) fn apply(mode: SystemThemeMode) -> Result<SystemThemeState, String> {
    apply_context(&Context::current()?, mode)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn theme_names_cannot_escape_the_theme_directory_or_inject_ini_keys() {
        for name in ["../Adwaita", "/Adwaita-dark", "..", "", "Adwaita\n[Other]"] {
            assert!(theme_variant(name, SystemThemeMode::Dark, &[]).is_none());
            assert!(theme_variant(name, SystemThemeMode::Light, &[]).is_none());
        }
    }

    fn context(config: &Path) -> Context {
        let schemas = config.join("schemas");
        fs::create_dir_all(&schemas).unwrap();
        fs::write(schemas.join("appearance.gschema.xml"), r#"<schemalist>
<schema id="org.gnome.desktop.interface" path="/org/gnome/desktop/interface/">
<key name="color-scheme" type="s"><default>'default'</default><choices><choice value="default"/><choice value="prefer-dark"/><choice value="prefer-light"/></choices></key>
<key name="gtk-theme" type="s"><default>'Adwaita'</default></key>
</schema></schemalist>"#).unwrap();
        assert!(
            Command::new("glib-compile-schemas")
                .arg(&schemas)
                .status()
                .unwrap()
                .success()
        );
        let source = gio::SettingsSchemaSource::from_directory(&schemas, None, false).unwrap();
        let schema = source.lookup(SCHEMA, false).unwrap();
        let memory = gio::memory_settings_backend_new();
        Context {
            config: config.into(),
            themes: vec![config.join("themes")],
            gtk4: true,
            gnome: Some(gio::Settings::new_full(&schema, Some(&memory), None)),
            verify_backend: false,
            environment: Environment::default(),
        }
    }

    #[test]
    fn applies_both_modes_to_gnome_and_modern_gtk_without_touching_other_values() {
        let directory = tempfile::tempdir().unwrap();
        let context = context(directory.path());
        for theme in ["adw-gtk3", "adw-gtk3-dark"] {
            let path = context.themes[0].join(theme).join("gtk-3.0");
            fs::create_dir_all(&path).unwrap();
            fs::write(path.join("gtk.css"), "").unwrap();
        }
        context
            .gnome
            .as_ref()
            .unwrap()
            .set_string("gtk-theme", "adw-gtk3-dark")
            .unwrap();
        for toolkit in ["gtk-3.0", "gtk-4.0"] {
            fs::create_dir_all(context.config.join(toolkit)).unwrap();
            fs::write(context.config.join(toolkit).join("settings.ini"), "# Keep\n[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-font-name=Example 11\ngtk-application-prefer-dark-theme=1\n").unwrap();
        }
        for mode in [SystemThemeMode::Light, SystemThemeMode::Dark] {
            let state = apply_context(&context, mode).unwrap();
            assert_eq!(state.mode, Some(mode));
            assert_eq!(
                context.gnome.as_ref().unwrap().string("color-scheme"),
                mode.scheme()
            );
            for toolkit in ["gtk-3.0", "gtk-4.0"] {
                let text =
                    fs::read_to_string(context.config.join(toolkit).join("settings.ini")).unwrap();
                assert!(text.contains("# Keep\n"));
                assert!(text.contains("gtk-font-name=Example 11"));
                assert!(text.contains(if mode == SystemThemeMode::Dark {
                    "gtk-theme-name=adw-gtk3-dark"
                } else {
                    "gtk-theme-name=adw-gtk3\n"
                }));
            }
            let gtk4 = fs::read_to_string(context.config.join("gtk-4.0/settings.ini")).unwrap();
            assert!(gtk4.contains(&format!("gtk-interface-color-scheme={}", mode.name())));
            assert!(!gtk4.contains("gtk-application-prefer-dark-theme"));
            assert_eq!(read_context(&context).unwrap().mode, Some(mode));
        }
    }

    #[test]
    fn invalid_gtk_file_prevents_all_changes_and_unknown_theme_is_preserved() {
        let directory = tempfile::tempdir().unwrap();
        let context = context(directory.path());
        context
            .gnome
            .as_ref()
            .unwrap()
            .set_string("gtk-theme", "Custom-No-Pair")
            .unwrap();
        fs::create_dir_all(context.config.join("gtk-4.0")).unwrap();
        fs::write(context.config.join("gtk-4.0/settings.ini"), "malformed").unwrap();
        assert!(apply_context(&context, SystemThemeMode::Dark).is_err());
        assert_eq!(
            context.gnome.as_ref().unwrap().string("color-scheme"),
            "default"
        );
        assert!(!context.config.join("gtk-3.0/settings.ini").exists());
        fs::write(context.config.join("gtk-4.0/settings.ini"), "[Settings]\n").unwrap();
        let report = apply_context(&context, SystemThemeMode::Dark).unwrap();
        assert_eq!(
            context.gnome.as_ref().unwrap().string("gtk-theme"),
            "Custom-No-Pair"
        );
        assert!(
            report
                .targets
                .iter()
                .any(|target| target.name == "GTK theme variant"
                    && target.status == ThemeTargetStatus::Unavailable)
        );
    }

    #[test]
    fn absent_optional_targets_are_reported_without_installing_anything() {
        let directory = tempfile::tempdir().unwrap();
        let context = Context {
            config: directory.path().into(),
            themes: vec![],
            gtk4: false,
            gnome: None,
            verify_backend: false,
            environment: Environment::default(),
        };
        let report = apply_context(&context, SystemThemeMode::Dark).unwrap();
        assert_eq!(
            report
                .targets
                .iter()
                .filter(|target| target.status == ThemeTargetStatus::Unavailable)
                .count(),
            6
        );
        assert!(!context.config.join("gtk-4.0").exists());
        assert!(context.config.join("gtk-3.0/settings.ini").exists());
    }
    #[test]
    fn commit_conflicts_restore_prior_writes_without_destroying_external_edits() {
        let directory = tempfile::tempdir().unwrap();
        let context = context(directory.path());
        let plan = prepare_context(&context, SystemThemeMode::Dark).unwrap();
        let external = context.config.join("gtk-4.0/settings.ini");
        fs::create_dir_all(external.parent().unwrap()).unwrap();
        fs::write(&external, "[Settings]\n# Changed externally\n").unwrap();
        assert!(plan.apply(&context).is_err());
        assert!(!context.config.join("gtk-3.0/settings.ini").exists());
        assert!(
            fs::read_to_string(external)
                .unwrap()
                .contains("Changed externally")
        );
        assert_eq!(
            context.gnome.as_ref().unwrap().string("color-scheme"),
            "default"
        );
    }

    #[test]
    fn gnome_conflicts_restore_files_and_keep_external_preferences() {
        let directory = tempfile::tempdir().unwrap();
        let context = context(directory.path());
        let plan = prepare_context(&context, SystemThemeMode::Dark).unwrap();
        context
            .gnome
            .as_ref()
            .unwrap()
            .set_string("color-scheme", "prefer-light")
            .unwrap();
        assert!(
            plan.apply(&context)
                .unwrap_err()
                .contains("changed externally")
        );
        assert_eq!(
            context.gnome.as_ref().unwrap().string("color-scheme"),
            "prefer-light"
        );
        assert!(!context.config.join("gtk-3.0/settings.ini").exists());
        assert!(!context.config.join("gtk-4.0/settings.ini").exists());
    }

    #[test]
    fn locked_gnome_values_fail_before_touching_gtk_files() {
        let directory = tempfile::tempdir().unwrap();
        let mut context = context(directory.path());
        let schema = context.gnome.as_ref().unwrap().settings_schema().unwrap();
        let locked = gio::null_settings_backend_new();
        context.gnome = Some(gio::Settings::new_full(&schema, Some(&locked), None));
        assert!(apply_context(&context, SystemThemeMode::Dark).is_err());
        assert!(!context.config.join("gtk-3.0/settings.ini").exists());
    }
}
