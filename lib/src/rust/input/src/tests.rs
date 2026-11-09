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
    fn reload(&mut self) {
        self.reloads += 1;
        self.binds = self.base_binds.clone();
        let file =
            config::parse(&INPUT, &fs::read_to_string(&self.file).unwrap_or_default()).unwrap();
        for (id, value) in file.options {
            let opt = config::option(&id).unwrap();
            self.options.insert(opt.name, value);
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
                        config::Kind::Text(_) => json!("[[EMPTY]]"),
                        _ => json!(0),
                    })}))
                    .collect();
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
