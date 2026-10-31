# Public application API

Remya Settings owns configuration, defaults, validation, persistence, and system
operations. GUI, CLI, and D-Bus calls use the same `AppPreferencesController` and
Rust appearance backend. Remya Bar is a separate application and a runtime client
of Settings; it must not import Settings pages or system-writing implementations.

## Identity and installation

| Item | Value |
| --- | --- |
| Executable | `remya_settings` |
| Desktop/application ID | `top.remya.settings` |
| Session bus service | `top.remya.settings.Service1` |
| Object path | `/top/remya/settings` |
| Versioned interface | `top.remya.settings.Settings1` |

Build with `fvm flutter build linux --release`, then run `python tool/install.py`.
The installer registers the desktop entry and D-Bus activation file in XDG data
locations and creates `~/.local/bin/remya_settings`. Add `~/.local/bin` to PATH if
needed. It refuses to replace an unrelated command or update a running installed
bundle. It never writes application or desktop configuration.

The native executable routes CLI arguments to a bundled standalone Dart client
before GTK initialization. `--help` therefore needs no display or running service.
Operations use the current user's session bus. The service is activated on demand
with `remya_settings --service`, runs the ordinary-user Rust service in a
hidden Flutter view, and requires the user's graphical session. It does not open
a window until requested. Closing the settings window hides it so bar clients can
continue using the service; `quit` stops it. Another dependent client may activate
it again. No Hyprland autostart or user desktop configuration is changed.

## Commands and matching D-Bus methods

Every method returns one UTF-8 JSON string (`s`). Input parameters are strings.
No command evaluates shell input. IDs are stable catalog IDs, not translated labels.

| CLI | D-Bus method and input signature | Result |
| --- | --- | --- |
| `get theme` | `Get(s key)` with `theme` | Versioned theme configuration |
| `get about` | `Get(s key)` with `about` | Application identity, version, repository, license, API version |
| `get date-time` | `Get(s key)` with `date-time` | Actual clock, local time, NTP status, time zone, saved zone, and conflict |
| `get timezones` | `Get(s key)` with `timezones` | Finite system time zone options |
| `get configuration` | `Get(s key)` with `configuration` | Saved/system values, conflicts, and detection errors |
| `resolve <appearance / date-time> <system / settings>` | `Resolve(ss feature, source)` | Adopt system values or apply saved values, with readback |
| `get system` | `Get(s key)` with `system` | Fresh system mode and target readback |
| `get catalog` | `Get(s key)` with `catalog` | Sources, categories, and page summaries |
| `get page:<id>` | `Get(s key)` with `page:<id>` | Complete page, sections, and control metadata |
| `get <setting-id>` | `Get(s key)` | ID, availability, reason, and current value where implemented |
| `set <setting-id> <value>` | `Set(ss id, value)` | Effective feature state after successful persistence and system readback |
| `list` | `List(s cursor)` | All controls in CLI; one bounded page on D-Bus |
| `search <query>` | `Search(s query)` | Matching page IDs, titles, and categories |
| `open [page-id]` | `Open(s page)` | `{"opened":"<page>"}`; defaults to `home` in CLI |
| `reload` | `Reload()` | Theme and freshly observed system state |
| `watch [theme\|all]` | `Changed(ss topic, json)` signal plus an initial `Get("theme")` | JSON lines in CLI |
| `restart` | `Restart()` | Request a system restart through logind with interactive authorization; save work first |
| `close` | `Close()` | Close the GUI through its native window action; keep both resident services |
| `quit` | `Quit()` | `{"quitting":true}` before process shutdown |

`Open` also accepts `home`, `about`, `licenses`, and `repository` (the fixed project URL).
`Get("catalog")` returns page
summaries; request each `page:<id>` for the complete original page metadata. This
keeps individual D-Bus replies bounded instead of sending the entire 1.3 MB catalog
in one message. `List` starts with cursor `"0"` and returns up to 32 controls,
`api_version: 1`, and `next_cursor`. Continue until `next_cursor` is `null`. CLI
pagination is automatic. Invalid or out-of-range cursors fail. Search uses the
same all-terms, case-insensitive matching as the GUI.

All currently available system controls are writable through both interfaces:

| Setting ID | Accepted values |
| --- | --- |
| `themes.material-style-variant` | `tonal_spot`, `fidelity`, `monochrome`, `neutral`, `vibrant`, `expressive`, `content`, `rainbow`, `fruit_salad` |
| `themes.material-theme-mode` | `light`, `dark` |
| `date-time.fb2a23dc` | Installed time zone ID from `get timezones` |
| `date-time.db451de3` | `true`, `false` |
| `date-time.098d06ec` | `sync` (automatic time must be enabled) |
| `date-time.7e33a213` | JSON array of NTP host names/IP addresses; `[]` selects Default |
| `date-time.format` | Installed locale from `get time-locales`; empty string inherits system language |
| `date-time.6422d209` | JSON object with `local_time` and `timezone` |

The remaining catalog controls remain queryable disabled previews. Calling `Set`
on a planned or unsupported control returns `Unavailable`; it never simulates a
successful system change. Future available controls must add their operation to
the common dispatcher and parity tests as part of implementing the GUI control.

```bash
remya_settings get theme
remya_settings set themes.material-style-variant vibrant
remya_settings set themes.material-theme-mode dark
remya_settings search 'material'
remya_settings open themes
remya_settings watch all

gdbus call --session --dest top.remya.settings.Service1 \
  --object-path /top/remya/settings \
  --method top.remya.settings.Settings1.Get theme

gdbus call --session --dest top.remya.settings.Service1 \
  --object-path /top/remya/settings \
  --method top.remya.settings.Settings1.Set themes.material-style-variant neutral
```

Example theme response:

```json
{"version":1,"theme":{"style_variant":"vibrant","theme_mode":"dark"}}
```

`system` returns `mode` (`light`, `dark`, or `null`) and `targets`, each with
`name`, `status`, and `detail`. Statuses are `detected`, `applied`, `unchanged`, or
`unavailable`. Target detection does not imply universal desktop propagation.

## Changes, errors, and concurrency

`Changed("theme", json)` publishes successfully committed effective themes.
`Changed("date-time", json)` publishes date/time readback, conflicts, and feature errors; `watch all` includes it.
`Changed("error", json)` reports a configuration/operation failure. The JSON error
signal has a `message`. CLI `watch` prints `{"topic":"theme","value":{...}}`
records, beginning with the current theme; `watch all` also prints error records.
The service observes atomic external config replacements at 500 ms intervals,
using the GUI's parser and reload path. Invalid input retains the last valid
in-memory theme and the invalid file, reports an error, and recovers after repair.

D-Bus failures use these names under `top.remya.settings.Settings1`:

| Suffix | Meaning |
| --- | --- |
| `InvalidArgument` | Invalid value, unknown ID/page, or invalid cursor |
| `Unavailable` | The requested operation is a disabled preview or has no backend |
| `OperationFailed` | Configuration, persistence, system application, or readback failed |

Standard D-Bus errors cover unknown methods/interfaces, incorrect signatures,
missing services, and connection failures. CLI success writes JSON to stdout and
exits 0; local syntax/arity errors exit 2; remote validation, operation, and connection failures exit 1. Failures
write `{"error":{"code":"...","message":"..."}}` to stderr. D-Bus calls have
a 30-second client deadline. Values are never represented as applied merely
because a request was accepted.

D-Bus operations serialize. GUI changes and external reloads also serialize in
the same controller. Rust retains its cross-process lock, validation, atomic
writes, independent readback, and rollback. Do not start a second independent
writer against the same TOML file; native application registration enforces one
settings instance per session. Read-only operations do not write system settings;
`Set` is the explicit write boundary.

## Client package and compatibility

`packages/remya_settings_client/` is the public source dependency. Its pure Dart
entrypoint, `settings_contract.dart`, contains D-Bus transport and versioned
configuration contracts and can compile without a Flutter engine. The Flutter
entrypoint adds the common MD3E theme and observable theme controller. It contains
no Settings pages, catalog renderer, native system writes, or backend FFI.

Release bar clients use D-Bus signals and keep the last valid theme through
service failures; a two-second refresh recovers after service restart. Debug
clients may use a read-only repository config override. Both applications use
the same seed, palette mapping, typography fallback, and expressive icon style.

The current local path dependency expects sibling repositories while developing.
Installed bundles do not depend on either source tree. Before independently
releasing the client package, pin a version/tag and check compatibility; do not
make bar components read private files or call private methods as a shortcut.
Keep new operations in their owning settings feature and expose them through the
same dispatcher. Preserve stable IDs and interface `Settings1` for compatible
additions; use a new interface version for incompatible wire/schema changes.

## Verification

- `fvm flutter test test/settings_api_test.dart`: contract parity, available
  setters, unavailable controls, input validation, rollback, system result
  serialization, catalog/search, reload, and navigation.
- `python test/interface_smoke.py`: installs both release bundles into temporary
  XDG roots, starts an isolated session bus, and exercises actual CLI/D-Bus
  activation, Rust writes and readback, signals, malformed configuration recovery,
  three-output bar theme propagation where available, navigation, and shutdown.
  Requires both release bundles, Hyprland, `grim`, Pillow, `gdbus`, and desktop-file-utils.
- The smoke test uses a keyfile GSettings backend and a temporary HOME/config root;
  it does not change personal appearance configuration.

Screenshots are saved under `build/interface-smoke/`. Pointer clicks are checked
manually; automated interface tests do not move the user's pointer. A timed-out
write may still finish at the service; read the effective value before retrying.

## Opening Settings during development

A debug Bar passes the sibling Settings debug executable to the public
`openRemyaSettings` helper. This uses normal native application activation and
starts the debug GUI/service without installing desktop or D-Bus activation files.
Build Settings with `fvm flutter build linux --debug` once before using this path;
a missing build reports that command. A release caller keeps using D-Bus `Open`.
The debug Settings process obtains its config root from its own native runner,
independently of the Bar working directory.

## Date and time

The Rust `date_time` crate uses the system bus interface
[`org.freedesktop.timedate1`](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.timedate1.html).
`GetAll` reads actual state and `ListTimezones` provides the allowed option set;
the catalog's `UTC` value is metadata only and is never shown as detected state.
The Flutter combo supports filtering and selection; arbitrary text cannot be applied.
System writes request interactive polkit authorization; missing services, canceled
authorization, and mismatching readback are errors, never simulated success.

```sh
remya_settings get date-time
remya_settings get timezones
remya_settings set date-time.fb2a23dc Asia/Taipei
remya_settings set date-time.6422d209 '{"local_time":"2026-10-30T14:30:00","timezone":"Asia/Taipei"}'
remya_settings get configuration
remya_settings resolve appearance system
remya_settings resolve date-time settings
```

Manual time accepts exactly `YYYY-MM-DDTHH:MM:SS` interpreted in the supplied
system time zone. Invalid calendar values, DST gaps/ambiguous local times, and a
changed system time zone are rejected before writing. Selecting manual time
explicitly disables NTP through `SetNTP`, then calls `SetTime` with an absolute UTC
microsecond timestamp. If the clock operation fails, the previous NTP state is
restored; restoration failure is reported too. Successful manual time leaves NTP
off, as stated in the confirmation dialog. The RTC is updated by timedated.
The current clock is never persisted as a startup target.

`Get("timezones")` returns `options` (stable time zone IDs) and `labels` (each ID
mapped to its current GMT offset, including fractional offsets). Choosing a zone
applies immediately; daylight saving time follows the zone database automatically.
`Get("time-locales")` lists the locally installed locales and the empty-string
system-language default. Time format changes use localed `SetLocale`, preserving
all other locale categories. Writes send only `LC_TIME=<locale>`. Default sends
the current exact `LANG` value: localed rejects empty locale assignments and
simplifies overrides that equal `LANG`. Existing processes retain their environment; the
GUI floats a notice within the main content pane with Later and a confirmed Restart now action, and a
local hint explaining that restarting applications or signing in again suffices.
`Restart()` uses logind `Reboot(true)`; tests intercept this request and never
restart the workstation. `LC_ALL` or a per-user locale override can take precedence
in other applications.

Automatic time uses timedated `SetNTP` and verified readback. The GUI hides manual
clock controls while automatic time is enabled or being enabled. Sync now requires
automatic time and requests a fresh timesyncd exchange; success requires a newer
NTP packet count and synchronized clock readback within 15 seconds. Network or
authorization failures remain visible. This operation does not change persistent
server configuration.

Time servers default to **Default**; normally no change is needed. Custom servers
are stored in `/etc/systemd/timesyncd.conf.d/90-remya-settings.conf` under `[Time]`
with an empty `NTP=` reset followed by `NTP=<servers>`. The bundled Rust helper
`libexec/remya-settings-service --privileged` is authorized once through pkexec and accepts only validated
server names/IP addresses, atomically replaces this one fixed file, restarts
`systemd-timesyncd.service`, and checks effective `SystemNTPServers`. A failed
restart or effective readback restores the previous file and restarts the service
again; restoration failures are reported. Default removes only this dedicated
file, restoring the administrator/vendor configuration. Other configuration files
are preserved, and unrecognized content or symlinks at the managed path are
rejected. Later drop-ins can override/append servers; mismatching effective values
cause rollback rather than claimed success. Per-interface NTP servers may also
participate according to systemd policy. Server changes require automatic time to
be enabled and do not require a system reboot.

```sh
remya_settings set date-time.db451de3 true
remya_settings set date-time.098d06ec sync
remya_settings set date-time.7e33a213 '["pool.ntp.org"]'
remya_settings set date-time.7e33a213 '[]'
remya_settings get time-locales
remya_settings set date-time.format en_US.utf8
```

Date/time results include `timezone`, `local_time`, `ntp`, `ntp_synchronized`,
`time_servers` (the managed choice; empty means Default), `active_time_server`,
`sync_error`, `time_locale`, `saved_timezone`, `saved`, `restart_suggested`, and
`conflict`. `unix_micros` is a decimal string to preserve native 64-bit values.
Invalid input is `InvalidArgument`; system failures use `OperationFailed`.
Startup authorization may wait for the system authentication dialog; the client deadline can expire
first, so read actual state before retrying. The pkexec helper is bundled for
both debug and release and needs a registered polkit authentication agent.

## Initialization, conflicts, and scheduling

Every implemented system preference adopts validated actual system state on its
first successful load and saves it atomically. Later checks preserve saved and
actual values separately. A conflict displays a warning at the top of the window;
`Resolve(feature, "system")` saves fresh actual state, while
`Resolve(feature, "settings")` applies the saved value through the same backend as
the GUI. Detection failures leave initialization incomplete and visible. App-only
palette preferences and disabled previews do not participate.

`SettingsScheduler` runs independent feature checks concurrently at startup, on
page navigation, and every 30 seconds. Overlapping rounds share one future;
the resident service serializes its own reads/writes, so polling cannot race a
write. Failures are retained by each controller and cannot cancel other feature
checks. Toolkit and command capabilities are cached until application restart.
Time zone offsets are refreshed on feature reload; locale options are cached after discovery; the open date/time page
updates its clock locally once per second and does not perform per-second IPC.

`test/date_time_test.dart`, `test/settings_scheduler_test.dart`,
`test/app_preferences_test.dart`, and `test/settings_api_test.dart` cover the
shared controllers, both conflict resolutions, failures, GUI, and API parity.
`cargo test -p remya_settings_date_time` exercises actual GIO D-Bus calls against a
private bus/fake timedated, including permission denial, NTP restoration, readback,
and calendar/DST validation; it never changes the host clock.

Authorization requires the `polkit-kde-agent` runtime dependency on Arch. On the first explicit GUI launch Settings starts its installed user agent service and authorizes the privileged process once; no compositor
configuration is changed. Background reconciliation does not disable or recreate
editing controls. Errors appear in rounded Material error surfaces at the bottom.

## Resident process architecture

`top.remya.settings.Service1`, `/top/remya/settings`, `Settings1`, the existing
method signatures, JSON keys, and `Changed(ss)` remain the public contract.
The compatible `Close()` / `close` addition closes the GUI without quitting Settings.
The native service reads `packages/remya_settings_client/api/settings1.xml`;
`settings_api_test.dart` checks it against the pure Dart client method arities.

The launcher dispatches commands to the existing CLI and `--service` to the Rust
user service. `Open` starts `remya_settings --gui <page>` only when needed; further
opens present the existing GUI and publish a navigation invalidation. Closing the
window terminates the GUI and releases its engines. Configurations, last valid
state, conflict tracking, and the public bus remain in the user service. Quit
terminates the GUI and closes the privileged connection. The service reaps closed
GUI children and performs independent reconciliation every 30 seconds; UI timers
run only while the GUI exists. No Flutter engine is loaded by either daemon.

The first explicit Open requests one administrator authorization. Read-only
D-Bus activation by Bar does not. The privileged Rust process communicates solely
through inherited stdin/stdout pipes with 8 KiB frames and a typed, finite command
whitelist; there is no network listener or public privileged socket. It reads the
system bus and writes only the explicitly selected system setting. User theme
files and XDG configuration stay owned and written by the ordinary-user service.
EOF terminates the privileged process. Failed or canceled authorization remains
visible; closing and reopening the GUI permits another explicit attempt. A dead
helper is not silently restarted in response to a write.

GUI adapters in `service_controllers.dart` perform no persistence or direct
system writes. Existing feature controllers remain widget/test models; their old
Dart D-Bus dispatcher has been replaced by the resident service. LC_TIME readback
compares normalized locale spellings and recognizes localed removing a redundant
LC_TIME that equals LANG. The GUI adopts this actual default instead of claiming
a readback mismatch. Bottom status cards share MD3E container styling; technical
errors are available in Details and restart notices use a primary action.
