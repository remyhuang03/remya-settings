use super::{Backend, Device, DevicePrefs, Direction, Snapshot, Stream};
use libpulse_binding as pulse;
use pulse::{
    callbacks::ListResult,
    context::{Context, FlagSet, State, subscribe::InterestMaskSet},
    mainloop::standard::{IterateResult, Mainloop},
    operation::Operation,
    volume::{ChannelVolumes, Volume},
};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
    thread,
    time::{Duration, Instant},
};

pub struct RealPulse;
struct Connection {
    context: Context,
    mainloop: Mainloop,
}
impl Connection {
    fn new() -> Result<Self, String> {
        let mainloop = Mainloop::new().ok_or("Cannot create audio mainloop")?;
        let mut context =
            Context::new(&mainloop, "Remya Settings").ok_or("Cannot create audio connection")?;
        context
            .connect(None, FlagSet::NOAUTOSPAWN, None)
            .map_err(|e| format!("Cannot connect to PipeWire audio: {e}"))?;
        let mut connection = Self { context, mainloop };
        let until = Instant::now() + Duration::from_secs(3);
        while connection.context.get_state() != State::Ready {
            if matches!(
                connection.context.get_state(),
                State::Failed | State::Terminated
            ) || Instant::now() > until
            {
                return Err(
                    "Audio service unavailable. Start pipewire-pulse and WirePlumber.".into(),
                );
            }
            connection.step()?;
        }
        Ok(connection)
    }
    fn step(&mut self) -> Result<(), String> {
        match self.mainloop.iterate(false) {
            IterateResult::Err(e) => Err(e
                .to_string()
                .unwrap_or_else(|| "Audio mainloop failed".into())),
            IterateResult::Quit(_) => Err("Audio connection closed".into()),
            _ => {
                thread::sleep(Duration::from_millis(1));
                Ok(())
            }
        }
    }
    fn wait<C: ?Sized>(&mut self, operation: Operation<C>) -> Result<(), String> {
        let until = Instant::now() + Duration::from_secs(3);
        while operation.get_state() == pulse::operation::State::Running {
            if Instant::now() > until {
                return Err("Audio service did not respond within 3 seconds".into());
            }
            self.step()?;
        }
        if operation.get_state() != pulse::operation::State::Done {
            return Err("Audio operation was cancelled".into());
        }
        Ok(())
    }
    fn success(
        &mut self,
        operation: Operation<dyn FnMut(bool)>,
        result: Rc<Cell<bool>>,
    ) -> Result<(), String> {
        self.wait(operation)?;
        if result.get() {
            Ok(())
        } else {
            Err(format!(
                "Audio server rejected the change: {}",
                self.context.errno()
            ))
        }
    }
}

/// One blocking subscription for the service, independent of inventory reads.
pub fn watch_default_output(notify: impl Fn() + Clone + 'static) {
    loop {
        let _ = watch_connection(notify.clone());
        thread::sleep(Duration::from_secs(5));
    }
}

fn watch_connection(notify: impl Fn() + Clone + 'static) -> Result<(), String> {
    let mut connection = Connection::new()?;
    let changed = notify.clone();
    connection
        .context
        .set_subscribe_callback(Some(Box::new(move |_, _, _| changed())));
    let result = Rc::new(Cell::new(false));
    let operation = connection.context.subscribe(
        InterestMaskSet::SINK | InterestMaskSet::SERVER,
        callback(&result),
    );
    connection.success(operation, result)?;
    notify();
    while connection.context.get_state() == State::Ready {
        if !matches!(connection.mainloop.iterate(true), IterateResult::Success(_)) {
            break;
        }
    }
    Ok(())
}

fn volumes(prefs: &DevicePrefs) -> Result<ChannelVolumes, String> {
    if prefs.channels.is_empty()
        || prefs.channels.len() > 32
        || prefs.channels.iter().any(|v| *v > Volume::MAX.0)
    {
        return Err("Invalid audio channel volumes".into());
    }
    let mut volume = ChannelVolumes::default();
    volume.set_len(prefs.channels.len() as u8);
    for (to, from) in volume.get_mut().iter_mut().zip(&prefs.channels) {
        *to = Volume(*from);
    }
    Ok(volume)
}
fn prefs(volume: &ChannelVolumes, muted: bool) -> DevicePrefs {
    DevicePrefs {
        channels: volume.get().iter().map(|v| v.0).collect(),
        muted,
    }
}
fn safe_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name.len() > 4096 || name.contains('\0') {
        Err("Invalid audio device name".into())
    } else {
        Ok(())
    }
}
fn callback(result: &Rc<Cell<bool>>) -> Box<dyn FnMut(bool)> {
    let out = result.clone();
    Box::new(move |success| out.set(success))
}
impl Backend for RealPulse {
    fn read(&mut self) -> Result<Snapshot, String> {
        let mut connection = Connection::new()?;
        let state = Rc::new(RefCell::new(Snapshot::default()));
        let out = state.clone();
        let op = connection.context.introspect().get_server_info(move |s| {
            let mut out = out.borrow_mut();
            out.default_output = s.default_sink_name.as_ref().map(|n| n.to_string());
            out.default_input = s.default_source_name.as_ref().map(|n| n.to_string());
        });
        connection.wait(op)?;
        let error = Rc::new(Cell::new(false));
        let failed = error.clone();
        let out = state.clone();
        let op = connection
            .context
            .introspect()
            .get_sink_info_list(move |result| match result {
                ListResult::Item(s) => {
                    if let Some(name) = &s.name {
                        out.borrow_mut().devices.push(Device {
                            name: name.to_string(),
                            index: s.index,
                            description: s
                                .description
                                .as_ref()
                                .map_or_else(|| name.to_string(), |s| s.to_string()),
                            direction: Direction::Output,
                            preferences: prefs(&s.volume, s.mute),
                            rate: s.sample_spec.rate,
                            channels: s.sample_spec.channels,
                            state: format!("{:?}", s.state),
                        });
                    }
                }
                ListResult::Error => failed.set(true),
                ListResult::End => {}
            });
        connection.wait(op)?;
        let failed = error.clone();
        let out = state.clone();
        let op = connection
            .context
            .introspect()
            .get_source_info_list(move |result| match result {
                ListResult::Item(s) => {
                    if let Some(name) = &s.name {
                        out.borrow_mut().devices.push(Device {
                            name: name.to_string(),
                            index: s.index,
                            description: s
                                .description
                                .as_ref()
                                .map_or_else(|| name.to_string(), |s| s.to_string()),
                            direction: Direction::Input,
                            preferences: prefs(&s.volume, s.mute),
                            rate: s.sample_spec.rate,
                            channels: s.sample_spec.channels,
                            state: format!("{:?}", s.state),
                        });
                    }
                }
                ListResult::Error => failed.set(true),
                ListResult::End => {}
            });
        connection.wait(op)?;
        let devices = state.borrow().devices.clone();
        let failed = error.clone();
        let out = state.clone();
        let op =
            connection
                .context
                .introspect()
                .get_sink_input_info_list(move |result| match result {
                    ListResult::Item(s) => out.borrow_mut().streams.push(Stream {
                        index: s.index,
                        client: s.client,
                        name: s.name.as_ref().map_or_else(String::new, |s| s.to_string()),
                        application: s
                            .proplist
                            .get_str("application.name")
                            .unwrap_or_else(|| "Audio application".into()),
                        direction: Direction::Output,
                        device: devices
                            .iter()
                            .find(|d| d.direction == Direction::Output && d.index == s.sink)
                            .map_or_else(String::new, |d| d.name.clone()),
                        preferences: prefs(&s.volume, s.mute),
                        has_volume: s.has_volume,
                        volume_writable: s.volume_writable,
                    }),
                    ListResult::Error => failed.set(true),
                    ListResult::End => {}
                });
        connection.wait(op)?;
        let devices = state.borrow().devices.clone();
        let failed = error.clone();
        let out = state.clone();
        let op = connection
            .context
            .introspect()
            .get_source_output_info_list(move |result| match result {
                ListResult::Item(s) => out.borrow_mut().streams.push(Stream {
                    index: s.index,
                    client: s.client,
                    name: s.name.as_ref().map_or_else(String::new, |s| s.to_string()),
                    application: s
                        .proplist
                        .get_str("application.name")
                        .unwrap_or_else(|| "Recording application".into()),
                    direction: Direction::Input,
                    device: devices
                        .iter()
                        .find(|d| d.direction == Direction::Input && d.index == s.source)
                        .map_or_else(String::new, |d| d.name.clone()),
                    preferences: prefs(&s.volume, s.mute),
                    has_volume: s.has_volume,
                    volume_writable: s.volume_writable,
                }),
                ListResult::Error => failed.set(true),
                ListResult::End => {}
            });
        connection.wait(op)?;
        if error.get() {
            return Err("Cannot read the complete audio inventory".into());
        }
        let mut snapshot = state.borrow().clone();
        snapshot.devices.sort_by(|a, b| {
            a.description
                .to_lowercase()
                .cmp(&b.description.to_lowercase())
        });
        Ok(snapshot)
    }
    fn set_default(&mut self, direction: Direction, name: &str) -> Result<(), String> {
        safe_name(name)?;
        let mut c = Connection::new()?;
        let result = Rc::new(Cell::new(false));
        let out = result.clone();
        let op = match direction {
            Direction::Output => c.context.set_default_sink(name, move |v| out.set(v)),
            Direction::Input => c.context.set_default_source(name, move |v| out.set(v)),
        };
        c.success(op, result)
    }
    fn set_device(
        &mut self,
        direction: Direction,
        name: &str,
        p: &DevicePrefs,
        operation: &str,
    ) -> Result<(), String> {
        safe_name(name)?;
        let mut c = Connection::new()?;
        if operation.ends_with("-volume") {
            let volume = volumes(p)?;
            let result = Rc::new(Cell::new(false));
            let op = match direction {
                Direction::Output => c.context.introspect().set_sink_volume_by_name(
                    name,
                    &volume,
                    Some(callback(&result)),
                ),
                Direction::Input => c.context.introspect().set_source_volume_by_name(
                    name,
                    &volume,
                    Some(callback(&result)),
                ),
            };
            return c.success(op, result);
        }
        let result = Rc::new(Cell::new(false));
        let op = match direction {
            Direction::Output => {
                c.context
                    .introspect()
                    .set_sink_mute_by_name(name, p.muted, Some(callback(&result)))
            }
            Direction::Input => c.context.introspect().set_source_mute_by_name(
                name,
                p.muted,
                Some(callback(&result)),
            ),
        };
        c.success(op, result)
    }
    fn set_stream(&mut self, s: &Stream, operation: &str) -> Result<(), String> {
        let mut c = Connection::new()?;
        if operation == "sound.stream-volume" {
            let volume = volumes(&s.preferences)?;
            let result = Rc::new(Cell::new(false));
            let op = match s.direction {
                Direction::Output => c.context.introspect().set_sink_input_volume(
                    s.index,
                    &volume,
                    Some(callback(&result)),
                ),
                Direction::Input => c.context.introspect().set_source_output_volume(
                    s.index,
                    &volume,
                    Some(callback(&result)),
                ),
            };
            c.success(op, result)?;
        }
        if operation == "sound.stream-muted" {
            let result = Rc::new(Cell::new(false));
            let op = match s.direction {
                Direction::Output => c.context.introspect().set_sink_input_mute(
                    s.index,
                    s.preferences.muted,
                    Some(callback(&result)),
                ),
                Direction::Input => c.context.introspect().set_source_output_mute(
                    s.index,
                    s.preferences.muted,
                    Some(callback(&result)),
                ),
            };
            c.success(op, result)?;
        }
        if operation != "sound.stream-device" {
            return Ok(());
        }
        safe_name(&s.device)?;
        let result = Rc::new(Cell::new(false));
        let op = match s.direction {
            Direction::Output => c.context.introspect().move_sink_input_by_name(
                s.index,
                &s.device,
                Some(callback(&result)),
            ),
            Direction::Input => c.context.introspect().move_source_output_by_name(
                s.index,
                &s.device,
                Some(callback(&result)),
            ),
        };
        c.success(op, result)
    }
}
