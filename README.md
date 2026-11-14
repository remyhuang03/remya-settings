<p align="center">
  <img src="assets/icons/app_icon-full.svg" width="128" alt="Remy'a Settings icon">
</p>

<h1 align="center">Remy'a Settings</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.8-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <a href="https://github.com/remyhuang03/remya-core/blob/main/docs/public-api.md"><img src="https://img.shields.io/badge/D--Bus-top.remya.Core1-5865F2" alt="D-Bus"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License"></a>
</p>

A global system settings application for **Hyprland on Linux**, built with **Flutter**, **Material Design 3 Expressive**, and [**Remya Core**](https://github.com/remyhuang03/remya-core). Layout and information architecture are inspired by modern desktop settings benchmarks like Windows 11 Settings, while tailored and diverged for native Linux and Hyprland workflows.

> [!CAUTION]
> **Early Development & Preview Only — Not Ready for Daily Use**
>
> - **Under Active Development**: This software is in an early, experimental stage of development and has **not** reached a usable production state.
> - **Many Features Unavailable**: Core reports which controls have verified integrations and which remain UI-only previews (`planned`).
> - **Implemented Features Are Unstable**: Even the implemented integrations are unstable, subject to breaking changes, and may have incomplete hardware verification boundaries.
> - **For Preview & Evaluation Only**: This repository is currently intended strictly for design preview and development reference. Use at your own risk on real systems.

## Implemented Features (Experimental)

- **Desktop and Appearance**. Configure wallpapers, themes, window appearance, animations, workspaces, text size, fonts, display layouts, night light, bell. Detailed styling and interface controls are documented in [Appearance](https://github.com/remyhuang03/remya-core/blob/main/docs/app-preferences.md) and [Themes](https://github.com/remyhuang03/remya-core/blob/main/docs/themes.md).
- **Connectivity and Devices**. Manage network connections, VPNs, and proxies alongside device pairing and shortcut recording. See [Network](https://github.com/remyhuang03/remya-core/blob/main/docs/network.md), [Bluetooth](https://github.com/remyhuang03/remya-core/blob/main/docs/bluetooth.md), [Sound](https://github.com/remyhuang03/remya-core/blob/main/docs/sound.md), [Camera](https://github.com/remyhuang03/remya-core/blob/main/docs/camera.md), and [Input](https://github.com/remyhuang03/remya-core/blob/main/docs/input.md) for audio routing, video feeds, and peripherals.
- **Apps and Storage**. Oversee default MIME handlers, installed software, AppImage packages, and XDG session autostart entries. Inspect drive partitions, track usage, and clean package caches using [Default apps](https://github.com/remyhuang03/remya-core/blob/main/docs/default-apps.md), [Installed apps](https://github.com/remyhuang03/remya-core/blob/main/docs/installed-apps.md), [AppImages](https://github.com/remyhuang03/remya-core/blob/main/docs/appimages.md), [Startup](https://github.com/remyhuang03/remya-core/blob/main/docs/startup.md), and [Storage](https://github.com/remyhuang03/remya-core/blob/main/docs/storage.md).
- **System and Power**. Track battery metrics, idle policies, hardware specifications, user avatars, languages, locales, and time synchronization. Configure Energy Saver thresholds, AI providers and usage monitoring, and manage software upgrades through [Power](https://github.com/remyhuang03/remya-core/blob/main/docs/power.md) and [System updates](https://github.com/remyhuang03/remya-core/blob/main/docs/updates.md).

## Settings Catalog & Coverage

Browse Home, category pages, and About; search settings through Core, follow related pages, and inspect third-party licenses.

- **Current Catalog**: Loaded from Remya Core; the GUI does not maintain its own catalog copy.
- **Desktop Reference & Inspiration**: Draws reference from applicable desktop settings benchmarks (including Windows 11 reference taxonomies), retaining relevant pages, controls, URI names, and hierarchy structures as design inspiration while departing where native Linux and Hyprland workflows differ. Removed Windows-only features are excluded from coverage records. See [research, sources, and limitations](https://github.com/remyhuang03/remya-core/blob/main/docs/windows-settings-research.md).
- **Hyprland Extensions**: Retains controls based on official configuration documentation and ecosystem tools, merging related previews into ordinary pages’ Advanced sections. See [Hyprland sources and version limits](https://github.com/remyhuang03/remya-core/blob/main/docs/hyprland-settings-research.md).
- **Availability & Tracking**: Every setting declares availability (`available` or `planned`). Unavailable controls remain disabled while allowing navigation to preview pages; contextually inapplicable options are hidden automatically. The catalog's `availability` and `reason` fields are the tracker; verification evidence lives in each feature document.

## Architecture & Resident Service

Settings is a disposable GUI client of [Remya Core](https://github.com/remyhuang03/remya-core).
Core owns `remyad`, the `remya` CLI, `top.remya.Core1`, system reconciliation,
and shared preferences. Closing Settings releases its Flutter process.
Only camera preview frames use an in-process Rust wrapper of Core's camera crate.
Remya apps own their preferences through Core registrations; Bar, Clipboard and
notification configuration no longer belongs to Settings.

The GUI consumes `remya_client` and `remya_ui` from a sibling `../remya-core`
checkout. Navigation comes from `Get("catalog")`, details from `Get("page:<id>")`,
and search from Core's `Search`. See [GUI development](docs/gui-client.md).

## Repository Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart, app.dart     Flutter startup, composition, and theme
  features/<feature>/     Feature-first Flutter UI, state, and controllers
  src/rust/camera_preview/ In-process camera preview bridge
  src/rust/camera_bridge/  Generated Dart bridge
assets/                   Application icons and license notices
linux/                    Native runner, GPU preference, and packaging templates
docs/                     GUI client architecture and UI performance notes
test/                     Controller, widget, catalog-loader and isolated installer tests
tool/                     GUI installer and license notice generator
```

## Development

Prerequisites: FVM, Rust via rustup, a sibling Remya Core checkout, and Linux
Flutter build tools (Clang, CMake, Ninja, pkg-config and GTK 3). Camera preview
links dynamically to PipeWire and GStreamer 1.28+. Install Core separately for
system integration dependencies and D-Bus activation.

```bash
fvm install
fvm flutter pub get
fvm flutter run -d linux
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. See `AGENTS.md` for project rules and guidelines.

### Code Quality & Verification

Choose checks for the actual change. Keep focused tests for non-trivial logic and regressions, and check affected interactions on the real desktop. Validate changes with analysis, tests and a release build. Install only when authorized; see `AGENTS.md`.

After updating Rust dependencies, run `python tool/generate_rust_notices.py` to refresh bundled third-party notices.

## Installation

The application ID is `top.remya.settings`; its executable is `remya_settings`. Install Remya Core first; the GUI installer requires its D-Bus activation file.

### Release Archive

When installing from a Linux x86_64 release archive from [GitHub Releases](https://github.com/remyhuang03/remya-settings/releases), verify the checksum against `SHA256SUMS`, extract the archive, and run `tool/install.py`:

```bash
sha256sum -c SHA256SUMS
tar --zstd -xf remya_settings-0.1.0-dev.20261111.0-linux-x86_64.tar.zst
cd remya_settings-0.1.0-dev.20261111.0-linux-x86_64
python tool/install.py
```

### Building from Source

Build and install into `XDG_DATA_HOME` with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

System updates and the privileged updater are owned by
[Remya Core](https://github.com/remyhuang03/remya-core/blob/main/docs/xdg-layout.md).
Launch from the application menu, `remya_settings`, or `gtk-launch top.remya.settings`.
Use Core's `remya` command for CLI operations. The GUI installer writes only the
bundle, command, desktop entries and icon, and refuses to replace a running GUI.

## Usage & Keyboard Shortcuts

- **Search**: `Ctrl+F` or `Ctrl+E` focuses search; `Escape` clears search.
- **Navigation**: `Alt+Left` navigates back through history.
- **Window Geometry**: Minimum window size is 360 × 600 logical pixels; initial requested size is 1,280 × 720. Compositor tiling rules may override requested geometry.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
