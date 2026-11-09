# Cursor and icon themes

The Cursor page (Appearance) and the Icons section of Colors and themes choose
the cursor theme, cursor size and icon theme, and add or remove theme packs.
The backend is `lib/src/rust/appearance/src/packs.rs`; the service feature is
`themes`. Hiding and pointer-movement options on the Cursor page are Hyprland
options in the `desktop` group; see [Input devices and shortcuts](input.md).

## Finding themes

Themes are looked up the way toolkits look them up:

1. `$XDG_DATA_HOME/icons` (default `~/.local/share/icons`), where Settings adds packs
2. `~/.icons`
3. `icons` in each absolute `$XDG_DATA_DIRS` entry
4. `/usr/share/pixmaps`

Cursor themes use `XCURSOR_PATH` instead when it is set, as libXcursor does.
A folder name found earlier hides the same name later in the path. A folder is:

- an icon theme when its `index.theme` lists `Directories` (`hicolor` is the
  fallback of every theme and is not offered);
- an XCursor theme when it has `cursors/default` or `cursors/left_ptr`;
- a Hyprcursor theme when it has `hyprcursors/` and a `manifest.hl` or
  `manifest.toml`.

Themes marked `Hidden=true`, such as Adwaita, are left out of the pickers unless
they are in use. The Cursor page lists the folders that exist, plus the user
folder, in search order.

## Previews

`Get cursor-preview:<theme>@<size>` decodes the theme's `default`, `text`,
`pointer` and `wait` cursors (with their legacy names, following `Inherits`)
with the `xcursor` crate and returns PNG images at the nominal size at or above
`size`, plus every nominal size the theme provides. The size slider stops at
those sizes. Hyprcursor-only themes have no preview images.

Icon previews are rendered by the GUI's GTK runner (`themeIcon` on the
`top.remya.paths` channel) from a private `GtkIconTheme`, so the desktop's own
icon theme is not touched.

## Applying a choice

A cursor theme or size change writes, in order, and undoes completed steps when
a later one fails:

| Target | Setting |
| --- | --- |
| Running Hyprland | `hyprctl setcursor <theme> <size>`; with `cursor:sync_gsettings_theme` Hyprland also updates GNOME settings |
| KDE / Qt (only when `kdeglobals` exists and `kwriteconfig6` is installed) | `kcminputrc` `[Mouse]` `cursorTheme`, `cursorSize` |
| GNOME / GTK | `org.gnome.desktop.interface` `cursor-theme`, `cursor-size` |
| GTK 3 and GTK 4 | `gtk-cursor-theme-name`, `gtk-cursor-theme-size` in `settings.ini` |
| XCursor default | `Inherits` of `default/index.theme` in the user icon folders that have one, otherwise a new one in `$XDG_DATA_HOME/icons` |
| New processes | `XCURSOR_THEME`, `XCURSOR_SIZE`, `HYPRCURSOR_THEME`, `HYPRCURSOR_SIZE` in a "Remy'a Settings cursor" block of `config.fish` and `hyprland.lua` |

An icon theme change writes `icon-theme`, `gtk-icon-theme-name` and, for KDE,
`kdeglobals` `[Icons]` `Theme`. Every write is read back; file edits keep the
rest of each file and are atomic, as for Light/Dark.

Running applications may keep their previous cursor or icons until they restart.

## Reconciliation

`themes.toml` beside `config.toml` keeps `cursor_theme`, `cursor_size` and
`icon_theme`. On first use it is filled from GNOME settings and nothing is
written. Later reads compare it with GNOME settings, the store GTK and Hyprland
follow. A difference is a conflict: `Resolve themes system` adopts the system
values, `Resolve themes settings` applies the saved ones to every target.

A login script that sets the cursor itself, such as `hyprctl setcursor` in an
`exec` at start-up, overrides the environment block. Settings then reports the
difference as a conflict instead of changing that script.

## Adding and removing packs

`Set cursor.install` or `Set themes.icon-install` with an absolute path to a
folder or an archive installs every theme folder inside it (up to four levels
deep) into `$XDG_DATA_HOME/icons`. Archives are unpacked by `bsdtar`, which
refuses absolute paths, `..` and writes through links, into a staging folder in
the same directory. Archives over 512 MiB, unpacked packs over 2 GiB, special
files, invalid folder names, `default`, `hicolor` and names that already exist
are refused; nothing is moved until every theme in the pack passes. Symbolic
links, which cursor themes rely on, are kept.

`Set cursor.remove` or `Set themes.icon-remove` with a folder name deletes that
theme from the user icon folder. A selected theme cannot be removed, and themes
outside the user folder never can. The GUI asks for confirmation first.

## Boundaries

- Hyprcursor themes are selectable but have no preview images.
- No GTK theme, Qt style or Kvantum theme is changed.
- Flatpak applications follow these settings only through their portal and
  runtime; Settings does not edit Flatpak overrides.

Verification:

- `cargo test -p remya_settings_appearance --no-default-features` (discovery,
  precedence, previews, installation, archives, every apply target and rollback
  with in-memory GNOME settings)
- `test/multitasking_cursor_test.dart`
- `test/desktop_smoke.py`, which runs the service against a nested Hyprland with
  isolated XDG roots, home and GNOME settings
