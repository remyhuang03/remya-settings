use crate::{Candidate, held_packages, installed_packages, nvidia_loaded, process};
use std::{
    path::{Path, PathBuf},
    process::Command,
};

pub(crate) trait Backend: Send + Sync {
    fn held(&self, all: bool) -> Result<Vec<String>, String>;
    fn aur(&self) -> bool;
    fn check(&self, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String>;
    /// Exit status of the root updater (pkexec uses 126/127 for refused authorization).
    fn upgrade(&self, all: bool, output: &mut dyn FnMut(&str)) -> Result<i32, String>;
    /// `installed`, `missing` or `outdated`.
    fn updater(&self) -> &'static str;
}
pub(crate) struct RealBackend {
    pub updater: PathBuf,
}
const YAY: &str = "/usr/bin/yay";
impl Backend for RealBackend {
    fn held(&self, all: bool) -> Result<Vec<String>, String> {
        let loaded = nvidia_loaded();
        let packages = if loaded && !all {
            installed_packages()?
        } else {
            vec![]
        };
        Ok(held_packages(all, loaded, &packages))
    }
    fn aur(&self) -> bool {
        Path::new(YAY).is_file()
    }
    fn check(&self, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
        let mut candidates = Vec::new();
        let mut sources = vec![("/usr/bin/checkupdates", vec!["--nocolor"], "repository")];
        if self.aur() {
            sources.push((YAY, vec!["-Qua", "--color", "never"], "AUR"));
        } else {
            output("AUR check skipped: yay is not installed.\n");
        }
        for (program, args, source) in sources {
            output(&format!("Checking {source} updates…\n"));
            let mut command = Command::new(program);
            command.args(args).env("LC_ALL", "C.UTF-8");
            let mut captured = String::new();
            let mut overflow = false;
            let code = process::run(command, |text| {
                if captured.len() + text.len() <= 2 * 1024 * 1024 {
                    captured.push_str(text);
                } else {
                    overflow = true;
                }
                output(text);
            })?;
            if overflow {
                return Err(
                    "Update inventory exceeded its output limit; previous results were retained"
                        .into(),
                );
            }
            if !check_succeeded(program, code, &captured) {
                return Err(check_error(source, code, &captured));
            }
            candidates.extend(parse_candidates(&captured, source));
        }
        candidates.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(candidates)
    }
    fn upgrade(&self, all: bool, output: &mut dyn FnMut(&str)) -> Result<i32, String> {
        let mut command = Command::new("/usr/bin/pkexec");
        command.arg(&self.updater).arg("upgrade");
        if all {
            command.arg("--include-held");
        }
        process::run(command, output)
    }
    fn updater(&self) -> &'static str {
        if !self.updater.is_file() {
            return "missing";
        }
        match Command::new(&self.updater).arg("version").output() {
            Ok(out)
                if out.status.success()
                    && String::from_utf8_lossy(&out.stdout).trim()
                        == crate::UPDATER_VERSION.to_string() =>
            {
                "installed"
            }
            _ => "outdated",
        }
    }
}
fn check_error(source: &str, code: i32, captured: &str) -> String {
    let mut terminal = crate::terminal::Log::default();
    terminal.push(captured);
    let mut lines = terminal
        .lines()
        .into_iter()
        .filter(|line| !line.trim().is_empty())
        .rev()
        .take(8)
        .collect::<Vec<_>>();
    lines.reverse();
    let diagnostic = lines.join("\n").chars().take(2000).collect::<String>();
    format!(
        "{source} update check failed (exit {code}): {}",
        if diagnostic.is_empty() {
            "The command returned no diagnostic output."
        } else {
            &diagnostic
        }
    )
}
fn check_succeeded(program: &str, code: i32, output: &str) -> bool {
    code == 0 || (program == "/usr/bin/checkupdates" && code == 2)
        // Yay uses an empty error / exit 1 when its upgrade graph is empty.
        || (program == "/usr/bin/yay" && code == 1 && output.trim().is_empty())
}
fn parse_candidates(text: &str, source: &str) -> Vec<Candidate> {
    text.lines()
        .filter_map(|line| {
            let words = line.split_whitespace().collect::<Vec<_>>();
            (words.len() >= 4 && words[2] == "->" && crate::valid_package(words[0])).then(|| {
                Candidate {
                    name: words[0].into(),
                    installed: words[1].into(),
                    available: words[3].into(),
                    source: source.into(),
                    held: false,
                }
            })
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn update_candidates_ignore_diagnostics_instead_of_inventing_packages() {
        let result = parse_candidates(
            "warning: stale data\nexample 1.0-1 -> 2.0-1 [2 days ago]\nno package updates\n",
            "AUR",
        );
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].name, "example");
        assert_eq!(result[0].source, "AUR");
    }
    #[test]
    fn empty_aur_graph_is_not_an_error_but_real_diagnostics_are_retained() {
        assert!(check_succeeded("/usr/bin/yay", 1, ""));
        assert!(!check_succeeded("/usr/bin/yay", 1, "error: request failed"));
        assert!(!check_succeeded("/usr/bin/checkupdates", 1, ""));
        assert!(check_succeeded("/usr/bin/checkupdates", 2, ""));
    }
    #[test]
    fn failed_check_summary_contains_bounded_real_terminal_diagnostics() {
        let message = check_error(
            "AUR",
            1,
            "\x1b[31merror: Get https://aur.archlinux.org/rpc: connection refused\x1b[0m\n",
        );
        assert!(message.contains("connection refused"));
        assert!(!message.contains('\x1b'));
        assert!(check_error("AUR", 1, &"diagnostic ".repeat(1000)).len() < 2200);
        assert!(check_error("AUR", 1, "").contains("no diagnostic"));
    }
}
