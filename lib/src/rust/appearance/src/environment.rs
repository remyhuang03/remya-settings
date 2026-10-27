use crate::api::{SystemThemeMode, ThemeTargetResult, ThemeTargetStatus};
use crate::files::{FileChange, read_optional};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const MATERIAL: &str = "QT_QUICK_CONTROLS_MATERIAL_THEME";
const UNIVERSAL: &str = "QT_QUICK_CONTROLS_UNIVERSAL_THEME";
const MARKER: &str = "Remy'a Settings appearance";

#[derive(Default)]
pub(crate) struct Environment {
    variables: Vec<&'static str>,
    fish: Option<PathBuf>,
    hypr: Option<PathBuf>,
}

impl Environment {
    pub fn current(config: &Path) -> Result<Self, String> {
        // Arch's Qt 6 package installs these modules here; never select a different style.
        let qml = Path::new("/usr/lib/qt6/qml/QtQuick/Controls");
        let variables = [("Material", MATERIAL), ("Universal", UNIVERSAL)]
            .into_iter()
            .filter_map(|(style, variable)| {
                qml.join(style).join("qmldir").is_file().then_some(variable)
            })
            .collect();
        let fish = command_exists("fish", "--version").then(|| config.join("fish/config.fish"));
        let hypr = std::env::var_os("HYPRLAND_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|| config.join("hypr/hyprland.lua"));
        if !hypr.is_absolute() {
            return Err("HYPRLAND_CONFIG must be an absolute path".into());
        }
        let hypr = (hypr.is_file() && command_exists("luac", "-v")).then_some(hypr);
        Ok(Self {
            variables,
            fish,
            hypr,
        })
    }

    pub fn read(&self) -> Result<Vec<ThemeTargetResult>, String> {
        let mut targets = self.styles();
        for (name, path, lua) in self.shells() {
            let detail = match path.filter(|_| !self.variables.is_empty()) {
                Some(path) => {
                    let bytes = read_optional(path)?.unwrap_or_default();
                    let content = std::str::from_utf8(&bytes)
                        .map_err(|error| format!("{}: {error}", path.display()))?;
                    let range = managed_range(content, lua)?;
                    if range.is_some() {
                        "Managed Qt defaults saved; inherited by new shell/session processes"
                    } else {
                        "No managed Qt defaults; applied on the next Light/Dark selection"
                    }
                }
                None => unavailable(lua),
            };
            targets.push(target(
                name,
                if path.is_some() && !self.variables.is_empty() {
                    ThemeTargetStatus::Detected
                } else {
                    ThemeTargetStatus::Unavailable
                },
                detail,
            ));
        }
        Ok(targets)
    }

    pub fn prepare(
        &self,
        mode: SystemThemeMode,
    ) -> Result<(Vec<FileChange>, Vec<ThemeTargetResult>), String> {
        let mut files = vec![];
        let mut targets = self.styles();
        for (name, path, lua) in self.shells() {
            let Some(path) = path.filter(|_| !self.variables.is_empty()) else {
                targets.push(target(
                    name,
                    ThemeTargetStatus::Unavailable,
                    unavailable(lua),
                ));
                continue;
            };
            let change = FileChange::prepare_text(path, |content| {
                let updated = edit(content, lua, &self.variables, mode)?;
                validate(&updated, lua).map_err(|error| format!("{}: {error}", path.display()))?;
                Ok(updated)
            })?;
            targets.push(target(name, if change.changed() {
                ThemeTargetStatus::Applied
            } else { ThemeTargetStatus::Unchanged }, if lua {
                "Qt defaults saved for the next Hyprland session; existing processes retain their environment"
            } else {
                "Qt defaults saved for new fish processes; existing shells retain their environment"
            }));
            files.push(change);
        }
        Ok((files, targets))
    }

    fn shells(&self) -> [(&'static str, Option<&Path>, bool); 2] {
        [
            ("fish environment", self.fish.as_deref(), false),
            ("Hyprland environment", self.hypr.as_deref(), true),
        ]
    }

    fn styles(&self) -> Vec<ThemeTargetResult> {
        [
            ("Qt Quick Material", MATERIAL),
            ("Qt Quick Universal", UNIVERSAL),
        ]
        .into_iter()
        .map(|(name, variable)| {
            target(
                name,
                if self.variables.contains(&variable) {
                    ThemeTargetStatus::Detected
                } else {
                    ThemeTargetStatus::Unavailable
                },
                if self.variables.contains(&variable) {
                    format!("{variable}; applies only to applications using this style")
                } else {
                    "Style module is not installed".into()
                },
            )
        })
        .collect()
    }
}

fn command_exists(command: &str, flag: &str) -> bool {
    Command::new(command)
        .arg(flag)
        .output()
        .is_ok_and(|output| output.status.success())
}

fn target(name: &str, status: ThemeTargetStatus, detail: impl Into<String>) -> ThemeTargetResult {
    ThemeTargetResult {
        name: name.into(),
        status,
        detail: detail.into(),
    }
}

fn unavailable(lua: bool) -> &'static str {
    if lua {
        "No installed Qt style, active Lua configuration, or luac syntax validator; skipped"
    } else {
        "No installed Qt style or fish shell; skipped"
    }
}

fn markers(lua: bool) -> (String, String) {
    let prefix = if lua { "--" } else { "#" };
    (
        format!("{prefix} BEGIN {MARKER}"),
        format!("{prefix} END {MARKER}"),
    )
}

fn managed_range(content: &str, lua: bool) -> Result<Option<std::ops::Range<usize>>, String> {
    let (begin, end) = markers(lua);
    let mut offset = 0;
    let mut starts = vec![];
    let mut ends = vec![];
    for line in content.split_inclusive('\n') {
        if line.trim_end() == begin {
            starts.push(offset);
        }
        if line.trim_end() == end {
            ends.push(offset + line.len());
        }
        offset += line.len();
    }
    match (starts.as_slice(), ends.as_slice()) {
        ([], []) => Ok(None),
        ([start], [end]) if start < end => Ok(Some(*start..*end)),
        _ => Err("Duplicate or incomplete managed appearance block; configuration retained".into()),
    }
}

fn edit(
    content: &str,
    lua: bool,
    variables: &[&str],
    mode: SystemThemeMode,
) -> Result<String, String> {
    let (begin, end) = markers(lua);
    let newline = if content.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let value = match mode {
        SystemThemeMode::Light => "Light",
        SystemThemeMode::Dark => "Dark",
    };
    let mut block = format!("{begin}{newline}");
    for variable in variables {
        block.push_str(&if lua {
            format!("hl.env(\"{variable}\", \"{value}\"){newline}")
        } else {
            format!("set -gx {variable} {value}{newline}")
        });
    }
    block.push_str(&format!("{end}{newline}"));
    let mut updated = content.to_owned();
    if let Some(range) = managed_range(content, lua)? {
        updated.replace_range(range, &block);
    } else {
        if !updated.is_empty() && !updated.ends_with('\n') {
            updated.push_str(newline);
        }
        updated.push_str(&block);
    }
    Ok(updated)
}

fn validate(content: &str, lua: bool) -> Result<(), String> {
    let mut command = if lua {
        Command::new("luac")
    } else {
        Command::new("fish")
    };
    if lua {
        command.args(["-p", "-"]);
    } else {
        command.args(["--no-config", "--no-execute"]);
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Cannot start configuration syntax validator: {error}"))?;
    let write = child.stdin.take().unwrap().write_all(content.as_bytes());
    let status = child.wait().map_err(|error| error.to_string())?;
    write.map_err(|error| error.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err("Configuration syntax validation failed; no appearance settings were changed".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_blocks_preserve_other_configuration_and_are_idempotent() {
        for (lua, original) in [
            (false, "# Personal\r\nset -gx OTHER keep\r\n"),
            (true, "-- Personal\nrequire(\"custom.env\")\n"),
        ] {
            let dark = edit(original, lua, &[MATERIAL, UNIVERSAL], SystemThemeMode::Dark).unwrap();
            assert!(dark.starts_with(original));
            let light = edit(&dark, lua, &[MATERIAL, UNIVERSAL], SystemThemeMode::Light).unwrap();
            assert!(light.starts_with(original));
            assert!(!light.contains("Dark"));
            assert_eq!(
                edit(&light, lua, &[MATERIAL, UNIVERSAL], SystemThemeMode::Light).unwrap(),
                light
            );
            assert!(
                edit(
                    &(dark.clone() + &dark),
                    lua,
                    &[MATERIAL],
                    SystemThemeMode::Light
                )
                .is_err()
            );
            assert!(
                edit(
                    &format!("{}\n", markers(lua).0),
                    lua,
                    &[MATERIAL],
                    SystemThemeMode::Light
                )
                .is_err()
            );
            let change = tempfile::tempdir().unwrap();
            let path = change.path().join("config");
            std::fs::write(&path, original).unwrap();
            let file = FileChange::prepare_text(&path, |content| {
                edit(content, lua, &[MATERIAL], SystemThemeMode::Dark)
            })
            .unwrap();
            file.apply().unwrap();
            file.rollback().unwrap();
            assert_eq!(std::fs::read_to_string(path).unwrap(), original);
        }
    }

    #[test]
    fn absent_styles_and_shells_never_create_configuration() {
        let env = Environment {
            variables: vec![],
            fish: None,
            hypr: None,
        };
        let (files, targets) = env.prepare(SystemThemeMode::Dark).unwrap();
        assert!(files.is_empty());
        assert!(
            targets
                .iter()
                .all(|target| target.status == ThemeTargetStatus::Unavailable)
        );
    }

    #[test]
    fn installed_syntax_validators_reject_broken_configuration_without_execution() {
        for (lua, command, flag, original, broken) in [
            (
                false,
                "fish",
                "--version",
                "set -gx OTHER keep\n",
                "if true\n",
            ),
            (
                true,
                "luac",
                "-v",
                "require(\"never-execute-this\")\n",
                "function (\n",
            ),
        ] {
            if command_exists(command, flag) {
                assert!(
                    validate(
                        &edit(original, lua, &[MATERIAL], SystemThemeMode::Dark).unwrap(),
                        lua
                    )
                    .is_ok()
                );
                assert!(
                    validate(
                        &edit(broken, lua, &[MATERIAL], SystemThemeMode::Dark).unwrap(),
                        lua
                    )
                    .is_err()
                );
            }
        }
    }
}
