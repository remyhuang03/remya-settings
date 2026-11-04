//! GUI-only preview; frame data never passes through the resident service.
use crate::Backend;
use gstreamer::{self as gst, prelude::*};
use gstreamer_app::AppSink;
use gstreamer_video::VideoFrameExt;
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

#[derive(Clone)]
struct Preview {
    pipeline: gst::Pipeline,
    sink: AppSink,
}
impl Drop for Preview {
    fn drop(&mut self) {
        let _ = self.pipeline.set_state(gst::State::Null);
    }
}
static PREVIEWS: OnceLock<Mutex<BTreeMap<u64, Arc<Preview>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn previews() -> &'static Mutex<BTreeMap<u64, Arc<Preview>>> {
    PREVIEWS.get_or_init(Default::default)
}
pub struct PreviewFrame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

pub fn start_preview(camera: String, serial: u64) -> Result<u64, String> {
    let camera = crate::native::Native
        .read()?
        .into_iter()
        .find(|c| c.name == camera && c.serial == serial)
        .ok_or("Camera identity changed")?;
    gst::init().map_err(|e| e.to_string())?;
    let pipeline = gst::Pipeline::new();
    let source = gst::ElementFactory::make("pipewiresrc")
        .property("target-object", serial.to_string())
        .build()
        .map_err(|e| e.to_string())?;
    let source_caps = gst::ElementFactory::make("capsfilter")
        .build()
        .map_err(|e| e.to_string())?;
    if let Some((num, denom)) = camera.framerate {
        source_caps.set_property(
            "caps",
            gst::Caps::builder("video/x-raw")
                .field("framerate", gst::Fraction::new(num as i32, denom as i32))
                .build(),
        );
    }
    let convert = gst::ElementFactory::make("videoconvert")
        .build()
        .map_err(|e| e.to_string())?;
    let scale = gst::ElementFactory::make("videoscale")
        .build()
        .map_err(|e| e.to_string())?;
    let rate = gst::ElementFactory::make("videorate")
        .property("drop-only", true)
        .build()
        .map_err(|e| e.to_string())?;
    let sink = AppSink::builder()
        .caps(
            &gst::Caps::builder("video/x-raw")
                .field("format", "RGBA")
                .field("width", 640i32)
                .field("height", 480i32)
                .field("framerate", gst::Fraction::new(15, 1))
                .build(),
        )
        .max_buffers(1)
        .property("leaky-type", gst_app_leaky())
        .sync(false)
        .build();
    pipeline
        .add_many([
            &source,
            &source_caps,
            &convert,
            &scale,
            &rate,
            sink.upcast_ref(),
        ])
        .map_err(|e| e.to_string())?;
    gst::Element::link_many([
        &source,
        &source_caps,
        &convert,
        &scale,
        &rate,
        sink.upcast_ref(),
    ])
    .map_err(|e| e.to_string())?;
    let preview = Arc::new(Preview { pipeline, sink });
    preview
        .pipeline
        .set_state(gst::State::Playing)
        .map_err(|e| e.to_string())?;
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    previews()
        .lock()
        .map_err(|_| "Preview lock failed")?
        .insert(id, preview);
    Ok(id)
}
fn gst_app_leaky() -> gstreamer_app::AppLeakyType {
    gstreamer_app::AppLeakyType::Downstream
}
pub fn next_preview_frame(id: u64) -> Result<PreviewFrame, String> {
    let preview = previews()
        .lock()
        .map_err(|_| "Preview lock failed")?
        .get(&id)
        .cloned()
        .ok_or("Preview stopped")?;
    let sample = preview
        .sink
        .try_pull_sample(gst::ClockTime::from_seconds(5))
        .ok_or_else(|| {
            preview
                .pipeline
                .bus()
                .and_then(|b| b.pop_filtered(&[gst::MessageType::Error]))
                .and_then(|m| {
                    if let gst::MessageView::Error(e) = m.view() {
                        Some(e.error().to_string())
                    } else {
                        None
                    }
                })
                .unwrap_or_else(|| "Camera preview timed out or disconnected".into())
        })?;
    let caps = sample.caps().ok_or("Camera format is unavailable")?;
    let info = gstreamer_video::VideoInfo::from_caps(caps).map_err(|e| e.to_string())?;
    let frame = gstreamer_video::VideoFrameRef::from_buffer_ref_readable(
        sample.buffer().ok_or("Empty camera buffer")?,
        &info,
    )
    .map_err(|e| e.to_string())?;
    let (width, height) = (info.width(), info.height());
    if width == 0 || height == 0 || width > 640 || height > 480 {
        return Err("Invalid preview dimensions".into());
    }
    let stride = frame.plane_stride()[0];
    let data = frame.plane_data(0).map_err(|e| e.to_string())?;
    if stride < width as i32 * 4 || data.len() < stride as usize * height as usize {
        return Err("Invalid camera frame layout".into());
    }
    let rgba = data
        .chunks(stride as usize)
        .take(height as usize)
        .flat_map(|row| row[..width as usize * 4].iter().copied())
        .collect();
    Ok(PreviewFrame {
        width,
        height,
        rgba,
    })
}
pub fn stop_preview(id: u64) -> Result<(), String> {
    if let Some(preview) = previews()
        .lock()
        .map_err(|_| "Preview lock failed")?
        .remove(&id)
    {
        preview
            .pipeline
            .set_state(gst::State::Null)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}
