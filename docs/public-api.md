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
| `get hostname` | `Get(s key)` with `hostname` | Actual static/runtime names, saved static name, conflict and error |
| `get system-information` | `Get(s key)` with `system-information` | Fresh read-only device/system fields with per-field errors |
| `get about` | `Get(s key)` with `about` | Application identity, version, repository, license, API version |
| `get date-time` | `Get(s key)` with `date-time` | Actual clock, local time, NTP status, time zone, saved zone, and conflict |
| `get timezones` | `Get(s key)` with `timezones` | Finite system time zone options |
| `get configuration` | `Get(s key)` with `configuration` | Saved/system values, conflicts, and detection errors |
| `resolve <appearance / date-time / display / night-light / hostname / background / default-apps / network> <system / settings>` | `Resolve(ss feature, source)` | Adopt system values or apply saved values, with readback |
| `resolve display <keep / revert>` | `Resolve(ss feature, source)` | Confirm or undo a pending display change |
| `get background` | `Get(s key)` with `background` | Saved and system background, displays, warnings, previews, conflict, write blocker, error |
| `get accent` | `Get(s key)` with `accent` | Accent source, `#RRGGBB` seed, sampled file, sampling error |
| `get fonts` | `Get(s key)` with `fonts` | User font directory and every installed family |
| `get font-search:<query>` | `Get(s key)` with `font-search:<query>` | Families whose name contains the query |
| `get font:<family>` | `Get(s key)` with `font:<family>` | One family's styles, formats, files and removability |
| `get system` | `Get(s key)` with `system` | Fresh system mode and target readback |
| `get display` | `Get(s key)` with `display` | Outputs, modes, saved and actual values, conflicts, pending change, write blocker |
| `get night-light` | `Get(s key)` with `night-light` | Saved and system preferences, live state, conflict, write blocker, error |
| `get display-brightness` | `Get(s key)` with `display-brightness` | Hardware brightness per active output, or why it is unavailable |
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

Available system preferences are writable through both interfaces; System information fields are read-only:

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
| Display settings | See [Display](#display) |

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
`Changed("night-light", json)` publishes Night light state after writes, reconciliation and detected changes; `watch all` includes it.
`Changed("display", json)` publishes display state after writes, confirmation expiry, reconciliation, and Hyprland output events; `watch all` includes it.
`Changed("background", json)` publishes background state after writes, reconciliation, and output events; `Changed("accent", json)` publishes accent changes; `Changed("fonts", {})` asks clients to read the font list again.
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
The seed comes from `Get("accent")` and the `accent` topic. The `theme` value and
`config.toml` schema stay unchanged, so clients built before the accent setting keep
working and simply stay on the default seed until rebuilt.

The current local path dependency expects sibling repositories while developing.
Installed bundles do not depend on either source tree. Before independently
releasing the client package, pin a version/tag and check compatibility; do not
make bar components read private files or call private methods as a shortcut.
Keep new operations in their owning settings feature and expose them through the
same dispatcher. Preserve stable IDs and interface `Settings1` for compatible
additions; use a new interface version for incompatible wire/schema changes.

## Verification

- `fvm flutter test`: configuration persistence, validation, conflicts and
  resolutions, failure retention, service controllers, and important GUI interactions.
  Shallow presentation checks and static XML string assertions were removed;
  CLI/D-Bus contract parity is exercised by the live interface smoke test.
- `python test/interface_smoke.py`: installs both release bundles into temporary
  XDG roots, starts an isolated session bus, and exercises actual CLI/D-Bus
  activation, Rust writes and readback, signals, malformed configuration recovery,
  three-output bar theme propagation where available, navigation, and shutdown.
  Requires both release bundles, Hyprland, `grim`, Pillow, `gdbus`, and desktop-file-utils.
- The smoke test uses a keyfile GSettings backend and a temporary HOME/config root;
  it does not change personal appearance configuration.

The smoke test samples Bar colors to verify theme propagation without retaining
page screenshots or checking decorative geometry. Pointer clicks are checked
manually; automated interface tests do not move the user's pointer. A timed-out
write may still finish at the service; read the effective value before retrying.

## Opening Settings during development

A debug Bar passes the sibling Settings debug executable to the public
`openRemyaSettings` helper. This uses normal native application activation and
starts the debug GUI/service without installing desktop or D-Bus activation files.
Pass `page: 'power'` to open Power & battery directly in either build mode.
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

## Display

The GUI uses paired X/Y inputs for position and custom resolution. Resolution is
Preferred or Custom; custom dimensions (1–32768 pixels per axis) snap in Rust to
the reported mode with the smallest squared pixel distance. Ties follow the
mode list's size/rate order; the current refresh rate is retained when offered at
the chosen size, otherwise the highest reported rate is used. The same correction
applies through CLI and D-Bus. The resulting dimensions are returned in display
state, and risky changes still require keep/revert confirmation.

Rotation and horizontal flip are independent GUI controls over the existing
`0`–`7` transform: rotation is `transform % 4`, flip adds `4`. Hardware brightness
is applied during dragging; queued writes to each output keep the newest value
and run serially with system readback. The refresh icon in the arrangement header
uses the existing `display.15697afc` operation, which remains in the catalog for
CLI/D-Bus parity. There is no separate Detect displays row in the GUI. Advanced
uses a separate collapsible heading above its settings surface.


The Rust `display` crate drives Hyprland through `hyprctl` and needs a Lua
configuration (`hyprctl status` reports `configProvider: lua`; `hl.monitor` is
verified on Hyprland 0.57). Set values are JSON:

```sh
remya_settings get display
remya_settings set display.12e2ed4d '{"output":"DP-1","value":"1.5","confirm_seconds":15}'
remya_settings resolve display keep
remya_settings set display.position '{"output":"DP-1","value":"1920x0"}'
remya_settings set display.5d419889 '{"output":"eDP-1","value":"40"}'
remya_settings set display.15697afc detect
```

| Setting ID | `value` | Rule field |
| --- | --- | --- |
| `display.5d419889` Brightness | `0`–`100` (live, not saved) | Backlight or DDC/CI |
| `display.af8e280d` Color preset | `auto`, `srgb`, `dcip3`, `dp3`, `adobe`, `wide`, `edid`, `hdr`, `hdredid` | `cm` |
| `display.0ce92088` HDR | `true`, `false` (`hdr` or `srgb`) | `cm` |
| `display.12e2ed4d` Scale | `auto` or a number; see `scale_options` | `scale` |
| `display.44f6b9b0` Resolution | `WIDTHxHEIGHT` or `preferred` | `mode` |
| `display.34d8396d` Refresh rate | Rate in Hz at the current resolution | `mode` |
| `display.9843ad76` Orientation | `0`–`7` | `transform` |
| `display.7cb5dc06` Multiple displays | `extend`, `disable`, `mirror:<output>` | `disabled`, `mirror` |
| `display.position` | `XxY` or `auto`, `auto-right`, ... | `position` |
| `display.91720250` Bit depth | `8`, `10` | `bitdepth` |
| `display.2d80c2c4` Variable refresh rate | empty (use `misc:vrr`), `0`–`3` | `vrr` |
| `display.sdr-eotf` | `default`, `gamma22`, `srgb` | `sdr_eotf` |
| `display.sdrbrightness`, `.sdrsaturation` | `0`–`5` | same name |
| `display.sdr-min-luminance`, `.sdr-max-luminance` | Nits | `sdr_min_luminance`, `sdr_max_luminance` |
| `display.min-luminance`, `.max-luminance`, `.max-avg-luminance` | Nits, `-1` for reported | same with underscores |
| `display.supports-hdr`, `.supports-wide-color` | `-1`, `0`, `1` | `supports_hdr`, `supports_wide_color` |
| `display.icc` | Absolute path of a file with an ICC signature, or empty | `icc` |
| `display.reserved-area` | `top right bottom left` | `reserved_area` |

`display.output`, `display.3b3ebb60`, `.761b7ac8`, `.3278abf9`,
and `.device` are read-only. `Get(<setting-id>)` returns a `value` for each connected
output.

**Applying.** A value is validated against the actual monitor, sent with `hyprctl
eval 'hl.monitor({...})'`, and confirmed by polling readback for up to 5 seconds.
A failed readback restores the previous value and reports the error. Hyprland merges
named fields into the live rule, so only changed fields are sent. Fields with no
readback (`vrr`, `sdr_eotf`, `icc`, `reserved_area`, `supports_*`, `min/max_luminance`)
are verified by reading back `monitors.lua`. Clearing `icc` applies after the next
configuration reload because `hl.monitor` rejects an empty path.

**Confirmation.** With `confirm_seconds` (at most 60), changes to `mode`, `scale`,
`transform`, `disabled`, `mirror`, `bitdepth`, `cm`, `supports_*`, and `icc` stay
pending: `pending` reports them with `remaining_ms`, other writes are rejected, and
nothing is written to disk. `resolve display keep` persists; `revert`, expiry, and
service shutdown restore the previous value. The countdown runs in the service so it
works if the GUI is on a blanked display or has exited. Without `confirm_seconds` a
change persists immediately. The last display showing a desktop cannot be disabled or
mirrored away, and a display being mirrored cannot be disabled.

**Persistence.** `$XDG_CONFIG_HOME/hypr/monitors.lua` holds one `hl.monitor` rule per
output, which `hyprland.lua` must load. Only the changed output's rule is rewritten;
comments, other rules, disconnected outputs, and unknown fields are preserved. A
`desc:` rule keeps its match. The first write leaves `monitors.lua.remya-backup`.
Configuration reloads are not triggered because they would reset other runtime
state. `write_blocked` explains why writes are refused: a non-Lua configuration, a
file that does not load `monitors.lua`, or content beyond `hl.monitor` rules and
comments. Such a file is never replaced.

**Reconciliation.** `display.toml` saves each output's preferences. Symbolic values
come from the rule (`scale = "auto"`, `mode = "preferred"`, automatic position), so a
resolved 1.6 scale is not a conflict. Disconnected outputs keep their values and raise
no conflict. A disabled output compares only `disabled` and `mirror`; a mirrored
output skips its geometry. Empty geometry while an output wakes is a detection error.
Hyprland `monitoradded`, `monitorremoved`, and `configreloaded` events trigger a check.

**Brightness** is live hardware state and is excluded from reconciliation because
keys and other tools change it. Built-in panels read `/sys/class/backlight` and write
through logind `Session.SetBrightness`, without root; the value never goes below 1%
so a panel cannot go fully dark. External displays use the optional `ddcutil` command
through a separate process, which needs the `i2c-dev` module and I2C access. Other
outputs report a `reason`. Brightness is read when the page opens, not while polling,
because DDC/CI is slow.

`cargo test -p remya_settings_display` covers parsing, validation, reconciliation,
confirmation, and failures against a fake compositor. `test/display_test.dart` covers
the controller and page. `python test/display_smoke.py` runs the real service against
a nested Hyprland with headless outputs, a private bus, and isolated XDG roots.

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

`test/date_time_test.dart`, `test/service_controllers_test.dart`, and
`test/app_preferences_test.dart` cover the
shared controllers, both conflict resolutions, failures, and GUI behavior.
`python test/interface_smoke.py` verifies actual CLI/D-Bus parity.
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
`python test/interface_smoke.py` exercises its methods through the CLI and D-Bus.

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

## System information

`Get("system-information")` returns `api_version: 1` and `values`, keyed by the
16 stable `about.*` information IDs. Each field contains a string `value` and
null `error`, or null `value` and a diagnostic `error`. `Get(<information ID>)`
returns the same field with ID, availability, and reason. `Set` rejects these
fields with `ReadOnly`. The pure Dart client exposes `readSystemInformation()`
and `systemInformationSettingIds`. `Get("about")` remains application metadata.

The feature-owned Rust backend uses MIT-licensed `sysinfo` 0.40.1 (Rust >= 1.95),
with only the `system` feature. It reads CPU models/logical processor count,
Linux-usable RAM (GiB), kernel architecture, OS and kernel versions,
hostname, manufacturer, model, model revision, motherboard manufacturer/model,
and physical/logical processor counts; it does not refresh process, disk, or network lists. RAM is not a
firmware DIMM capacity measurement. Firmware manufacturer, version and release
date are read from the three fixed public Linux DMI sysfs attributes
`bios_vendor`, `bios_version`, and `bios_date`. Empty values and common firmware
placeholders are reported as unavailable. Read failures remain per-field errors.

The GUI reads on page entry and offers Refresh. No observations are persisted or
reconciled, no elevation is requested by the reader, and no system writes occur.
Rename device is implemented through the shared hostname controller. The reader does not access machine-id.
Use `open system-information`
to open this page; `open about` retains the application About page behavior.

The page layout is inspired by modern desktop settings patterns (referencing the About hierarchy found in Windows Settings): a device header followed
by labeled Device specifications, Firmware, and System specifications groups.
Independent facts have their own rows; text information never uses U+00B7 as a
separator. No serial numbers, UUIDs, or device identifiers are read.

Firmware dates are parsed as the DMI calendar date, then formatted using `%x`
under fresh systemd-localed `LC_TIME`, inheriting `LANG` or `C` when absent.
This uses GNU coreutils `date` with separate arguments, a validated installed
locale and a fixed UTC timezone; no process-global locale or system settings
are changed. The resident service's inherited `LC_ALL` does not override the
selected system time format. Invalid dates or unavailable locales return a
per-field error. GUI, CLI and D-Bus share this same localized value.

## Device hostname

`Get("hostname")` returns `static_hostname`, runtime `hostname`,
`saved_static_hostname`, `initialized`, `writable`, `conflict`, `error`, `authorized`, and
`authorizing`. `Get("about.0f142010")` includes the same state and the static
hostname as `value`. `Get("system-information")` includes this state under
`hostname`; its information fields remain read-only.

`Set("about.0f142010", name)` accepts 1–63 lowercase ASCII letters, digits, and
hyphens, beginning and ending with a letter or digit. It rejects an unresolved
configuration conflict. The pure Dart client exposes `readHostname()`,
`renameHostname()`, `resolveHostname()`, and the matching form validator.
`Resolve("hostname", "system")` adopts the observed static name;
`Resolve("hostname", "settings")` reapplies the saved static name. Both return
full configuration including `hostname`. The `hostname` change topic reports
updates and operation errors to clients. Empty or existing valid domain-style
static names can be adopted and restored; the normal rename form accepts only a
single nonempty label. Runtime names are observations, never persisted.

The Rust service initializes `hostname.toml` from actual hostnamed readback on
first successful detection, never from defaults. Startup, page entry, polling,
and explicit Refresh compare current static configuration with the saved name.
Invalid configuration, detection failures, failed authorization, writes, or
persistence preserve the last valid saved value and surface an error. Conflicts
require one of the two explicit resolution actions. Failed operations remain
visible across ordinary reads until a successful retry or resolution.

The existing private authorized helper accepts only a bounded typed Hostname
request containing the target and expected previous static name. It rechecks
that previous name, calls `org.freedesktop.hostname1.SetStaticHostname`, and
verifies static and current runtime names before reporting success. Clearing an
initially absent static name restores hostnamed's normal runtime-name policy.
PrettyHostname, `/etc/hosts`, network configuration and service configuration
are not modified. Changes are immediate; existing apps may need reopening.
The ordinary service, GUI and CLI do not directly write system hostname files.

The System information menu uses an info icon. An edit icon beside the current
hostname opens the validated rename dialog; there is no separate Rename row.
Validation includes a private fake hostnamed D-Bus server for success, stale
names, denied writes and mismatched readback, feature-controller tests for
initialization/conflicts/resolutions/persistence failures, and widget tests for
input validation, failed renames and refresh after success at minimum width.
These tests never rename the workstation.

## Background

hyprpaper shows images and cannot play video, so videos use mpvpaper as a separate
process. Both are runtime tools of the desktop, not linked code; mpvpaper and ffmpeg
are only needed for video and for sampling or previews.

| Setting | ID | `Set` value |
| --- | --- | --- |
| Background type | `background.99b01ada` | `image` or `video`; needs an earlier file of that type |
| Display | `background.display` | Read-only list of outputs; pass `display` with a file or fit |
| Background file | `background.9e58290b` | Absolute path, or `{"path":"…","display":"DP-1"}`; `display` may be a list |
| Fit | `background.56c289eb` | `cover`, `contain`, `tile`, `fill`, or `{"fit":"…","display":"DP-1"}`; `display` may be a list; video has no `tile` |
| Video when covered | `background.video-pause` | `keep`, `pause`, `stop` |
| Show splash text | `background.splash` | `true`, `false` |
| Splash offset | `background.splash-offset` | 0 to 10000; the page's slider covers 0 to 200 |
| Splash opacity | `background.splash-opacity` | 0 to 1 |

A selected file is copied to the application's backgrounds directory (see
[XDG layout](xdg-layout.md)) under its content hash plus a cleaned name. Saved
configuration, `hyprpaper.conf` and the video unit reference only that copy; the
selected path is not retained, and moving or deleting the original has no effect.
Copies nothing references are removed after each successful change. The file type
comes from `file --mime-type`. A display name omitted or `*` means all displays:
choosing a file for all displays replaces per-display images. The page lists displays
in a button group, connecting those with the same file and fit. A first click selects
the group and a second click selects that display alone; a selection covering every
display is sent as `*`, so it also applies to displays connected later.

Images write `$XDG_CONFIG_HOME/hypr/hyprpaper.conf` atomically, then call `hyprctl
hyprpaper wallpaper` for each connected output by name, because hyprpaper does not
let a wildcard request replace a running wildcard entry, and wait for `listactive`
to report the file. The strict reader accepts comments, splash keys, `ipc = true`,
`wallpaper { … }` blocks and the `wallpaper[]:key` form. Rotation keys, `source`,
variables, inline comments, directory-style entries, and anything else make the file
read-only for Settings with a visible reason. The first rewrite keeps the original
as `hyprpaper.conf.remya-backup`. The `hyprlang` crate was evaluated for reading and
rejected: it cannot parse the `wallpaper[]:` form.

Videos play on all displays through the user unit
`top.remya.settings.video-background.service` in `$XDG_CONFIG_HOME/systemd/user`,
enabled for `graphical-session.target`, on the bottom layer so they stay above
hyprpaper whichever starts first. The unit is written only when video is selected
and disabled when an image is selected. Choosing an image also stops other mpvpaper
processes, because they would cover it. An mpvpaper started by another program is
read as the actual video background and reported in `warnings`.

First use records the actual configuration and applies nothing. Startup, page entry,
polling and output events compare saved values with fresh readback: type, images,
splash, and video while video is active. A remembered video is not a difference
while an image shows. Conflicts keep both values and block writes until `Resolve
("background", "system" | "settings")`. Failed application restores `hyprpaper.conf`,
the previous images and the previous type, keeps the saved file, and stays in `error`.

`warnings` also reports several running hyprpaper instances (changes reach only one)
and full-screen layers drawn above the background.

hyprpaper reads its configuration only at start and its IPC treats Fill as Cover, so
splash changes and a newly chosen Fill restart it; everything else stays on IPC, sent
only to outputs that changed so another output's Fill survives. A restart stops this
Hyprland session's hyprpaper processes, identified by `HYPRLAND_INSTANCE_SIGNATURE`,
which also clears duplicate instances. It starts one again through `hyprpaper.service`
when that unit is enabled or active, otherwise through Hyprland with `hl.exec_cmd`. The
background blanks for one to two seconds with a large image. Success requires hyprpaper
to report the expected images; failure restores the file and restarts hyprpaper with it.
While a video covers hyprpaper the file is written and the restart waits until the
background returns to an image, happening under the video before it stops.

## Accent color

`themes.8983f367` takes `background` or `custom`. `themes.6f67371e` takes `#RRGGBB`
and selects `custom`. `background` decodes the current background's first frame to at
most 128 pixels per side with ffmpeg and picks the seed with `material-colors`: Celebi
quantization followed by Score, the Material color utilities' source-color method. It
resamples when the current background changes (the video, else the all-displays image,
else the first image). A failed sample keeps the last color and fills `error`; it does
not fail the background change. `accent.toml` is an application preference: missing
means the default custom seed, and no system counterpart exists to reconcile.

## Fonts

The list comes from `fc-list` and is a live observation, so nothing is saved or
reconciled. `Set("fonts.158ba0bb", path)` validates the extension (TTF, OTF, TTC, OTC,
WOFF, WOFF2), size and `fc-query`, copies into `$XDG_DATA_HOME/fonts`, refuses to
overwrite a file of the same name, runs `fc-cache`, confirms `fc-list` shows it, and
removes the copy otherwise. `Set("fonts.f869cae5", family)` deletes that family's files
inside the user font directory and verifies the removal; system-wide files stay, and a
family with only system files is rejected. `fonts.65a8477b` and `fonts.fc3969c7` are
reads, available through `font-search:` and `font:`, and reject `Set` with `ReadOnly`.
Running applications may need reopening to see font changes.
The page reads the list when opened and on the `fonts` change topic, and builds only
rows near the viewport, because each preview loads a whole font file.


## Default applications

See [Default apps](default-apps.md) for type groups, conflict handling, and rollback limitations.
All operations run in the ordinary-user service with GIO; no authorization prompt is needed for reads or association writes.

| CLI | D-Bus | Result |
| --- | --- | --- |
| `get default-apps` | `Get("default-apps")` | `api_version`, `initialized`, `writable`, `saved`, `system`, `conflict`, `error`, `groups`, `handlers`, MIME-to-extension `extensions` |
| `get default-applications:<query>` | `Get("default-applications:<query>")` | `applications`: desktop `id`, display `name`, serialized GIcon `icon`, declared `types` |
| `get default-types:<query>` | `Get("default-types:<query>")` | `types`: matching MIME/scheme `type` and current desktop-ID `application`; `.pdf` searches extension globs |
| `get default-candidates:<comma-separated-types>` | `Get("default-candidates:<comma-separated-types>")` | Applications declaring at least one requested type; the browser UI requires both HTTP and HTTPS |
| `get <defaults-setting-id>` | `Get(id)` | Feature state, ID, availability, and per-type `value` for a shortcut |
| `set defaults.b131ac5a <json>` | `Set(id, json)` | Set explicit MIME/scheme types and save verified outcomes |
| `set defaults.897fdfef <json>` | `Set(id, json)` | Same operation for an application's supported-type selection |
| `set <shortcut-id> <json>` | `Set(id, json)` | Fixed group, filtered to the selected application's declared types; omit `types` |
| `resolve default-apps system` | `Resolve("default-apps", "system")` | Adopt actual associations; returns default-apps state |
| `resolve default-apps settings` | `Resolve("default-apps", "settings")` | Apply differing saved associations with readback; returns default-apps state |

Write JSON is `{"application":"org.example.Reader.desktop","types":["application/pdf"]}`.
Shortcut JSON is `{"application":"org.example.Browser.desktop"}`. Unknown fields, invalid or absent applications, unsupported types, conflicts, and unverifiable writes fail. Explicit selections contain 1–256 types.
`Get("configuration")` includes `default-apps`; `Changed("default-apps", json)` reports relevant Set/Resolve/Reload outcomes, including errors. The public Dart extension exposes these operations without Flutter dependencies.

Empty desktop-ID strings represent unset defaults; they are not application IDs. Failed reads carry `error` and `writable:false`; old values are retained and must not be presented as fresh detections. `defaults.ff4c4bec` remains unavailable and rejects Set.

## Installed applications

See [Installed apps](installed-apps.md) for package scope, metadata limits, and verification boundaries.

| CLI | D-Bus | Result |
| --- | --- | --- |
| `get installed-apps` | `Get("installed-apps")` | `api_version`, `applications`, source-specific `warnings` |
| `get installed-apps:<json>` | `Get("installed-apps:<json>")` | Filter/sort inventory: optional `query`, `source`, and `sort` (`name`, `size`, `installed`); missing numeric values sort last |
| `get installed-app:<id>` | `Get("installed-app:<id>")` | One observed application with `id`, `name`, serialized GIcon `icon`, `source`, nullable `version`, byte `size`, epoch-seconds `installed`, `package`, `location`, `token`, `uninstallable`, `reason`, and `related` launchers |
| `get <installed-setting-id>` | `Get(id)` | Observed inventory with the setting's ID and availability |
| `set installed.c3c4a29c <json>` | `Set(id, json)` | `{"removed":"<id>"}` after package-manager success and readback |
| `get calendar-date:<YYYY-MM-DD>` | `Get("calendar-date:<date>")` | `value` formatted under the current system LC_TIME, with LANG fallback |

Uninstall JSON is `{"id":"org.example.App.desktop","token":"<observed-version>"}` or a Flatpak inventory ID `flatpak:<installation>:<app>/<arch>/<branch>` with its observed commit token. Do not invent IDs or tokens. The four inspection/view control IDs reject Set with ReadOnly. Manual installations cannot be uninstalled. Native and system-Flatpak changes require the existing explicitly authorized GUI session. `Changed("installed-apps", {})` invalidates inventory after uninstall attempts. The Dart ApplicationsClient exposes the same operations.

Managed AppImage launchers have `source: "appimage"`, with `X-AppImage-Version` and file size when available. They remain `uninstallable: false` in Installed apps; use the existing AppImages update/removal operations. Other manual launchers keep `source: "manual"`. This adds a source value without changing the versioned payload shape.

The private helper's typed Uninstall request contains only an ID and token; it verifies package ownership itself and never accepts arbitrary privileged paths or commands.

## AppImages

See [AppImages](appimages.md) for the folder, sources, update and safety rules.

| CLI | D-Bus | Result |
| --- | --- | --- |
| `get appimages` | `Get("appimages")` | `api_version`, `directory`, `auto_check`, `auto_update`, `last_check`, `installing` file names, `error`, and `apps` |
| `get <appimages-setting-id>` | `Get(id)` | `id`, `availability`, toggle `value` and the full `state` |
| `set appimages.install <absolute-path>` | `Set(id, path)` | `{"installing":"<file>"}`; the result arrives through `installing` and `error` |
| `install-appimage <path>` | `Set("appimages.install", absolute)` then `Open("appimages")` | Same, for the file-manager handler |
| `set appimages.check <id or all>` | `Set(id, value)` | `{"started":[ids]}`; `all` checks apps whose updates are on |
| `set appimages.update <id or all>` | `Set(id, value)` | `{"started":[ids]}`; checks, then downloads and installs only when newer |
| `set appimages.cancel <id>` | `Set(id, value)` | `{"cancelling":"<id>"}` |
| `set appimages.source <json>` | `Set(id, json)` | `{"id":"<id>"}`. JSON is `{"id","source":null or string,"updates":bool}`; `null` restores the published source |
| `set appimages.integrate <id>` | `Set(id, value)` | `{"integrated":"<id>"}` after the launcher is written |
| `set appimages.open <id>` | `Set(id, value)` | `{"opened":"<id>","pid":n}` |
| `set appimages.uninstall <id>` | `Set(id, value)` | `{"removed":"<id>"}` after Trash and launcher cleanup |
| `set appimages.auto-check <true/false>` | `Set(id, value)` | `{"id","value"}` |
| `set appimages.auto-update <true/false>` | `Set(id, value)` | `{"id","value"}` |

Each `apps` entry has these fields:

- `id`: the file name;
- `name`, `icon` and `version`: from the launcher, or `null`;
- `path` and `size`;
- `integrated`;
- `source` and `source_origin` (`custom`, `embedded` or `desktop`), or `null`;
- `updates`;
- `job`: `null`, or `{status, bytes, total, speed}`;
- `checked`;
- `available`: `null`, or `{version, size}`;
- `error`.

Checks, updates and installs run on service worker threads, so `Set` returns as soon as the job is accepted. While anything changes, `Changed("appimages", state)` is published at most once a second. Unknown IDs, relative or non-AppImage paths, non-https sources and busy apps are rejected. `Get` never starts network work. The Dart `AppImagesClient` exposes read and source writes; other operations use `Set` with the exported setting IDs.

## External input-method configuration

Time & language > More contains only detected configuration tools. `get input-method-tools`
(`Get("input-method-tools")`) returns `tools` with stable `id`, `name` and serialized
GIcon `icon`. `Get` on either setting ID provides the same inspection data.
`set time-more.fcitx5 open` and `set time-more.ibus open` (the corresponding `Set` calls)
spawn `/usr/bin/fcitx5-configtool` and `/usr/bin/ibus-setup`, respectively. Missing or
non-executable tools are hidden in the GUI and reject launch. Unknown IDs and values
are rejected. The response `opened` and `pid` confirms process creation, not a change
to input-method preferences. The service reaps the child when it exits.

No command line, executable path, elevation, daemon activation, environment change,
or input-method configuration write is exposed. The external application owns its
configuration; Settings has no system preference snapshot to reconcile here.
The pure Dart InputMethodToolsClient exposes read and launch parity.

Tool interfaces: [Fcitx 5 Configtool](https://fcitx-im.org/wiki/Configtool_(Fcitx_5)),
[IBus](https://github.com/ibus/ibus).

## Other external settings applications

`Get("external-tools:<group>")` lists installed tools for `time`, `system` or
`appearance`. Unknown groups fail. The input-method-tools key remains an alias
for the time group. Each tool is a fixed ordinary-user executable under /usr/bin;
`Set(<id>, "open")` launches it with no command arguments. Missing executables
are hidden and reject launch. More pages do not own or reconcile external preferences.

| More page | Setting ID | Executable |
| --- | --- | --- |
| System | `system-more.kde` | `systemsettings` |
| System | `system-more.gnome` | `gnome-control-center` |
| System | `system-more.localsend` | `localsend` |
| Appearance | `appearance-more.qt6ct` | `qt6ct` |
| Appearance | `appearance-more.kvantum` | `kvantummanager` |
| Appearance | `appearance-more.gtk` | `nwg-look` |
| Appearance | `appearance-more.gnome-tweaks` | `gnome-tweaks` |

ExternalToolsClient exposes grouped discovery and launch without Flutter.

External-tool discovery includes nullable `launch_error`. GNOME Settings is listed as an informative readout without an Open control outside GNOME/Unity; launch is rejected with the platform reason. No desktop environment variables are spoofed.

## Network

See [Network settings](network.md) for behavior, secrets and limits. NetworkManager is required.

| CLI | D-Bus | Result |
| --- | --- | --- |
| `get network` | `Get("network")` | Fresh `api_version`, `available`, `initialized`, `writable`, `conflict`, `conflicts`, `error`, `failure`, `connecting`, `adapter`, `connectivity`, `connectivity_check`, `check_uri`, `wifi_enabled`, `wifi_hardware_enabled`, `primary_uuid`, `permissions`, `devices`, `profiles`, `active` |
| `get network-traffic` | `Get("network-traffic")` | `interface`, `rx_bytes`, `tx_bytes` of the active adapter since it came up, or nulls. Clients derive speeds; does not read NetworkManager |
| `get <control-id>` | `Get(id)` | Readable controls return `id`, `availability`, `reason`, `value`, `error` |
| `set wifi.enabled <true/false>` | `Set(id, value)` | Radio, verified by readback |
| `set wifi.adapter <interface>` | `Set(id, value)` | Adapter for later Wi-Fi operations in this service session |
| `set wifi.refresh scan` | `Set(id, value)` | Requests a scan; results arrive in `Changed` |
| `set wifi.connect <json>` | `Set(id, json)` | `{"ssid"\|"uuid", "password"?}`. Starts activation and returns with `connecting` set |
| `set wifi.disconnect disconnect` | `Set(id, value)` | Disconnects the selected adapter |
| `set known-networks.add <json>` | `Set(id, json)` | `{"ssid","security":"open"\|"wpa2"\|"wpa3","password"?,"hidden"?,"autoconnect"?}`. Saves without activating |
| `set known-networks.autoconnect <json>` | `Set(id, json)` | `{"uuid","value":true\|false}` |
| `set known-networks.metered <json>` | `Set(id, json)` | `{"uuid","value":"automatic"\|"yes"\|"no"}` |
| `set known-networks.change-password <json>` | `Set(id, json)` | `{"uuid","value":"password"}` for personal networks |
| `set known-networks.forget <uuid>` | `Set(id, uuid)` | Deletes the profile, verified by readback |
| `set network-status.sign-in open` | `Set(id, value)` | Opens the connectivity address in a captive portal |
| `resolve network <system/settings>` | `Resolve("network", source)` | Adopts system preferences, or applies saved ones with readback |

Use `-` as the CLI value to read it from stdin, so a password does not appear in the process list:
`printf '%s' '{"ssid":"Cafe","password":"..."}' | remya_settings set wifi.connect -`

Every other `network-status.*`, `wifi.*` and `known-networks.*` control is read-only or `planned`. `known-networks.mac`, `known-networks.priority` and `network-status.data-usage` return `Unavailable`. `Get("configuration")` includes `network`. `Changed("network", state)` reports NetworkManager changes, excluding signal strength between scans. `NetworkClient` in `packages/remya_settings_client` exposes these without Flutter.

## Night light

Night light requires hyprsunset. Settings writes only
`$XDG_CONFIG_HOME/hypr/hyprsunset.conf`, keeps a snapshot in `night-light.toml` and
runs hyprsunset through its packaged `hyprsunset.service`, which a write enables and
restarts. hyprsunset cannot reload, so every configuration change replaces the
process; gamma and a manual override on a schedule are carried across.

```text
remya_settings get night-light
remya_settings set night-light.e32be03e true
remya_settings set night-light.temperature 2600
remya_settings set night-light.7e6239c9 true
remya_settings set night-light.e8868af6 19:00
remya_settings set night-light.a0bb9f49 06:30
remya_settings resolve night-light system
```

| Setting | Values | Effect |
| --- | --- | --- |
| `night-light.e32be03e` Night light | `true`, `false` | Saved without a schedule; on a schedule, a live override until the next boundary |
| `night-light.temperature` | `1000`-`6500` K | Saved in every profile |
| `night-light.7e6239c9` Schedule | `true`, `false` | Fixed hours through two native profiles, 19:00 to 06:30 at first; turning it off leaves Night light on |
| `night-light.e8868af6`, `.a0bb9f49` Start, End | `HH:MM`, different from each other | Profile times; rejected without a schedule |
| `night-light.50840111` Timing | Unavailable | Sunset to sunrise is planned |

The file is parsed strictly: anything other than comments, `max-gamma` and the one
or two profiles Settings can express blocks writes and leaves it untouched. Only the
file is reconciled with the snapshot. The live on/off state and temperature are not,
because other tools such as the shell's quick toggle change them routinely.

The filter is a hardware color transform, so it is not part of screenshots or
recordings. On an HDR output it may be applied to encoded values and look too strong;
the page says so while any display uses HDR.

## Bluetooth

`Get("bluetooth")` returns `available`, `adapters`, `devices`, `scanning`,
`operation`, `prompt`, and `error`. `scanning` contains only Settings-owned scan
sessions; adapter `discovering` can also reflect another application's session.
Adapters include `id`, `address`, `name`, `powered`, `discoverable`, `discovering`
and `pairable`, with nullable `hardware_blocked` and `software_blocked` from Linux rfkill sysfs. Devices include `id`, `adapter`, `address`, `name`, `icon`, `paired`,
`bonded`, `connected`, `blocked` and nullable `battery` (0–100). IDs are current
BlueZ object paths and must be obtained again after hotplug or service restart.

All Bluetooth writes accept a JSON object. Input is limited to 4096 bytes;
unknown fields, unknown targets and incorrect adapter/device membership fail.

| Setting ID | JSON input |
| --- | --- |
| `bluetooth.enabled` | `{"adapter":"<id>","enabled":true}` or false |
| `bluetooth.scan` | `{"adapter":"<id>","enabled":true}` starts/renews a 60-second scan; false releases the own session |
| `bluetooth.discoverable` | Same input; true requests a discoverable 60-second scan, false releases it |
| `bluetooth.pair` | `{"adapter":"<id>","device":"<id>"}` pairs, then attempts to connect |
| `bluetooth.connect` / `bluetooth.disconnect` | `{"adapter":"<id>","device":"<id>"}` |
| `bluetooth.forget` | `{"adapter":"<id>","device":"<id>"}` removes the device and its bond |
| `bluetooth.cancel` | `{}` cancels pending pairing |
| `bluetooth.respond` | `{"request":<prompt-id>,"pin":"1234"}`, `{"request":<id>,"passkey":123456}`, or `{"request":<id>,"accept":true}`; `accept:false` rejects any pending request |
| `airplane.bluetooth` | Literal `open`, equivalent to opening the Bluetooth page |

`bluetooth.adapter`, `bluetooth.devices` and `bluetooth.information` are read-only
catalog entries. Adapter selection is local to each client; each operation sends
its adapter explicitly. `Get` on a Bluetooth setting returns catalog availability
and the same complete Bluetooth state in `value`, with its error.

Writes return the current state with an operation `id`, `kind`, `status`, `adapter`
and optional `device`. Acceptance is `running`, not success. Completion is
`completed`, `failed` or `cancelled`, reported through readback and
`Changed("bluetooth", state)` (also included in CLI `watch all`). Only one device
operation runs at a time; cancellation, scan cleanup and Agent responses remain
available during it. Pair timeout is 120 seconds. Errors retain actual device state,
including a successful bond whose subsequent connection failed.

A prompt includes `id`, `device` and `kind` (BlueZ Agent method name). Display and
comparison prompts carry a zero-padded `code`; DisplayPasskey also has `entered`.
AuthorizeService includes `service`. Display prompts need no reply; other prompts
require a matching request ID. PIN is 1–16 ASCII alphanumeric characters; passkeys
are integers 0–999999. Input PINs are not stored, echoed or logged; display codes
are intentionally visible to clients until their prompt ends. Use stdin to keep
input PINs out of the process list:

```bash
remya_settings get bluetooth
remya_settings set bluetooth.scan '{"adapter":"/org/bluez/hci0","enabled":true}'
remya_settings set bluetooth.respond -
```

No API method signature or existing payload changes. There is no Bluetooth
configuration snapshot or `Resolve` operation; see [Bluetooth](bluetooth.md) for
state ownership and the explicit hardware verification limits.


## Account information and Settings avatar

| CLI | D-Bus | Result |
| --- | --- | --- |
| `get account-information` | `Get("account-information")` | `api_version`, read-only `username`, nullable `avatar_path`/`avatar_revision`, and nullable `error` |
| `get your-info.a1aaf352` | `Get(id)` | Service user's GLib/NSS username and the same account state |
| `get your-info.58484bbb` | `Get(id)` | Saved Settings avatar path and the same account state |
| `set your-info.58484bbb <json>` | `Set(id, json)` | Updated account state after atomic avatar persistence |

Avatar JSON is `{"path":"/absolute/image.png","crop":{"left":0,"top":0,"right":1,"bottom":1}}`. Crop edges are finite normalized coordinates in the source image after EXIF orientation; require `0 <= left < right <= 1` and `0 <= top < bottom <= 1`. PNG, JPEG and WebP input is bounded to 32 MiB, 64 megapixels and 16,384 pixels per side. The ordinary-user Rust service decodes, crops and resizes with system GdkPixbuf and saves a 512 × 512 PNG beside its configuration. No source image is changed or retained. Invalid input, unsupported decoding and failed persistence leave the last saved avatar intact. Avatar destination symlinks are rejected.


The GUI uses the MIT-licensed Croppy crop component with its public pure-Dart Cassowary solver option. A small Flutter input adapter sends drag, pinch, vertical mouse wheel and slider changes through the same public controller and square crop rectangle, with 1–8× zoom. Scrolling up zooms in; scrolling down zooms out. The package's native asset is still built and bundled, and its Kiwi/Loki notices are retained, but avatar geometry does not depend on loading that native library. The service continues to own decoding and saved output.

Username rejects Set with ReadOnly. `Changed("account-information", state)` reports avatar changes through the same versioned interface; `AccountInformationClient` supplies pure Dart helpers. The avatar is app-owned data: it has no system counterpart, reconciliation or elevation, does not change a desktop/account picture, and does not enable login. Manage Account and Login options remain unavailable previews.

## Sound

`Get("sound")` and the pure Dart `SoundClient.readSound()` return version-1 state:
`api_version`, `available`, nullable `error` and live `system`.
`system` contains nullable `default_output`/`default_input`, `devices` and `streams`.
Devices have stable `name`, current `index`, `description`, `direction` (`output` or
`input`), `rate`, `channels`, `state` and `preferences`. Stream records have current
`index`, nullable `client`, `name`, `application`, `direction`, `device`,
`has_volume`, `volume_writable` and `preferences`. Preferences contain raw
PulseAudio channel volumes (`65536` is 100%) and `muted`.

All writes are bounded to 4096 bytes and use the existing `Set(id, json)` / `remya_settings set id '<json>'`
contract. `SoundClient.changeSound` encodes a Dart map; `setSound` accepts JSON.

| Setting IDs | JSON input |
| --- | --- |
| `sound.output-device`, `sound.input-device` | `{"name":"stable-server-device-name"}` |
| `sound.output-volume`, `sound.input-volume` | `{"percent":50}`; optional `name` selects a particular device |
| `sound.output-muted`, `sound.input-muted` | `{"muted":true}`; optional `name` selects a particular device |
| `sound.device-volume` | `{"direction":"output","name":"device-name","percent":50}` |
| `sound.device-muted` | `{"direction":"input","name":"device-name","muted":true}` |
| `sound.stream-volume` | `{"direction":"output","index":42,"client":17,"percent":50}` |
| `sound.stream-muted` | `{"direction":"input","index":42,"client":17,"muted":true}` |
| `sound.stream-device` | `{"direction":"output","index":42,"client":17,"device":"destination-name"}` |
| `sound.refresh` | `{}` |

Volume must be finite and between 0 and 150%; scaling preserves channel balance.
Unknown fields, unavailable devices, stale streams and unwritable stream volume
fail explicitly. `client:null` is required for a stream without a client index.
`sound.devices` and `sound.streams` are read-only inventory catalog entries.
Getting any available Sound setting returns the same state with its ID and
availability. Writes return verified readback; `Changed("sound", state)` reports
changes. The configuration summary includes the same live Sound/error state.

All Sound settings follow current audio-server state and are never persisted or
compared with a saved configuration. Sound has no `Resolve` operation; the CLI,
D-Bus and Dart client expose only live reads, writes and refresh. Readback checks
only the requested field. See [Sound](sound.md) for dependencies and verification
boundaries.

## System updates

`Get("updates")` returns `api_version`, `revision`, `available`, `reason`, `missing` (required tool paths that are absent), `updater` (`installed`, `missing` or `outdated`), `install_command`, `aur` (whether yay exists), `all`, `retry`, `busy`, `phase` (`idle`, `checking`, `upgrading`, `retrying`, `completed`, `failed`), `kind` (`check`, `upgrade`, `scheduled`), `attempt`, `retry_at`, `checked_at`, `held`, `packages` (`name`, `installed`, `available`, `source` = `repository` or `AUR`, `held`), `eligible` (an unheld repository update exists), `output` and `error`, plus `schedule` (`enabled`, `active_start`, `active_end`, `last_run_day`, `notice`, `error`, `editable`). `Get("updates")` re-reads the installed root updater. Per-setting Get adds `id` and `availability` (`available`, or `unsupported` when required tools are missing).

| CLI | D-Bus | Result |
| --- | --- | --- |
| `set updates.check check` | `Set(id, "check")` | Starts an asynchronous check; needs only the tools |
| `set updates.upgrade upgrade` | `Set(id, "upgrade")` | Starts an asynchronous repository upgrade; `Unavailable` until the root updater is installed |
| `set updates.include-held <bool>` | `Set(id, value)` | Session-only; `Busy` while an operation runs |
| `set updates.retry <bool>` | `Set(id, value)` | Session-only; `false` stops further attempts |
| `set updates.automatic <bool>` | `Set(id, value)` | Saved in `updates.json` |
| `set active-hours.e8868af6 HH:mm` | `Set(id, value)` | Active hours start; saved local time, must differ from the end |
| `set active-hours.a0bb9f49 HH:mm` | `Set(id, value)` | Active hours end; automatic updates start when it is reached |

`updates.status` and `updates.output` reject Set with `ReadOnly`. A second check or upgrade while busy returns `Busy`. `Changed("updates", state)` is published at most once a second while anything changes. Quit returns `Busy` while an update runs. Upgrades never use the GUI-authorized privileged helper: the service runs `pkexec /usr/local/libexec/remya-settings-update upgrade [--include-held]`, which is allowed without a password only by the polkit rule from `tool/install_system_updater.py`. The Dart `UpdatesClient` exposes every operation above. See [System updates](updates.md).

## Cameras

`Get("cameras")` returns api_version, available, initialized, devices, saved,
conflicts (node names) and error. Each device has name, serial, description,
framerate and controls. Each control reports value, min, max, step, default and
writable. `Get("cameras.devices")` and individual control IDs return the same
state with id. Inventory is read-only.

`Set("cameras.brightness|contrast|saturation|sharpness", JSON)` accepts
`{"camera":"node.name","serial":52,"value":3}` with an actual current device
identity. `Set("cameras.reset", JSON)` accepts camera and serial, without value.
These operations validate capabilities and verify readback. Errors are retained.

`Resolve("cameras:<node.name>", "system|settings")` adopts the detected values
or applies saved values for that camera. `Get("configuration")` includes cameras.
`Changed("cameras", state)` reports operations, resolutions and periodic changes.
CLI get/set/resolve use the identical service operations. CameraClient exposes
readCameras, changeCamera and resolveCamera without Flutter. `open cameras`
opens the page; local frame rendering is a GUI concern and not a D-Bus payload.
See [Camera](camera.md) for dependencies, persistence and verification.

## Power

The automatic Energy saver activation threshold accepts integer selections or a boolean toggle. The independent turn-off threshold uses `battery-saver.off-threshold`. See [power operations and history contract](power.md#public-operations). All writes use the owning Rust controller. History uses bounded SQLite queries.

## Remy'a Bar appearance

Use `get remya-bar.clock-seconds` and `set remya-bar.clock-seconds <true|false>`
or the corresponding `Get(id)` and `Set(id, value)` D-Bus methods. Both
return `{"id":"remya-bar.clock-seconds","availability":"available","value":true}`
with the effective boolean. After a successful write, `Changed` uses the setting
ID as its topic and carries the same payload. The pure Dart `BarClockClient`
extension provides typed read and write methods.

The ordinary-user service stores `clock_seconds` as a boolean in
`remya-bar.toml`. A missing file defaults to `true`. Malformed files are
reported and protected from overwrites. This preference controls the clock
capsule across outputs and has no system counterpart.

### Remya Bar folded applications

`Get("remya-bar.folded-apps")` returns an available setting whose `value` is
the list of folded StatusNotifierItem IDs. The list defaults to empty.
`Set("remya-bar.folded-apps", "{\"id\":\"app-id\",\"folded\":true}")` adds one
ID, and `folded: false` removes it. The operation returns the updated setting
and emits `Changed` with the same topic. The CLI accepts the same JSON string
as its set value. Settings serializes edits and atomically stores the list in
`remya-bar-tray.toml` beside its selected configuration.
