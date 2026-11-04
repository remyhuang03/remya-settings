use remya_settings_camera::{Backend, native::Native};
fn main() {
    println!(
        "{}",
        serde_json::to_string_pretty(&Native.read().unwrap()).unwrap()
    );
}
