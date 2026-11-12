use super::*;
use std::sync::Mutex;

const LIST: &str =
    "printer HP_Smart_Tank_510_series is idle.  enabled since Sat Sep 12 23:15:18 2026
\tForm mounted:
\tContent types: any
\tDescription: HP Smart Tank 510 series
\tAlerts: none
\tLocation: 
\tConnection: direct
";
const STOPPED: &str = "printer Office disabled since Thu Nov 12 14:00:00 2026 -
\tPaused
\tForm mounted:
\tDescription: Office laser
\tLocation: Room 2
";
const DEVICES: &str = "device for HP_Smart_Tank_510_series: usb://HP/Smart%20Tank%20510%20series?serial=CN45S540D6&interface=1
device for Office: ipp://office.local/ipp/print
";
const ACCEPTING: &str = "HP_Smart_Tank_510_series accepting requests since Sat Sep 12 23:15:18 2026
Office not accepting requests since Thu Nov 12 14:00:00 2026 -
\tRejecting Jobs
";

#[derive(Default)]
struct Fake {
    stopped: Mutex<bool>,
    default: Mutex<String>,
    jobs: Mutex<String>,
    calls: Mutex<Vec<String>>,
    fail: Option<&'static str>,
}

impl Cups for Fake {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let call = format!("{program} {}", args.join(" "));
        self.calls.lock().unwrap().push(call.clone());
        if let Some(message) = self.fail.filter(|_| program != "lpstat") {
            return Err(message.into());
        }
        let stopped = *self.stopped.lock().unwrap();
        Ok(match call.as_str() {
            "lpstat -l -p" if stopped => {
                format!("{LIST}{STOPPED}").replace("is idle.", "disabled since X -\n\tPaused\n")
            }
            "lpstat -l -p" => format!("{LIST}{STOPPED}"),
            "lpstat -v" => DEVICES.into(),
            "lpstat -a" => ACCEPTING.into(),
            "lpstat -d" => match self.default.lock().unwrap().as_str() {
                "" => "no system default destination\n".into(),
                name => format!("system default destination: {name}\n"),
            },
            "lpstat -o" => self.jobs.lock().unwrap().clone(),
            _ if program == "lpoptions" => {
                *self.default.lock().unwrap() = args[1].into();
                String::new()
            }
            _ if program == "cupsdisable" => {
                *self.stopped.lock().unwrap() = true;
                String::new()
            }
            _ if program == "cupsenable" => {
                *self.stopped.lock().unwrap() = false;
                String::new()
            }
            _ if program == "cancel" => {
                self.jobs.lock().unwrap().clear();
                String::new()
            }
            _ if program == "lp" => "request id is HP_Smart_Tank_510_series-7 (1 file(s))\n".into(),
            _ => return Err(format!("unexpected {call}")),
        })
    }
}

const HP: &str = "HP_Smart_Tank_510_series";

#[test]
fn real_lpstat_output_parses() {
    let printers = Printers::new(Fake {
        jobs: Mutex::new(format!("{HP}-12  remy  1024  Thu Nov 12 14:00:00 2026\n")),
        ..Fake::default()
    });
    let state = printers.read().unwrap();
    let hp = &state["printers"][0];
    assert_eq!(hp["name"], HP);
    assert_eq!(hp["state"], "idle");
    assert_eq!(hp["description"], "HP Smart Tank 510 series");
    assert_eq!(hp["location"], "");
    assert_eq!(hp["reason"], "");
    assert_eq!(hp["accepting"], true);
    assert_eq!(hp["default"], false);
    assert!(hp["uri"].as_str().unwrap().starts_with("usb://HP/"));
    assert_eq!(
        hp["jobs"],
        json!([{"id": format!("{HP}-12"), "user": "remy", "size": 1024}])
    );
    let office = &state["printers"][1];
    assert_eq!(office["state"], "stopped");
    assert_eq!(office["reason"], "Paused");
    assert_eq!(office["location"], "Room 2");
    assert_eq!(office["accepting"], false);
    assert_eq!(office["jobs"], json!([]));
    assert_eq!(state["default"], Value::Null);
}

#[test]
fn writes_are_validated_and_read_back() {
    let printers = Printers::new(Fake {
        jobs: Mutex::new(format!("{HP}-12  remy  1024  date\n")),
        ..Fake::default()
    });
    let set = |id, value: Value| printers.set(id, &value.to_string());
    assert_eq!(set(DEFAULT, json!({"name": HP})).unwrap()["default"], HP);
    assert_eq!(
        set(PAUSE, json!({"name": HP, "paused": true})).unwrap()["printers"][0]["state"],
        "stopped"
    );
    assert_eq!(
        set(PAUSE, json!({"name": HP, "paused": false})).unwrap()["printers"][0]["state"],
        "idle"
    );
    assert!(set(TEST_PAGE, json!({"name": HP})).is_ok());
    assert_eq!(
        set(CANCEL_JOB, json!({"id": format!("{HP}-12")})).unwrap()["printers"][0]["jobs"],
        json!([])
    );
    for (id, value) in [
        (DEFAULT, json!({"name": "Missing"})),
        (DEFAULT, json!({"name": "-x"})),
        (PAUSE, json!({"name": HP})),
        (CANCEL_JOB, json!({"id": format!("{HP}-12")})),
        (REMOVE, json!({})),
    ] {
        assert!(set(id, value).unwrap_err().starts_with("InvalidArgument:"));
    }
    let calls = printers.cups.calls.lock().unwrap();
    assert!(calls.contains(&format!("lp -d {HP} {TEST_FILE}")));
    assert!(
        !calls
            .iter()
            .any(|c| c.contains("Missing") || c.contains("-x"))
    );
}

#[test]
fn cups_failures_are_surfaced() {
    let printers = Printers::new(Fake {
        fail: Some("lpadmin: Forbidden"),
        ..Fake::default()
    });
    assert_eq!(
        printers.set(REMOVE, &json!({"name": HP}).to_string()),
        Err("lpadmin: Forbidden".into())
    );
    assert!(printers.read().unwrap()["printers"][0]["name"] == HP);
}

#[test]
fn an_empty_or_unreachable_cups_reads_cleanly() {
    struct Empty(&'static str);
    impl Cups for Empty {
        fn run(&self, _: &str, _: &[&str]) -> Result<String, String> {
            Err(self.0.into())
        }
    }
    let state = Printers::new(Empty("lpstat: No destinations added.")).state();
    assert_eq!(state["printers"], json!([]));
    assert_eq!(state["error"], Value::Null);
    let state = Printers::new(Empty("lpstat: Scheduler is not running.")).state();
    assert_eq!(state["error"], "lpstat: Scheduler is not running.");
}
