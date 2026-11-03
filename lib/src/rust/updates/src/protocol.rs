use serde::{Deserialize, Serialize};
use std::{
    io::{BufRead, Read, Write},
    path::{Component, Path},
};

pub const FRAME_LIMIT: usize = 8192;
pub const BRIDGE_FD: i32 = 3;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", deny_unknown_fields)]
pub enum Operation {
    Ping,
    Sync {
        refresh: bool,
        upgrade: bool,
        packages: Vec<String>,
        dependencies: bool,
        needed: bool,
    },
    Install {
        archives: Vec<String>,
        dependencies: bool,
        needed: bool,
    },
    Reason {
        packages: Vec<String>,
        explicit: bool,
    },
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BridgeRequest {
    pub job: String,
    pub operation: Operation,
}
#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", deny_unknown_fields)]
pub enum Output {
    Text { text: String },
    Exit { code: i32 },
    Error { message: String },
}
pub fn read_frame(reader: &mut impl BufRead) -> Result<Option<String>, String> {
    let mut bytes = Vec::new();
    let count = reader
        .take((FRAME_LIMIT + 1) as u64)
        .read_until(b'\n', &mut bytes)
        .map_err(|e| e.to_string())?;
    if count == 0 {
        return Ok(None);
    }
    if count > FRAME_LIMIT || bytes.last() != Some(&b'\n') {
        return Err("Invalid or oversized updater frame".into());
    }
    String::from_utf8(bytes)
        .map(Some)
        .map_err(|e| e.to_string())
}
pub fn write_frame(writer: &mut impl Write, value: &impl Serialize) -> Result<(), String> {
    let data = serde_json::to_vec(value).map_err(|e| e.to_string())?;
    if data.len() >= FRAME_LIMIT {
        return Err("Updater request exceeds its frame limit".into());
    }
    writer
        .write_all(&data)
        .and_then(|_| writer.write_all(b"\n"))
        .and_then(|_| writer.flush())
        .map_err(|e| e.to_string())
}
pub fn valid_job(job: &str) -> bool {
    job.strip_prefix("remya-settings-update-")
        .is_some_and(|tail| {
            tail.len() >= 6 && tail.len() <= 32 && tail.bytes().all(|b| b.is_ascii_alphanumeric())
        })
}
pub fn valid_package(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 255
        && !value.starts_with(['-', '.'])
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@_+.-".contains(&b))
}
pub fn valid_target(value: &str) -> bool {
    let parts = value.split('/').collect::<Vec<_>>();
    (parts.len() == 1 || parts.len() == 2) && parts.iter().all(|p| valid_package(p))
}
pub fn valid_relative_archive(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 4096
        && value.ends_with(".pkg.tar.zst")
        && Path::new(value)
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
}

/// Translate only yay's finite pacman update operations, never arbitrary sudo commands.
pub fn parse_sudo(args: &[String], job_root: &Path) -> Result<Operation, String> {
    if args == ["-v"] {
        return Ok(Operation::Ping);
    }
    if args.first().map(String::as_str) != Some("/usr/bin/pacman") {
        return Err("Only pacman update operations are authorized".into());
    }
    let mut operation = None;
    let (mut refresh, mut upgrade, mut dependencies, mut explicit, mut needed) =
        (false, false, false, false, false);
    let mut targets = Vec::new();
    let mut args = args[1..].iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--" => {
                targets.extend(args.cloned());
                break;
            }
            "--config" => {
                if args.next().map(String::as_str) != Some("/etc/pacman.conf") {
                    return Err("The system pacman configuration is fixed".into());
                }
            }
            "--color" => {
                if !matches!(
                    args.next().map(String::as_str),
                    Some("always" | "auto" | "never")
                ) {
                    return Err("Invalid pacman color mode".into());
                }
            }
            "--ignore" => {
                let values = args.next().ok_or("Missing held packages")?;
                if !values.split(',').all(valid_package) {
                    return Err("Invalid held package name".into());
                }
            }
            "--noconfirm" => {}
            "--needed" => needed = true,
            "--asdeps" => dependencies = true,
            "--asexplicit" => explicit = true,
            flag if flag.starts_with('-') && !flag.starts_with("--") => {
                for c in flag[1..].chars() {
                    match c {
                        'S' | 'U' | 'D' => {
                            if operation.replace(c).is_some() {
                                return Err("Ambiguous pacman operation".into());
                            }
                        }
                        'y' => refresh = true,
                        'u' => upgrade = true,
                        _ => return Err(format!("Pacman flag {flag} is not authorized")),
                    }
                }
            }
            _ => return Err(format!("Pacman argument {arg} is not authorized")),
        }
    }
    if targets.len() > 256 || (dependencies && explicit) {
        return Err("Invalid pacman target set".into());
    }
    match operation {
        Some('S')
            if (refresh || upgrade || !targets.is_empty())
                && targets.iter().all(|p| valid_target(p))
                && !explicit =>
        {
            Ok(Operation::Sync {
                refresh,
                upgrade,
                packages: targets,
                dependencies,
                needed,
            })
        }
        Some('U') if !targets.is_empty() && !refresh && !upgrade && !explicit => {
            let archives = targets
                .iter()
                .map(|p| {
                    let path = Path::new(p);
                    let relative = if path.is_absolute() {
                        path.strip_prefix(job_root)
                            .map_err(|_| "Package archive is outside this update job")?
                    } else {
                        path
                    };
                    let value = relative.to_str().ok_or("Invalid package archive path")?;
                    if !valid_relative_archive(value) {
                        return Err("Only this job's .pkg.tar.zst archives can be installed");
                    }
                    Ok(value.to_owned())
                })
                .collect::<Result<Vec<_>, &str>>()?;
            Ok(Operation::Install {
                archives,
                dependencies,
                needed,
            })
        }
        Some('D')
            if !targets.is_empty()
                && !refresh
                && !upgrade
                && !needed
                && (explicit || dependencies)
                && targets.iter().all(|p| valid_package(p)) =>
        {
            Ok(Operation::Reason {
                packages: targets,
                explicit,
            })
        }
        _ => Err("Pacman operation is outside the updater contract".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(args: &[&str]) -> Vec<String> {
        args.iter().map(|s| (*s).into()).collect()
    }
    #[test]
    fn accepts_yay_update_operations_and_confines_package_archives() {
        let root = Path::new("/run/user/1000/remya-settings-update-abcdef");
        assert!(matches!(
            parse_sudo(
                &args(&[
                    "/usr/bin/pacman",
                    "-Syu",
                    "--ignore",
                    "linux,nvidia-utils",
                    "--noconfirm",
                    "--config",
                    "/etc/pacman.conf",
                    "--"
                ]),
                root
            )
            .unwrap(),
            Operation::Sync {
                refresh: true,
                upgrade: true,
                ..
            }
        ));
        assert!(matches!(
            parse_sudo(
                &args(&[
                    "/usr/bin/pacman",
                    "-U",
                    "--asdeps",
                    "--noconfirm",
                    "--config",
                    "/etc/pacman.conf",
                    "--",
                    "/run/user/1000/remya-settings-update-abcdef/build/app/app-1-x86_64.pkg.tar.zst"
                ]),
                root
            )
            .unwrap(),
            Operation::Install {
                dependencies: true,
                ..
            }
        ));
        for bad in [
            args(&["sh", "-c", "id"]),
            args(&["/usr/bin/pacman", "-S", "--root", "/tmp", "--", "linux"]),
            args(&["/usr/bin/pacman", "-U", "--", "/tmp/pkg.pkg.tar.zst"]),
            args(&["/usr/bin/pacman", "-U", "--", "../pkg.pkg.tar.zst"]),
            args(&[
                "/usr/bin/pacman",
                "-S",
                "--config",
                "/tmp/pacman.conf",
                "--",
                "linux",
            ]),
            args(&["/usr/bin/pacman", "-S", "--", "--help"]),
        ] {
            assert!(parse_sudo(&bad, root).is_err(), "{bad:?}");
        }
        assert!(read_frame(&mut &vec![b'x'; FRAME_LIMIT + 1][..]).is_err());
        assert!(!valid_job("../../tmp"));
    }
}
