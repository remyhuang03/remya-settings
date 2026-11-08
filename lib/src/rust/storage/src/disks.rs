use crate::{
    invalid,
    scan::{Usage, usage},
};
use gio::{
    glib::{Variant, variant::ToVariant},
    prelude::*,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::BTreeMap, fs, os::unix::fs::MetadataExt, path::Path};
const PREFIX: &str = "org.freedesktop.UDisks2.";
pub type Objects = BTreeMap<String, BTreeMap<String, BTreeMap<String, Value>>>;
pub trait Disks: Send + Sync {
    fn objects(&self) -> Result<Objects, String>;
    fn call(
        &self,
        path: &str,
        interface: &str,
        method: &str,
        label: Option<&str>,
    ) -> Result<(), String>;
    fn open(&self, path: &Path) -> Result<(), String>;
}
pub struct RealDisks;
fn connection() -> Result<gio::DBusConnection, String> {
    gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE)
        .map_err(|e| format!("Unavailable:UDisks2 system bus: {e}"))
}
fn value(v: &Variant) -> Value {
    match v.type_().as_str() {
        "v" => value(&v.as_variant().unwrap()),
        "s" | "o" | "g" => json!(v.str().unwrap_or("")),
        "b" => json!(v.get::<bool>().unwrap_or(false)),
        "t" => json!(v.get::<u64>().unwrap_or(0)),
        "u" => json!(v.get::<u32>().unwrap_or(0)),
        "x" => json!(v.get::<i64>().unwrap_or(0)),
        "i" => json!(v.get::<i32>().unwrap_or(0)),
        "y" => json!(v.get::<u8>().unwrap_or(0)),
        _ if v.type_().as_str().starts_with('a') => Value::Array(
            (0..v.n_children())
                .map(|i| value(&v.child_value(i)))
                .collect(),
        ),
        _ => Value::Null,
    }
}
impl Disks for RealDisks {
    fn objects(&self) -> Result<Objects, String> {
        let reply = connection()?
            .call_sync(
                Some("org.freedesktop.UDisks2"),
                "/org/freedesktop/UDisks2",
                "org.freedesktop.DBus.ObjectManager",
                "GetManagedObjects",
                None,
                None,
                gio::DBusCallFlags::NONE,
                10_000,
                gio::Cancellable::NONE,
            )
            .map_err(|e| format!("Unavailable:UDisks2: {e}"))?;
        let objects = reply.child_value(0);
        let mut result = Objects::new();
        for i in 0..objects.n_children() {
            let entry = objects.child_value(i);
            let id = entry.child_value(0).str().unwrap().to_string();
            let interfaces = entry.child_value(1);
            let mut parsed = BTreeMap::new();
            for j in 0..interfaces.n_children() {
                let interface = interfaces.child_value(j);
                let name = interface.child_value(0).str().unwrap().to_string();
                let props = interface.child_value(1);
                let mut map = BTreeMap::new();
                for k in 0..props.n_children() {
                    let p = props.child_value(k);
                    map.insert(
                        p.child_value(0).str().unwrap().to_string(),
                        value(&p.child_value(1)),
                    );
                }
                parsed.insert(name, map);
            }
            result.insert(id, parsed);
        }
        Ok(result)
    }
    fn call(
        &self,
        path: &str,
        interface: &str,
        method: &str,
        label: Option<&str>,
    ) -> Result<(), String> {
        let options = BTreeMap::<String, Variant>::new();
        let parameters = match label {
            Some(label) => (label, options).to_variant(),
            None => (options,).to_variant(),
        };
        connection()?
            .call_sync(
                Some("org.freedesktop.UDisks2"),
                path,
                &format!("{PREFIX}{interface}"),
                method,
                Some(&parameters),
                None,
                gio::DBusCallFlags::ALLOW_INTERACTIVE_AUTHORIZATION,
                120_000,
                gio::Cancellable::NONE,
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    fn open(&self, path: &Path) -> Result<(), String> {
        gio::AppInfo::launch_default_for_uri(
            &gio::File::for_path(path).uri(),
            gio::AppLaunchContext::NONE,
        )
        .map_err(|e| e.to_string())
    }
}
fn prop<'a>(objects: &'a Objects, id: &str, interface: &str, key: &str) -> Option<&'a Value> {
    objects
        .get(id)?
        .get(&format!("{PREFIX}{interface}"))?
        .get(key)
}
fn text(objects: &Objects, id: &str, interface: &str, key: &str) -> String {
    prop(objects, id, interface, key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .into()
}
fn flag(objects: &Objects, id: &str, interface: &str, key: &str) -> bool {
    prop(objects, id, interface, key)
        .and_then(Value::as_bool)
        .unwrap_or(false)
}
fn number(objects: &Objects, id: &str, interface: &str, key: &str) -> u64 {
    prop(objects, id, interface, key)
        .and_then(Value::as_u64)
        .unwrap_or(0)
}
fn bytes(v: &Value) -> String {
    if let Some(s) = v.as_str() {
        return s.trim_end_matches('\0').into();
    }
    let b = v
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(Value::as_u64)
                .map(|b| b as u8)
                .take_while(|b| *b != 0)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    String::from_utf8_lossy(&b).into()
}
#[derive(Clone, Serialize)]
pub struct Drive {
    pub id: String,
    pub model: String,
    pub vendor: String,
    pub size: u64,
    pub removable: bool,
    pub media_removable: bool,
    pub ejectable: bool,
    pub can_power_off: bool,
    pub connection: String,
    pub rotational: bool,
    pub volumes: Vec<Volume>,
}
#[derive(Clone, Serialize)]
pub struct Volume {
    pub id: String,
    pub device: String,
    pub label: String,
    pub fs_type: String,
    pub size: u64,
    pub offset: u64,
    pub number: u64,
    pub mount_points: Vec<String>,
    pub usage: Option<Usage>,
    pub system: bool,
    pub can_mount: bool,
    pub can_unmount: bool,
    pub can_rename: bool,
}
pub fn parse(objects: &Objects, home: &Path) -> Vec<Drive> {
    let home_dev = fs::metadata(home).ok().map(|m| m.dev());
    let mut drives = Vec::new();
    for (id, interfaces) in objects {
        let loop_file = prop(objects, id, "Loop", "BackingFile")
            .map(bytes)
            .unwrap_or_default();
        let loop_drive = interfaces.contains_key(&format!("{PREFIX}Loop"))
            && !loop_file.is_empty()
            && ["", "/"].contains(&text(objects, id, "Block", "Drive").as_str());
        if !interfaces.contains_key(&format!("{PREFIX}Drive")) && !loop_drive {
            continue;
        }
        let bus = text(objects, id, "Drive", "ConnectionBus");
        let mut drive = Drive {
            id: id.clone(),
            model: if loop_drive {
                format!("Loop: {loop_file}")
            } else {
                text(objects, id, "Drive", "Model")
            },
            vendor: text(objects, id, "Drive", "Vendor"),
            size: if loop_drive {
                number(objects, id, "Block", "Size")
            } else {
                number(objects, id, "Drive", "Size")
            },
            removable: flag(objects, id, "Drive", "Removable"),
            media_removable: flag(objects, id, "Drive", "MediaRemovable"),
            ejectable: flag(objects, id, "Drive", "Ejectable"),
            can_power_off: flag(objects, id, "Drive", "CanPowerOff"),
            connection: match bus.as_str() {
                "usb" | "nvme" | "sata" | "sdio" => bus,
                "ata" => "sata".into(),
                _ if interfaces.contains_key(&format!("{PREFIX}Drive.Ata")) => "sata".into(),
                _ => "other".into(),
            },
            rotational: prop(objects, id, "Drive", "RotationRate")
                .and_then(Value::as_i64)
                .is_some_and(|rate| rate != 0),
            volumes: Vec::new(),
        };
        for (block, ifs) in objects {
            if !ifs.contains_key(&format!("{PREFIX}Block"))
                || flag(objects, block, "Block", "HintIgnore")
            {
                continue;
            }
            let backing = text(objects, block, "Block", "CryptoBackingDevice");
            let base = if !backing.is_empty() && backing != "/" {
                &backing
            } else {
                block
            };
            if (text(objects, base, "Block", "Drive") != *id && !(loop_drive && base == id))
                || flag(objects, base, "Block", "HintIgnore")
            {
                continue;
            }
            let device = prop(objects, block, "Block", "PreferredDevice")
                .or_else(|| prop(objects, block, "Block", "Device"))
                .map(bytes)
                .unwrap_or_default();
            if device.contains("zram") {
                continue;
            }
            if ifs.contains_key(&format!("{PREFIX}Loop"))
                && prop(objects, block, "Loop", "BackingFile")
                    .map(bytes)
                    .unwrap_or_default()
                    .is_empty()
            {
                continue;
            }
            let fs_type = text(objects, block, "Block", "IdType");
            let filesystem = ifs.contains_key(&format!("{PREFIX}Filesystem"));
            // Show the unlocked filesystem once, using its backing partition geometry.
            if fs_type == "crypto_LUKS"
                && objects
                    .keys()
                    .any(|b| text(objects, b, "Block", "CryptoBackingDevice") == *block)
            {
                continue;
            }
            if !filesystem
                && !ifs.contains_key(&format!("{PREFIX}Partition"))
                && fs_type != "swap"
                && fs_type != "crypto_LUKS"
            {
                continue;
            }
            let mount_points = prop(objects, block, "Filesystem", "MountPoints")
                .and_then(Value::as_array)
                .map(|a| a.iter().map(bytes).collect::<Vec<_>>())
                .unwrap_or_default();
            let system = fs_type == "swap"
                || mount_points.iter().any(|p| {
                    ["/", "/boot", "/efi", "/boot/efi", "/home", "/usr", "/var"]
                        .contains(&p.as_str())
                        || fs::metadata(p).is_ok_and(|m| Some(m.dev()) == home_dev)
                });
            let usage = mount_points.first().and_then(|p| usage(Path::new(p)).ok());
            if drive.connection == "other" {
                drive.connection = if device.contains("nvme") {
                    "nvme"
                } else if device.contains("mmcblk") {
                    "sdio"
                } else {
                    "other"
                }
                .into();
            }
            drive.volumes.push(Volume {
                id: block.clone(),
                device,
                label: text(objects, block, "Block", "IdLabel"),
                fs_type,
                size: number(objects, base, "Block", "Size"),
                offset: number(objects, base, "Partition", "Offset"),
                number: number(objects, base, "Partition", "Number"),
                can_mount: filesystem && mount_points.is_empty(),
                can_unmount: filesystem && !mount_points.is_empty() && !system,
                can_rename: filesystem && !flag(objects, block, "Block", "ReadOnly"),
                mount_points,
                usage,
                system,
            });
        }
        drive.volumes.sort_by_key(|v| v.offset);
        drives.push(drive);
    }
    drives
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Mount {
    pub volume: String,
    pub action: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Eject {
    pub drive: String,
    pub action: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Label {
    pub volume: String,
    pub label: String,
}
pub fn valid_label(label: &str) -> bool {
    label.len() <= 255 && !label.chars().any(|c| c.is_control() || c == '/')
}
pub fn operate(
    disks: &dyn Disks,
    home: &Path,
    id: &str,
    payload: &str,
) -> Result<Vec<Drive>, String> {
    let objects = disks.objects()?;
    let drives = parse(&objects, home);
    match id {
        "storage.mount" => {
            let p: Mount = crate::payload(payload)?;
            let v = drives
                .iter()
                .flat_map(|d| &d.volumes)
                .find(|v| v.id == p.volume)
                .ok_or_else(|| invalid("Unknown volume object path"))?;
            match p.action.as_str() {
                "mount" if v.can_mount => disks.call(&v.id, "Filesystem", "Mount", None)?,
                "unmount" if v.can_unmount => disks.call(&v.id, "Filesystem", "Unmount", None)?,
                _ => return Err(invalid("Mount action is unavailable for this volume")),
            }
        }
        "storage.label" => {
            let p: Label = crate::payload(payload)?;
            if !valid_label(&p.label) {
                return Err(invalid(
                    "Label must be at most 255 bytes, with no / or control characters",
                ));
            }
            let v = drives
                .iter()
                .flat_map(|d| &d.volumes)
                .find(|v| v.id == p.volume && v.can_rename)
                .ok_or_else(|| invalid("Unknown or read-only volume"))?;
            disks.call(&v.id, "Filesystem", "SetLabel", Some(&p.label))?;
        }
        "storage.eject" => {
            let p: Eject = crate::payload(payload)?;
            let d = drives
                .iter()
                .find(|d| d.id == p.drive)
                .ok_or_else(|| invalid("Unknown drive object path"))?;
            let method = match p.action.as_str() {
                "eject" if d.ejectable => "Eject",
                "power-off" if d.can_power_off => "PowerOff",
                _ => return Err(invalid("Drive action is unavailable")),
            };
            // Ignored blocks stay hidden, but must still protect an entire physical drive.
            let mut safety_objects = objects.clone();
            for interfaces in safety_objects.values_mut() {
                if let Some(block) = interfaces.get_mut(&format!("{PREFIX}Block")) {
                    block.remove("HintIgnore");
                }
            }
            let all = parse(&safety_objects, home);
            let all_volumes = all
                .iter()
                .find(|drive| drive.id == d.id)
                .map(|drive| drive.volumes.as_slice())
                .unwrap_or(&[]);
            if all_volumes.iter().any(|v| v.system) {
                return Err(invalid("Cannot eject a drive with a system volume"));
            }
            if all_volumes.iter().any(|v| {
                !v.mount_points.is_empty() && !d.volumes.iter().any(|visible| visible.id == v.id)
            }) {
                return Err(invalid("Drive contains a mounted volume hidden by UDisks2"));
            }
            for v in &d.volumes {
                if !v.mount_points.is_empty() {
                    disks.call(&v.id, "Filesystem", "Unmount", None)?;
                }
            }
            disks.call(&d.id, "Drive", method, None)?;
        }
        _ => return Err(invalid("Unknown disk action")),
    }
    let next = parse(&disks.objects()?, home);
    if id == "storage.label" {
        let p: Label = crate::payload(payload)?;
        if !next
            .iter()
            .flat_map(|d| &d.volumes)
            .any(|v| v.id == p.volume && v.label == p.label)
        {
            return Err("Conflict:Volume label readback differs".into());
        }
    }
    if id == "storage.mount" {
        let p: Mount = crate::payload(payload)?;
        if !next
            .iter()
            .flat_map(|d| &d.volumes)
            .any(|v| v.id == p.volume && (p.action == "mount") != v.mount_points.is_empty())
        {
            return Err("Conflict:Mount readback differs".into());
        }
    }
    Ok(next)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn decodes_signed_rotation_rate_and_normalizes_connection_bus() {
        assert_eq!(value(&7200_i32.to_variant()), json!(7200));
        assert_eq!(value(&(-1_i32).to_variant()), json!(-1));
        for (bus, expected) in [("ata", "sata"), ("usb", "usb"), ("unknown", "other")] {
            let objects:Objects=serde_json::from_value(json!({"/drive":{"org.freedesktop.UDisks2.Drive":{"RotationRate":-1,"ConnectionBus":bus}}})).unwrap();
            let drives = parse(&objects, Path::new("/home"));
            assert!(drives[0].rotational);
            assert_eq!(drives[0].connection, expected);
        }
    }
}
