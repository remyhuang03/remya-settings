//! System clock and time zone settings through systemd-timedated.
pub mod api;
#[cfg(feature = "bridge")]
mod frb_generated;
mod timedate;

mod services;

mod ntp_config;

mod ntp_config_write;
mod persistent;
