# Hyprland settings catalog additions

Research date: 2026-10-26. Baseline: commit `44679b271497c40a0d37dd40299f89ae59c7aa6f`.

The retained extension has no category of its own: its **303 controls** live on ordinary pages, and three pages (Window appearance, Animations and Input capture) were added for it. Coverage files describe the currently included controls and their owning pages.

Controls marked `available` use the Settings service and the Settings-owned Lua files described in [Input devices and shortcuts](input.md) and [Public interfaces](public-api.md). Every other addition is `planned`: it stays disabled, and nothing is read or modified for it. Optional components are named in each page's availability reason; their presence and compatibility are not detected.

## Reference versions

The official wiki is versioned and its default pages target latest Git. This research pins the wiki to commit `026b282bdde916bb7ce77689857f40cf1e829e82`, rather than claiming the listed settings work on every installed release. Ecosystem components have independent releases and configuration formats. Hyprland 0.55+ Lua syntax must not be confused with older hyprlang configuration.

| Reference | Pinned revision | What was inspected | How it informs this draft |
| --- | --- | --- | --- |
| [Hyprland Wiki](https://github.com/hyprwm/hyprland-wiki/tree/026b282bdde916bb7ce77689857f40cf1e829e82) | `026b282` | Configuration options, layouts, monitors, rules, bindings, permissions, ecosystem documentation | Authoritative configuration keys, types, documented defaults/limits, and component boundaries |
| [HyprViz](https://github.com/timasoft/hyprviz/tree/83e4dfcde1eeae157b10c799e46fda1fae630269) | `83e4dfc` | `src/gui.rs`, `src/advanced_editors.rs`, `readme.md` | Separate configuration categories and editors for rules, binds, curves, environment, and session actions |
| [HyprSettings](https://github.com/acropolis914/hyprsettings/tree/2343820372012eb436d7d24fe645f7948651d37b) | `2343820` | README and source layout | Multi-file configuration discovery, comment preservation, variables, color/gradient/curve editing workflows |
| [nwg-shell-config](https://github.com/nwg-piotr/nwg-shell-config/tree/99dc0e00aa8b0931cd2b1be562ef950fbcc337f8) | `99dc0e0` | README and configuration package layout | Default desktop tools, shell style presets, idle/lock, backup/restore, and system information |
| [nwg-displays](https://github.com/nwg-piotr/nwg-displays/tree/412eff2779cf123f308753faab1a182dd474ba7a) | `412eff2` | README and output configuration implementation layout | Output-to-workspace assignments, multi-output configuration, fallback rules, and saved layouts |

At the inspected revision, HyprViz's README explicitly says Hyprland 0.55 is not supported yet. Its editor organization is a feature reference, not proof that its parser supports current Lua. HyprSettings describes a `hyprland.conf` editor; this draft does not infer Lua compatibility from that description. The inspected nwg-displays documentation distinguishes legacy `source` configuration and Lua module inclusion. Sway-only autotiling and GTKlock-specific settings from nwg-shell-config are not presented as native Hyprland capabilities.

Only feature facts and interface organization were used. No third-party implementation code, scripts, schemas, artwork, or prose descriptions were copied into the application. Product labels and disabled previews are authored in this project; source-specific technical keys are retained for traceability.

## Classification and gap coverage

Hyprland controls are grouped by system responsibility on ordinary pages; there is no Hyprland category in navigation.

| Category | Added pages | Missing concepts now represented |
| --- | ---: | --- |
| System | 0 | Window layouts (Dwindle, Master and Scrolling options on System › Multitasking, each shown only for its layout), environment variables (System › Environment variables), Graphics (tearing, direct scanout, automatic HDR, XWayland scaling), window groups, focus and full-screen behavior (System › Multitasking), compositor version and configuration errors (System › System information), native monitor rules and reserved areas, HDR/ICC fields, output/workspace assignments, hypridle listeners |
| Sound | 0 | Native PipeWire default devices, stream inventory and routing; device profile/port previews |
| Bluetooth & devices | 0 | Global XKB/input overrides, pointer engine, touchpad/touch/tablet/pen parameters, virtual keyboards and gesture definitions |
| Appearance | 2 | Window appearance (window and group border colours, corners, opacity, dimming, shadows and glow) and Animations (global switches, motion blur, wobbly windows, animation trees and curves); window blur lives on Background |
| Privacy & security | 1 | Capture boundaries, Hyprlock authentication and widget configuration |

No unrelated network, account, language, accessibility, or update category was changed merely to increase coverage. Concepts already represented there remain available as original previews.

## Field inventory and structured workflows

The pinned official **Config options** table contains **368 real option rows**; 155 remain represented once in the current controls; mouse, touchpad, gesture and bind-behaviour options that Settings implements are mapped to their ordinary pages, as are the window blur, fallback background and display wake options on Background and Power & battery, the `general` and `general:snap` options on System › Multitasking, the cursor hiding and movement options on Appearance › Cursor, the common `group`, focus and not-responding `misc` options on System › Multitasking, and tearing, direct scanout, automatic HDR and XWayland scaling on System › Graphics. The remaining `group`, `misc`, `render`, `opengl`, `xwayland`, `ecosystem`, `debug` and `experimental` options and `layout:single_window_aspect_ratio*` were removed as debugging, compatibility, nag or rarely used switches, together with layer rules, compositor permission rules, per-device input blocks and hardware switch bindings, plugin management, UWSM/user-service and IPC diagnostics previews. Cursor options for zooming (Magnifier's concern), debugging and rendering (`invisible`, `min_refresh_rate`, `no_break_fs_vrr`, `hotspot_padding`, `use_cpu_buffer`, `default_monitor`, `sync_gsettings_theme`, the remaining warp variants) and `general:locale` were removed, as was `decoration:screen_shader` (a raw shader path with no ordinary-user meaning). Rarely used or duplicated options were removed rather than previewed: global `misc:vrr` (per-display VRR is implemented), splash colour, font and rendering, forced default wallpapers, and the blur `ignore_opacity`, `new_optimizations`, `vibrancy_darkness` and `popups_ignorealpha` tuning. The nwg-displays output-assignment drafts, raw hypridle command fields and Hyprland session exit actions were also removed; the Power page covers screen off, locking and sleep instead. The example table under Syntax is excluded. Layout-specific options come from the separate Dwindle, Master and Scrolling pages; rarely used ones (`master:special_scale_factor`, `new_on_active`, `center_master_fallback`, `center_ignores_reserved`, `allow_small_split`, `scrolling:follow_focus`, `follow_min_visible`, `explicit_column_widths`, `wrap_swapcol`) and per-workspace layout overrides were removed. Monocle has no configuration keys and its operations are not previewed. Configuration file, include and reload previews were removed: Settings writes only its own files, and System information reports configuration errors.

Additional tables cover monitor fields, workspace rules, gesture definition fields, and documented configuration fields for hypridle, hyprlock, hyprpaper and hyprqt6engine. Repeated lock-screen widget properties retain distinct widget-specific identities. Gesture runtime callback payloads are not treated as persisted user settings.

Non-tabular features use explicit workflow previews: animation curves, wallpaper directory rotation and archive backup/restore. These are draft task boundaries, not claims of implemented services.

Documented boolean fields use disabled switches. Bounded numeric fields use the documented range; unbounded or compound fields remain disabled text previews. Gradients and Bézier/Spring parameters are explicit draft fields, not a new live editor. Known enum sets are retained where unambiguous. All displayed defaults are illustrative source values, not detected state. The original catalog's control kinds and runtime schema remain unchanged.

## Evidence and preservation checks

- `assets/settings/catalog.json`: current categories, sources and pages, with related compositor previews grouped in the owning ordinary page's collapsed Advanced section.
- `docs/hyprland-settings-coverage.json`: baseline IDs, inspected repository revisions, file permalinks, remaining standalone page IDs, and one source mapping for every added control, including folded controls. Native types/defaults/limits are recorded for table-derived fields.
- `test/catalog_test.dart`: retained baseline identities, source mapping integrity, coverage of current source fields, searchable additions, unavailable previews, and coverage parity.

Catalog tests validate current category/page/control identities and source mappings. Rendering tests exercise the enlarged catalog at wide, compact, and narrow widths; asset/schema validation and a Linux build check that the generic renderer accepts every added page.

## Implementation boundaries for later work

Future integrations must select compatible Hyprland/component versions, preserve configuration structure and comments, validate values and paths, distinguish dynamic reloads from restart-only settings, and support rollback where writes could disrupt a session. GUI permission rules are not equivalent to a universal application sandbox. Optional shell components and update/package managers are not selected by the presence of their preview pages. These constraints do not add system-side behavior to this milestone.

Related input, touchpad, touch, pen, display, graphics, audio, power, appearance, lock-screen, backup and authorization previews now live under the corresponding ordinary page's default-collapsed Advanced section. Unimplemented previews remain planned and disabled; available audio controls are documented in [Sound](sound.md). Startup apps now use XDG Autostart and UWSM; see [Startup apps](startup.md). Mouse, touchpad and keyboard shortcuts are implemented on the Bluetooth & devices pages; see [Input devices and shortcuts](input.md). 

Window rules are implemented on Apps › Window rules as one curated editor rather than previews of every match condition and effect; Desktop Portal and Screen Sharing was removed because xdg-desktop-portal-hyprland already provides its own share picker and restore-token choice.
