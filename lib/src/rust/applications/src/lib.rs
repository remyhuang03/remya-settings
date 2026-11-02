pub mod external_tools;
// Desktop application discovery and package-manager-owned installation information.
use gio::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
    process::Command,
};

pub const SEARCH: &str = "installed.15735a25";
pub const SORT: &str = "installed.3bf3689a";
pub const FILTER: &str = "installed.765cf6c3";
pub const DETAILS: &str = "installed.32098ab2";
pub const UNINSTALL: &str = "installed.c3c4a29c";
pub const IDS: [&str; 5] = [SEARCH, SORT, FILTER, DETAILS, UNINSTALL];
#[derive(Clone, Serialize, Deserialize)]
pub struct Application {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub types: BTreeSet<String>,
}
pub fn desktop_applications() -> Vec<Application> {
    let mut apps = gio::AppInfo::all()
        .into_iter()
        .filter(|a| a.should_show())
        .filter_map(|a| {
            Some(Application {
                id: a.id()?.to_string(),
                name: a.display_name().to_string(),
                icon: a.icon().and_then(|i| i.to_string()).map(|s| s.to_string()),
                types: a
                    .supported_types()
                    .into_iter()
                    .map(|s| s.to_string())
                    .collect(),
            })
        })
        .collect::<Vec<_>>();
    apps.sort_by_cached_key(|a| (a.name.to_lowercase(), a.id.clone()));
    apps
}
fn invalid(message: &str) -> String {
    format!("InvalidArgument:{message}")
}
fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 255
        && !name.starts_with(['-', '.'])
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@_+.-".contains(&b))
}
fn run(program: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(std::process::Stdio::null())
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err(format!(
            "{program}: {}{}",
            String::from_utf8_lossy(&out.stderr)
                .chars()
                .take(512)
                .collect::<String>(),
            String::from_utf8_lossy(&out.stdout)
                .chars()
                .take(512)
                .collect::<String>()
        ));
    }
    String::from_utf8(out.stdout).map_err(|e| e.to_string())
}
#[derive(Clone, Serialize)]
struct Native {
    package: String,
    version: String,
    size: Option<u64>,
    installed: Option<i64>,
    desktops: Vec<String>,
}
fn fields(text: &str) -> Result<BTreeMap<&str, Vec<&str>>, String> {
    let mut map = BTreeMap::<&str, Vec<&str>>::new();
    let mut current = None;
    for line in text.lines().filter(|l| !l.is_empty()) {
        if line.starts_with('%') && line.ends_with('%') {
            if map.contains_key(line) {
                return Err("Duplicate ALPM field".into());
            }
            current = Some(line);
            map.insert(line, vec![]);
        } else {
            map.get_mut(current.ok_or("Invalid ALPM field")?)
                .ok_or("Invalid ALPM section")?
                .push(line);
        }
    }
    Ok(map)
}
fn native_at(path: &Path) -> Result<Vec<Native>, String> {
    let mut packages = vec![];
    for entry in
        fs::read_dir(path).map_err(|e| format!("Cannot read native package database: {e}"))?
    {
        let entry = entry.map_err(|e| e.to_string())?;
        if !entry.file_type().map_err(|e| e.to_string())?.is_dir() {
            continue;
        }
        let desc = fs::read_to_string(entry.path().join("desc")).map_err(|e| e.to_string())?;
        let data = fields(&desc)?;
        let one = |key| {
            data.get(key)
                .filter(|v| v.len() == 1)
                .map(|v| v[0])
                .ok_or_else(|| format!("Missing ALPM {key}"))
        };
        let package = one("%NAME%")?;
        if !valid_name(package) {
            return Err("Invalid native package name".into());
        }
        let files = fs::read_to_string(entry.path().join("files")).map_err(|e| e.to_string())?;
        let files = fields(&files)?;
        let desktops = files
            .get("%FILES%")
            .into_iter()
            .flatten()
            .filter_map(|f| {
                f.strip_prefix("usr/share/applications/")
                    .filter(|f| f.ends_with(".desktop"))
                    .map(|f| f.replace('/', "-"))
            })
            .collect::<Vec<_>>();
        if desktops.is_empty() {
            continue;
        }
        let number = |key| -> Result<Option<u64>, String> {
            data.get(key)
                .map(|v| {
                    v.first()
                        .ok_or("Empty ALPM number".to_string())
                        .and_then(|s| s.parse::<u64>().map_err(|e| e.to_string()))
                })
                .transpose()
        };
        packages.push(Native {
            package: package.into(),
            version: one("%VERSION%")?.into(),
            size: number("%SIZE%")?,
            installed: number("%INSTALLDATE%")?.map(|n| n as i64),
            desktops,
        });
    }
    Ok(packages)
}
fn native() -> Result<Vec<Native>, String> {
    let directory = run("/usr/bin/pacman-conf", &["DBPath"])?;
    let directory = Path::new(directory.trim());
    if !directory.is_absolute() {
        return Err("Native database path must be absolute".into());
    }
    native_at(&directory.join("local"))
}
#[derive(Clone, Serialize, Deserialize)]
struct Flatpak {
    application_id: String,
    name: String,
    version: String,
    installation: String,
    #[serde(rename = "ref")]
    reference: String,
    active_commit: String,
}
fn flatpaks(scope: Option<&str>) -> Result<Vec<Flatpak>, String> {
    if !Path::new("/usr/bin/flatpak").exists() {
        return Ok(vec![]);
    }
    let mut args = vec![
        "list",
        "--app",
        "--json",
        "--columns=application,name,version,installation,ref,active",
    ];
    let selection = scope.map(installation).transpose()?;
    if let Some(selection) = &selection {
        args.push(selection);
    }
    let text = run("/usr/bin/flatpak", &args)?;
    if text.trim().is_empty() {
        return Ok(vec![]);
    }
    serde_json::from_str(&text).map_err(|e| format!("Invalid Flatpak inventory: {e}"))
}
fn installation(name: &str) -> Result<String, String> {
    if name == "user" {
        Ok("--user".into())
    } else if name == "system" {
        Ok("--system".into())
    } else if valid_name(name) {
        Ok(format!("--installation={name}"))
    } else {
        Err(invalid("Invalid Flatpak installation"))
    }
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Removal {
    pub id: String,
    pub token: String,
}
#[derive(Clone, Serialize)]
struct Installed {
    id: String,
    name: String,
    icon: Option<String>,
    source: String,
    version: Option<String>,
    size: Option<u64>,
    installed: Option<i64>,
    package: Option<String>,
    location: Option<String>,
    token: String,
    uninstallable: bool,
    reason: String,
    related: Vec<String>,
}
fn inventory() -> Result<(Vec<Installed>, Vec<String>), String> {
    let mut warnings = vec![];
    let packages = match native() {
        Ok(v) => v,
        Err(e) => {
            warnings.push(e);
            vec![]
        }
    };
    let flat = match flatpaks(None) {
        Ok(v) => v,
        Err(e) => {
            warnings.push(e);
            vec![]
        }
    };
    let mut result = vec![];
    let mut seen = BTreeSet::new();
    for app in desktop_applications() {
        let info = gio::DesktopAppInfo::new(&app.id);
        if info
            .as_ref()
            .is_some_and(|i| i.string("X-Flatpak").is_some())
        {
            continue;
        }
        let package = packages.iter().find(|p| p.desktops.contains(&app.id));
        let (source, token, reason) = if let Some(p) = package {
            (
                "pacman",
                p.version.clone(),
                format!(
                    "Removes package {}. Package dependencies remain checked; application data is retained.",
                    p.package
                ),
            )
        } else {
            (
                "manual",
                String::new(),
                "Not owned by pacman or Flatpak; use the application's installer to remove it."
                    .into(),
            )
        };
        let location = info
            .and_then(|i| i.filename())
            .map(|p| p.to_string_lossy().into_owned());
        seen.insert(app.id.clone());
        result.push(Installed {
            id: app.id,
            name: app.name,
            icon: app.icon,
            source: source.into(),
            version: package.map(|p| p.version.clone()),
            size: package.and_then(|p| p.size),
            installed: package.and_then(|p| p.installed),
            package: package.map(|p| p.package.clone()),
            location,
            token,
            uninstallable: package.is_some(),
            reason,
            related: package.map(|p| p.desktops.clone()).unwrap_or_default(),
        });
    }
    // Package-owned launchers remain installed even when a broken user override hides them from GIO.
    for package in &packages {
        for id in &package.desktops {
            if seen.contains(id) {
                continue;
            }
            let path = Path::new("/usr/share/applications").join(id);
            if let Some(app) = gio::DesktopAppInfo::from_filename(&path).filter(|a| a.should_show())
            {
                result.push(Installed {
                    id: id.clone(),
                    name: app.display_name().to_string(),
                    icon: app
                        .icon()
                        .and_then(|i| i.to_string())
                        .map(|s| s.to_string()),
                    source: "pacman".into(),
                    version: Some(package.version.clone()),
                    size: package.size,
                    installed: package.installed,
                    package: Some(package.package.clone()),
                    location: Some(path.to_string_lossy().into()),
                    token: package.version.clone(),
                    uninstallable: true,
                    reason: format!(
                        "Removes package {} and its launchers; retains application data.",
                        package.package
                    ),
                    related: package.desktops.clone(),
                });
                seen.insert(id.clone());
            }
        }
    }
    for app in flat {
        let scope = installation(&app.installation)?;
        let location = run(
            "/usr/bin/flatpak",
            &["info", &scope, "--show-location", &app.reference],
        );
        let size = run(
            "/usr/bin/flatpak",
            &["info", &scope, "--show-size", &app.reference],
        )
        .and_then(|s| s.trim().parse::<u64>().map_err(|e| e.to_string()));
        if let Err(e) = &size {
            warnings.push(e.clone());
        }
        let icon = gio::DesktopAppInfo::new(&format!("{}.desktop", app.application_id))
            .and_then(|a| a.icon())
            .and_then(|i| i.to_string())
            .map(|s| s.to_string())
            .or(Some(app.application_id.clone()));
        result.push(Installed {
            id: format!("flatpak:{}:{}", app.installation, app.reference),
            name: app.name,
            icon,
            source: format!("flatpak-{}", app.installation),
            version: (!app.version.is_empty()).then_some(app.version),
            size: size.ok(),
            installed: None,
            package: Some(app.application_id),
            location: location.ok().map(|s| s.trim().into()),
            token: app.active_commit,
            uninstallable: true,
            reason:
                "Removes this Flatpak application without deleting its data or unused runtimes."
                    .into(),
            related: vec![],
        });
    }
    result.sort_by_cached_key(|a| (a.name.to_lowercase(), a.id.clone()));
    Ok((result, warnings))
}
pub fn read() -> Result<Value, String> {
    let (apps, warnings) = inventory()?;
    Ok(json!({"api_version":1,"applications":apps,"warnings":warnings}))
}
#[derive(Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Sort {
    #[default]
    Name,
    Size,
    Installed,
}
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Query {
    query: String,
    sort: Sort,
    source: Option<String>,
}
pub fn search(payload: &str) -> Result<Value, String> {
    let query: Query = serde_json::from_str(payload).map_err(|e| invalid(&e.to_string()))?;
    if query.query.len() > 255 {
        return Err(invalid("Search is too long"));
    }
    let (mut apps, warnings) = inventory()?;
    let needle = query.query.to_lowercase();
    apps.retain(|a| {
        format!("{} {}", a.name, a.package.as_deref().unwrap_or(""))
            .to_lowercase()
            .contains(&needle)
            && query
                .source
                .as_ref()
                .is_none_or(|source| *source == a.source)
    });
    apps.sort_by(|a, b| {
        let descending = |a: Option<u64>, b: Option<u64>| match (a, b) {
            (Some(a), Some(b)) => b.cmp(&a),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            _ => std::cmp::Ordering::Equal,
        };
        let order = match query.sort {
            Sort::Name => std::cmp::Ordering::Equal,
            Sort::Size => descending(a.size, b.size),
            Sort::Installed => {
                descending(a.installed.map(|n| n as u64), b.installed.map(|n| n as u64))
            }
        };
        order.then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(json!({"api_version":1,"applications":apps,"warnings":warnings}))
}
pub fn details(id: &str) -> Result<Value, String> {
    let (apps, _) = inventory()?;
    apps.into_iter()
        .find(|a| a.id == id)
        .map(|a| json!(a))
        .ok_or_else(|| invalid("Unknown installed application"))
}
pub fn needs_authorization(id: &str) -> bool {
    !id.starts_with("flatpak:user:")
}
pub fn uninstall(removal: &Removal, privileged: bool) -> Result<Value, String> {
    if removal.id.starts_with("flatpak:") {
        let rest = removal.id.strip_prefix("flatpak:").unwrap();
        let (scope, reference) = rest
            .split_once(':')
            .ok_or_else(|| invalid("Invalid Flatpak ID"))?;
        let parts = reference.split('/').collect::<Vec<_>>();
        if parts.len() != 3 || !parts.iter().all(|p| valid_name(p)) {
            return Err(invalid("Invalid Flatpak reference"));
        }
        if (scope != "user") != privileged {
            return Err(invalid("Incorrect uninstall authorization boundary"));
        }
        let current = flatpaks(Some(scope))?
            .into_iter()
            .find(|a| a.installation == scope && a.reference == reference)
            .ok_or_else(|| invalid("Flatpak is no longer installed"))?;
        if current.active_commit != removal.token {
            return Err("Conflict:Application changed; refresh before uninstalling".into());
        }
        let scope = installation(scope)?;
        run(
            "/usr/bin/flatpak",
            &[
                "uninstall",
                &scope,
                "--app",
                "--noninteractive",
                "--assumeyes",
                "--no-related",
                "--",
                reference,
            ],
        )?;
        if flatpaks(Some(&current.installation))?
            .iter()
            .any(|a| a.installation == current.installation && a.reference == reference)
        {
            return Err("Flatpak uninstall readback still lists the application".into());
        }
    } else {
        if !privileged {
            return Err("Authorize system package removal in Settings first".into());
        }
        if !valid_name(&removal.id) || !removal.id.ends_with(".desktop") {
            return Err(invalid("Invalid desktop ID"));
        }
        let package = native()?
            .into_iter()
            .find(|p| p.desktops.contains(&removal.id))
            .ok_or_else(|| invalid("Desktop entry is not owned by a native package"))?;
        if package.version != removal.token {
            return Err("Conflict:Package version changed; refresh before uninstalling".into());
        }
        run(
            "/usr/bin/pacman",
            &["-R", "--noconfirm", "--", &package.package],
        )?;
        if native()?.iter().any(|p| p.package == package.package) {
            return Err("Native uninstall readback still lists the package".into());
        }
    }
    Ok(json!({"removed":removal.id}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_current_alpm_database_and_rejects_ambiguous_metadata() {
        let root = tempfile::tempdir().unwrap();
        let pkg = root.path().join("app-1");
        fs::create_dir(&pkg).unwrap();
        fs::write(
            pkg.join("desc"),
            "%NAME%\nexample\n\n%VERSION%\n1.2-1\n\n%SIZE%\n2048\n\n%INSTALLDATE%\n1735689600\n",
        )
        .unwrap();
        fs::write(pkg.join("files"),"%FILES%\nusr/bin/example\nusr/share/applications/example.desktop\nusr/share/applications/helper.desktop\n").unwrap();
        let packages = native_at(root.path()).unwrap();
        assert_eq!(packages[0].size, Some(2048));
        assert_eq!(packages[0].installed, Some(1735689600));
        assert_eq!(packages[0].desktops.len(), 2);
        fs::write(pkg.join("desc"), "%NAME%\nexample\n%NAME%\nother\n").unwrap();
        assert!(native_at(root.path()).is_err());
        for bad in ["", "--all", "../app", "a/b", "foo;bar"] {
            assert!(!valid_name(bad));
        }
        assert!(
            uninstall(
                &Removal {
                    id: "bad/desktop".into(),
                    token: "1".into()
                },
                true
            )
            .unwrap_err()
            .contains("InvalidArgument")
        );
        assert!(
            uninstall(
                &Removal {
                    id: "flatpak:user:../bad/stable".into(),
                    token: "1".into()
                },
                false
            )
            .is_err()
        );
        assert!(
            uninstall(
                &Removal {
                    id: "example.desktop".into(),
                    token: "1".into()
                },
                false
            )
            .is_err()
        );
    }
}
