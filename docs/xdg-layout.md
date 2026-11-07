# XDG paths and application installation

The application ID is `top.remya.settings`; the executable stays `remya_settings`.
Remya Bar uses `top.remya.bar` and executable `remya_bar`.

| Purpose | Location |
| --- | --- |
| Debug Settings preferences | `<settings-repository>/config/config.local.toml` |
| Debug Bar theme override, highest priority | `<bar-repository>/config/config.local.toml` |
| Debug Bar fallback | Sibling Settings repository's local config, then installed XDG config |
| Installed/shared Settings preferences | `$XDG_CONFIG_HOME/remya/settings/config.toml` |
| Bar clock preference | `remya-bar.toml` beside the selected Settings configuration |
| Bar sidebar tile layout | `remya-bar-sidebar.toml` beside the selected Settings configuration |
| Bar folded tray apps | `remya-bar-tray.toml` beside the selected Settings configuration |
| Config fallback | `$HOME/.config/remya/settings/config.toml` |
| Background, accent settings | `background.toml` and `accent.toml` beside `config.toml` |
| Background copies | `$XDG_DATA_HOME/remya/settings/backgrounds/`; debug: `<settings-repository>/config/backgrounds/` |
| Background previews | `$XDG_CACHE_HOME/remya/settings/background-previews/`; debug: `<settings-repository>/config/background-previews/` |
| hyprpaper configuration | `$XDG_CONFIG_HOME/hypr/hyprpaper.conf`, with one `hyprpaper.conf.remya-backup` |
| Night light snapshot | `night-light.toml` beside `config.toml` (debug: repository `config/`) |
| hyprsunset configuration | `$XDG_CONFIG_HOME/hypr/hyprsunset.conf`, run by the packaged `hyprsunset.service` |
| Video background unit | `$XDG_CONFIG_HOME/systemd/user/top.remya.settings.video-background.service` |
| Default application snapshot | `default-apps.toml` beside `config.toml` (debug: repository `config/`) |
| Network preference snapshot | `network.toml` beside `config.toml` (debug: repository `config/`) |
| XDG default associations | GIO-managed `mimeapps.list` with standard desktop-specific/config/data precedence |
| Settings avatar | `avatar.png` beside `config.toml`; debug: `<settings-repository>/config/avatar.png` |
| AppImage preferences | `appimages.toml` beside `config.toml` (debug: repository `config/`) |
| AppImage folder | `$HOME/AppImages/`; launchers in `$XDG_DATA_HOME/applications/`, icons in `$XDG_DATA_HOME/icons/` |
| Installed fonts | `$XDG_DATA_HOME/fonts/` |
| Installed bundles | `$XDG_DATA_HOME/remya/remya_settings/` and `remya_bar/` |
| Desktop entries | `$XDG_DATA_HOME/applications/top.remya.{settings,bar}.desktop`, plus the hidden AppImage handler `top.remya.settings.appimage.desktop` |
| Settings icon | `$XDG_DATA_HOME/icons/hicolor/scalable/apps/top.remya.settings.svg` |
| D-Bus activation | `$XDG_DATA_HOME/dbus-1/services/top.remya.settings.Service1.service` |
| User commands | `$HOME/.local/bin/remya_settings` and `remya_bar` |
| Hyprland sockets | `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket{,2}.sock` |

Debug builds isolate only the Settings files listed above; hyprpaper, hyprsunset, the video
unit, fonts and XDG default application associations remain the real desktop's.
The default-apps snapshot uses the selected debug/release Settings config directory;
only isolated HOME/XDG roots isolate association writes during tests.

An unset, empty, or relative `XDG_CONFIG_HOME`/`XDG_DATA_HOME` is ignored. Config
falls back to `~/.config`; data falls back to `~/.local/share`. HOME must be
absolute when a fallback or user command path needs it. User executable paths
follow the XDG recommendation `~/.local/bin`; there is no invented `XDG_BIN_HOME`.
XDG_DATA_DIRS is respected when checking for the Settings runtime dependency.
Only background previews use a cache directory; they can be deleted at any time.
Future features must use XDG_CACHE_HOME, XDG_STATE_HOME, or XDG_RUNTIME_DIR for
their actual responsibilities. An unset, empty, or relative XDG_CACHE_HOME falls
back to `~/.cache`.

The native runner reports the debug repository root, so local configuration is
independent of the launch working directory. Settings creates missing debug
preferences in that repository rather than writing personal XDG config. A
missing config uses defaults without a startup write. Installed profile/release
builds never consult repository config. Debug isolation applies to application
preferences; explicitly selecting system Light/Dark still invokes the system
backend unless tests supply isolated XDG/keyfile state.

From each repository, build a release and run `python tool/install.py`. Install
Settings first, then Bar. The scripts copy relocatable bundles into the selected
XDG data directory and create desktop/service entries and user command links.
They stage bundle replacements on the destination filesystem, refuse to update
running installed bundles, and preserve application configuration. Spaces and
special characters in paths are quoted according to the separate Desktop Entry
and D-Bus Exec formats. Re-run installation after building an update, with that
application stopped. `remya_settings quit` stops the background service.

Do not automatically move or delete a previous manually installed bundle or
legacy desktop entry. Existing installations under `~/.local/opt` and old
`top.remya.remya_settings` launchers can be removed separately after reviewing
what owns them. Installation does not modify PATH, shell startup files,
Hyprland configuration, or system directories.

Sources: [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/),
[Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/),
and [D-Bus service activation](https://dbus.freedesktop.org/doc/dbus-specification.html#message-bus-starting-services).

## Display configuration

`display.toml` lives beside `config.toml` (debug: repository `config/display.toml`;
profile/release: `$XDG_CONFIG_HOME/remya/settings/display.toml`). It contains
`version = 1` and an `outputs` table of saved rule values per connector name. It uses
the same atomic writer; invalid files are retained and reported.

The display system target is `$XDG_CONFIG_HOME/hypr/monitors.lua` (fallback
`~/.config/hypr/monitors.lua`), also in debug builds, written only after an explicit
change. The first write keeps the original as `monitors.lua.remya-backup`. Symlinks
and file permissions are preserved. Settings never edits `hyprland.lua`; it must
already load `monitors.lua`.

## Date/time preference

`date-time.toml` lives beside `config.toml` (debug: repository
`config/date-time.toml`; profile/release: `$XDG_CONFIG_HOME/remya/settings/date-time.toml`,
with the existing absolute HOME fallback). It contains `version = 1` and the
saved `timezone`, `ntp`, `time_servers`, and `time_locale` preferences. Older timezone-only version-1 files adopt missing fields from validated actual system state. It uses the same atomic writer and permissions policy
as appearance preferences. Missing state adopts the actual system time zone;
malformed/unknown values are retained and reported rather than overwritten.
There is no stored clock timestamp, unused cache directory, or private Bar parser.

The time server system integration additionally owns
`/etc/systemd/timesyncd.conf.d/90-remya-settings.conf`. This is a systemd drop-in,
not XDG application configuration. It is written only following an explicit
Custom/Default selection and successful pkexec authorization. Default removes
only this managed file. The Rust service and CLI reside in the bundle's `libexec/`
directory; installation does not create or change system time configuration.

The activation entry still launches `remya_settings --service`, which now execs
`libexec/remya-settings-service` without loading GTK or Flutter. Normal desktop
launch calls the existing Open interface; only the private `--gui <page>` path
creates the Flutter process. The authorized helper uses the same Rust executable
with `--privileged` and inherits a private pipe, with no permanent root service
installation or global privileged socket.

## System information

System specification fields are read-only observations and create no XDG files.
They do not read or derive a device identifier.

## Device hostname preference

`hostname.toml` lives beside `config.toml` (debug: repository
`config/hostname.toml`; profile/release: `$XDG_CONFIG_HOME/remya/settings/hostname.toml`,
with the existing absolute HOME fallback). Its version-1 schema contains only
`version = 1` and `static_hostname`. Initialization adopts actual system state;
malformed files are retained and reported. Writes use the existing atomic writer
and permissions policy. Runtime hostname, PrettyHostname, and hardware
specifications are never saved. No system hostname files are written directly;
systemd-hostnamed owns those changes through the existing authorized helper.

Installed-app inventory has no Settings snapshot: it reads GIO desktop entries,
the configured ALPM local database, and Flatpak's selected installations. Search,
sort, and source filters are session-local. Uninstall preserves user application
data, Flatpak runtimes, and unrelated desktop entries. The UI's rendered icon
cache lives only in memory and is released with the GUI engine.

External input-method configuration entries only launch installed tools. Settings
does not create input-method preferences, migrate configuration, or persist input
method environment variables. The external tool retains ownership of its files.

## Bluetooth

Bluetooth creates no Settings configuration, cache or state files. BlueZ owns
bonds and secrets; power, discovery and connection state are read live. Settings
retains only its temporary scan and pairing operation in service memory and never
restores those operations at startup. See [Bluetooth](bluetooth.md).


## Settings account avatar

The ordinary-user service owns `avatar.png` beside its selected Settings configuration: `$XDG_CONFIG_HOME/remya/settings/avatar.png` (HOME fallback) in profile/release, or repository `config/avatar.png` in debug. A confirmed crop atomically replaces only this file, with mode 0600 on first creation and existing permissions retained. It rejects an avatar-file symlink rather than following it. The picker source is not changed, copied to the library or saved as a path preference. Username is a live read-only process-user observation and creates no files. The avatar is not synchronized to AccountsService, a desktop shell or a login system.

## Sound

Sound has no Settings-owned configuration or cache. Device volume, mute, default
input/output devices and application routing follow live audio-server state.
The ordinary-user service connects to the existing pipewire-pulse socket and
never saves or restores audio preferences. See [Sound](sound.md).

System update progress, held/retry session choices, logs and candidate inventory are memory-only. The application-owned daily schedule is saved atomically in `updates.json` beside `config.toml` (or beside debug `config.local.toml`); it stores the enabled flag, active hours start and end (local HH:mm), the local date on which the last handled inactive period began, and the outcome notice. Defaults are disabled, so first read never schedules an upgrade. Checks use checkupdates' own temporary database; no job directories are created.

`tool/install.py` also writes `$XDG_DATA_HOME/systemd/user/top.remya.settings.service` and enables it for `graphical-session.target`, so the resident service starts with the session; the D-Bus service file names it with `SystemdService=`. When the service is running, the installer asks it to Quit (refused while an update runs), installs, and starts the unit again.

The one exception outside the user's home is the optional system updater, installed only by `sudo python tool/install_system_updater.py`: `/usr/local/libexec/remya-settings-update` (root:root, 0755) and `/etc/polkit-1/rules.d/50-top.remya.settings.update.rules` (0644). The release bundle's `libexec/remya-settings-update` is only its install source.

## Camera configuration

`cameras.toml` is adjacent to the service's main config (repository config in
debug; `$XDG_CONFIG_HOME/remya/settings/` in profile/release with HOME fallback).
Its version-1 cameras table maps PipeWire node names to the supported brightness,
contrast, saturation and sharpness values. Node serials and preview frames are
never persisted. The ordinary-user Rust service owns atomic writes and conflict
resolution; no PipeWire/WirePlumber configuration files are edited.

## Power history

Power preferences and restoration metadata are `power.json` and `power.runtime.json` beside the Settings configuration. Permanent battery history is `$XDG_STATE_HOME/remya/settings/power.sqlite3` (HOME fallback `.local/state`); debug uses repository `config/power.sqlite3`. Relative state roots are ignored. SQLite WAL/SHM files remain beside the database.

`power.json` stores the last nonzero activation threshold as
`preferred_threshold` and the turn-off policy as `off_threshold`.
Existing files without the field follow the turn-on threshold. Keep awake is a session-only hypridle inhibitor and creates no files. See [Power and energy saver](power.md).
