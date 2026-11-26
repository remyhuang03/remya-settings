# Agent Instructions & Development Guidelines

## Project Scope
- `remya_settings` is the global system settings GUI for Hyprland on Linux, using Flutter. It is a client of the shared Remya backend in [remya-core](https://github.com/remyhuang03/remya-core) (`remyad`, D-Bus `top.remya.Core1`, CLI `remya`), which owns every system integration, the settings catalog, configuration, reconciliation, privileged writes and CLI/D-Bus parity. Read remya-core's `AGENTS.md`, `docs/public-api.md` and `docs/xdg-layout.md` before changing behaviour that crosses that boundary, and change the backend in remya-core, never here.
- Draw design inspiration from Windows 11 Settings for information architecture and layout (persistent category navigation, search, Home cards, grouped settings, and nested pages), while adapting to Linux and Hyprland workflows and using Material Design 3 Expressive rather than Fluent styling.
- Settings shows system and shared Remya settings. Preferences owned by other Remya applications (Bar, Launcher, Screen Capture, …) are edited in those applications' own settings windows; Settings only lists installed applications from their registrations in the "Remya apps" category and opens them through `OpenApp`. Never re-implement another application's preference pages here.
- Render availability exactly as remyad reports it: show text and an icon for unavailable states, not color alone; keep unavailable controls disabled while allowing navigation to their previews; no status badges for available items.
- Automatically hide a setting that cannot be used in the current state, such as a video-only option while an image is active or a dependent option while its parent is off, instead of showing it disabled. Keep a readout when it still informs. Temporary states (busy, conflict, read-only file) stay visible and disabled so their explanation has context.
- Call `Manage(feature)` when a system feature page opens; show conflicts reported by remyad at the top of the page with the explicit adopt-system and apply-saved choices, and keep failures visible.
- The Repository action may open its fixed URL with the desktop opener.
- Reuse development practices from `image_resizer`, not its features, configuration, window geometry, assets, or application identifiers.

## Architecture
- Keep Flutter at the repository root. Organize code under `lib/features/<feature>/`, keeping each feature's UI, state and data access together; add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`. Talk to remyad only through `remya_client` (pure Dart) and use `remya_ui` for the shared Remya theme; both come from remya-core. Do not parse remyad's configuration files.
- The only in-process Rust is the camera preview wrapper under `lib/src/rust/`, connected through `flutter_rust_bridge` 2.13.0. Keep generated bridge code separate and regenerate it with the matching generator and FVM formatting instead of editing it. Linux CMake builds and bundles that library.
- The application/desktop ID is `top.remya.settings`; the executable is `remya_settings`. Closing the window must terminate the process and release the engine.
- Keep debug application preferences that belong to the GUI itself in repository `config/` regardless of launch cwd; release GUI preferences use `XDG_CONFIG_HOME/remya/settings/`. Install the bundle and desktop metadata under XDG_DATA_HOME and the command under HOME/.local/bin.
- Remove obsolete client interfaces directly when remya-core changes; do not keep aliases, migration code or compatibility branches.
- Use `tool/install.py`; it requires an installed remya-core and refuses to overwrite unrelated commands or update a running installed bundle.

## Coding & UI
- Format user-visible calendar dates according to the current system LC_TIME, inheriting LANG when LC_TIME is unset. Keep persisted dates locale-independent.
- Do not use the middle dot character (U+00B7) to separate text information. Present distinct facts as labeled fields or separate lines.
- Put a page's advanced options in a default-collapsed `Advanced` section of that same page, not in a separate second-level page or menu. Do not keep a folded-in page's old ID.
- Apply setting changes immediately when the setting supports immediate application and doing so is appropriate; do not add an unnecessary Apply button.
- For settings that require a system restart, show a global "Reboot to apply" status bar with Restart now and Later actions, and a local explanation beside the setting. State application restart or sign-in requirements accurately when a full reboot is unnecessary.
- Let the native runner own initial window setup and respect Wayland compositor policy. Change desktop configuration only through explicitly selected, implemented system settings; never alter unrelated compositor policy or window rules.

### Icons
- Use `Icon` and named `Icons` constants from `package:material_ui/material_ui.dart`, for example `const Icon(Icons.airplanemode_active_rounded)`. Do not use raw code points.
- Choose the icon for its meaning and keep its rounded/outlined style consistent with nearby controls. Use existing icons instead of custom drawings, image assets, or new dependencies for standard symbols.
- Register catalog page icons in `pageIcon` in `lib/features/settings/presentation/settings_widgets.dart`; do not leave a specific page using its category's generic fallback.
- Give icon-only actions a tooltip or semantic label; retain visible text where the UI already provides it.
- Before rebuilding a release after icon changes, invalidate only the generated `.dart_tool/flutter_build/*/release_bundle_linux-x64_assets.stamp` files so the bundled icon-font subset includes the new glyphs.
- Inspect the installed release on the desktop to confirm the intended glyph renders. Passing analysis, widget tests, or a release build alone does not verify icon appearance.

## Validation
- Use `fvm flutter run -d linux` for interactive verification and release builds when release behavior changes.

<!-- BEGIN:remya-shared profiles=base,source-length,rust,flutter-app,workstation-install,release-skill -->
<!-- Generated from remya-apps-skills/rules/. Do not edit manually; run remya-apps-skills/rules/sync.py. -->

## Shared Remya Guidelines

- Write rule documents, including `AGENTS.md`, in English.
- Respect XDG base directories (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`); ignore relative XDG values and use absolute `$HOME` fallbacks; do not create unused cache/state directories. Never automatically modify user Hyprland or desktop configuration.
- License & dependencies: PolyForm Noncommercial License 1.0.0 (`LICENSE`). Check dependency license compatibility before adding code or libraries and preserve third-party notices. Prefer permissive licenses (`MIT`, `BSD`, `Apache-2.0`, `ISC`, `Zlib`, `Unlicense`). Keep `LGPL` libraries dynamically linked or in separate processes; never introduce `GPL`, `AGPL`, `SSPL`, or incompatible strong-copyleft code. Reuse existing helpers/packages.
- Validation hygiene: Keep durable tests for non-trivial logic and regressions; remove obsolete, duplicate, or temporary UI-inspection tests before committing. Validate configuration input, preserve the last valid state on errors, and use atomic persistence.
- Git workflow: Develop and validate on a separate branch `<type>/<short-description>` (lowercase words and hyphens). Use small, focused stacked commits when appropriate. Follow Conventional Commits: `<type>(<scope>): <description>` (lowercase imperative description without a final period; mark breaking changes with `!` or `BREAKING CHANGE:`). Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Inspect diffs, stage only intended paths, and preserve unrelated changes. Commit approval is mandatory: show completed changes and validation results before requesting explicit user approval to run `git commit`. Approval to commit also authorizes merging ready branches into `main`, deleting fully merged local branches (and clean worktrees), pushing `main` to `origin`, and verifying remote refs.

### Source Length Check

- Run `python tool/check_source_length.py` as part of local validation (warns for Rust and Dart files over 800 physical lines, including comments and blank lines). Review every reported file against the single-responsibility principle and refactor files that mix responsibilities.
- When a reviewed file should stay together, run `python tool/check_source_length.py add <path> --reason "<why it should stay together>"` and include the updated `tool/source_length_exceptions.json` (keyed by SHA-256; modified files still over 800 lines require another review).

### Rust Toolchain & Validation

- Use the root `rust-toolchain.toml` (do not change toolchain channels without explicit instruction) and inherit common crate metadata from the workspace where applicable. Commit `Cargo.lock`; ignore build output.
- Run before presenting changes: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`.

### Flutter Linux App Guidelines

- Always invoke Flutter and Dart via `fvm flutter ...` and `fvm dart ...`, never global SDK commands.
- Target Linux only.
- All UI must follow Material Design 3 Expressive (MD3E): import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`; enable Material 3 and Expressive color schemes; follow the design system for spacing, shape, typography, and motion.
- Use dot shorthand wherever supported and the expected type is unambiguous. Split complex widgets by responsibility and keep small single-use widgets private.
- Run `fvm flutter pub get` after dependency changes. Run `fvm dart format --output=none --set-exit-if-changed lib test`, `fvm flutter analyze`, `fvm flutter test`, and `fvm flutter build linux --debug` as relevant. Keep debug and release builds sequential because Flutter shares ephemeral native engine files between modes.
- A successful build does not verify desktop behavior; verify affected window behavior and interactions on the real desktop and report untested boundaries.

### Workstation Release Install

- After application or daemon code changes, finish validation, rebuild the release bundle/binaries, and run `python tool/install.py` on this workstation as the final implementation step so the user can manually review the installed application. Source changes and successful builds alone do not complete the task.
- Verify that the installed bundle, command, desktop entry, and any service unit use the updated build, and exercise the installed application. Preserve user configuration and unrelated installations. Install `remya-core` before dependent apps (and Settings before Bar when both change). Stop verification instances you started without disabling persistent user units.

### Releases

- Use the user-level `remya-release` skill from [remya-apps-skills](https://github.com/remyhuang03/remya-apps-skills) for Linux release work (install via `npx skills add remyhuang03/remya-apps-skills --skill remya-release --agent codex --global`, then invoke `$remya-release`). Release `remya-core` first at every stage.
<!-- END:remya-shared -->
