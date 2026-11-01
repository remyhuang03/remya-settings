<p align="center">
  <img src="assets/icons/settings.svg" width="128" alt="Remy'a Settings icon">
</p>

<h1 align="center">Remy'a Settings</h1>

A global system settings application for **Hyprland on Linux**, built with **Flutter**, **Material Design 3 Expressive**, and a modular **Rust workspace**. Layout and information architecture reference Windows 11 Settings.

## Implemented Features & Integrations

Settings combines a Windows 11-inspired hierarchy with native Linux and Hyprland backend integrations. Real device and system settings are implemented in Rust and reconciled with the underlying host:

- **Personalization (Wallpaper, Accent, Fonts, & Themes)**:
  - **Wallpaper**: Image backgrounds managed via `hyprpaper` IPC and video wallpapers managed through a dedicated `mpvpaper` systemd unit. Supports multi-monitor setups (per-display or grouped displays) and copies selected media into application storage.
  - **Accent Color**: Dynamic Material palette extraction from the active wallpaper or manual selection using a color picker with presets.
  - **Fonts**: Fontconfig-backed font browser with live previews, style and format inspection, font file installation (`.ttf`, `.otf`), and user font uninstallation.
  - **System Appearance**: Synchronized Light/Dark theme switching for GNOME/GTK targets and official Qt Quick environment defaults persisted through fish and Hyprland Lua configuration.
- **Display**:
  - Live Hyprland monitor output detection, arrangement, resolution, refresh rate, scaling, rotation, mirroring, HDR, and color profiles.
  - Hardware backlight brightness control via `logind` and external monitors via `ddcutil`.
  - Atomic configuration persistence to `$XDG_CONFIG_HOME/hypr/monitors.lua` with strict Lua validation and a keep-or-revert countdown safety timer.
- **System Information & Hostname**:
  - Real-time specifications for OS distribution, Linux kernel, Hyprland version, CPU, GPU, memory, swap, disk usage, and uptime.
  - Hostname inspection and editing with polkit authorization via `systemd-hostnamed`.
- **Date & Time**:
  - Clock synchronization via `systemd-timedated` with automatic NTP toggle.
  - Manual date/time setting and system timezone selection from `ListTimezones`.
  - Calendar date formatting adhering to system `LC_TIME`.
- **System Configuration Reconciliation**:
  - Reads and validates actual system state on first run without imposing arbitrary defaults.
  - Compares saved preferences with fresh system readbacks at startup and on page navigation, alerting users to conflicts with explicit options to adopt system configuration or reapply saved settings.

## Settings Catalog & Coverage

Browse Home, 12 categories, 258 detail pages, and About; search settings locally, follow related pages, and inspect third-party licenses.

- **Current Catalog**: 12 categories, 258 pages, 1,979 controls (68 available with real system backends, 1,808 planned previews, 103 unsupported).
- **Windows 11 Reference**: Covers the 204 unique names in Microsoft's public URI tables and 343 hierarchy entries (257 leaf controls) in its Windows 11 backup catalog. See [research, sources, coverage, and limitations](docs/windows-settings-research.md).
- **Hyprland Extensions**: Adds 90 pages and 784 controls based on official configuration documentation and existing ecosystem tools. See [Hyprland sources, classifications, and version limits](docs/hyprland-settings-research.md).
- **Availability & Tracking**: Every setting declares availability (`available`, `planned`, or `unsupported`). Unavailable controls remain disabled while allowing navigation to preview pages; contextually inapplicable options are hidden automatically. See the [item-by-item implementation progress checklist](docs/settings-implementation-progress.md).

## Architecture & Resident Service

Settings uses a client-service architecture to keep memory footprint minimal and provide full operation parity across GUI, CLI, and D-Bus interfaces:

- **Resident User Service (`remya_settings`)**: An ordinary-user Rust service that owns production configuration, reconciliation, CLI dispatch, and the session D-Bus interface (`top.remya.settings.Settings1`).
- **Disposable Flutter GUI**: The Flutter desktop application connects as a disposable client. Closing the window immediately terminates the Flutter process to release engine memory, while the resident service continues running for dependent clients.
- **GPU Optimization**: The native runner prefers the integrated GPU for the Flutter settings window to avoid discrete GPU (e.g. NVIDIA) driver memory overhead.
- **Privilege Separation**: Elevated operations (such as hostname changes) execute through a dedicated helper process authenticated via polkit (`polkit-kde-agent`) communicating over private bounded pipes.
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
    background/           Wallpaper management (hyprpaper / mpvpaper) and accent color
    date_time/            Date, time, NTP, and time zone management
    display/              Hyprland display outputs, layout, and brightness
    fonts/                Font browsing, preview, installation, and removal
    integration/          Resident service controllers and status
    settings/             Catalog model, navigation, search, page renderer
    system_information/   Hardware/OS specifications and hostname management
  src/rust/
    appearance/           GNOME/GTK settings and Qt toolkit environments
    appearance_bridge/    Generated Flutter/Rust bridge for appearance
    background/           Hyprpaper IPC, mpvpaper unit, media copying, accent extraction
    core/                 Backend types and crate boundaries
    date_time/            systemd-timedated client and calendar helpers
    date_time_bridge/     Generated Flutter/Rust bridge for date/time
    display/              Hyprland monitor rules, monitors.lua, and brightness
    fonts/                Fontconfig queries, font installation, and metadata
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
- CLI commands: `remya_settings --help` lists available commands. Implemented features provide full CLI parity (e.g. `remya_settings get theme`, `remya_settings get display`, `remya_settings get background`, `remya_settings get hostname`).
- To exit the resident background service before updates, run `remya_settings quit`.
- See [XDG directory layout](docs/xdg-layout.md) and [public API documentation](docs/public-api.md).

## Usage & Keyboard Shortcuts

- **Search**: `Ctrl+F` or `Ctrl+E` focuses search; `Escape` clears search.
- **Navigation**: `Alt+Left` navigates back through history.
- **Window Geometry**: Minimum window size is 360 × 600 logical pixels; initial requested size is 1,251 × 720. Compositor tiling rules may override requested geometry.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
