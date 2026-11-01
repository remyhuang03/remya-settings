use gio::glib::{Variant, variant::ToVariant};
use std::process::Command;

use crate::timedate::Timedate;

pub(crate) const SYNC: &str = "org.freedesktop.timesync1";
pub(crate) const SYNC_PATH: &str = "/org/freedesktop/timesync1";
pub(crate) const SYNC_INTERFACE: &str = "org.freedesktop.timesync1.Manager";
const LOCALE: &str = "org.freedesktop.locale1";
const LOCALE_PATH: &str = "/org/freedesktop/locale1";

impl Timedate {
    pub(crate) fn service_call(
        &self,
        name: &str,
        path: &str,
        interface: &str,
        method: &str,
        args: Variant,
    ) -> Result<Variant, String> {
        self.0
            .call_sync(
                Some(name),
                path,
                interface,
                method,
                Some(&args),
                None,
                gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
                120_000,
                gio::Cancellable::NONE,
            )
            .map_err(|error| format!("{method}: {error}"))
    }

    pub(crate) fn property(
        &self,
        name: &str,
        path: &str,
        interface: &str,
        property: &str,
    ) -> Result<Variant, String> {
        self.service_call(
            name,
            path,
            "org.freedesktop.DBus.Properties",
            "Get",
            (interface, property).to_variant(),
        )?
        .get::<(Variant,)>()
        .map(|(value,)| value)
        .ok_or_else(|| format!("Invalid {property}"))
    }

    pub(crate) fn sync_servers(&self) -> Result<Vec<String>, String> {
        self.property(SYNC, SYNC_PATH, SYNC_INTERFACE, "RuntimeNTPServers")?
            .get()
            .ok_or_else(|| "Invalid runtime NTP servers".into())
    }

    pub(crate) fn write_servers(&self, servers: &[String]) -> Result<(), String> {
        crate::ntp_config::validate_servers(servers)?;
        self.service_call(
            SYNC,
            SYNC_PATH,
            SYNC_INTERFACE,
            "SetRuntimeNTPServers",
            (servers,).to_variant(),
        )?;
        if self.sync_servers()? != servers {
            return Err("Time server readback does not match the request".into());
        }
        Ok(())
    }

    pub(crate) fn persistent_servers(&self) -> Result<Vec<String>, String> {
        crate::ntp_config::read(std::path::Path::new(crate::ntp_config::CONFIG))
    }

    pub(crate) fn set_persistent_servers(
        &self,
        servers: &[String],
    ) -> Result<crate::api::DateTimeState, String> {
        crate::ntp_config::validate_servers(servers)?;
        if !self.read()?.ntp {
            return Err("Enable automatic time before choosing servers".into());
        }
        crate::persistent::set_servers(servers)?;
        let observed = self.read()?;
        if observed.time_servers != servers {
            return Err("Persistent time server readback does not match the request".into());
        }
        Ok(observed)
    }

    pub(crate) fn locale_values(&self) -> Result<Vec<String>, String> {
        self.property(LOCALE, LOCALE_PATH, LOCALE, "Locale")?
            .get()
            .ok_or_else(|| "Invalid system locale".into())
    }

    pub(crate) fn set_time_locale(
        &self,
        locale: &str,
    ) -> Result<crate::api::DateTimeState, String> {
        if !list_locales()?.iter().any(|value| value == locale) {
            return Err("Choose an installed locale".into());
        }
        let current = self.locale_values()?;
        let language = current
            .iter()
            .find_map(|v| v.strip_prefix("LANG="))
            .unwrap_or("C");
        // localed rejects empty assignments and removes overrides equal to LANG.
        let requested = if locale.is_empty() { language } else { locale };
        let values = vec![format!("LC_TIME={requested}")];
        self.service_call(
            LOCALE,
            LOCALE_PATH,
            LOCALE,
            "SetLocale",
            (values, true).to_variant(),
        )?;
        let state = self.read()?;
        let values = self.locale_values()?;
        let language = values
            .iter()
            .find_map(|v| v.strip_prefix("LANG="))
            .unwrap_or("C");
        let actual = if state.time_locale.is_empty() {
            language
        } else {
            &state.time_locale
        };
        let requested = if locale.is_empty() { language } else { locale };
        if normalize_locale(actual) != normalize_locale(requested) {
            return Err("LC_TIME readback does not match the request".into());
        }
        Ok(state)
    }

    pub(crate) fn sync_now(&self) -> Result<crate::api::DateTimeState, String> {
        if !self.read()?.ntp {
            return Err("Enable automatic time before synchronizing".into());
        }
        let packet_count = || -> Result<u64, String> {
            self.property(SYNC, SYNC_PATH, SYNC_INTERFACE, "NTPMessage")?
                .child_value(13)
                .get()
                .ok_or_else(|| "Invalid NTP packet count".into())
        };
        let before = packet_count()?;
        self.write_servers(&self.sync_servers()?)?;
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
        while std::time::Instant::now() < deadline {
            std::thread::sleep(std::time::Duration::from_millis(250));
            if packet_count()? > before {
                let state = self.read()?;
                if state.ntp_synchronized {
                    return Ok(state);
                }
            }
        }
        Err("No fresh synchronized NTP response within 15 seconds; automatic synchronization remains enabled".into())
    }
}

pub(crate) fn list_locales() -> Result<Vec<String>, String> {
    let result = Command::new("locale")
        .arg("-a")
        .output()
        .map_err(|e| e.to_string())?;
    if !result.status.success() {
        return Err("Cannot list installed locales".into());
    }
    let mut locales: Vec<String> = String::from_utf8(result.stdout)
        .map_err(|e| e.to_string())?
        .lines()
        .map(str::to_owned)
        .collect();
    if locales.is_empty() {
        return Err("No installed locales found".into());
    }
    locales.sort();
    locales.dedup();
    locales.insert(0, String::new());
    Ok(locales)
}

pub(crate) fn normalize_locale(locale: &str) -> String {
    locale.replace('-', "").to_ascii_lowercase()
}
