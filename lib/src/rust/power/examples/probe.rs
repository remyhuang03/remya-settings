//! Live probe using isolated preferences/history; exercise mode restores host values.
use remya_settings_power::Power;
fn main() {
    let root = std::path::PathBuf::from(std::env::args().nth(1).expect("isolated root"));
    let idle = std::path::PathBuf::from(std::env::args().nth(2).expect("hypridle.conf"));
    if std::env::args().nth(3).as_deref() == Some("idle-exercise") {
        let original = std::fs::read_to_string(&idle).unwrap();
        let values = remya_settings_power::idle::read(&original).unwrap();
        let wanted = remya_settings_power::idle::Timeouts {
            screen: values.screen + 1,
            sleep: values.sleep + 1,
        };
        let result = remya_settings_power::idle::apply(&idle, &wanted);
        let restore = remya_settings_power::idle::apply(&idle, &values);
        remya_settings_display::atomic_write(&idle, original.as_bytes()).unwrap();
        assert!(restore.is_ok(), "restore failed: {restore:?}");
        assert!(result.is_ok(), "timeout exercise failed: {result:?}");
        assert_eq!(std::fs::read_to_string(&idle).unwrap(), original);
        println!("hypridle timeout/restart roundtrip passed; original file restored byte-for-byte");
        return;
    }
    let mut power = Power::new(root.join("power.json"), idle, root.join("power.sqlite3"));
    let initial = power.read();
    println!("{initial}");
    assert!(initial["error"].is_null());
    if std::env::args().nth(3).as_deref() == Some("exercise") {
        let original = initial["system"]["profile"].as_str().unwrap();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            power.set("battery-saver.07945503", "true").unwrap();
            assert_eq!(
                power.set("battery-saver.743773bd", "true").unwrap()["system"]["profile"],
                "power-saver"
            );
            assert_eq!(
                power.set("battery-saver.743773bd", "false").unwrap()["system"]["profile"],
                original
            );
            power.set("battery-saver.power-source", "true").unwrap();
            power.set("battery-saver.9b0caf70", "100").unwrap();
            for _ in 0..10 {
                power.tick()
            }
            assert_eq!(power.read()["system"]["profile"], "power-saver");
            power.set("battery-saver.9b0caf70", "0").unwrap();
            for _ in 0..10 {
                power.tick()
            }
            assert_eq!(power.read()["system"]["profile"], original);
        }));
        power.set("battery-saver.9b0caf70", "0").unwrap();
        power.set("battery-saver.07945503", "false").unwrap();
        power
            .set("power.5a4f0131", &serde_json::to_string(original).unwrap())
            .unwrap();
        assert!(result.is_ok(), "exercise failed; host profile restored");
        println!("profile, automatic saver, built-in dimming roundtrip passed");
    }
    power.tick();
    println!(
        "{}",
        power
            .query(&format!(
                "{{\"from\":0,\"to\":{}}}",
                remya_settings_power::history::now() + 1
            ))
            .unwrap()
    );
}
