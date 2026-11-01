# XDG paths and application installation

The application ID is `top.remya.settings`; the executable stays `remya_settings`.
Remya Bar uses `top.remya.bar` and executable `remya_bar`.

| Purpose | Location |
| --- | --- |
| Debug Settings preferences | `<settings-repository>/config/config.local.toml` |
| Debug Bar theme override, highest priority | `<bar-repository>/config/config.local.toml` |
| Debug Bar fallback | Sibling Settings repository's local config, then installed XDG config |
| Installed/shared Settings preferences | `$XDG_CONFIG_HOME/remya/settings/config.toml` |
| Config fallback | `$HOME/.config/remya/settings/config.toml` |
| Installed bundles | `$XDG_DATA_HOME/remya/remya_settings/` and `remya_bar/` |
| Desktop entries | `$XDG_DATA_HOME/applications/top.remya.{settings,bar}.desktop` |
| Settings icon | `$XDG_DATA_HOME/icons/hicolor/scalable/apps/top.remya.settings.svg` |
| D-Bus activation | `$XDG_DATA_HOME/dbus-1/services/top.remya.settings.Service1.service` |
| User commands | `$HOME/.local/bin/remya_settings` and `remya_bar` |
| Hyprland sockets | `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket{,2}.sock` |

An unset, empty, or relative `XDG_CONFIG_HOME`/`XDG_DATA_HOME` is ignored. Config
falls back to `~/.config`; data falls back to `~/.local/share`. HOME must be
absolute when a fallback or user command path needs it. User executable paths
follow the XDG recommendation `~/.local/bin`; there is no invented `XDG_BIN_HOME`.
XDG_DATA_DIRS is respected when checking for the Settings runtime dependency.
No cache/state directories are created because neither current feature needs
persistent caches or state. Future features must use XDG_CACHE_HOME,
XDG_STATE_HOME, or XDG_RUNTIME_DIR for their actual responsibilities.

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
