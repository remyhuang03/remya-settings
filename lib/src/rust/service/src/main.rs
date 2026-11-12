mod ai;
mod clipboard;
mod events;
mod notifications;
mod osd;
mod privileged;
mod state;
use gio::glib::{self, variant::ToVariant};
use std::sync::{Arc, Mutex};
const NAME: &str = "top.remya.settings.Service1";
const PATH: &str = "/top/remya/settings";
const INTERFACE: &str = "top.remya.settings.Settings1";
fn signal(bus: &gio::DBusConnection, topic: &str, value: &serde_json::Value) {
    let _ = bus.emit_signal(
        None,
        PATH,
        INTERFACE,
        "Changed",
        Some(&(topic, value.to_string()).to_variant()),
    );
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
fn run() -> Result<(), String> {
    if std::env::args().nth(1).as_deref() == Some("--privileged") {
        return privileged::serve();
    }
    let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    let config = if let Some(root) = std::env::args().skip_while(|a| a != "--debug-root").nth(1) {
        std::path::PathBuf::from(root).join("config/config.local.toml")
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .filter(|p| p.is_absolute())
            .or_else(|| {
                std::env::var_os("HOME")
                    .map(std::path::PathBuf::from)
                    .filter(|p| p.is_absolute())
                    .map(|p| p.join(".config"))
            })
            .ok_or("Absolute HOME required")?
            .join("remya/settings/config.toml")
    };
    let initial = state::State::new(config);
    let appimages = initial.appimages.clone();
    let storage = initial.storage.clone();
    let bluetooth = initial.bluetooth.clone();
    let state = Arc::new(Mutex::new(initial));
    let xml = include_str!("../../../../../packages/remya_settings_client/api/settings1.xml");
    let info = gio::DBusNodeInfo::for_xml(xml)
        .map_err(|e| e.to_string())?
        .lookup_interface(INTERFACE)
        .unwrap();
    let handler = state.clone();
    let main_loop = glib::MainLoop::new(None, false);
    let quit = main_loop.clone();
    let _registration = bus
        .register_object(PATH, &info)
        .method_call(move |bus, _, _, _, method, args, invocation| {
            let args = (0..args.n_children())
                .map(|i| args.child_value(i).get::<String>().unwrap())
                .collect::<Vec<_>>();
            let state = handler.clone();
            let quit = quit.clone();
            let method = method.to_owned();
            glib::MainContext::default().spawn_local(async move {
                let worker = state.clone();
                let work_method = method.clone();
                let work_args = args.clone();
                let (
                    result,
                    theme,
                    date,
                    display,
                    hostname,
                    default_apps,
                    background,
                    accent,
                    theme_changed,
                    accent_changed,
                    appearance_error,
                ) = gio::spawn_blocking(move || {
                    let mut state = worker.lock().unwrap();
                    let before = state.theme.clone();
                    let accent_before = state.background.accent_state();
                    let result = state.execute(&work_method, &work_args);
                    let appearance_error =
                        if work_method == "Set" && work_args[0].starts_with("themes.material-") {
                            result.as_ref().err().cloned()
                        } else {
                            None
                        };
                    if let Err(error) = &result
                        && work_method == "Set"
                        && work_args[0].starts_with("date-time.")
                    {
                        state.date_error = Some(error.clone());
                    }
                    (
                        result,
                        state.theme.clone(),
                        state.configuration()["date-time"].clone(),
                        state.display.state(),
                        state.hostname_state(),
                        state.default_apps.state(),
                        state.background.state(),
                        state.background.accent_state(),
                        state.theme != before,
                        state.background.accent_state() != accent_before,
                        appearance_error,
                    )
                })
                .await
                .expect("service worker panicked");
                // A rejected page must not open anything or request authorization.
                let opened_page = match (result.is_ok(), method.as_str()) {
                    (true, "Open") if args[0] != "repository" => Some(args[0].as_str()),
                    (true, "Set") => state::linked_page(&args[0]),
                    _ => None,
                };
                let succeeded = result.is_ok();
                match result {
                    Ok(value) => {
                        invocation.return_value(Some(&(value.to_string(),).to_variant()));
                        if method == "Set"
                            && ([
                                state::BAR_CLOCK_SECONDS,
                                state::BAR_KEY_PREVIEW,
                                state::BAR_FOLDED_APPS,
                                state::BAR_SIDEBAR,
                                state::BAR_LAYOUT,
                                remya_settings_power::KEEP_AWAKE,
                                remya_settings_display::night_light::GAMMA,
                            ]
                            .contains(&args[0].as_str())
                                || notifications::IDS.contains(&args[0].as_str())
                                || osd::IDS.contains(&args[0].as_str())
                                || clipboard::IDS.contains(&args[0].as_str())
                                || remya_settings_network::proxy::IDS.contains(&args[0].as_str())
                                || [
                                    remya_settings_network::airplane::ENABLED,
                                    remya_settings_network::airplane::WIFI,
                                ]
                                .contains(&args[0].as_str()))
                        {
                            signal(&bus, &args[0], &value);
                        }
                        if method == "Set"
                            && (args[0] == remya_settings_display::manager::BRIGHTNESS
                                || args[0].starts_with("display-brightness:"))
                        {
                            signal(&bus, "display-brightness", &value);
                        }
                        if method == "Set" && ai::SET_IDS.contains(&args[0].as_str()) {
                            signal(&bus, &args[0], &value);
                            if args[0] != ai::PROVIDERS {
                                signal(&bus, ai::PROVIDERS, &value);
                            }
                        }
                    }
                    Err(error) => {
                        let (kind, message) = error
                            .split_once(':')
                            .filter(|(k, _)| ["InvalidArgument", "Unavailable"].contains(k))
                            .unwrap_or(("OperationFailed", &error));
                        invocation.return_dbus_error(&format!("{INTERFACE}.{kind}"), message);
                    }
                }
                if method == "Set" || method == "Resolve" || method == "Reload" {
                    if theme_changed {
                        signal(&bus, "theme", &theme);
                    }
                    signal(&bus, "date-time", &date);
                    signal(&bus, "display", &display);
                    signal(&bus, "hostname", &hostname);
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "night-light"
                                || remya_settings_display::is_night_light_setting(id)
                        })
                    {
                        let night_light = state.lock().unwrap().night_light.state();
                        signal(&bus, "night-light", &night_light);
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "network" || remya_settings_network::is_network_setting(id)
                        })
                    {
                        let network = state.lock().unwrap().network.state();
                        signal(&bus, "network", &network);
                    }
                    if method == "Reload"
                        || args
                            .first()
                            .is_some_and(|id| id.starts_with("defaults.") || id == "default-apps")
                    {
                        signal(&bus, "default-apps", &default_apps);
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "startup" || remya_settings_startup::IDS.contains(&id.as_str())
                        })
                    {
                        signal(&bus, "startup", &state.lock().unwrap().startup.state());
                    }
                    signal(&bus, "background", &background);
                    if accent_changed {
                        signal(&bus, "accent", &accent);
                    }
                    if args.first().is_some_and(|id| id.starts_with("installed.")) {
                        signal(&bus, "installed-apps", &serde_json::json!({}));
                    }
                    if args.first().is_some_and(|id| {
                        remya_settings_system_information::account::IDS.contains(&id.as_str())
                    }) && let Ok(account) = state.lock().unwrap().account.read()
                    {
                        signal(&bus, "account-information", &account);
                    }
                    if method == "Reload"
                        || args
                            .first()
                            .is_some_and(|id| id == "input" || remya_settings_input::is_setting(id))
                    {
                        signal(&bus, "input", &state.lock().unwrap().input.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == remya_settings_date_time::language::FEATURE
                                || remya_settings_date_time::language::is_setting(id)
                        })
                    {
                        signal(&bus, "language", &state.lock().unwrap().language.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "desktop" || remya_settings_input::is_desktop_setting(id)
                        })
                    {
                        signal(&bus, "desktop", &state.lock().unwrap().desktop.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "themes" || remya_settings_appearance::packs::is_setting(id)
                        })
                    {
                        signal(&bus, "themes", &state.lock().unwrap().themes.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "text-size"
                                || remya_settings_appearance::text_size::is_setting(id)
                        })
                    {
                        signal(&bus, "text-size", &state.lock().unwrap().text_size.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "power"
                                || id == "battery-saver"
                                || (id != remya_settings_power::KEEP_AWAKE
                                    && remya_settings_power::is_setting(id))
                        })
                    {
                        signal(&bus, "power", &state.lock().unwrap().power.state());
                    }
                    if method == "Reload"
                        || args
                            .first()
                            .is_some_and(|id| id == "sound" || remya_settings_sound::is_setting(id))
                    {
                        signal(&bus, "sound", &state.lock().unwrap().sound.state());
                    }
                    if method == "Reload"
                        || args.first().is_some_and(|id| {
                            id == "cameras"
                                || id.starts_with("cameras:")
                                || remya_settings_camera::is_setting(id)
                        })
                    {
                        signal(&bus, "cameras", &state.lock().unwrap().cameras.state());
                    }
                    if args
                        .first()
                        .is_some_and(|id| remya_settings_updates::is_setting(id))
                    {
                        signal(&bus, "updates", &state.lock().unwrap().updates.state());
                    }
                    if args
                        .first()
                        .is_some_and(|id| remya_settings_fonts::IDS.contains(&id.as_str()))
                    {
                        signal(&bus, "fonts", &serde_json::json!({}));
                    }
                }
                if let Some(message) = appearance_error {
                    signal(&bus, "error", &serde_json::json!({"message":message}));
                }
                if let Some(page) = opened_page {
                    signal(&bus, "navigation", &serde_json::json!({"page":page}));
                    let needed = state.lock().unwrap().begin_authorization();
                    if needed {
                        signal(&bus, "date-time", &serde_json::json!({"authorizing":true}));
                        let result = gio::spawn_blocking(privileged::Session::start)
                            .await
                            .expect("authorization worker");
                        state.lock().unwrap().finish_authorization(result);
                    }
                    signal(
                        &bus,
                        "date-time",
                        &state.lock().unwrap().configuration()["date-time"],
                    );
                }
                if opened_page.is_some() {
                    signal(&bus, "hostname", &state.lock().unwrap().hostname_state());
                }
                if method == "Quit" && succeeded {
                    let _ = bus.flush_future().await;
                    state.lock().unwrap().shutdown();
                    quit.quit();
                }
            });
        })
        .build()
        .map_err(|e| e.to_string())?;
    let result = bus
        .call_sync(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            Some(&(NAME, 4u32).to_variant()),
            None,
            gio::DBusCallFlags::NONE,
            5000,
            gio::Cancellable::NONE,
        )
        .map_err(|e| e.to_string())?;
    if result.get::<(u32,)>() != Some((1,)) {
        return Ok(());
    }
    {
        let mut state = state.lock().unwrap();
        state.ensure_idle();
        state.refresh();
    }
    let polling = state.clone();
    let poll_bus = bus.clone();
    let mut ticks = 0u32;
    events::watch(state.clone(), bus.clone());
    events::watch_sound(state.clone(), bus.clone());
    if let Err(error) = events::watch_backlight(state.clone(), bus.clone()) {
        eprintln!("Backlight events unavailable: {error}");
    }
    let _network_subscriptions = events::watch_network(state.clone(), bus.clone());
    let _power_sleep = events::watch_power_sleep(state.clone());
    let power_state = state.clone();
    let power_bus = bus.clone();
    std::thread::spawn(move || {
        loop {
            {
                let mut s = power_state.lock().unwrap();
                let before = s.power.state();
                s.power.tick();
                if s.power.state() != before {
                    signal(&power_bus, "power", &s.power.state());
                }
            }
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    });
    glib::timeout_add_seconds_local(1, move || {
        ticks += 1;
        if bluetooth.take_dirty() {
            signal(&poll_bus, "bluetooth", &bluetooth.state());
        }
        if let Ok(state) = polling.try_lock() {
            state.updates.tick();
            if state.updates.take_dirty() {
                signal(&poll_bus, "updates", &state.updates.state());
            }
        }
        if storage.take_dirty() {
            signal(&poll_bus, "storage", &storage.state("storage"));
            signal(&poll_bus, "cleanup", &storage.state("cleanup"));
        }
        if appimages.take_dirty() {
            signal(&poll_bus, "appimages", &appimages.state());
        }
        if ticks.is_multiple_of(60) {
            appimages.auto_tick();
            storage.auto_tick();
        }
        let mut expired = false;
        if let Ok(mut state) = polling.try_lock() {
            state.reap_gui();
            if state.reap_authorization() {
                signal(&poll_bus, "hostname", &state.hostname_state());
            }
            expired = state.display.pending_expired();
        }
        if expired {
            let state = polling.clone();
            let bus = poll_bus.clone();
            std::thread::spawn(move || {
                let mut s = state.lock().unwrap();
                // Another caller may have kept or reverted it first; this is then a no-op.
                if s.display.pending_expired() {
                    let result = s.display.revert_pending();
                    if let Err(message) = result {
                        signal(&bus, "error", &serde_json::json!({"message": message}));
                    }
                    signal(&bus, "display", &s.display.state());
                }
            });
        }
        let state = polling.clone();
        let bus = poll_bus.clone();
        if ticks.is_multiple_of(30) {
            std::thread::spawn(move || {
                let mut s = state.lock().unwrap();
                let before = s.theme.clone();
                let errors = s.theme_error.clone();
                let accent = s.background.accent_state();
                let network = s.network.state();
                let night_light = s.night_light.state();
                let sound = s.sound.state();
                let cameras = s.cameras.state();
                let startup = s.startup.state();
                s.refresh();
                if s.startup.state() != startup {
                    signal(&bus, "startup", &s.startup.state());
                }
                if s.cameras.state() != cameras {
                    signal(&bus, "cameras", &s.cameras.state());
                }
                if s.sound.state() != sound {
                    signal(&bus, "sound", &s.sound.state());
                }
                if s.night_light.state() != night_light {
                    signal(&bus, "night-light", &s.night_light.state());
                }
                if s.network.state() != network {
                    signal(&bus, "network", &s.network.state());
                }
                if s.background.accent_state() != accent {
                    signal(&bus, "accent", &s.background.accent_state());
                }
                if s.theme != before {
                    signal(&bus, "theme", &s.theme);
                }
                if s.theme_error != errors {
                    signal(&bus, "error", &serde_json::json!({"message":s.theme_error}));
                }
                signal(&bus, "date-time", &s.configuration()["date-time"]);
                signal(&bus, "hostname", &s.hostname_state());
                signal(&bus, "display", &s.display.state());
                signal(&bus, "background", &s.background.state());
            });
        }
        glib::ControlFlow::Continue
    });
    main_loop.run();
    bus.unregister_object(_registration)
        .map_err(|e| e.to_string())?;
    drop(state);
    Ok(())
}
