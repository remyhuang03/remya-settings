mod engine;
mod process;
mod schedule;
mod terminal;
pub mod updater;

use engine::{Backend, RealBackend};
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

/// Bump whenever the root updater's behavior or arguments change.
pub const UPDATER_VERSION: u32 = 1;
pub const INSTALL_COMMAND: &str = "sudo python tool/install_system_updater.py";
pub const CHECK: &str = "updates.check";
pub const UPGRADE: &str = "updates.upgrade";
pub const ALL: &str = "updates.include-held";
pub const RETRY: &str = "updates.retry";
pub const STATUS: &str = "updates.status";
pub const OUTPUT: &str = "updates.output";
pub const AUTOMATIC: &str = "updates.automatic";
pub const ACTIVE_START: &str = "active-hours.e8868af6";
pub const ACTIVE_END: &str = "active-hours.a0bb9f49";
pub const IDS: [&str; 9] = [
    CHECK,
    UPGRADE,
    ALL,
    RETRY,
    STATUS,
    OUTPUT,
    AUTOMATIC,
    ACTIVE_START,
    ACTIVE_END,
];
pub fn is_setting(id: &str) -> bool {
    IDS.contains(&id)
}
pub fn valid_package(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 255
        && !value.starts_with(['-', '.'])
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@_+.-".contains(&b))
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
    if !packages.iter().all(|p| valid_package(p)) {
        return Err("Invalid installed package name".into());
    }
    Ok(packages)
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
    updater: &'static str,
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
    fn eligible(&self) -> bool {
        self.candidates
            .iter()
            .any(|c| c.source == "repository" && !c.held)
    }
}
struct Inner {
    state: Mutex<State>,
    backend: Arc<dyn Backend>,
    dirty: AtomicBool,
    stop: AtomicBool,
    required: Vec<PathBuf>,
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
fn not_ready(updater: &str) -> String {
    format!(
        "Unavailable:The system updater is {updater}. Run {INSTALL_COMMAND} from the Settings source tree once."
    )
}
impl Updates {
    pub fn new(configuration: PathBuf, write: fn(&Path, &[u8]) -> Result<(), String>) -> Self {
        let required = [
            "/usr/bin/pacman",
            "/usr/bin/checkupdates",
            "/usr/bin/pkexec",
            "/usr/bin/systemd-run",
        ]
        .into_iter()
        .map(PathBuf::from)
        .collect();
        Self::with_backend(
            Arc::new(RealBackend {
                updater: updater::PATH.into(),
            }),
            required,
            schedule::Schedule::load(configuration, write),
        )
    }
    fn with_backend(
        backend: Arc<dyn Backend>,
        required: Vec<PathBuf>,
        schedule: schedule::Schedule,
    ) -> Self {
        Self(Arc::new(Inner {
            state: Mutex::new(State {
                revision: 0,
                schedule,
                updater: backend.updater(),
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
            }),
            backend,
            dirty: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            required,
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
    /// Re-reads the installed root updater, e.g. after the user ran the install command.
    pub fn refresh(&self) {
        let updater = self.0.backend.updater();
        if self.0.state.lock().unwrap().updater != updater {
            self.change(|state| state.updater = updater);
        }
    }
    pub fn state(&self) -> Value {
        let state = self.0.state.lock().unwrap();
        let missing = self.missing();
        let available = missing.is_empty() && state.updater == "installed";
        let reason = if !missing.is_empty() {
            Some(format!(
                "Required tools are missing: {}",
                missing.join(", ")
            ))
        } else if !available {
            Some(format!(
                "The system updater is {}. Run {INSTALL_COMMAND} from the Settings source tree once.",
                state.updater
            ))
        } else {
            None
        };
        json!({"api_version":1,"revision":state.revision,"schedule":state.schedule.state(),"available":available,"reason":reason,"missing":missing,"updater":state.updater,"install_command":INSTALL_COMMAND,"aur":self.0.backend.aur(),"all":state.all,"retry":state.retry,"busy":state.busy,"phase":state.phase,"kind":state.kind,"attempt":state.attempt,"retry_at":state.retry_at,"checked_at":state.checked_at,"held":state.held,"packages":state.candidates,"eligible":state.eligible(),"output":state.log.lines(),"error":state.error})
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
        let missing = self.missing();
        if !missing.is_empty() {
            return Err(format!(
                "Unavailable:Required update tools are missing: {}",
                missing.join(", ")
            ));
        }
        let updater = self.0.backend.updater();
        let mut state = self.0.state.lock().unwrap();
        state.updater = updater;
        if kind != "check" && updater != "installed" {
            return Err(not_ready(updater));
        }
        if state.busy {
            return Err("Busy:An update operation is already running".into());
        }
        state.revision = state.revision.saturating_add(1);
        state.busy = true;
        state.kind = kind;
        state.phase = if kind == "upgrade" {
            "upgrading"
        } else {
            "checking"
        };
        state.attempt = 0;
        state.retry_at = None;
        state.error = None;
        state.log = terminal::Log::default();
        self.0.stop.store(false, Ordering::Relaxed);
        self.0.dirty.store(true, Ordering::Relaxed);
        Ok(())
    }
    pub fn set(&self, id: &str, value: &str) -> Result<Value, String> {
        match id {
            AUTOMATIC | ACTIVE_START | ACTIVE_END => {
                let local = schedule::LocalTime::now().ok_or("Cannot read the local time")?;
                let mut state = self.0.state.lock().unwrap();
                state.schedule.set(id, value, &local)?;
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
                            candidate.held = !value
                                && candidate.source == "repository"
                                && state.held.contains(&candidate.name);
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
                    let all = updates.0.state.lock().unwrap().all;
                    let result = updates.check(all);
                    updates.finish(result);
                });
            }
            UPGRADE => {
                if value != "upgrade" {
                    return Err("InvalidArgument:Use upgrade".into());
                }
                self.start("upgrade")?;
                let updates = self.clone();
                thread::spawn(move || {
                    let all = updates.0.state.lock().unwrap().all;
                    let result = updates.upgrade(all);
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
    pub fn tick(&self) {
        if let Some(local) = schedule::LocalTime::now() {
            self.tick_at(&local);
        }
    }
    fn tick_at(&self, local: &schedule::LocalTime) {
        let due = {
            let mut state = self.0.state.lock().unwrap();
            let busy = state.busy;
            let ready = self.missing().is_empty() && state.updater == "installed";
            let due = state.schedule.due(local, busy, ready);
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
                // Scheduled runs always keep the default holds.
                updates.check(false)?;
                if !updates.0.state.lock().unwrap().eligible() {
                    updates.output("No eligible repository updates; pacman was not started.\n");
                    return Ok(());
                }
                updates.upgrade(false)
            })();
            updates.finish(result);
        });
    }
    fn check(&self, all: bool) -> Result<(), String> {
        let held = self.0.backend.held(false)?;
        self.change(|state| state.held = held.clone());
        let mut candidates = self.0.backend.check(&mut |text| self.output(text))?;
        for candidate in &mut candidates {
            candidate.held =
                !all && candidate.source == "repository" && held.contains(&candidate.name);
        }
        self.change(|state| {
            state.candidates = candidates;
            state.checked_at = Some(now());
        });
        self.output("Update check completed.\n");
        Ok(())
    }
    fn upgrade(&self, all: bool) -> Result<(), String> {
        loop {
            self.change(|state| {
                state.attempt += 1;
                state.phase = "upgrading";
                state.retry_at = None;
                state.error = None;
            });
            let attempt = self.0.state.lock().unwrap().attempt;
            self.output(&format!("Upgrade attempt {attempt}.\n"));
            let message = match self.0.backend.upgrade(all, &mut |text| self.output(text)) {
                Ok(0) => {
                    self.change(|state| {
                        state.checked_at = None;
                        state.candidates.clear();
                    });
                    self.output(
                        "Upgrade completed. Check again to refresh the package inventory.\n",
                    );
                    return Ok(());
                }
                // pkexec: 126 = authorization refused or dismissed, 127 = not authorized.
                Ok(126 | 127) => {
                    return Err(format!(
                        "System update was not authorized. Run {INSTALL_COMMAND} to install the updater and its polkit rule."
                    ));
                }
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
            self.output(&format!(
                "Retrying in {delay} seconds. Turn off Retry after failure to stop further attempts.\n"
            ));
            for _ in 0..delay * 10 {
                thread::sleep(Duration::from_millis(100));
                if !self.0.state.lock().unwrap().retry || self.0.stop.load(Ordering::Relaxed) {
                    return Err(message);
                }
            }
        }
    }
    pub fn shutdown(&self) {
        self.0.stop.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicU32;
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
    fn candidate(name: &str, source: &str) -> Candidate {
        Candidate {
            name: name.into(),
            installed: "1".into(),
            available: "2".into(),
            source: source.into(),
            held: false,
        }
    }
    struct Fake {
        updater: &'static str,
        candidates: Vec<Candidate>,
        codes: Mutex<Vec<i32>>,
        gate: Option<(
            std::sync::mpsc::Sender<()>,
            Mutex<std::sync::mpsc::Receiver<()>>,
        )>,
        checks: AtomicU32,
        upgrades: Mutex<Vec<bool>>,
    }
    impl Fake {
        fn new(candidates: Vec<Candidate>, codes: Vec<i32>) -> Self {
            Self {
                updater: "installed",
                candidates,
                codes: Mutex::new(codes),
                gate: None,
                checks: 0.into(),
                upgrades: Mutex::new(vec![]),
            }
        }
    }
    impl Backend for Fake {
        fn held(&self, _: bool) -> Result<Vec<String>, String> {
            Ok(vec!["linux".into()])
        }
        fn aur(&self) -> bool {
            true
        }
        fn check(&self, output: &mut dyn FnMut(&str)) -> Result<Vec<Candidate>, String> {
            if let Some((entered, release)) = &self.gate {
                entered.send(()).unwrap();
                release.lock().unwrap().recv().unwrap();
            }
            self.checks.fetch_add(1, Ordering::Relaxed);
            output("checked\n");
            Ok(self.candidates.clone())
        }
        fn upgrade(&self, all: bool, output: &mut dyn FnMut(&str)) -> Result<i32, String> {
            self.upgrades.lock().unwrap().push(all);
            output("fake transaction\n");
            let mut codes = self.codes.lock().unwrap();
            Ok(if codes.len() > 1 {
                codes.remove(0)
            } else {
                codes[0]
            })
        }
        fn updater(&self) -> &'static str {
            self.updater
        }
    }
    fn service(backend: Arc<Fake>) -> Updates {
        Updates::with_backend(backend, vec![], schedule::Schedule::memory())
    }
    fn await_phase(updates: &Updates, phase: &str) {
        for _ in 0..200 {
            if updates.state()["phase"] == phase {
                return;
            }
            thread::sleep(Duration::from_millis(10));
        }
        panic!("expected {phase}, got {}", updates.state());
    }
    #[test]
    fn check_is_asynchronous_holds_repository_packages_and_never_counts_aur() {
        let (entered, receive) = std::sync::mpsc::channel();
        let (release, wait) = std::sync::mpsc::channel();
        let mut fake = Fake::new(
            vec![candidate("linux", "repository"), candidate("linux", "AUR")],
            vec![0],
        );
        fake.gate = Some((entered, Mutex::new(wait)));
        let backend = Arc::new(fake);
        let updates = service(backend.clone());
        updates.set(CHECK, "check").unwrap();
        receive.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(updates.state()["phase"], "checking");
        assert!(
            updates
                .set(CHECK, "check")
                .unwrap_err()
                .starts_with("Busy:")
        );
        assert!(updates.set(ALL, "true").is_err());
        release.send(()).unwrap();
        await_phase(&updates, "completed");
        let state = updates.state();
        assert_eq!(state["packages"][0]["held"], true);
        assert_eq!(state["packages"][1]["held"], false);
        assert_eq!(state["eligible"], false);
        updates.set(ALL, "true").unwrap();
        assert_eq!(updates.state()["eligible"], true);
        assert!(
            updates
                .set(OUTPUT, "clear")
                .unwrap_err()
                .starts_with("ReadOnly:")
        );
        assert!(backend.upgrades.lock().unwrap().is_empty());
    }
    #[test]
    fn upgrade_passes_held_choice_retries_failures_and_stops_on_refused_authorization() {
        let backend = Arc::new(Fake::new(vec![], vec![1, 0]));
        let updates = service(backend.clone());
        updates.set(ALL, "true").unwrap();
        updates.set(RETRY, "true").unwrap();
        updates.set(UPGRADE, "upgrade").unwrap();
        await_phase(&updates, "retrying");
        for _ in 0..200 {
            if updates.state()["phase"] == "completed" {
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(updates.state()["phase"], "completed");
        assert_eq!(*backend.upgrades.lock().unwrap(), [true, true]);

        let refused = Arc::new(Fake::new(vec![], vec![126]));
        let updates = service(refused.clone());
        updates.set(RETRY, "true").unwrap();
        updates.set(UPGRADE, "upgrade").unwrap();
        await_phase(&updates, "failed");
        assert!(
            updates.state()["error"]
                .as_str()
                .unwrap()
                .contains("not authorized")
        );
        assert_eq!(refused.upgrades.lock().unwrap().len(), 1);

        let failing = Arc::new(Fake::new(vec![], vec![1]));
        let updates = service(failing.clone());
        updates.set(RETRY, "true").unwrap();
        updates.set(UPGRADE, "upgrade").unwrap();
        await_phase(&updates, "retrying");
        updates.set(RETRY, "false").unwrap();
        await_phase(&updates, "failed");
        assert_eq!(failing.upgrades.lock().unwrap().len(), 1);
    }
    #[test]
    fn missing_or_outdated_updater_blocks_upgrades_but_not_checks() {
        for status in ["missing", "outdated"] {
            let mut fake = Fake::new(vec![], vec![0]);
            fake.updater = status;
            let backend = Arc::new(fake);
            let updates = service(backend.clone());
            let state = updates.state();
            assert_eq!(state["available"], false);
            assert!(state["reason"].as_str().unwrap().contains(INSTALL_COMMAND));
            assert!(
                updates
                    .set(UPGRADE, "upgrade")
                    .unwrap_err()
                    .starts_with("Unavailable:")
            );
            updates.set(CHECK, "check").unwrap();
            await_phase(&updates, "completed");
            assert!(backend.upgrades.lock().unwrap().is_empty());
        }
        let tools = Updates::with_backend(
            Arc::new(Fake::new(vec![], vec![0])),
            vec!["/nonexistent/pacman".into()],
            schedule::Schedule::memory(),
        );
        assert!(
            tools
                .set(CHECK, "check")
                .unwrap_err()
                .starts_with("Unavailable:")
        );
    }
    #[test]
    fn scheduled_runs_check_first_keep_holds_and_run_once_per_day() {
        for eligible in [false, true] {
            let backend = Arc::new(Fake::new(
                vec![
                    candidate(if eligible { "mesa" } else { "linux" }, "repository"),
                    candidate("yay-bin", "AUR"),
                ],
                vec![0],
            ));
            let updates = service(backend.clone());
            updates.set(ALL, "true").unwrap();
            let tonight = schedule::LocalTime {
                day: "2026-11-03".into(),
                yesterday: "2026-11-02".into(),
                minute: 23 * 60 + 30,
            };
            updates.tick_at(&tonight);
            assert_eq!(backend.checks.load(Ordering::Relaxed), 0);
            updates
                .0
                .state
                .lock()
                .unwrap()
                .schedule
                .set(AUTOMATIC, "true", &tonight)
                .unwrap();
            updates.tick_at(&tonight);
            await_phase(&updates, "completed");
            updates.tick_at(&tonight);
            assert_eq!(backend.checks.load(Ordering::Relaxed), 1);
            assert_eq!(
                *backend.upgrades.lock().unwrap(),
                if eligible { vec![false] } else { vec![] }
            );
            assert_eq!(
                updates.state()["schedule"]["notice"],
                "Automatic update completed."
            );
        }
    }
}
