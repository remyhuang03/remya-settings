//! Owns background and accent state: first-use initialization from the system,
//! conflict detection, verified application, rollback, and copy cleanup.
use crate::{
    accent::{self, Accent},
    hyprpaper::{self, FITS, HyprpaperConfig, Image, Splash, WILDCARD},
    media,
    system::{Desktop, layer_warnings},
    video::{self, UNIT, Video},
};
use remya_settings_display::atomic_write;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, hash_map::DefaultHasher},
    fs,
    hash::{Hash, Hasher},
    path::{Path, PathBuf},
    thread,
    time::{Duration, UNIX_EPOCH},
};

pub const KIND: &str = "background.99b01ada";
pub const DISPLAY: &str = "background.display";
pub const FILE: &str = "background.9e58290b";
pub const FIT: &str = "background.56c289eb";
pub const PAUSE: &str = "background.video-pause";
pub const SPLASH: &str = "background.splash";
pub const SPLASH_OFFSET: &str = "background.splash-offset";
pub const SPLASH_OPACITY: &str = "background.splash-opacity";
pub const ACCENT_SOURCE: &str = "themes.8983f367";
pub const ACCENT_COLOR: &str = "themes.6f67371e";
const IDS: [&str; 8] = [
    KIND,
    DISPLAY,
    FILE,
    FIT,
    PAUSE,
    SPLASH,
    SPLASH_OFFSET,
    SPLASH_OPACITY,
];
pub fn is_background_setting(id: &str) -> bool {
    IDS.contains(&id)
}
pub fn is_accent_setting(id: &str) -> bool {
    id == ACCENT_SOURCE || id == ACCENT_COLOR
}

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub version: u8,
    pub kind: String,
    #[serde(default)]
    pub images: Vec<Image>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub video: Option<Video>,
    pub splash: Splash,
}

impl Saved {
    /// A remembered video is not a difference while an image is showing.
    fn stable(&self) -> (String, &Vec<Image>, Option<&Video>, &Splash) {
        let video = (self.kind == "video")
            .then_some(self.video.as_ref())
            .flatten();
        (self.kind.clone(), &self.images, video, &self.splash)
    }
    /// The file the accent is sampled from.
    fn current_path(&self) -> Option<&str> {
        if self.kind == "video" {
            return self.video.as_ref().map(|v| v.path.as_str());
        }
        self.images
            .iter()
            .find(|i| i.monitor == WILDCARD)
            .or(self.images.first())
            .map(|i| i.path.as_str())
    }
}

pub struct Paths {
    pub config: PathBuf,
    pub accent: PathBuf,
    pub media: PathBuf,
    pub cache: PathBuf,
    pub hyprpaper: PathBuf,
    pub units: PathBuf,
    pub home: Option<PathBuf>,
}

pub struct BackgroundManager<D: Desktop> {
    desktop: D,
    paths: Paths,
    saved: Option<Saved>,
    observed: Option<Saved>,
    comments: Vec<String>,
    write_blocked: Option<String>,
    monitors: Vec<String>,
    active: BTreeMap<String, String>,
    warnings: Vec<String>,
    previews: BTreeMap<String, String>,
    read_error: Option<String>,
    operation_error: Option<String>,
    accent: Accent,
    accent_error: Option<String>,
    /// hyprpaper's file changed while a video covered it; applied on returning to image.
    restart_pending: bool,
}

/// hyprpaper's IPC treats Fill as Cover, and it reads splash options only at start.
fn needs_restart(previous: &Saved, next: &Saved) -> bool {
    previous.splash != next.splash
        || next
            .images
            .iter()
            .any(|image| image.fit == "fill" && !previous.images.contains(image))
}

impl<D: Desktop> BackgroundManager<D> {
    pub fn new(desktop: D, paths: Paths) -> Self {
        Self {
            desktop,
            paths,
            saved: None,
            observed: None,
            comments: Vec::new(),
            write_blocked: None,
            monitors: Vec::new(),
            active: BTreeMap::new(),
            warnings: Vec::new(),
            previews: BTreeMap::new(),
            read_error: None,
            operation_error: None,
            accent: Accent::default(),
            accent_error: None,
            restart_pending: false,
        }
    }

    fn unit_path(&self) -> PathBuf {
        self.paths.units.join(UNIT)
    }

    /// Current system values. A hyprpaper file this reader rejects blocks writes.
    fn observe(&mut self) -> Result<Saved, String> {
        let text = match fs::read_to_string(&self.paths.hyprpaper) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(format!("{}: {e}", self.paths.hyprpaper.display())),
        };
        let parsed = hyprpaper::parse(&text, self.paths.home.as_deref()).map_err(|e| {
            let reason = format!("{}: {e}", self.paths.hyprpaper.display());
            self.write_blocked = Some(reason.clone());
            reason
        })?;
        self.write_blocked = None;
        self.comments = parsed.comments;
        let managed = if self.desktop.unit_enabled() {
            let unit = fs::read_to_string(self.unit_path()).map_err(|e| e.to_string())?;
            Some(video::parse_unit(&unit)?)
        } else {
            None
        };
        let other = self
            .desktop
            .other_players()
            .iter()
            .find_map(|(_, args)| video::parse_command_line(args));
        let active = managed.or(other);
        let remembered = self.saved.as_ref().and_then(|s| s.video.clone());
        Ok(Saved {
            version: 1,
            kind: if active.is_some() { "video" } else { "image" }.into(),
            images: parsed.images,
            video: active.or(remembered),
            splash: parsed.splash,
        })
    }

    pub fn refresh(&mut self) -> Result<(), String> {
        let result = self.refresh_inner();
        self.read_error = result.as_ref().err().cloned();
        result
    }

    fn refresh_inner(&mut self) -> Result<(), String> {
        let loaded: Option<Saved> = match fs::read_to_string(&self.paths.config) {
            Ok(text) => Some(
                toml::from_str(&text)
                    .map_err(|e| format!("Invalid background configuration: {e}"))?,
            ),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => return Err(e.to_string()),
        };
        if let Some(saved) = &loaded {
            validate(saved)?;
            self.saved = loaded.clone();
        }
        let observed = self.observe()?;
        if loaded.is_none() {
            // First use records the actual desktop; defaults are never applied to it.
            self.persist(&observed)?;
            self.saved = Some(observed.clone());
        }
        self.monitors = self.desktop.monitors()?;
        self.active = self.desktop.active_images().unwrap_or_default();
        self.warnings = self.collect_warnings(&observed);
        self.observed = Some(observed);
        self.refresh_previews();
        self.refresh_accent();
        Ok(())
    }

    fn collect_warnings(&self, observed: &Saved) -> Vec<String> {
        let mut warnings = self
            .desktop
            .layers()
            .map(|layers| layer_warnings(&layers))
            .unwrap_or_default();
        if observed.kind == "video" && !self.desktop.unit_active() {
            warnings.push(if self.desktop.unit_enabled() {
                "The video background is enabled but mpvpaper is not running.".to_owned()
            } else {
                "Another program started this video background; it can replace it again.".to_owned()
            });
        }
        warnings
    }

    fn persist(&self, saved: &Saved) -> Result<(), String> {
        let text = toml::to_string(saved).map_err(|e| e.to_string())?;
        atomic_write(&self.paths.config, text.as_bytes())
    }

    fn preview_path(&self, path: &str) -> Option<PathBuf> {
        let metadata = fs::metadata(path).ok()?;
        let modified = metadata.modified().ok()?.duration_since(UNIX_EPOCH).ok()?;
        let mut hash = DefaultHasher::new();
        (path, modified.as_secs(), metadata.len()).hash(&mut hash);
        Some(self.paths.cache.join(format!("{:016x}.png", hash.finish())))
    }

    fn referenced_paths(&self) -> Vec<&str> {
        [self.saved.as_ref(), self.observed.as_ref()]
            .into_iter()
            .flatten()
            .flat_map(|s| {
                s.images
                    .iter()
                    .map(|i| i.path.as_str())
                    .chain(s.video.iter().map(|v| v.path.as_str()))
            })
            .collect()
    }

    /// Previews are conveniences: a missing frame never fails the feature.
    fn refresh_previews(&mut self) {
        let paths = self
            .referenced_paths()
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        let mut previews = BTreeMap::new();
        for path in paths {
            let Some(preview) = self.preview_path(&path) else {
                continue;
            };
            if !preview.exists() {
                let _ = fs::create_dir_all(&self.paths.cache);
                if self.desktop.write_preview(&path, &preview).is_err() {
                    continue;
                }
            }
            previews.insert(path, preview.to_string_lossy().into_owned());
        }
        media::collect_garbage(
            &self.paths.cache,
            &previews.values().map(String::as_str).collect::<Vec<_>>(),
        );
        self.previews = previews;
    }

    fn ready(&self) -> Result<Saved, String> {
        if let Some(reason) = &self.write_blocked {
            return Err(format!(
                "hyprpaper.conf is read-only for Settings: {reason}"
            ));
        }
        let saved = self
            .saved
            .clone()
            .ok_or("Background configuration is not initialized")?;
        if self.has_conflict() {
            return Err("Conflict:Resolve the background configuration difference first".into());
        }
        Ok(saved)
    }

    fn has_conflict(&self) -> bool {
        match (&self.saved, &self.observed) {
            (Some(saved), Some(observed)) => saved.stable() != observed.stable(),
            _ => false,
        }
    }

    /// The image each connected output should show.
    fn targets(&self, images: &[Image]) -> Vec<(String, Image)> {
        self.monitors
            .iter()
            .filter_map(|monitor| {
                images
                    .iter()
                    .find(|i| &i.monitor == monitor)
                    .or(images.iter().find(|i| i.monitor == WILDCARD))
                    .map(|image| (monitor.clone(), image.clone()))
            })
            .collect()
    }

    /// A wildcard request does not replace a running wildcard entry in hyprpaper, so
    /// outputs are addressed by name. Unchanged ones keep what they are showing, which
    /// matters for Fill: a repeated request would turn it into Cover.
    fn apply_images(&mut self, from: &[Image], to: &[Image]) -> Result<(), String> {
        let before = self.targets(from);
        let changed = self
            .targets(to)
            .into_iter()
            .filter(|target| !before.contains(target))
            .collect::<Vec<_>>();
        for (monitor, image) in &changed {
            self.desktop.apply_image(monitor, &image.path, &image.fit)?;
        }
        self.wait_for_images(&changed)
    }

    /// Each output decodes its image asynchronously before reporting it, and a new
    /// hyprpaper needs a moment before it answers at all.
    fn wait_for_images(&mut self, targets: &[(String, Image)]) -> Result<(), String> {
        if targets.is_empty() {
            return Ok(());
        }
        let mut last = "hyprpaper did not report the new image".to_owned();
        for attempt in 0..48 {
            match self.desktop.active_images() {
                Ok(active)
                    if targets
                        .iter()
                        .all(|(monitor, image)| active.get(monitor) == Some(&image.path)) =>
                {
                    self.active = active;
                    return Ok(());
                }
                Ok(_) => {}
                Err(error) => last = error,
            }
            if attempt < 47 {
                thread::sleep(Duration::from_millis(250));
            }
        }
        Err(last)
    }

    fn restart_hyprpaper(&mut self, images: &[Image]) -> Result<(), String> {
        self.desktop.restart_hyprpaper(&self.paths.hyprpaper)?;
        let targets = self.targets(images);
        self.wait_for_images(&targets)
    }

    fn write_unit(&self, video: &Video) -> Result<(), String> {
        atomic_write(&self.unit_path(), video::render_unit(video).as_bytes())?;
        self.desktop.reload_units()
    }

    fn stop_players(&self) -> Result<(), String> {
        for (pid, _) in self.desktop.other_players() {
            self.desktop.stop_process(pid);
        }
        Ok(())
    }

    fn apply_kind(&mut self, previous: &Saved, next: &Saved) -> Result<(), String> {
        if next.kind == "video" {
            let video = next.video.as_ref().ok_or("Choose a video first")?;
            if previous.kind != "video" || previous.video.as_ref() != Some(video) {
                self.stop_players()?;
                self.write_unit(video)?;
                self.desktop.start_unit()?;
            } else if !self.desktop.unit_active() {
                self.desktop.start_unit()?;
            }
            return Ok(());
        }
        if self.desktop.unit_enabled() || self.desktop.unit_active() {
            self.desktop.stop_unit()?;
        }
        self.stop_players()?;
        if !self.desktop.other_players().is_empty() {
            return Err("Another mpvpaper process did not stop".into());
        }
        Ok(())
    }

    fn render_hyprpaper(&self, next: &Saved) -> String {
        HyprpaperConfig {
            images: next.images.clone(),
            splash: next.splash.clone(),
            comments: self.comments.clone(),
        }
        .render()
    }

    /// The first rewrite of a user's file keeps its original bytes alongside it.
    fn write_hyprpaper(&self, next: &Saved) -> Result<(), String> {
        let path = &self.paths.hyprpaper;
        if path.exists() {
            let backup = path.with_extension("conf.remya-backup");
            if !backup.exists() {
                fs::copy(path, &backup).map_err(|e| format!("{}: {e}", backup.display()))?;
            }
        }
        atomic_write(path, self.render_hyprpaper(next).as_bytes())
    }

    /// Applies `next`, verifies it, and only then saves it. Failure restores what
    /// was changed and keeps the last valid saved configuration.
    fn commit(&mut self, previous: Saved, next: Saved) -> Result<(), String> {
        validate(&next)?;
        let before = fs::read(&self.paths.hyprpaper).ok();
        let file_changed = previous.images != next.images || previous.splash != next.splash;
        let images_changed = previous.images != next.images;
        let required = needs_restart(&previous, &next);
        // A video hides hyprpaper, so nothing blanks when it restarts underneath one.
        let leaving_video = previous.kind == "video" && next.kind == "image";
        let restart = next.kind == "image" && (required || (leaving_video && self.restart_pending));
        let result = (|| {
            if file_changed {
                self.write_hyprpaper(&next)?;
            }
            if restart {
                self.restart_hyprpaper(&next.images)?;
            } else if images_changed {
                self.apply_images(&previous.images, &next.images)?;
            }
            self.apply_kind(&previous, &next)?;
            self.persist(&next)
        })();
        if let Err(error) = result {
            let mut message = error;
            if file_changed {
                let restored = match &before {
                    Some(bytes) => atomic_write(&self.paths.hyprpaper, bytes),
                    None => fs::remove_file(&self.paths.hyprpaper).map_err(|e| e.to_string()),
                };
                if let Err(failure) = restored {
                    message = format!("{message}; hyprpaper.conf was not restored: {failure}");
                }
            }
            let reverted = if restart {
                self.restart_hyprpaper(&previous.images)
            } else if images_changed {
                self.apply_images(&next.images, &previous.images)
            } else {
                Ok(())
            };
            if let Err(failure) = reverted {
                message = format!("{message}; the previous image was not restored: {failure}");
            }
            if previous.kind != next.kind
                && let Err(failure) = self.apply_kind(&next, &previous)
            {
                message = format!("{message}; the previous background was not restored: {failure}");
            }
            let _ = self.refresh();
            self.operation_error = Some(message.clone());
            return Err(message);
        }
        self.restart_pending = next.kind == "video" && (required || self.restart_pending);
        self.saved = Some(next);
        self.operation_error = None;
        let refreshed = self.refresh();
        self.collect_copies();
        refreshed
    }

    fn collect_copies(&self) {
        let keep = self.referenced_paths();
        media::collect_garbage(&self.paths.media, &keep);
    }

    fn import(&self, source: &Path) -> Result<(String, String), String> {
        if !source.is_absolute() {
            return Err(invalid("Use an absolute file path"));
        }
        if !source.is_file() {
            return Err(invalid("The background file does not exist"));
        }
        let mime = self.desktop.mime_type(source)?;
        let kind = match mime.split('/').next() {
            Some("image") => "image",
            Some("video") => "video",
            _ => return Err(invalid(&format!("Unsupported file type {mime}"))),
        };
        let copy = media::import(source, &self.paths.media)?;
        Ok((kind.to_owned(), copy.to_string_lossy().into_owned()))
    }

    fn set_file(&mut self, request: &str) -> Result<(), String> {
        let (source, displays) = target_request(request, "path")?;
        let previous = self.ready()?;
        self.check_displays(&displays)?;
        let (kind, copy) = self.import(Path::new(&source))?;
        let all = displays[0] == WILDCARD;
        let mut next = previous.clone();
        next.kind = kind.clone();
        if kind == "video" {
            if !all {
                return Err(invalid("A video plays on all displays"));
            }
            let current = previous.video.as_ref();
            next.video = Some(Video {
                path: copy,
                fit: current.map_or("cover".into(), |v| v.fit.clone()),
                pause: current.map_or("keep".into(), |v| v.pause.clone()),
            });
        } else {
            let fit_of = |display: &str| {
                let images = &previous.images;
                images
                    .iter()
                    .find(|i| i.monitor == display)
                    .or(images.iter().find(|i| i.monitor == WILDCARD))
                    .or(images.first())
                    .map_or("cover".to_owned(), |i| i.fit.clone())
            };
            let chosen = displays
                .iter()
                .map(|display| Image {
                    monitor: display.clone(),
                    path: copy.clone(),
                    fit: fit_of(display),
                })
                .collect::<Vec<_>>();
            if all {
                next.images.clear();
            }
            next.images.retain(|i| !displays.contains(&i.monitor));
            next.images.extend(chosen);
        }
        self.commit(previous, next)
    }

    fn set_fit(&mut self, request: &str) -> Result<(), String> {
        let (fit, displays) = target_request(request, "fit")?;
        let previous = self.ready()?;
        self.check_displays(&displays)?;
        let mut next = previous.clone();
        if previous.kind == "video" {
            if !video::FITS.contains(&fit.as_str()) {
                return Err(invalid("A video can use cover, contain or fill"));
            }
            next.video.as_mut().ok_or("Choose a video first")?.fit = fit;
            return self.commit(previous, next);
        }
        if !FITS.contains(&fit.as_str()) {
            return Err(invalid("Use cover, contain, tile or fill"));
        }
        if displays[0] == WILDCARD {
            next.images.iter_mut().for_each(|i| i.fit.clone_from(&fit));
            return self.commit(previous, next);
        }
        for display in displays {
            if let Some(image) = next.images.iter_mut().find(|i| i.monitor == display) {
                image.fit.clone_from(&fit);
            } else if let Some(base) = next.images.iter().find(|i| i.monitor == WILDCARD).cloned() {
                next.images.push(Image {
                    monitor: display,
                    path: base.path,
                    fit: fit.clone(),
                });
            } else {
                return Err(invalid("Choose an image for this display first"));
            }
        }
        self.commit(previous, next)
    }

    fn check_displays(&self, displays: &[String]) -> Result<(), String> {
        if displays
            .iter()
            .any(|d| d != WILDCARD && !self.monitors.contains(d))
        {
            return Err(invalid("Unknown display"));
        }
        Ok(())
    }

    pub fn set(&mut self, id: &str, value: &str) -> Result<Value, String> {
        self.refresh()?;
        match id {
            KIND => {
                let previous = self.ready()?;
                if !["image", "video"].contains(&value) {
                    return Err(invalid("Use image or video"));
                }
                if value == "video" && previous.video.is_none() {
                    return Err(invalid("Choose a video file first"));
                }
                if value == "image" && previous.images.is_empty() {
                    return Err(invalid("Choose an image file first"));
                }
                let mut next = previous.clone();
                next.kind = value.into();
                self.commit(previous, next)?;
            }
            FILE => self.set_file(value)?,
            FIT => self.set_fit(value)?,
            PAUSE => {
                let previous = self.ready()?;
                if !video::PAUSES.contains(&value) {
                    return Err(invalid("Use keep, pause or stop"));
                }
                let mut next = previous.clone();
                next.video
                    .as_mut()
                    .ok_or_else(|| invalid("Choose a video file first"))?
                    .pause = value.into();
                self.commit(previous, next)?;
            }
            SPLASH | SPLASH_OFFSET | SPLASH_OPACITY => {
                let previous = self.ready()?;
                let mut next = previous.clone();
                match id {
                    SPLASH => {
                        next.splash.enabled =
                            value.parse().map_err(|_| invalid("Use true or false"))?;
                    }
                    SPLASH_OFFSET => {
                        next.splash.offset = value
                            .parse()
                            .ok()
                            .filter(|o| (0..=10_000).contains(o))
                            .ok_or_else(|| invalid("Use 0 to 10000"))?;
                    }
                    _ => {
                        next.splash.opacity = value
                            .parse()
                            .ok()
                            .filter(|o| (0.0..=1.0).contains(o))
                            .ok_or_else(|| invalid("Use 0 to 1"))?;
                    }
                }
                self.commit(previous, next)?;
            }
            DISPLAY => {
                return Err(invalid(
                    "Display is chosen with each change; pass it with the file or fit",
                ));
            }
            _ => return Err(invalid("Unknown setting")),
        }
        Ok(self.state())
    }

    /// Adopt the system's values, or apply the saved ones with readback.
    pub fn resolve(&mut self, source: &str) -> Result<(), String> {
        self.refresh()?;
        let observed = self
            .observed
            .clone()
            .ok_or("Background configuration cannot be detected")?;
        let saved = self
            .saved
            .clone()
            .ok_or("Background configuration is not initialized")?;
        match source {
            "system" => {
                self.persist(&observed)?;
                self.saved = Some(observed);
                self.operation_error = None;
                self.refresh()
            }
            "settings" => {
                if let Some(reason) = &self.write_blocked {
                    return Err(format!(
                        "hyprpaper.conf is read-only for Settings: {reason}"
                    ));
                }
                self.commit(observed, saved)
            }
            _ => Err(invalid("Unknown resolution")),
        }
    }

    /// Reads for hot paths and error reporting; `operation_error` stays until a retry.
    pub fn error(&self) -> Option<&str> {
        self.operation_error
            .as_deref()
            .or(self.read_error.as_deref())
    }

    pub fn clear_operation_error(&mut self) {
        self.operation_error = None;
    }

    pub fn state(&self) -> Value {
        json!({
            "initialized": self.saved.is_some(),
            "saved": self.saved,
            "system": self.observed,
            "conflict": self.has_conflict(),
            "write_blocked": self.write_blocked,
            "monitors": self.monitors,
            "active": self.active,
            "warnings": self.warnings,
            "previews": self.previews,
            "names": self.referenced_paths().into_iter()
                .map(|p| (p.to_owned(), json!(media::display_name(p))))
                .collect::<serde_json::Map<_, _>>(),
            "error": self.error(),
        })
    }

    pub fn setting_value(&self, id: &str) -> Value {
        let Some(saved) = &self.saved else {
            return Value::Null;
        };
        let image = saved
            .images
            .iter()
            .find(|i| i.monitor == WILDCARD)
            .or(saved.images.first());
        match id {
            KIND => json!(saved.kind),
            DISPLAY => json!(self.monitors),
            FILE if saved.kind == "video" => json!(saved.video.as_ref().map(|v| &v.path)),
            FILE => json!(image.map(|i| &i.path)),
            FIT if saved.kind == "video" => json!(saved.video.as_ref().map(|v| &v.fit)),
            FIT => json!(image.map(|i| &i.fit)),
            PAUSE => json!(saved.video.as_ref().map(|v| &v.pause)),
            SPLASH => json!(saved.splash.enabled),
            SPLASH_OFFSET => json!(saved.splash.offset),
            SPLASH_OPACITY => json!(saved.splash.opacity),
            _ => Value::Null,
        }
    }

    // Accent color.

    pub fn accent_state(&self) -> Value {
        json!({
            "source": self.accent.source,
            "color": self.accent.color,
            "sampled_from": self.accent.sampled_from,
            "error": self.accent_error,
        })
    }

    pub fn accent_value(&self, id: &str) -> Value {
        if id == ACCENT_SOURCE {
            json!(self.accent.source)
        } else {
            json!(self.accent.color)
        }
    }

    fn save_accent(&mut self, next: Accent) -> Result<(), String> {
        let text = toml::to_string(&next).map_err(|e| e.to_string())?;
        atomic_write(&self.paths.accent, text.as_bytes())?;
        self.accent = next;
        Ok(())
    }

    fn sample(&self, path: &str) -> Result<String, String> {
        accent::seed_from_pixels(&self.desktop.sample_pixels(path)?)
    }

    /// Reloads the preference and follows the background. A failed sample keeps the
    /// last color and stays visible; it never blocks the background itself.
    pub fn refresh_accent(&mut self) {
        let result = (|| {
            self.accent = accent::load(&self.paths.accent)?;
            if self.accent.source != "background" {
                return Ok(());
            }
            let Some(path) = self
                .saved
                .as_ref()
                .and_then(Saved::current_path)
                .map(str::to_owned)
            else {
                return Ok(());
            };
            if self.accent.sampled_from.as_deref() == Some(path.as_str()) {
                return Ok(());
            }
            let color = self.sample(&path)?;
            self.save_accent(Accent {
                color,
                sampled_from: Some(path),
                ..self.accent.clone()
            })
        })();
        self.accent_error = result.err();
    }

    pub fn set_accent(&mut self, id: &str, value: &str) -> Result<Value, String> {
        let current = accent::load(&self.paths.accent)?;
        let next = if id == ACCENT_COLOR {
            Accent {
                source: "custom".into(),
                color: accent::normalize_color(value)
                    .ok_or_else(|| invalid("Use a #RRGGBB color"))?,
                sampled_from: None,
                ..current
            }
        } else if value == "custom" {
            Accent {
                source: "custom".into(),
                sampled_from: None,
                ..current
            }
        } else if value == "background" {
            let path = self
                .saved
                .as_ref()
                .and_then(Saved::current_path)
                .ok_or_else(|| invalid("Choose a background first"))?
                .to_owned();
            Accent {
                source: "background".into(),
                color: self.sample(&path)?,
                sampled_from: Some(path),
                ..current
            }
        } else {
            return Err(invalid("Use background or custom"));
        };
        self.save_accent(next)?;
        self.accent_error = None;
        Ok(self.accent_state())
    }
}

fn validate(saved: &Saved) -> Result<(), String> {
    let image_ok = saved.images.iter().all(|i| {
        FITS.contains(&i.fit.as_str()) && i.path.starts_with('/') && !i.path.contains(',')
    });
    let video_ok = saved.video.as_ref().is_none_or(|v| {
        video::FITS.contains(&v.fit.as_str())
            && video::PAUSES.contains(&v.pause.as_str())
            && v.path.starts_with('/')
    });
    if saved.version != 1
        || !["image", "video"].contains(&saved.kind.as_str())
        || !image_ok
        || !video_ok
        || (saved.kind == "video" && saved.video.is_none())
    {
        return Err("Invalid background configuration".into());
    }
    Ok(())
}

/// `{"<field>":"…","display":"…" or ["…","…"]}`, or a bare value meaning all displays.
fn target_request(request: &str, field: &str) -> Result<(String, Vec<String>), String> {
    let everywhere = || vec![WILDCARD.to_owned()];
    if !request.starts_with('{') {
        return Ok((request.to_owned(), everywhere()));
    }
    let value: Value =
        serde_json::from_str(request).map_err(|_| invalid("Expected a JSON object"))?;
    let object = value
        .as_object()
        .ok_or_else(|| invalid("Expected a JSON object"))?;
    if object.keys().any(|k| k != field && k != "display") {
        return Err(invalid("Unknown field"));
    }
    let main = object
        .get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| invalid(&format!("Missing {field}")))?;
    let displays = match object.get("display") {
        None => everywhere(),
        Some(Value::String(display)) => vec![display.clone()],
        Some(Value::Array(list)) => list
            .iter()
            .map(|d| d.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| invalid("Invalid display"))?,
        Some(_) => return Err(invalid("Invalid display")),
    };
    let wildcard = displays.iter().any(|d| d == WILDCARD);
    if displays.is_empty() || (wildcard && displays.len() > 1) {
        return Err(invalid("Invalid display"));
    }
    Ok((main.to_owned(), displays))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct Fake {
        active: BTreeMap<String, String>,
        enabled: bool,
        running: bool,
        players: Vec<(u32, Vec<String>)>,
        fail_apply: bool,
        fail_unit: bool,
        fail_restart: bool,
        restarts: usize,
        fail_sample: bool,
        applied: Vec<String>,
        pixels: Vec<u8>,
    }
    #[derive(Clone, Default)]
    struct FakeDesktop(Arc<Mutex<Fake>>);
    impl Desktop for FakeDesktop {
        fn monitors(&self) -> Result<Vec<String>, String> {
            Ok(vec!["DP-1".into(), "DP-2".into()])
        }
        fn apply_image(&self, monitor: &str, path: &str, fit: &str) -> Result<(), String> {
            let mut fake = self.0.lock().unwrap();
            if fake.fail_apply {
                return Err("hyprpaper is not running".into());
            }
            fake.applied.push(format!("{monitor},{path},{fit}"));
            fake.active.insert(monitor.into(), path.into());
            Ok(())
        }
        fn active_images(&self) -> Result<BTreeMap<String, String>, String> {
            Ok(self.0.lock().unwrap().active.clone())
        }
        fn layers(&self) -> Result<Value, String> {
            Ok(json!({}))
        }
        fn reload_units(&self) -> Result<(), String> {
            Ok(())
        }
        fn unit_enabled(&self) -> bool {
            self.0.lock().unwrap().enabled
        }
        fn unit_active(&self) -> bool {
            self.0.lock().unwrap().running
        }
        fn start_unit(&self) -> Result<(), String> {
            let mut fake = self.0.lock().unwrap();
            if fake.fail_unit {
                return Err("mpvpaper did not keep running".into());
            }
            fake.enabled = true;
            fake.running = true;
            Ok(())
        }
        fn stop_unit(&self) -> Result<(), String> {
            let mut fake = self.0.lock().unwrap();
            fake.enabled = false;
            fake.running = false;
            Ok(())
        }
        fn other_players(&self) -> Vec<(u32, Vec<String>)> {
            self.0.lock().unwrap().players.clone()
        }
        fn stop_process(&self, pid: u32) {
            self.0.lock().unwrap().players.retain(|(p, _)| *p != pid);
        }
        fn restart_hyprpaper(&self, config: &Path) -> Result<(), String> {
            let mut fake = self.0.lock().unwrap();
            fake.restarts += 1;
            // Rolling back after a failure must still be able to restore the old file.
            if fake.fail_restart {
                fake.fail_restart = false;
                return Err("hyprpaper did not stop".into());
            }
            let text = fs::read_to_string(config).unwrap_or_default();
            let images = hyprpaper::parse(&text, None).unwrap().images;
            fake.active.clear();
            for monitor in ["DP-1", "DP-2"] {
                if let Some(image) = images
                    .iter()
                    .find(|i| i.monitor == monitor)
                    .or(images.iter().find(|i| i.monitor == WILDCARD))
                {
                    fake.active.insert(monitor.into(), image.path.clone());
                }
            }
            Ok(())
        }
        fn mime_type(&self, path: &Path) -> Result<String, String> {
            Ok(match path.extension().and_then(|e| e.to_str()) {
                Some("png") => "image/png",
                Some("mp4") => "video/mp4",
                _ => "text/plain",
            }
            .into())
        }
        fn sample_pixels(&self, _: &str) -> Result<Vec<u8>, String> {
            let fake = self.0.lock().unwrap();
            if fake.fail_sample {
                return Err("ffmpeg failed".into());
            }
            Ok(fake.pixels.clone())
        }
        fn write_preview(&self, _: &str, output: &Path) -> Result<(), String> {
            fs::write(output, b"png").map_err(|e| e.to_string())
        }
    }

    struct Setup {
        root: tempfile::TempDir,
        fake: FakeDesktop,
        manager: BackgroundManager<FakeDesktop>,
    }

    fn setup(conf: Option<&str>) -> Setup {
        let root = tempfile::tempdir().unwrap();
        let path = |name: &str| root.path().join(name);
        if let Some(conf) = conf {
            fs::write(path("hyprpaper.conf"), conf).unwrap();
        }
        fs::create_dir(path("units")).unwrap();
        let fake = FakeDesktop::default();
        fake.0.lock().unwrap().pixels = [30, 90, 220, 255].repeat(32);
        let manager = BackgroundManager::new(
            fake.clone(),
            Paths {
                config: path("background.toml"),
                accent: path("accent.toml"),
                media: path("backgrounds"),
                cache: path("previews"),
                hyprpaper: path("hyprpaper.conf"),
                units: path("units"),
                home: None,
            },
        );
        Setup {
            root,
            fake,
            manager,
        }
    }

    fn source(setup: &Setup, name: &str) -> String {
        let file = setup.root.path().join(name);
        fs::write(&file, name.as_bytes()).unwrap();
        file.to_str().unwrap().to_owned()
    }

    fn file(setup: &Setup, name: &str) -> String {
        fs::read_to_string(setup.root.path().join(name)).unwrap()
    }

    const WALLPAPER: &str =
        "wallpaper {\n    monitor = *\n    path = /old.png\n    fit_mode = tile\n}\n";

    #[test]
    fn first_use_records_the_system_and_applies_nothing() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let state = s.manager.state();
        assert_eq!(state["saved"]["images"][0]["path"], "/old.png");
        assert_eq!(state["conflict"], false);
        assert!(s.fake.0.lock().unwrap().applied.is_empty());
        assert_eq!(file(&s, "hyprpaper.conf"), WALLPAPER);
        assert!(file(&s, "background.toml").contains("/old.png"));
    }

    #[test]
    fn detection_failure_leaves_configuration_uninitialized() {
        let mut s = setup(Some("source = x\n"));
        assert!(s.manager.refresh().is_err());
        let state = s.manager.state();
        assert_eq!(state["initialized"], false);
        assert!(state["write_blocked"].as_str().unwrap().contains("source"));
        assert!(!s.root.path().join("background.toml").exists());
        assert_eq!(file(&s, "hyprpaper.conf"), "source = x\n");
    }

    #[test]
    fn a_selected_image_is_copied_and_only_the_copy_is_referenced() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let picked = source(&s, "picked.png");
        s.manager.set(FILE, &picked).unwrap();
        fs::remove_file(&picked).unwrap();
        let conf = file(&s, "hyprpaper.conf");
        let saved = file(&s, "background.toml");
        let copy = s.manager.state()["saved"]["images"][0]["path"]
            .as_str()
            .unwrap()
            .to_owned();
        assert!(copy.contains("/backgrounds/") && copy.ends_with("-picked.png"));
        assert!(Path::new(&copy).exists());
        assert!(!conf.contains(&picked) && !saved.contains(&picked));
        assert!(conf.contains(&copy));
        assert_eq!(s.fake.0.lock().unwrap().active["DP-1"], copy);
        assert_eq!(s.fake.0.lock().unwrap().active["DP-2"], copy);
        // The inherited fit survives and the original file is kept as a backup.
        assert!(conf.contains("fit_mode = tile"));
        assert_eq!(file(&s, "hyprpaper.conf.remya-backup"), WALLPAPER);
        assert_eq!(s.manager.state()["conflict"], false);
    }

    #[test]
    fn per_display_images_coexist_and_all_displays_replaces_them() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let one = source(&s, "one.png");
        let request = json!({"path": one, "display": "DP-2"}).to_string();
        s.manager.set(FILE, &request).unwrap();
        let state = s.manager.state();
        assert_eq!(state["saved"]["images"].as_array().unwrap().len(), 2);
        // Only the chosen display is addressed; the other keeps what it shows.
        assert!(
            s.fake
                .0
                .lock()
                .unwrap()
                .applied
                .iter()
                .all(|a| a.starts_with("DP-2,"))
        );
        s.manager
            .set(FIT, &json!({"fit":"contain","display":"DP-2"}).to_string())
            .unwrap();
        assert_eq!(s.manager.state()["saved"]["images"][1]["fit"], "contain");
        let all = source(&s, "all.png");
        s.manager.set(FILE, &all).unwrap();
        assert_eq!(
            s.manager.state()["saved"]["images"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert!(
            s.manager
                .set(FILE, &json!({"path": all, "display":"HDMI-9"}).to_string())
                .is_err()
        );
    }

    #[test]
    fn video_runs_in_the_managed_unit_and_image_is_restored_when_switching_back() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        assert!(
            s.manager
                .set(KIND, "video")
                .unwrap_err()
                .starts_with("InvalidArgument")
        );
        let clip = source(&s, "clip.mp4");
        s.manager.set(FILE, &clip).unwrap();
        let unit = file(&s, &format!("units/{UNIT}"));
        assert!(unit.contains("-clip.mp4") && !unit.contains(&clip));
        assert_eq!(s.manager.state()["saved"]["kind"], "video");
        assert!(s.fake.0.lock().unwrap().running);
        assert_eq!(file(&s, "hyprpaper.conf"), WALLPAPER);
        assert!(s.manager.set(FIT, "tile").unwrap_err().contains("cover"));
        s.manager.set(FIT, "fill").unwrap();
        assert!(file(&s, &format!("units/{UNIT}")).contains("keepaspect=no"));
        s.manager.set(PAUSE, "pause").unwrap();
        assert!(file(&s, &format!("units/{UNIT}")).contains("--auto-pause"));
        s.manager.set(KIND, "image").unwrap();
        assert!(!s.fake.0.lock().unwrap().enabled);
        // The video stays remembered and switching back needs no new selection.
        assert_eq!(s.manager.state()["conflict"], false);
        s.manager.set(KIND, "video").unwrap();
        assert!(s.fake.0.lock().unwrap().running);
    }

    #[test]
    fn choosing_an_image_stops_other_mpvpaper_processes() {
        let mut s = setup(Some(WALLPAPER));
        s.fake.0.lock().unwrap().players =
            vec![(7, ["mpvpaper", "DP-1", "/v.mp4"].map(String::from).to_vec())];
        s.manager.refresh().unwrap();
        let state = s.manager.state();
        assert_eq!(state["saved"]["kind"], "video");
        assert!(
            state["warnings"][0]
                .as_str()
                .unwrap()
                .contains("Another program")
        );
        s.manager.set(KIND, "image").unwrap();
        assert!(s.fake.0.lock().unwrap().players.is_empty());
    }

    #[test]
    fn failed_application_restores_files_and_retains_the_saved_configuration() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let saved = file(&s, "background.toml");
        s.fake.0.lock().unwrap().fail_apply = true;
        let picked = source(&s, "picked.png");
        assert!(
            s.manager
                .set(FILE, &picked)
                .unwrap_err()
                .contains("not running")
        );
        assert_eq!(file(&s, "hyprpaper.conf"), WALLPAPER);
        assert_eq!(file(&s, "background.toml"), saved);
        assert!(s.manager.error().unwrap().contains("not running"));
        s.fake.0.lock().unwrap().fail_apply = false;

        s.fake.0.lock().unwrap().fail_unit = true;
        let clip = source(&s, "clip.mp4");
        assert!(s.manager.set(FILE, &clip).is_err());
        assert_eq!(file(&s, "background.toml"), saved);
        assert_eq!(s.manager.state()["saved"]["kind"], "image");
    }

    #[test]
    fn external_changes_conflict_and_both_resolutions_work() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let conf = s.root.path().join("hyprpaper.conf");
        let edited = WALLPAPER.replace("/old.png", "/edited.png");
        fs::write(&conf, &edited).unwrap();
        s.manager.refresh().unwrap();
        assert_eq!(s.manager.state()["conflict"], true);
        // Both values stay and writes wait for an explicit choice.
        assert_eq!(s.manager.state()["saved"]["images"][0]["path"], "/old.png");
        assert_eq!(
            s.manager.state()["system"]["images"][0]["path"],
            "/edited.png"
        );
        assert!(
            s.manager
                .set(SPLASH, "false")
                .unwrap_err()
                .starts_with("Conflict")
        );

        s.manager.resolve("settings").unwrap();
        assert_eq!(s.manager.state()["conflict"], false);
        assert!(file(&s, "hyprpaper.conf").contains("/old.png"));
        assert_eq!(s.fake.0.lock().unwrap().active["DP-1"], "/old.png");

        fs::write(&conf, &edited).unwrap();
        s.manager.resolve("system").unwrap();
        assert_eq!(s.manager.state()["conflict"], false);
        assert_eq!(
            s.manager.state()["saved"]["images"][0]["path"],
            "/edited.png"
        );
        assert!(file(&s, "hyprpaper.conf").contains("/edited.png"));
        assert!(s.manager.resolve("other").is_err());
    }

    #[test]
    fn replaced_copies_are_removed_but_a_remembered_video_stays() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        s.manager.set(FILE, &source(&s, "clip.mp4")).unwrap();
        s.manager.set(FILE, &source(&s, "one.png")).unwrap();
        let first = s.manager.state()["saved"]["images"][0]["path"]
            .as_str()
            .unwrap()
            .to_owned();
        s.manager.set(FILE, &source(&s, "two.png")).unwrap();
        assert!(!Path::new(&first).exists());
        let names = fs::read_dir(s.root.path().join("backgrounds"))
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect::<Vec<_>>();
        assert_eq!(names.len(), 2, "{names:?}");
        assert!(names.iter().any(|n| n.ends_with("-clip.mp4")));
    }

    #[test]
    fn splash_is_validated_and_written_without_touching_images() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        s.manager.set(SPLASH, "false").unwrap();
        s.manager.set(SPLASH_OFFSET, "40").unwrap();
        s.manager.set(SPLASH_OPACITY, "0.25").unwrap();
        let conf = file(&s, "hyprpaper.conf");
        assert!(conf.contains("splash = false") && conf.contains("splash_offset = 40"));
        assert!(conf.contains("/old.png"));
        assert!(s.fake.0.lock().unwrap().applied.is_empty());
        assert_eq!(s.fake.0.lock().unwrap().restarts, 3);
        for (id, bad) in [(SPLASH, "x"), (SPLASH_OFFSET, "-1"), (SPLASH_OPACITY, "2")] {
            assert!(
                s.manager
                    .set(id, bad)
                    .unwrap_err()
                    .starts_with("InvalidArgument")
            );
        }
        assert!(s.manager.set(DISPLAY, "DP-1").is_err());
    }

    #[test]
    fn only_changes_ipc_cannot_apply_restart_hyprpaper() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let restarts = |s: &Setup| s.fake.0.lock().unwrap().restarts;
        s.manager.set(FILE, &source(&s, "one.png")).unwrap();
        s.manager.set(FIT, "contain").unwrap();
        assert_eq!(restarts(&s), 0);
        assert_eq!(s.fake.0.lock().unwrap().applied.len(), 4);

        s.manager.set(FIT, "fill").unwrap();
        assert_eq!(restarts(&s), 1);
        assert_eq!(s.fake.0.lock().unwrap().applied.len(), 4);
        s.manager.set(SPLASH, "false").unwrap();
        assert_eq!(restarts(&s), 2);

        // Changing one display leaves the other's Fill alone; IPC would make it Cover.
        s.manager
            .set(FIT, &json!({"fit":"cover","display":"DP-2"}).to_string())
            .unwrap();
        assert_eq!(restarts(&s), 2);
        let applied = s.fake.0.lock().unwrap().applied.clone();
        assert!(applied.last().unwrap().starts_with("DP-2,"));
        assert_eq!(applied.len(), 5);
    }

    #[test]
    fn a_restart_waits_while_a_video_covers_hyprpaper() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        s.manager.set(FILE, &source(&s, "clip.mp4")).unwrap();
        s.manager.set(SPLASH, "false").unwrap();
        assert_eq!(s.fake.0.lock().unwrap().restarts, 0);
        assert!(file(&s, "hyprpaper.conf").contains("splash = false"));
        s.manager.set(KIND, "image").unwrap();
        assert_eq!(s.fake.0.lock().unwrap().restarts, 1);
        s.manager.set(KIND, "video").unwrap();
        s.manager.set(KIND, "image").unwrap();
        assert_eq!(s.fake.0.lock().unwrap().restarts, 1);
    }

    #[test]
    fn a_failed_restart_restores_the_file_and_the_running_wallpaper() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let saved = file(&s, "background.toml");
        s.fake.0.lock().unwrap().fail_restart = true;
        assert!(
            s.manager
                .set(SPLASH, "false")
                .unwrap_err()
                .contains("did not stop")
        );
        assert_eq!(file(&s, "hyprpaper.conf"), WALLPAPER);
        assert_eq!(file(&s, "background.toml"), saved);
        assert_eq!(s.fake.0.lock().unwrap().restarts, 2);
        assert_eq!(s.fake.0.lock().unwrap().active["DP-1"], "/old.png");
        assert!(s.manager.error().unwrap().contains("did not stop"));
    }

    #[test]
    fn accent_follows_the_background_and_keeps_its_color_on_failure() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        assert_eq!(s.manager.accent_state()["color"], accent::DEFAULT_COLOR);
        assert!(!s.root.path().join("accent.toml").exists());

        s.manager.set_accent(ACCENT_COLOR, "#a1b2c3").unwrap();
        assert_eq!(s.manager.accent_state()["color"], "#A1B2C3");
        assert!(s.manager.set_accent(ACCENT_COLOR, "red").is_err());

        s.manager.set_accent(ACCENT_SOURCE, "background").unwrap();
        let sampled = s.manager.accent_state()["color"]
            .as_str()
            .unwrap()
            .to_owned();
        assert_ne!(sampled, "#A1B2C3");

        s.fake.0.lock().unwrap().pixels = [220, 60, 30, 255].repeat(32);
        s.manager.set(FILE, &source(&s, "red.png")).unwrap();
        let resampled = s.manager.accent_state()["color"]
            .as_str()
            .unwrap()
            .to_owned();
        assert_ne!(resampled, sampled);

        s.fake.0.lock().unwrap().fail_sample = true;
        s.manager.set(FILE, &source(&s, "other.png")).unwrap();
        let state = s.manager.accent_state();
        assert_eq!(state["color"], resampled.as_str());
        assert!(state["error"].as_str().unwrap().contains("ffmpeg"));
        assert!(s.manager.set_accent(ACCENT_SOURCE, "other").is_err());
    }

    #[test]
    fn unsupported_files_are_rejected_before_anything_changes() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let note = source(&s, "note.txt");
        assert!(
            s.manager
                .set(FILE, &note)
                .unwrap_err()
                .contains("Unsupported")
        );
        assert!(s.manager.set(FILE, "relative.png").is_err());
        assert!(s.manager.set(FILE, "/does/not/exist.png").is_err());
        assert!(!s.root.path().join("backgrounds").exists());
    }

    #[test]
    fn requests_accept_bare_values_and_strict_objects() {
        let one = |d: &str| vec![d.to_owned()];
        assert_eq!(
            target_request("/a", "path").unwrap(),
            ("/a".into(), one("*"))
        );
        assert_eq!(
            target_request(r#"{"path":"/a","display":"DP-1"}"#, "path").unwrap(),
            ("/a".into(), one("DP-1"))
        );
        assert_eq!(
            target_request(r#"{"path":"/a","display":["DP-1","DP-2"]}"#, "path")
                .unwrap()
                .1,
            ["DP-1", "DP-2"]
        );
        for bad in [
            r#"{"path":"/a","other":1}"#,
            r#"{"display":"DP-1"}"#,
            r#"{"path":"/a","display":[]}"#,
            r#"{"path":"/a","display":["*","DP-1"]}"#,
            r#"{"path":"/a","display":[1]}"#,
            r#"{"path":"/a","display":1}"#,
        ] {
            assert!(target_request(bad, "path").is_err(), "{bad}");
        }
    }

    #[test]
    fn a_group_of_displays_changes_together() {
        let mut s = setup(Some(WALLPAPER));
        s.manager.refresh().unwrap();
        let group = json!(["DP-1", "DP-2"]);
        let one = source(&s, "one.png");
        s.manager
            .set(FILE, &json!({"path": one, "display": group}).to_string())
            .unwrap();
        let state = s.manager.state();
        let images = state["saved"]["images"].as_array().unwrap();
        assert_eq!(images.len(), 3);
        assert_eq!(images[1]["path"], images[2]["path"]);
        // Each display keeps the fit it was already using.
        assert_eq!(images[1]["fit"], "tile");
        s.manager
            .set(FIT, &json!({"fit":"contain","display":group}).to_string())
            .unwrap();
        let state = s.manager.state();
        let images = state["saved"]["images"].as_array().unwrap();
        assert_eq!(images[0]["fit"], "tile");
        assert_eq!(images[1]["fit"], "contain");
        assert_eq!(images[2]["fit"], "contain");
        let bad = json!({"fit":"cover","display":["DP-1","HDMI-9"]}).to_string();
        assert!(
            s.manager
                .set(FIT, &bad)
                .unwrap_err()
                .contains("Unknown display")
        );
    }
}
