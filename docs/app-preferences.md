# Appearance configuration and backend

Colors and themes contains the system Light/Dark selector, the accent color, and the application palette selector. There is no Follow system option. Remy'a Settings immediately uses the selected mode, accent and Material palette. The accent is stored separately in `accent.toml`; see [public interfaces](public-api.md#accent-color).

Appearance → Remy'a Bar contains Show seconds, enabled by default. The Settings
service saves this app preference and publishes changes to running bars. See
[the clock preference API](public-api.md#remya-bar-appearance).

## Configuration ownership

| Data | Owner | Storage |
| --- | --- | --- |
| Material palette and last selected mode | Typed Dart preferences/controller | Application TOML below |
| GNOME/libadwaita color preference | Rust appearance crate, GIO | `org.gnome.desktop.interface` GSettings |
| Installed GTK toolkit preferences | Rust appearance crate | `$XDG_CONFIG_HOME/gtk-{3,4}.0/settings.ini` |
| Documented Qt Quick theme defaults | Rust appearance crate | Managed blocks in fish and Hyprland configuration |
| UI-only catalog controls | Catalog renderer | No persistence or host access |

The Rust feature crate is `lib/src/rust/appearance/`; the core crate stays empty. Its handwritten API is `src/api.rs`, system coordination is `src/system_theme.rs`, atomic file updates are `src/files.rs`, and toolkit environment configuration is `src/environment.rs`. `flutter_rust_bridge` 2.13.0 connects this feature to Flutter. Generated Dart bindings live in `lib/src/rust/appearance_bridge/`; regenerate with the matching generator and `flutter_rust_bridge.yaml`, never edit generated files. Linux CMake builds and bundles the Rust shared library. GIO/GLib remain dynamically linked system dependencies.

## Application TOML

| Build | File |
| --- | --- |
| Debug | `config/config.local.toml` below the native-reported repository root, independent of launch cwd |
| Profile/release | `$XDG_CONFIG_HOME/remya/settings/config.toml` |
| Profile/release fallback | `$HOME/.config/remya/settings/config.toml` when XDG_CONFIG_HOME is missing or relative |

An absolute HOME or XDG_CONFIG_HOME is required. Debug mode isolates only the application's TOML: explicitly selecting Light/Dark still changes real desktop appearance. Tests inject an isolated backend or configuration root.

```toml
version = 1

[theme]
style_variant = "tonal_spot"
theme_mode = "light"
```

- `style_variant`: `tonal_spot`, `fidelity`, `monochrome`, `neutral`, `vibrant`, `expressive`, `content`, `rainbow`, or `fruit_salad`. These change the Material color scheme; widgets retain Material Design 3 Expressive styling.
- `theme_mode`: last selected `light` or `dark`. First launch reads the current GNOME/GTK preference and atomically saves it. Startup and Reload subsequently compare saved and actual values without overwriting either side; a top warning offers adoption or application. Editing TOML never changes the desktop. A previous preview file containing `system` is accepted as migration input and saved as an explicit mode on the next successful edit.
- Missing fields use Tonal spot/Light defaults. Existing explicit style selections are retained. Missing files do not trigger a write. Empty files, malformed TOML, unsupported versions, unknown keys, wrong types, and unknown enum values are rejected.
- `seed_color` is not part of this file, and no automatic startup writes are included. The public service observes external configuration changes every 500 ms and reloads through the same controller. Invalid files retain the last valid live theme and produce an API/UI error. Removing a file and reloading retains the last valid live state.

`lib/features/appearance/` keeps the immutable model, file store, serialized controller, and Rust adapter together. `main.dart` initializes the bridge and reads state before startup. `app.dart` owns the controller, distributes it through an inherited notifier, and rebuilds both Material themes. Busy controls are disabled; failures appear in an English error banner with Reload. Navigation is retained across theme changes.

## Supported system targets

| Target | Explicit interface | Behavior |
| --- | --- | --- |
| GNOME / libadwaita | `org.gnome.desktop.interface color-scheme` | `prefer-light` / `prefer-dark`, only when the schema/key exists |
| GTK 3 | `[Settings] gtk-application-prefer-dark-theme` | `0` / `1`; GTK 3 is also the native runner's toolkit |
| GTK 4.20+ | `[Settings] gtk-interface-color-scheme` | `light` / `dark`; removes the obsolete GTK 4 prefer-dark key |
| Existing GTK theme | GNOME `gtk-theme` and existing `gtk-theme-name` | Switch only matching installed light/dark variants; retain themes without a matching variant |
| Qt Quick Material | `QT_QUICK_CONTROLS_MATERIAL_THEME` | `Light` / `Dark`, only when the Qt 6 style module is installed |
| Qt Quick Universal | `QT_QUICK_CONTROLS_UNIVERSAL_THEME` | `Light` / `Dark`, only when the Qt 6 style module is installed |

Target current Arch Linux packages. No deprecated GTK 4 fallback or old Hyprland syntax is implemented. Toolkit and schema detection do not install packages. The settings page offers Light and Dark icon buttons with selection states, tooltips, and keyboard focus. Selecting either mode applies supported toolkit settings automatically through Rust. Backend target results remain internal; the page does not show toolkit/environment diagnostics or a routine reload button. Failures still appear in the error banner with Reload.

Qt defaults apply only to applications using those styles; explicit QML properties take precedence. The backend does not set `QT_QUICK_CONTROLS_STYLE`, `QT_QPA_PLATFORMTHEME`, `QT_STYLE_OVERRIDE`, or `GTK_THEME`, replace a palette file, or guess Kvantum/qt6ct/KDE theme names. Qt Widgets and other applications can consume the system preference through their existing platform integration. The desktop portal appearance interface is read-only: availability and propagation depend on the installed portal backend, so the app does not claim universal application coverage.

Sources: [Qt supported environment variables](https://doc.qt.io/qt-6/qtquickcontrols-environment.html), [GTK 3 preference](https://docs.gtk.org/gtk3/property.Settings.gtk-application-prefer-dark-theme.html), [GTK 4 interface preference](https://docs.gtk.org/gtk4/property.Settings.gtk-interface-color-scheme.html), [portal Settings](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html), and [Qt color-scheme platform behavior](https://doc.qt.io/qt-6/qstylehints.html#colorScheme-prop).

## fish and Hyprland environments

The default shell is fish. The Rust backend maintains clearly delimited `Remy'a Settings appearance` blocks at the end of `$XDG_CONFIG_HOME/fish/config.fish` and the active Hyprland Lua entrypoint (`$HYPRLAND_CONFIG`, otherwise `$XDG_CONFIG_HOME/hypr/hyprland.lua`). The fish block uses `set -gx`; the Lua block uses `hl.env`. Existing content outside these blocks is retained byte for byte. Future edits replace the same block instead of adding duplicates. Incomplete or duplicate markers abort the operation.

fish must be installed; its configuration may be created. Hyprland's entrypoint must already exist and `luac` must be available for syntax validation, otherwise that target is reported as skipped. The complete proposed configuration is syntax-checked without executing it (`fish --no-config --no-execute`, `luac -p -`) before any system changes. No Bash/Zsh profiles, `/etc/environment`, systemd environment files, or universal fish variables are modified.

Environment changes affect newly started fish processes and the next Hyprland session. Existing processes keep their inherited environment; the app does not restart the compositor, shell, or other applications. Application launch wrappers and explicit application overrides may still take precedence.

Sources: [fish configuration](https://fishshell.com/docs/current/language.html#configuration-files) and [Hyprland environment variables](https://wiki.hypr.land/configuring/core/environment-variables/).

## Validation, persistence, and failures

- App TOML writes use a flushed sibling temporary file followed by rename. Existing symlinks and permission bits are retained; new files use `0600`. Invalid existing data is never silently overwritten. Successful saves normalize TOML and do not preserve comments.
- Rust acquires a per-user appearance lock, then preflights all target files and GSettings writability/ranges before changing any appearance setting. Files use flushed atomic replacement and independent readback; comments, line endings, unrelated keys, symlinks, and permissions are preserved. Changed file baselines abort rather than overwrite an external edit.
- GSettings changes are batched and synchronized, then verified through an independent `gsettings get` process. A failure restores prior user values and exact previous file bytes; concurrent external changes are retained and incomplete rollback is reported. Multiple targets cannot form one filesystem transaction; process termination or power loss can interrupt the sequence.
- The controller saves the app record before applying system changes and restores the previous record if the backend fails. Successful backend state drives the application theme. Reload reflects partial external state after an error where possible.
- Application TOML saves serialize within one app instance; do not edit the same TOML concurrently from multiple instances. Rust system updates have a cross-process lock. No machine-specific configuration or secrets are committed.

Durable tests cover strict TOML, atomic persistence, controller ordering/error recovery, actual control bindings, retained navigation, installed theme matching, GSettings/file rollback, managed environment blocks, syntax validation, and missing optional targets. Native verification uses the real bridge and independent GTK/Qt probes, with exact restoration of personal files after temporary Light/Dark checks. Current verification evidence is recorded in [the implementation tracker](settings-implementation-progress.md).

The appearance, accent, background, fonts, date/time, and Display controls are available (see public-api.md). The remaining catalog controls remain disabled previews. The single-level sidebar is persistent, becomes icon-only below 1000 logical pixels, and uses wrapping connected page buttons with leading icons under the category title. The native minimum width is 360 logical pixels.

## Dependent applications and public operations

The common configuration decoder, XDG path contract, and Material theme live in
`packages/remya_settings_client`. Settings retains the writer/controller and Rust
system backend. Remya Bar consumes the effective release theme through the public
D-Bus service; it does not apply system preferences or depend on Settings pages.
See [public interfaces](public-api.md) for CLI/D-Bus operation parity and
[XDG layout](xdg-layout.md) for debug, installation, and runtime paths.
