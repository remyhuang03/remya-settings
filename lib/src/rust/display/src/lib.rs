//! Hyprland display configuration: live monitor rules, `monitors.lua` persistence,
//! reconciliation with saved Settings values, and hardware brightness.
pub mod brightness;
pub mod files;
pub mod hyprland;
pub mod manager;
pub mod model;
pub mod rules;

pub use files::atomic_write;
pub use hyprland::{Compositor, Hyprctl, Monitor, run_bytes};
pub use manager::{DisplayManager, is_display_setting};
