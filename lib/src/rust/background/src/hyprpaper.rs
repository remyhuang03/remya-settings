//! Strict reader and writer for `hyprpaper.conf`. Anything this reader cannot prove
//! equivalent after a rewrite makes the file read-only instead of being discarded.
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const WILDCARD: &str = "*";
pub const FITS: [&str; 4] = ["cover", "contain", "tile", "fill"];

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Image {
    pub monitor: String,
    pub path: String,
    pub fit: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Splash {
    pub enabled: bool,
    pub offset: i64,
    pub opacity: f64,
}

/// hyprpaper's documented defaults, used when a key is absent.
impl Default for Splash {
    fn default() -> Self {
        Self {
            enabled: true,
            offset: 20,
            opacity: 0.8,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct HyprpaperConfig {
    pub images: Vec<Image>,
    pub splash: Splash,
    /// Comment lines, retained at the top of a rewritten file.
    pub comments: Vec<String>,
}

fn boolean(value: &str) -> Option<bool> {
    match value {
        "true" | "yes" | "on" | "1" => Some(true),
        "false" | "no" | "off" | "0" => Some(false),
        _ => None,
    }
}

fn expand_home(path: &str, home: Option<&Path>) -> Result<String, String> {
    if let Some(rest) = path.strip_prefix('~') {
        let home = home.ok_or("A home path needs HOME")?;
        return Ok(format!(
            "{}/{}",
            home.display(),
            rest.trim_start_matches('/')
        ));
    }
    Ok(path.to_owned())
}

#[derive(Default)]
struct Pending {
    monitor: Option<String>,
    path: Option<String>,
    fit: Option<String>,
}

impl Pending {
    fn set(&mut self, key: &str, value: &str, line: usize) -> Result<(), String> {
        let slot = match key {
            "monitor" => &mut self.monitor,
            "path" => &mut self.path,
            "fit_mode" => &mut self.fit,
            "timeout" | "order" | "recursive" => {
                return Err(format!(
                    "line {line}: wallpaper rotation ({key}) is not supported"
                ));
            }
            other => return Err(format!("line {line}: unknown wallpaper key {other}")),
        };
        if slot.replace(value.to_owned()).is_some() {
            return Err(format!("line {line}: repeated wallpaper key {key}"));
        }
        Ok(())
    }

    fn finish(self, line: usize, home: Option<&Path>) -> Result<Image, String> {
        let path = self
            .path
            .filter(|path| !path.is_empty())
            .ok_or_else(|| format!("line {line}: wallpaper without a path"))?;
        let path = expand_home(&path, home)?;
        if !path.starts_with('/') || path.contains(['$', ',']) {
            return Err(format!("line {line}: unsupported wallpaper path {path}"));
        }
        let fit = self.fit.unwrap_or_else(|| "cover".into());
        if !FITS.contains(&fit.as_str()) {
            return Err(format!("line {line}: unknown fit mode {fit}"));
        }
        let monitor = self.monitor.unwrap_or_default();
        Ok(Image {
            monitor: if monitor.is_empty() {
                WILDCARD.into()
            } else {
                monitor
            },
            path,
            fit,
        })
    }
}

pub fn parse(text: &str, home: Option<&Path>) -> Result<HyprpaperConfig, String> {
    let mut config = HyprpaperConfig::default();
    let mut block: Option<Pending> = None;
    let mut array: Option<(Pending, usize)> = None;
    for (index, raw) in text.lines().enumerate() {
        let number = index + 1;
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('#') {
            if block.is_some() {
                return Err(format!("line {number}: comment inside a wallpaper block"));
            }
            config.comments.push(line.to_owned());
            continue;
        }
        if line.contains('#') {
            return Err(format!("line {number}: inline comments are not supported"));
        }
        if line == "}" {
            let done = block
                .take()
                .ok_or_else(|| format!("line {number}: unmatched closing brace"))?;
            config.images.push(done.finish(number, home)?);
            continue;
        }
        if line.starts_with("wallpaper") && line.ends_with('{') {
            if line.trim_end_matches('{').trim() != "wallpaper" || block.is_some() {
                return Err(format!("line {number}: unsupported wallpaper block"));
            }
            block = Some(Pending::default());
            continue;
        }
        let (key, value) = line
            .split_once('=')
            .map(|(k, v)| (k.trim(), v.trim()))
            .ok_or_else(|| format!("line {number}: unsupported syntax"))?;
        if let Some(pending) = block.as_mut() {
            pending.set(key, value, number)?;
            continue;
        }
        if let Some(field) = key.strip_prefix("wallpaper[]:") {
            // Each `wallpaper[]:monitor` starts the next entry of this array form.
            if field == "monitor"
                && let Some((done, line)) = array.take()
            {
                config.images.push(done.finish(line, home)?);
            }
            let (pending, _) = array.get_or_insert_with(|| (Pending::default(), number));
            pending.set(field, value, number)?;
            continue;
        }
        match key {
            "splash" => {
                config.splash.enabled =
                    boolean(value).ok_or_else(|| format!("line {number}: invalid splash value"))?;
            }
            "splash_offset" => {
                config.splash.offset = value
                    .parse()
                    .map_err(|_| format!("line {number}: invalid splash offset"))?;
            }
            "splash_opacity" => {
                config.splash.opacity = value
                    .parse()
                    .ok()
                    .filter(|o| (0.0..=1.0).contains(o))
                    .ok_or_else(|| format!("line {number}: invalid splash opacity"))?;
            }
            "ipc" => {
                if boolean(value) != Some(true) {
                    return Err(format!(
                        "line {number}: hyprpaper IPC is off, so backgrounds cannot be applied"
                    ));
                }
            }
            other => return Err(format!("line {number}: unsupported setting {other}")),
        }
    }
    if block.is_some() {
        return Err("Unterminated wallpaper block".into());
    }
    if let Some((done, line)) = array.take() {
        config.images.push(done.finish(line, home)?);
    }
    for (index, image) in config.images.iter().enumerate() {
        if config.images[..index]
            .iter()
            .any(|other| other.monitor == image.monitor)
        {
            return Err(format!(
                "Several wallpapers target display {}",
                image.monitor
            ));
        }
    }
    Ok(config)
}

impl HyprpaperConfig {
    /// `*` is the wildcard spelling: hyprlang does not list empty special-category keys.
    pub fn render(&self) -> String {
        let mut out = String::new();
        for comment in &self.comments {
            out.push_str(comment);
            out.push('\n');
        }
        if !self.comments.is_empty() {
            out.push('\n');
        }
        let defaults = Splash::default();
        if self.splash.enabled != defaults.enabled {
            out.push_str(&format!("splash = {}\n", self.splash.enabled));
        }
        if self.splash.offset != defaults.offset {
            out.push_str(&format!("splash_offset = {}\n", self.splash.offset));
        }
        if self.splash.opacity != defaults.opacity {
            out.push_str(&format!("splash_opacity = {}\n", self.splash.opacity));
        }
        for image in &self.images {
            if !out.is_empty() && !out.ends_with("\n\n") {
                out.push('\n');
            }
            out.push_str(&format!(
                "wallpaper {{\n    monitor = {}\n    path = {}\n    fit_mode = {}\n}}\n",
                image.monitor, image.path, image.fit
            ));
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_array_form_and_rewrites_it_as_equivalent_blocks() {
        let parsed = parse(
            "# mine\nwallpaper[]:monitor = eDP-1\nwallpaper[]:path = /a.png\nwallpaper[]:fit_mode = cover\n\nwallpaper[]:monitor =\nwallpaper[]:path = ~/b.png\nwallpaper[]:fit_mode = tile\n",
            Some(Path::new("/home/u")),
        )
        .unwrap();
        assert_eq!(parsed.images.len(), 2);
        assert_eq!(parsed.images[1].monitor, WILDCARD);
        assert_eq!(parsed.images[1].path, "/home/u/b.png");
        let again = parse(&parsed.render(), None).unwrap();
        assert_eq!(again, parsed);
        assert!(parsed.render().starts_with("# mine\n"));
    }

    #[test]
    fn block_form_and_splash_round_trip() {
        let parsed = parse(
            "splash = false\nsplash_offset = 4\nsplash_opacity = 0.5\nipc = true\nwallpaper {\n  monitor = DP-1\n  path = /a.png\n}\n",
            None,
        )
        .unwrap();
        assert!(!parsed.splash.enabled);
        assert_eq!(parsed.images[0].fit, "cover");
        assert_eq!(parse(&parsed.render(), None).unwrap(), parsed);
    }

    #[test]
    fn content_that_cannot_be_preserved_makes_the_file_read_only() {
        for bad in [
            "source = other.conf\n",
            "ipc = false\n",
            "$x = 1\n",
            "wallpaper {\n monitor =\n path = /dir\n timeout = 30\n}\n",
            "wallpaper {\n path = /a.png\n order = random\n}\n",
            "wallpaper {\n path = /a.png\n",
            "wallpaper {\n path = relative.png\n}\n",
            "wallpaper {\n path = /a,b.png\n}\n",
            "wallpaper {\n path = /a.png # note\n}\n",
            "wallpaper {\n path = /a.png\n fit_mode = stretch\n}\n",
            "wallpaper {\n path = /a.png\n}\nwallpaper {\n path = /b.png\n}\n",
            "}\n",
            "splash_opacity = 4\n",
        ] {
            assert!(parse(bad, None).is_err(), "{bad}");
        }
    }

    #[test]
    fn a_missing_file_is_equivalent_to_empty_defaults() {
        let parsed = parse("", None).unwrap();
        assert!(parsed.images.is_empty());
        assert_eq!(parsed.splash, Splash::default());
        assert_eq!(parsed.render(), "");
    }
}
