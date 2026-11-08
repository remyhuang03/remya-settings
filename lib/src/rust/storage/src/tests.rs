use super::*;
use std::{
    fs,
    os::unix::fs::{MetadataExt, PermissionsExt, symlink},
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "remya-storage-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn roots(&self) -> scan::Roots {
        scan::Roots {
            home: self.0.clone(),
            cache: self.0.join(".cache"),
            trash: self.0.join(".local/share/Trash"),
            folders: vec![
                ("documents", "Documents", self.0.join("Documents")),
                ("downloads", "Downloads", self.0.join("Downloads")),
            ],
        }
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn file(path: &Path, text: &[u8]) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, text).unwrap();
}
#[test]
fn scan_counts_allocated_blocks_hardlinks_hidden_files_and_categories() {
    let t = Temp::new();
    let roots = t.roots();
    file(&roots.home.join("Documents/a"), &vec![1; 8192]);
    fs::hard_link(
        roots.home.join("Documents/a"),
        roots.home.join("Documents/b"),
    )
    .unwrap();
    file(&roots.cache.join("app/a"), &vec![1; 4096]);
    file(&roots.home.join(".secret"), b"hidden");
    symlink("/", roots.home.join("outside")).unwrap();
    let result = scan::scan(&roots, |_| {});
    let docs = result
        .categories
        .iter()
        .find(|c| c.id == "documents")
        .unwrap();
    let allocated = fs::metadata(roots.home.join("Documents/a"))
        .unwrap()
        .blocks()
        * 512;
    assert_eq!(
        docs.bytes,
        allocated + fs::metadata(roots.home.join("Documents")).unwrap().blocks() * 512
    );
    assert_eq!(result.progress.files, 3);
    assert_eq!(result.cache.len(), 1);
    assert_eq!(result.cache[0].name, "app");
    assert!(result.error.is_none());
    assert!(result.scanned_at.is_some());
}
#[test]
fn large_files_keep_only_the_largest_thirty() {
    let mut scan = scan::Scan::default();
    for n in 0..33 {
        scan.add_large(scan::LargeFile {
            path: PathBuf::from(format!("/home/large-{n:02}")),
            bytes: 100_000_000 + n,
            modified: 0,
        });
    }
    assert_eq!(scan.large.len(), 30);
    assert_eq!(scan.large[0].bytes, 100_000_032);
    assert_eq!(scan.large.last().unwrap().bytes, 100_000_003);
}
#[test]
fn unreadable_directory_is_skipped() {
    let t = Temp::new();
    let dir = t.0.join("denied");
    fs::create_dir(&dir).unwrap();
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o0)).unwrap();
    let result = scan::scan(&t.roots(), |_| {});
    // Root bypasses mode bits; the same walk error path is exercised on missing HOME below.
    if fs::read_dir(&dir).is_err() {
        assert!(result.skipped > 0);
    }
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
    let mut roots = t.roots();
    roots.home = t.0.join("missing");
    let result = scan::scan(&roots, |_| {});
    assert!(result.skipped > 0);
    assert!(result.error.is_some());
}
#[derive(Default)]
struct FakeTrash {
    items: Mutex<Vec<cleanup::TrashEntry>>,
    moved: Mutex<Vec<PathBuf>>,
    lists: AtomicU64,
    purges: Mutex<Vec<Vec<String>>>,
    fail_purge: bool,
    broken: u64,
    fail_list: bool,
}
impl Trash for FakeTrash {
    fn list(&self) -> Result<cleanup::TrashListing, String> {
        self.lists.fetch_add(1, Ordering::Relaxed);
        if self.fail_list {
            return Err("Cannot list trash".into());
        }
        Ok(cleanup::TrashListing {
            items: self.items.lock().unwrap().clone(),
            broken: self.broken,
        })
    }
    fn purge(&self, entries: &[cleanup::TrashEntry]) -> Result<(), String> {
        self.purges.lock().unwrap().push(
            entries
                .iter()
                .map(|entry| entry.item.id.to_string_lossy().into_owned())
                .collect(),
        );
        if self.fail_purge {
            return Err("Cannot purge trash".into());
        }
        let ids = entries
            .iter()
            .map(|entry| &entry.item.id)
            .collect::<std::collections::HashSet<_>>();
        self.items
            .lock()
            .unwrap()
            .retain(|entry| !ids.contains(&entry.item.id));
        Ok(())
    }
    fn move_files(&self, paths: &[PathBuf]) -> Result<(), String> {
        for path in paths {
            self.moved.lock().unwrap().push(path.clone());
            let target = path.with_extension("trashed");
            fs::rename(path, target).map_err(|e| e.to_string())?;
        }
        Ok(())
    }
}
fn trash_entry(id: &str, deleted: i64, bytes: u64) -> cleanup::TrashEntry {
    cleanup::TrashEntry {
        item: trash::TrashItem {
            id: id.into(),
            name: id.into(),
            original_parent: PathBuf::from("/fake-trash"),
            time_deleted: deleted,
        },
        bytes,
    }
}
#[test]
fn policy_uses_latest_access_or_modify_time_and_trashes_downloads() {
    let t = Temp::new();
    let roots = t.roots();
    let trash = FakeTrash::default();
    let at = 100 * 86400;
    for (path, access) in [
        (roots.cache.join("old"), 1),
        (roots.cache.join("recent"), at),
        (roots.home.join("Downloads/old"), 1),
    ] {
        file(&path, &vec![1; 4096]);
        let f = fs::File::options().write(true).open(&path).unwrap();
        f.set_times(
            fs::FileTimes::new()
                .set_modified(UNIX_EPOCH + Duration::from_secs(1))
                .set_accessed(UNIX_EPOCH + Duration::from_secs(access)),
        )
        .unwrap();
    }
    trash
        .items
        .lock()
        .unwrap()
        .extend([trash_entry("old", 1, 50), trash_entry("new", at as i64, 60)]);
    let mut prefs = Prefs::default();
    prefs.automatic.downloads_days = 30;
    let run = cleanup::policy(&roots, &prefs, &trash, at);
    assert!(run.error.is_none());
    assert!(run.freed_bytes >= 50);
    assert!(!roots.cache.join("old").exists());
    assert!(roots.cache.join("recent").exists());
    assert!(roots.home.join("Downloads/old.trashed").exists());
    assert_eq!(trash.list().unwrap().items.len(), 1);
    assert_eq!(trash.moved.lock().unwrap().len(), 1);
}
#[test]
fn schedule_and_strict_preferences_retain_invalid_files() {
    let t = Temp::new();
    let path = t.0.join("cleanup.toml");
    let mut p = Prefs::load(&path).unwrap();
    assert!(!p.automatic.enabled);
    assert_eq!(p.automatic.downloads_days, 0);
    p.automatic.enabled = true;
    p.last_run = Some(cleanup::LastRun {
        at: 100,
        ..Default::default()
    });
    for (frequency, days) in [
        ("daily", 1),
        ("weekly", 7),
        ("monthly", 30),
        ("low-space", 1),
    ] {
        p.automatic.frequency = frequency.into();
        assert!(!p.due(100 + days * 86400 - 1, 1, 100));
        assert!(p.due(100 + days * 86400, 1, 100));
    }
    assert!(!p.due(9999999, 20, 100));
    p.save(&path).unwrap();
    let valid = fs::read_to_string(&path).unwrap();
    assert!(Prefs::load(&path).is_ok());
    fs::write(&path, format!("{valid}\nunknown = 3\n")).unwrap();
    assert!(Prefs::load(&path).is_err());
    let before = fs::read_to_string(&path).unwrap();
    let storage = Storage::new(
        t.roots(),
        path.clone(),
        Arc::new(FakeDisks::default()),
        Arc::new(FakeTrash::default()),
        Arc::new(FakeProcess::default()),
    );
    assert!(storage.set("cleanup.auto", "true").is_err());
    assert_eq!(before, fs::read_to_string(path).unwrap());
    assert!(p.change("cleanup.auto-cache", "1").is_err());
    assert!(payload::<Empty>("{\"extra\":true}").is_err());
}
#[test]
fn cache_and_open_allowlists_reject_traversals_and_symlink_ancestors() {
    let t = Temp::new();
    let roots = t.roots();
    file(&roots.cache.join("app/a"), b"keep");
    symlink("/", roots.cache.join("link")).unwrap();
    for name in ["", ".", "..", "../app", "/etc"] {
        assert!(!cleanup::valid_folder(name));
    }
    assert!(cleanup::checked_path(&roots.cache, &roots.cache.join("link/etc/passwd")).is_err());
    let s = Storage::new(
        roots.clone(),
        t.0.join("cleanup.toml"),
        Arc::new(FakeDisks::default()),
        Arc::new(FakeTrash::default()),
        Arc::new(FakeProcess::default()),
    );
    assert!(s.set("storage.open", r#"{"path":"/etc"}"#).is_err());
    assert!(
        s.set("storage.mount", r#"{"volume":"/fake","action":"mount"}"#)
            .is_err()
    );
    assert!(
        s.set("storage.label", r#"{"volume":"/fake","label":"bad/name"}"#)
            .is_err()
    );
    {
        let mut i = s.inner.lock().unwrap();
        i.scan = scan::scan(&roots, |_| {});
    }
    assert!(allowed_open(&s.inner.lock().unwrap(), &roots.cache));
    let children = s.inner.lock().unwrap().scan.cache.clone();
    assert!(cleanup::remove_cache(&roots, &["../app".into()], &children).is_err());
    cleanup::remove_cache(&roots, &["app".into()], &children).unwrap();
    assert!(!roots.cache.join("app").exists());
}
#[derive(Default)]
struct FakeDisks {
    objects: Mutex<disks::Objects>,
    calls: Mutex<Vec<String>>,
}
impl Disks for FakeDisks {
    fn objects(&self) -> Result<disks::Objects, String> {
        Ok(self.objects.lock().unwrap().clone())
    }
    fn call(
        &self,
        path: &str,
        interface: &str,
        method: &str,
        label: Option<&str>,
    ) -> Result<(), String> {
        self.calls
            .lock()
            .unwrap()
            .push(format!("{interface}.{method}"));
        if method == "Mount" || method == "Unmount" {
            self.objects
                .lock()
                .unwrap()
                .get_mut(path)
                .unwrap()
                .get_mut("org.freedesktop.UDisks2.Filesystem")
                .unwrap()
                .insert(
                    "MountPoints".into(),
                    if method == "Mount" {
                        json!(["/remya-test-unmounted-path"])
                    } else {
                        json!([])
                    },
                );
        }
        if method == "SetLabel" {
            self.objects
                .lock()
                .unwrap()
                .get_mut(path)
                .unwrap()
                .get_mut("org.freedesktop.UDisks2.Block")
                .unwrap()
                .insert("IdLabel".into(), json!(label.unwrap()));
        }
        Ok(())
    }
    fn open(&self, _: &Path) -> Result<(), String> {
        Ok(())
    }
}
fn objects() -> disks::Objects {
    serde_json::from_value(json!({
    "/drive":{"org.freedesktop.UDisks2.Drive":{"Model":"Test SSD","Size":1000,"ConnectionBus":"usb","Ejectable":true,"CanPowerOff":true}},
    "/part":{"org.freedesktop.UDisks2.Block":{"Drive":"/drive","IdType":"crypto_LUKS","Size":500},"org.freedesktop.UDisks2.Partition":{"Offset":100,"Number":1}},
    "/clear":{"org.freedesktop.UDisks2.Block":{"CryptoBackingDevice":"/part","IdType":"ext4","IdLabel":"Data","Device":[47,100,101,118,47,100,109,45,48,0]},"org.freedesktop.UDisks2.Filesystem":{"MountPoints":[[47,0]]}},
    "/ignored":{"org.freedesktop.UDisks2.Block":{"Drive":"/drive","HintIgnore":true,"Size":1},"org.freedesktop.UDisks2.Filesystem":{}},
    "/swap":{"org.freedesktop.UDisks2.Block":{"Drive":"/drive","IdType":"swap","Size":10}},
    "/zram":{"org.freedesktop.UDisks2.Block":{"Drive":"/drive","IdType":"ext4","Device":[47,100,101,118,47,122,114,97,109,48,0]},"org.freedesktop.UDisks2.Filesystem":{}}
})).unwrap()
}
#[test]
fn udisks_fixture_resolves_luks_and_protects_system_volumes() {
    let fake = FakeDisks {
        objects: Mutex::new(objects()),
        ..Default::default()
    };
    let drives = disks::parse(&fake.objects().unwrap(), Path::new("/home"));
    assert_eq!(drives.len(), 1);
    assert_eq!(drives[0].volumes.len(), 2);
    let clear = drives[0].volumes.iter().find(|v| v.id == "/clear").unwrap();
    assert_eq!(clear.offset, 100);
    assert_eq!(clear.number, 1);
    assert!(clear.system);
    assert!(!clear.can_unmount);
    assert!(
        disks::operate(
            &fake,
            Path::new("/home"),
            "storage.mount",
            r#"{"volume":"/clear","action":"unmount"}"#
        )
        .is_err()
    );
    assert!(
        disks::operate(
            &fake,
            Path::new("/home"),
            "storage.eject",
            r#"{"drive":"/drive","action":"eject"}"#
        )
        .is_err()
    );
    assert!(fake.calls.lock().unwrap().is_empty());
    assert!(
        disks::operate(
            &fake,
            Path::new("/home"),
            "storage.label",
            r#"{"volume":"/clear","label":"New"}"#
        )
        .is_ok()
    );
    assert!(!disks::valid_label(&"a".repeat(256)));
    assert!(!disks::valid_label("bad\n"));
}
#[derive(Default)]
struct FakeProcess {
    calls: Mutex<Vec<(String, Vec<String>)>>,
    locked: bool,
    removed: Mutex<bool>,
    cache_dir: Option<PathBuf>,
    orphan_names: Option<&'static str>,
}
impl Process for FakeProcess {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        self.calls
            .lock()
            .unwrap()
            .push((program.into(), args.iter().map(|s| s.to_string()).collect()));
        if program == "/usr/bin/paccache" {
            return Ok("finished dry run: 1 candidates (disk space saved: 1 KiB)".into());
        }
        match args {
            ["CacheDir"] => Ok(self.cache_dir.as_ref().unwrap().to_string_lossy().into()),
            ["-R", "--noconfirm", "--", "orphan"] => {
                *self.removed.lock().unwrap() = true;
                Ok(String::new())
            }
            ["-Qdtq"] if *self.removed.lock().unwrap() => Ok(String::new()),
            ["-Qdtq"] => Ok(self.orphan_names.unwrap_or("orphan\n").into()),
            ["-Qi", "--", "orphan"] => {
                Ok("Name : orphan\nVersion : 1.0-1\nInstalled Size : 1.5 MiB\n".into())
            }
            ["-Qi", "--", names @ ..] => Ok(names
                .iter()
                .map(|name| format!("Name : {name}\nVersion : 1.0-1\nInstalled Size : 1.5 MiB\n"))
                .collect::<Vec<_>>()
                .join("\n")),
            _ => Ok(String::new()),
        }
    }
    fn exists(&self, _: &str) -> bool {
        self.cache_dir.is_some()
    }
    fn locked(&self) -> bool {
        self.locked
    }
}
#[test]
fn package_parsers_and_root_validation_refuse_changed_selections() {
    assert_eq!(
        packages::paccache_saved("==> finished dry run: 2 candidates (disk space saved: 1.5 MiB)")
            .unwrap(),
        1572864
    );
    assert_eq!(
        packages::paccache_saved("no candidate packages found for pruning").unwrap(),
        0
    );
    assert!(packages::paccache_saved("garbage").is_err());
    let process = FakeProcess::default();
    let current = packages::orphans(&process).unwrap();
    assert_eq!(current[0].bytes, 1572864);
    assert!(packages::validate_keep(0).is_err());
    assert!(packages::validate_keep(4).is_err());
    let request = current
        .iter()
        .map(|p| packages::Package {
            name: p.name.clone(),
            version: p.version.clone(),
        })
        .collect::<Vec<_>>();
    assert!(packages::validate_packages(&request, &current).is_ok());
    let mut wrong = request.clone();
    wrong[0].version = "2".into();
    assert!(
        packages::validate_packages(&wrong, &current)
            .unwrap_err()
            .starts_with("Conflict:")
    );
    wrong[0].name = "--root".into();
    assert!(packages::validate_packages(&wrong, &current).is_err());
    assert!(packages::validate_packages(&vec![request[0].clone(); 501], &current).is_err());
    let locked = FakeProcess {
        locked: true,
        ..Default::default()
    };
    assert!(packages::remove_packages(&locked, &request).is_err());
    assert!(locked.calls.lock().unwrap().is_empty());
    assert!(packages::clean_cache(&locked, 2, false).is_err());
}
#[test]
fn constructor_is_lazy_and_worker_completes_without_holding_state() {
    let t = Temp::new();
    file(&t.0.join("Documents/test"), b"data");
    let s = Storage::new(
        t.roots(),
        t.0.join("cleanup.toml"),
        Arc::new(FakeDisks::default()),
        Arc::new(FakeTrash::default()),
        Arc::new(FakeProcess::default()),
    );
    assert!(!s.inner.lock().unwrap().started);
    assert!(s.state("storage")["usage"]["scanned_at"].is_null());
    s.read("storage");
    for _ in 0..100 {
        if !s.busy() {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(!s.busy());
    assert!(s.state("storage")["usage"]["scanned_at"].is_number());
    assert!(s.take_dirty());
    assert!(!s.take_dirty());
}

#[test]
fn privileged_commands_are_fixed_and_read_back() {
    let t = Temp::new();
    file(&t.0.join("cached.pkg.tar.zst"), b"cache");
    let process = FakeProcess {
        cache_dir: Some(t.0.clone()),
        ..Default::default()
    };
    let state = packages::clean_cache(&process, 2, true).unwrap();
    assert_eq!(state["files"], 1);
    assert_eq!(state["bytes"], 5);
    let calls = process.calls.lock().unwrap();
    assert!(calls.contains(&(
        "/usr/bin/paccache".into(),
        vec!["-r".into(), "-k".into(), "2".into()]
    )));
    assert!(calls.contains(&(
        "/usr/bin/paccache".into(),
        vec!["-r".into(), "-u".into(), "-k".into(), "0".into()]
    )));
    drop(calls);
    let selected = [packages::Package {
        name: "orphan".into(),
        version: "1.0-1".into(),
    }];
    assert_eq!(
        packages::remove_packages(&process, &selected).unwrap()["packages"],
        json!([])
    );
    assert!(
        payload::<packages::RemovePackages>(
            r#"{"packages":[{"name":"orphan","version":"1","bytes":2}]}"#
        )
        .is_err()
    );
}
#[test]
fn run_now_works_when_disabled_and_external_invalid_policy_is_retained() {
    let t = Temp::new();
    let config = t.0.join("cleanup.toml");
    let trash = Arc::new(FakeTrash::default());
    trash.items.lock().unwrap().push(trash_entry("old", 1, 30));
    let s = Storage::new(
        t.roots(),
        config.clone(),
        Arc::new(FakeDisks::default()),
        trash.clone(),
        Arc::new(FakeProcess::default()),
    );
    assert!(s.set("cleanup.run-now", "{}").is_ok());
    for _ in 0..100 {
        if !s.busy() {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(!s.busy());
    assert!(trash.list().unwrap().items.is_empty());
    let prefs = Prefs::load(&config).unwrap();
    assert!(!prefs.automatic.enabled);
    assert_eq!(prefs.last_run.unwrap().freed_bytes, 30);
    fs::write(&config, "broken [").unwrap();
    assert!(s.set("cleanup.auto", "true").is_err());
    assert_eq!(fs::read_to_string(&config).unwrap(), "broken [");
    assert_eq!(s.state("cleanup")["writable"], false);
}
#[test]
fn external_cache_is_measured_without_adding_it_to_home_usage() {
    let home = Temp::new();
    let external = Temp::new();
    let mut roots = home.roots();
    roots.cache = external.0.join("cache");
    file(&roots.cache.join("app/data"), &vec![1; 4096]);
    let result = scan::scan(&roots, |_| {});
    assert_eq!(result.cache.len(), 1);
    assert!(result.cache[0].bytes >= 4096);
    assert_eq!(
        result
            .categories
            .iter()
            .find(|c| c.id == "cache")
            .unwrap()
            .bytes,
        0
    );
}

#[test]
fn loop_devices_need_backing_files_and_are_not_ejectable() {
    let fixture:disks::Objects=serde_json::from_value(json!({
        "/loop": {"org.freedesktop.UDisks2.Block":{"Drive":"/","IdType":"ext4","Size":100},"org.freedesktop.UDisks2.Loop":{"BackingFile":[47,116,101,115,116,0]},"org.freedesktop.UDisks2.Filesystem":{}},
        "/empty": {"org.freedesktop.UDisks2.Block":{"Drive":"/","IdType":"ext4","Size":100},"org.freedesktop.UDisks2.Loop":{"BackingFile":[0]},"org.freedesktop.UDisks2.Filesystem":{}}
    })).unwrap();
    let drives = disks::parse(&fixture, Path::new("/home"));
    assert_eq!(drives.len(), 1);
    assert_eq!(drives[0].volumes.len(), 1);
    assert!(!drives[0].can_power_off);
    assert!(!drives[0].ejectable);
}

#[test]
fn mount_readback_and_eject_unmount_order_use_reported_objects_only() {
    let mut objects = objects();
    objects.remove("/swap");
    objects
        .get_mut("/clear")
        .unwrap()
        .get_mut("org.freedesktop.UDisks2.Filesystem")
        .unwrap()
        .insert("MountPoints".into(), json!([]));
    let fake = FakeDisks {
        objects: Mutex::new(objects),
        ..Default::default()
    };
    let drives = disks::operate(
        &fake,
        Path::new("/home"),
        "storage.mount",
        r#"{"volume":"/clear","action":"mount"}"#,
    )
    .unwrap();
    assert!(!drives[0].volumes[0].mount_points.is_empty());
    disks::operate(
        &fake,
        Path::new("/home"),
        "storage.eject",
        r#"{"drive":"/drive","action":"eject"}"#,
    )
    .unwrap();
    assert_eq!(
        *fake.calls.lock().unwrap(),
        vec!["Filesystem.Mount", "Filesystem.Unmount", "Drive.Eject"]
    );
}

#[test]
fn ignored_system_blocks_still_protect_the_physical_drive() {
    let mut objects = objects();
    objects.remove("/swap");
    objects
        .get_mut("/clear")
        .unwrap()
        .get_mut("org.freedesktop.UDisks2.Filesystem")
        .unwrap()
        .insert("MountPoints".into(), json!([]));
    objects
        .get_mut("/ignored")
        .unwrap()
        .get_mut("org.freedesktop.UDisks2.Filesystem")
        .unwrap()
        .insert("MountPoints".into(), json!(["/"]));
    let fake = FakeDisks {
        objects: Mutex::new(objects),
        ..Default::default()
    };
    assert!(
        disks::operate(
            &fake,
            Path::new("/home"),
            "storage.eject",
            r#"{"drive":"/drive","action":"power-off"}"#
        )
        .is_err()
    );
    assert!(fake.calls.lock().unwrap().is_empty());
}

#[test]
fn orphan_details_are_parsed_as_records_and_queried_in_one_batch() {
    let records = "Name : first\nVersion : 1.0-1\nInstalled Size : 1.5 MiB\n\nName : second\nVersion : 2.0-2\nInstalled Size : 2 KiB\n\n";
    let parsed = packages::installed_packages(records).unwrap();
    assert_eq!(parsed.len(), 2);
    assert_eq!(parsed[0].name, "first");
    assert_eq!(parsed[0].version, "1.0-1");
    assert_eq!(parsed[0].bytes, 1572864);
    assert_eq!(parsed[1].name, "second");
    assert_eq!(parsed[1].version, "2.0-2");
    assert_eq!(parsed[1].bytes, 2048);
    assert!(packages::installed_packages("Name : incomplete").is_err());
    let process = FakeProcess {
        orphan_names: Some("first\nsecond\n"),
        ..Default::default()
    };
    assert_eq!(packages::orphans(&process).unwrap().len(), 2);
    assert_eq!(
        *process.calls.lock().unwrap(),
        vec![
            ("/usr/bin/pacman".into(), vec!["-Qdtq".into()]),
            (
                "/usr/bin/pacman".into(),
                vec!["-Qi".into(), "--".into(), "first".into(), "second".into()]
            )
        ]
    );
    let empty = FakeProcess {
        orphan_names: Some(""),
        ..Default::default()
    };
    assert!(packages::orphans(&empty).unwrap().is_empty());
    assert_eq!(empty.calls.lock().unwrap().len(), 1);
    let invalid = FakeProcess {
        orphan_names: Some("first\n--root\n"),
        ..Default::default()
    };
    assert!(packages::orphans(&invalid).is_err());
    assert_eq!(invalid.calls.lock().unwrap().len(), 1);
}
#[test]
fn expired_trash_is_purged_once_and_only_success_counts_as_freed() {
    let t = Temp::new();
    let mut prefs = Prefs::default();
    prefs.automatic.cache_days = 0;
    for fail in [false, true] {
        let trash = FakeTrash {
            fail_purge: fail,
            ..Default::default()
        };
        trash.items.lock().unwrap().extend([
            trash_entry("old-a", 1, 50),
            trash_entry("old-b", 1, 70),
            trash_entry("recent", 100 * 86400, 90),
            trash_entry("undated", -1, 100),
        ]);
        let run = cleanup::policy(&t.roots(), &prefs, &trash, 100 * 86400);
        assert_eq!(trash.lists.load(Ordering::Relaxed), 1);
        assert_eq!(*trash.purges.lock().unwrap(), vec![vec!["old-a", "old-b"]]);
        assert_eq!(run.freed_bytes, if fail { 0 } else { 120 });
        assert_eq!(run.error.is_some(), fail);
    }
}
#[test]
fn empty_trash_purges_the_listed_batch_without_relisting_it() {
    let t = Temp::new();
    let trash = Arc::new(FakeTrash::default());
    trash
        .items
        .lock()
        .unwrap()
        .extend([trash_entry("a", 1, 20), trash_entry("b", 2, 30)]);
    let storage = Storage::new(
        t.roots(),
        t.0.join("cleanup.toml"),
        Arc::new(FakeDisks::default()),
        trash.clone(),
        Arc::new(FakeProcess::default()),
    );
    assert!(
        storage
            .set("cleanup.trash", r#"{"action":"empty"}"#)
            .is_ok()
    );
    for _ in 0..100 {
        if !storage.busy() {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(!storage.busy());
    assert_eq!(*trash.purges.lock().unwrap(), vec![vec!["a", "b"]]);
    // One initial list and one readback after the action.
    assert_eq!(trash.lists.load(Ordering::Relaxed), 2);
    assert_eq!(storage.state("cleanup")["trash"]["items"], 0);
}
#[test]
fn background_refresh_is_coalesced_and_does_not_block_user_sets() {
    use std::sync::mpsc;
    struct PausedDisks {
        entered: mpsc::SyncSender<()>,
        resume: Mutex<mpsc::Receiver<()>>,
    }
    impl Disks for PausedDisks {
        fn objects(&self) -> Result<disks::Objects, String> {
            self.entered.send(()).map_err(|e| e.to_string())?;
            self.resume
                .lock()
                .unwrap()
                .recv_timeout(Duration::from_secs(5))
                .map_err(|e| e.to_string())?;
            Ok(disks::Objects::new())
        }
        fn call(&self, _: &str, _: &str, _: &str, _: Option<&str>) -> Result<(), String> {
            Ok(())
        }
        fn open(&self, _: &Path) -> Result<(), String> {
            Ok(())
        }
    }
    let t = Temp::new();
    let (entered_tx, entered_rx) = mpsc::sync_channel(1);
    let (resume_tx, resume_rx) = mpsc::channel();
    let storage = Storage::new(
        t.roots(),
        t.0.join("cleanup.toml"),
        Arc::new(PausedDisks {
            entered: entered_tx,
            resume: Mutex::new(resume_rx),
        }),
        Arc::new(FakeTrash::default()),
        Arc::new(FakeProcess::default()),
    );
    storage.inner.lock().unwrap().started = true;
    assert_eq!(storage.read("storage")["busy"], false);
    entered_rx.recv_timeout(Duration::from_secs(2)).unwrap();
    for _ in 0..20 {
        assert_eq!(storage.read("cleanup")["writable"], true);
    }
    assert!(entered_rx.try_recv().is_err());
    assert!(storage.inner.lock().unwrap().refreshing);
    let state = storage.set("cleanup.auto", "true").unwrap();
    assert_eq!(state["busy"], false);
    assert_eq!(state["automatic"]["enabled"], true);
    resume_tx.send(()).unwrap();
    for _ in 0..100 {
        if !storage.inner.lock().unwrap().refreshing {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(!storage.inner.lock().unwrap().refreshing);
    assert!(!storage.busy());
    assert_eq!(storage.state("cleanup")["automatic"]["enabled"], true);
}

#[test]
fn trash_listing_skips_missing_metadata_and_purges_only_readable_items() {
    let t = Temp::new();
    let info = t.0.join("info");
    let good = info.join("good.trashinfo");
    let broken = info.join("broken.trashinfo");
    file(&good, b"[Trash Info]\nPath=/original/good\n");
    file(&broken, b"[Trash Info]\nPath=/original/broken\n");
    file(&t.0.join("files/good"), b"contents");
    let mut good_entry = trash_entry("good", 1, 0).item;
    good_entry.id = good.clone().into_os_string();
    let mut broken_entry = trash_entry("broken", 1, 0).item;
    broken_entry.id = broken.clone().into_os_string();
    let listing = cleanup::TrashListing::read(vec![broken_entry, good_entry]);
    assert_eq!(listing.broken, 1);
    assert_eq!(listing.items.len(), 1);
    assert_eq!(listing.items[0].bytes, 8);
    cleanup::RealTrash.purge(&listing.items).unwrap();
    assert!(!good.exists());
    assert!(!t.0.join("files/good").exists());
    assert!(broken.exists());
}

#[test]
fn large_files_use_allocated_size_and_hide_internal_directories_without_losing_usage() {
    let t = Temp::new();
    let mut roots = t.roots();
    roots.cache.push("");
    roots.folders[0].2.push("");
    file(&roots.cache.join("app/data"), b"cache");
    let sparse = fs::File::create(t.0.join("Docker.raw")).unwrap();
    sparse.set_len(412_000_000_000).unwrap();
    for name in [
        "Downloads/visible",
        ".docker/internal",
        "Documents/.nested/internal",
    ] {
        let path = t.0.join(name);
        file(&path, b"");
        let file = fs::File::options().write(true).open(path).unwrap();
        rustix::fs::fallocate(&file, rustix::fs::FallocateFlags::empty(), 0, 100_000_000).unwrap();
    }
    symlink(t.0.join("Downloads/visible"), t.0.join("linked-large")).unwrap();
    let result = scan::scan(&roots, |_| {});
    assert_eq!(result.large.len(), 1);
    assert_eq!(result.large[0].path, t.0.join("Downloads/visible"));
    assert_eq!(
        result.large[0].bytes,
        fs::metadata(&result.large[0].path).unwrap().blocks() * 512
    );
    assert!(
        result
            .categories
            .iter()
            .find(|c| c.id == "home-other")
            .unwrap()
            .bytes
            >= 100_000_000
    );
    assert!(
        result
            .categories
            .iter()
            .find(|c| c.id == "documents")
            .unwrap()
            .bytes
            >= 100_000_000
    );
    for category in result.categories {
        if let Some(path) = category.path {
            assert!(path.is_absolute());
            assert!(!path.as_os_str().as_encoded_bytes().ends_with(b"/"));
        }
    }
}

#[test]
fn trash_state_reports_broken_count_and_only_list_failure_is_an_error() {
    let t = Temp::new();
    for fail_list in [false, true] {
        let trash = Arc::new(FakeTrash {
            broken: 2,
            fail_list,
            ..Default::default()
        });
        trash
            .items
            .lock()
            .unwrap()
            .push(trash_entry("readable", 1, 40));
        let storage = Storage::new(
            t.roots(),
            t.0.join("cleanup.toml"),
            Arc::new(FakeDisks::default()),
            trash,
            Arc::new(FakeProcess::default()),
        );
        storage.refresh();
        let state = storage.state("cleanup");
        if fail_list {
            assert_eq!(state["trash"], json!({"error":"Cannot list trash"}));
        } else {
            assert_eq!(state["trash"], json!({"items":1,"bytes":40,"broken":2}));
        }
    }
}
