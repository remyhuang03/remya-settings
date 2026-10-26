# Remy'a Settings

An independent Linux desktop application scaffold using Flutter, Material Design 3 Expressive, and Rust.

## Layout

This monorepo uses feature-first organization and a root Cargo workspace:

```text
.fvmrc                    Flutter SDK pin
Cargo.toml                Rust workspace
lib/
  main.dart               Flutter startup
  app.dart                Application composition and theme
  features/<feature>/     Feature UI, state, and data access (add as needed)
  src/rust/
    core/                 Initial empty Rust backend crate
linux/                    Native Flutter runner
test/                     Flutter tests
```

Flutter stays at the repository root. Add feature crates under `lib/src/rust/` and register them in the root workspace when needed. The current app is an empty themed window; there are no settings features or Flutter/Rust bridge yet. Add `flutter_rust_bridge` alongside the first real backend API.

## Development

Install FVM, Rust via rustup, and Linux Flutter build prerequisites (Clang, CMake, Ninja, pkg-config, and GTK 3 development libraries). Run from the repository root:

```bash
fvm install
fvm flutter pub get
fvm flutter doctor
fvm flutter run -d linux
```

FVM pins Flutter to `3.47.8`; `rust-toolchain.toml` selects stable Rust with rustfmt and Clippy. Stable Rust follows installed toolchain updates. See `AGENTS.md` for development and validation rules.

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
fvm flutter build linux --debug
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

No distribution license has been selected.
