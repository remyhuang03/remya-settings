use super::*;
use std::sync::{Arc, Mutex};

/// A compositor whose options and binds follow `eval` and a reload of `input.lua`.
#[derive(Default)]
struct World {
    options: BTreeMap<&'static str, Value>,
    base_binds: Vec<(u32, String)>,
    binds: Vec<(u32, String)>,
    submap: String,
    file: PathBuf,
    reloads: u32,
    reject: bool,
}

#[derive(Clone, Default)]
struct Fake(Arc<Mutex<World>>);

fn option_from_line(line: &str) -> Option<(&'static config::Opt, Value)> {
    INPUT.options.iter().find_map(|opt| {
        let empty = config::option_line(opt, &Value::Null);
        let (prefix, suffix) = empty.split_once("null")?;
        let inner = line.strip_prefix(prefix)?.strip_suffix(suffix)?;
        Some((opt, serde_json::from_str(inner).ok()?))
    })
}

impl World {
    /// Stores a value the way `descriptions` reports it; layouts are two options.
    fn store(&mut self, opt: &config::Opt, value: Value) {
        if opt.kind == config::Kind::Layouts {
            let (layouts, variants) = xkb::join(&value).unwrap();
            self.options.insert("input:kb_layout", json!(layouts));
            self.options.insert("input:kb_variant", json!(variants));
        } else {
            self.options.insert(opt.name, value);
        }
    }

    fn reload(&mut self) {
        self.reloads += 1;
        self.binds = self.base_binds.clone();
        let file =
            config::parse(&INPUT, &fs::read_to_string(&self.file).unwrap_or_default()).unwrap();
        for (id, value) in file.options {
            let opt = config::option(&id).unwrap();
            self.store(opt, value);
        }
        for keys in file.disabled {
            let (m, k) = keys::parse_combo(&keys).unwrap();
            self.binds
                .retain(|(bm, bk)| !(*bm == m && bk.eq_ignore_ascii_case(&k)));
        }
        for s in file.shortcuts {
            let (m, k) = keys::parse_combo(&s.keys).unwrap();
            self.binds.push((m, k));
        }
    }
}

impl Hypr for Fake {
    fn request(&self, args: &[&str]) -> Result<String, String> {
        let mut w = self.0.lock().unwrap();
        Ok(match args {
            ["-j", "descriptions"] => {
                let mut all: Vec<Value> = INPUT.options
                    .iter()
                    .map(|o| json!({"name": o.name, "current": w.options.get(o.name).cloned().unwrap_or(match o.kind {
                        config::Kind::Bool => json!(false),
                        config::Kind::Text(_) | config::Kind::XkbOptions => json!("[[EMPTY]]"),
                        config::Kind::Layouts => json!("us"),
                        _ => json!(0),
                    })}))
                    .collect();
                all.push(json!({"name": "input:kb_variant", "current": w.options.get("input:kb_variant").cloned().unwrap_or(json!("[[EMPTY]]"))}));
                all.push(json!({"name": "misc:disable_autoreload", "current": true}));
                Value::from(all).to_string()
            }
            ["-j", "binds"] => Value::from(
                w.binds
                    .iter()
                    .map(|(m, k)| json!({"modmask": m, "key": k, "keycode": 0, "submap": "", "description": "", "dispatcher": "HL.Dispatcher(exec_cmd)"}))
                    .collect::<Vec<_>>(),
            )
            .to_string(),
            ["-j", "devices"] => json!({"mice": [{"name": "usb-mouse"}, {"name": "syna-touchpad"}],
                "keyboards": [{"name": "kb", "main": true, "layout": "us", "rules": "", "model": "", "variant": "", "options": ""}]})
            .to_string(),
            ["-j", "submap"] => json!(if w.submap.is_empty() { "default" } else { &w.submap }).to_string(),
            ["reload"] => {
                w.reload();
                "ok".into()
            }
            ["eval", code] => {
                if w.reject {
                    return Ok("error: rejected".into());
                }
                if let Some((opt, value)) = option_from_line(code) {
                    w.options.insert(opt.name, value);
                } else if let Ok(file) = config::parse(&INPUT, code) {
                    for (id, value) in file.options {
                        w.store(config::option(&id).unwrap(), value);
                    }
                } else if code.contains("hl.define_submap") {
                } else if let Some(rest) = code.strip_prefix("hl.dispatch(hl.dsp.submap(\"") {
                    let name = rest.split('"').next().unwrap();
                    w.submap = if name == "reset" { String::new() } else { name.into() };
                } else {
                    return Ok(format!("error: unexpected {code}"));
                }
                "ok".into()
            }
            other => return Err(format!("unexpected {other:?}")),
        })
    }
}

struct Setup {
    _dir: tempfile::TempDir,
    hypr: PathBuf,
    world: Fake,
    input: Input<Fake>,
}

fn setup() -> Setup {
    let dir = tempfile::tempdir().unwrap();
    let hypr = dir.path().join("hypr");
    fs::create_dir_all(&hypr).unwrap();
    fs::write(hypr.join("hyprland.lua"), "hl.config({})\n").unwrap();
    let world = Fake::default();
    {
        let mut w = world.0.lock().unwrap();
        w.file = hypr.join("remya-settings/input.lua");
        w.options.insert("input:sensitivity", json!(0.1));
        w.base_binds = vec![(64, "Q".into()), (64, "J".into())];
        w.binds = w.base_binds.clone();
    }
    let input = Input::new(
        &INPUT,
        world.clone(),
        hypr.clone(),
        dir.path().join("input.toml"),
    );
    Setup {
        _dir: dir,
        hypr,
        world,
        input,
    }
}

#[test]
fn first_use_adopts_live_values_without_writing_hyprland_files() {
    let mut s = setup();
    s.input.refresh().unwrap();
    let state = s.input.state();
    assert_eq!(state["options"]["mouse.pointer-speed"], json!(0.1));
    assert_eq!(state["options"]["mouse.acceleration"], json!(""));
    assert_eq!(state["conflict"], false);
    assert_eq!(state["touchpads"], json!(["syna-touchpad"]));
    assert_eq!(state["key_labels"]["24"], "Q");
    assert!(!s.hypr.join("remya-settings").exists());
    assert_eq!(
        fs::read_to_string(s.hypr.join("hyprland.lua")).unwrap(),
        "hl.config({})\n"
    );
}

#[test]
fn options_added_after_first_use_adopt_the_live_value() {
    let mut s = setup();
    s.input.refresh().unwrap();
    let path = s._dir.path().join("input.toml");
    let mut saved: Saved = toml::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
    saved.options.remove("mouse.pointer-speed");
    saved
        .options
        .insert("mouse.natural-scroll".into(), json!(true));
    fs::write(&path, toml::to_string(&saved).unwrap()).unwrap();
    s.input.refresh().unwrap();
    let state = s.input.state();
    assert_eq!(state["saved"]["mouse.pointer-speed"], json!(0.1));
    // Existing saved values keep their conflict.
    assert_eq!(state["conflicts"], json!(["mouse.natural-scroll"]));
    assert!(
        fs::read_to_string(&path)
            .unwrap()
            .contains("mouse.pointer-speed")
    );
}

#[test]
fn option_changes_apply_live_persist_and_survive_reload() {
    let mut s = setup();
    s.input.set("mouse.pointer-speed", "0.5").unwrap();
    s.input.set("touchpad.tap-to-click", "true").unwrap();
    let file = fs::read_to_string(s.hypr.join("remya-settings/input.lua")).unwrap();
    assert!(file.contains("hl.config({ input = { sensitivity = 0.5 } })"));
    assert!(file.contains("tap_to_click = true"));
    assert!(
        fs::read_to_string(s.hypr.join("hyprland.lua"))
            .unwrap()
            .ends_with(&INPUT.block())
    );
    s.world
        .0
        .lock()
        .unwrap()
        .options
        .insert("input:sensitivity", json!(0.0));
    s.world.0.lock().unwrap().reload();
    let state = s.input.set("mouse.natural-scroll", "true").unwrap();
    assert_eq!(state["system"]["mouse.pointer-speed"], json!(0.5));
    assert_eq!(state["conflict"], false);
}

#[test]
fn keyboard_layouts_and_variants_change_together() {
    let mut s = setup();
    let layouts =
        json!([{"layout": "us", "variant": ""}, {"layout": "de", "variant": "nodeadkeys"}]);
    let state = s
        .input
        .set("language.keyboard-layouts", &layouts.to_string())
        .unwrap();
    assert_eq!(state["system"]["language.keyboard-layouts"], layouts);
    let file = fs::read_to_string(s.hypr.join("remya-settings/input.lua")).unwrap();
    assert!(file.contains(
        "hl.config({ input = { kb_layout = \"us,de\", kb_variant = \",nodeadkeys\" } })"
    ));
    assert_eq!(
        s.world.0.lock().unwrap().options["input:kb_variant"],
        ",nodeadkeys"
    );
    let state = s
        .input
        .set(
            "language.keyboard-options",
            "\"grp:alt_shift_toggle,caps:escape\"",
        )
        .unwrap();
    assert_eq!(
        state["options"]["language.keyboard-options"],
        "grp:alt_shift_toggle,caps:escape"
    );
    s.world.0.lock().unwrap().reload();
    s.input.refresh().unwrap();
    assert_eq!(s.input.state()["conflict"], false);
    for bad in [
        json!([{"layout": "us", "variant": "nodeadkeys"}]),
        json!([{"layout": "no-such-layout"}]),
        json!([]),
    ] {
        let error = s
            .input
            .set("language.keyboard-layouts", &bad.to_string())
            .unwrap_err();
        assert!(error.starts_with("InvalidArgument:"), "{error}");
    }
    assert!(
        s.input
            .set("language.keyboard-options", "\"grp:nope\"")
            .is_err()
    );
    assert_eq!(
        s.input.state()["options"]["language.keyboard-layouts"],
        layouts
    );
}

#[test]
fn invalid_and_rejected_values_change_nothing() {
    let mut s = setup();
    assert!(
        s.input
            .set("mouse.pointer-speed", "3")
            .unwrap_err()
            .starts_with("InvalidArgument:")
    );
    assert!(
        s.input
            .set("mouse.acceleration", "\"custom\"")
            .unwrap_err()
            .starts_with("InvalidArgument:")
    );
    s.world.0.lock().unwrap().reject = true;
    assert!(s.input.set("mouse.pointer-speed", "0.3").is_err());
    assert!(s.input.state()["error"].is_string());
    assert!(!s.hypr.join("remya-settings/input.lua").exists());
    let saved: Saved =
        toml::from_str(&fs::read_to_string(s._dir.path().join("input.toml")).unwrap()).unwrap();
    assert_eq!(saved.options["mouse.pointer-speed"], json!(0.1));
}

#[test]
fn conflicts_block_writes_until_resolved_either_way() {
    let mut s = setup();
    s.input.refresh().unwrap();
    s.world
        .0
        .lock()
        .unwrap()
        .options
        .insert("input:sensitivity", json!(-0.4));
    s.input.refresh().unwrap();
    assert_eq!(s.input.state()["conflicts"], json!(["mouse.pointer-speed"]));
    assert!(s.input.set("mouse.natural-scroll", "true").is_err());
    let state = s.input.resolve("settings").unwrap();
    assert_eq!(state["system"]["mouse.pointer-speed"], json!(0.1));
    s.world
        .0
        .lock()
        .unwrap()
        .options
        .insert("input:sensitivity", json!(-0.4));
    let state = s.input.resolve("system").unwrap();
    assert_eq!(state["options"]["mouse.pointer-speed"], json!(-0.4));
    assert_eq!(state["conflict"], false);
    // The adopted value also replaces the one in Settings' own file, so a reload keeps it.
    let file = fs::read_to_string(s.hypr.join("remya-settings/input.lua")).unwrap();
    assert!(file.contains("sensitivity = -0.4"), "{file}");
    s.world.0.lock().unwrap().reload();
    s.input.refresh().unwrap();
    assert_eq!(s.input.state()["conflict"], false);
}

#[test]
fn shortcuts_are_added_replaced_turned_off_and_removed_with_readback() {
    let mut s = setup();
    let add = |keys: &str, replace: bool| {
        json!({"keys": keys, "action": "command", "command": "foot", "description": "Terminal", "replace": replace}).to_string()
    };
    let error = s
        .input
        .set(ADD, &add("SUPER + code:24", false))
        .unwrap_err();
    assert!(error.starts_with("Conflict:"), "{error}");
    let state = s.input.set(ADD, &add("SUPER + code:24", true)).unwrap();
    assert_eq!(state["custom"][0]["keys"], "SUPER + q");
    assert_eq!(state["disabled"][0]["keys"], "SUPER + Q");
    assert!(
        state["shortcuts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|s| s["custom"] == true)
    );
    assert!(
        s.input
            .set(ADD, &add("q", false))
            .unwrap_err()
            .starts_with("InvalidArgument:")
    );

    let state = s
        .input
        .set(
            DISABLE,
            &json!({"keys": "SUPER + J", "disabled": true}).to_string(),
        )
        .unwrap();
    assert!(
        !state["shortcuts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|s| s["keys"] == "SUPER + J")
    );
    let state = s
        .input
        .set(
            DISABLE,
            &json!({"keys": "SUPER + J", "disabled": false}).to_string(),
        )
        .unwrap();
    assert!(
        state["shortcuts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|s| s["keys"] == "SUPER + J")
    );

    let state = s
        .input
        .set(REMOVE, &json!({"keys": "SUPER + q"}).to_string())
        .unwrap();
    assert_eq!(state["custom"], json!([]));
    assert!(s.world.0.lock().unwrap().reloads >= 4);
}

#[test]
fn hand_edited_files_block_writes() {
    let mut s = setup();
    fs::create_dir_all(s.hypr.join("remya-settings")).unwrap();
    fs::write(s.hypr.join("remya-settings/input.lua"), "os.exit()\n").unwrap();
    let _ = s.input.refresh();
    assert!(s.input.state()["write_blocked"].is_string());
    assert!(s.input.set("mouse.natural-scroll", "true").is_err());
    assert_eq!(
        fs::read_to_string(s.hypr.join("remya-settings/input.lua")).unwrap(),
        "os.exit()\n"
    );
}

#[test]
fn recording_enters_and_leaves_an_empty_submap() {
    let mut s = setup();
    s.input.set(RECORD, "true").unwrap();
    assert_eq!(s.world.0.lock().unwrap().submap, RECORD_SUBMAP);
    assert!(s.input.is_recording());
    s.input.stop_recording().unwrap();
    assert_eq!(s.world.0.lock().unwrap().submap, "");
}

/// A compositor for the desktop group whose workspace rules follow a reload of `desktop.lua`.
#[derive(Clone, Default)]
struct Desk(Arc<Mutex<(PathBuf, Vec<Value>, u32)>>);

impl Hypr for Desk {
    fn request(&self, args: &[&str]) -> Result<String, String> {
        let mut w = self.0.lock().unwrap();
        Ok(match args {
            ["-j", "descriptions"] => {
                let mut all: Vec<Value> = DESKTOP
                    .options
                    .iter()
                    .map(|o| {
                        json!({"name": o.name, "current": match o.kind {
                            config::Kind::Bool => json!(false),
                            config::Kind::Text(_)
                            | config::Kind::FontFamily
                            | config::Kind::BellSound => json!("[[EMPTY]]"),
                            config::Kind::Color | config::Kind::Rgba => json!("ff000000"),
                            config::Kind::Vec2(..) => json!([0, 0]),
                            _ => json!(0),
                        }})
                    })
                    .collect();
                all.push(json!({"name": "misc:disable_autoreload", "current": true}));
                Value::from(all).to_string()
            }
            ["-j", "workspacerules"] => Value::from(w.1.clone()).to_string(),
            ["-j", "clients"] => json!([
                {"class": "org.gnome.Nautilus", "title": "Home", "mapped": true},
                {"class": "org.gnome.Nautilus", "title": "Downloads", "mapped": true},
                {"class": "", "title": "popup"},
            ])
            .to_string(),
            ["-j", "configerrors"] => {
                let text = fs::read_to_string(&w.0).unwrap_or_default();
                // Stands in for Hyprland refusing a value it cannot load.
                json!([if text.contains("REJECT") {
                    "remya-settings/desktop.lua:3: bad"
                } else {
                    ""
                }])
                .to_string()
            }
            ["eval", code] if code.starts_with("hl.window_rule({ enabled = false, ") => {
                if code.contains("Bogus") {
                    "error: unknown field".into()
                } else {
                    "ok".into()
                }
            }
            ["-j", "monitors"] => json!([{"name": "DP-1", "description": "Wide", "x": 0, "y": 0,
                "width": 3840, "height": 2160, "scale": 2.0, "transform": 1,
                "activeWorkspace": {"name": "1"}, "specialWorkspace": {"name": ""}}])
            .to_string(),
            ["-j", "workspaces"] => json!([{"id": 1, "name": "1", "monitor": "DP-1",
                "windows": 2, "ispersistent": false}])
            .to_string(),
            ["reload"] => {
                w.2 += 1;
                let file =
                    config::parse(&DESKTOP, &fs::read_to_string(&w.0).unwrap_or_default()).unwrap();
                // Hyprland reports only the fields a rule sets, under camelCase names.
                w.1 = file
                    .rules
                    .iter()
                    .map(|r| {
                        let mut e = json!({"workspaceString": r.workspace, "enabled": true});
                        if !r.monitor.is_empty() {
                            e["monitor"] = json!(r.monitor);
                        }
                        if r.default {
                            e["default"] = json!(true);
                        }
                        if r.persistent {
                            e["persistent"] = json!(true);
                        }
                        if !r.default_name.is_empty() {
                            e["defaultName"] = json!(r.default_name);
                        }
                        e
                    })
                    .collect();
                "ok".into()
            }
            other => return Err(format!("unexpected {other:?}")),
        })
    }
}

#[test]
fn workspace_rules_are_validated_written_reloaded_and_reconciled() {
    let dir = tempfile::tempdir().unwrap();
    let hypr = dir.path().join("hypr");
    fs::create_dir_all(&hypr).unwrap();
    fs::write(hypr.join("hyprland.lua"), "hl.config({})\n").unwrap();
    let owned = hypr.join("remya-settings/desktop.lua");
    let world = Desk::default();
    world.0.lock().unwrap().0 = owned.clone();
    // A rule from another file is shown but never claimed by Settings.
    world.0.lock().unwrap().1 = vec![json!({"workspaceString": "9", "persistent": true})];
    let mut desk = Input::new(
        &DESKTOP,
        world.clone(),
        hypr.clone(),
        dir.path().join("desktop.toml"),
    );
    desk.refresh().unwrap();
    let state = desk.state();
    assert_eq!(state["rules"], json!([]));
    assert_eq!(state["live_rules"][0]["settings"], false);
    // A portrait 4K display at scale 2 is 1080 by 1920 desktop pixels.
    assert_eq!(state["monitors"][0]["width"], json!(1080.0));
    assert_eq!(state["monitors"][0]["height"], json!(1920.0));
    assert_eq!(state["workspaces"][0]["windows"], 2);
    assert!(!owned.exists());

    let set = |desk: &mut Input<Desk>, rule: Value| desk.set(RULE_SET, &rule.to_string());
    for bad in [
        json!({"workspace": "web"}),
        json!({"workspace": "name:"}),
        json!({"workspace": "0"}),
        json!({"workspace": "1", "monitor": "DP 1"}),
        json!({"workspace": "1", "default": true}),
        json!({"workspace": "special:x", "monitor": "DP-1", "default": true}),
        json!({"workspace": "name:chat", "default_name": "Chat"}),
        json!({"workspace": "1", "gaps_in": 4}),
    ] {
        let error = set(&mut desk, bad.clone()).unwrap_err();
        assert!(error.starts_with("InvalidArgument:"), "{bad}: {error}");
    }
    assert!(!owned.exists());

    let state = set(
        &mut desk,
        json!({"workspace": "2", "monitor": "DP-1", "persistent": true, "default": true}),
    )
    .unwrap();
    assert_eq!(state["rules"][0]["workspace"], "2");
    assert_eq!(state["live_rules"][0]["settings"], true);
    assert!(fs::read_to_string(&owned).unwrap().contains(
        "hl.workspace_rule({ workspace = \"2\", monitor = \"DP-1\", default = true, persistent = true })"
    ));
    // A second default on the same display takes over; renaming onto a used workspace is refused.
    set(
        &mut desk,
        json!({"workspace": "name:chat", "persistent": true}),
    )
    .unwrap();
    let state = set(
        &mut desk,
        json!({"workspace": "3", "monitor": "DP-1", "default": true}),
    )
    .unwrap();
    assert_eq!(state["rules"][0]["default"], json!(null));
    assert_eq!(state["rules"][2]["default"], true);
    let error = set(&mut desk, json!({"workspace": "3", "previous": "2"})).unwrap_err();
    assert!(error.starts_with("InvalidArgument:"), "{error}");
    // Editing keeps the rule's place and drops removed fields once Hyprland reports them gone.
    let state = set(
        &mut desk,
        json!({"workspace": "4", "default_name": "Web", "previous": "2"}),
    )
    .unwrap();
    assert_eq!(
        state["rules"][0],
        json!({"workspace": "4", "default_name": "Web"})
    );
    assert!(
        !fs::read_to_string(&owned)
            .unwrap()
            .contains("workspace = \"2\"")
    );

    // A hand change in Settings' own file is a conflict until one side is chosen.
    let text = fs::read_to_string(&owned).unwrap();
    fs::write(&owned, text.replace("\"Web\"", "\"Mail\"")).unwrap();
    desk.refresh().unwrap();
    assert_eq!(desk.state()["conflicts"], json!(["workspaces"]));
    assert!(set(&mut desk, json!({"workspace": "5"})).is_err());
    let state = desk.resolve("settings").unwrap();
    assert_eq!(state["conflict"], false);
    assert!(fs::read_to_string(&owned).unwrap().contains("\"Web\""));
    fs::write(
        &owned,
        fs::read_to_string(&owned)
            .unwrap()
            .replace("\"Web\"", "\"Mail\""),
    )
    .unwrap();
    let state = desk.resolve("system").unwrap();
    assert_eq!(state["rules"][0]["default_name"], "Mail");

    let state = desk
        .set(RULE_REMOVE, &json!({"workspace": "name:chat"}).to_string())
        .unwrap();
    assert_eq!(state["rules"].as_array().unwrap().len(), 2);
    assert!(
        desk.set(RULE_REMOVE, &json!({"workspace": "name:chat"}).to_string())
            .is_err()
    );
    assert!(world.0.lock().unwrap().2 >= 5);
}

#[test]
fn window_rules_and_environment_are_checked_written_and_reconciled() {
    let dir = tempfile::tempdir().unwrap();
    let hypr = dir.path().join("hypr");
    fs::create_dir_all(&hypr).unwrap();
    fs::write(hypr.join("hyprland.lua"), "hl.config({})\n").unwrap();
    let owned = hypr.join("remya-settings/desktop.lua");
    let world = Desk::default();
    world.0.lock().unwrap().0 = owned.clone();
    let mut desk = Input::new(
        &DESKTOP,
        world.clone(),
        hypr.clone(),
        dir.path().join("desktop.toml"),
    );
    desk.refresh().unwrap();
    let state = desk.state();
    assert_eq!(state["window_rules"], json!([]));
    assert_eq!(
        state["windows"],
        json!([{"class": "org.gnome.Nautilus", "title": "Home"}])
    );

    let set = |desk: &mut Input<Desk>, id, v: Value| desk.set(id, &v.to_string());
    let rule = json!({"class": "org.gnome.Nautilus", "float": true, "size": [60, 50], "workspace": "3", "silent": true});
    let state = set(&mut desk, WINDOW_RULE_SET, rule.clone()).unwrap();
    assert_eq!(state["window_rules"][0], rule);
    let text = fs::read_to_string(&owned).unwrap();
    assert!(text.contains(r#"hl.window_rule({ match = { class = "^(org\\.gnome\\.Nautilus)$" }, float = true, size = { "(monitor_w*0.6)", "(monitor_h*0.5)" }, workspace = "3 silent" })"#), "{text}");
    let reloads = world.0.lock().unwrap().2;
    // Duplicates, unknown fields and Hyprland's own refusal leave the file as it was.
    assert!(
        set(
            &mut desk,
            WINDOW_RULE_SET,
            json!({"class": "org.gnome.Nautilus", "pin": true, "previous": {"class": "foot"}})
        )
        .is_err()
    );
    assert!(
        set(
            &mut desk,
            WINDOW_RULE_SET,
            json!({"class": "a", "no_anim": true})
        )
        .unwrap_err()
        .starts_with("InvalidArgument:")
    );
    assert!(
        set(
            &mut desk,
            WINDOW_RULE_SET,
            json!({"class": "Bogus", "pin": true})
        )
        .unwrap_err()
        .contains("unknown field")
    );
    assert_eq!(fs::read_to_string(&owned).unwrap(), text);
    // Editing in place by the previous match.
    let state = set(
        &mut desk,
        WINDOW_RULE_SET,
        json!({"title": "Save As", "float": true, "center": true,
        "previous": {"class": "org.gnome.Nautilus"}}),
    )
    .unwrap();
    assert_eq!(
        state["window_rules"],
        json!([{"title": "Save As", "float": true, "center": true}])
    );

    let state = set(
        &mut desk,
        ENV_SET,
        json!({"name": "GDK_BACKEND", "value": "wayland,x11"}),
    )
    .unwrap();
    assert_eq!(
        state["env"],
        json!([{"name": "GDK_BACKEND", "value": "wayland,x11"}])
    );
    assert!(world.0.lock().unwrap().2 > reloads);
    assert!(
        set(
            &mut desk,
            ENV_SET,
            json!({"name": "XCURSOR_SIZE", "value": "24"})
        )
        .is_err()
    );
    let before = fs::read_to_string(&owned).unwrap();
    let error = set(
        &mut desk,
        ENV_SET,
        json!({"name": "SDL_VIDEODRIVER", "value": "REJECT"}),
    )
    .unwrap_err();
    assert!(error.contains("rejected"), "{error}");
    assert_eq!(fs::read_to_string(&owned).unwrap(), before);
    assert_eq!(desk.state()["env"].as_array().unwrap().len(), 1);
    let state = set(
        &mut desk,
        ENV_SET,
        json!({"name": "GDK_BACKEND", "value": "wayland", "previous": "GDK_BACKEND"}),
    )
    .unwrap();
    assert_eq!(state["env"][0]["value"], "wayland");

    // A hand edit is a conflict on its own ID until resolved.
    fs::write(
        &owned,
        fs::read_to_string(&owned)
            .unwrap()
            .replace("\"wayland\"", "\"x11\""),
    )
    .unwrap();
    desk.refresh().unwrap();
    assert_eq!(desk.state()["conflicts"], json!(["environment"]));
    let state = desk.resolve("system").unwrap();
    assert_eq!(state["env"][0]["value"], "x11");

    let state = set(&mut desk, ENV_REMOVE, json!({"name": "GDK_BACKEND"})).unwrap();
    assert_eq!(state["env"], json!([]));
    let state = set(&mut desk, WINDOW_RULE_REMOVE, json!({"title": "Save As"})).unwrap();
    assert_eq!(state["window_rules"], json!([]));
    assert!(set(&mut desk, WINDOW_RULE_REMOVE, json!({"title": "Save As"})).is_err());
}
