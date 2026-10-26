# Agent Instructions & Development Guidelines

## Project Scope
- `remya_settings` is an independent Linux desktop project using Flutter and Rust.
- Reuse development practices from `image_resizer`, not its features, configuration, window geometry, assets, application identifiers, or license.
- Write rule documents, including `AGENTS.md`, in English.

## Architecture: Monorepo + Feature-first + Rust Workspace
- Keep Flutter at the repository root and manage Rust crates through the root `Cargo.toml` workspace.
- Organize Flutter code under `lib/features/<feature>/`, keeping each feature's UI, state, and data access together. Add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`.
- Put Rust crates under `lib/src/rust/<crate>/`. Group backend functionality by feature; create crates only for concrete responsibility or dependency boundaries.
- `lib/src/rust/core/` is the initial empty backend crate. Do not turn it into a catch-all for unrelated features.
- Extract shared code only when multiple features need it; avoid speculative layers and empty feature scaffolding.
- Implement backend logic and complex or performance-critical computation in Rust. Connect Flutter through `flutter_rust_bridge` when the first backend API is needed; the initial scaffold has no bridge.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually.

## Toolchains & Dependencies
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.8`. Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` and inherit common crate metadata from the workspace.
- Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
- Reuse existing helpers and dependencies. Add packages only for concrete requirements.
- Check dependency license compatibility and preserve third-party notices. No distribution license is selected; do not inherit another project's license.

## Coding & UI
- Use dot shorthand wherever supported and the expected type is unambiguous. Keep explicit types when shorthand cannot resolve correctly.
- Split complex components into smaller objects with clear responsibilities. Keep small, non-reusable components private in the same file and composition shallow.
- All UI must follow Material Design 3 Expressive (MD3E).
- Import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`.
- Enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Preserve keyboard navigation, visible focus, readable contrast, and scrolling at supported window sizes.
- Target Linux only; do not generate other platforms without explicit instruction.
- Let the native runner own initial window setup and respect Wayland compositor policy. Never automatically modify user desktop configuration.

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
