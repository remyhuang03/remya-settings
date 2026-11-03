pub mod authorization;
pub mod bridge;
mod engine;
mod process;
pub mod protocol;
mod schedule;
mod terminal;

use engine::{Backend, RealBackend};
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
    process::Command,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

pub const WORK_IN_PROGRESS: bool = true;
pub const WIP_REASON: &str = "Work in progress: package updates are incomplete and upgrade execution is unverified. Checks, updates and automatic scheduling are paused.";
pub const CHECK: &str = "updates.check";
pub const UPGRADE: &str = "updates.upgrade";
pub const ALL: &str = "updates.include-held";
pub const RETRY: &str = "updates.retry";
pub const STATUS: &str = "updates.status";
pub const OUTPUT: &str = "updates.output";
pub const AUTOMATIC: &str = "updates.automatic";
pub const TIME: &str = "updates.daily-time";
pub const IDS: [&str; 8] = [CHECK, UPGRADE, ALL, RETRY, STATUS, OUTPUT, AUTOMATIC, TIME];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}
const DEFAULT_HELD: &[&str] = &[
    "linux",
    "linux-headers",
    "linux-firmware",
    "linux-firmware-amd",
    "linux-firmware-amdgpu",
    "linux-firmware-atheros",
    "linux-firmware-broadcom",
    "linux-firmware-cirrus",
    "linux-firmware-intel",
    "linux-firmware-mediatek",
    "linux-firmware-nvidia",
    "linux-firmware-other",
    "linux-firmware-radeon",
    "linux-firmware-realtek",
    "linux-firmware-ti",
    "linux-firmware-whence",
    "mkinitcpio",
    "mkinitcpio-busybox",
];

pub fn nvidia_loaded() -> bool {
    Path::new("/proc/driver/nvidia").is_dir()
        || fs::read_to_string("/proc/modules")
            .is_ok_and(|text| text.lines().any(|line| line.starts_with("nvidia")))
}
pub fn held_packages(all: bool, nvidia: bool, installed: &[String]) -> Vec<String> {
    if all {
        return vec![];
    }
    let mut held = DEFAULT_HELD
        .iter()
        .map(|s| (*s).to_owned())
        .collect::<Vec<_>>();
    if nvidia {
        for name in installed.iter().filter(|s| s.contains("nvidia")) {
            if !held.contains(name) {
                held.push(name.clone());
            }
        }
    }
    held
}
pub fn installed_packages() -> Result<Vec<String>, String> {
    let out = Command::new("/usr/bin/pacman")
        .arg("-Qq")
        .env("LC_ALL", "C.UTF-8")
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("Cannot read installed packages to protect the running NVIDIA driver".into());
    }
    let text = String::from_utf8(out.stdout).map_err(|e| e.to_string())?;
    let packages = text.lines().map(str::to_owned).collect::<Vec<_>>();
    if !packages.iter().all(|p| protocol::valid_package(p)) {
        return Err("Invalid installed package name".into());
    }
    Ok(packages)
}
pub trait Privilege: Send + Sync {
    fn begin(&self, job: &str, all: bool) -> Result<Vec<String>, String>;
    fn run(
        &self,
        job: &str,
        operation: &protocol::Operation,
        output: &mut dyn FnMut(&str),
    ) -> Result<i32, String>;
    fn end(&self, job: &str) -> Result<(), String>;
}
#[derive(Clone, Serialize)]
pub struct Candidate {
    pub name: String,
    pub installed: String,
    pub available: String,
    pub source: String,
    pub held: bool,
}
struct State {
    revision: u64,
    schedule: schedule::Schedule,
    all: bool,
    retry: bool,
    busy: bool,
    phase: &'static str,
    kind: &'static str,
    attempt: u32,
    retry_at: Option<u64>,
    checked_at: Option<u64>,
    held: Vec<String>,
    candidates: Vec<Candidate>,
    log: terminal::Log,
    error: Option<String>,
}
impl State {
    fn new(schedule: schedule::Schedule) -> Self {
        Self {
            revision: 0,
            schedule,
            all: false,
            retry: false,
            busy: false,
            phase: "idle",
            kind: "none",
            attempt: 0,
            retry_at: None,
            checked_at: None,
            held: vec![],
            candidates: vec![],
            log: terminal::Log::default(),
            error: None,
        }
    }
}
struct Inner {
    state: Mutex<State>,
    backend: Arc<dyn Backend>,
    dirty: AtomicBool,
    stop: AtomicBool,
    required: Vec<PathBuf>,
    work_in_progress: bool,
}
#[derive(Clone)]
pub struct Updates(Arc<Inner>);
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn retry_delay(attempt: u32) -> u64 {
    u64::from(attempt).saturating_mul(5).min(60)
}
impl Updates {
    pub fn new(
        bridge: PathBuf,
        configuration: PathBuf,
        write: fn(&Path, &[u8]) -> Result<(), String>,
    ) -> Self {
        let required = [
            "/usr/bin/yay",
            "/usr/bin/pacman",
            "/usr/bin/checkupdates",
            "/usr/bin/script",
            "/usr/bin/makepkg",
            "/usr/bin/fakeroot",
            "/usr/bin/git",
            "/usr/bin/gpg",
        ]
        .into_iter()
        .map(PathBuf::from)
        .chain([bridge.clone()])
        .collect();
        Self::with_backend(
            Arc::new(RealBackend { bridge }),
            required,
            schedule::Schedule::load(configuration, write),
            WORK_IN_PROGRESS,
        )
    }
    fn with_backend(
        backend: Arc<dyn Backend>,
        required: Vec<PathBuf>,
        schedule: schedule::Schedule,
        work_in_progress: bool,
    ) -> Self {
        Self(Arc::new(Inner {
            state: Mutex::new(State::new(schedule)),
            backend,
            dirty: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            required,
            work_in_progress,
        }))
    }
    fn missing(&self) -> Vec<String> {
        self.0
            .required
            .iter()
            .filter(|p| !p.is_file())
            .map(|p| p.display().to_string())
            .collect()
    }
    pub fn state(&self) -> Value {
        let state = self.0.state.lock().unwrap();
        let missing = self.missing();
        json!({"api_version":1,"revision":state.revision,"schedule":state.schedule.state(),"available":!self.0.work_in_progress && missing.is_empty(),"work_in_progress":self.0.work_in_progress,"reason":if self.0.work_in_progress {Some(WIP_REASON)} else {None},"missing":missing,"all":state.all,"retry":state.retry,"busy":state.busy,"phase":state.phase,"kind":state.kind,"attempt":state.attempt,"retry_at":state.retry_at,"checked_at":state.checked_at,"held":state.held,"packages":state.candidates,"output":state.log.lines(),"error":state.error})
    }
    pub fn busy(&self) -> bool {
        self.0.state.lock().unwrap().busy
    }
    pub fn take_dirty(&self) -> bool {
        self.0.dirty.swap(false, Ordering::Relaxed)
    }
    fn change(&self, update: impl FnOnce(&mut State)) {
        let mut state = self.0.state.lock().unwrap();
        update(&mut state);
        state.revision = state.revision.saturating_add(1);
        self.0.dirty.store(true, Ordering::Relaxed);
    }
    fn output(&self, text: &str) {
        self.change(|state| state.log.push(text));
    }
    fn finish(&self, result: Result<(), String>) {
        if let Err(error) = &result {
            self.output(&format!("{error}\n"));
        }
        self.change(|state| {
            state.busy = false;
            state.retry_at = None;
            state.phase = if result.is_ok() {
                "completed"
            } else {
                "failed"
            };
            if state.kind == "scheduled" {
                state
                    .schedule
                    .finished(result.as_ref().err().map(String::as_str));
            }
            state.error = result.err();
        });
    }
    fn start(&self, kind: &'static str) -> Result<(), String> {
        if self.0.work_in_progress {
            return Err(format!("Unavailable:{WIP_REASON}"));
        }
        let missing = self.missing();
        if !missing.is_empty() {
            return Err(format!(
                "Unavailable:Required update tools are missing: {}",
                missing.join(", ")
            ));
        }
        let mut state = self.0.state.lock().unwrap();
        if state.busy {
            return Err("Busy:An update operation is already running".into());
        }
        state.revision = state.revision.saturating_add(1);
        state.busy = true;
        state.kind = kind;
        state.phase = if kind == "check" || kind == "scheduled" {
            "checking"
        } else {
            "upgrading"
        };
        state.attempt = 0;
        state.retry_at = None;
        state.error = None;
        state.log = terminal::Log::default();
        self.0.stop.store(false, Ordering::Relaxed);
        self.0.dirty.store(true, Ordering::Relaxed);
        Ok(())
    }
    pub fn set(
        &self,
        id: &str,
        value: &str,
        privilege: Option<Arc<dyn Privilege>>,
    ) -> Result<Value, String> {
        if self.0.work_in_progress {
            return Err(format!("Unavailable:{WIP_REASON}"));
        }
        match id {
            AUTOMATIC | TIME => {
                let mut state = self.0.state.lock().unwrap();
                state.schedule.set(id, value)?;
                state.revision = state.revision.saturating_add(1);
                self.0.dirty.store(true, Ordering::Relaxed);
            }
            ALL | RETRY => {
                let value = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err("InvalidArgument:Use true or false".into()),
                };
                if id == ALL && self.busy() {
                    return Err("Busy:Wait for the current operation before changing its held-package policy".into());
                }
                self.change(|state| {
                    if id == ALL {
                        state.all = value;
                        for candidate in &mut state.candidates {
                            candidate.held = !value && state.held.contains(&candidate.name);
                        }
                    } else {
                        state.retry = value;
                    }
                });
            }
            CHECK => {
                if value != "check" {
                    return Err("InvalidArgument:Use check".into());
                }
                self.start("check")?;
                let updates = self.clone();
                thread::spawn(move || {
                    let result = updates.check();
                    updates.finish(result);
                });
            }
            UPGRADE => {
                if value != "upgrade" {
                    return Err("InvalidArgument:Use upgrade".into());
                }
                let privilege = privilege
                    .ok_or("Unauthorized:Open Settings and authorize system changes first")?;
                self.start("upgrade")?;
                let updates = self.clone();
                thread::spawn(move || {
                    let all = updates.0.state.lock().unwrap().all;
                    let result = updates.upgrade(privilege, all);
                    updates.finish(result);
                });
            }
            STATUS | OUTPUT => {
                return Err("ReadOnly:Update status and output cannot be changed".into());
            }
            _ => return Err("InvalidArgument:Unknown update setting".into()),
        }
        Ok(self.state())
    }
    pub fn tick(&self, privilege: Option<Arc<dyn Privilege>>) {
        if self.0.work_in_progress {
            return;
        }
        if let Some(local) = schedule::LocalTime::now() {
            self.tick_at(&local, privilege);
        }
    }
    fn tick_at(&self, local: &schedule::LocalTime, privilege: Option<Arc<dyn Privilege>>) {
        if self.0.work_in_progress {
            return;
        }
        let due = {
            let mut state = self.0.state.lock().unwrap();
            let busy = state.busy;
            let due = state.schedule.due(local, busy, privilege.is_some());
            if !matches!(due, schedule::Due::None) {
                state.revision = state.revision.saturating_add(1);
                self.0.dirty.store(true, Ordering::Relaxed);
            }
            due
        };
        if !matches!(due, schedule::Due::Run) {
            return;
        }
        if let Err(error) = self.start("scheduled") {
            self.change(|state| state.schedule.finished(Some(&error)));
            return;
        }
        let updates = self.clone();
        thread::spawn(move || {
            let result = (|| {
                updates.output("Daily automatic update: checking for eligible packages.\n");
                updates.check()?;
                let eligible = {
                    let state = updates.0.state.lock().unwrap();
                    state
                        .candidates
                        .iter()
                        .any(|candidate| !state.held.contains(&candidate.name))
                };
                if !eligible {
                    updates.output("No eligible updates; no package transaction was started.\n");
                    return Ok(());
                }
                updates.upgrade(
                    privilege.ok_or("Scheduled update authorization is no longer available")?,
                    false,
                )
            })();
            updates.finish(result);
        });
    }
    fn scratch(&self) -> Result<tempfile::TempDir, String> {
        let uid = unsafe { libc::geteuid() };
        if uid == 0 {
            return Err("Updates and AUR builds must run as an ordinary user".into());
        }
        let base = process::job_base(uid);
        match fs::DirBuilder::new().mode(0o700).create(&base) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(e) => return Err(e.to_string()),
        }
        let metadata = fs::symlink_metadata(&base).map_err(|e| e.to_string())?;
        if !metadata.is_dir() || metadata.uid() != uid || metadata.mode() & 0o077 != 0 {
            return Err("Update working directory is not private and owned by this user".into());
        }
        tempfile::Builder::new()
            .prefix("remya-settings-update-")
            .permissions(fs::Permissions::from_mode(0o700))
            .tempdir_in(base)
            .map_err(|e| e.to_string())
    }
    fn check(&self) -> Result<(), String> {
        let root = self.scratch()?;
        let all = self.0.state.lock().unwrap().all;
        let held = self.0.backend.held(false)?;
        self.change(|state| state.held = held.clone());
        let mut candidates = self
            .0
            .backend
            .check(root.path(), &mut |text| self.output(text))?;
        for candidate in &mut candidates {
            candidate.held = !all && held.contains(&candidate.name);
        }
        self.change(|state| {
            state.candidates = candidates;
            state.checked_at = Some(now());
        });
        self.output("Update check completed.\n");
        Ok(())
    }
    fn upgrade(&self, privilege: Arc<dyn Privilege>, all: bool) -> Result<(), String> {
        let root = self.scratch()?;
        let job = root
            .path()
            .file_name()
            .and_then(|p| p.to_str())
            .ok_or("Invalid update working directory")?;
        let held = privilege.begin(job, all)?;
        self.change(|state| state.held = held.clone());
        self.output(&if held.is_empty() {
            "Upgrading everything; no packages are held.\n".into()
        } else {
            format!(
                "Holding {} packages for this session: {}\n",
                held.len(),
                held.join(", ")
            )
        });
        let result = (|| {
            loop {
                self.change(|state| {
                    state.attempt += 1;
                    state.phase = "upgrading";
                    state.retry_at = None;
                    state.error = None;
                });
                let attempt = self.0.state.lock().unwrap().attempt;
                self.output(&format!("Upgrade attempt {attempt}.\n"));
                let result =
                    self.0
                        .backend
                        .upgrade(root.path(), &held, privilege.clone(), &mut |text| {
                            self.output(text)
                        });
                if matches!(result, Ok(0)) {
                    self.change(|state| {
                        state.checked_at = None;
                        state.candidates.clear();
                    });
                    self.output(
                        "Upgrade completed. Check again to refresh the package inventory.\n",
                    );
                    return Ok(());
                }
                let message = match result {
                    Ok(code) => format!("Upgrade failed (exit {code})"),
                    Err(error) => error,
                };
                self.output(&format!("{message}\n"));
                if !self.0.state.lock().unwrap().retry || self.0.stop.load(Ordering::Relaxed) {
                    return Err(message);
                }
                let delay = retry_delay(attempt);
                self.change(|state| {
                    state.phase = "retrying";
                    state.retry_at = Some(now() + delay);
                    state.error = Some(message.clone());
                });
                self.output(&format!("Retrying in {delay} seconds. Turn off Retry after failure to stop further attempts.\n"));
                for _ in 0..delay * 10 {
                    thread::sleep(Duration::from_millis(100));
                    if !self.0.state.lock().unwrap().retry || self.0.stop.load(Ordering::Relaxed) {
                        return Err(message);
                    }
                }
            }
        })();
        let ended = privilege.end(job);
        result.and(ended)
    }
    pub fn shutdown(&self) {
        self.0.stop.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn holds_match_up_and_all_removes_every_hold() {
        let installed = vec![
            "nvidia-utils".into(),
            "lib32-nvidia-utils".into(),
            "mesa".into(),
        ];
        let held = held_packages(false, true, &installed);
        assert!(held.contains(&"linux-firmware-amd".into()));
        assert!(held.contains(&"linux-firmware-ti".into()));
        assert!(held.contains(&"nvidia-utils".into()));
        assert!(held.contains(&"lib32-nvidia-utils".into()));
        assert!(!held.contains(&"mesa".into()));
        assert!(!held_packages(false, false, &installed).contains(&"nvidia-utils".into()));
        assert!(held_packages(true, true, &installed).is_empty());
        assert_eq!(retry_delay(1), 5);
        assert_eq!(retry_delay(12), 60);
        assert_eq!(retry_delay(100), 60);
    }
    struct ReadOnly;
    impl Backend for ReadOnly {
        fn held(&self, _: bool) -> Result<Vec<String>, String> {
            Ok(vec!["linux".into()])
        }
        fn check(&self, _: &Path, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
            output("checked\n");
            Ok(vec![])
        }
        fn upgrade(
            &self,
            _: &Path,
            _: &[String],
            _: Arc<dyn Privilege>,
            _: &mut dyn FnMut(&str),
        ) -> Result<i32, String> {
            panic!("read-only calls must never upgrade")
        }
    }
    #[test]
    fn inspection_and_view_options_never_start_an_upgrade() {
        let updates = Updates::with_backend(
            Arc::new(ReadOnly),
            vec![],
            schedule::Schedule::memory(),
            false,
        );
        assert_eq!(updates.state()["phase"], "idle");
        updates.set(ALL, "true", None).unwrap();
        updates.set(RETRY, "true", None).unwrap();
        assert!(
            updates
                .set(UPGRADE, "upgrade", None)
                .unwrap_err()
                .starts_with("Unauthorized:")
        );
        assert!(!updates.busy());
        assert!(updates.set(OUTPUT, "clear", None).is_err());
    }
    struct Gate {
        entered: std::sync::mpsc::Sender<()>,
        release: Mutex<std::sync::mpsc::Receiver<()>>,
        upgrades: std::sync::atomic::AtomicU32,
    }
    impl Backend for Gate {
        fn held(&self, _: bool) -> Result<Vec<String>, String> {
            Ok(vec!["linux".into()])
        }
        fn check(&self, _: &Path, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
            self.entered.send(()).unwrap();
            self.release.lock().unwrap().recv().unwrap();
            output("repository checked\n");
            Ok(vec![Candidate {
                name: "linux".into(),
                installed: "1".into(),
                available: "2".into(),
                source: "repository".into(),
                held: false,
            }])
        }
        fn upgrade(
            &self,
            _: &Path,
            _: &[String],
            _: Arc<dyn Privilege>,
            output: &mut dyn FnMut(&str),
        ) -> Result<i32, String> {
            self.upgrades.fetch_add(1, Ordering::Relaxed);
            output("fake package transaction failed\n");
            Ok(1)
        }
    }
    struct FakePrivilege;
    impl Privilege for FakePrivilege {
        fn begin(&self, _: &str, _: bool) -> Result<Vec<String>, String> {
            Ok(vec!["linux".into()])
        }
        fn run(
            &self,
            _: &str,
            _: &protocol::Operation,
            _: &mut dyn FnMut(&str),
        ) -> Result<i32, String> {
            panic!("fake backend must not run pacman")
        }
        fn end(&self, _: &str) -> Result<(), String> {
            Ok(())
        }
    }
    fn await_phase(updates: &Updates, phase: &str) {
        for _ in 0..100 {
            if updates.state()["phase"] == phase {
                return;
            }
            thread::sleep(Duration::from_millis(10));
        }
        panic!("expected {phase}, got {}", updates.state());
    }
    #[test]
    fn asynchronous_check_stays_responsive_and_retry_can_stop_without_restarting_transaction() {
        let (entered, receive) = std::sync::mpsc::channel();
        let (release, wait) = std::sync::mpsc::channel();
        let backend = Arc::new(Gate {
            entered,
            release: Mutex::new(wait),
            upgrades: 0.into(),
        });
        let updates =
            Updates::with_backend(backend.clone(), vec![], schedule::Schedule::memory(), false);
        updates.set(CHECK, "check", None).unwrap();
        receive.recv_timeout(Duration::from_secs(2)).unwrap();
        assert!(updates.busy());
        assert_eq!(updates.state()["phase"], "checking");
        assert!(
            updates
                .set(CHECK, "check", None)
                .unwrap_err()
                .starts_with("Busy:")
        );
        assert!(updates.set(ALL, "true", None).is_err());
        assert_eq!(backend.upgrades.load(Ordering::Relaxed), 0);
        release.send(()).unwrap();
        await_phase(&updates, "completed");
        assert_eq!(updates.state()["packages"][0]["held"], true);
        updates.set(RETRY, "true", None).unwrap();
        updates
            .set(UPGRADE, "upgrade", Some(Arc::new(FakePrivilege)))
            .unwrap();
        await_phase(&updates, "retrying");
        updates.set(RETRY, "false", None).unwrap();
        await_phase(&updates, "failed");
        assert_eq!(backend.upgrades.load(Ordering::Relaxed), 1);
        assert_eq!(updates.state()["packages"][0]["name"], "linux");
        assert!(
            updates.state()["output"]
                .as_array()
                .unwrap()
                .iter()
                .any(|s| s.as_str().unwrap().contains("fake package transaction"))
        );
    }
    struct AutomaticBackend {
        checks: std::sync::atomic::AtomicU32,
        upgrades: std::sync::atomic::AtomicU32,
        eligible: bool,
    }
    impl Backend for AutomaticBackend {
        fn held(&self, _: bool) -> Result<Vec<String>, String> {
            Ok(vec!["linux".into()])
        }
        fn check(&self, _: &Path, _: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
            self.checks.fetch_add(1, Ordering::Relaxed);
            Ok(vec![Candidate {
                name: if self.eligible { "mesa" } else { "linux" }.into(),
                installed: "1".into(),
                available: "2".into(),
                source: "repository".into(),
                held: false,
            }])
        }
        fn upgrade(
            &self,
            _: &Path,
            held: &[String],
            _: Arc<dyn Privilege>,
            _: &mut dyn FnMut(&str),
        ) -> Result<i32, String> {
            assert_eq!(held, ["linux"]);
            self.upgrades.fetch_add(1, Ordering::Relaxed);
            Ok(0)
        }
    }
    struct AutomaticPrivilege(Mutex<Vec<bool>>);
    impl Privilege for AutomaticPrivilege {
        fn begin(&self, _: &str, all: bool) -> Result<Vec<String>, String> {
            self.0.lock().unwrap().push(all);
            Ok(vec!["linux".into()])
        }
        fn run(
            &self,
            _: &str,
            _: &protocol::Operation,
            _: &mut dyn FnMut(&str),
        ) -> Result<i32, String> {
            unreachable!("fake updater never invokes pacman")
        }
        fn end(&self, _: &str) -> Result<(), String> {
            Ok(())
        }
    }
    #[test]
    fn scheduled_jobs_check_first_keep_holds_and_never_prompt_or_replay_without_authorization() {
        for eligible in [false, true] {
            let backend = Arc::new(AutomaticBackend {
                checks: 0.into(),
                upgrades: 0.into(),
                eligible,
            });
            let updates =
                Updates::with_backend(backend.clone(), vec![], schedule::Schedule::memory(), false);
            let privilege = Arc::new(AutomaticPrivilege(Mutex::new(vec![])));
            let local = schedule::LocalTime {
                day: "2026-11-03".into(),
                minute: 180,
            };
            updates.tick_at(&local, Some(privilege.clone()));
            assert_eq!(backend.checks.load(Ordering::Relaxed), 0);
            updates.set(ALL, "true", None).unwrap();
            updates.set(AUTOMATIC, "true", None).unwrap();
            updates.tick_at(&local, None);
            updates.tick_at(&local, Some(privilege.clone()));
            assert_eq!(backend.checks.load(Ordering::Relaxed), 0);
            assert!(
                updates.state()["schedule"]["notice"]
                    .as_str()
                    .unwrap()
                    .contains("not authorized")
            );
            let tomorrow = schedule::LocalTime {
                day: "2026-11-04".into(),
                minute: 180,
            };
            updates.tick_at(&tomorrow, Some(privilege.clone()));
            await_phase(&updates, "completed");
            updates.tick_at(&tomorrow, Some(privilege.clone()));
            assert_eq!(backend.checks.load(Ordering::Relaxed), 1);
            assert_eq!(
                backend.upgrades.load(Ordering::Relaxed),
                u32::from(eligible)
            );
            assert_eq!(
                *privilege.0.lock().unwrap(),
                if eligible { vec![false] } else { vec![] }
            );
        }
    }
    #[test]
    fn production_job_is_private_and_passes_the_privileged_directory_boundary() {
        let updates = Updates::with_backend(
            Arc::new(ReadOnly),
            vec![],
            schedule::Schedule::memory(),
            false,
        );
        let scratch = updates.scratch().unwrap();
        let uid = unsafe { libc::geteuid() };
        let metadata = scratch.path().metadata().unwrap();
        assert_eq!(metadata.uid(), uid);
        assert_eq!(metadata.mode() & 0o777, 0o700);
        let job = scratch.path().file_name().unwrap().to_str().unwrap();
        assert!(authorization::job_directory(job, uid).is_ok());
        fs::set_permissions(scratch.path(), fs::Permissions::from_mode(0o755)).unwrap();
        assert!(authorization::job_directory(job, uid).is_err());
    }
    #[test]
    fn production_wip_rejects_every_write_and_never_runs_a_saved_schedule() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("updates.json");
        let saved =
            br#"{"version":1,"enabled":true,"time":"03:00","last_run_day":null,"notice":null}"#;
        fs::write(&path, saved).unwrap();
        let schedule = schedule::Schedule::load(path.clone(), |_, _| {
            panic!("WIP must not write schedule data")
        });
        let updates = Updates::with_backend(Arc::new(ReadOnly), vec![], schedule, true);
        assert_eq!(
            Updates::new("/missing-bridge".into(), path.clone(), |_, _| Ok(())).state()["work_in_progress"],
            true
        );
        assert_eq!(updates.state()["available"], false);
        assert_eq!(updates.state()["reason"], WIP_REASON);
        assert_eq!(updates.state()["schedule"]["enabled"], true);
        for id in IDS {
            assert!(
                updates
                    .set(id, "true", Some(Arc::new(FakePrivilege)))
                    .unwrap_err()
                    .starts_with("Unavailable:")
            );
        }
        updates.tick_at(
            &schedule::LocalTime {
                day: "2026-11-03".into(),
                minute: 180,
            },
            Some(Arc::new(FakePrivilege)),
        );
        assert!(!updates.busy());
        assert_eq!(updates.state()["phase"], "idle");
        assert!(updates.state()["output"].as_array().unwrap().is_empty());
        assert_eq!(fs::read(path).unwrap(), saved);
    }
}
