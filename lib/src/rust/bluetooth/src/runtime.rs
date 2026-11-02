use super::*;
use gio::glib::{self, variant::ToVariant};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
    time::Instant,
};

const AGENT_XML: &str = r#"<node><interface name="org.bluez.Agent1">
<method name="Release"/><method name="Cancel"/>
<method name="RequestPinCode"><arg type="o"/><arg type="s" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o"/><arg type="s"/></method>
<method name="RequestPasskey"><arg type="o"/><arg type="u" direction="out"/></method>
<method name="DisplayPasskey"><arg type="o"/><arg type="u"/><arg type="q"/></method>
<method name="RequestConfirmation"><arg type="o"/><arg type="u"/></method>
<method name="RequestAuthorization"><arg type="o"/></method>
<method name="AuthorizeService"><arg type="o"/><arg type="s"/></method>
</interface></node>"#;

type Shared = Rc<RefCell<Runtime>>;
struct Runtime {
    bus: gio::DBusConnection,
    owner: Option<String>,
    registered: bool,
    objects: Objects,
    scans: HashMap<String, Instant>,
    stopping: std::collections::HashSet<String>,
    scan_generation: u64,
    operation: Value,
    prompt: Value,
    pending: Option<gio::DBusMethodInvocation>,
    next: u64,
    deadline: Option<Instant>,
    error: Option<String>,
    available: bool,
    output: Arc<Mutex<Value>>,
    dirty: Arc<AtomicBool>,
}
impl Runtime {
    fn publish(&self) -> Value {
        let mut value = snapshot(&self.objects);
        value["available"] = json!(self.available);
        value["error"] = json!(self.error);
        value["operation"] = self.operation.clone();
        value["prompt"] = self.prompt.clone();
        let mut scans = self.scans.keys().cloned().collect::<Vec<_>>();
        scans.sort();
        value["scanning"] = json!(scans);
        let mut saved = self.output.lock().unwrap();
        if *saved != value {
            *saved = value.clone();
            self.dirty.store(true, Ordering::Release);
        }
        value
    }
    fn sync(
        &self,
        destination: &str,
        path: &str,
        interface: &str,
        method: &str,
        args: Option<&Variant>,
    ) -> Result<Variant, String> {
        self.bus
            .call_sync(
                Some(destination),
                path,
                interface,
                method,
                args,
                None,
                gio::DBusCallFlags::NO_AUTO_START,
                3000,
                gio::Cancellable::NONE,
            )
            .map_err(|e| e.to_string())
    }
    fn refresh(&mut self) {
        let owner = self
            .sync(
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "GetNameOwner",
                Some(&(BLUEZ,).to_variant()),
            )
            .ok()
            .and_then(|v| v.get::<(String,)>().map(|v| v.0));
        if self.owner != owner {
            self.registered = false;
            self.scans.clear();
            self.stopping.clear();
            if self.running() {
                self.finish(Err("Bluetooth service changed during the operation".into()));
            }
            self.owner = owner;
        }
        let result = self
            .owner
            .as_deref()
            .ok_or_else(|| "Bluetooth service is not running".to_owned())
            .and_then(|owner| {
                self.sync(
                    owner,
                    "/",
                    "org.freedesktop.DBus.ObjectManager",
                    "GetManagedObjects",
                    None,
                )
            })
            .and_then(|v| {
                v.get::<(Objects,)>()
                    .map(|v| v.0)
                    .ok_or_else(|| "Invalid BlueZ device state".into())
            });
        match result {
            Ok(objects) => {
                self.objects = objects;
                self.available = true;
                if self.error.as_deref().is_some_and(|e| {
                    e == "Bluetooth service is not running" || e == "Invalid BlueZ device state"
                }) {
                    self.error = None;
                }
                self.scans.retain(|path, _| {
                    self.objects.iter().any(|(p, interfaces)| {
                        p.as_str() == path
                            && interfaces.get(ADAPTER).is_some_and(|p| flag(p, "Powered"))
                    })
                });
                if self.running() {
                    let path = self.operation["device"]
                        .as_str()
                        .or_else(|| self.operation["adapter"].as_str())
                        .unwrap_or_default();
                    if self.operation["kind"] != "forget"
                        && !self.objects.keys().any(|p| p.as_str() == path)
                    {
                        self.finish(Err("Bluetooth device or adapter was removed".into()));
                    }
                }
            }
            Err(error) => {
                self.available = false;
                self.error = Some(error);
            }
        }
        self.publish();
    }
    fn running(&self) -> bool {
        self.operation["status"] == "running"
    }
    fn finish(&mut self, result: Result<(), String>) {
        self.reject_prompt("Canceled");
        self.deadline = None;
        match result {
            Ok(()) => {
                self.operation["status"] = json!("completed");
                self.error = None;
            }
            Err(error) => {
                self.operation["status"] = json!("failed");
                self.error = Some(error);
            }
        }
        self.publish();
    }
    fn reject_prompt(&mut self, kind: &str) {
        if let Some(invocation) = self.pending.take() {
            invocation
                .return_dbus_error(&format!("org.bluez.Error.{kind}"), "Pairing request ended");
        }
        self.prompt = Value::Null;
    }
    fn adapter(&self, request: &Request) -> Result<String, String> {
        let path = request
            .adapter
            .as_deref()
            .ok_or_else(|| invalid("An adapter is required"))?;
        if !self
            .objects
            .iter()
            .any(|(p, i)| p.as_str() == path && i.contains_key(ADAPTER))
        {
            return Err(invalid("Adapter no longer exists"));
        }
        Ok(path.into())
    }
    fn device(&self, request: &Request) -> Result<String, String> {
        let adapter = self.adapter(request)?;
        let path = request
            .device
            .as_deref()
            .ok_or_else(|| invalid("A device is required"))?;
        if !self.objects.iter().any(|(p, i)| {
            p.as_str() == path
                && i.get(DEVICE)
                    .is_some_and(|d| string(d, "Adapter").as_deref() == Some(&adapter))
        }) {
            return Err(invalid("Device does not belong to this adapter"));
        }
        Ok(path.into())
    }
    fn respond(&mut self, request: &Request) -> Result<Value, String> {
        if self.pending.is_none() || request.request != self.prompt["id"].as_u64() {
            return Err(invalid("Pairing request expired"));
        }
        if request.accept == Some(false) {
            self.reject_prompt("Rejected");
            return Ok(self.publish());
        }
        let reply = match self.prompt["kind"].as_str().unwrap_or_default() {
            "RequestPinCode" => {
                let pin = request
                    .pin
                    .as_deref()
                    .filter(|s| {
                        !s.is_empty()
                            && s.len() <= 16
                            && s.chars().all(|c| c.is_ascii_alphanumeric())
                    })
                    .ok_or_else(|| invalid("PIN must contain 1 to 16 ASCII letters or digits"))?;
                (pin,).to_variant()
            }
            "RequestPasskey" => (request
                .passkey
                .filter(|p| *p <= 999_999)
                .ok_or_else(|| invalid("Passkey must be between 000000 and 999999"))?,)
                .to_variant(),
            _ => {
                if request.accept != Some(true) {
                    return Err(invalid("Confirm or reject this pairing request"));
                }
                ().to_variant()
            }
        };
        self.pending.take().unwrap().return_value(Some(&reply));
        self.prompt = Value::Null;
        Ok(self.publish())
    }
}

async fn call(
    bus: &gio::DBusConnection,
    owner: &str,
    path: &str,
    interface: &str,
    method: &str,
    args: Option<&Variant>,
    timeout: i32,
) -> Result<Variant, String> {
    bus.call_future(
        Some(owner),
        path,
        interface,
        method,
        args,
        None,
        gio::DBusCallFlags::NO_AUTO_START,
        timeout,
    )
    .await
    .map_err(|e| e.to_string())
}
fn spawn(context: &glib::MainContext, work: impl std::future::Future<Output = ()> + 'static) {
    drop(context.spawn_local(work));
}

fn stop_scan(state: &Shared, path: String) {
    let (bus, owner) = {
        let mut s = state.borrow_mut();
        s.scan_generation += 1;
        if s.scans.remove(&path).is_none() {
            return;
        }
        s.stopping.insert(path.clone());
        s.publish();
        (s.bus.clone(), s.owner.clone())
    };
    let Some(owner) = owner else { return };
    let state = state.clone();
    spawn(&glib::MainContext::ref_thread_default(), async move {
        let result = call(&bus, &owner, &path, ADAPTER, "StopDiscovery", None, 5000).await;
        let filter = HashMap::<String, Variant>::new();
        let cleared = call(
            &bus,
            &owner,
            &path,
            ADAPTER,
            "SetDiscoveryFilter",
            Some(&(filter,).to_variant()),
            5000,
        )
        .await;
        let mut s = state.borrow_mut();
        s.stopping.remove(&path);
        if s.owner.as_deref() == Some(&owner) {
            if let Err(error) = result {
                s.error = Some(format!("Cannot stop Bluetooth scan: {error}"));
                // Keep ownership on failure so cleanup can be retried.
                s.scans
                    .insert(path, Instant::now() + Duration::from_secs(5));
            } else if let Err(error) = cleared {
                s.error = Some(format!("Cannot clear Bluetooth scan filter: {error}"));
            }
        }
        s.refresh();
    });
}
fn cancel(state: &Shared, reason: &str) {
    let (bus, owner, path) = {
        let mut s = state.borrow_mut();
        if !s.running() || s.operation["kind"] != "pair" {
            return;
        }
        let path = s.operation["device"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        s.reject_prompt("Canceled");
        s.operation["status"] = json!("cancelled");
        s.deadline = None;
        s.error = if reason.is_empty() {
            None
        } else {
            Some(reason.into())
        };
        s.publish();
        (s.bus.clone(), s.owner.clone(), path)
    };
    if let Some(owner) = owner {
        let state = state.clone();
        spawn(&glib::MainContext::ref_thread_default(), async move {
            let result = call(&bus, &owner, &path, DEVICE, "CancelPairing", None, 5000).await;
            if let Err(error) = result
                && !error.contains("org.bluez.Error.DoesNotExist")
            {
                let mut s = state.borrow_mut();
                s.error = Some(format!("Cannot cancel pairing: {error}"));
                s.publish();
            }
        });
    }
}
fn cleanup(state: &Shared) {
    state.borrow_mut().scan_generation += 1;
    cancel(state, "");
    let scans = state.borrow().scans.keys().cloned().collect::<Vec<_>>();
    for scan in scans {
        stop_scan(state, scan);
    }
}
fn agent(
    state: &Shared,
    sender: Option<&str>,
    method: &str,
    args: &Variant,
    invocation: gio::DBusMethodInvocation,
) {
    let mut s = state.borrow_mut();
    if sender != s.owner.as_deref() {
        invocation.return_dbus_error("org.bluez.Error.Rejected", "Unknown Bluetooth service");
        return;
    }
    if method == "Release" || method == "Cancel" {
        s.reject_prompt("Canceled");
        if method == "Release" {
            s.registered = false;
        }
        invocation.return_value(Some(&().to_variant()));
        s.publish();
        return;
    }
    let device = args.child_value(0).str().unwrap_or_default().to_owned();
    if !s.running() || s.operation["kind"] != "pair" || s.operation["device"] != device {
        invocation.return_dbus_error("org.bluez.Error.Rejected", "No matching pairing operation");
        return;
    }
    s.reject_prompt("Canceled");
    s.next += 1;
    s.prompt = json!({"id":s.next,"kind":method,"device":device});
    match method {
        "DisplayPinCode" => s.prompt["code"] = json!(args.child_value(1).str()),
        "DisplayPasskey" | "RequestConfirmation" => {
            s.prompt["code"] = json!(format!(
                "{:06}",
                args.child_value(1).get::<u32>().unwrap_or_default()
            ));
            if method == "DisplayPasskey" {
                s.prompt["entered"] = json!(args.child_value(2).get::<u16>());
            }
        }
        "AuthorizeService" => s.prompt["service"] = json!(args.child_value(1).str()),
        _ => {}
    }
    if method.starts_with("Display") {
        invocation.return_value(Some(&().to_variant()));
    } else {
        s.pending = Some(invocation);
    }
    s.publish();
}

fn command(state: &Shared, id: &str, request: Request) -> Result<Value, String> {
    if id == "read" {
        state.borrow_mut().refresh();
        return Ok(state.borrow().publish());
    }
    if id == "cleanup" {
        cleanup(state);
        return Ok(state.borrow().publish());
    }
    if id == "bluetooth.respond" {
        return state.borrow_mut().respond(&request);
    }
    if id == "bluetooth.cancel" {
        cancel(state, "");
        return Ok(state.borrow().publish());
    }
    let (bus, owner, adapter, device, serial) = {
        let mut s = state.borrow_mut();
        if !s.available {
            return Err("Unavailable:Bluetooth service is not available".into());
        }
        let adapter = s.adapter(&request)?;
        let device = if [
            "bluetooth.pair",
            "bluetooth.connect",
            "bluetooth.disconnect",
            "bluetooth.forget",
        ]
        .contains(&id)
        {
            Some(s.device(&request)?)
        } else {
            None
        };
        if id == "bluetooth.scan" || id == "bluetooth.discoverable" || id == "bluetooth.enabled" {
            request
                .enabled
                .ok_or_else(|| invalid("enabled must be true or false"))?;
        }
        if (id == "bluetooth.scan" || id == "bluetooth.discoverable")
            && request.enabled == Some(false)
        {
            drop(s);
            stop_scan(state, adapter);
            return Ok(state.borrow().publish());
        }
        if s.stopping.contains(&adapter) {
            return Err("Bluetooth scan cleanup is still in progress".into());
        }
        if s.running() {
            return Err("A Bluetooth operation is already in progress".into());
        }
        if !is_setting(id) {
            return Err(invalid("Unknown Bluetooth action"));
        }
        s.next += 1;
        let serial = s.next;
        s.operation = json!({"id":serial,"kind":id.trim_start_matches("bluetooth."),"status":"running","adapter":adapter,"device":device});
        s.error = None;
        if id == "bluetooth.pair" {
            s.deadline = Some(Instant::now() + Duration::from_secs(120));
        }
        s.publish();
        (
            s.bus.clone(),
            s.owner.clone().unwrap(),
            adapter,
            device,
            serial,
        )
    };
    let kind = id.to_owned();
    let state_clone = state.clone();
    spawn(&glib::MainContext::ref_thread_default(), async move {
        let result = perform(
            &state_clone,
            &bus,
            &owner,
            &kind,
            &adapter,
            device.as_deref(),
            request,
        )
        .await;
        let mut s = state_clone.borrow_mut();
        if s.operation["id"] == serial && s.running() {
            s.refresh();
            if s.running() {
                s.finish(result);
            }
        }
    });
    Ok(state.borrow().publish())
}
async fn perform(
    state: &Shared,
    bus: &gio::DBusConnection,
    owner: &str,
    kind: &str,
    adapter: &str,
    device: Option<&str>,
    request: Request,
) -> Result<(), String> {
    let serial = state.borrow().operation["id"].clone();
    let active = || {
        let s = state.borrow();
        s.running() && s.operation["id"] == serial && s.owner.as_deref() == Some(owner)
    };
    match kind {
        "bluetooth.enabled" => {
            let enabled = request.enabled.unwrap();
            call(
                bus,
                owner,
                adapter,
                PROPERTIES,
                "Set",
                Some(&(ADAPTER, "Powered", enabled.to_variant()).to_variant()),
                20_000,
            )
            .await?;
            let read = call(
                bus,
                owner,
                adapter,
                PROPERTIES,
                "Get",
                Some(&(ADAPTER, "Powered").to_variant()),
                5000,
            )
            .await?;
            if read.get::<(Variant,)>().and_then(|v| v.0.get::<bool>()) != Some(enabled) {
                return Err("Bluetooth power readback did not match".into());
            }
        }
        "bluetooth.scan" | "bluetooth.discoverable" => {
            let generation = state.borrow().scan_generation;
            let visible = kind == "bluetooth.discoverable";
            let filter = HashMap::from([
                ("Transport", "auto".to_variant()),
                ("Discoverable", visible.to_variant()),
            ]);
            call(
                bus,
                owner,
                adapter,
                ADAPTER,
                "SetDiscoveryFilter",
                Some(&(filter,).to_variant()),
                5000,
            )
            .await?;
            let existing = state.borrow().scans.contains_key(adapter);
            if !existing {
                call(bus, owner, adapter, ADAPTER, "StartDiscovery", None, 5000).await?;
            }
            state
                .borrow_mut()
                .scans
                .insert(adapter.into(), Instant::now() + Duration::from_secs(60));
            if state.borrow().scan_generation != generation || !active() {
                stop_scan(state, adapter.into());
            }
        }
        "bluetooth.pair" => {
            if !state.borrow().registered {
                let path = ObjectPath::try_from(AGENT_PATH).unwrap();
                call(
                    bus,
                    owner,
                    "/org/bluez",
                    "org.bluez.AgentManager1",
                    "RegisterAgent",
                    Some(&(path, "KeyboardDisplay").to_variant()),
                    5000,
                )
                .await?;
                if state.borrow().owner.as_deref() == Some(owner) {
                    state.borrow_mut().registered = true;
                }
            }
            if !active() {
                return Err("Pairing was cancelled".into());
            }
            let path = device.unwrap();
            // The service deadline must cancel BlueZ before the transport gives up.
            call(bus, owner, path, DEVICE, "Pair", None, 130_000).await?;
            if !active() {
                return Err("Pairing was cancelled".into());
            }
            {
                let mut s = state.borrow_mut();
                s.deadline = None;
                s.reject_prompt("Canceled");
                s.publish();
            }
            // A successful bond survives a failed profile connection.
            call(bus, owner, path, DEVICE, "Connect", None, 20_000)
                .await
                .map_err(|e| format!("Paired, but could not connect: {e}"))?;
            verify(bus, owner, path, "Paired", true).await?;
            verify(bus, owner, path, "Connected", true).await?;
        }
        "bluetooth.connect" | "bluetooth.disconnect" => {
            let connect = kind == "bluetooth.connect";
            call(
                bus,
                owner,
                device.unwrap(),
                DEVICE,
                if connect { "Connect" } else { "Disconnect" },
                None,
                20_000,
            )
            .await?;
            verify(bus, owner, device.unwrap(), "Connected", connect).await?;
        }
        "bluetooth.forget" => {
            let path =
                ObjectPath::try_from(device.unwrap()).map_err(|_| invalid("Invalid device"))?;
            call(
                bus,
                owner,
                adapter,
                ADAPTER,
                "RemoveDevice",
                Some(&(path,).to_variant()),
                20_000,
            )
            .await?;
            let value = call(
                bus,
                owner,
                "/",
                "org.freedesktop.DBus.ObjectManager",
                "GetManagedObjects",
                None,
                5000,
            )
            .await?;
            let objects = value.get::<(Objects,)>().ok_or("Invalid BlueZ state")?.0;
            if objects.iter().any(|(p, i)| {
                p.as_str() == device.unwrap()
                    && i.get(DEVICE)
                        .is_some_and(|p| flag(p, "Paired") || flag(p, "Bonded"))
            }) {
                return Err("Device is still paired after removal".into());
            }
        }
        _ => return Err(invalid("Unknown Bluetooth action")),
    }
    Ok(())
}
async fn verify(
    bus: &gio::DBusConnection,
    owner: &str,
    path: &str,
    property: &str,
    expected: bool,
) -> Result<(), String> {
    let value = call(
        bus,
        owner,
        path,
        PROPERTIES,
        "Get",
        Some(&(DEVICE, property).to_variant()),
        5000,
    )
    .await?;
    if value.get::<(Variant,)>().and_then(|v| v.0.get::<bool>()) != Some(expected) {
        return Err(format!("Bluetooth {property} readback did not match"));
    }
    Ok(())
}

pub(super) fn run(
    receiver: mpsc::Receiver<Command>,
    output: Arc<Mutex<Value>>,
    dirty: Arc<AtomicBool>,
) -> Result<(), String> {
    let context = glib::MainContext::new();
    context
        .with_thread_default(|| {
            let address =
                gio::dbus_address_get_for_bus_sync(gio::BusType::System, gio::Cancellable::NONE)
                    .map_err(|e| e.to_string())?;
            let bus = gio::DBusConnection::for_address_sync(
                &address,
                gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
                    | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
                None,
                gio::Cancellable::NONE,
            )
            .map_err(|e| e.to_string())?;
            let state = Rc::new(RefCell::new(Runtime {
                bus: bus.clone(),
                owner: None,
                registered: false,
                objects: Objects::new(),
                scans: HashMap::new(),
                stopping: std::collections::HashSet::new(),
                scan_generation: 0,
                operation: Value::Null,
                prompt: Value::Null,
                pending: None,
                next: 0,
                deadline: None,
                error: None,
                available: false,
                output,
                dirty,
            }));
            let weak = Rc::downgrade(&state);
            let info = gio::DBusNodeInfo::for_xml(AGENT_XML)
                .unwrap()
                .lookup_interface(AGENT)
                .unwrap();
            let registration = bus
                .register_object(AGENT_PATH, &info)
                .method_call(move |_, sender, _, _, method, args, invocation| {
                    if let Some(state) = weak.upgrade() {
                        agent(&state, sender, method, &args, invocation);
                    } else {
                        invocation
                            .return_dbus_error("org.bluez.Error.Canceled", "Settings stopped");
                    }
                })
                .build()
                .map_err(|e| e.to_string())?;
            let changed = Rc::new(Cell::new(false));
            let invalidate = changed.clone();
            let _objects = bus.subscribe_to_signal(
                Some(BLUEZ),
                None,
                None,
                None,
                None,
                gio::DBusSignalFlags::NONE,
                move |_| invalidate.set(true),
            );
            let invalidate = changed.clone();
            let _owner = bus.subscribe_to_signal(
                Some("org.freedesktop.DBus"),
                Some("org.freedesktop.DBus"),
                Some("NameOwnerChanged"),
                None,
                Some(BLUEZ),
                gio::DBusSignalFlags::NONE,
                move |_| invalidate.set(true),
            );
            state.borrow_mut().refresh();
            context.block_on(async {
                let mut next_refresh = Instant::now();
                let mut last_refresh = Instant::now();
                loop {
                    match receiver.try_recv() {
                        Ok(command_) => {
                            let result = command(&state, &command_.id, command_.request);
                            let _ = command_.reply.send(result);
                        }
                        Err(mpsc::TryRecvError::Disconnected) => {
                            cleanup(&state);
                            break;
                        }
                        Err(mpsc::TryRecvError::Empty) => {}
                    }
                    let now = Instant::now();
                    if now >= next_refresh
                        || (changed.get()
                            && now.duration_since(last_refresh) >= Duration::from_millis(250))
                    {
                        state.borrow_mut().refresh();
                        changed.set(false);
                        last_refresh = now;
                        next_refresh = now + Duration::from_secs(2);
                    }
                    let expired = state
                        .borrow()
                        .scans
                        .iter()
                        .filter(|(_, deadline)| **deadline <= now)
                        .map(|(path, _)| path.clone())
                        .collect::<Vec<_>>();
                    for path in expired {
                        stop_scan(&state, path);
                    }
                    if state.borrow().deadline.is_some_and(|d| d <= now) {
                        cancel(&state, "Bluetooth pairing timed out");
                    }
                    glib::timeout_future(Duration::from_millis(50)).await;
                }
                glib::timeout_future(Duration::from_millis(100)).await;
            });
            let _ = bus.unregister_object(registration);
            let _ = bus.close_sync(gio::Cancellable::NONE);
            Ok(())
        })
        .map_err(|e| e.to_string())?
}
