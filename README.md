<p align="center">
  <img src="assets/icons/settings.svg" width="128" alt="Remy'a Settings icon">
</p>

<h1 align="center">Remy'a Settings</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-1793D1?logo=archlinux" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.47.8-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Rust-2024-dea584?logo=rust" alt="Rust">
  <a href="docs/public-api.md"><img src="https://img.shields.io/badge/D--Bus-top.remya.settings-5865F2" alt="D-Bus"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue" alt="License"></a>
</p>

A global system settings application for **Hyprland on Linux**, built with **Flutter**, **Material Design 3 Expressive**, and a modular **Rust workspace**. Layout and information architecture are inspired by modern desktop settings benchmarks like Windows 11 Settings, while tailored and diverged for native Linux and Hyprland workflows.

> [!CAUTION]
> **Early Development & Preview Only — Not Ready for Daily Use**
>
> - **Under Active Development**: This software is in an early, experimental stage of development and has **not** reached a usable production state.
> - **Majority of Features Unavailable**: Out of 1,335 controls across 123 catalog pages, **966 controls are unimplemented UI-only previews** (`planned`) and 10 are platform-inapplicable (`unsupported`). 359 controls currently have backend integrations.
> - **Implemented Features Are Unstable**: Even the implemented integrations are unstable, subject to breaking changes, and may have incomplete hardware verification boundaries.
> - **For Preview & Evaluation Only**: This repository is currently intended strictly for design preview and development reference. Use at your own risk on real systems.

## Implemented Features (Experimental)

- **Desktop and Appearance**. Configure wallpapers, themes, fonts, display layouts, night light, window behavior, and Remya Bar personalization. Detailed styling and interface controls are documented in [Appearance](docs/app-preferences.md) and [Themes](docs/themes.md).
- **Connectivity and Devices**. Manage network connections, VPNs, and proxies alongside device pairing and shortcut recording. See [Network](docs/network.md), [Bluetooth](docs/bluetooth.md), [Sound](docs/sound.md), [Camera](docs/camera.md), and [Input](docs/input.md) for audio routing, video feeds, and peripherals.
- **Apps and Storage**. Oversee default MIME handlers, installed software, AppImage packages, and XDG session autostart entries. Inspect drive partitions, track usage, and clean package caches using [Default apps](docs/default-apps.md), [Installed apps](docs/installed-apps.md), [AppImages](docs/appimages.md), [Startup](docs/startup.md), and [Storage](docs/storage.md).
- **System and Power**. Track battery metrics, idle policies, hardware specifications, user avatars, and time synchronization. Configure Energy Saver thresholds and manage software upgrades through [Power](docs/power.md) and [System updates](docs/updates.md).

## Settings Catalog & Coverage

Browse Home, category pages, and About; search settings locally, follow related pages, and inspect third-party licenses.

- **Current Catalog**: 15 categories, 123 pages, 1,335 controls (359 available, 966 planned previews, 10 unsupported).
- **Desktop Reference & Inspiration**: Draws reference from applicable desktop settings benchmarks (including Windows 11 reference taxonomies), retaining relevant pages, controls, URI names, and hierarchy structures as design inspiration while departing where native Linux and Hyprland workflows differ. Removed Windows-only features are excluded from coverage records. See [research, sources, and limitations](docs/windows-settings-research.md).
- **Hyprland Extensions**: Retains controls based on official configuration documentation and ecosystem tools, merging related previews into ordinary pages’ Advanced sections. See [Hyprland sources and version limits](docs/hyprland-settings-research.md).
- **Availability & Tracking**: Every setting declares availability (`available`, `planned`, or `unsupported`). Unavailable controls remain disabled while allowing navigation to preview pages; contextually inapplicable options are hidden automatically. See the [implementation progress checklist](docs/settings-implementation-progress.md).

## Architecture & Resident Service

Settings uses a client-service architecture to keep memory footprint minimal and provide full operation parity across GUI, CLI, and D-Bus interfaces:

- **Resident User Service (`remya_settings`)**: An ordinary-user Rust service that owns production configuration, reconciliation, CLI dispatch, and the session D-Bus interface (`top.remya.settings.Settings1`).
- **Disposable Flutter GUI**: The Flutter desktop application connects as a disposable client. Closing the window immediately terminates the Flutter process to release engine memory, while the resident service continues running for dependent clients.
- **GPU Optimization**: The native runner prefers the integrated GPU for the Flutter settings window to avoid discrete GPU (e.g. NVIDIA) driver memory overhead.
- **Privilege Separation**: Elevated operations (such as hostname changes and package uninstallation) execute through a dedicated helper process authenticated via polkit communicating over private bounded pipes.
- **Dependent Applications**: Remya Bar (`top.remya.bar`) integrates via `packages/remya_settings_client` (a package with a pure Dart D-Bus contract and Flutter theme helpers) for synchronized themes and settings observation over D-Bus. See [public API and process boundaries](docs/public-api.md).

## Repository Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart, app.dart     Flutter startup, composition, and theme
  features/<feature>/     Feature-first Flutter UI, state, and controllers
  src/rust/<crate>/       Modular Rust backends, bridges, and resident service
packages/
  remya_settings_client/  Pure Dart D-Bus contract and Flutter theme helpers
assets/                   Application icons, settings catalog/schema, and license notices
linux/                    Native runner, GPU preference, and packaging templates
docs/                     Architecture, feature specs, public API, and progress tracking
test/                     Unit, widget, catalog, and isolated CLI/D-Bus smoke tests
tool/                     Installer, CLI entrypoint, and license notice generator
```

## Development

Prerequisites: FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, GTK 3 development libraries, GLib/GIO 2.84+, GdkPixbuf and libpulse headers, and GSettings tools). Current Arch Linux packages are the target; GTK 4 appearance requires GTK 4.20+. fish and luac validate their respective configuration targets. Sound requires dynamically linked system `libpulse` (PulseAudio 15+ API) and the current PipeWire, pipewire-pulse and WirePlumber services. Network requires NetworkManager; Bluetooth requires BlueZ; Night light requires `hyprsunset`; elevated operations require `polkit-kde-agent`.

```bash
fvm install
fvm flutter pub get
fvm flutter run -d linux
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. See `AGENTS.md` for project rules and guidelines.

### Code Quality & Verification

Choose checks for the actual change. Keep focused tests for non-trivial logic and regressions, and check affected interactions on the real desktop. Application changes are delivered through a rebuilt, locally installed release for review; see `AGENTS.md`.

After updating Rust dependencies, run `python tool/generate_rust_notices.py` to refresh bundled third-party notices.

## Installation

The application ID is `top.remya.settings`; its executable is `remya_settings`. For paired installations with Remya Bar, install Settings before Bar so that shared services and D-Bus interfaces are in place.

### Release Archive

When installing from a Linux x86_64 release archive from [GitHub Releases](https://github.com/remyhuang03/remya-settings/releases), verify the checksum against `SHA256SUMS`, extract the archive, and run `tool/install.py`:

```bash
sha256sum -c SHA256SUMS
tar --zstd -xf remya_settings-0.1.0-dev.20261109.0-linux-x86_64.tar.zst
cd remya_settings-0.1.0-dev.20261109.0-linux-x86_64
python tool/install.py
```

### Building from Source

Build and install into `XDG_DATA_HOME` with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

### System Updater

For system updates, install the root updater and its polkit rule once (and again when the page reports it outdated):

```bash
sudo python tool/install_system_updater.py
```

- Launch **Remy'a Settings** from the application menu, run `remya_settings`, or use `gtk-launch top.remya.settings`.
- CLI commands: `remya_settings --help` lists available commands. Implemented features provide full CLI parity (e.g. `remya_settings get theme`, `remya_settings get display`, `remya_settings get background`, `remya_settings get sound`, `remya_settings get network`, `remya_settings get bluetooth`, `remya_settings get default-apps`, `remya_settings get hostname`, `remya_settings get power`).
- The resident background service starts with the graphical session (`top.remya.settings.service`). `tool/install.py` stops and restarts it around an update; it refuses while a system update is running. Run `remya_settings quit` to stop it manually.
- See [XDG directory layout](docs/xdg-layout.md) and [public API documentation](docs/public-api.md).

## Usage & Keyboard Shortcuts

- **Search**: `Ctrl+F` or `Ctrl+E` focuses search; `Escape` clears search.
- **Navigation**: `Alt+Left` navigates back through history.
- **Window Geometry**: Minimum window size is 360 × 600 logical pixels; initial requested size is 1,251 × 720. Compositor tiling rules may override requested geometry.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
