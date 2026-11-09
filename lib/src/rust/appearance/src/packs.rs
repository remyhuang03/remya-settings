//! Icon and cursor theme packs: discovery in the icon search path, cursor previews,
//! installation into the user's icon folder, and the selected cursor and icon themes.
//!
//! The selection is stored by GNOME's interface settings, which GTK and Hyprland
//! (`cursor:sync_gsettings_theme`) follow; Settings keeps its own copy in
//! `themes.toml` for reconciliation and writes the documented toolkit settings too.
use crate::api::{ThemeTargetResult, ThemeTargetStatus};
use crate::files::FileChange;
use crate::system_theme::{AppearancePlan, Context, result, setting_change};
use base64::Engine;
use gio::glib::{self, variant::ToVariant};
use gio::prelude::*;
use remya_settings_display::{Hyprctl, atomic_write, run_bytes};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

pub const CURSOR_THEME: &str = "cursor.theme";
pub const CURSOR_SIZE: &str = "cursor.size";
pub const CURSOR_INSTALL: &str = "cursor.install";
pub const CURSOR_REMOVE: &str = "cursor.remove";
pub const CURSOR_FOLDERS: &str = "cursor.folders";
pub const ICON_THEME: &str = "themes.icon-theme";
pub const ICON_INSTALL: &str = "themes.icon-install";
pub const ICON_REMOVE: &str = "themes.icon-remove";
/// `Get cursor-preview:<theme>` returns the theme's preview images.
pub const PREVIEW: &str = "cursor-preview:";
pub const IDS: [&str; 8] = [
    CURSOR_THEME,
    CURSOR_SIZE,
    CURSOR_INSTALL,
    CURSOR_REMOVE,
    CURSOR_FOLDERS,
    ICON_THEME,
    ICON_INSTALL,
    ICON_REMOVE,
];
pub const SIZES: std::ops::RangeInclusive<i32> = 8..=256;

const CURSOR_MARKER: &str = "Remy'a Settings cursor";
const ARCHIVE_LIMIT: u64 = 512 * 1024 * 1024;
const EXTRACTED_LIMIT: u64 = 2 * 1024 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(120);

fn invalid(message: impl std::fmt::Display) -> String {
    format!("InvalidArgument:{message}")
}

/// A theme folder name Settings may place in configuration and paths.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 255
        && !matches!(name, "." | "..")
        && !name.starts_with('.')
        && !name
            .chars()
            .any(|c| c.is_control() || matches!(c, '/' | '"' | '\\' | '$' | '`'))
}

/// The folders searched for themes, in priority order.
#[derive(Clone, Debug)]
pub struct Roots {
    /// Where Settings installs packs: `$XDG_DATA_HOME/icons`.
    pub user: PathBuf,
    pub home: PathBuf,
    /// The freedesktop icon theme search path.
    pub icons: Vec<PathBuf>,
    /// The XCursor search path: `XCURSOR_PATH` when set, otherwise the icon path.
    pub cursors: Vec<PathBuf>,
}

impl Roots {
    pub fn current() -> Result<Self, String> {
        let absolute = |name: &str| {
            std::env::var_os(name)
                .map(PathBuf::from)
                .filter(|p| p.is_absolute())
        };
        let home = absolute("HOME").ok_or("An absolute HOME is required")?;
        let data = absolute("XDG_DATA_HOME").unwrap_or_else(|| home.join(".local/share"));
        let dirs = std::env::var("XDG_DATA_DIRS")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
        let cursor_path = std::env::var("XCURSOR_PATH").ok();
        Ok(Self::new(home, data, &dirs, cursor_path.as_deref()))
    }

    pub fn new(home: PathBuf, data: PathBuf, data_dirs: &str, cursor_path: Option<&str>) -> Self {
        let user = data.join("icons");
        let mut icons = vec![user.clone(), home.join(".icons")];
        icons.extend(
            data_dirs
                .split(':')
                .map(PathBuf::from)
                .filter(|p| p.is_absolute())
                .map(|p| p.join("icons")),
        );
        icons.push("/usr/share/pixmaps".into());
        dedupe(&mut icons);
        let mut cursors = match cursor_path.filter(|p| !p.is_empty()) {
            Some(path) => path
                .split(':')
                .filter_map(|p| match p.strip_prefix("~/") {
                    Some(rest) => Some(home.join(rest)),
                    None => Some(PathBuf::from(p)).filter(|p| p.is_absolute()),
                })
                .collect(),
            None => icons.clone(),
        };
        dedupe(&mut cursors);
        Self {
            user,
            home,
            icons,
            cursors,
        }
    }

    /// Every searched folder with its purpose, for the folder list on the pages.
    pub fn folders(&self) -> Vec<Value> {
        let mut all = self.icons.clone();
        all.extend(self.cursors.iter().cloned());
        dedupe(&mut all);
        all.iter()
            .map(|path| {
                json!({
                    "path": path.display().to_string(),
                    "icons": self.icons.contains(path),
                    "cursors": self.cursors.contains(path),
                    "user": *path == self.user,
                    "exists": path.is_dir(),
                })
            })
            .collect()
    }
}

fn dedupe(paths: &mut Vec<PathBuf>) {
    let mut seen = vec![];
    paths.retain(|p| {
        let fresh = !seen.contains(p);
        seen.push(p.clone());
        fresh
    });
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Pack {
    pub id: String,
    pub name: String,
    pub comment: String,
    /// An icon theme: `index.theme` lists icon directories.
    pub icons: bool,
    /// An XCursor theme: a `cursors` folder.
    pub cursors: bool,
    /// A Hyprcursor theme: a `hyprcursors` folder with a manifest.
    pub scalable: bool,
    /// `Hidden=true`: a fallback theme left out of pickers unless it is in use.
    pub hidden: bool,
    /// Installed in the user's folder, so Settings may remove it.
    pub user: bool,
    pub path: String,
}

fn index(dir: &Path) -> Option<glib::KeyFile> {
    let file = glib::KeyFile::new();
    file.load_from_file(dir.join("index.theme"), glib::KeyFileFlags::NONE)
        .ok()?;
    Some(file)
}

fn inspect(dir: &Path, id: &str) -> Pack {
    let theme = index(dir);
    let text = |key: &str| {
        theme
            .as_ref()
            .and_then(|t| t.locale_string("Icon Theme", key, None).ok())
            .map(|s| s.to_string())
            .unwrap_or_default()
    };
    let hidden = theme
        .as_ref()
        .and_then(|t| t.boolean("Icon Theme", "Hidden").ok())
        .unwrap_or(false);
    let cursors = dir.join("cursors");
    let hyprcursors = dir.join("hyprcursors");
    Pack {
        id: id.into(),
        name: Some(text("Name"))
            .filter(|n| !n.is_empty())
            .unwrap_or(id.into()),
        comment: text("Comment"),
        icons: id != "hicolor" && !text("Directories").trim().is_empty(),
        cursors: ["default", "left_ptr"]
            .iter()
            .any(|n| cursors.join(n).exists()),
        scalable: hyprcursors.is_dir()
            && ["manifest.hl", "manifest.toml"]
                .iter()
                .any(|m| dir.join(m).is_file()),
        hidden,
        user: false,
        path: dir.display().to_string(),
    }
}

/// Installed themes by folder name; earlier roots take precedence, as in lookups.
pub fn list(roots: &Roots) -> Vec<Pack> {
    let mut found: BTreeMap<String, Pack> = BTreeMap::new();
    let mut all = roots.icons.clone();
    all.extend(roots.cursors.iter().cloned());
    dedupe(&mut all);
    for root in &all {
        let Ok(entries) = fs::read_dir(root) else {
            continue;
        };
        for entry in entries.flatten() {
            let Some(id) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            if !valid_name(&id) || id == "default" || !entry.path().is_dir() {
                continue;
            }
            let mut pack = inspect(&entry.path(), &id);
            pack.icons &= roots.icons.contains(root);
            pack.cursors &= roots.cursors.contains(root);
            pack.scalable &= roots.cursors.contains(root);
            pack.user = *root == roots.user;
            match found.get_mut(&id) {
                Some(first) => {
                    // A theme may be split over several roots; the first one names it.
                    first.icons |= pack.icons;
                    first.cursors |= pack.cursors;
                    first.scalable |= pack.scalable;
                }
                None => {
                    found.insert(id, pack);
                }
            }
        }
    }
    let mut packs: Vec<_> = found
        .into_values()
        .filter(|p| p.icons || p.cursors || p.scalable)
        .collect();
    packs.sort_by_key(|p| p.name.to_lowercase());
    packs
}

/// The cursor images shown on a theme card, by role and freedesktop cursor names.
const PREVIEW_CURSORS: [(&str, &[&str]); 4] = [
    ("pointer", &["default", "left_ptr"]),
    ("text", &["text", "xterm"]),
    ("link", &["pointer", "hand2", "hand1"]),
    ("busy", &["wait", "watch"]),
];

fn png(image: &xcursor::parser::Image) -> Result<String, String> {
    let mut bytes = vec![];
    let mut encoder = png::Encoder::new(&mut bytes, image.width, image.height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
    writer
        .write_image_data(&image.pixels_rgba)
        .map_err(|e| e.to_string())?;
    writer.finish().map_err(|e| e.to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(bytes))
}

/// Finds a cursor file in `theme`, following `Inherits` like libXcursor.
fn cursor_file(roots: &Roots, theme: &str, names: &[&str], depth: usize) -> Option<PathBuf> {
    if depth > 8 {
        return None;
    }
    for root in &roots.cursors {
        let dir = root.join(theme);
        if let Some(file) = names
            .iter()
            .map(|n| dir.join("cursors").join(n))
            .find(|p| p.is_file())
        {
            return Some(file);
        }
    }
    let parents = roots.cursors.iter().find_map(|r| {
        index(&r.join(theme))?
            .string("Icon Theme", "Inherits")
            .ok()
            .map(|s| s.to_string())
    })?;
    parents
        .split([',', ';'])
        .map(str::trim)
        .filter(|p| valid_name(p) && *p != theme)
        .find_map(|p| cursor_file(roots, p, names, depth + 1))
}

/// Preview images of `theme` at the nominal size nearest to `size`.
pub fn cursor_preview(roots: &Roots, theme: &str, size: u32) -> Result<Value, String> {
    if !valid_name(theme) {
        return Err(invalid("Unknown cursor theme"));
    }
    let pack = list(roots)
        .into_iter()
        .find(|p| p.id == theme && (p.cursors || p.scalable))
        .ok_or_else(|| invalid("Unknown cursor theme"))?;
    let mut sizes = vec![];
    let mut images = vec![];
    for (role, names) in PREVIEW_CURSORS {
        let Some(file) = cursor_file(roots, theme, names, 0) else {
            continue;
        };
        let Some(all) = fs::read(&file)
            .ok()
            .and_then(|b| xcursor::parser::parse_xcursor(&b))
        else {
            continue;
        };
        let mut nominal: Vec<u32> = all.iter().map(|i| i.size).collect();
        nominal.sort_unstable();
        nominal.dedup();
        if sizes.is_empty() {
            sizes = nominal.clone();
        }
        let pick = nominal
            .iter()
            .copied()
            .find(|s| *s >= size)
            .or(nominal.last().copied());
        let Some(image) = pick.and_then(|s| all.iter().find(|i| i.size == s)) else {
            continue;
        };
        images.push(json!({
            "role": role,
            "png": png(image)?,
            "size": image.size,
            "width": image.width,
            "height": image.height,
            "xhot": image.xhot,
            "yhot": image.yhot,
        }));
    }
    Ok(json!({"id": pack.id, "sizes": sizes, "images": images, "scalable": pack.scalable}))
}

fn tree_size(path: &Path) -> Result<u64, String> {
    let meta = fs::symlink_metadata(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let kind = meta.file_type();
    if kind.is_symlink() {
        return Ok(0);
    }
    if kind.is_file() {
        return Ok(meta.len());
    }
    if !kind.is_dir() {
        return Err(invalid(format!(
            "{} is not a regular file or folder",
            path.display()
        )));
    }
    let mut total = 0;
    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        total += tree_size(&entry.map_err(|e| e.to_string())?.path())?;
        if total > EXTRACTED_LIMIT {
            return Err(invalid("The theme is larger than 2 GiB"));
        }
    }
    Ok(total)
}

/// Copies a folder, keeping symbolic links as links (cursor themes rely on them).
fn copy_tree(from: &Path, to: &Path) -> Result<(), String> {
    let meta = fs::symlink_metadata(from).map_err(|e| e.to_string())?;
    if meta.file_type().is_symlink() {
        let target = fs::read_link(from).map_err(|e| e.to_string())?;
        return std::os::unix::fs::symlink(target, to).map_err(|e| e.to_string());
    }
    if meta.is_file() {
        return fs::copy(from, to).map(|_| ()).map_err(|e| e.to_string());
    }
    fs::create_dir(to).map_err(|e| format!("{}: {e}", to.display()))?;
    for entry in fs::read_dir(from).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        copy_tree(&entry.path(), &to.join(entry.file_name()))?;
    }
    Ok(())
}

/// Theme folders inside an unpacked pack, without descending into a found theme.
fn theme_folders(dir: &Path, depth: usize, found: &mut Vec<PathBuf>) {
    let is_theme = ["index.theme", "cursors", "hyprcursors"]
        .iter()
        .any(|n| fs::symlink_metadata(dir.join(n)).is_ok());
    if is_theme && depth > 0 {
        found.push(dir.to_owned());
        return;
    }
    if depth >= 4 {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut children: Vec<_> = entries
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
        .map(|e| e.path())
        .collect();
    children.sort();
    for child in children {
        theme_folders(&child, depth + 1, found);
    }
}

/// Installs every theme in a folder or archive into the user's icon folder.
pub fn install(roots: &Roots, source: &Path) -> Result<Vec<String>, String> {
    if !source.is_absolute() {
        return Err(invalid("Choose a theme folder or archive"));
    }
    let meta = fs::metadata(source).map_err(|e| invalid(format!("{}: {e}", source.display())))?;
    fs::create_dir_all(&roots.user).map_err(|e| format!("{}: {e}", roots.user.display()))?;
    let staging = tempfile::Builder::new()
        .prefix(".remya-settings-theme-")
        .tempdir_in(&roots.user)
        .map_err(|e| e.to_string())?;
    if meta.is_dir() {
        let name = source
            .file_name()
            .ok_or_else(|| invalid("Choose a theme folder"))?;
        tree_size(source)?;
        copy_tree(source, &staging.path().join(name))?;
    } else {
        if meta.len() > ARCHIVE_LIMIT {
            return Err(invalid("The archive is larger than 512 MiB"));
        }
        let (from, to) = (
            source
                .to_str()
                .ok_or_else(|| invalid("Unsupported file name"))?,
            staging.path().to_str().ok_or("Unsupported icon folder")?,
        );
        // bsdtar refuses absolute paths, `..` and writes through links unless told otherwise.
        run_bytes(
            "bsdtar",
            &[
                "-x",
                "-f",
                from,
                "-C",
                to,
                "--no-same-owner",
                "--no-same-permissions",
            ],
            &[],
            TIMEOUT,
        )
        .map_err(|e| invalid(format!("The archive cannot be unpacked: {e}")))?;
    }
    tree_size(staging.path())?;
    let mut folders = vec![];
    theme_folders(staging.path(), 0, &mut folders);
    let mut moves = vec![];
    for folder in folders {
        let name = folder
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_owned();
        let pack = inspect(&folder, &name);
        if !(pack.icons || pack.cursors || pack.scalable) {
            continue;
        }
        if !valid_name(&name) || matches!(name.as_str(), "default" | "hicolor") {
            return Err(invalid(format!(
                "\"{name}\" cannot be used as a theme name"
            )));
        }
        let target = roots.user.join(&name);
        if fs::symlink_metadata(&target).is_ok() || moves.iter().any(|(_, n)| *n == name) {
            return Err(invalid(format!("\"{name}\" is already installed")));
        }
        moves.push((folder, name));
    }
    if moves.is_empty() {
        return Err(invalid("No icon or cursor theme was found"));
    }
    for (folder, name) in &moves {
        fs::rename(folder, roots.user.join(name)).map_err(|e| e.to_string())?;
    }
    Ok(moves.into_iter().map(|(_, n)| n).collect())
}

/// Removes a theme from the user's icon folder.
pub fn remove(roots: &Roots, id: &str) -> Result<(), String> {
    if !valid_name(id) {
        return Err(invalid("Unknown theme"));
    }
    let path = roots.user.join(id);
    let meta = fs::symlink_metadata(&path)
        .map_err(|_| invalid("Only themes in your own icon folder can be removed"))?;
    if meta.file_type().is_symlink() {
        fs::remove_file(&path)
    } else {
        fs::remove_dir_all(&path)
    }
    .map_err(|e| format!("{}: {e}", path.display()))
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Prefs {
    pub cursor_theme: String,
    pub cursor_size: i32,
    pub icon_theme: String,
}

impl Prefs {
    /// The values under their setting IDs, as the other option features report them.
    fn by_id(&self) -> Value {
        json!({
            CURSOR_THEME: self.cursor_theme,
            CURSOR_SIZE: self.cursor_size,
            ICON_THEME: self.icon_theme,
        })
    }
}

fn gnome(context: &Context) -> Result<&gio::Settings, String> {
    let settings = context
        .gnome
        .as_ref()
        .ok_or("The GNOME interface settings schema is not installed")?;
    let schema = settings.settings_schema().ok_or("Missing GNOME schema")?;
    for key in ["cursor-theme", "cursor-size", "icon-theme"] {
        if !schema.has_key(key) {
            return Err(format!("GNOME interface settings have no {key} key"));
        }
    }
    Ok(settings)
}

pub fn read_system() -> Result<Prefs, String> {
    read_context(&Context::current()?)
}

fn read_context(context: &Context) -> Result<Prefs, String> {
    let settings = gnome(context)?;
    Ok(Prefs {
        cursor_theme: settings.string("cursor-theme").into(),
        cursor_size: settings.int("cursor-size"),
        icon_theme: settings.string("icon-theme").into(),
    })
}

/// One KDE configuration key written with KDE's own tools, with its prior value.
struct KdeChange {
    file: &'static str,
    group: &'static str,
    key: &'static str,
    previous: String,
    value: String,
}

fn kde_tools(context: &Context) -> bool {
    context.config.join("kdeglobals").is_file()
        && ["kreadconfig6", "kwriteconfig6"].iter().all(|tool| {
            Command::new(tool)
                .arg("--help")
                .output()
                .is_ok_and(|o| o.status.success())
        })
}

fn kde_tool(tool: &str, args: &[&str]) -> Result<String, String> {
    let bytes = run_bytes(tool, args, &[], Duration::from_secs(10))?;
    Ok(String::from_utf8_lossy(&bytes)
        .trim_end_matches('\n')
        .to_owned())
}

impl KdeChange {
    fn prepare(
        file: &'static str,
        group: &'static str,
        key: &'static str,
        value: String,
    ) -> Result<Self, String> {
        let previous = kde_tool(
            "kreadconfig6",
            &["--file", file, "--group", group, "--key", key],
        )?;
        Ok(Self {
            file,
            group,
            key,
            previous,
            value,
        })
    }

    fn write(&self, value: &str) -> Result<(), String> {
        let mut args = vec![
            "--file", self.file, "--group", self.group, "--key", self.key,
        ];
        if value.is_empty() {
            args.push("--delete");
        } else {
            args.push(value);
        }
        kde_tool("kwriteconfig6", &args)?;
        let read = kde_tool(
            "kreadconfig6",
            &[
                "--file", self.file, "--group", self.group, "--key", self.key,
            ],
        )?;
        if read != value {
            return Err(format!("KDE {} {} readback failed", self.file, self.key));
        }
        Ok(())
    }
}

/// Cursor or icon changes across GNOME, GTK, XCursor, KDE, the shell environments
/// and the running compositor; every completed step is undone on failure.
struct Change {
    kde: Vec<KdeChange>,
    targets: Vec<ThemeTargetResult>,
}

fn gtk_files(
    context: &Context,
    edits: &[(&str, Option<String>)],
    targets: &mut Vec<ThemeTargetResult>,
) -> Result<Vec<FileChange>, String> {
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
        let file = FileChange::prepare(&context.config.join(toolkit).join("settings.ini"), edits)?;
        targets.push(result(
            name,
            if file.changed() {
                ThemeTargetStatus::Applied
            } else {
                ThemeTargetStatus::Unchanged
            },
            "settings.ini",
        ));
        files.push(file);
    }
    Ok(files)
}

fn status(changed: bool) -> ThemeTargetStatus {
    if changed {
        ThemeTargetStatus::Applied
    } else {
        ThemeTargetStatus::Unchanged
    }
}

fn plan_cursor(
    context: &Context,
    roots: &Roots,
    theme: &str,
    size: i32,
) -> Result<AppearancePlan, String> {
    let settings = gnome(context)?;
    let mut settings_changes = vec![];
    settings_changes.extend(setting_change(
        settings,
        "cursor-theme",
        theme.to_variant(),
    )?);
    settings_changes.extend(setting_change(settings, "cursor-size", size.to_variant())?);
    let mut targets = vec![result(
        "GNOME / GTK",
        status(!settings_changes.is_empty()),
        format!("cursor-theme={theme}, cursor-size={size}"),
    )];
    let mut files = gtk_files(
        context,
        &[
            ("gtk-cursor-theme-name", Some(theme.into())),
            ("gtk-cursor-theme-size", Some(size.to_string())),
        ],
        &mut targets,
    )?;
    // Programs without their own setting use the XCursor "default" theme.
    let defaults: Vec<PathBuf> = [roots.user.clone(), roots.home.join(".icons")]
        .into_iter()
        .map(|r| r.join("default/index.theme"))
        .filter(|p| p.is_file())
        .collect();
    let defaults = if defaults.is_empty() {
        vec![roots.user.join("default/index.theme")]
    } else {
        defaults
    };
    for path in defaults {
        let file =
            FileChange::prepare_group(&path, "Icon Theme", &[("Inherits", Some(theme.into()))])?;
        targets.push(result(
            "XCursor default",
            status(file.changed()),
            path.display().to_string(),
        ));
        files.push(file);
    }
    let size = size.to_string();
    let (environment, environment_targets) = context.environment.prepare_values(
        CURSOR_MARKER,
        &[
            ("XCURSOR_THEME", theme.into()),
            ("XCURSOR_SIZE", size.clone()),
            ("HYPRCURSOR_THEME", theme.into()),
            ("HYPRCURSOR_SIZE", size),
        ],
        "Cursor theme",
    )?;
    files.extend(environment);
    targets.extend(environment_targets);
    Ok(AppearancePlan {
        settings_changes,
        files,
        targets,
    })
}

fn plan_icons(context: &Context, theme: &str) -> Result<AppearancePlan, String> {
    let settings = gnome(context)?;
    let settings_changes: Vec<_> = setting_change(settings, "icon-theme", theme.to_variant())?
        .into_iter()
        .collect();
    let mut targets = vec![result(
        "GNOME / GTK",
        status(!settings_changes.is_empty()),
        format!("icon-theme={theme}"),
    )];
    let files = gtk_files(
        context,
        &[("gtk-icon-theme-name", Some(theme.into()))],
        &mut targets,
    )?;
    Ok(AppearancePlan {
        settings_changes,
        files,
        targets,
    })
}

/// Sets the running compositor's cursor; Ok(false) when no Hyprland session exists.
fn set_compositor_cursor(theme: &str, size: i32) -> Result<bool, String> {
    let Ok(instance) = Hyprctl::instance() else {
        return Ok(false);
    };
    let size = size.to_string();
    let output = run_bytes(
        "hyprctl",
        &["-i", &instance, "setcursor", theme, &size],
        &[],
        Duration::from_secs(5),
    )?;
    match String::from_utf8_lossy(&output).trim() {
        "ok" => Ok(true),
        other => Err(format!("Hyprland rejected the cursor theme: {other}")),
    }
}

impl Change {
    fn kde(
        context: &Context,
        keys: &[(&'static str, &'static str, &'static str, String)],
    ) -> Result<Self, String> {
        let mut targets = vec![];
        let kde = if kde_tools(context) {
            keys.iter()
                .map(|(file, group, key, value)| {
                    KdeChange::prepare(file, group, key, value.clone())
                })
                .collect::<Result<Vec<_>, _>>()?
        } else {
            targets.push(result(
                "KDE / Qt",
                ThemeTargetStatus::Unavailable,
                "No KDE configuration or kwriteconfig6; skipped",
            ));
            vec![]
        };
        Ok(Self { kde, targets })
    }

    /// Writes KDE keys, then `plan`; undoes the KDE keys if anything fails.
    fn apply(
        mut self,
        context: &Context,
        plan: impl FnOnce() -> Result<AppearancePlan, String>,
    ) -> Result<Vec<ThemeTargetResult>, String> {
        let mut written = 0;
        let result = (|| {
            for change in &self.kde {
                change.write(&change.value)?;
                written += 1;
            }
            plan()?.apply(context)
        })();
        match result {
            Ok(targets) => {
                if !self.kde.is_empty() {
                    let changed = self.kde.iter().any(|c| c.previous != c.value);
                    self.targets.push(crate::system_theme::result(
                        "KDE / Qt",
                        status(changed),
                        "kdeglobals and kcminputrc",
                    ));
                }
                self.targets.extend(targets);
                Ok(self.targets)
            }
            Err(error) => {
                let failed: Vec<_> = self.kde[..written]
                    .iter()
                    .rev()
                    .filter_map(|c| c.write(&c.previous).err())
                    .collect();
                Err(if failed.is_empty() {
                    error
                } else {
                    format!("{error}. KDE rollback incomplete: {}", failed.join("; "))
                })
            }
        }
    }
}

/// Sets the running compositor's cursor; Ok(false) when there is none.
type Compositor = fn(&str, i32) -> Result<bool, String>;

fn apply_cursor_context(
    context: &Context,
    roots: &Roots,
    theme: &str,
    size: i32,
    compositor: Compositor,
) -> Result<Vec<ThemeTargetResult>, String> {
    let _lock = context.lock()?;
    let before = read_context(context)?;
    let live = compositor(theme, size)?;
    let change = Change::kde(
        context,
        &[
            ("kcminputrc", "Mouse", "cursorTheme", theme.into()),
            ("kcminputrc", "Mouse", "cursorSize", size.to_string()),
        ],
    );
    // The compositor may have updated GNOME settings already, so plan only after it.
    let result = change.and_then(|c| c.apply(context, || plan_cursor(context, roots, theme, size)));
    match result {
        Ok(mut targets) => {
            targets.push(result_live(live));
            let after = read_context(context)?;
            if after.cursor_theme != theme || after.cursor_size != size {
                return Err("The cursor theme did not read back".into());
            }
            Ok(targets)
        }
        Err(error) => {
            if live {
                let _ = compositor(&before.cursor_theme, before.cursor_size);
            }
            Err(error)
        }
    }
}

fn result_live(live: bool) -> ThemeTargetResult {
    if live {
        result("Hyprland", ThemeTargetStatus::Applied, "Cursor reloaded")
    } else {
        result(
            "Hyprland",
            ThemeTargetStatus::Unavailable,
            "No running session; applies at the next sign-in",
        )
    }
}

fn apply_icons_context(context: &Context, theme: &str) -> Result<Vec<ThemeTargetResult>, String> {
    let _lock = context.lock()?;
    let change = Change::kde(context, &[("kdeglobals", "Icons", "Theme", theme.into())])?;
    let targets = change.apply(context, || plan_icons(context, theme))?;
    if read_context(context)?.icon_theme != theme {
        return Err("The icon theme did not read back".into());
    }
    Ok(targets)
}

/// Saved selection, live selection and the installed packs.
pub struct ThemePacks {
    saved_path: PathBuf,
    saved: Option<Prefs>,
    system: Option<Prefs>,
    packs: Vec<Pack>,
    roots: Option<Roots>,
    targets: Vec<ThemeTargetResult>,
    error: Option<String>,
}

pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}

impl ThemePacks {
    pub fn new(saved_path: PathBuf) -> Self {
        Self {
            saved_path,
            saved: None,
            system: None,
            packs: vec![],
            roots: None,
            targets: vec![],
            error: None,
        }
    }

    fn read(&mut self) -> Result<(), String> {
        let roots = Roots::current()?;
        self.packs = list(&roots);
        self.roots = Some(roots);
        let system = read_system();
        self.system = system.as_ref().ok().cloned();
        self.saved = match fs::read_to_string(&self.saved_path) {
            Ok(text) => Some(
                toml::from_str(&text).map_err(|e| format!("{}: {e}", self.saved_path.display()))?,
            ),
            // First use saves what the system uses now and changes nothing.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let system = system.clone()?;
                self.save(&system)?;
                Some(system)
            }
            Err(e) => return Err(format!("{}: {e}", self.saved_path.display())),
        };
        system.map(|_| ())
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.read();
        self.error = result.as_ref().err().cloned();
        result
    }

    fn save(&self, prefs: &Prefs) -> Result<(), String> {
        let text = toml::to_string(prefs).map_err(|e| e.to_string())?;
        atomic_write(&self.saved_path, text.as_bytes())
    }

    fn conflicts(&self) -> Vec<&'static str> {
        let (Some(saved), Some(system)) = (&self.saved, &self.system) else {
            return vec![];
        };
        let mut ids = vec![];
        if saved.cursor_theme != system.cursor_theme {
            ids.push(CURSOR_THEME);
        }
        if saved.cursor_size != system.cursor_size {
            ids.push(CURSOR_SIZE);
        }
        if saved.icon_theme != system.icon_theme {
            ids.push(ICON_THEME);
        }
        ids
    }

    pub fn state(&self) -> Value {
        let saved = self.saved.as_ref();
        let in_use = |id: &str| {
            [saved, self.system.as_ref()]
                .into_iter()
                .flatten()
                .any(|p| p.cursor_theme == id || p.icon_theme == id)
        };
        let packs = |f: fn(&Pack) -> bool| {
            self.packs
                .iter()
                .filter(|p| f(p) && (!p.hidden || in_use(&p.id)))
                .collect::<Vec<_>>()
        };
        json!({
            "options": saved.map(Prefs::by_id),
            "saved": saved.map(Prefs::by_id),
            "system": self.system.as_ref().map(Prefs::by_id),
            "conflict": !self.conflicts().is_empty(),
            "conflicts": self.conflicts(),
            "cursor_themes": packs(|p| p.cursors || p.scalable),
            "icon_themes": packs(|p| p.icons),
            "folders": self.roots.as_ref().map(Roots::folders),
            "user_folder": self.roots.as_ref().map(|r| r.user.display().to_string()),
            "targets": self.targets,
            "error": self.error,
        })
    }

    pub fn setting_value(&self, id: &str) -> Value {
        let state = self.state();
        match id {
            CURSOR_FOLDERS => state["folders"].clone(),
            CURSOR_INSTALL | ICON_INSTALL => state["user_folder"].clone(),
            CURSOR_REMOVE | ICON_REMOVE => json!(
                self.packs
                    .iter()
                    .filter(|p| p.user)
                    .map(|p| &p.id)
                    .collect::<Vec<_>>()
            ),
            _ => state["options"][id].clone(),
        }
    }

    pub fn preview(&mut self, request: &str) -> Result<Value, String> {
        let (theme, size) = match request.rsplit_once('@') {
            Some((theme, size)) => (theme, size.parse().map_err(|_| invalid("Unknown size"))?),
            None => (request, 24),
        };
        let roots = Roots::current()?;
        cursor_preview(&roots, theme, size)
    }

    fn selection(&mut self) -> Result<Prefs, String> {
        self.refresh()?;
        if !self.conflicts().is_empty() {
            return Err("Resolve the theme settings conflict first".into());
        }
        self.saved
            .clone()
            .ok_or_else(|| "Theme settings are not initialized".into())
    }

    fn pack(&self, id: &str, cursor: bool) -> Result<(), String> {
        self.packs
            .iter()
            .any(|p| {
                p.id == id
                    && if cursor {
                        p.cursors || p.scalable
                    } else {
                        p.icons
                    }
            })
            .then_some(())
            .ok_or_else(|| {
                invalid(if cursor {
                    "Unknown cursor theme"
                } else {
                    "Unknown icon theme"
                })
            })
    }

    fn apply(&mut self, next: &Prefs, current: &Prefs) -> Result<(), String> {
        let context = Context::current()?;
        let roots = Roots::current()?;
        let mut targets = vec![];
        if next.cursor_theme != current.cursor_theme || next.cursor_size != current.cursor_size {
            targets.extend(apply_cursor_context(
                &context,
                &roots,
                &next.cursor_theme,
                next.cursor_size,
                set_compositor_cursor,
            )?);
        }
        if next.icon_theme != current.icon_theme {
            targets.extend(apply_icons_context(&context, &next.icon_theme)?);
        }
        self.save(next)?;
        self.targets = targets;
        Ok(())
    }

    fn change(&mut self, id: &str, value: &Value) -> Result<Value, String> {
        let text = || {
            value
                .as_str()
                .ok_or_else(|| invalid("Expected a JSON string"))
        };
        match id {
            CURSOR_FOLDERS => {
                return Err(
                    "ReadOnly:The theme folders follow the XDG and XCursor search paths".into(),
                );
            }
            CURSOR_INSTALL | ICON_INSTALL => {
                let installed = install(&Roots::current()?, Path::new(text()?))?;
                let _ = self.refresh();
                let mut state = self.state();
                state["installed"] = json!(installed);
                return Ok(state);
            }
            CURSOR_REMOVE | ICON_REMOVE => {
                let name = text()?;
                self.refresh()?;
                if let Some(saved) = &self.saved
                    && (saved.cursor_theme == name || saved.icon_theme == name)
                {
                    return Err(invalid("Choose another theme before removing this one"));
                }
                remove(&Roots::current()?, name)?;
                let _ = self.refresh();
                return Ok(self.state());
            }
            _ => {}
        }
        let current = self.selection()?;
        let mut next = current.clone();
        match id {
            CURSOR_THEME => {
                let theme = text()?;
                self.pack(theme, true)?;
                next.cursor_theme = theme.into();
            }
            CURSOR_SIZE => {
                next.cursor_size = value
                    .as_i64()
                    .and_then(|v| i32::try_from(v).ok())
                    .filter(|v| SIZES.contains(v))
                    .ok_or_else(|| {
                        invalid(format!(
                            "Use a size from {} to {}",
                            SIZES.start(),
                            SIZES.end()
                        ))
                    })?;
            }
            ICON_THEME => {
                let theme = text()?;
                self.pack(theme, false)?;
                next.icon_theme = theme.into();
            }
            _ => return Err(invalid("Unknown setting")),
        }
        self.apply(&next, &current)?;
        let _ = self.refresh();
        Ok(self.state())
    }

    pub fn set(&mut self, id: &str, input: &str) -> Result<Value, String> {
        let value: Value = serde_json::from_str(input).map_err(|_| invalid("Expected JSON"))?;
        let result = self.change(id, &value);
        if let Err(error) = &result
            && !error.starts_with("InvalidArgument:")
        {
            let _ = self.refresh();
            self.error = Some(error.clone());
        }
        result
    }

    pub fn resolve(&mut self, source: &str) -> Result<Value, String> {
        self.refresh()?;
        let system = self
            .system
            .clone()
            .ok_or("The system themes cannot be read")?;
        match source {
            "system" => self.save(&system)?,
            "settings" => {
                let saved = self.saved.clone().ok_or("Nothing is saved yet")?;
                self.pack(&saved.cursor_theme, true)?;
                self.pack(&saved.icon_theme, false)?;
                self.apply(&saved, &system)?;
            }
            _ => return Err(invalid("Unknown resolution")),
        }
        self.refresh()?;
        Ok(self.state())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roots(dir: &Path) -> Roots {
        Roots::new(
            dir.join("home"),
            dir.join("home/.local/share"),
            &format!("{}:relative", dir.join("usr").display()),
            None,
        )
    }

    fn theme(root: &Path, id: &str, index: &str, cursor: bool) {
        let dir = root.join(id);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("index.theme"), index).unwrap();
        if cursor {
            fs::create_dir_all(dir.join("cursors")).unwrap();
            fs::write(dir.join("cursors/left_ptr"), xcursor_file()).unwrap();
            std::os::unix::fs::symlink("left_ptr", dir.join("cursors/default")).unwrap();
        }
    }

    /// A one-image XCursor file: 2x2 pixels, nominal size 24.
    fn xcursor_file() -> Vec<u8> {
        let mut b = vec![];
        let u = |b: &mut Vec<u8>, v: u32| b.extend_from_slice(&v.to_le_bytes());
        b.extend_from_slice(b"Xcur");
        u(&mut b, 16);
        u(&mut b, 0x10000);
        u(&mut b, 1);
        u(&mut b, 0xfffd0002);
        u(&mut b, 24);
        u(&mut b, 28);
        for v in [36, 0xfffd0002, 24, 1, 2, 2, 0, 0, 50] {
            u(&mut b, v);
        }
        for _ in 0..4 {
            u(&mut b, 0xff336699);
        }
        b
    }

    #[test]
    fn search_path_order_and_xcursor_path() {
        let r = Roots::new(
            "/h".into(),
            "/h/data".into(),
            "/usr/share:rel",
            Some("~/c:/x:rel"),
        );
        assert_eq!(
            r.icons,
            [
                "/h/data/icons",
                "/h/.icons",
                "/usr/share/icons",
                "/usr/share/pixmaps"
            ]
            .map(PathBuf::from)
        );
        assert_eq!(r.cursors, ["/h/c", "/x"].map(PathBuf::from));
        assert!(!valid_name("../x") && !valid_name(".hidden") && !valid_name("a\"b"));
        assert!(valid_name("Bibata-Modern Classic"));
    }

    #[test]
    fn lists_icon_and_cursor_themes_with_precedence_and_previews() {
        let dir = tempfile::tempdir().unwrap();
        let r = roots(dir.path());
        let system = dir.path().join("usr/icons");
        theme(
            &system,
            "Papirus",
            "[Icon Theme]\nName=Papirus\nDirectories=48x48/apps\n",
            false,
        );
        theme(
            &system,
            "hicolor",
            "[Icon Theme]\nName=Hicolor\nDirectories=48x48/apps\n",
            false,
        );
        theme(
            &system,
            "Hidden",
            "[Icon Theme]\nName=H\nHidden=true\nDirectories=a\n",
            false,
        );
        theme(&system, "Bare", "[Icon Theme]\nName=Bare\n", false);
        theme(&system, "Bibata", "[Icon Theme]\nName=Bibata\n", true);
        theme(&r.user, "Papirus", "[Icon Theme]\nName=My Papirus\n", true);
        let packs = list(&r);
        let ids: Vec<_> = packs.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(ids, ["Bibata", "Hidden", "Papirus"]);
        assert!(packs[1].hidden);
        let papirus = &packs[2];
        assert!(papirus.user && papirus.icons && papirus.cursors);
        assert_eq!(papirus.name, "My Papirus");
        let preview = cursor_preview(&r, "Bibata", 48).unwrap();
        assert_eq!(preview["sizes"], json!([24]));
        assert_eq!(preview["images"][0]["role"], "pointer");
        assert!(!preview["images"][0]["png"].as_str().unwrap().is_empty());
        assert!(cursor_preview(&r, "../Bibata", 24).is_err());
        assert!(cursor_preview(&r, "Papirus2", 24).is_err());
    }

    #[test]
    fn install_copies_folders_with_links_and_refuses_duplicates_and_empty_packs() {
        let dir = tempfile::tempdir().unwrap();
        let r = roots(dir.path());
        let download = dir.path().join("download");
        theme(&download, "Cool", "[Icon Theme]\nName=Cool\n", true);
        assert_eq!(install(&r, &download.join("Cool")).unwrap(), ["Cool"]);
        assert!(r.user.join("Cool/cursors/default").is_symlink());
        assert!(
            install(&r, &download.join("Cool"))
                .unwrap_err()
                .contains("already installed")
        );
        // A folder holding several themes installs each of them.
        theme(
            &download,
            "Two",
            "[Icon Theme]\nName=Two\nDirectories=a\n",
            false,
        );
        fs::create_dir_all(download.join("pack")).unwrap();
        fs::rename(download.join("Two"), download.join("pack/Two")).unwrap();
        assert_eq!(install(&r, &download.join("pack")).unwrap(), ["Two"]);
        fs::create_dir_all(download.join("empty/x")).unwrap();
        assert!(install(&r, &download.join("empty")).is_err());
        assert!(install(&r, Path::new("relative")).is_err());
        assert_eq!(
            fs::read_dir(&r.user).unwrap().count(),
            2,
            "no staging folder is left behind"
        );
        remove(&r, "Two").unwrap();
        assert!(remove(&r, "Two").is_err());
        assert!(remove(&r, "../download").is_err());
    }

    #[test]
    fn cursor_and_icon_themes_reach_gnome_gtk_and_the_xcursor_default() {
        let dir = tempfile::tempdir().unwrap();
        let context = crate::system_theme::tests::context(&dir.path().join("config"));
        let r = roots(dir.path());
        fs::create_dir_all(context.config.join("gtk-3.0")).unwrap();
        fs::write(
            context.config.join("gtk-3.0/settings.ini"),
            "[Settings]\ngtk-font-name=Keep 11\ngtk-cursor-theme-name=Old\n",
        )
        .unwrap();
        fs::create_dir_all(r.home.join(".icons/default")).unwrap();
        fs::write(
            r.home.join(".icons/default/index.theme"),
            "[Icon Theme]\nInherits=Old\n",
        )
        .unwrap();
        let targets = apply_cursor_context(&context, &r, "Bibata", 32, |_, _| Ok(false)).unwrap();
        assert!(
            targets
                .iter()
                .any(|t| t.name == "Hyprland" && t.status == ThemeTargetStatus::Unavailable)
        );
        let prefs = read_context(&context).unwrap();
        assert_eq!(
            (prefs.cursor_theme.as_str(), prefs.cursor_size),
            ("Bibata", 32)
        );
        let gtk3 = fs::read_to_string(context.config.join("gtk-3.0/settings.ini")).unwrap();
        assert!(
            gtk3.contains("gtk-font-name=Keep 11") && gtk3.contains("gtk-cursor-theme-name=Bibata")
        );
        assert!(gtk3.contains("gtk-cursor-theme-size=32"));
        // An existing default theme file is updated; none is created beside it.
        assert!(
            fs::read_to_string(r.home.join(".icons/default/index.theme"))
                .unwrap()
                .contains("Inherits=Bibata")
        );
        assert!(!r.user.join("default").exists());
        apply_icons_context(&context, "Papirus").unwrap();
        assert_eq!(read_context(&context).unwrap().icon_theme, "Papirus");
        assert!(
            fs::read_to_string(context.config.join("gtk-4.0/settings.ini"))
                .unwrap()
                .contains("gtk-icon-theme-name=Papirus")
        );
        // A compositor failure leaves everything as it was.
        let before = read_context(&context).unwrap();
        assert!(apply_cursor_context(&context, &r, "Other", 24, |_, _| Err("no".into())).is_err());
        assert_eq!(read_context(&context).unwrap(), before);
    }

    #[test]
    fn archives_install_through_bsdtar() {
        if Command::new("bsdtar").arg("--version").output().is_err() {
            return;
        }
        let dir = tempfile::tempdir().unwrap();
        let r = roots(dir.path());
        let download = dir.path().join("download");
        theme(&download, "Packed", "[Icon Theme]\nName=Packed\n", true);
        let archive = dir.path().join("packed.tar.gz");
        let status = Command::new("bsdtar")
            .args([
                "-czf",
                archive.to_str().unwrap(),
                "-C",
                download.to_str().unwrap(),
                "Packed",
            ])
            .status()
            .unwrap();
        assert!(status.success());
        assert_eq!(install(&r, &archive).unwrap(), ["Packed"]);
        assert!(r.user.join("Packed/cursors/default").is_symlink());
        fs::write(dir.path().join("broken.tar.gz"), b"not an archive").unwrap();
        assert!(install(&r, &dir.path().join("broken.tar.gz")).is_err());
    }
}
