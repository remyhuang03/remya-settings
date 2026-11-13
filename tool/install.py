#!/usr/bin/env python3
"""Install a built release bundle in XDG_DATA_HOME without changing configuration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

APP_ID = "remya_settings"
PACKAGE = "top.remya.settings"


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


def require_core(environment):
    roots = [data_home(environment)]
    roots += [Path(value) for value in environment.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if value.startswith("/")]
    if not any((root / "dbus-1/services/top.remya.Core1.service").is_file() for root in roots):
        raise RuntimeError("Install remya-core first: top.remya.Core1.service was not found in the XDG data roots")


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
    require_core(environment)
    data = data_home(environment).resolve()
    source = root / "build/linux/x64/release/bundle"
    if not (source / APP_ID).is_file():
        raise RuntimeError("Run fvm flutter build linux --release first")
    destination = data / "remya" / APP_ID
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
    shutil.copyfile(root / "assets/icons/app_icon.svg", icons / f"{PACKAGE}.svg")
    if shutil.which("gtk-update-icon-cache"):
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(data / "icons/hicolor")], check=True)
    command.parent.mkdir(parents=True, exist_ok=True)
    if not command.is_symlink():
        command.symlink_to(destination / APP_ID)
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(applications)], check=True)
    print(f"Installed {PACKAGE} in {destination}")
    print(f"Command: {command} (add ~/.local/bin to PATH if needed)")
    print(f"Launch with: gtk-launch {PACKAGE}")


if __name__ == "__main__":
    install(Path(__file__).resolve().parents[1], os.environ)
