use remya_settings_camera::{Backend, api, native::Native};
fn main() {
    for c in Native.read().unwrap() {
        let id = api::start_preview(c.name, c.serial).unwrap();
        let result = api::next_preview_frame(id);
        api::stop_preview(id).unwrap();
        let frame = result.unwrap();
        assert_eq!(
            frame.rgba.len(),
            frame.width as usize * frame.height as usize * 4
        );
        println!("Preview {}: {}x{}", c.serial, frame.width, frame.height);
    }
}
