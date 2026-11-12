//! CUPS printers and their queues through the CUPS command-line tools.
//!
//! Printers are live CUPS state: Settings keeps no copy, so there is nothing to
//! reconcile. Every write is checked against a fresh listing and read back.
use remya_settings_display::run_bytes;
use serde_json::{Value, json};
use std::{
    thread,
    time::{Duration, Instant},
};

pub const DEFAULT: &str = "printers.default";
pub const TEST_PAGE: &str = "printers.test-page";
pub const PAUSE: &str = "printers.pause";
pub const CANCEL_JOB: &str = "printers.cancel-job";
pub const REMOVE: &str = "printers.remove";
pub const IDS: [&str; 5] = [DEFAULT, TEST_PAGE, PAUSE, CANCEL_JOB, REMOVE];
const TEST_FILE: &str = "/usr/share/cups/data/testprint";

pub fn is_setting(id: &str) -> bool {
    id == "printers" || IDS.contains(&id)
}

fn invalid(message: impl std::fmt::Display) -> String {
    format!("InvalidArgument:{message}")
}

/// Runs one CUPS tool and returns its standard output.
pub trait Cups: Send {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String>;
}

pub struct RealCups;
impl Cups for RealCups {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        // The C locale keeps lpstat's wording stable for the parser.
        let bytes = run_bytes(program, args, &[("LC_ALL", "C")], Duration::from_secs(10))?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }
}

/// `lpstat -l -p`: one block per printer, starting at a `printer` line.
fn printers(text: &str) -> Vec<Value> {
    let mut out: Vec<Value> = vec![];
    let mut header = true;
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("printer ") {
            let mut words = rest.split_whitespace();
            let name = words.next().unwrap_or_default();
            let state = if rest.contains(" disabled since ") {
                "stopped"
            } else if rest.contains(" now printing ") {
                "printing"
            } else {
                "idle"
            };
            out.push(json!({"name": name, "state": state, "reason": "", "description": "", "location": ""}));
            header = true;
            continue;
        }
        let Some(printer) = out.last_mut() else {
            continue;
        };
        let line = line.trim();
        if let Some(value) = line.strip_prefix("Description:") {
            printer["description"] = json!(value.trim());
        } else if let Some(value) = line.strip_prefix("Location:") {
            printer["location"] = json!(value.trim());
        } else if line.starts_with("Form mounted:") {
            header = false;
        } else if header && !line.is_empty() {
            // lpstat prints the printer state message before the attribute lines.
            printer["reason"] = json!(line);
        }
    }
    out
}

/// The device URI of `name` from `lpstat -v`.
fn device(text: &str, name: &str) -> String {
    text.lines()
        .find_map(|l| l.strip_prefix(&format!("device for {name}: ")))
        .unwrap_or_default()
        .to_owned()
}

/// `lpstat -o` lines: `NAME-ID  user  size  date`.
fn jobs(text: &str, name: &str) -> Vec<Value> {
    text.lines()
        .filter_map(|l| {
            let mut words = l.split_whitespace();
            let id = words.next()?;
            let (printer, number) = id.rsplit_once('-')?;
            (printer == name && number.parse::<u32>().is_ok()).then(|| {
                json!({
                    "id": id,
                    "user": words.next().unwrap_or_default(),
                    "size": words.next().and_then(|s| s.parse::<u64>().ok()),
                })
            })
        })
        .collect()
}

pub fn parse(list: &str, devices: &str, accepting: &str, default: &str, queue: &str) -> Value {
    let default = default
        .lines()
        .find_map(|l| l.strip_prefix("system default destination: "))
        .map(str::trim);
    let printers: Vec<Value> = printers(list)
        .into_iter()
        .map(|mut p| {
            let name = p["name"].as_str().unwrap_or_default().to_owned();
            p["uri"] = json!(device(devices, &name));
            p["accepting"] = json!(
                accepting
                    .lines()
                    .any(|l| l.starts_with(&format!("{name} accepting requests")))
            );
            p["default"] = json!(default == Some(name.as_str()));
            p["jobs"] = json!(jobs(queue, &name));
            p
        })
        .collect();
    json!({"printers": printers, "default": default, "error": null})
}

pub struct Printers<C> {
    cups: C,
}

impl<C: Cups> Printers<C> {
    pub fn new(cups: C) -> Self {
        Self { cups }
    }

    /// An lpstat listing; CUPS reports an empty one as an error.
    fn lpstat(&self, args: &[&str]) -> Result<String, String> {
        match self.cups.run("lpstat", args) {
            Err(e) if e.contains("No destinations added") => Ok(String::new()),
            other => other,
        }
    }

    pub fn read(&self) -> Result<Value, String> {
        Ok(parse(
            &self.lpstat(&["-l", "-p"])?,
            &self.lpstat(&["-v"])?,
            &self.lpstat(&["-a"])?,
            &self.lpstat(&["-d"])?,
            &self.lpstat(&["-o"])?,
        ))
    }

    pub fn state(&self) -> Value {
        self.read()
            .unwrap_or_else(|e| json!({"printers": [], "default": null, "error": e}))
    }

    pub fn setting_value(&self, id: &str) -> Value {
        let state = self.state();
        json!({"id": id, "availability": "available", "reason": "Uses CUPS.", "value": state})
    }

    /// Polls fresh state until `check` holds, for at most two seconds.
    fn confirm(&self, what: &str, check: impl Fn(&Value) -> bool) -> Result<Value, String> {
        let started = Instant::now();
        loop {
            let state = self.read()?;
            if check(&state) {
                return Ok(state);
            }
            if started.elapsed() > Duration::from_secs(2) {
                return Err(format!("CUPS did not report the change: {what}"));
            }
            thread::sleep(Duration::from_millis(100));
        }
    }

    pub fn set(&self, id: &str, input: &str) -> Result<Value, String> {
        let request: Value = serde_json::from_str(input).map_err(|_| invalid("Expected JSON"))?;
        let state = self.read()?;
        let find = |state: &Value, name: &str| {
            state["printers"]
                .as_array()
                .and_then(|all| all.iter().find(|p| p["name"] == name).cloned())
        };
        if id == CANCEL_JOB {
            let job = request["id"]
                .as_str()
                .ok_or_else(|| invalid("Expected {\"id\":\"<printer>-<number>\"}"))?;
            let queued = |state: &Value| {
                state["printers"].as_array().is_some_and(|all| {
                    all.iter()
                        .flat_map(|p| p["jobs"].as_array().cloned().unwrap_or_default())
                        .any(|j| j["id"] == job)
                })
            };
            if job.starts_with('-') || !queued(&state) {
                return Err(invalid("No queued print job has that ID"));
            }
            self.cups.run("cancel", &[job])?;
            return self.confirm("job cancelled", |s| !queued(s));
        }
        let name = request["name"]
            .as_str()
            .ok_or_else(|| invalid("Expected {\"name\":...}"))?;
        // The listing check also keeps a name from being read as a command-line option.
        if name.starts_with('-') || find(&state, name).is_none() {
            return Err(invalid("No printer has that name"));
        }
        match id {
            DEFAULT => {
                self.cups.run("lpoptions", &["-d", name])?;
                self.confirm("default printer", |s| s["default"] == name)
            }
            TEST_PAGE => {
                let out = self.cups.run("lp", &["-d", name, TEST_FILE])?;
                if !out.contains("request id is ") {
                    return Err(format!("CUPS did not accept the test page: {}", out.trim()));
                }
                self.read()
            }
            PAUSE => {
                let paused = request["paused"]
                    .as_bool()
                    .ok_or_else(|| invalid("Expected paused"))?;
                self.cups
                    .run(if paused { "cupsdisable" } else { "cupsenable" }, &[name])?;
                self.confirm("printer state", |s| {
                    find(s, name).is_some_and(|p| (p["state"] == "stopped") == paused)
                })
            }
            REMOVE => {
                self.cups.run("lpadmin", &["-x", name])?;
                self.confirm("printer removed", |s| find(s, name).is_none())
            }
            _ => Err(invalid("Unknown setting")),
        }
    }
}

#[cfg(test)]
mod tests;
