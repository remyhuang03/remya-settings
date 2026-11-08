use super::*;
use std::sync::{Arc, Mutex};
use tempfile::TempDir;
#[derive(Clone, Default)]
struct FakeSystemd {
    fail: Arc<Mutex<bool>>,
    units: Arc<Mutex<Vec<Unit>>>,
}
impl Systemd for FakeSystemd {
    fn read(&self) -> Result<Runtime, String> {
        if *self.fail.lock().unwrap() {
            return Err("User manager unreachable".into());
        }
        Ok(Runtime {
            session_autostart: true,
            units: self.units.lock().unwrap().clone(),
        })
    }
}
fn setup() -> (TempDir, Startup<FakeSystemd>) {
    let temp = TempDir::new().unwrap();
    let dirs = Directories {
        user: temp.path().join("user/autostart"),
        system: vec![
            temp.path().join("system/autostart"),
            temp.path().join("system2/autostart"),
        ],
        desktops: vec!["Hyprland".into(), "Test".into()],
        path: vec!["/usr/bin".into()],
    };
    for p in std::iter::once(&dirs.user).chain(&dirs.system) {
        fs::create_dir_all(p).unwrap();
    }
    let config = temp.path().join("settings/startup.toml");
    (temp, Startup::new(FakeSystemd::default(), Ok(dirs), config))
}
fn desktop(name: &str, extra: &str) -> String {
    format!(
        "# retained comment\n[Desktop Entry]\nType=Application\nName={name}\nName[fr]=Nom\nComment=Description\nExec=/usr/bin/true\n{extra}"
    )
}
fn put(manager: &Startup<FakeSystemd>, system: bool, id: &str, extra: &str) -> PathBuf {
    let dirs = manager.dirs().unwrap();
    let path = if system { &dirs.system[0] } else { &dirs.user }.join(id);
    fs::write(&path, desktop(id, extra)).unwrap();
    path
}
fn set(manager: &mut Startup<FakeSystemd>, id: &str, enabled: bool) -> Result<Value, String> {
    manager.set(IDS[0], &json!({"id":id,"enabled":enabled}).to_string())
}
#[test]
fn precedence_hidden_origin_sort_and_invalid_files() {
    let (_temp, mut m) = setup();
    put(&m, true, "a.desktop", "");
    put(&m, false, "a.desktop", "Hidden=true\n");
    put(&m, false, "b.desktop", "X-GNOME-Autostart-enabled=false\n");
    fs::write(
        m.dirs().unwrap().system[1].join("a.desktop"),
        desktop("Wrong", ""),
    )
    .unwrap();
    fs::write(m.dirs().unwrap().user.join("bad.desktop"), "invalid [").unwrap();
    m.refresh().unwrap();
    let s = m.state();
    assert_eq!(s["skipped_invalid"], 1);
    assert_eq!(s["entries"][0]["id"], "a.desktop");
    assert_eq!(s["entries"][0]["origin"], "system");
    assert_eq!(s["entries"][0]["removable"], false);
    assert_eq!(s["system"], json!({"a.desktop":false,"b.desktop":true}));
    assert_eq!(s["entries"][1]["origin"], "user");
    assert_eq!(s["entries"][1]["removable"], true);
}
#[test]
fn generator_filters_and_desktop_components() {
    let (_temp, mut m) = setup();
    for (id, extra) in [
        ("only", "OnlyShowIn=GNOME;KDE;\n"),
        ("not", "NotShowIn=Test;\n"),
        ("missing", "TryExec=remya-nonexistent-executable\n"),
        ("relative", "TryExec=./true\n"),
        ("phase", "X-GNOME-Autostart-Phase=\n"),
        ("skip", "X-systemd-skip=true\n"),
        ("bool", "Hidden=broken\n"),
        (
            "included",
            "OnlyShowIn=Test;\nNotShowIn=GNOME;\nTryExec=true\n",
        ),
        ("absolute", "TryExec=/usr/bin/true\n"),
        ("kde", "X-KDE-autostart-condition=some:condition\n"),
    ] {
        put(&m, false, &format!("{id}.desktop"), extra);
    }
    let not_exec = m.config.with_file_name("not-executable");
    fs::create_dir_all(not_exec.parent().unwrap()).unwrap();
    fs::write(&not_exec, "test").unwrap();
    put(
        &m,
        false,
        "nonexec.desktop",
        &format!("TryExec={}\n", not_exec.display()),
    );
    let link = put(&m, false, "link.desktop", "");
    fs::write(
        link,
        "[Desktop Entry]\nType=Link\nName=Link\nURL=https://example.org\n",
    )
    .unwrap();
    m.refresh().unwrap();
    assert_eq!(
        m.system,
        BTreeMap::from([
            ("absolute.desktop".into(), true),
            ("included.desktop".into(), true),
            ("kde.desktop".into(), true)
        ])
    );
    assert_eq!(m.skipped_invalid, 1);
}
#[test]
fn enable_disable_overrides_preserve_data_and_remove_only_equal_copies() {
    let (_temp, mut m) = setup();
    let source = put(
        &m,
        true,
        "system.desktop",
        "X-GNOME-Autostart-enabled=true\n",
    );
    let original = fs::read_to_string(&source).unwrap();
    let user = m.dirs().unwrap().user.join("system.desktop");
    set(&mut m, "system.desktop", true).unwrap();
    assert!(!user.exists());
    let state = set(&mut m, "system.desktop", false).unwrap();
    assert_eq!(state["system"]["system.desktop"], false);
    assert_eq!(
        fs::metadata(&user).unwrap().permissions().mode() & 0o777,
        0o644
    );
    let data = fs::read_to_string(&user).unwrap();
    assert!(data.contains("# retained comment") && data.contains("Name[fr]=Nom"));
    assert_eq!(
        string(&load(&user).unwrap(), "X-GNOME-Autostart-enabled"),
        "false"
    );
    set(&mut m, "system.desktop", true).unwrap();
    assert!(!user.exists());
    assert_eq!(fs::read_to_string(&source).unwrap(), original);
    set(&mut m, "system.desktop", false).unwrap();
    let key = load(&user).unwrap();
    key.set_string(GROUP, "Comment", "Customized");
    fs::write(&user, key.to_data()).unwrap();
    set(&mut m, "system.desktop", true).unwrap();
    assert!(user.exists());
    assert_eq!(string(&load(&user).unwrap(), "Comment"), "Customized");
    let user_only = put(&m, false, "user.desktop", "");
    set(&mut m, "user.desktop", false).unwrap();
    set(&mut m, "user.desktop", true).unwrap();
    assert!(user_only.exists());
    assert!(!load(&user_only).unwrap().has_key(GROUP, "Hidden").unwrap());
}
#[test]
fn hidden_system_entry_can_be_enabled() {
    let (_temp, mut m) = setup();
    put(&m, true, "hidden.desktop", "Hidden=true\n");
    assert_eq!(
        set(&mut m, "hidden.desktop", true).unwrap()["system"]["hidden.desktop"],
        true
    );
}
#[test]
fn add_app_copy_and_remove_only_user_entries() {
    let (_temp, mut m) = setup();
    let source = put(&m, true, "existing.desktop", "");
    let application = m.config.with_file_name("installed.desktop");
    fs::create_dir_all(application.parent().unwrap()).unwrap();
    fs::write(&application, desktop("Copied application", "Hidden=true\n")).unwrap();
    m.application_file = Box::new(move |id| (id == "copied.desktop").then(|| application.clone()));
    assert!(
        m.set(IDS[1], r#"{"application":"missing.desktop"}"#)
            .unwrap_err()
            .starts_with("InvalidArgument:")
    );
    m.set(IDS[1], r#"{"application":"copied.desktop"}"#)
        .unwrap();
    let copied = load(&m.dirs().unwrap().user.join("copied.desktop")).unwrap();
    assert_eq!(string(&copied, "Name"), "Copied application");
    assert!(!copied.has_key(GROUP, "Hidden").unwrap());
    assert!(copied.to_data().contains("Name[fr]=Nom"));
    assert!(
        m.set(IDS[1], r#"{"application":"copied.desktop"}"#)
            .unwrap_err()
            .contains("already exists")
    );
    assert!(
        m.set(IDS[3], r#"{"id":"existing.desktop"}"#)
            .unwrap_err()
            .starts_with("InvalidArgument:")
    );
    m.set(IDS[3], r#"{"id":"copied.desktop"}"#).unwrap();
    assert!(source.exists());
    assert!(!m.system.contains_key("copied.desktop"));
}
#[test]
fn command_quoting_slug_collisions_and_validation() {
    let (_temp, mut m) = setup();
    let command = "/usr/bin/true 'two words' 'a\"b' '$HOME' '100%' 'a\\b' '' '`x`'";
    for name in ["Hello World", "Hello World", "中文"] {
        m.set(IDS[2], &json!({"name":name,"command":command}).to_string())
            .unwrap();
    }
    assert_eq!(m.system.len(), 3);
    assert!(m.system.contains_key("remya-hello-world-2.desktop"));
    let key = load(&m.dirs().unwrap().user.join("remya-command.desktop")).unwrap();
    assert_eq!(
        string(&key, "Exec"),
        r#"/usr/bin/true "two words" "a\"b" "\$HOME" 100%% "a\\b" "" "\`x\`""#
    );
    for (name, command) in [
        ("", "true"),
        ("bad\n", "true"),
        ("ok", "missing-program"),
        ("ok", "true\n"),
        ("ok", "'bad"),
        ("ok", ""),
    ] {
        assert!(
            m.set(IDS[2], &json!({"name":name,"command":command}).to_string())
                .unwrap_err()
                .starts_with("InvalidArgument:")
        );
    }
}
#[test]
fn ids_payloads_and_symlink_writes_are_rejected() {
    let (_temp, mut m) = setup();
    for id in [
        "../x.desktop",
        "a/b.desktop",
        "a\\b.desktop",
        ".x.desktop",
        "x",
        "bad\n.desktop",
        &format!("{}.desktop", "a".repeat(250)),
    ] {
        assert!(validate_id(id).is_err(), "{id}");
    }
    assert!(validate_id("org.example-App.desktop").is_ok());
    for text in [
        r#"{"id":"a.desktop","enabled":true,"extra":0}"#,
        r#"{"id":"a.desktop","enabled":"yes"}"#,
        "invalid",
    ] {
        assert!(
            m.set(IDS[0], text)
                .unwrap_err()
                .starts_with("InvalidArgument:")
        );
    }
    let system = put(&m, true, "a.desktop", "");
    std::os::unix::fs::symlink(&system, m.dirs().unwrap().user.join("a.desktop")).unwrap();
    assert!(
        set(&mut m, "a.desktop", false)
            .unwrap_err()
            .starts_with("Unavailable:")
    );
    assert!(!load(&system).unwrap().has_key(GROUP, "Hidden").unwrap());
}
#[test]
fn reconciliation_initialization_conflicts_resolutions_and_adoption() {
    let (_temp, mut m) = setup();
    let first = put(&m, false, "a.desktop", "");
    assert!(!m.config.exists());
    m.refresh().unwrap();
    assert_eq!(m.saved, Some(m.system.clone()));
    fs::write(&first, desktop("a.desktop", "Hidden=true\n")).unwrap();
    m.refresh().unwrap();
    let before = fs::read(&m.config).unwrap();
    assert!(m.state()["conflict"].as_bool().unwrap());
    assert_eq!(
        m.state()["conflicts"][0],
        json!({"id":"a.desktop","name":"a.desktop","saved":true,"system":false})
    );
    for id in IDS {
        assert!(m.set(id, "{}").unwrap_err().starts_with("Conflict:"));
    }
    assert_eq!(fs::read(&m.config).unwrap(), before);
    m.resolve("settings").unwrap();
    assert!(m.system["a.desktop"]);
    fs::write(&first, desktop("a.desktop", "Hidden=true\n")).unwrap();
    m.resolve("system").unwrap();
    assert!(!m.saved.as_ref().unwrap()["a.desktop"]);
    put(&m, false, "b.desktop", "");
    fs::remove_file(first).unwrap();
    m.refresh().unwrap();
    assert_eq!(m.saved, Some(BTreeMap::from([("b.desktop".into(), true)])));
    assert!(!m.state()["conflict"].as_bool().unwrap());
}
fn fail_write(_: &Path, _: &[u8]) -> Result<(), String> {
    Err("Injected write failure".into())
}
#[test]
fn invalid_config_detection_and_write_failures_retain_last_valid_saved() {
    let (_temp, mut m) = setup();
    put(&m, false, "a.desktop", "");
    m.refresh().unwrap();
    let saved = m.saved.clone();
    for bad in [
        "invalid [",
        "version=2\n[enabled]\n",
        "version=1\nunknown=true\n[enabled]\n",
        "version=1\n[enabled]\n'../a.desktop'=true\n",
    ] {
        fs::write(&m.config, bad).unwrap();
        assert!(m.refresh().is_err());
        assert_eq!(m.saved, saved);
        assert_eq!(m.state()["writable"], false);
        assert!(set(&mut m, "a.desktop", false).is_err());
        assert_eq!(fs::read_to_string(&m.config).unwrap(), bad);
    }
    fs::remove_file(&m.config).unwrap();
    m.refresh().unwrap();
    let valid = fs::read(&m.config).unwrap();
    m.writer = fail_write;
    assert!(set(&mut m, "a.desktop", false).is_err());
    assert_eq!(m.saved, saved);
    assert_eq!(fs::read(&m.config).unwrap(), valid);
    assert!(m.state()["error"].is_string());
    put(&m, false, "a.desktop", "Hidden=true\n");
    assert!(m.resolve("settings").is_err());
    assert_eq!(fs::read(&m.config).unwrap(), valid);
    // A persistence failure after readback still keeps the old saved map and a conflict.
    m.writer = |path, bytes| {
        if path.file_name().unwrap() == "startup.toml" {
            fail_write(path, bytes)
        } else {
            atomic_write(path, bytes)
        }
    };
    assert!(m.resolve("system").is_err());
    assert_eq!(m.saved, saved);
    let (_fresh_temp, mut fresh) = setup();
    fresh.writer = fail_write;
    assert!(fresh.refresh().is_err());
    assert!(!fresh.config.exists());
    assert!(fresh.saved.is_none());
    let (_unreadable_temp, mut unreadable) = setup();
    let user = unreadable.dirs().unwrap().user.clone();
    fs::remove_dir(&user).unwrap();
    fs::write(&user, "not a directory").unwrap();
    assert!(unreadable.refresh().is_err());
    assert!(!unreadable.config.exists());
}
#[test]
fn fake_systemd_statuses_and_failure_do_not_break_discovery() {
    let (_temp, mut m) = setup();
    for (id, active, sub, result, expected) in [
        ("run", "active", "running", "success", "running"),
        ("exit", "active", "exited", "success", "finished"),
        ("done", "inactive", "dead", "success", "finished"),
        ("fail", "failed", "failed", "exit-code", "failed"),
        ("condition", "inactive", "dead", "exec-condition", "failed"),
    ] {
        let path = put(&m, false, &format!("{id}.desktop"), "");
        m.systemd.units.lock().unwrap().push(Unit {
            source: path,
            active: active.into(),
            sub: sub.into(),
            result: result.into(),
        });
        m.refresh().unwrap();
        assert_eq!(
            m.entries
                .iter()
                .find(|e| e.id == format!("{id}.desktop"))
                .unwrap()
                .status
                .as_deref(),
            Some(expected)
        );
    }
    put(&m, false, "none.desktop", "");
    m.refresh().unwrap();
    assert_eq!(
        m.entries
            .iter()
            .find(|e| e.id == "none.desktop")
            .unwrap()
            .status
            .as_deref(),
        Some("not-started")
    );
    *m.systemd.fail.lock().unwrap() = true;
    m.refresh().unwrap();
    assert!(m.entries.iter().all(|e| e.status.is_none()));
    assert_eq!(m.state()["session_autostart"], Value::Null);
    assert!(m.state()["status_error"].is_string());
    assert_eq!(m.state()["writable"], true);
}

#[test]
fn readback_failure_and_unreadable_config_keep_the_saved_file() {
    let (_temp, mut m) = setup();
    put(&m, false, "a.desktop", "");
    m.refresh().unwrap();
    let saved = fs::read(&m.config).unwrap();
    m.writer = |path, data| {
        if path
            .extension()
            .is_some_and(|extension| extension == "desktop")
        {
            atomic_write(
                path,
                String::from_utf8_lossy(data)
                    .replace("Hidden=true", "Hidden=false")
                    .as_bytes(),
            )
        } else {
            atomic_write(path, data)
        }
    };
    assert!(
        set(&mut m, "a.desktop", false)
            .unwrap_err()
            .contains("readback")
    );
    assert_eq!(fs::read(&m.config).unwrap(), saved);
    assert!(m.saved.as_ref().unwrap()["a.desktop"]);
    fs::remove_file(&m.config).unwrap();
    fs::create_dir(&m.config).unwrap();
    assert!(m.refresh().is_err());
    assert_eq!(m.state()["writable"], false);
    assert!(m.config.is_dir());
}

#[test]
fn hidden_user_stub_inherits_system_metadata_and_enables_by_removing_override() {
    let (_temp, mut m) = setup();
    let system = m.dirs().unwrap().system[0].join("stub.desktop");
    fs::write(
        &system,
        desktop(
            "System startup app",
            "OnlyShowIn=Hyprland;\nIcon=system-icon\n",
        ),
    )
    .unwrap();
    let original = fs::read(&system).unwrap();
    let stub = m.dirs().unwrap().user.join("stub.desktop");
    fs::write(&stub, "[Desktop Entry]\nHidden=true\n").unwrap();
    m.refresh().unwrap();
    let state = m.state();
    assert_eq!(state["entries"][0]["name"], "System startup app");
    assert_eq!(state["entries"][0]["comment"], "Description");
    assert_eq!(state["entries"][0]["icon"], "system-icon");
    assert_eq!(state["entries"][0]["exec"], "/usr/bin/true");
    assert_eq!(state["entries"][0]["origin"], "system");
    assert_eq!(state["entries"][0]["enabled"], false);
    assert_eq!(state["skipped_invalid"], 0);
    assert_eq!(
        fs::read_to_string(&stub).unwrap(),
        "[Desktop Entry]\nHidden=true\n"
    );
    assert_eq!(
        set(&mut m, "stub.desktop", true).unwrap()["system"]["stub.desktop"],
        true
    );
    assert!(!stub.exists());
    assert_eq!(fs::read(system).unwrap(), original);
}

#[test]
fn hidden_user_overrides_merge_filters_with_user_keys_winning() {
    let (_temp, mut m) = setup();
    for (id, filter) in [
        ("type", "Type=Link\n"),
        ("only", "OnlyShowIn=GNOME;\n"),
        ("not", "NotShowIn=Hyprland;\n"),
        ("try", "TryExec=missing-remya-program\n"),
        ("phase", "X-GNOME-Autostart-Phase=Applications\n"),
        ("skip", "X-systemd-skip=true\n"),
    ] {
        let id = format!("{id}.desktop");
        let system = put(&m, true, &id, "");
        let key = load(&system).unwrap();
        let (name, value) = filter.trim_end().split_once('=').unwrap();
        key.set_value(GROUP, name, value);
        fs::write(&system, key.to_data()).unwrap();
        fs::write(
            m.dirs().unwrap().user.join(&id),
            "[Desktop Entry]\nHidden=true\n",
        )
        .unwrap();
    }
    put(
        &m,
        true,
        "wins.desktop",
        "OnlyShowIn=GNOME;\nX-systemd-skip=true\n",
    );
    fs::write(
        m.dirs().unwrap().system[1].join("wins.desktop"),
        desktop(
            "Wrong system entry",
            "X-GNOME-Autostart-Phase=Applications\n",
        ),
    )
    .unwrap();
    fs::write(m.dirs().unwrap().user.join("wins.desktop"), "[Desktop Entry]\nHidden=true\nName=Custom name\nComment=Custom comment\nOnlyShowIn=Hyprland;\nX-systemd-skip=false\n").unwrap();
    m.refresh().unwrap();
    assert_eq!(m.system, BTreeMap::from([("wins.desktop".into(), false)]));
    assert_eq!(m.entries[0].name, "Custom name");
    assert_eq!(m.entries[0].comment, "Custom comment");
    assert_eq!(m.skipped_invalid, 0);
}

#[test]
fn failed_add_readback_removes_app_and_command_files_and_retains_saved_state() {
    let (_temp, mut m) = setup();
    m.refresh().unwrap();
    let saved = fs::read(&m.config).unwrap();
    let application = m.config.with_file_name("excluded.desktop");
    fs::write(&application, desktop("Excluded app", "OnlyShowIn=GNOME;\n")).unwrap();
    m.application_file = Box::new(move |_| Some(application.clone()));
    assert!(
        m.set(IDS[1], r#"{"application":"excluded.desktop"}"#)
            .unwrap_err()
            .contains("readback")
    );
    assert!(!m.dirs().unwrap().user.join("excluded.desktop").exists());
    assert!(m.entries.is_empty() && m.system.is_empty());
    assert_eq!(fs::read(&m.config).unwrap(), saved);
    m.writer = |path, bytes| {
        let data = format!("{}Hidden=true\n", String::from_utf8_lossy(bytes));
        atomic_write(path, data.as_bytes())
    };
    assert!(
        m.set(
            IDS[2],
            r#"{"name":"Bad readback","command":"/usr/bin/true"}"#
        )
        .unwrap_err()
        .contains("readback")
    );
    assert!(
        !m.dirs()
            .unwrap()
            .user
            .join("remya-bad-readback.desktop")
            .exists()
    );
    assert!(m.entries.is_empty() && m.system.is_empty());
    assert_eq!(fs::read(&m.config).unwrap(), saved);
}
