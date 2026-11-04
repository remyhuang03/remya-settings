//! Root side of system updates: one fixed repository upgrade, nothing else.
use crate::{held_packages, installed_packages, nvidia_loaded};
use std::process::Command;

/// Fixed install path; the polkit rule allows exactly this program.
pub const PATH: &str = "/usr/local/libexec/remya-settings-update";

/// Accepts `upgrade` or `upgrade --include-held` from an ordinary user through pkexec.
pub fn parse(args: &[String], euid: u32, pkexec_uid: Option<String>) -> Result<bool, String> {
    let all = match args {
        [a] if a == "upgrade" => false,
        [a, b] if a == "upgrade" && b == "--include-held" => true,
        _ => return Err("Usage: remya-settings-update version | upgrade [--include-held]".into()),
    };
    let caller = pkexec_uid.and_then(|uid| uid.parse::<u32>().ok());
    if euid != 0 || !caller.is_some_and(|uid| uid != 0) {
        return Err(
            "The system updater runs only as root through pkexec from an ordinary user".into(),
        );
    }
    Ok(all)
}

pub fn pacman_args(held: &[String]) -> Vec<String> {
    let mut args = [
        "-Syu",
        "--noconfirm",
        "--color",
        "never",
        "--config",
        "/etc/pacman.conf",
    ]
    .map(String::from)
    .to_vec();
    if !held.is_empty() {
        args.extend(["--ignore".into(), held.join(",")]);
    }
    args
}

/// pacman runs in its own system unit: a logout, a stopped Settings service or a closed
/// output pipe cannot kill a transaction, and the fixed unit name allows one at a time.
pub fn command(all: bool) -> Result<Command, String> {
    let loaded = nvidia_loaded();
    let installed = if loaded && !all {
        installed_packages()?
    } else {
        vec![]
    };
    let held = held_packages(all, loaded, &installed);
    if held.is_empty() {
        println!("Upgrading everything; no packages are held.");
    } else {
        println!("Holding {} packages: {}", held.len(), held.join(", "));
    }
    let mut command = Command::new("/usr/bin/systemd-run");
    command
        .args([
            "--wait",
            "--pipe",
            "--quiet",
            "--collect",
            "--unit=remya-settings-update",
            "--setenv=LC_ALL=C.UTF-8",
            "--",
            "/usr/bin/pacman",
        ])
        .args(pacman_args(&held))
        .env_clear()
        .env("PATH", "/usr/bin")
        .env("LC_ALL", "C.UTF-8");
    Ok(command)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|s| (*s).into()).collect()
    }
    #[test]
    fn only_fixed_upgrades_from_an_ordinary_pkexec_caller_are_accepted() {
        let caller = || Some("1000".to_owned());
        assert_eq!(parse(&args(&["upgrade"]), 0, caller()), Ok(false));
        assert_eq!(
            parse(&args(&["upgrade", "--include-held"]), 0, caller()),
            Ok(true)
        );
        for bad in [
            args(&[]),
            args(&["upgrade", "--ignore"]),
            args(&["--include-held", "upgrade"]),
            args(&["upgrade", "--include-held", "x"]),
            args(&["sh"]),
        ] {
            assert!(parse(&bad, 0, caller()).is_err(), "{bad:?}");
        }
        assert!(parse(&args(&["upgrade"]), 1000, caller()).is_err());
        assert!(parse(&args(&["upgrade"]), 0, None).is_err());
        assert!(parse(&args(&["upgrade"]), 0, Some("0".into())).is_err());
    }
    #[test]
    fn pacman_arguments_are_fixed_and_carry_holds() {
        assert_eq!(
            pacman_args(&[]),
            [
                "-Syu",
                "--noconfirm",
                "--color",
                "never",
                "--config",
                "/etc/pacman.conf"
            ]
        );
        let held = pacman_args(&["linux".into(), "nvidia-utils".into()]);
        assert_eq!(held[held.len() - 2..], ["--ignore", "linux,nvidia-utils"]);
    }
}
