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
> - **Majority of Features Unavailable**: Out of 1,667 controls across 138 catalog pages, **1,480 controls are unimplemented UI-only previews** (`planned`) and 10 are platform-inapplicable (`unsupported`). Only 177 controls currently have backend integrations.
> - **Implemented Features Are Unstable**: Even the implemented integrations are unstable, subject to breaking changes, and may have incomplete hardware verification boundaries.
> - **For Preview & Evaluation Only**: This repository is currently intended strictly for design preview and development reference. Use at your own risk on real systems.

## Implemented Features (Experimental)

Settings combines an information architecture inspired by modern desktop settings with native Linux and Hyprland backend integrations, reconciled with host state via Rust:

- **Appearance**: Wallpaper management (`hyprpaper` images & `mpvpaper` videos), dynamic Material accent color extraction, Fontconfig font manager, and synchronized Light/Dark switching for GNOME/GTK and Qt Quick. See [Appearance](docs/app-preferences.md).
- **Apps**: XDG default MIME associations (`mimeapps.list`), installed desktop applications inventory with guarded pacman/flatpak uninstallation, an AppImage library (`$HOME/AppImages`) with zsync delta updates and live progress, and detected external configuration tools under More. See [Default apps](docs/default-apps.md), [Installed apps](docs/installed-apps.md), and [AppImages](docs/appimages.md).
- **Display**: Hyprland monitor arrangement, resolution, scaling, rotation/flip, HDR, colour presets, backlight brightness (`logind` / `ddcutil`), and safe atomic persistence to `monitors.lua` with a keep-or-revert countdown timer.
- **Night light**: Color temperature, on/off, and fixed-hours schedule through `hyprsunset` (`hyprsunset.conf`).
- **Network**: Real-time connection status, live adapter traffic speeds, Wi-Fi radio power toggle, access point scanning, connection handling, and saved NetworkManager profiles. See [Network](docs/network.md).
- **Bluetooth**: Adapter power, rfkill diagnostics, temporary discoverability, device scanning, pairing with interactive BlueZ Agent prompts (PIN, passkey, numeric comparison), connection toggling, battery reporting, and bond removal via system BlueZ. See [Bluetooth](docs/bluetooth.md) for features, API, and hardware verification limits.
- **Sound**: Native PipeWire output/input defaults, device volume and mute, application volume mixer/routing, and full sound device inventory, with persisted preference reconciliation through the per-user PulseAudio (`libpulse`) API. See [Sound](docs/sound.md).
- **System & Hostname**: Real-time read-only hardware/OS/firmware specifications (CPU, memory, motherboard, BIOS/UEFI DMI, kernel) via `sysinfo` and sysfs, plus polkit-authorized static hostname editing via `systemd-hostnamed`.
- **Account information**: Read-only process username, plus a Settings-owned avatar (`avatar.png`) with interactive square crop, pan, and zoom.
- **Date & Time**: NTP synchronization and custom NTP server drop-ins via `systemd-timedated` / `systemd-timesyncd`, timezone selection (`ListTimezones`), manual clock setting, and `LC_TIME` calendar formatting via `systemd-localed`.
- **System updates**: Repository and AUR update checks, repository upgrades with pacman through a fixed root-owned updater, session-only held-package and retry choices, and optional automatic updates that the login-started service runs when your active hours end. AUR packages are listed, not installed. See [System updates](docs/updates.md).
- **Configuration Reconciliation**: Non-destructive system detection on first launch and automatic conflict resolution prompts between saved preferences and live system state.

## Settings Catalog & Coverage

Browse Home, category pages, and About; search settings locally, follow related pages, and inspect third-party licenses.

- **Current Catalog**: 13 categories, 138 pages, 1,667 controls (177 available, 1,480 planned previews, 10 unsupported).
- **Desktop Reference & Inspiration**: Draws reference from applicable desktop settings benchmarks (including Windows 11 reference taxonomies), retaining relevant pages, controls, URI names, and hierarchy structures as design inspiration while departing where native Linux and Hyprland workflows differ. Removed Windows-only features are excluded from coverage records. See [research, sources, and limitations](docs/windows-settings-research.md).
- **Hyprland Extensions**: Retains 762 controls based on official configuration documentation and ecosystem tools, merging related previews into ordinary pages’ Advanced sections. See [Hyprland sources and version limits](docs/hyprland-settings-research.md).
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
  main.dart, app.dart     Flutter startup, composition, and theme
  features/<feature>/     Feature-first Flutter UI, state, and controllers
  src/rust/<crate>/       Modular Rust backends, bridges, and resident service
packages/
  remya_settings_client/  Pure Dart D-Bus client library for Remya Bar and dependent apps
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

The application ID is `top.remya.settings`; its executable is `remya_settings`.
Build and install into `XDG_DATA_HOME` with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

For system updates, install the root updater and its polkit rule once (and again when the page reports it outdated):

```bash
sudo python tool/install_system_updater.py
```

- Launch **Remy'a Settings** from the application menu, run `remya_settings`, or use `gtk-launch top.remya.settings`.
- CLI commands: `remya_settings --help` lists available commands. Implemented features provide full CLI parity (e.g. `remya_settings get theme`, `remya_settings get display`, `remya_settings get background`, `remya_settings get sound`, `remya_settings get network`, `remya_settings get bluetooth`, `remya_settings get default-apps`, `remya_settings get hostname`).
- The resident background service starts with the graphical session (`top.remya.settings.service`). `tool/install.py` stops and restarts it around an update; it refuses while a system update is running. Run `remya_settings quit` to stop it manually.
- See [XDG directory layout](docs/xdg-layout.md) and [public API documentation](docs/public-api.md).

## Usage & Keyboard Shortcuts

- **Search**: `Ctrl+F` or `Ctrl+E` focuses search; `Escape` clears search.
- **Navigation**: `Alt+Left` navigates back through history.
- **Window Geometry**: Minimum window size is 360 × 600 logical pixels; initial requested size is 1,251 × 720. Compositor tiling rules may override requested geometry.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
