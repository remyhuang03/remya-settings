use crate::{
    held_packages, installed_packages, nvidia_loaded, process,
    protocol::{Operation, valid_job, valid_package, valid_relative_archive, valid_target},
};
use std::{
    ffi::{CString, OsStr},
    fs::{self, File, OpenOptions},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            ffi::OsStrExt,
            fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
        },
    },
    path::{Component, Path},
    process::Command,
};

fn open_child(parent: &File, name: &OsStr, directory: bool) -> Result<File, String> {
    let name = CString::new(name.as_bytes()).map_err(|_| "Invalid archive path")?;
    let flags = libc::O_RDONLY
        | libc::O_CLOEXEC
        | libc::O_NOFOLLOW
        | libc::O_NONBLOCK
        | if directory { libc::O_DIRECTORY } else { 0 };
    let fd = unsafe { libc::openat(parent.as_raw_fd(), name.as_ptr(), flags) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    Ok(unsafe { File::from_raw_fd(fd) })
}

pub(crate) fn job_directory(job: &str, uid: u32) -> Result<File, String> {
    if !valid_job(job) {
        return Err("Invalid update job identity".into());
    }
    let base = process::job_base(uid);
    let root = base.join(job);
    for directory in [&base, &root] {
        let metadata = fs::symlink_metadata(directory).map_err(|e| e.to_string())?;
        if !metadata.is_dir()
            || metadata.uid() != uid
            || metadata.mode() & 0o077 != 0
            || directory.canonicalize().map_err(|e| e.to_string())? != *directory
        {
            return Err("Update directory is not private and owned by its user".into());
        }
    }
    let base_directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW)
        .open(&base)
        .map_err(|e| e.to_string())?;
    let directory = open_child(&base_directory, OsStr::new(job), true)?;
    for file in [&base_directory, &directory] {
        let metadata = file.metadata().map_err(|e| e.to_string())?;
        if metadata.uid() != uid || metadata.mode() & 0o077 != 0 {
            return Err("Update directory changed while authorizing the job".into());
        }
    }
    Ok(directory)
}

pub struct Authorization {
    job: String,
    directory: File,
    uid: u32,
    held: Vec<String>,
}
impl Authorization {
    pub fn begin(job: &str, all: bool) -> Result<Self, String> {
        let uid = std::env::var("PKEXEC_UID")
            .ok()
            .and_then(|s| s.parse::<u32>().ok())
            .filter(|uid| *uid != 0)
            .ok_or("Updater authorization requires the originating ordinary user")?;
        if !valid_job(job) {
            return Err("Invalid update job identity".into());
        }
        let directory = job_directory(job, uid)?;
        let installed = if nvidia_loaded() && !all {
            installed_packages()?
        } else {
            vec![]
        };
        Ok(Self {
            job: job.into(),
            directory,
            uid,
            held: held_packages(all, nvidia_loaded(), &installed),
        })
    }
    pub fn job(&self) -> &str {
        &self.job
    }
    pub fn held(&self) -> &[String] {
        &self.held
    }
    fn stage_archive(&self, relative: &str, target: &Path) -> Result<(), String> {
        if !valid_relative_archive(relative) {
            return Err("Invalid package archive path".into());
        }
        let mut directory = self.directory.try_clone().map_err(|e| e.to_string())?;
        let components = Path::new(relative).components().collect::<Vec<_>>();
        for component in &components[..components.len() - 1] {
            let Component::Normal(name) = component else {
                return Err("Invalid archive directory".into());
            };
            directory = open_child(&directory, name, true)?;
        }
        let Component::Normal(name) = components.last().unwrap() else {
            return Err("Invalid archive file".into());
        };
        let mut source = open_child(&directory, name, false)?;
        let metadata = source.metadata().map_err(|e| e.to_string())?;
        if !metadata.is_file() || metadata.uid() != self.uid {
            return Err("Archive is not a regular file built by this job".into());
        }
        let mut destination = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(target)
            .map_err(|e| e.to_string())?;
        let count = std::io::copy(
            &mut std::io::Read::take(&mut source, metadata.len()),
            &mut destination,
        )
        .map_err(|e| e.to_string())?;
        if count != metadata.len() {
            return Err("Package archive changed while staging".into());
        }
        Ok(())
    }
    fn arguments(
        &self,
        operation: &Operation,
        staging: Option<&Path>,
    ) -> Result<Vec<String>, String> {
        let mut args = Vec::new();
        match operation {
            Operation::Ping => return Ok(args),
            Operation::Sync {
                refresh,
                upgrade,
                packages,
                dependencies,
                needed,
            } => {
                if !(*refresh || *upgrade || !packages.is_empty())
                    || packages.len() > 256
                    || !packages.iter().all(|p| valid_target(p))
                {
                    return Err("Invalid repository update request".into());
                }
                if packages.iter().any(|p| {
                    self.held
                        .iter()
                        .any(|held| p.rsplit('/').next() == Some(held.as_str()))
                }) {
                    return Err("This package is held for the running session; choose Include held packages to update it".into());
                }
                args.push(format!(
                    "-S{}{}",
                    if *refresh { "y" } else { "" },
                    if *upgrade { "u" } else { "" }
                ));
                if *dependencies {
                    args.push("--asdeps".into());
                }
                if *needed {
                    args.push("--needed".into());
                }
                if !self.held.is_empty() {
                    args.extend(["--ignore".into(), self.held.join(",")]);
                }
                args.extend([
                    "--noconfirm".into(),
                    "--config".into(),
                    "/etc/pacman.conf".into(),
                    "--".into(),
                ]);
                args.extend(packages.iter().cloned());
            }
            Operation::Install {
                archives,
                dependencies,
                needed,
            } => {
                if archives.is_empty() || archives.len() > 256 {
                    return Err("Invalid built-package request".into());
                }
                args.push("-U".into());
                if *dependencies {
                    args.push("--asdeps".into());
                }
                if *needed {
                    args.push("--needed".into());
                }
                args.extend([
                    "--noconfirm".into(),
                    "--config".into(),
                    "/etc/pacman.conf".into(),
                    "--".into(),
                ]);
                for (index, relative) in archives.iter().enumerate() {
                    if !valid_relative_archive(relative) {
                        return Err("Package archive is outside the update contract".into());
                    }
                    let path = staging
                        .ok_or("Package staging directory is missing")?
                        .join(format!("{index}.pkg.tar.zst"));
                    // Validate and install the same root-owned copy; user build files can change at any time.
                    self.stage_archive(relative, &path)?;
                    let mut inspect = Command::new("/usr/bin/pacman");
                    inspect.args(["-Qpq", "--"]).arg(&path);
                    process::fixed_environment(&mut inspect);
                    let output = inspect.output().map_err(|e| e.to_string())?;
                    if !output.status.success() {
                        return Err("Cannot validate built package metadata".into());
                    }
                    let name = String::from_utf8(output.stdout).map_err(|e| e.to_string())?;
                    if !valid_package(name.trim())
                        || self.held.iter().any(|held| held == name.trim())
                    {
                        return Err(
                            "Built package is invalid or held for the running session".into()
                        );
                    }
                    args.push(path.to_string_lossy().into_owned());
                }
            }
            Operation::Reason { packages, explicit } => {
                if packages.is_empty()
                    || packages.len() > 256
                    || !packages.iter().all(|p| valid_package(p))
                {
                    return Err("Invalid package installation reason".into());
                }
                args.extend([
                    "-D".into(),
                    if *explicit {
                        "--asexplicit".into()
                    } else {
                        "--asdeps".into()
                    },
                    "--config".into(),
                    "/etc/pacman.conf".into(),
                    "--".into(),
                ]);
                args.extend(packages.iter().cloned());
            }
        }
        Ok(args)
    }
    pub fn run(&self, operation: &Operation, output: impl FnMut(&str)) -> Result<i32, String> {
        let staging = if matches!(operation, Operation::Install { .. }) {
            Some(
                tempfile::Builder::new()
                    .prefix("remya-settings-packages-")
                    .permissions(fs::Permissions::from_mode(0o700))
                    .tempdir_in("/var/tmp")
                    .map_err(|e| e.to_string())?,
            )
        } else {
            None
        };
        let args = self.arguments(operation, staging.as_ref().map(|dir| dir.path()))?;
        if args.is_empty() {
            return Ok(0);
        }
        let mut command = process::pty_command("/usr/bin/pacman", &args);
        process::fixed_environment(&mut command);
        process::run(command, None, output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn privileged_requests_keep_fixed_paths_and_enforce_session_holds() {
        let directory = tempfile::tempdir().unwrap();
        let auth = Authorization {
            job: "remya-settings-update-abcdef".into(),
            directory: File::open(directory.path()).unwrap(),
            uid: unsafe { libc::geteuid() },
            held: vec!["linux".into()],
        };
        let args = auth
            .arguments(
                &Operation::Sync {
                    refresh: true,
                    upgrade: true,
                    packages: vec![],
                    dependencies: false,
                    needed: false,
                },
                None,
            )
            .unwrap();
        assert!(
            args.windows(2)
                .any(|p| p == ["--config", "/etc/pacman.conf"])
        );
        assert!(args.windows(2).any(|p| p == ["--ignore", "linux"]));
        assert!(
            auth.arguments(
                &Operation::Sync {
                    refresh: false,
                    upgrade: false,
                    packages: vec!["linux".into()],
                    dependencies: false,
                    needed: false
                },
                None
            )
            .is_err()
        );
        assert!(
            auth.arguments(
                &Operation::Install {
                    archives: vec!["../../etc/pacman.conf".into()],
                    dependencies: false,
                    needed: false
                },
                None
            )
            .is_err()
        );
    }
    #[test]
    fn staged_archive_survives_source_replacement_and_refuses_symlink_escapes() {
        let root = tempfile::tempdir().unwrap();
        let staging = tempfile::tempdir().unwrap();
        fs::create_dir(root.path().join("build")).unwrap();
        let source = root.path().join("build/app.pkg.tar.zst");
        fs::write(&source, b"validated bytes").unwrap();
        let auth = Authorization {
            job: "remya-settings-update-abcdef".into(),
            directory: File::open(root.path()).unwrap(),
            uid: unsafe { libc::geteuid() },
            held: vec![],
        };
        let target = staging.path().join("0.pkg.tar.zst");
        auth.stage_archive("build/app.pkg.tar.zst", &target)
            .unwrap();
        fs::remove_file(&source).unwrap();
        fs::write(&source, b"replacement package").unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"validated bytes");
        fs::rename(root.path().join("build"), root.path().join("old-build")).unwrap();
        std::os::unix::fs::symlink(root.path().join("old-build"), root.path().join("build"))
            .unwrap();
        assert!(
            auth.stage_archive(
                "build/app.pkg.tar.zst",
                &staging.path().join("1.pkg.tar.zst")
            )
            .is_err()
        );
        std::os::unix::fs::symlink(&source, root.path().join("escape.pkg.tar.zst")).unwrap();
        assert!(
            auth.stage_archive("escape.pkg.tar.zst", &staging.path().join("2.pkg.tar.zst"))
                .is_err()
        );
    }
    #[test]
    fn archive_fifo_is_rejected_without_waiting_for_a_writer() {
        let root = tempfile::tempdir().unwrap();
        let staging = tempfile::tempdir().unwrap();
        let fifo = root.path().join("app.pkg.tar.zst");
        let name = CString::new(fifo.as_os_str().as_bytes()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
        let auth = Authorization {
            job: "remya-settings-update-abcdef".into(),
            directory: File::open(root.path()).unwrap(),
            uid: unsafe { libc::geteuid() },
            held: vec![],
        };
        let started = std::time::Instant::now();
        assert!(
            auth.stage_archive("app.pkg.tar.zst", &staging.path().join("0.pkg.tar.zst"))
                .is_err()
        );
        assert!(started.elapsed() < std::time::Duration::from_secs(1));
    }
    #[test]
    fn real_package_metadata_is_checked_on_the_staged_file_without_installing() {
        let root = tempfile::tempdir().unwrap();
        let staging = tempfile::tempdir().unwrap();
        fs::write(root.path().join(".PKGINFO"), "pkgname = remya-updater-test\npkgbase = remya-updater-test\npkgver = 1-1\npkgdesc = Read-only test\nbuilddate = 1\npackager = Test\nsize = 0\narch = any\nlicense = MIT\n").unwrap();
        assert!(
            Command::new("/usr/bin/bsdtar")
                .args(["--zstd", "-cf"])
                .arg(root.path().join("app.pkg.tar.zst"))
                .arg("-C")
                .arg(root.path())
                .arg(".PKGINFO")
                .status()
                .unwrap()
                .success()
        );
        let mut auth = Authorization {
            job: "remya-settings-update-abcdef".into(),
            directory: File::open(root.path()).unwrap(),
            uid: unsafe { libc::geteuid() },
            held: vec![],
        };
        let operation = Operation::Install {
            archives: vec!["app.pkg.tar.zst".into()],
            dependencies: false,
            needed: false,
        };
        let arguments = auth.arguments(&operation, Some(staging.path())).unwrap();
        assert_eq!(
            arguments.last().unwrap(),
            &staging.path().join("0.pkg.tar.zst").to_string_lossy()
        );
        assert_eq!(arguments[0], "-U");
        auth.held.push("remya-updater-test".into());
        let held_staging = tempfile::tempdir().unwrap();
        assert!(
            auth.arguments(&operation, Some(held_staging.path()))
                .unwrap_err()
                .contains("held")
        );
    }
}
