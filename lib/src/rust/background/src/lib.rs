//! Desktop background: images through hyprpaper, videos through mpvpaper (hyprpaper
//! cannot play video), plus the accent color sampled from the current background.
pub mod accent;
pub mod hyprpaper;
pub mod manager;
pub mod media;
pub mod system;
pub mod video;

pub use manager::{BackgroundManager, is_accent_setting, is_background_setting};
pub use system::{Desktop, RealDesktop};
