# Default apps

The Apps > Default apps page manages XDG file and URI associations through the ordinary-user Rust service and GIO. It requires the same GLib/GIO 2.84 minimum as the service. No new third-party dependency or privileged process is introduced.

## Controls

| Control | Stable ID | Scope |
| --- | --- | --- |
| File or link type | `defaults.b131ac5a` | Search an extension, MIME type, or URI scheme; choose a supported handler for each type. Extensions use the shared MIME database's globs and may return several types. |
| Applications | `defaults.897fdfef` | Search installed visible desktop applications. Open the supported-type list, set individual defaults, or confirm the listed types together (up to 256). |
| Web browser | `defaults.ccac113f` | HTTP and HTTPS together; candidate must declare both. HTML files remain independently selectable. |
| Mail | `defaults.3adc9929` | `x-scheme-handler/mailto` |
| Photos | `defaults.c0b97974` | Registered `image/*` MIME types and their extensions |
| Video | `defaults.e7fe6be6` | Registered `video/*` MIME types and their extensions |
| Audio | `defaults.audio` | Registered `audio/*` MIME types and their extensions |
| Text editor | `defaults.text` | `text/plain` |
| PDF | `defaults.pdf` | `application/pdf` |
| File manager | `defaults.file-manager` | `inode/directory` |

One search field matches application names and IDs locally and searches extensions, MIME types, and URI schemes through the service after a short debounce. Both result groups appear together; stale requests cannot replace a newer query.

Grouped media shortcuts list registered MIME types and affect only those declared by the selected application. The picker shows the exact list before confirmation. Mixed defaults, unset defaults, unknown reads, and missing desktop IDs are explicit readouts in the left column. Changes apply on confirmation in the picker. Search and application-detail views do not write system configuration. Selected defaults use overlapping application icons for mixed associations; unset types do not contribute an icon. A single assigned application uses an unframed icon so its edge stays visible. Clicking the group or Manage opens a searchable, lazy extension/protocol list with per-MIME Change actions and Set all. Extensions sharing one MIME type (for example .jpg and .jpeg) are explicitly linked; Settings does not create custom MIME overrides to split them. Application rows and picker candidates display real application icons through the existing GTK 3 runner and current desktop icon theme. Missing icons use a generic fallback.

`defaults.ff4c4bec` (Reset all default apps) remains planned and disabled. There is no whole-file deletion, invented Linux terminal role, or editing of Hyprland key-binding commands.

## Ownership, persistence, and failures

`lib/src/rust/default_apps` owns discovery, validation, readback, and reconciliation. GIO resolves XDG precedence, including desktop-specific files; Settings validates readable association files before accepting GIO's unset result. It never rewrites desktop entry commands or shells out to launch candidates.

`default-apps.toml` beside the service configuration contains version 1 and a MIME-to-desktop-ID table. An empty string records an unset default. First use snapshots real system associations without changing them. Startup and page entry compare this saved snapshot against fresh system reads. Newly discovered types stay unmanaged until explicit editing or adopting the system. A read or persistence failure leaves the last valid saved snapshot intact.

Conflicts preserve saved and actual values, with explicit Use system configuration and Apply saved Settings actions. Applying saved Settings fails visibly if an application was removed, ceased declaring support, or the saved value is unset. Restoring an unset value through GIO would reset other associations; choose a handler or adopt the actual system state instead.

All mutations are serialized by the service. Each write checks the just-read default against the snapshot and verifies the resulting handler. Multiple types do not form a system transaction. A failed group attempts to restore previous handlers in reverse order; a previously unset handler cannot be safely restored this way, so incomplete rollback is reported with the affected types. GIO may also add the chosen handler to the association list; restoring a default does not remove those additional candidate associations. Persistence failure after a system write remains visible with the old saved values and the new system values.

Applications that use internal preferences or custom openers may bypass XDG defaults. This feature cannot force those applications to obey the associations.

## Interfaces and verification

The GUI and pure Dart client use the same `Get`, `Set`, and `Resolve` operations as CLI and D-Bus. See [public API](public-api.md#default-applications) and [XDG layout](xdg-layout.md).

- Rust tests cover first-use failure, no-write initialization, both conflict resolutions, invalid input, configuration failure retention, batch rollback, unset rollback limits, and incorrect readback.
- `test/service_controllers_test.dart` covers failed-write retention and unresolved conflicts. The picker, extensions, unified search, and icons were verified during implementation; local presentation checks are not retained.
- `python test/interface_smoke.py` uses synthetic desktop entries under isolated HOME/XDG roots to test real GIO writes/readback, external conflicts, both resolutions, extension search, browser grouping, and CLI/D-Bus parity. It also checks that removed pages cannot be opened.

## Primary references

- [freedesktop.org MIME Applications specification](https://specifications.freedesktop.org/mime-apps/latest/)
- [GIO AppInfo](https://docs.gtk.org/gio/iface.AppInfo.html)
- [GIO set_as_default_for_type](https://docs.gtk.org/gio/method.AppInfo.set_as_default_for_type.html)
