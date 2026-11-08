use crate::invalid;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    path::Path,
    process::{Command, Stdio},
};

pub trait Process: Send + Sync {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String>;
    fn exists(&self, program: &str) -> bool;
    fn locked(&self) -> bool;
}
pub struct RealProcess;
impl Process for RealProcess {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let out = Command::new(program)
            .args(args)
            .env("LC_ALL", "C")
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("Unavailable:{program}: {e}"))?;
        if out.status.success()
            || (program == "/usr/bin/pacman"
                && args == ["-Qdtq"]
                && out.status.code() == Some(1)
                && out.stdout.is_empty()
                && out.stderr.is_empty())
        {
            Ok(String::from_utf8_lossy(&out.stdout).into())
        } else {
            Err(format!(
                "{program}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ))
        }
    }
    fn exists(&self, program: &str) -> bool {
        Path::new(program).is_file()
    }
    fn locked(&self) -> bool {
        Path::new("/var/lib/pacman/db.lck").exists()
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Package {
    pub name: String,
    pub version: String,
}
#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct InstalledPackage {
    pub name: String,
    pub version: String,
    pub bytes: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageCache {
    pub keep: u8,
    pub uninstalled: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RemovePackages {
    pub packages: Vec<Package>,
}
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with(['-', '.'])
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@._+-".contains(&b))
}
pub fn size(text: &str) -> Option<u64> {
    let mut words = text.split_whitespace();
    let number: f64 = words.next()?.replace(',', "").parse().ok()?;
    let multiplier = match words.next().unwrap_or("B") {
        "B" | "bytes" => 1.,
        "KiB" | "Ki" => 1024.,
        "MiB" | "Mi" => 1024_f64.powi(2),
        "GiB" | "Gi" => 1024_f64.powi(3),
        "TiB" | "Ti" => 1024_f64.powi(4),
        _ => return None,
    };
    (number.is_finite() && number >= 0.).then_some((number * multiplier) as u64)
}
pub fn paccache_saved(text: &str) -> Result<u64, String> {
    if text.contains("no candidate") {
        return Ok(0);
    }
    for line in text.lines() {
        if let Some((_, v)) = line.split_once("disk space saved:") {
            return size(v.trim().trim_end_matches(')'))
                .ok_or_else(|| "Invalid paccache size summary".into());
        }
    }
    Err("paccache did not report disk space saved".into())
}
pub fn installed(text: &str) -> Result<InstalledPackage, String> {
    let field = |key: &str| {
        text.lines().find_map(|line| {
            line.split_once(':')
                .filter(|(k, _)| k.trim() == key)
                .map(|(_, v)| v.trim().to_string())
        })
    };
    Ok(InstalledPackage {
        name: field("Name").ok_or("Missing package name")?,
        version: field("Version").ok_or("Missing package version")?,
        bytes: size(&field("Installed Size").ok_or("Missing installed size")?)
            .ok_or("Invalid installed size")?,
    })
}
pub(crate) fn installed_packages(text: &str) -> Result<Vec<InstalledPackage>, String> {
    text.split("\n\n")
        .filter(|record| !record.trim().is_empty())
        .map(installed)
        .collect()
}
pub fn orphans(process: &dyn Process) -> Result<Vec<InstalledPackage>, String> {
    let output = process.run("/usr/bin/pacman", &["-Qdtq"])?;
    let names = output.lines().filter(|s| !s.is_empty()).collect::<Vec<_>>();
    if names.iter().any(|name| !valid_name(name)) {
        return Err(invalid("Invalid package name from pacman"));
    }
    if names.is_empty() {
        return Ok(Vec::new());
    }
    let mut args = vec!["-Qi", "--"];
    args.extend(names);
    installed_packages(&process.run("/usr/bin/pacman", &args)?)
}

pub fn cache(process: &dyn Process) -> Result<Value, String> {
    if !process.exists("/usr/bin/paccache") {
        return Ok(
            json!({"bytes":null,"files":null,"candidates":{},"uninstalled_bytes":null,"missing_tool":"Install pacman-contrib for paccache"}),
        );
    }
    let mut candidates = serde_json::Map::new();
    for keep in [1, 2, 3] {
        candidates.insert(
            keep.to_string(),
            json!(paccache_saved(&process.run(
                "/usr/bin/paccache",
                &["-d", "-v", &format!("-k{keep}")]
            )?)?),
        );
    }
    let uninstalled =
        paccache_saved(&process.run("/usr/bin/paccache", &["-d", "-v", "-u", "-k0"])?)?;
    // Query the configured cache directories instead of assuming /var/cache/pacman/pkg.
    let dirs = process.run("/usr/bin/pacman-conf", &["CacheDir"])?;
    let mut bytes = 0;
    let mut files = 0;
    for dir in dirs.lines() {
        for entry in std::fs::read_dir(dir).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let m = entry.metadata().map_err(|e| e.to_string())?;
            if m.is_file() {
                bytes += m.len();
                files += 1;
            }
        }
    }
    Ok(
        json!({"bytes":bytes,"files":files,"candidates":candidates,"uninstalled_bytes":uninstalled,"missing_tool":null}),
    )
}
pub fn validate_keep(keep: u8) -> Result<(), String> {
    if (1..=3).contains(&keep) {
        Ok(())
    } else {
        Err(invalid("keep must be 1, 2 or 3"))
    }
}
pub fn validate_packages(request: &[Package], current: &[InstalledPackage]) -> Result<(), String> {
    if request.is_empty() || request.len() > 500 {
        return Err(invalid("Select 1 to 500 packages"));
    }
    let mut seen = std::collections::HashSet::new();
    for p in request {
        if !valid_name(&p.name) || !seen.insert(&p.name) {
            return Err(invalid("Invalid or duplicate package name"));
        }
        if !current
            .iter()
            .any(|q| q.name == p.name && q.version == p.version)
        {
            return Err(format!(
                "Conflict:{} is no longer an orphan with the reported version",
                p.name
            ));
        }
    }
    Ok(())
}
pub fn clean_cache(process: &dyn Process, keep: u8, uninstalled: bool) -> Result<Value, String> {
    validate_keep(keep)?;
    if process.locked() {
        return Err("Conflict:Pacman database is locked".into());
    }
    process.run("/usr/bin/paccache", &["-r", "-k", &keep.to_string()])?;
    if uninstalled {
        process.run("/usr/bin/paccache", &["-r", "-u", "-k", "0"])?;
    }
    cache(process)
}
pub fn remove_packages(process: &dyn Process, packages: &[Package]) -> Result<Value, String> {
    if process.locked() {
        return Err("Conflict:Pacman database is locked".into());
    }
    validate_packages(packages, &orphans(process)?)?;
    let mut args = vec!["-R", "--noconfirm", "--"];
    args.extend(packages.iter().map(|p| p.name.as_str()));
    process.run("/usr/bin/pacman", &args)?;
    let remaining = orphans(process)?;
    if packages
        .iter()
        .any(|p| remaining.iter().any(|q| q.name == p.name))
    {
        return Err("Conflict:Package removal readback failed".into());
    }
    Ok(json!({"packages":remaining}))
}
