# Installed apps

Installed apps lists desktop applications registered through GIO, plus visible package-owned launchers whose user overrides prevent normal discovery, and Flatpak apps. It is not a list of every library or command-line package. Application rows show real icons and names with a compact wrapping summary of source, labeled version, and labeled size. Details add location, package identity, and native installation dates. Unavailable metadata stays explicitly unavailable.

The feature reuses the installed GTK 3 runner for themed icon rendering; raster and SVG icons are decoded asynchronously into PNG bytes. Flutter caches those bytes for the GUI lifetime. The headless Rust service exposes serialized GIcon metadata and does not initialize a GTK display.

## Settings and state

- `installed.15735a25`: application/package search.
- `installed.3bf3689a`: name, descending package size, or descending installation date; missing values sort last.
- `installed.765cf6c3`: source filter (replaces the Windows drive filter without changing its ID).
- `installed.32098ab2`: per-application details.
- `installed.c3c4a29c`: confirmed uninstall.

The application list uses `SliverList.builder`; search, sorting, and filtering operate on the observed metadata without rebuilding the entire list. Inventory is refreshed on page entry, explicit Refresh, and uninstall outcomes. These are live observations and session-local view preferences, so there is no saved system configuration to reconcile.

Native metadata comes from the current ALPM database format (pacman 6.1+), using the system's `pacman-conf DBPath`. Package size belongs to the entire package; launchers sharing a package repeat that size. Flatpak uses the current `list --json` interface and `info --show-size`. Version and deployment date may be unavailable; no filesystem timestamp is labeled as a Flatpak installation date. Displayed native dates are formatted using actual system LC_TIME via the Rust date/time backend.

## Uninstall boundary

Every removal carries an observed desktop/ref ID and version/commit token. The backend re-reads ownership and version before invoking a fixed package-manager command and verifies absence afterward. Stale tokens and unknown/manual entries fail; package dependency errors are reported without forcing removal. The GUI confirms the application and package scope, including other launchers in the package.

Native removal is `pacman -R --noconfirm -- <owned-package>`, through the existing authorized private Rust helper. It does not request recursive dependency removal, skip dependency checks, discard saved package configuration, or delete application data. The helper accepts no command, path, database root, or shell snippet from a client.

Flatpak removal uses an exact app ref with `--app --noninteractive --assumeyes --no-related`, omits `--delete-data`, and verifies inventory readback. User installations run without elevation; system installations use the authorized helper. Removal may take longer than ordinary reads; the Dart client allows five minutes for this operation. Package scripts run under the package manager's normal policy.

Manual installations remain visible with an explanation and disabled uninstall. Permissions, repair, and reset remain unavailable previews. This implementation does not delete launchers as a substitute for uninstalling an application.

## Verification

`test/service_controllers_test.dart` covers fresh inventory and failure retention after unsuccessful uninstall operations. UI search, lazy rows, details, and confirmation were checked during implementation; their local presentation tests are not retained. Rust tests cover current ALPM parsing, duplicate/invalid metadata, and invalid uninstall requests. `test/interface_smoke.py` verifies actual native versions/dates against pacman, unauthorized native rejection, and a real temporary user Flatpak install/uninstall with application data retained, plus CLI/D-Bus parity. No real workstation package is removed by verification; successful privileged native/system-Flatpak removal remains a manual verification boundary.

References: [ALPM description format](https://man.archlinux.org/man/alpm-db-desc.5.en), [ALPM files format](https://man.archlinux.org/man/alpm-db-files.5.en), [pacman](https://man.archlinux.org/man/pacman.8.en), [Flatpak commands](https://docs.flatpak.org/en/latest/flatpak-command-reference.html).
