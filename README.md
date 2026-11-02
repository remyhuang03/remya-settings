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

A global system settings application for **Hyprland on Linux**, built with **Flutter**, **Material Design 3 Expressive**, and a modular **Rust workspace**. Layout and information architecture reference Windows 11 Settings.

## Implemented Features

Settings combines a Windows 11-inspired hierarchy with native Linux and Hyprland backend integrations, reconciled with host state via Rust:

- **Appearance**: Wallpaper management (`hyprpaper` images & `mpvpaper` videos), dynamic Material accent color extraction, Fontconfig font manager, and synchronized Light/Dark switching for GNOME/GTK and Qt Quick.
- **Apps**: XDG default MIME associations (`mimeapps.list`), installed desktop applications inventory with guarded pacman/flatpak uninstallation, an AppImage library with zsync delta updates and live progress, and detected external configuration tools under More.
- **Display**: Hyprland monitor arrangement, resolution, scaling, rotation, HDR, backlight brightness (`logind` / `ddcutil`), and safe atomic persistence to `monitors.lua` with a keep-or-revert countdown timer.
- **Night light**: Color temperature, on/off and fixed-hours schedule through `hyprsunset`.
- **Network**: Real-time connection status, Wi-Fi radio power toggle, access point scanning, connection handling, and saved NetworkManager profiles.
- **System & Hostname**: Real-time hardware/OS specifications (CPU, GPU, memory, swap, disk, uptime) and polkit-authorized hostname editing.
- **Date & Time**: NTP synchronization via `systemd-timedated`, timezone selection (`ListTimezones`), manual clock setting, and `LC_TIME` calendar formatting.
- **Configuration Reconciliation**: Non-destructive system detection on launch and automatic conflict resolution prompts between saved preferences and live system state.

## Settings Catalog & Coverage

Browse Home, 12 categories, 220 detail pages, and About; search settings locally, follow related pages, and inspect third-party licenses.

- **Current Catalog**: 12 categories, 217 pages, 1,813 controls (139 available with real system backends, 1,640 planned previews, 34 unsupported).
- **Windows 11 Reference**: Covers 140 pages, 1,074 reference controls, 155 unique URI names from reference tables, and 335 hierarchy entries (247 leaf controls) in its backup catalog. See [research, sources, and limitations](docs/windows-settings-research.md).
- **Hyprland Extensions**: Adds 2 categories, 83 pages, and 762 controls based on official configuration documentation and ecosystem tools. See [Hyprland sources and version limits](docs/hyprland-settings-research.md).
- **Availability & Tracking**: Every setting declares availability (`available`, `planned`, or `unsupported`). Unavailable controls remain disabled while allowing navigation to preview pages; contextually inapplicable options are hidden automatically. See the [implementation progress checklist](docs/settings-implementation-progress.md).

## Architecture & Resident Service

Settings uses a client-service architecture to keep memory footprint minimal and provide full operation parity across GUI, CLI, and D-Bus interfaces:

- **Resident User Service (`remya_settings`)**: An ordinary-user Rust service that owns production configuration, reconciliation, CLI dispatch, and the session D-Bus interface (`top.remya.settings.Settings1`).
- **Disposable Flutter GUI**: The Flutter desktop application connects as a disposable client. Closing the window immediately terminates the Flutter process to release engine memory, while the resident service continues running for dependent clients.
- **GPU Optimization**: The native runner prefers the integrated GPU for the Flutter settings window to avoid discrete GPU (e.g. NVIDIA) driver memory overhead.
- **Privilege Separation**: Elevated operations (such as hostname changes and package uninstallation) execute through a dedicated helper process authenticated via polkit communicating over private bounded pipes.
- **Dependent Applications**: Remya Bar (`top.remya.bar`) integrates via `packages/remya_settings_client` (pure Dart, zero Flutter/backend dependencies) for synchronized themes and settings observation over D-Bus. See [public API and process boundaries](docs/public-api.md).

## Repository Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart               Flutter startup
  app.dart                Application composition and theme
  features/
    about/                Product information and licenses
    appearance/           App preferences, atomic TOML storage, theme state
    applications/         Installed application inventory and external tools
    background/           Wallpaper management (hyprpaper / mpvpaper) and accent color
    date_time/            Date, time, NTP, and time zone management
    default_apps/         XDG MIME default application associations
    display/              Hyprland display outputs, layout, and brightness
    fonts/                Font browsing, preview, installation, and removal
    integration/          Resident service controllers and status
    network/              Network status, Wi-Fi, and known networks
    settings/             Catalog model, navigation, search, page renderer
    system_information/   Hardware/OS specifications and hostname management
  src/rust/
    appearance/           GNOME/GTK settings and Qt toolkit environments
    appearance_bridge/    Generated Flutter/Rust bridge for appearance
    applications/         Desktop entry parsing, icon lookup, package uninstall
    background/           Hyprpaper IPC, mpvpaper unit, media copying, accent extraction
    core/                 Backend types and crate boundaries
    date_time/            systemd-timedated client and calendar helpers
    date_time_bridge/     Generated Flutter/Rust bridge for date/time
    default_apps/         mimeapps.list reader/writer and MIME associations
    display/              Hyprland monitor rules, monitors.lua, and brightness
    fonts/                Fontconfig queries, font installation, and metadata
    network/              NetworkManager client and saved-network reconciliation
    service/              Resident session D-Bus service and privileged helper
    system_information/   Hardware/OS inspection and systemd-hostnamed client
packages/
  remya_settings_client/  Pure Dart D-Bus client library for Remya Bar and dependent apps
assets/
  icons/                  Application icon (SVG and rendered PNG)
  settings/               UI catalog and JSON Schema
linux/                    Native runner, GPU preference, and packaging templates
docs/                     Architecture, research snapshots, public API, and progress tracking
test/                     Catalog, unit tests, and CLI/D-Bus interface smoke tests
tool/                     Installer, CLI generator, and license notice tools
```

## Development

Prerequisites: FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, GTK 3 development libraries, GLib/GIO 2.84+ headers, and GSettings tools). Current Arch Linux packages are the target; GTK 4 appearance requires GTK 4.20+. fish and luac validate their respective configuration targets.

```bash
fvm install
fvm flutter pub get
fvm flutter run -d linux
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. See `AGENTS.md` for project rules and guidelines.

### Code Quality & Verification

Run all checks before presenting changes:

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
fvm flutter build linux --debug
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
git diff --check
```

After updating Rust dependencies, run `python tool/generate_rust_notices.py` to refresh bundled third-party notices.

## Installation

The application ID is `top.remya.settings`; its executable is `remya_settings`.
Build and install into `XDG_DATA_HOME` with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

- Launch **Remy'a Settings** from the application menu, run `remya_settings`, or use `gtk-launch top.remya.settings`.
- CLI commands: `remya_settings --help` lists available commands. Implemented features provide full CLI parity (e.g. `remya_settings get theme`, `remya_settings get display`, `remya_settings get background`, `remya_settings get hostname`, `remya_settings get default-app`).
- To exit the resident background service before updates, run `remya_settings quit`.
- See [XDG directory layout](docs/xdg-layout.md) and [public API documentation](docs/public-api.md).

## Usage & Keyboard Shortcuts

- **Search**: `Ctrl+F` or `Ctrl+E` focuses search; `Escape` clears search.
- **Navigation**: `Alt+Left` navigates back through history.
- **Window Geometry**: Minimum window size is 360 × 600 logical pixels; initial requested size is 1,251 × 720. Compositor tiling rules may override requested geometry.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
