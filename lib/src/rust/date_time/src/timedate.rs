use crate::api::DateTimeState;
use gio::glib::{DateTime, TimeType, TimeZone, Variant, variant::ToVariant};
use std::collections::HashMap;

const NAME: &str = "org.freedesktop.timedate1";
const PATH: &str = "/org/freedesktop/timedate1";

pub(crate) struct Timedate(pub(crate) gio::DBusConnection);

impl Timedate {
    pub(crate) fn connect() -> Result<Self, String> {
        gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)
            .map(Self)
            .map_err(|error| format!("System D-Bus unavailable: {error}"))
    }

    fn call(&self, interface: &str, method: &str, args: Variant) -> Result<Variant, String> {
        self.service_call(NAME, PATH, interface, method, args)
    }

    pub(crate) fn read(&self) -> Result<DateTimeState, String> {
        let reply = self.call(
            "org.freedesktop.DBus.Properties",
            "GetAll",
            (NAME,).to_variant(),
        )?;
        let (properties,) = reply
            .get::<(HashMap<String, Variant>,)>()
            .ok_or("Invalid timedated properties")?;
        let timezone = properties
            .get("Timezone")
            .and_then(|value| value.get::<String>())
            .ok_or("Missing timedated Timezone")?;
        let ntp = properties
            .get("NTP")
            .and_then(|value| value.get::<bool>())
            .ok_or("Missing timedated NTP")?;
        let unix_micros = properties
            .get("TimeUSec")
            .and_then(|value| value.get::<u64>())
            .and_then(|value| i64::try_from(value).ok())
            .ok_or("Invalid timedated TimeUSec")?;
        let zone = TimeZone::from_identifier(Some(&timezone)).ok_or("Unknown system time zone")?;
        let local = DateTime::from_unix_utc_usec(unix_micros)
            .and_then(|date| date.to_timezone(&zone))
            .map_err(|error| error.to_string())?;
        let ntp_synchronized = properties
            .get("NTPSynchronized")
            .and_then(|value| value.get::<bool>())
            .ok_or("Missing NTPSynchronized")?;
        let time_servers = self.persistent_servers()?;
        let sync = self.sync_servers().and_then(|_| {
            let active = self
                .property(
                    crate::services::SYNC,
                    crate::services::SYNC_PATH,
                    crate::services::SYNC_INTERFACE,
                    "ServerName",
                )?
                .get::<String>()
                .ok_or("Invalid NTP server name")?;
            Ok(active)
        });
        let (active_time_server, sync_error) = match sync {
            Ok(active) => (active, None),
            Err(error) => (String::new(), Some(error)),
        };
        let time_locale = self
            .locale_values()?
            .into_iter()
            .find_map(|value| value.strip_prefix("LC_TIME=").map(str::to_owned))
            .unwrap_or_default();
        Ok(DateTimeState {
            unix_micros,
            local_time: local
                .format("%Y-%m-%dT%H:%M:%S")
                .map_err(|e| e.to_string())?
                .into(),
            timezone,
            ntp,
            ntp_synchronized,
            time_servers,
            active_time_server,
            sync_error,
            time_locale,
        })
    }

    pub(crate) fn timezones(&self) -> Result<Vec<String>, String> {
        self.call(NAME, "ListTimezones", ().to_variant())?
            .get::<(Vec<String>,)>()
            .map(|(zones,)| zones)
            .filter(|zones| !zones.is_empty())
            .ok_or_else(|| "Invalid or empty timedated time zone list".into())
    }

    pub(crate) fn set_timezone(&self, timezone: &str) -> Result<DateTimeState, String> {
        if !self.timezones()?.iter().any(|zone| zone == timezone) {
            return Err("Choose a time zone from the system list".into());
        }
        self.call(NAME, "SetTimezone", (timezone, true).to_variant())?;
        let state = self.read()?;
        if state.timezone != timezone {
            return Err("Time zone readback does not match the request".into());
        }
        Ok(state)
    }

    pub(crate) fn set_automatic_time(&self, enabled: bool) -> Result<DateTimeState, String> {
        self.call(NAME, "SetNTP", (enabled, true).to_variant())?;
        let state = self.read()?;
        if state.ntp != enabled {
            return Err("Automatic time readback does not match the request".into());
        }
        Ok(state)
    }

    pub(crate) fn set_manual_time(
        &self,
        local_time: &str,
        timezone: &str,
    ) -> Result<DateTimeState, String> {
        let micros = local_micros(local_time, timezone)?;
        let before = self.read()?;
        if before.timezone != timezone {
            return Err("System time zone changed; reload before setting the clock".into());
        }
        if before.ntp {
            self.call(NAME, "SetNTP", (false, true).to_variant())?;
        }
        let applied = (|| {
            self.call(NAME, "SetTime", (micros, false, true).to_variant())?;
            let state = self.read()?;
            if state.ntp || state.unix_micros.abs_diff(micros) > 5_000_000 {
                return Err("Clock readback does not match the request".into());
            }
            Ok(state)
        })();
        if applied.is_err() && before.ntp {
            // A failed clock write must not silently leave automatic time disabled.
            self.call(NAME, "SetNTP", (true, true).to_variant())
                .map_err(|restore| {
                    format!(
                        "{}; restoring automatic time also failed: {restore}",
                        applied.as_ref().unwrap_err()
                    )
                })?;
        }
        applied
    }
}

pub(crate) fn timezone_label(id: &str) -> Result<String, String> {
    let zone = TimeZone::from_identifier(Some(id)).ok_or("Unknown time zone")?;
    let now = DateTime::now(&zone).map_err(|e| e.to_string())?;
    let minutes = now.utc_offset().as_minutes();
    Ok(format!(
        "{id} (GMT{}{:02}:{:02})",
        if minutes < 0 { "-" } else { "+" },
        minutes.abs() / 60,
        minutes.abs() % 60
    ))
}

fn local_micros(value: &str, timezone: &str) -> Result<i64, String> {
    if value.len() != 19 || !value.is_ascii() {
        return Err("Use local time YYYY-MM-DDTHH:MM:SS".into());
    }
    let utc = DateTime::from_iso8601(&format!("{value}Z"), None)
        .map_err(|_| "Invalid local date and time")?;
    if utc
        .format("%Y-%m-%dT%H:%M:%S")
        .map_err(|e| e.to_string())?
        .as_str()
        != value
    {
        return Err("Invalid local date and time".into());
    }
    let zone = TimeZone::from_identifier(Some(timezone)).ok_or("Unknown time zone")?;
    let seconds = utc.to_unix();
    let standard = zone.find_interval(TimeType::Standard, seconds);
    let daylight = zone.find_interval(TimeType::Daylight, seconds);
    if standard < 0 || daylight < 0 {
        return Err(
            "This local time does not exist because of a daylight-saving transition".into(),
        );
    }
    if zone.offset(standard) != zone.offset(daylight) {
        return Err("This local time is ambiguous because of a daylight-saving transition; choose another time".into());
    }
    let micros = (seconds - i64::from(zone.offset(standard))) * 1_000_000;
    if micros <= 0 {
        return Err("System time must be after the Unix epoch".into());
    }
    Ok(micros)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timezone_labels_include_signed_fractional_offsets() {
        assert_eq!(
            timezone_label("Asia/Taipei").unwrap(),
            "Asia/Taipei (GMT+08:00)"
        );
        assert_eq!(
            timezone_label("Asia/Kathmandu").unwrap(),
            "Asia/Kathmandu (GMT+05:45)"
        );
        assert_eq!(
            timezone_label("Etc/GMT+3").unwrap(),
            "Etc/GMT+3 (GMT-03:00)"
        );
        assert_eq!(timezone_label("UTC").unwrap(), "UTC (GMT+00:00)");
    }

    #[test]
    fn validates_local_time_and_dst_transitions() {
        assert_eq!(
            local_micros("2026-10-30T08:00:00", "Asia/Taipei").unwrap(),
            local_micros("2026-10-30T00:00:00", "UTC").unwrap()
        );
        for value in [
            "2026-02-30T12:00:00",
            "2026-10-30T24:00:00",
            "2026-10-30T12:00:00Z",
            "bad",
            "1960-01-01T00:00:00",
        ] {
            assert!(local_micros(value, "UTC").is_err(), "{value}");
        }
        assert!(local_micros("2026-03-08T02:30:00", "America/New_York").is_err());
        assert!(local_micros("2026-11-01T01:30:00", "America/New_York").is_err());
        assert!(local_micros("2026-10-30T08:00:00", "Invalid/Zone").is_err());
    }
    #[test]
    fn isolated_dbus_writes_authorization_errors_and_readback() {
        use gio::glib::{MainContext, MainLoop};
        use std::io::{BufRead, BufReader};
        use std::process::{Command, Stdio};
        use std::sync::{Arc, Mutex, mpsc};
        use std::time::Duration;

        struct Daemon(std::process::Child);
        impl Drop for Daemon {
            fn drop(&mut self) {
                let _ = self.0.kill();
                let _ = self.0.wait();
            }
        }
        #[derive(Default)]
        struct State {
            zone: String,
            ntp: bool,
            micros: u64,
            calls: Vec<String>,
            deny_time: bool,
            ignore_zone: bool,
            fail_restore: bool,
            servers: Vec<String>,
            locales: Vec<String>,
            packets: u64,
            deny_settings: bool,
            ignore_locale: bool,
            rebooted: bool,
        }
        let mut daemon = Daemon(
            Command::new("dbus-daemon")
                .args(["--session", "--nofork", "--print-address=1"])
                .stdout(Stdio::piped())
                .spawn()
                .unwrap(),
        );
        let mut address = String::new();
        BufReader::new(daemon.0.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        let address = address.trim().to_owned();
        let state = Arc::new(Mutex::new(State {
            zone: "Asia/Taipei".into(),
            ntp: true,
            locales: vec!["LANG=en_US.UTF-8".into(), "LC_NUMERIC=C".into()],
            micros: local_micros("2026-10-30T12:00:00", "Asia/Taipei").unwrap() as u64,
            ..State::default()
        }));
        let (ready_tx, ready_rx) = mpsc::channel();
        let (stop_tx, stop_rx) = mpsc::channel();
        let server_address = address.clone();
        let server_state = state.clone();
        let server = std::thread::spawn(move || {
            let context = MainContext::new();
            context.with_thread_default(|| {
                let connection = gio::DBusConnection::for_address_sync(&server_address,
                    gio::DBusConnectionFlags::AUTHENTICATION_CLIENT | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION, None, gio::Cancellable::NONE).unwrap();
                let xml = r#"<node><interface name="org.freedesktop.timedate1">
                    <property name="Timezone" type="s" access="read"/>
                    <property name="NTP" type="b" access="read"/><property name="NTPSynchronized" type="b" access="read"/>
                    <property name="TimeUSec" type="t" access="read"/>
                    <method name="ListTimezones"><arg type="as" direction="out"/></method>
                    <method name="SetTimezone"><arg type="s" direction="in"/><arg type="b" direction="in"/></method>
                    <method name="SetNTP"><arg type="b" direction="in"/><arg type="b" direction="in"/></method>
                    <method name="SetTime"><arg type="x" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="in"/></method>
                </interface></node>"#;
                let info = gio::DBusNodeInfo::for_xml(xml).unwrap().lookup_interface(NAME).unwrap();
                let method_state = server_state.clone();
                let property_state = server_state.clone();
                let _registration = connection.register_object(PATH, &info)
                    .method_call(move |_, _, _, _, method, parameters, invocation| {
                        let mut state = method_state.lock().unwrap();
                        state.calls.push(method.into());
                        match method {
                            "ListTimezones" => { invocation.return_value(Some(&(vec!["Asia/Taipei", "UTC"],).to_variant())); return; }
                            "SetTimezone" => {
                                let (zone, interactive) = parameters.get::<(String, bool)>().unwrap();
                                assert!(interactive);
                                if !state.ignore_zone { state.zone = zone; }
                            }
                            "SetNTP" => {
                                let (ntp, interactive) = parameters.get::<(bool, bool)>().unwrap();
                                assert!(interactive);
                                if ntp && state.fail_restore {
                                    invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Restore denied"); return;
                                }
                                state.ntp = ntp;
                            }
                            "SetTime" => {
                                let (micros, relative, interactive) = parameters.get::<(i64, bool, bool)>().unwrap();
                                assert!(!relative && interactive);
                                assert!(!state.ntp);
                                if state.deny_time {
                                    invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Clock permission denied"); return;
                                }
                                state.micros = micros as u64;
                            }
                            _ => panic!("Unexpected method {method}"),
                        }
                        invocation.return_value(Some(&().to_variant()));
                    })
                    .property(move |_, _, _, _, property| {
                        let state = property_state.lock().unwrap();
                        match property {
                            "Timezone" => state.zone.to_variant(),
                            "NTP" | "NTPSynchronized" => state.ntp.to_variant(),
                            "TimeUSec" => state.micros.to_variant(),
                            _ => panic!("Unexpected property {property}"),
                        }
                    }).build().unwrap();
                connection.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", Some(&(NAME, 0u32).to_variant()), None, gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE).unwrap();
                let mut registrations = vec![];
                for (name, path, interface, xml) in [
                    (crate::services::SYNC, crate::services::SYNC_PATH, crate::services::SYNC_INTERFACE, r#"<node><interface name="org.freedesktop.timesync1.Manager"><property name="RuntimeNTPServers" type="as" access="read"/><property name="ServerName" type="s" access="read"/><property name="NTPMessage" type="(uuuuittayttttbtt)" access="read"/><method name="SetRuntimeNTPServers"><arg type="as" direction="in"/></method></interface></node>"#),
                    ("org.freedesktop.locale1", "/org/freedesktop/locale1", "org.freedesktop.locale1", r#"<node><interface name="org.freedesktop.locale1"><property name="Locale" type="as" access="read"/><method name="SetLocale"><arg type="as" direction="in"/><arg type="b" direction="in"/></method></interface></node>"#),
                    ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", r#"<node><interface name="org.freedesktop.login1.Manager"><method name="Reboot"><arg type="b" direction="in"/></method></interface></node>"#),
                ] {
                    let info = gio::DBusNodeInfo::for_xml(xml).unwrap().lookup_interface(interface).unwrap();
                    let method_state = server_state.clone();
                    let property_state = server_state.clone();
                    registrations.push(connection.register_object(path, &info)
                        .method_call(move |_, _, _, _, method, args, invocation| {
                            let mut state = method_state.lock().unwrap();
                            if state.deny_settings { invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Settings denied"); return; }
                            match method {
                                "SetRuntimeNTPServers" => { state.servers = args.get::<(Vec<String>,)>().unwrap().0; state.packets += 1; }
                                "SetLocale" => {
                                    let (values, interactive) = args.get::<(Vec<String>, bool)>().unwrap();
                                    assert!(interactive);
                                    assert_eq!(values.len(), 1);
                                    assert!(values[0].starts_with("LC_TIME="));
                                    if values.iter().any(|value| value.ends_with('=')) {
                                        invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", "Empty locale is invalid");
                                        return;
                                    }
                                    if !state.ignore_locale {
                                        for value in values {
                                            let (key, content) = value.split_once('=').unwrap();
                                            state.locales.retain(|old| old.split_once('=').unwrap().0 != key);
                                            assert!(!content.is_empty());
                                            state.locales.push(value);
                                        }
                                        let lang = state.locales.iter().find_map(|v| v.strip_prefix("LANG=")).unwrap_or("C").to_owned();
                                        state.locales.retain(|v| v.strip_prefix("LC_TIME=").is_none_or(|locale| locale != lang));
                                    }
                                }
                                "Reboot" => { assert!(args.get::<(bool,)>().unwrap().0); state.rebooted = true; }
                                _ => panic!("Unexpected method {method}"),
                            }
                            invocation.return_value(Some(&().to_variant()));
                        })
                        .property(move |_, _, _, _, property| {
                            let state = property_state.lock().unwrap();
                            match property {
                                "RuntimeNTPServers" => state.servers.to_variant(),
                                "ServerName" => state.servers.first().map(String::as_str).unwrap_or("pool.ntp.org").to_variant(),
                                "Locale" => state.locales.to_variant(),
                                "NTPMessage" => (0u32,4u32,4u32,1u32,0i32,0u64,0u64,vec![0u8;4],0u64,0u64,0u64,0u64,false,state.packets,0u64).to_variant(),
                                _ => panic!("Unexpected property {property}"),
                            }
                        }).build().unwrap());
                    connection.call_sync(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", Some(&(name, 0u32).to_variant()), None, gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE).unwrap();
                }
                let main_loop = MainLoop::new(Some(&context), false);
                let stop_loop = main_loop.clone();
                let source = gio::glib::timeout_source_new(Duration::from_millis(20), None, gio::glib::Priority::DEFAULT, move || {
                    if stop_rx.try_recv().is_ok() { stop_loop.quit(); gio::glib::ControlFlow::Break } else { gio::glib::ControlFlow::Continue }
                });
                source.attach(Some(&context));
                ready_tx.send(()).unwrap();
                main_loop.run();
            }).unwrap();
        });
        ready_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        let client = Timedate(
            gio::DBusConnection::for_address_sync(
                &address,
                gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
                    | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
                None,
                gio::Cancellable::NONE,
            )
            .unwrap(),
        );
        assert!(!client.set_automatic_time(false).unwrap().ntp);
        assert!(client.sync_now().is_err());
        assert!(client.set_automatic_time(true).unwrap().ntp);
        client.write_servers(&["pool.ntp.org".into()]).unwrap();
        assert!(client.sync_now().unwrap().ntp_synchronized);
        assert!(client.write_servers(&["https://bad".into()]).is_err());
        let locale = crate::services::list_locales()
            .unwrap()
            .into_iter()
            .find(|v| !v.is_empty())
            .unwrap();
        assert_eq!(client.set_time_locale(&locale).unwrap().time_locale, locale);
        assert!(
            state
                .lock()
                .unwrap()
                .locales
                .contains(&"LANG=en_US.UTF-8".into())
        );
        assert!(
            state
                .lock()
                .unwrap()
                .locales
                .contains(&"LC_NUMERIC=C".into())
        );
        if crate::services::list_locales()
            .unwrap()
            .contains(&"en_US.utf8".into())
        {
            assert_eq!(
                client.set_time_locale("en_US.utf8").unwrap().time_locale,
                "en_US.utf8"
            );
            client.set_time_locale(&locale).unwrap();
        }
        for option in crate::services::list_locales().unwrap() {
            client.set_time_locale(&option).unwrap();
            assert!(client.set_time_locale("").unwrap().time_locale.is_empty());
            let locales = &state.lock().unwrap().locales;
            assert!(locales.contains(&"LANG=en_US.UTF-8".into()));
            assert!(locales.contains(&"LC_NUMERIC=C".into()));
        }
        client.set_time_locale(&locale).unwrap();
        state.lock().unwrap().ignore_locale = true;
        assert!(client.set_time_locale("").unwrap_err().contains("readback"));
        state.lock().unwrap().ignore_locale = false;
        state.lock().unwrap().deny_settings = true;
        assert!(client.write_servers(&[]).unwrap_err().contains("denied"));
        assert!(client.set_time_locale("").unwrap_err().contains("denied"));
        state.lock().unwrap().deny_settings = false;
        client
            .service_call(
                "org.freedesktop.login1",
                "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager",
                "Reboot",
                (true,).to_variant(),
            )
            .unwrap();
        assert!(state.lock().unwrap().rebooted);
        assert_eq!(client.read().unwrap().local_time, "2026-10-30T12:00:00");
        assert!(client.set_timezone("Bad/Zone").is_err());
        assert!(
            !state
                .lock()
                .unwrap()
                .calls
                .iter()
                .any(|call| call == "SetTimezone")
        );
        assert_eq!(client.set_timezone("UTC").unwrap().timezone, "UTC");
        let applied = client
            .set_manual_time("2026-10-30T13:30:00", "UTC")
            .unwrap();
        assert!(!applied.ntp);
        assert_eq!(applied.local_time, "2026-10-30T13:30:00");
        {
            let mut state = state.lock().unwrap();
            state.ntp = true;
            state.deny_time = true;
            state.calls.clear();
        }
        let failure = client
            .set_manual_time("2026-10-30T14:00:00", "UTC")
            .unwrap_err();
        assert!(failure.contains("Clock permission denied"));
        assert!(state.lock().unwrap().ntp);
        assert_eq!(state.lock().unwrap().calls, ["SetNTP", "SetTime", "SetNTP"]);
        state.lock().unwrap().fail_restore = true;
        assert!(
            client
                .set_manual_time("2026-10-30T14:00:00", "UTC")
                .unwrap_err()
                .contains("restoring automatic time also failed")
        );
        state.lock().unwrap().ignore_zone = true;
        assert!(
            client
                .set_timezone("Asia/Taipei")
                .unwrap_err()
                .contains("readback")
        );
        stop_tx.send(()).unwrap();
        server.join().unwrap();
    }
}
