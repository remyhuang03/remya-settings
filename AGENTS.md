# Agent Instructions & Development Guidelines

## Project Scope
- `remya_settings` is the global system settings GUI for Hyprland on Linux, using Flutter. It is a client of the shared Remya backend in [remya-core](https://github.com/remyhuang03/remya-core) (`remyad`, D-Bus `top.remya.Core1`, CLI `remya`), which owns every system integration, the settings catalog, configuration, reconciliation, privileged writes and CLI/D-Bus parity. Read remya-core's `AGENTS.md`, `docs/public-api.md` and `docs/xdg-layout.md` before changing behaviour that crosses that boundary, and change the backend in remya-core, never here.
- Draw design inspiration from Windows 11 Settings for information architecture and layout (persistent category navigation, search, Home cards, grouped settings, and nested pages), while adapting to Linux and Hyprland workflows and using Material Design 3 Expressive rather than Fluent styling.
- Settings shows system and shared Remya settings. Preferences owned by other Remya applications (Bar, Launcher, Screen Capture, …) are edited in those applications' own settings windows; Settings only lists installed applications from their registrations in the "Remya apps" category and opens them through `OpenApp`. Never re-implement another application's preference pages here.
- Render availability exactly as remyad reports it: show text and an icon for unavailable states, not color alone; keep unavailable controls disabled while allowing navigation to their previews; no status badges for available items. Never present sample values as detected device state.
- Automatically hide a setting that cannot be used in the current state, such as a video-only option while an image is active or a dependent option while its parent is off, instead of showing it disabled. Keep a readout when it still informs. Temporary states (busy, conflict, read-only file) stay visible and disabled so their explanation has context.
- Call `Manage(feature)` when a system feature page opens; show conflicts reported by remyad at the top of the page with the explicit adopt-system and apply-saved choices, and keep failures visible.
- The Repository action may open its fixed URL with the desktop opener.
- Reuse development practices from `image_resizer`, not its features, configuration, window geometry, assets, or application identifiers.
- Write rule documents, including `AGENTS.md`, in English.

## Architecture
- Keep Flutter at the repository root. Organize code under `lib/features/<feature>/`, keeping each feature's UI, state and data access together; add internal layers only when needed.
- Keep application composition in `lib/app.dart` and startup in `lib/main.dart`. Talk to remyad only through `remya_client` (pure Dart) and use `remya_ui` for the shared Remya theme; both come from remya-core. Do not parse remyad's configuration files.
- The only in-process Rust is the camera preview wrapper under `lib/src/rust/`, connected through `flutter_rust_bridge` 2.13.0. Keep generated bridge code separate and regenerate it with the matching generator and FVM formatting instead of editing it. Linux CMake builds and bundles that library.
- The application/desktop ID is `top.remya.settings`; the executable is `remya_settings`. Closing the window must terminate the process and release the engine.
- Keep debug application preferences that belong to the GUI itself in repository `config/` regardless of launch cwd; release GUI preferences use `XDG_CONFIG_HOME/remya/settings/`. Install the bundle and desktop metadata under XDG_DATA_HOME and the command under HOME/.local/bin. Ignore relative XDG values.
- Remove obsolete client interfaces directly when remya-core changes; do not keep aliases, migration code or compatibility branches.
- Use `tool/install.py`; it requires an installed remya-core and refuses to overwrite unrelated commands or update a running installed bundle.

## Toolchains & Dependencies
- Always invoke Flutter and Dart as `fvm flutter ...` and `fvm dart ...`, never through global SDK commands.
- `.fvmrc` pins Flutter to `3.47.8`. Do not change versions without explicit instruction. Run `fvm install` for fresh setup.
- Use the root `rust-toolchain.toml` for the preview wrapper. Commit `.fvmrc`, `pubspec.lock`, and `Cargo.lock`; ignore SDK caches, build output, and local configuration.
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

### Icons
- Use `Icon` and named `Icons` constants from `package:material_ui/material_ui.dart`, for example `const Icon(Icons.airplanemode_active_rounded)`. Do not use raw code points.
- Choose the icon for its meaning and keep its rounded/outlined style consistent with nearby controls. Use existing icons instead of custom drawings, image assets, or new dependencies for standard symbols.
- Register catalog page icons in `pageIcon` in `lib/features/settings/presentation/settings_widgets.dart`; do not leave a specific page using its category's generic fallback.
- Give icon-only actions a tooltip or semantic label; retain visible text where the UI already provides it.
- Before rebuilding a release after icon changes, invalidate only the generated `.dart_tool/flutter_build/*/release_bundle_linux-x64_assets.stamp` files so the bundled icon-font subset includes the new glyphs.
- Inspect the installed release on the desktop to confirm the intended glyph renders. Passing analysis, widget tests, or a release build alone does not verify icon appearance.

## Validation
- Run `fvm flutter pub get` after dependency changes. Use `fvm flutter run -d linux` for interactive verification and release builds when release behavior changes.
- Keep durable tests only for non-trivial logic and regressions. Check trivial content (static text, catalog wording, one-off UI inspection) with temporary test files and delete them once they pass; avoid duplicate coverage.
- A successful build does not verify desktop behavior. Check affected window behavior and interactions on the real desktop; report untested boundaries.
- Validate configuration input, preserve the last valid state on errors, and use atomic persistence when writing configuration is introduced. Never commit secrets or machine-specific configuration.

- After every application code change, finish validation and rebuild the release bundle, then run `python tool/install.py` (after installing remya-core when it changed) on this workstation as the final implementation step so the user can manually review the installed application. Source changes and successful builds alone do not complete the task.
- Verify that the installed bundle, command, and desktop entry use the updated build, and exercise the installed application. Preserve user configuration and unrelated installations. Install remya-core before Settings and other Remya applications; retain the required cleanup of verification instances.

## Releases
- Use the user-level `remya-release` skill from [remya-apps-skills](https://github.com/remyhuang03/remya-apps-skills) for Linux release work. Install it with `npx skills add remyhuang03/remya-apps-skills --skill remya-release --agent codex --global`, then invoke `$remya-release` from this checkout.

## Git Workflow
- Develop and validate on a separate branch using `<type>/<short-description>` with lowercase words and hyphens, such as `feat/appearance` or `chore/initialize-project`.
- Use stacked commits when appropriate. Keep each commit small, focused, and independently reviewable, with dependent changes ordered in the stack.
- Follow Conventional Commits: `<type>(<scope>): <description>`. Use a lowercase imperative description without a final period; mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`.
- Inspect diffs, stage only intended paths, and preserve unrelated changes.
- Commit approval is mandatory: show completed changes and validation results before requesting explicit user review approval to run `git commit`.
- Approval to commit also authorizes the branch follow-up: merge each branch that is ready into `main`, delete local branches (and their worktrees) that are fully merged, and push `main` to `origin`. Do not push or merge without such approval. Verify remote refs after delivery.
