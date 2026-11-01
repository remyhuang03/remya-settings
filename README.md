# Remy'a Settings

A global system settings application for **Hyprland on Linux**, using **Flutter**, **Material Design 3 Expressive**, and a **Rust workspace**. Layout and information architecture reference Windows 11 Settings.

## Current milestone: system appearance and host previews

Browse Home, 12 categories, 292 detail pages, and About; search settings, follow related pages, and inspect third-party licenses. Date/time controls include automatic synchronization, persistent time servers with Default, time zone GMT offsets, manual time, and system LC_TIME. Display controls arrange real Hyprland outputs and set brightness, scale, resolution, refresh rate, orientation, mirroring, color, and HDR, with advanced options in a collapsed section; see [Display](docs/public-api.md#display). The catalog contains 2,105 controls; availability is tracked per setting in the catalog and implementation checklist. Appearance reads installed GNOME/GTK preferences and changes them only when explicitly selected; documented Qt Quick defaults are saved through fish and Hyprland Lua configuration. Other device/account values are examples, never detected host state, and preview controls do not persist values.

The inventory covers the 204 unique names in Microsoft's public URI tables and 343 hierarchy entries (257 leaf controls) in its Windows 11 backup catalog. This is an application-owned UI schema, not an export of Windows' unpublished internal schema. See [research, sources, coverage, and limitations](docs/windows-settings-research.md).

See the [item-by-item implementation progress checklist](docs/settings-implementation-progress.md) for every setting's stable ID, implementation status, and space for tracking and verification notes.

The Hyprland extension adds 105 pages and 837 controls based on official configuration documentation and existing settings tools; the current Windows-reference pages and controls remain covered. See [Hyprland sources, classifications, and version limits](docs/hyprland-settings-research.md).

## Layout

```text
Cargo.toml                Root Rust workspace
lib/
  main.dart               Flutter startup
  app.dart                Application composition and theme
  features/
    appearance/           App preferences, atomic TOML storage, theme state
    settings/             Catalog model, navigation, search, page renderer
    about/                Product information and licenses
  src/rust/
    core/                 Empty future backend crate
    appearance/           GNOME/GTK settings and Qt toolkit environments
    appearance_bridge/    Generated Flutter/Rust bridge
    display/              Hyprland monitor rules, monitors.lua, and brightness
assets/
  icons/                  Owner-provided SVG and rendered PNG
  settings/               UI catalog and JSON Schema
linux/                    Native runner and packaging templates
docs/                     Research and coverage snapshot
test/                     Catalog, interaction, and layout checks
```

Flutter stays at the repository root. Rust crates live under `lib/src/rust/` and are registered in the root workspace. The appearance feature uses `flutter_rust_bridge` 2.13.0; Linux CMake builds its shared library. The ordinary-user Rust service owns configuration and API dispatch; Flutter connects as a disposable GUI client. Closing the window releases the Flutter process while the small user service and its authorized helper stay resident. See [configuration architecture and supported settings](docs/app-preferences.md) and [the example configuration](config/config.example.toml).

## Development

Install FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, and GTK 3 development libraries, GLib/GIO 2.84+ headers, and GSettings tools). Current Arch packages are the target; GTK 4 appearance requires GTK 4.20+. fish and luac validate their respective environment configuration targets. From the repository root:

```bash
fvm install
fvm flutter pub get
fvm flutter run -d linux
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. Stable Rust follows installed toolchain updates. See `AGENTS.md` for project rules.

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

After Rust dependency changes, run `python tool/generate_rust_notices.py` to refresh bundled third-party notices. GLib/GIO use dynamic system linking; generated notices are shown in the license view.

## Install in the user application menu

The application ID is `top.remya.settings`; its executable remains `remya_settings`.
Build and install into XDG_DATA_HOME with a user command in `~/.local/bin`:

```bash
fvm flutter build linux --release
python tool/install.py
```

Launch **Remy'a Settings** from the menu, run `remya_settings`, or use
`gtk-launch top.remya.settings`. `remya_settings --help` lists the CLI. The D-Bus
service starts on demand without a window and stays available after the UI is
closed; run `remya_settings quit` before updating. The installer preserves config
and refuses to replace unrelated commands or a running bundle. See
[the XDG directory layout](docs/xdg-layout.md) and
[the complete CLI and D-Bus API](docs/public-api.md).

Remya Bar is a separate dependent application. Its public integration boundary is
`packages/remya_settings_client`: versioned contracts, D-Bus transport, shared MD3E
theme, and observable theme state. GUI, CLI, and D-Bus operations share the same
resident Rust service and its feature backends.

Keyboard shortcuts: Ctrl+F or Ctrl+E focuses search, Escape clears search, and Alt+Left navigates back. The sidebar stays visible; the native window minimum size is 360 × 600 logical pixels, with an initial requested size of 1,251 × 720. The compositor controls placement and may override size hints when tiling. Themes → Material Design controls the app palette and system Light/Dark mode. Environment defaults affect new fish processes and the next Hyprland session; see the configuration document for supported targets and override limits.

Licensed under [PolyForm Noncommercial License 1.0.0](LICENSE), matching `image_resizer`.


Date/time settings use Rust and systemd-timedated's system D-Bus API for manual
time and finite-list time zone selection. See [the API](docs/public-api.md) for
input formats, authorization, first-use system adoption, conflict resolution,
and the concurrent check scheduler. Other date/time controls remain previews.

## Resident Settings

The ordinary-user Rust service owns the public D-Bus interface, configuration,
and system readback. The Flutter window is a separate client and exits completely
on close. `remya_settings close` closes only the window; `remya_settings quit`
stops Settings and its authorized helper. The first explicit GUI launch requests
one system authorization using `polkit-kde-agent`; Bar's read-only activation does
not. Reopening the GUI reuses a successful authorization while Settings remains
resident. See [the public API and process boundaries](docs/public-api.md).

`python test/resident_service_smoke.py` measures PSS and checks three real GUI
close/reopen cycles on a private bus. `python test/interface_smoke.py` checks the
installed CLI/D-Bus contract and three-output Bar theme propagation.
