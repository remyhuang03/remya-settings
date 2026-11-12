# Input devices and shortcuts

The Mouse, Touchpad and Keyboard shortcuts pages (Bluetooth & devices) configure
Hyprland 0.57 or later with a Lua configuration. The backend is the
`remya_settings_input` crate in `lib/src/rust/input/`. The keyboard shortcuts
work entirely through Hyprland key bindings, but the interface does not present
them as a Hyprland feature.

## Values and persistence

Each option in `config::INPUT_OPTIONS` maps a catalog ID to a Hyprland option name
and type. The same engine serves a second group, `config::DESKTOP`, whose window
blur, fallback background, display wake, compositor font (`misc:font_family`) and
compositor bell (`misc:bell_sound`) options live in their own
`remya-settings/desktop.lua` and `desktop.toml` and never contain shortcuts. Live values come from one `hyprctl -j descriptions` call. Hyprland's
own range checks are repeated in Rust; the GUI offers narrower slider ranges.

The `desktop` group also holds the Multitasking page (`general:*` and
`general:snap:*`: layout, gaps, borders, snapping and resizing) and the hiding
and pointer-movement options of the Cursor page (`cursor:*`). Gaps are CSS-style:
one number for every side or `[top, right, bottom, left]`, written to Lua as a
number or a `{ top, right, bottom, left }` table. Cursor and icon themes are a
separate feature; see [Cursor and icon themes](themes.md).

The keyboard layouts of the Language and Region page are `input` options too.
`language.keyboard-layouts` is an ordered `[{layout, variant}]` list read from
`input:kb_layout` and `input:kb_variant` and written as one
`hl.config({ input = { kb_layout = "us,de", kb_variant = ",nodeadkeys" } })` line,
so a layout and a variant meant for another layout are never compiled together
(on a nested Hyprland 0.57 an invalid pair silently falls back to `us` while
`descriptions` still reports the request). `language.keyboard-options` is
`input:kb_options`; the page's layout switching shortcut replaces only its `grp:`
entries. Layouts, variants and options are validated against xkeyboard-config's
`/usr/share/X11/xkb/rules/evdev.lst` (`xkb.rs`), at most four layouts. Per-device
`kb_layout` overrides in the user's configuration are not changed.

The Window appearance page (`general:col.*` border colors and `decoration:*`
corners, opacity, dimming, shadow and glow), the Animations page
(`animations:*`, `misc:animate_*`, `decoration:motion_blur:*` and
`decoration:wobble:*`) and the layout options of the Multitasking page
(`dwindle:*`, `master:*` and `scrolling:*`, each shown only while its layout is
chosen) are in the same group.
Colors with transparency are `#rrggbbaa` and are written as `rgba(rrggbbaa)`;
Hyprland reports them as `AARRGGBB` gradients, of which the first color is
read. Option names containing a dot nest in Lua (`col.active_border` becomes
`col = { active_border = … }`). The shadow offset is `[x, y]`, written as
`{ x, y }`.

A change is applied in four steps:

1. `hyprctl eval 'hl.config({ … })'`, which Hyprland validates.
2. Readback through `descriptions`.
3. A rewrite of the Settings-owned `$XDG_CONFIG_HOME/hypr/remya-settings/input.lua`.
4. An update of the saved copy in `input.toml`, stored beside `config.toml`.

The first write appends this managed block to the end of `hyprland.lua`:

```lua
-- BEGIN Remy'a Settings input
require("remya-settings.input")
-- END Remy'a Settings input
```

The block comes last, so the values it loads override earlier configuration.
Hyprland reloads automatically when that file changes, and a reload discards
values that only `eval` set. For that reason, `input.lua` holds every option
Settings has written. If any step fails, Settings restores the previous file,
removes a block it added, and reverts the live values.

`input.lua` contains only the lines Settings renders:

- `hl.config` statements
- `hl.unbind` of a combination
- `hl.bind` with `hl.dsp.exec_cmd` or one of eight fixed actions: close,
  float, fullscreen, maximize, pin, scratchpad, group (toggle a window group)
  and group-next (next tab in the group)

The reader parses the file and renders it again. When the result differs from
the file, it refuses to write and reports `write_blocked`, so a hand-edited file
is never overwritten. A missing `hyprland.lua` blocks writes in the same way.

## Reconciliation

On first use, Settings saves the live option values and the shortcuts in
`input.lua`, and changes nothing. An option added to a group later starts from
its live value the same way. Every later read compares:

- saved options with live values (floating-point values to three decimals)
- saved custom and turned-off shortcuts with `input.lua`

Each difference is listed in `conflicts`. The ID `keyboard-shortcuts` stands
for a difference in shortcuts. While a conflict exists, writes are refused.
`Resolve input system` adopts the live values and the file. It also replaces adopted values in the
Settings-owned file, which loads last and would otherwise bring the old value back
on the next reload. `Resolve input
settings` writes the saved values and verifies them.

## Shortcuts

`hyprctl -j binds` is grouped by submap and combination. Each group reports:

- its keycaps and a description, if it has one
- labelled actions (Lua function binds show as "Script")
- whether it is a custom shortcut

Settings uses libxkbcommon, the library Hyprland uses to resolve bind keys, to:

- build the main keyboard's layout from `hyprctl devices`
- compare spellings of the same key, such as `Q`, `q` and `code:24`
- label keys and find a key's position on the keyboard map

New shortcuts are stored with the canonical keysym name. Binding a plain key
without Super, Ctrl or Alt is refused, except for function, media (`XF86`) and
Print keys.

When a new combination is already in use, the change requires `replace`.
Replacing a built-in shortcut adds an `hl.unbind` line before the new bind;
replacing a custom shortcut drops it. To restore a turned-off shortcut, Settings
removes its `hl.unbind` line and Hyprland reloads its configuration.

After every shortcut write, Settings waits up to three seconds for live binds to
match the saved state. If they do not match, the files are restored. If
`misc:disable_autoreload` is set, Settings runs `hyprctl reload` itself.

### Recording

Without help, Hyprland would run an existing binding (for example Super+Q, which
closes the window) before the recorder saw the keys. Following the Hyprland wiki's
pass-through submap pattern, `Set keyboard-shortcuts.record true` defines and
enters an empty `remya-settings-record` submap. That submap contains only a
non-consuming `Escape` bind that returns to the default submap, so the recorder
still receives Escape.

Recording ends in any of these ways:

- the GUI sends `false`
- the user presses Escape
- Hyprland reloads its configuration, which drops the submap
- the service detects that the GUI process exited

The Flutter recorder maps the physical key to an XKB keycode through
`kLinuxToPhysicalKey`. The service then names the keycode in the active layout.

## Window rules and environment variables

Apps › Window rules and System › Environment variables also use the `desktop`
group. `desktop.lua` accepts these two more line shapes, after the workspace
rules and in this fixed field order:

```lua
hl.env("GDK_BACKEND", "wayland,x11")
hl.window_rule({ match = { class = "^(org\\.gnome\\.Nautilus)$", title = ".*(Save As).*" }, float = true, center = true, size = { "(monitor_w*0.6)", "(monitor_h*0.5)" }, workspace = "3 silent", pin = true, maximize = true, no_initial_focus = true, opacity = 0.9, no_blur = true, no_shadow = true, keep_aspect_ratio = true, idle_inhibit = "fullscreen" })
```

A rule matches an exact app class, text its title contains, or both; Settings
writes both as literal text, escaping RE2 characters, and reads back only that
shape. Rules are keyed by class and title. Center, size and pin need `float`;
size is 10% to 100% of the display; opacity is 10% to 100%; `silent` needs a
workspace; maximized and full screen exclude each other; `idle_inhibit` is
`focus`, `fullscreen` or `always`. Before a write, Hyprland evaluates the rule
with `enabled = false`, which refuses unknown fields and wrong types without the
rule taking effect.

Variable names are letters, digits and underscores, not starting with a digit.
Names that Cursor and Light/Dark write (`XCURSOR_*`, `HYPRCURSOR_*`,
`QT_QUICK_CONTROLS_*_THEME`) and session variables (`PATH`, `HOME`,
`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `HYPRLAND_INSTANCE_SIGNATURE` and others,
listed in `reserved_env`) are refused. Values are one line.

A change to either reloads the configuration explicitly, even with autoreload
on, and then fails, restoring the files, when `hyprctl -j configerrors` names a
Settings-owned file. Hyprland sets variables on reload for apps it starts
afterwards; it does not unset a removed one, so that takes effect after signing
in again. Saved lists are compared with `desktop.lua` under the conflict IDs
`window-rules` and `environment`. Rules and variables in other files are not
read or changed.

## Workspaces

The Workspaces page (System) uses the `desktop` group. Its options are
`misc:close_special_on_empty`, `misc:initial_workspace_tracking`,
`binds:hide_special_on_workspace_change`, `binds:workspace_center_on` and
`input:special_fallthrough`. The back-and-forth and cycling options stay in the
`input` group, because their lines already live in `input.lua`.

Workspace rules are the one other line shape `desktop.lua` accepts, in this fixed
field order:

```lua
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true, default_name = "Web" })
```

Only `workspace` is required, and fields that are off or empty are left out. The
selector is a number from 1 to 9999, `name:<text>` or `special:<text>`; text is
one line of at most 64 characters. `monitor` is empty or a connector name.
`default` needs a display and a regular workspace, and setting it clears
`default` on other Settings rules for the same display. `default_name` applies
to numbered workspaces only.

Rules change only on a configuration reload. After a write, Settings reloads
(unless autoreload is on) and waits up to three seconds until
`hyprctl -j workspacerules` reports every saved rule and no longer reports the
fields of removed or edited ones. If that does not happen, the files are
restored. Hyprland merges rules for the same workspace, so a field that another
file also sets cannot be removed from Settings; that write times out and is
undone.

Saved rules are compared with the rules in `desktop.lua`; a difference is the
conflict ID `workspaces`. `Get desktop` also reports `live_rules` (every live
rule, with `settings` marking the ones in `desktop.lua`), `monitors` (connector,
layout position and logical size after scale and rotation, and the active and
scratchpad workspace) and `workspaces` (`id`, `name`, `monitor`, `windows`,
`persistent`). Rules from other files, such as a display tool's
`workspaces.lua`, are shown read-only and never edited.

## Visualizations

| Page | What it shows |
| --- | --- |
| Mouse | The primary button and which way content moves when the wheel rolls toward you |
| Touchpad | The right-click method (corner area or finger count), with a caption for tap mapping |
| Keyboard shortcuts | A keyboard map. Modifier keys toggle the filter; keys with a shortcut are highlighted, and custom ones use the tertiary color. Selecting a free key offers to add a shortcut there. |
| Workspaces | Displays at their layout positions and logical proportions, each with its open workspaces and the rule workspaces bound to it. The showing workspace is highlighted; selecting one edits its Settings rule or starts one. |

Options that do not apply are hidden rather than disabled:

- pointer refocus, unless focus follows the pointer
- the tap options, unless tap-to-click is on
- drag lock, unless tap-and-drag is on

## Boundaries

Settings does not offer these features:

- **Per-device enabling, speed and acceleration.** `device` rules have no
  `hyprctl` readback.
- **Gesture bindings.** `hl.gesture` has no readback.
- **Editing Lua function binds.**

The mouse settings apply to all pointers, and the pointer speed also applies to
touchpads.

Verification:

- `cargo test -p remya_settings_input` (fake compositor)
- `test/input_test.dart`
- `test/input_smoke.py`, which runs the service against a nested Hyprland with
  isolated XDG roots
- `test/desktop_smoke.py`, the same for the desktop group: Multitasking
  (including window groups, focus and full screen, and the Dwindle, Master and
  Scrolling layouts), Graphics, Window appearance, Animations, Workspaces and
  the System information compositor readouts. Each option is written, kept
  after `hyprctl reload`, read back without a conflict, and out-of-range values
  are refused.

Not tested on hardware: direct scanout and automatic HDR switching with a real
game or HDR content.
