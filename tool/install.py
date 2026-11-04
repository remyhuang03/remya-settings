#!/usr/bin/env python3
"""Install a built release bundle in XDG_DATA_HOME without changing configuration."""
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import time

APP_ID = "remya_settings"
PACKAGE = "top.remya.settings"
UNIT = f"{PACKAGE}.service"


def data_home(environment):
    value = environment.get("XDG_DATA_HOME", "")
    if value.startswith("/"):
        return Path(value)
    home = environment.get("HOME", "")
    if not home.startswith("/"):
        raise ValueError("An absolute HOME or XDG_DATA_HOME is required")
    return Path(home) / ".local/share"


def desktop_quote(path):
    # Desktop Entry Exec quoting, followed by string-value escaping.
    value = str(path).replace("%", "%%")
    for character in ('\\', '"', '`', '$'):
        value = value.replace(character, "\\" + character)
    return '"' + value.replace("\\", "\\\\") + '"'


def unit_quote(path):
    # systemd.syntax: double-quoted word; % and $ are specifier/variable prefixes.
    value = str(path).replace("\\", "\\\\").replace('"', '\\"')
    return '"' + value.replace("%", "%%").replace("$", "$$") + '"'


def user_unit(executable):
    return (
        "[Unit]\nDescription=Remya Settings service\n"
        "PartOf=graphical-session.target\nAfter=graphical-session.target\n\n"
        f"[Service]\nType=dbus\nBusName={PACKAGE}.Service1\n"
        f"ExecStart={unit_quote(executable)} --service\nRestart=on-failure\n\n"
        "[Install]\nWantedBy=graphical-session.target\n")


def stop_service():
    """Ask a running service to quit; it refuses while a system update is running."""
    if not shutil.which("gdbus"):
        return False
    owner = subprocess.run(
        ["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus", "--object-path",
         "/org/freedesktop/DBus", "--method", "org.freedesktop.DBus.NameHasOwner",
         f"{PACKAGE}.Service1"], capture_output=True, text=True, timeout=10)
    if "true" not in owner.stdout:
        return False
    result = subprocess.run(
        ["gdbus", "call", "--session", "--dest", f"{PACKAGE}.Service1", "--object-path",
         "/top/remya/settings", "--method", "top.remya.settings.Settings1.Quit"],
        capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"The Settings service refused to stop: {result.stderr.strip()}")
    return True


def bundle_running(destination):
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            executable = (process / "exe").resolve()
        except (OSError, RuntimeError):
            continue
        if executable.is_relative_to(destination):
            return True
    return False


def install(root, environment):
    data = data_home(environment).resolve()
    source = root / "build/linux/x64/release/bundle"
    if not (source / APP_ID).is_file():
        raise RuntimeError("Run fvm flutter build linux --release first")
    destination = data / "remya" / APP_ID
    stopped = bundle_running(destination) and stop_service()
    for _ in range(100):
        if not (stopped and bundle_running(destination)):
            break
        time.sleep(0.1)
    # Refuse an update while this installed bundle is executing.
    if bundle_running(destination):
        raise RuntimeError(f"Stop {APP_ID} before updating its installed bundle")
    home = environment.get("HOME", "")
    if not home.startswith("/"):
        raise ValueError("An absolute HOME is required for ~/.local/bin")
    command = Path(home) / ".local/bin" / APP_ID
    if command.exists() or command.is_symlink():
        if not command.is_symlink() or command.resolve() != destination / APP_ID:
            raise RuntimeError(f"Refusing to replace unrelated command: {command}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{APP_ID}-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "bundle"
        shutil.copytree(source, staging, symlinks=True)
        backup = Path(temporary) / "previous"
        if destination.exists():
            destination.rename(backup)
        try:
            staging.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    applications = data / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    entry = (root / f"linux/packaging/{PACKAGE}.desktop").read_text()
    # env lets Gio validate the launcher before expanding literal %% in path arguments.
    entry = entry.replace(f"Exec={APP_ID}", f"Exec=/usr/bin/env {desktop_quote(destination / APP_ID)}")
    (applications / f"{PACKAGE}.desktop").write_text(entry)
    # Separate hidden entry: opening a file must not change how the main launcher behaves.
    handler = (root / f"linux/packaging/{PACKAGE}.appimage.desktop").read_text()
    handler = handler.replace(f"Exec={APP_ID}", f"Exec=/usr/bin/env {desktop_quote(destination / APP_ID)}")
    (applications / f"{PACKAGE}.appimage.desktop").write_text(handler)
    icons = data / "icons/hicolor/scalable/apps"
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "assets/icons/settings.svg", icons / f"{PACKAGE}.svg")
    if shutil.which("gtk-update-icon-cache"):
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(data / "icons/hicolor")], check=True)
    services = data / "dbus-1/services"
    services.mkdir(parents=True, exist_ok=True)
    (services / f"{PACKAGE}.Service1.service").write_text(
        f"[D-BUS Service]\nName={PACKAGE}.Service1\n"
        f"Exec={shlex.quote(str(destination / APP_ID))} --service\n"
        f"SystemdService={UNIT}\n")
    # The resident service starts with the graphical session and owns the daily system update.
    units = data / "systemd/user"
    units.mkdir(parents=True, exist_ok=True)
    (units / UNIT).write_text(user_unit(destination / APP_ID))
    if shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "--user", "enable", "--now", UNIT], check=True)
    command.parent.mkdir(parents=True, exist_ok=True)
    if not command.is_symlink():
        command.symlink_to(destination / APP_ID)
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(applications)], check=True)
    print(f"Installed {PACKAGE} in {destination}")
    print(f"Command: {command} (add ~/.local/bin to PATH if needed)")
    print(f"Launch with: gtk-launch {PACKAGE}")
    print(f"Service: {UNIT} starts with the graphical session")
    print("System updates: run sudo python tool/install_system_updater.py once to install the root updater")


if __name__ == "__main__":
    install(Path(__file__).resolve().parents[1], os.environ)
