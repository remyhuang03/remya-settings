//! Fixed external configuration launchers; configuration remains owned by each tool.
use serde_json::{Value, json};
use std::{
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Stdio},
};
pub const IDS: [&str; 9] = [
    "time-more.fcitx5",
    "time-more.ibus",
    "system-more.kde",
    "system-more.gnome",
    "appearance-more.qt6ct",
    "appearance-more.kvantum",
    "appearance-more.gtk",
    "appearance-more.gnome-tweaks",
    "system-more.localsend",
];
const TOOLS: [(&str, &str, &str, &str); 9] = [
    (
        IDS[0],
        "Fcitx 5 Configuration",
        "fcitx5-configtool",
        "fcitx",
    ),
    (IDS[1], "IBus Preferences", "ibus-setup", "ibus-setup"),
    (
        IDS[2],
        "KDE System Settings",
        "systemsettings",
        "systemsettings",
    ),
    (
        IDS[3],
        "GNOME Settings",
        "gnome-control-center",
        "org.gnome.Settings",
    ),
    (
        IDS[4],
        "Qt 6 Settings",
        "qt6ct",
        "preferences-desktop-theme",
    ),
    (IDS[5], "Kvantum Manager", "kvantummanager", "kvantum"),
    (IDS[6], "GTK Settings", "nwg-look", "nwg-look"),
    (IDS[7], "GNOME Tweaks", "gnome-tweaks", "org.gnome.tweaks"),
    (IDS[8], "LocalSend", "localsend", "localsend"),
];
fn launch_error(id: &str) -> Option<&'static str> {
    if id == "system-more.gnome"
        && !std::env::var("XDG_CURRENT_DESKTOP")
            .unwrap_or_default()
            .split(':')
            .any(|d| d.eq_ignore_ascii_case("GNOME") || d.eq_ignore_ascii_case("Unity"))
    {
        Some("GNOME Settings only supports GNOME or Unity sessions")
    } else {
        None
    }
}
fn detected(root: &Path, group: &str) -> Value {
    json!({"tools":TOOLS.iter().filter(|(id,_,binary,_)|id.starts_with(&format!("{group}-more.")) && root.join(binary).metadata().is_ok_and(|m|m.is_file()&&m.permissions().mode()&0o111!=0)).map(|(id,name,_,icon)|json!({"id":id,"name":name,"icon":icon,"launch_error":launch_error(id)})).collect::<Vec<_>>()})
}
pub fn read(group: &str) -> Result<Value, String> {
    if !["time", "system", "appearance"].contains(&group) {
        return Err("InvalidArgument:Unknown external settings group".into());
    }
    Ok(detected(Path::new("/usr/bin"), group))
}
pub fn read_setting(id: &str) -> Result<Value, String> {
    if !IDS.contains(&id) {
        return Err("InvalidArgument:Unknown external settings tool".into());
    }
    read(id.split_once("-more.").unwrap().0)
}
pub fn open(id: &str) -> Result<Value, String> {
    if let Some(error) = launch_error(id) {
        return Err(format!("Unavailable:{error}"));
    }
    let (_, _, binary, _) = TOOLS
        .iter()
        .find(|(key, _, _, _)| *key == id)
        .ok_or("InvalidArgument:Unknown external settings tool")?;
    if !read_setting(id)?["tools"]
        .as_array()
        .unwrap()
        .iter()
        .any(|t| t["id"] == id)
    {
        return Err("Unavailable:External configuration tool is not installed".into());
    }
    let mut child = Command::new(Path::new("/usr/bin").join(binary))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Cannot open external configuration: {e}"))?;
    let pid = child.id();
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(json!({"opened":id,"pid":pid}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_installed_executable_tools_are_exposed() {
        let root = tempfile::tempdir().unwrap();
        assert!(
            detected(root.path(), "time")["tools"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        let file = root.path().join("fcitx5-configtool");
        std::fs::write(&file, "#!/bin/sh\nexit 0\n").unwrap();
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert!(
            detected(root.path(), "time")["tools"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        std::fs::set_permissions(file, std::fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(detected(root.path(), "time")["tools"][0]["id"], IDS[0]);
        let localsend = root.path().join("localsend");
        std::fs::write(&localsend, "").unwrap();
        assert!(
            detected(root.path(), "system")["tools"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        std::fs::set_permissions(localsend, std::fs::Permissions::from_mode(0o700)).unwrap();
        let tools = detected(root.path(), "system");
        assert_eq!(tools["tools"][0]["id"], "system-more.localsend");
        assert_eq!(tools["tools"][0]["name"], "LocalSend");
        assert_eq!(tools["tools"].as_array().unwrap().len(), 1);
        assert!(open("../../bin/sh").is_err());
        assert!(read("../../bin").is_err());
        assert!(
            detected(root.path(), "appearance")["tools"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }
}
