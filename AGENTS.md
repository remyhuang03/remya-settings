# Agent Instructions & Development Guidelines

## Project Scope
- `remya_settings` is a global system settings application for Hyprland on Linux, using Flutter and Rust.
- Follow Windows 11 Settings for information architecture and layout (persistent category navigation, search, Home cards, grouped settings, and nested pages), while using Material Design 3 Expressive rather than Fluent styling.
- Host settings remain UI-only previews except explicitly implemented, verified integrations. System Light/Dark appearance is authorized for installed GNOME/GTK targets and documented Qt Quick defaults and must be implemented in Rust through flutter_rust_bridge. App-owned Material palette preferences may use this application's TOML configuration. Do not activate unrelated previews or modify unrelated desktop settings. The Repository action may open its fixed URL with the desktop opener.
- Maintain the settings catalog and its schema alongside the UI. Preserve source references and document coverage gaps; Microsoft's public page catalog is not a complete internal control schema.
- Keep `docs/settings-implementation-progress.md` synchronized with every added, removed, or implemented catalog item. Record verification evidence before marking a system feature implemented. During development, IDs may change freely without aliases; keep them consistent and update every reference. Remove deleted pages and controls from the repository entirely, including documents and coverage records.
- Every setting must declare availability and a reason: `planned` (not implemented), `unsupported` (Windows-specific, legacy, or inapplicable), or `available` (a working, verified integration). Show text and an icon for unavailable states, not color alone; keep unavailable controls disabled while allowing navigation to their previews. Do not show status badges for available items.
- Automatically hide a setting that cannot be used in the current state, such as a video-only option while an image is active or a dependent option while its parent is off, instead of showing it disabled. Keep a readout when it still informs. Temporary states (busy, conflict, read-only file) stay visible and disabled so their explanation has context. This does not change how `planned` and `unsupported` catalog previews are shown.
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
- Implement backend logic and complex or performance-critical computation in Rust. The appearance feature is connected through `flutter_rust_bridge` 2.13.0. Keep system appearance code in `lib/src/rust/appearance/`, Hyprland display code in `lib/src/rust/display/` and NetworkManager code in `lib/src/rust/network/`; do not move them into Dart or the empty core crate.
- Keep generated bridge code separate from handwritten code and regenerate it instead of editing it manually. Use `flutter_rust_bridge.yaml`, the matching 2.13.0 generator, and FVM formatting after generation. Linux CMake builds and bundles the Rust shared library.

## Public Interfaces and Dependent Applications
- The ordinary-user Rust service owns production configuration, reconciliation, and CLI/D-Bus dispatch. Flutter is a disposable GUI client; closing its window must terminate its process and release the engine.
- System writes requiring elevation run in a separately authorized Rust process over private bounded pipes. Authorize once on the first explicit GUI launch; reuse it while Settings stays resident. Do not expose arbitrary commands, configurable privileged paths, or a public privileged socket. Read-only Bar activation must not prompt for authorization.

- The application/desktop ID is `top.remya.settings`; the executable is `remya_settings`. Remya Bar (`top.remya.bar`) is a separate dependent application.
- Provide complete operation parity through the CLI and versioned session D-Bus API for every implemented feature. Expose unavailable catalog entries for inspection but reject attempts to execute them; never simulate success.
- Route GUI, CLI, and D-Bus operations through the owning feature controller/backend. Extend `lib/src/rust/service`, the client contract and `api/settings1.xml`, documentation, and parity tests when adding available operations; do not duplicate persistence or system-write logic in interfaces.
- Debug dependent applications may pass the Settings debug executable to the public opener; keep release launch on the D-Bus interface and document missing-build guidance.
- `packages/remya_settings_client` is the public integration boundary for dependent apps. Keep its pure Dart contract usable without Flutter and its theme adapter free of Settings UI or backend dependencies. Preserve the versioned wire contract; use a new interface version for incompatible changes to its methods or payload shapes.
- Keep debug application preferences in repository config/config.local.toml regardless of launch cwd. Profile/release preferences use XDG_CONFIG_HOME/remya/settings/config.toml with the standard HOME fallback. Keep installation bundles and desktop/service metadata under XDG_DATA_HOME and commands under HOME/.local/bin. Ignore relative XDG values.
- Support Hyprland's Lua configuration only for display persistence: write only `hl.monitor` rules in `$XDG_CONFIG_HOME/hypr/monitors.lua`, and refuse to edit a file with content the strict reader cannot prove safe. Risky display changes need the service-owned keep-or-revert countdown, and persist only after confirmation.
- Do not automatically migrate or remove prior installations or user configuration. Use `tool/install.py`; refuse to overwrite unrelated commands or update a running installed bundle.
- Keep `docs/public-api.md` and `docs/xdg-layout.md` synchronized with implementation. Use isolated XDG roots and GSettings state for system-write verification.

## System Configuration Reconciliation
- Apply this rule to every implemented system-backed setting, including future integrations; app-only preferences and unavailable previews have no system counterpart and must not be synchronized.
- On first use, read and validate the actual system configuration and atomically save it as the initial Settings configuration. Never apply defaults to the system at first launch. If detection fails, report the error and leave configuration uninitialized.
- On application startup and when opening a settings page, compare saved Settings values with fresh system readback. Preserve both values on conflict and show a warning at the top with explicit choices: adopt the system configuration into Settings, or apply the saved Settings configuration to the system.
- Route both choices through the owning feature controller, retain validation and platform authorization, and verify system readback after writes. Failed detection, authorization, persistence, or application must remain visible and must not silently resolve a conflict or overwrite the last valid configuration.
- Compare stable preferences, not naturally changing measurements: never persist the current wall clock as a time to restore at startup. The Wi-Fi radio state and the set of NetworkManager profiles are not compared: Bar, hotkeys and other tools change the radio routinely, and Settings cannot recreate a deleted profile without its secrets, so additions and removals are adopted automatically. Keep GUI, CLI, and D-Bus behavior consistent and cover initialization, conflicts, both resolutions, and failure retention with tests.

## Toolchains & Dependencies
- Assume fish is the user's default shell. Persist appearance-related environment variables only through fish and Hyprland configuration; do not modify Bash, Zsh, POSIX profile files, /etc/environment, or systemd environment configuration. Use documented Light/Dark settings or official environment variables only; skip software without an explicit setting instead of forcing platform plugins or guessing theme replacements.
- NetworkManager is a required dependency of the network settings; do not add other network backends or fallbacks.
- Target Arch Linux with current, regularly updated packages. Support modern upstream dependency versions only; do not add compatibility layers, deprecated fallbacks, or version branches for older system libraries or services. Document required minimum versions when an API has a concrete floor. GTK 3 remains a distinct installed toolkit target; use the current GTK 4 API rather than obsolete GTK 4 fallbacks.
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.8`. Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` and inherit common crate metadata from the workspace.
- Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
- Reuse existing helpers and dependencies. Add packages only for concrete requirements.
- This project uses the PolyForm Noncommercial License 1.0.0 (`LICENSE`), matching `image_resizer` by explicit owner instruction.
- Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (MIT, BSD, Apache-2.0, ISC, Zlib, Unlicense). LGPL libraries must remain dynamically linked or separate processes; do not introduce GPL, AGPL, SSPL, or other incompatible strong-copyleft code.

## Coding & UI
- Format user-visible calendar dates according to the current system LC_TIME, inheriting LANG when LC_TIME is unset. Keep persisted dates locale-independent.
- Do not use the middle dot character (U+00B7) to separate text information. Present distinct facts as labeled fields or separate lines.
- Put a page's advanced options in a default-collapsed `Advanced` section of that same page, not in a separate second-level page or menu. Do not keep a folded-in page's old ID.
- Apply setting changes immediately when the setting supports immediate application and doing so is appropriate; do not add an unnecessary Apply button.
- For settings that require a system restart, show a global "Reboot to apply" status bar with Restart now and Later actions, and a local explanation beside the setting. State application restart or sign-in requirements accurately when a full reboot is unnecessary.
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

- After every application code change, finish validation and rebuild the release bundle, then run `python tool/install.py` on this workstation as the final implementation step so the user can manually review the installed application. Source changes and successful builds alone do not complete the task.
- Verify that the installed bundle, command, and desktop entry use the updated build, and exercise the installed application. Preserve user configuration and unrelated installations. When both Settings and Bar change, install Settings first and Bar second; retain the required cleanup of verification instances.

## Git Workflow
- Develop and validate on a separate branch using `<type>/<short-description>` with lowercase words and hyphens, such as `feat/appearance` or `chore/initialize-project`.
- Use stacked commits when appropriate. Keep each commit small, focused, and independently reviewable, with dependent changes ordered in the stack.
- Follow Conventional Commits: `<type>(<scope>): <description>`. Use a lowercase imperative description without a final period; mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`.
- Inspect diffs, stage only intended paths, and preserve unrelated changes.
- Commit approval is mandatory: show completed changes and validation results before requesting explicit user review approval to run `git commit`.
- Do not push or merge without user authorization. Verify remote refs after authorized delivery.
