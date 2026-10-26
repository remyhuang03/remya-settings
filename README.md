# Remy'a Settings

A global system settings application for **Hyprland on Linux**, using **Flutter**, **Material Design 3 Expressive**, and a **Rust workspace**. Layout and information architecture reference Windows 11 Settings.

## Current milestone: UI only

Browse Home, 13 categories, 308 detail pages, and About; search settings, follow related pages, and inspect third-party licenses. The catalog contains 2,180 preview controls, with every operation explicitly **not implemented** or **not applicable** and disabled. Devices, account information, values, and capacities are examples, never detected host state. No system configuration is read or changed, no services are called, and no preview values are persisted.

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
    settings/             Catalog model, navigation, search, page renderer
    about/                Product information and licenses
  src/rust/core/          Empty future backend crate
assets/
  icons/                  Owner-provided SVG and rendered PNG
  settings/               UI catalog and JSON Schema
linux/                    Native runner and packaging templates
docs/                     Research and coverage snapshot
test/                     Catalog, interaction, and layout checks
```

Flutter stays at the repository root. Rust crates live under `lib/src/rust/` and are registered in the root workspace. Backend APIs and `flutter_rust_bridge` will be added when real functionality is implemented.

## Development

Install FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, and GTK 3 development libraries). From the repository root:

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

Keyboard shortcuts: Ctrl+F or Ctrl+E focuses search, Escape clears search, and Alt+Left navigates back. Navigation collapses into a drawer below 1,000 logical pixels.

Licensed under [PolyForm Noncommercial License 1.0.0](LICENSE), matching `image_resizer`.
