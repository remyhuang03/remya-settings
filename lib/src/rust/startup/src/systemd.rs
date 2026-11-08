use gio::glib::{self, variant::ToVariant};
use std::path::PathBuf;

#[derive(Default)]
pub struct Runtime {
    pub session_autostart: bool,
    pub units: Vec<Unit>,
}
#[derive(Clone)]
pub struct Unit {
    pub source: PathBuf,
    pub active: String,
    pub sub: String,
    pub result: String,
}
impl Unit {
    pub fn status(&self) -> &'static str {
        match (
            self.active.as_str(),
            self.sub.as_str(),
            self.result.as_str(),
        ) {
            ("active", "running", _) => "running",
            ("failed", _, _) => "failed",
            ("active", "exited", _) | ("inactive", _, "success") => "finished",
            (_, _, result) if !result.is_empty() && result != "success" => "failed",
            _ => "not-started",
        }
    }
}
pub trait Systemd: Send {
    fn read(&self) -> Result<Runtime, String>;
}
pub struct RealSystemd;
const DEST: &str = "org.freedesktop.systemd1";
const MANAGER: &str = "/org/freedesktop/systemd1";
impl Systemd for RealSystemd {
    fn read(&self) -> Result<Runtime, String> {
        let bus = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE)
            .map_err(|e| e.to_string())?;
        let call =
            |path: &str, interface: &str, method: &str, args: &glib::Variant, reply: &str| {
                let reply_type = glib::VariantTy::new(reply).map_err(|e| e.to_string())?;
                bus.call_sync(
                    Some(DEST),
                    path,
                    interface,
                    method,
                    Some(args),
                    Some(reply_type),
                    gio::DBusCallFlags::NO_AUTO_START,
                    2000,
                    gio::Cancellable::NONE,
                )
                .map_err(|e| e.to_string())
            };
        let property = |path: &str, interface: &str, name: &str| -> Result<String, String> {
            call(
                path,
                "org.freedesktop.DBus.Properties",
                "Get",
                &(interface, name).to_variant(),
                "(v)",
            )?
            .child_value(0)
            .as_variant()
            .and_then(|v| v.get::<String>())
            .ok_or_else(|| format!("Invalid systemd {name} property"))
        };
        let target = call(
            MANAGER,
            "org.freedesktop.systemd1.Manager",
            "LoadUnit",
            &("xdg-desktop-autostart.target",).to_variant(),
            "(o)",
        )?;
        let target_path = target.child_value(0);
        let session_autostart = property(
            target_path.str().ok_or("Invalid systemd target path")?,
            "org.freedesktop.systemd1.Unit",
            "ActiveState",
        )? == "active";
        let reply = call(
            MANAGER,
            "org.freedesktop.systemd1.Manager",
            "ListUnitsByPatterns",
            &(Vec::<String>::new(), vec!["app-*@autostart.service"]).to_variant(),
            "(a(ssssssouso))",
        )?;
        let mut units = vec![];
        for row in reply.child_value(0).iter() {
            let text = |i| {
                row.child_value(i)
                    .str()
                    .map(str::to_owned)
                    .ok_or("Invalid systemd unit row")
            };
            let path = text(6)?;
            units.push(Unit {
                source: property(&path, "org.freedesktop.systemd1.Unit", "SourcePath")?.into(),
                active: text(3)?,
                sub: text(4)?,
                result: property(&path, "org.freedesktop.systemd1.Service", "Result")?,
            });
        }
        Ok(Runtime {
            session_autostart,
            units,
        })
    }
}
