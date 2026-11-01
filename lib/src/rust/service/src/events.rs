//! Refreshes display state as soon as Hyprland reports an output change.
use crate::{signal, state::State};
use remya_settings_display::Hyprctl;
use std::{
    io::{BufRead, BufReader},
    os::unix::net::UnixStream,
    path::PathBuf,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

fn is_output_event(line: &str) -> bool {
    ["monitoradded", "monitorremoved", "configreloaded"]
        .iter()
        .any(|event| line.starts_with(event))
}

fn socket() -> Option<PathBuf> {
    let runtime = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?);
    Some(
        runtime
            .join("hypr")
            .join(Hyprctl::instance().ok()?)
            .join(".socket2.sock"),
    )
}

pub fn watch(state: Arc<Mutex<State>>, bus: gio::DBusConnection) {
    thread::spawn(move || {
        loop {
            // Absent while Hyprland restarts; reconnect rather than ending the watch.
            let Some(stream) = socket().and_then(|path| UnixStream::connect(path).ok()) else {
                thread::sleep(Duration::from_secs(5));
                continue;
            };
            for line in BufReader::new(stream).lines() {
                let Ok(line) = line else { break };
                if !is_output_event(&line) {
                    continue;
                }
                // Let a burst of hot-plug events settle before reading the outputs.
                thread::sleep(Duration::from_millis(500));
                let mut state = state.lock().unwrap();
                let _ = state.display.refresh();
                signal(&bus, "display", &state.display.state());
                let _ = state.background.refresh();
                signal(&bus, "background", &state.background.state());
            }
            thread::sleep(Duration::from_secs(1));
        }
    });
}

#[cfg(test)]
mod tests {
    use super::is_output_event;

    #[test]
    fn only_output_changes_trigger_a_refresh() {
        assert!(is_output_event("monitoraddedv2>>1,DP-1,desc"));
        assert!(is_output_event("monitorremoved>>DP-1"));
        assert!(!is_output_event("workspace>>1"));
    }
}
