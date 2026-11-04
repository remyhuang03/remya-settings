//! Run with `cargo test -p remya_settings_sound --test isolated_pulse -- --ignored`.
//! Every process and native connection uses a new private runtime directory.
use remya_settings_sound::{Backend, Direction, Sound, pulse::RealPulse};
use serde_json::json;
use std::{
    path::Path,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

struct Server(Vec<Child>);
impl Drop for Server {
    fn drop(&mut self) {
        for child in self.0.iter_mut().rev() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
fn command(runtime: &Path, program: &str) -> Command {
    let mut cmd = Command::new(program);
    cmd.env("XDG_CONFIG_HOME", runtime.join("config"))
        .env("XDG_STATE_HOME", runtime.join("state"))
        .env("XDG_CACHE_HOME", runtime.join("cache"))
        .env(
            "DBUS_SESSION_BUS_ADDRESS",
            format!("unix:path={}/no-bus", runtime.display()),
        )
        .env("XDG_RUNTIME_DIR", runtime)
        .env("PIPEWIRE_RUNTIME_DIR", runtime)
        .env("PIPEWIRE_REMOTE", "pipewire-0")
        .env("PULSE_RUNTIME_PATH", runtime.join("pulse"))
        .env(
            "PULSE_SERVER",
            format!("unix:{}/pulse/native", runtime.display()),
        )
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    cmd
}
fn wait_socket(path: &Path) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !path.exists() {
        assert!(
            Instant::now() < deadline,
            "Audio test server did not create {}",
            path.display()
        );
        thread::sleep(Duration::from_millis(20));
    }
}

#[test]
#[ignore = "requires pipewire, pipewire-pulse, WirePlumber, pactl and pacat; starts a private audio server"]
fn native_controls_and_stream_routes_use_private_audio_server() {
    let temp = tempfile::Builder::new()
        .prefix("remya-audio-test-")
        .tempdir()
        .unwrap();
    let runtime = temp.path();
    let mut server = Server(vec![command(runtime, "pipewire").spawn().unwrap()]);
    wait_socket(&runtime.join("pipewire-0"));
    server
        .0
        .push(command(runtime, "pipewire-pulse").spawn().unwrap());
    wait_socket(&runtime.join("pulse/native"));
    server.0.push(
        command(runtime, "wireplumber")
            .args(["--profile", "policy"])
            .spawn()
            .unwrap(),
    );
    thread::sleep(Duration::from_millis(150));
    for name in ["remya_test_a", "remya_test_b"] {
        assert!(
            command(runtime, "pactl")
                .args([
                    "load-module",
                    "module-null-sink",
                    &format!("sink_name={name}")
                ])
                .status()
                .unwrap()
                .success()
        );
    }
    // Test process environment is private; native libpulse never reaches the desktop socket.
    unsafe {
        std::env::set_var(
            "PULSE_SERVER",
            format!("unix:{}/pulse/native", runtime.display()),
        );
    }
    let mut backend = RealPulse;
    let actual = backend.read().unwrap();
    assert!(
        actual
            .devices
            .iter()
            .all(|d| d.name.starts_with("remya_test_"))
    );
    assert_eq!(
        actual
            .devices
            .iter()
            .filter(|d| d.direction == Direction::Output)
            .count(),
        2
    );
    let config = runtime.join("sound.toml");
    let mut sound = Sound::new(RealPulse);
    sound.refresh().unwrap();
    let output = "remya_test_b";
    let input = "remya_test_b.monitor";
    sound
        .set("sound.output-device", &json!({"name":output}).to_string())
        .unwrap();
    sound
        .set("sound.input-device", &json!({"name":input}).to_string())
        .unwrap();
    sound
        .set("sound.output-volume", r#"{"percent":37}"#)
        .unwrap();
    sound
        .set("sound.output-muted", r#"{"muted":true}"#)
        .unwrap();
    sound
        .set("sound.input-volume", r#"{"percent":45}"#)
        .unwrap();
    sound.set("sound.input-muted", r#"{"muted":true}"#).unwrap();
    let readback = backend.read().unwrap();
    assert_eq!(readback.default_output.as_deref(), Some(output));
    assert_eq!(readback.default_input.as_deref(), Some(input));
    for (name, expected) in [(output, 37.), (input, 45.)] {
        let device = readback.devices.iter().find(|d| d.name == name).unwrap();
        assert!((device.percent() - expected).abs() < 0.01);
        assert!(device.preferences.muted);
    }
    let mut external = readback
        .devices
        .iter()
        .find(|d| d.name == output)
        .unwrap()
        .preferences
        .clone();
    external.muted = false;
    backend
        .set_device(Direction::Output, output, &external, "sound.output-muted")
        .unwrap();
    sound.refresh().unwrap();
    assert!(
        !sound.state()["system"]["devices"]
            .as_array()
            .unwrap()
            .iter()
            .find(|d| d["name"] == output)
            .unwrap()["preferences"]["muted"]
            .as_bool()
            .unwrap()
    );
    assert!(!config.exists());
    // Stale fields in a request must not overwrite another tool's live changes.
    external.channels.fill(16384);
    external.muted = true;
    backend
        .set_device(Direction::Output, output, &external, "sound.output-volume")
        .unwrap();
    let current = backend.read().unwrap();
    let current = current.devices.iter().find(|d| d.name == output).unwrap();
    assert!(!current.preferences.muted);
    external.channels.fill(65536);
    backend
        .set_device(Direction::Output, output, &external, "sound.output-muted")
        .unwrap();
    let current = backend.read().unwrap();
    let current = current.devices.iter().find(|d| d.name == output).unwrap();
    assert_eq!(
        current.preferences.channels,
        vec![16384; external.channels.len()]
    );
    assert!(current.preferences.muted);
    server.0.push(
        command(runtime, "pacat")
            .args([
                "--playback",
                "--device=remya_test_a",
                "--rate=48000",
                "--channels=2",
                "--format=s16le",
                "/dev/zero",
            ])
            .spawn()
            .unwrap(),
    );
    let deadline = Instant::now() + Duration::from_secs(5);
    let stream = loop {
        let state = backend.read().unwrap();
        if let Some(s) = state
            .streams
            .into_iter()
            .find(|s| s.direction == Direction::Output)
        {
            break s;
        }
        assert!(
            Instant::now() < deadline,
            "Test playback stream did not appear"
        );
        thread::sleep(Duration::from_millis(20));
    };
    let change = |value: serde_json::Value| {
        let mut body = json!({"index":stream.index,"client":stream.client,"direction":"output"});
        body.as_object_mut()
            .unwrap()
            .extend(value.as_object().unwrap().clone());
        body.to_string()
    };
    sound
        .set("sound.stream-volume", &change(json!({"percent":22})))
        .unwrap();
    sound
        .set("sound.stream-muted", &change(json!({"muted":true})))
        .unwrap();
    sound
        .set("sound.stream-device", &change(json!({"device":output})))
        .unwrap();
    assert!(!config.exists());
    let state = backend.read().unwrap();
    let observed = state
        .streams
        .iter()
        .find(|s| s.index == stream.index)
        .unwrap();
    assert_eq!(observed.device, output);
    assert!(observed.preferences.muted);
    assert!(
        (remya_settings_sound::volume_percent(&observed.preferences.channels) - 22.).abs() < 0.01
    );
}
