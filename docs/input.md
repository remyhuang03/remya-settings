# Input devices and shortcuts

The Mouse, Touchpad and Keyboard shortcuts pages (Bluetooth & devices) configure
Hyprland 0.57 or later with a Lua configuration. The backend is the
`remya_settings_input` crate in `lib/src/rust/input/`. The keyboard shortcuts
work entirely through Hyprland key bindings, but the interface does not present
them as a Hyprland feature.

## Values and persistence

Each option in `config::OPTIONS` maps a catalog ID to a Hyprland option name
and type. Live values come from one `hyprctl -j descriptions` call. Hyprland's
own range checks are repeated in Rust; the GUI offers narrower slider ranges.

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
- `hl.bind` with `hl.dsp.exec_cmd` or one of six fixed window actions: close,
  float, fullscreen, maximize, pin and scratchpad

The reader parses the file and renders it again. When the result differs from
the file, it refuses to write and reports `write_blocked`, so a hand-edited file
is never overwritten. A missing `hyprland.lua` blocks writes in the same way.

## Reconciliation

On first use, Settings saves the live option values and the shortcuts in
`input.lua`, and changes nothing. Every later read compares:

- saved options with live values (floating-point values to three decimals)
- saved custom and turned-off shortcuts with `input.lua`

Each difference is listed in `conflicts`. The ID `keyboard-shortcuts` stands
for a difference in shortcuts. While a conflict exists, writes are refused.
`Resolve input system` adopts the live values and the file. `Resolve input
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

## Visualizations

| Page | What it shows |
| --- | --- |
| Mouse | The primary button and which way content moves when the wheel rolls toward you |
| Touchpad | The right-click method (corner area or finger count), with a caption for tap mapping |
| Keyboard shortcuts | A keyboard map. Modifier keys toggle the filter; keys with a shortcut are highlighted, and custom ones use the tertiary color. Selecting a free key offers to add a shortcut there. |

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
