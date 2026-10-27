# Agent Instructions & Development Guidelines

## Project Scope
- `remya_settings` is a global system settings application for Hyprland on Linux, using Flutter and Rust.
- Follow Windows 11 Settings for information architecture and layout (persistent category navigation, search, Home cards, grouped settings, and nested pages), while using Material Design 3 Expressive rather than Fluent styling.
- Host settings remain UI-only previews except explicitly implemented, verified integrations. System Light/Dark appearance is authorized for installed GNOME/GTK targets and documented Qt Quick defaults and must be implemented in Rust through flutter_rust_bridge. App-owned Material palette preferences may use this application's TOML configuration. Do not activate unrelated previews or modify unrelated desktop settings. The Repository action may open its fixed URL with the desktop opener.
- Maintain the settings catalog and its schema alongside the UI. Preserve source references and document coverage gaps; Microsoft's public page catalog is not a complete internal control schema.
- Keep `docs/settings-implementation-progress.md` synchronized with every added, removed, or implemented catalog item. Preserve stable IDs and existing tracking notes; record verification evidence before marking a system feature implemented.
- Every setting must declare availability and a reason: `planned` (not implemented), `unsupported` (Windows-specific, legacy, or inapplicable), or `available` (a working, verified integration). Show text and an icon for unavailable states, not color alone; keep unavailable controls disabled while allowing navigation to their previews. Do not show status badges for available items.
- Never present sample values as detected device state, or mark an item available merely because its page renders. Enable controls only after a real integration and its tests exist.
- Reuse development practices from `image_resizer`, not its features, configuration, window geometry, assets, or application identifiers.
- Write rule documents, including `AGENTS.md`, in English.

## Architecture: Monorepo + Feature-first + Rust Workspace
- Keep Flutter at the repository root and manage Rust crates through the root `Cargo.toml` workspace.
- Organize Flutter code under `lib/features/<feature>/`, keeping each feature's UI, state, and data access together. Add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`. App-owned appearance state, its typed configuration, and file storage belong to `lib/features/appearance/`; keep simple Flutter appearance preferences in Dart as in the reference app. Rust remains the boundary for system backends and complex computation.
- Put Rust crates under `lib/src/rust/<crate>/`. Group backend functionality by feature; create crates only for concrete responsibility or dependency boundaries.
- `lib/src/rust/core/` is the initial empty backend crate. Do not turn it into a catch-all for unrelated features.
- Extract shared code only when multiple features need it; avoid speculative layers and empty feature scaffolding.
- Implement backend logic and complex or performance-critical computation in Rust. The appearance feature is connected through `flutter_rust_bridge` 2.13.0. Keep system appearance code in `lib/src/rust/appearance/`; do not move it into Dart or the empty core crate.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually. Use `flutter_rust_bridge.yaml`, the matching 2.13.0 generator, and FVM formatting after generation. Linux CMake builds and bundles the Rust shared library.

## Toolchains & Dependencies
- Assume fish is the user's default shell. Persist appearance-related environment variables only through fish and Hyprland configuration; do not modify Bash, Zsh, POSIX profile files, /etc/environment, or systemd environment configuration. Use documented Light/Dark settings or official environment variables only; skip software without an explicit setting instead of forcing platform plugins or guessing theme replacements.
- Target Arch Linux with current, regularly updated packages. Support modern upstream dependency versions only; do not add compatibility layers, deprecated fallbacks, or version branches for older system libraries or services. Document required minimum versions when an API has a concrete floor. GTK 3 remains a distinct installed toolkit target; use the current GTK 4 API rather than obsolete GTK 4 fallbacks.
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.8`. Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` and inherit common crate metadata from the workspace.
- Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
- Reuse existing helpers and dependencies. Add packages only for concrete requirements.
- This project uses the PolyForm Noncommercial License 1.0.0 (`LICENSE`), matching `image_resizer` by explicit owner instruction.
- Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (MIT, BSD, Apache-2.0, ISC, Zlib, Unlicense). LGPL libraries must remain dynamically linked or separate processes; do not introduce GPL, AGPL, SSPL, or other incompatible strong-copyleft code.

## Coding & UI
- Use dot shorthand wherever supported and the expected type is unambiguous. Keep explicit types when shorthand cannot resolve correctly.
- Split complex components into smaller objects with clear responsibilities. Keep small, non-reusable components private in the same file and composition shallow.
- All UI must follow Material Design 3 Expressive (MD3E).
- Import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`.
- Enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Preserve keyboard navigation, visible focus, readable contrast, and scrolling at supported window sizes.
- Target Linux only; do not generate other platforms without explicit instruction.
- Let the native runner own initial window setup and respect Wayland compositor policy. Change desktop configuration only through explicitly selected, implemented system settings; never alter unrelated compositor policy or window rules.

## Validation
- Run relevant checks before presenting changes for review:
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
- Run `fvm flutter pub get` after dependency changes. Use `fvm flutter run -d linux` for interactive verification and release builds when release behavior changes.
- Keep durable tests for non-trivial logic and regressions; remove temporary UI inspection tests after verification and avoid duplicate coverage.
- A successful build does not verify desktop behavior. Check affected window behavior and interactions on the real desktop; report untested boundaries.
- Validate configuration input, preserve the last valid state on errors, and use atomic persistence when writing configuration is introduced. Never commit secrets or machine-specific configuration.

## Git Workflow
- Develop and validate on a separate branch using `<type>/<short-description>` with lowercase words and hyphens, such as `feat/appearance` or `chore/initialize-project`.
- Use stacked commits when appropriate to split multi-step, dependent changes into small, focused, reviewable commits.
- Follow Conventional Commits: `<type>(<scope>): <description>`. Use a lowercase imperative description without a final period; mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`.
- Inspect diffs, stage only intended paths, and preserve unrelated changes.
- Commit approval is mandatory: show completed changes and validation results before requesting explicit user review approval to run `git commit`.
- Do not push or merge without user authorization. Verify remote refs after authorized delivery.
