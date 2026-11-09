#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct DateTimeState {
    pub unix_micros: i64,
    pub local_time: String,
    pub timezone: String,
    pub ntp: bool,
    pub ntp_synchronized: bool,
    pub time_servers: Vec<String>,
    pub active_time_server: String,
    pub sync_error: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct TimezoneOption {
    pub id: String,
    pub label: String,
}

pub fn read_date_time() -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.read()
}

pub fn list_timezones() -> Result<Vec<TimezoneOption>, String> {
    crate::timedate::Timedate::connect()?
        .timezones()?
        .into_iter()
        .map(|id| {
            let label = crate::timedate::timezone_label(&id)?;
            Ok(TimezoneOption { id, label })
        })
        .collect()
}

pub fn set_timezone(timezone: String) -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.set_timezone(&timezone)
}

/// Local wall time (YYYY-MM-DDTHH:MM:SS) in the expected system time zone.
/// Explicitly switches off NTP, restoring it if setting the clock fails.
pub fn set_manual_time(local_time: String, timezone: String) -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.set_manual_time(&local_time, &timezone)
}

pub fn set_automatic_time(enabled: bool) -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.set_automatic_time(enabled)
}

pub fn set_time_servers(servers: Vec<String>) -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.set_persistent_servers(&servers)
}

pub fn sync_now() -> Result<DateTimeState, String> {
    crate::timedate::Timedate::connect()?.sync_now()
}

pub fn restart_system() -> Result<(), String> {
    use gio::glib::variant::ToVariant;
    crate::timedate::Timedate::connect()?.service_call(
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "Reboot",
        (true,).to_variant(),
    )?;
    Ok(())
}
