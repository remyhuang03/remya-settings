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
with `remya_settings --service`, runs the normal controller and Rust backend in a
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
| `get system` | `Get(s key)` with `system` | Fresh system mode and target readback |
| `get catalog` | `Get(s key)` with `catalog` | Sources, categories, and page summaries |
| `get page:<id>` | `Get(s key)` with `page:<id>` | Complete page, sections, and control metadata |
| `get <setting-id>` | `Get(s key)` | ID, availability, reason, and current value where implemented |
| `set <setting-id> <value>` | `Set(ss id, value)` | Effective theme after successful persistence and system readback |
| `list` | `List(s cursor)` | All controls in CLI; one bounded page on D-Bus |
| `search <query>` | `Search(s query)` | Matching page IDs, titles, and categories |
| `open [page-id]` | `Open(s page)` | `{"opened":"<page>"}`; defaults to `home` in CLI |
| `reload` | `Reload()` | Theme and freshly observed system state |
| `watch [theme\|all]` | `Changed(ss topic, json)` signal plus an initial `Get("theme")` | JSON lines in CLI |
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
