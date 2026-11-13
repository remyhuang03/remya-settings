pub use crate::preview::PreviewFrame;

pub fn start_preview(camera: String, serial: u64) -> Result<u64, String> {
    remya_camera::preview::start_preview(camera, serial)
}

pub fn next_preview_frame(id: u64) -> Result<PreviewFrame, String> {
    let frame = remya_camera::preview::next_preview_frame(id)?;
    Ok(PreviewFrame {
        width: frame.width,
        height: frame.height,
        rgba: frame.rgba,
    })
}

pub fn stop_preview(id: u64) -> Result<(), String> {
    remya_camera::preview::stop_preview(id)
}

#[cfg(test)]
mod tests {
    #[test]
    fn rejects_unknown_preview_without_hardware() {
        assert!(super::next_preview_frame(0).is_err());
        assert!(super::stop_preview(0).is_ok());
    }
}
