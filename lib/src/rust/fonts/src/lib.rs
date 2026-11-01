//! Installed fonts through fontconfig. Writes touch only the user's font directory;
//! the font list is a live observation, so there is nothing to save or reconcile.
use remya_settings_display::{atomic_write, run_bytes};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
    time::Duration,
};

pub const SEARCH: &str = "fonts.65a8477b";
pub const INSTALL: &str = "fonts.158ba0bb";
pub const DETAILS: &str = "fonts.fc3969c7";
pub const UNINSTALL: &str = "fonts.f869cae5";
pub const IDS: [&str; 4] = [SEARCH, INSTALL, DETAILS, UNINSTALL];

const EXTENSIONS: [&str; 6] = ["ttf", "otf", "ttc", "otc", "woff", "woff2"];
const SIZE_LIMIT: u64 = 256 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(60);
const FORMAT: &str = "%{family[0]}\t%{style[0]}\t%{fontformat}\t%{file}\n";

fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}

pub trait Fontconfig: Send {
    /// One `family<TAB>style<TAB>format<TAB>file` line per installed face.
    fn list(&self) -> Result<String, String>;
    /// Family names inside a font file; an error means it is not a usable font.
    fn query(&self, file: &Path) -> Result<Vec<String>, String>;
    fn rebuild(&self, directory: &Path) -> Result<(), String>;
}

pub struct RealFontconfig;

fn tool(program: &str, args: &[&str]) -> Result<String, String> {
    let bytes = run_bytes(program, args, &[], TIMEOUT)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

impl Fontconfig for RealFontconfig {
    fn list(&self) -> Result<String, String> {
        tool("fc-list", &["--format", FORMAT])
    }
    fn query(&self, file: &Path) -> Result<Vec<String>, String> {
        let file = file.to_str().ok_or("Unsupported file path")?;
        let output = tool("fc-query", &["--format", "%{family[0]}\n", file])?;
        Ok(output
            .lines()
            .filter(|l| !l.is_empty())
            .map(str::to_owned)
            .collect())
    }
    fn rebuild(&self, directory: &Path) -> Result<(), String> {
        let directory = directory.to_str().ok_or("Unsupported font directory")?;
        tool("fc-cache", &["--force", directory]).map(|_| ())
    }
}

struct Face {
    family: String,
    style: String,
    format: String,
    file: String,
}

fn parse_list(output: &str) -> Vec<Face> {
    output
        .lines()
        .filter_map(|line| {
            let mut parts = line.split('\t');
            let family = parts.next()?;
            let style = parts.next()?;
            let format = parts.next()?;
            let file = parts.next()?;
            (!family.is_empty() && !file.is_empty()).then(|| Face {
                family: family.to_owned(),
                style: style.to_owned(),
                format: format.to_owned(),
                file: file.to_owned(),
            })
        })
        .collect()
}

pub struct FontManager<F: Fontconfig> {
    fontconfig: F,
    directory: PathBuf,
}

impl<F: Fontconfig> FontManager<F> {
    pub fn new(fontconfig: F, directory: PathBuf) -> Self {
        Self {
            fontconfig,
            directory,
        }
    }

    fn removable(&self, file: &str) -> bool {
        Path::new(file).starts_with(&self.directory)
    }

    fn faces(&self) -> Result<Vec<Face>, String> {
        Ok(parse_list(&self.fontconfig.list()?))
    }

    /// Families sorted by name, each with what the list and details views need.
    pub fn families(&self) -> Result<Value, String> {
        let mut grouped: BTreeMap<String, [BTreeSet<String>; 3]> = BTreeMap::new();
        for face in self.faces()? {
            let entry = grouped.entry(face.family).or_default();
            entry[0].insert(face.style);
            entry[1].insert(face.format);
            entry[2].insert(face.file);
        }
        let mut families = grouped
            .into_iter()
            .map(|(family, [styles, formats, files])| {
                let removable = files.iter().filter(|f| self.removable(f)).count();
                json!({
                    "family": family,
                    "styles": styles,
                    "formats": formats,
                    "files": files,
                    "user_files": removable,
                    "system_files": files.len() - removable,
                })
            })
            .collect::<Vec<_>>();
        families.sort_by_key(|f| f["family"].as_str().unwrap_or("").to_lowercase());
        Ok(json!({"directory": self.directory, "families": families}))
    }

    pub fn search(&self, query: &str) -> Result<Value, String> {
        let needle = query.to_lowercase();
        let mut state = self.families()?;
        let matches = state["families"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|f| {
                f["family"]
                    .as_str()
                    .is_some_and(|name| name.to_lowercase().contains(&needle))
            })
            .cloned()
            .collect::<Vec<_>>();
        state["families"] = json!(matches);
        Ok(state)
    }

    pub fn details(&self, family: &str) -> Result<Value, String> {
        self.families()?["families"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|f| f["family"] == family)
            .cloned()
            .ok_or_else(|| invalid("Unknown font family"))
    }

    /// Copies a font into the user directory, then confirms fontconfig lists it.
    pub fn install(&self, source: &str) -> Result<Value, String> {
        let source = Path::new(source);
        if !source.is_absolute() || !source.is_file() {
            return Err(invalid("Choose an existing font file"));
        }
        source
            .extension()
            .and_then(|e| e.to_str())
            .map(str::to_lowercase)
            .filter(|e| EXTENSIONS.contains(&e.as_str()))
            .ok_or_else(|| invalid("Use a TTF, OTF, TTC, OTC, WOFF or WOFF2 file"))?;
        let name = source
            .file_name()
            .ok_or_else(|| invalid("Invalid file name"))?;
        let size = fs::metadata(source).map_err(|e| e.to_string())?.len();
        if size > SIZE_LIMIT {
            return Err(invalid("The font file is too large"));
        }
        let families = self
            .fontconfig
            .query(source)
            .map_err(|_| invalid("This file is not a valid font"))?;
        if families.is_empty() {
            return Err(invalid("This file is not a valid font"));
        }
        let target = self.directory.join(name);
        if target.exists() {
            return Err(format!(
                "A font named {} is already installed",
                name.to_string_lossy()
            ));
        }
        let bytes = fs::read(source).map_err(|e| e.to_string())?;
        atomic_write(&target, &bytes)?;
        let installed = target.to_string_lossy().into_owned();
        let confirmed = self.fontconfig.rebuild(&self.directory).and_then(|()| {
            self.faces()?
                .iter()
                .any(|face| face.file == installed)
                .then_some(())
                .ok_or_else(|| "Fontconfig did not list the installed font".to_owned())
        });
        if let Err(error) = confirmed {
            let _ = fs::remove_file(&target);
            let _ = self.fontconfig.rebuild(&self.directory);
            return Err(error);
        }
        Ok(json!({"installed": installed, "families": families}))
    }

    /// Removes the family's files from the user directory. System files stay, and
    /// another family sharing a collection file is named before anything is removed.
    pub fn uninstall(&self, family: &str) -> Result<Value, String> {
        let faces = self.faces()?;
        let files = faces
            .iter()
            .filter(|f| f.family == family)
            .map(|f| f.file.clone())
            .collect::<BTreeSet<_>>();
        if files.is_empty() {
            return Err(invalid("Unknown font family"));
        }
        let (removable, system): (Vec<_>, Vec<_>) =
            files.into_iter().partition(|f| self.removable(f));
        if removable.is_empty() {
            return Err(invalid(
                "This font is installed for the whole system and cannot be removed here",
            ));
        }
        for file in &removable {
            fs::remove_file(file).map_err(|e| format!("{file}: {e}"))?;
        }
        self.fontconfig.rebuild(&self.directory)?;
        let remaining = self.faces()?;
        if remaining.iter().any(|f| removable.contains(&f.file)) {
            return Err("Fontconfig still lists the removed font".into());
        }
        Ok(json!({"removed": removable, "system_files_kept": system}))
    }
}

/// XDG_DATA_HOME/fonts, the directory the standard fontconfig setup scans first.
pub fn user_font_directory() -> Result<PathBuf, String> {
    xdg::BaseDirectories::new()
        .get_data_home()
        .map(|data| data.join("fonts"))
        .ok_or_else(|| "Absolute HOME required".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Clone)]
    struct Fake {
        system: Arc<Mutex<String>>,
        directory: PathBuf,
        accept: bool,
        visible: bool,
    }
    impl Fontconfig for Fake {
        fn list(&self) -> Result<String, String> {
            let mut out = self.system.lock().unwrap().clone();
            if self.visible {
                for entry in fs::read_dir(&self.directory)
                    .into_iter()
                    .flatten()
                    .flatten()
                {
                    out.push_str(&format!(
                        "User Sans\tRegular\tTrueType\t{}\n",
                        entry.path().display()
                    ));
                }
            }
            Ok(out)
        }
        fn query(&self, _: &Path) -> Result<Vec<String>, String> {
            if self.accept {
                Ok(vec!["User Sans".into()])
            } else {
                Err("no font".into())
            }
        }
        fn rebuild(&self, _: &Path) -> Result<(), String> {
            Ok(())
        }
    }

    fn setup(accept: bool, visible: bool) -> (tempfile::TempDir, FontManager<Fake>) {
        let root = tempfile::tempdir().unwrap();
        let directory = root.path().join("fonts");
        let fake = Fake {
            system: Arc::new(Mutex::new(
                "Noto Sans\tBold\tCFF\t/usr/share/fonts/a.otf\nNoto Sans\tRegular\tTrueType\t/usr/share/fonts/b.ttf\n".into(),
            )),
            directory: directory.clone(),
            accept,
            visible,
        };
        (root, FontManager::new(fake, directory))
    }

    #[test]
    fn families_group_faces_and_mark_only_user_files_removable() {
        let (_root, fonts) = setup(true, true);
        let state = fonts.families().unwrap();
        let noto = &state["families"][0];
        assert_eq!(noto["family"], "Noto Sans");
        assert_eq!(noto["styles"].as_array().unwrap().len(), 2);
        assert_eq!(noto["user_files"], 0);
        assert_eq!(noto["system_files"], 2);
        assert!(fonts.details("Missing").is_err());
        assert_eq!(
            fonts.search("NOTO").unwrap()["families"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert!(
            fonts.search("zzz").unwrap()["families"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn install_uninstall_round_trip_stays_in_the_user_directory() {
        let (root, fonts) = setup(true, true);
        let source = root.path().join("user.ttf");
        fs::write(&source, b"font").unwrap();
        let installed = fonts.install(source.to_str().unwrap()).unwrap();
        let target = installed["installed"].as_str().unwrap().to_owned();
        assert!(target.starts_with(root.path().join("fonts").to_str().unwrap()));
        assert_eq!(fs::read(&target).unwrap(), b"font");
        assert!(source.exists());
        assert!(
            fonts
                .install(source.to_str().unwrap())
                .unwrap_err()
                .contains("already")
        );
        let details = fonts.details("User Sans").unwrap();
        assert_eq!(details["user_files"], 1);
        fonts.uninstall("User Sans").unwrap();
        assert!(!Path::new(&target).exists());
        assert!(
            fonts
                .uninstall("User Sans")
                .unwrap_err()
                .starts_with("InvalidArgument")
        );
    }

    #[test]
    fn system_fonts_and_invalid_files_are_refused() {
        let (root, fonts) = setup(false, true);
        let error = fonts.uninstall("Noto Sans").unwrap_err();
        assert!(error.contains("whole system"));
        assert!(Path::new("/usr").exists());
        let source = root.path().join("fake.ttf");
        fs::write(&source, b"not a font").unwrap();
        assert!(
            fonts
                .install(source.to_str().unwrap())
                .unwrap_err()
                .contains("not a valid")
        );
        let text = root.path().join("note.txt");
        fs::write(&text, b"x").unwrap();
        assert!(fonts.install(text.to_str().unwrap()).is_err());
        assert!(fonts.install("relative.ttf").is_err());
        assert!(!root.path().join("fonts").exists());
    }

    #[test]
    fn an_install_fontconfig_cannot_see_is_rolled_back() {
        let (root, fonts) = setup(true, false);
        let source = root.path().join("user.ttf");
        fs::write(&source, b"font").unwrap();
        assert!(
            fonts
                .install(source.to_str().unwrap())
                .unwrap_err()
                .contains("did not list")
        );
        assert_eq!(fs::read_dir(root.path().join("fonts")).unwrap().count(), 0);
    }

    #[test]
    fn list_parsing_skips_incomplete_lines() {
        let faces = parse_list("A\tB\tC\t/d\nbroken\n\t\t\t\n");
        assert_eq!(faces.len(), 1);
        assert_eq!(faces[0].file, "/d");
    }
}
