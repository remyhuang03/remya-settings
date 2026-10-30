# Remy'a Settings

A global system settings application for **Hyprland on Linux**, using **Flutter**, **Material Design 3 Expressive**, and a **Rust workspace**. Layout and information architecture reference Windows 11 Settings.

## Current milestone: system appearance and host previews

Browse Home, 13 categories, 308 detail pages, and About; search settings, follow related pages, and inspect third-party licenses. The catalog contains 2,182 controls: a working application Material palette, a Rust-backed system Light/Dark setting, and 2,180 disabled host previews. Appearance reads installed GNOME/GTK preferences and changes them only when explicitly selected; documented Qt Quick defaults are saved through fish and Hyprland Lua configuration. Other device/account values are examples, never detected host state, and preview controls do not persist values.

The inventory covers the 219 unique names in Microsoft's public URI tables and all 354 hierarchy entries (267 leaf controls) in its Windows 11 backup catalog. This is an application-owned UI schema, not an export of Windows' unpublished internal schema. See [research, sources, coverage, and limitations](docs/windows-settings-research.md).

See the [item-by-item implementation progress checklist](docs/settings-implementation-progress.md) for every setting's stable ID, implementation status, and space for tracking and verification notes.

The Hyprland extension adds 106 pages and 859 controls based on official configuration documentation and existing settings tools; the original Windows-reference pages and controls are preserved. See [Hyprland sources, classifications, and version limits](docs/hyprland-settings-research.md).

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
assets/
  icons/                  Owner-provided SVG and rendered PNG
  settings/               UI catalog and JSON Schema
linux/                    Native runner and packaging templates
docs/                     Research and coverage snapshot
test/                     Catalog, interaction, and layout checks
```

Flutter stays at the repository root. Rust crates live under `lib/src/rust/` and are registered in the root workspace. The appearance feature uses `flutter_rust_bridge` 2.13.0; Linux CMake builds its shared library. App-owned appearance preferences use a typed Dart model, TOML file storage, and a shared controller. See [configuration architecture and supported settings](docs/app-preferences.md) and [the example configuration](config/config.example.toml).

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
settings controller and Rust backend.

Keyboard shortcuts: Ctrl+F or Ctrl+E focuses search, Escape clears search, and Alt+Left navigates back. The sidebar stays visible; the native window minimum width is 1,000 logical pixels. Themes → Material Design controls the app palette and system Light/Dark mode. Environment defaults affect new fish processes and the next Hyprland session; see the configuration document for supported targets and override limits.

Licensed under [PolyForm Noncommercial License 1.0.0](LICENSE), matching `image_resizer`.
