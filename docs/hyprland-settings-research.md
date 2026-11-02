# Hyprland settings catalog additions

Research date: 2026-10-26. Baseline: commit `44679b271497c40a0d37dd40299f89ae59c7aa6f`.

This extension adds **2 categories, 85 pages, and 768 controls** (wallpaper-per-output and Hyprpaper misc pages were folded into Background, Qt application and blur variant pages were removed by owner request, and cursor pages moved to the System Cursor page). The combined catalog has **12 categories, 225 pages, and 1,814 controls**. The current reference catalog contains **140 pages and 1,074 controls**. The former `hypr-monitor-fields` page moved into Display: its implemented fields left this extension, and duplicates are listed under `retired` in the coverage file. Coverage files describe the current included controls.

Apart from the implemented Display fields, this extension remains **UI only**. Every remaining addition is `planned`, operation controls remain disabled, and no configuration, process, device, or service is read or modified by the application. Optional components are identified in each page's availability reason. Their presence and compatibility have not been detected.

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

Hyprland pages are grouped by system responsibility; OpenGL and rendering belong under System. The two dedicated Hyprland categories remain at the end of navigation.

| Category | Added pages | Missing concepts now represented |
| --- | ---: | --- |
| System | 10 | OpenGL, rendering and color pipeline, native monitor rules and reserved areas, HDR/ICC/VRR fields, output/workspace assignments, multi-GPU selection, XWayland and application quirks, hypridle listeners, PipeWire routing |
| Bluetooth & devices | 12 | Global and per-device XKB/input overrides, pointer engine, touchpad/touch/tablet/pen parameters, virtual keyboards, gesture definitions and hardware switch bindings |
| Appearance | 16 | Border gradients, gaps-related appearance, opacity/dimming, blur, shadows/glow/motion effects, animation trees and curves, and shell presets |
| Privacy & security | 14 | Compositor permission rules, capture boundaries, portals and file-picker providers, authorization agent, Hyprlock authentication and widget configuration |
| **Window & workspaces (new)** | **23** | Dwindle/Master/Scrolling/Monocle layouts, general layout and snapping, persistent/special workspaces, window groups and group bars, window/layer/workspace rules, key bindings, flags and submaps |
| **Session & configuration (new)** | **12** | Config entrypoints and includes, comments/overrides, backup/restore and diff previews, autostart/shutdown hooks, UWSM/user services, environment variables, plugins, diagnostics, experimental options and logout/power menu |

No unrelated network, account, language, accessibility, or update category was changed merely to increase coverage. Concepts already represented there remain available as original previews.

## Field inventory and structured workflows

The pinned official **Config options** table contains **368 real option rows**; 366 remain represented once in the current added controls. The example table under Syntax is excluded. Layout-specific options come from the separate Dwindle, Master and Scrolling pages; Monocle's documented operations are represented as an operation preview rather than inventing nonexistent configuration keys.

Additional tables cover monitor fields, workspace rules, window match conditions and static/dynamic effects, layer match/effects, gesture definition fields, and documented configuration fields for hypridle, hyprlock, hyprpaper, hyprsunset and hyprqt6engine. Repeated lock-screen widget properties retain distinct widget-specific identities. Gesture runtime callback payloads are not treated as persisted user settings.

Non-tabular features use explicit workflow previews: shortcut creation and conflict inspection, bind flags/submaps, device selection/tags, lid and tablet-mode switches, animation curves, wallpaper directory rotation, config include graphs and comment preservation, archive backup/restore, portal/provider choice, permission policies, plugin lifecycle, environment variables, service/session diagnostics, and exit actions. These are draft task boundaries, not claims of implemented services.

Documented boolean fields use disabled switches. Bounded numeric fields use the documented range; unbounded or compound fields remain disabled text previews. Gradients and Bézier/Spring parameters are explicit draft fields, not a new live editor. Known enum sets are retained where unambiguous. All displayed defaults are illustrative source values, not detected state. The original catalog's control kinds and runtime schema remain unchanged.

## Evidence and preservation checks

- `assets/settings/catalog.json`: original objects plus appended categories, sources, and pages.
- `docs/hyprland-settings-coverage.json`: baseline IDs, inspected repository revisions, file permalinks, new page IDs, and one source mapping for every added control. Native types/defaults/limits are recorded for table-derived fields.
- `docs/settings-implementation-progress.md`: combined human-readable tracker; all preexisting detailed page blocks and tracking notes are retained verbatim, with added pages and updated summary counts.
- `test/catalog_test.dart`: retained baseline identities, source mapping integrity, coverage of current source fields, searchable additions, unavailable previews, and exact tracker parity.

Catalog tests validate current category/page/control identities and source mappings. Rendering tests exercise the enlarged catalog at wide, compact, and narrow widths; asset/schema validation and a Linux build check that the generic renderer accepts every added page.

## Implementation boundaries for later work

Future integrations must select compatible Hyprland/component versions, preserve configuration structure and comments, validate values and paths, distinguish dynamic reloads from restart-only settings, and support rollback where writes could disrupt a session. GUI permission rules are not equivalent to a universal application sandbox. Optional shell components and update/package managers are not selected by the presence of their preview pages. These constraints do not add system-side behavior to this milestone.
