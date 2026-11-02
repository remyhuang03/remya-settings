# AppImages

Apps > AppImages manages AppImage applications kept in one folder, `$HOME/AppImages`. The folder is fixed so updates, launchers and command links always find the same file. It is not configurable.

## What it does

- **Install** copies a chosen `.AppImage` into the folder as `<Name>.AppImage`, where `Name` comes from the image's desktop entry. The original file stays where it was. Opening an AppImage from a file manager uses the hidden `top.remya.settings.appimage.desktop` handler (`remya_settings install-appimage <path>`). The handler installs the file and opens this page.
- **Launcher integration** writes `$XDG_DATA_HOME/applications/<id>.desktop` and an icon under `$XDG_DATA_HOME/icons/`. Only standard descriptive keys (`Name`, `GenericName`, `Comment`, `Categories`, `Keywords`, `MimeType`, `StartupWMClass`, `StartupNotify`, `Terminal`, `OnlyShowIn`, `NotShowIn`, `PrefersNonDefaultGPU`, `SingleMainWindow`, their translations) and `X-` extensions come from the image. `Exec`, `TryExec`, actions and other keys never do: `Exec` is always `env DESKTOPINTEGRATION=1 "<path>"` plus the image's file field code. The launcher is the visible (`NoDisplay` not `true`) entry that runs the image; hidden handlers an application registers for itself are left alone. An ID already used by another user entry or by `/usr/share/applications` falls back to `appimage-<name>.desktop`.
- **Update sources** are resolved in this order:
  1. a source the user saved;
  2. the image's embedded `.upd_info`;
  3. the launcher's `X-AppImage-UpdateURL`.

  Accepted sources:
  - `https://github.com/<owner>/<repo>`, which uses the latest release's AppImage for this CPU architecture;
  - `gh-releases-zsync|owner|repo|tag|glob`;
  - `zsync|<https URL>`;
  - an https `.zsync` URL.
- **Check** compares the published SHA-256 (GitHub `digest`) or zsync SHA-1 with the installed file. Without a checksum, a size change counts as a new build.
- **Update** uses a zsync delta when the release publishes one, and the whole file otherwise; a failed delta falls back to the whole file. The download is written to `.<id>.part` beside the image. It must be an AppImage and match the published checksum before it is renamed over the installed file, so the path, launchers and command links stay valid. The launcher is then refreshed with the new version.
- **Progress** is published once a second as `Changed("appimages", state)` while work runs. Each job reports a `status` (`queued`, `checking`, `comparing`, `downloading`, `installing`), `bytes`, `total` and `speed` in bytes per second. Cancel stops the download and removes partial files.
- **Automatic checks** run at most once a day while the resident service is running, with failed attempts spaced an hour apart. When **Install updates automatically** is on, available updates are installed as they are found. Checks are on by default; automatic installation is off.
- **Move to Trash** uses the desktop Trash through GIO. It also removes the launcher, the application's own hidden handler entries that point at the image (URL or folder handlers it registered itself), the app's own icon when no other entry uses it, and command links in `~/.local/bin` that point at the image. Application data in the home folder is kept.

Portable home or configuration folders (`.home`, `.config`) are intentionally not provided.

## Safety

Images are never executed to read metadata. The service reads the ELF section table and `.upd_info` itself, and reads the SquashFS payload with [`backhand`](https://crates.io/crates/backhand). Payload symlinks resolve lexically inside the image. Only the top-level desktop file (1 MiB limit) and icon (16 MiB limit) are read into memory. DwarFS payloads are reported as unsupported.

Every request uses https through `ureq` with `https_only`, including redirects and zsync block requests. Hand-entered sources must be https. Release assets for another CPU architecture are ignored. `backhand` is built without `lzo`, whose Rust implementation is GPL-2.0.

## Preferences

`appimages.toml`, beside `config.toml`, stores `auto_check`, `auto_update`, `last_check` (epoch seconds) and the per-app `source` / `updates_disabled` choices. It is written atomically. A malformed file is reported and never overwritten. These are app-owned preferences with no system counterpart, so there is nothing to reconcile.

## References and reused work

- [AppImage update information](https://github.com/AppImage/AppImageSpec/blob/master/draft.md#update-information)
- [zsync-rs](https://crates.io/crates/zsync-rs) (MIT)
- [backhand](https://crates.io/crates/backhand) (MIT OR Apache-2.0)

The feature scope follows [AppManager](https://github.com/kem-a/AppManager) at the product level only; AppManager is GPL-3.0, so no code is taken from it. [`appimageupdate`](https://crates.io/crates/appimageupdate) was not used: it renames the installed file away for the whole download, and it derives the output path from the control file. [`appimage-rs`](https://crates.io/crates/appimage-rs) was not used because it always enables backhand's GPL-2.0 `lzo` codec.

## Verification

- Rust unit tests cover:
  - source parsing and https enforcement;
  - architecture and glob asset selection;
  - the checksum-then-size update decision;
  - ELF `.upd_info` and payload-offset reading, including out-of-range tables;
  - payload link confinement;
  - desktop entry rendering that drops image commands and quotes paths;
  - preference persistence, damaged-file retention, request validation, automatic-check spacing and icon-removal confinement.
- `test/service_controllers_test.dart` covers live progress state and visible rejected writes.
- `test/interface_smoke.py` runs against the installed bundles with isolated XDG roots. It uses a real GridCraft release with 64 KiB zeroed. It installs through `install-appimage`, then checks:
  - the launcher with `desktop-file-validate`;
  - source changes over the CLI and over D-Bus;
  - a real zsync delta update with live progress and `Changed` signals;
  - byte-for-byte readback against the published release;
  - Move to Trash.
