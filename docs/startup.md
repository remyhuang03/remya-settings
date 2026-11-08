# Startup apps

Settings manages XDG Autostart applications for Hyprland sessions started through
UWSM. UWSM activates `xdg-desktop-autostart.target`; systemd's
`systemd-xdg-autostart-generator` generates `app-<escaped>@autostart.service`
units. Changes affect the next sign-in; Settings never starts or stops an app.

## Discovery and generator semantics

The effective entry is the first file with a given `.desktop` filename, searching
`$XDG_CONFIG_HOME/autostart` (fallback `$HOME/.config/autostart`) before each
`$XDG_CONFIG_DIRS/autostart` directory (default `/etc/xdg`). Relative XDG paths
are ignored. An entry is System whenever a system directory contains its ID,
including when a user override wins; other entries are Added by you.

GLib KeyFile preserves comments, translations and unrelated keys during edits.
Names and comments use the current locale. Entries are sorted by name ignoring
case, then ID. A disabled user override is merged over the next system file
with the same ID for display metadata and filtering; user keys take precedence.
This keeps minimal Hidden-only overrides visible as disabled system entries.
Invalid files are omitted and counted in `skipped_invalid`.
Unreadable directories fail detection and leave the saved snapshot unchanged.

The model targets systemd 262 semantics: `Hidden=true` disables an entry;
`OnlyShowIn` and `NotShowIn` match any colon-separated `XDG_CURRENT_DESKTOP`
component. Non-Application entries, unmatched desktop conditions, unresolved or
non-executable `TryExec`, any `X-GNOME-Autostart-Phase` key, and
`X-systemd-skip=true` are omitted. `X-GNOME-Autostart-enabled` does not determine
the effective enabled state; when editing an entry with that key, Settings keeps
it synchronized with Hidden for other desktop consumers.

`X-KDE-autostart-condition` is preserved. The generator delegates this runtime
condition to `kde-systemd-start-condition`; Settings does not evaluate arbitrary
application conditions or run their commands while discovering entries. The
resulting unit status reports what the session manager actually did. See the
[systemd generator source](https://github.com/systemd/systemd/blob/v262/src/xdg-autostart-generator/xdg-autostart-service.c).

## Writes

All entry writes go to the user autostart directory, atomically with mode 0644.
Settings never edits system directories, Hyprland configuration, UWSM units,
application installations, or generated systemd units. Symlinked user entries and
a symlinked autostart directory are refused because the shared atomic writer
follows links.

Turning an entry off sets Hidden in its user file, copying the system file when
needed. Turning it on removes Hidden. If the resulting user KeyFile data equals
the system file, the override is removed so package updates take effect again.
Enabling a user override without an Exec key removes it when a system entry exists,
so a minimal disabling stub cannot shadow the system executable.
Customized overrides with Exec remain. System entries can only be turned off,
not removed.
Removing a user-only entry deletes just its startup file, leaving the app installed.

Add an app resolves an installed desktop ID through GIO and copies its desktop
file without Hidden. Existing listed entries must be enabled instead. Unlisted
files with a colliding ID are preserved and the add is rejected. Add a custom
command validates its name and executable, parses shell quoting with GLib, then
quotes argv for Desktop Entry Exec syntax and doubles literal percent signs.
There is no shell execution. If readback fails after adding an app or command,
the newly written file is removed before returning the error. Names produce
`remya-<slug>.desktop`, with numeric suffixes for collisions, including filtered files. IDs must be at most 255 bytes,
end in `.desktop`, and contain no path separators, leading dot or control characters.

## Reconciliation

`startup.toml` lives next to the selected main Settings config, with `version = 1`
and an `[enabled]` table mapping filenames to booleans. Unknown fields, invalid
IDs and unsupported versions are rejected without overwriting the file.

First successful detection saves actual enabled states and never applies defaults.
Refresh compares only shared IDs: changed enabled states create explicit conflicts,
with both values retained. The entry set is excluded: additions are adopted and
removals dropped automatically because Settings cannot recreate a deleted file's
content. Both resolutions use the feature manager: Use system configuration
saves readback; Apply Settings configuration writes each differing saved value,
verifies it, then saves. Writes are blocked during conflict. Detection, write,
readback and persistence failures remain visible and preserve the last valid
saved snapshot. A partial failed application can leave system entries changed;
the next read exposes any remaining conflicts for explicit resolution.

## Runtime observations

A read-only session-bus query calls `ListUnitsByPatterns` for autostart services,
then reads Unit.SourcePath and Service.Result. Exact effective source paths map
units to entries; a new override may therefore show Not started until next login.
Active/running means Running; active/exited or inactive with Result=success means
Finished; failed units or unsuccessful results mean Failed; no matching unit
means Not started. The target's ActiveState supplies `session_autostart`.
When it is false, the UI retains the UWSM explanation and hides runtime row labels
and the Last sign-in summary. The summary also stays hidden when all running,
finished and failed counts are zero.
An unreachable manager makes statuses and session state null, with `status_error`,
without blocking enabled-state discovery or writes. Status is live observation,
never persisted. A 30-second service refresh emits Changed startup when it changes.

## Verification and boundaries

`cargo test -p remya_settings_startup -p remya_settings_service` covers isolated
files, generator filters, override preservation, command quoting, validation,
reconciliation and failing writes, with a fake systemd query.
`test/startup_page_test.dart` covers the page, controller, dialogs and routing.
`startup_fixtures()` and `startup_checks()` in `test/interface_smoke.py` cover the
normal installed CLI/D-Bus smoke flow, using temporary HOME/XDG roots and a private
session bus. The architect runs this full flow after installation; it was not
rerun during this review because it invokes installers and other desktop features.
Actual sign-in under UWSM, real generated unit properties, translated desktop
entries and KDE runtime conditions still require desktop/session verification.
