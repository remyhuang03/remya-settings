---
name: hyprland-desktop-testing
description: >-
  CLAUDE MODELS ONLY. Codex and other non-Claude agents must not load or follow
  this skill. Drive the live Hyprland 0.57 desktop for visual checks of the
  installed Remya Settings app: find windows, open pages, move the pointer,
  click, scroll, take screenshots and run write tests in a nested Hyprland.
  Use when a Claude model must inspect or interact with the real desktop.
---

# Hyprland desktop testing (Claude models only)

> **Scope: Claude models only.** If you are Codex or any non-Claude agent, stop
> reading and ignore this skill; use your own desktop workflow instead. These
> notes work around gaps in how Claude drives the desktop and would only add
> noise to agents that already handle Hyprland well.

`scripts/desk.sh` wraps the commands below. All coordinates are Hyprland
**logical** coordinates (the ones `hyprctl` reports), across all monitors.

## Find and open things

- Open a Settings page (starts the GUI if needed):
  `gdbus call --session --dest top.remya.settings.Service1 --object-path /top/remya/settings --method top.remya.settings.Settings1.Open <page-id>`.
  Wait about 2.5 s before capturing.
- Window geometry: `desk.sh window top.remya.settings` prints `X,Y WxH` from
  `hyprctl -j clients` (`at`, `size`). Check `workspace.id` against the
  monitor's `activeWorkspace` if the window may be hidden.
- Dialogs are separate clients (a GTK file chooser, a polkit agent): list
  `hyprctl -j clients` again after the action. Bars, notifications and
  launchers are layers: `hyprctl -j layers`.
- Monitor layout and scale: `hyprctl -j monitors`. Scales here are fractional
  (1.6, 1.33), so logical sizes differ from pixel sizes.

## Screenshots

- `desk.sh shot "X,Y WxH" out.png` runs `grim -g ... -s 1`: the image is in
  logical pixels, so positions in it map 1:1 back to pointer coordinates
  (`window X + image x`). Without `-s 1` the image is scaled and that mapping
  breaks.
- Save screenshots in the session scratchpad, then Read the PNG to look at it.

## Pointer, click and scroll

- `hyprctl dispatch movecursor` does nothing with the 0.57 Lua config; do not
  use it. `ydotool` (needs `ydotoold`) only moves relatively, and pointer
  acceleration can overshoot, so `desk.sh to X Y` closes half the remaining
  distance per step and checks `hyprctl cursorpos` until within 2 px.
- If `to` reports that the pointer stopped elsewhere, the user is probably
  moving the mouse. Wait and retry instead of fighting them.
- Click: `desk.sh click` (`ydotool click 0xC0`, left press and release).
- Scroll: `desk.sh scroll -8` scrolls down. It only reaches the window under
  the pointer, so move there first. Small values (±5 to ±10) per step; large
  ones jump past whole sections. Sleep 0.6 to 1 s before capturing so
  animations settle.
- Silence `ydotool` with `>/dev/null 2>&1`; it prints warnings on every call.
- Do not type text or press keys into windows you did not open yourself.

## Safety on the real desktop

- Never type a password. Restarting `top.remya.settings.service` resets its
  authorization, so the next GUI launch shows a polkit prompt. If you caused
  it, find the agent client and click its Cancel button, then tell the user
  (Settings shows an "Authorization canceled" banner until they retry).
- Only read the real desktop. Settings changes that write system or user
  configuration belong in the nested instance below.
- After `python tool/install.py`, check the service runs the new binary:
  `readlink /proc/$(systemctl --user show -p MainPID --value top.remya.settings.service)/exe`.
  A `(deleted)` suffix means something reactivated the old binary during the
  swap; run `systemctl --user restart top.remya.settings.service`.

## Write tests in a nested Hyprland

See `test/desktop_smoke.py` for the full pattern:

1. Create a temporary home with its own `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and
   `HOME`, set `GSETTINGS_BACKEND=keyfile` (Hyprland syncs the cursor theme
   into GNOME settings), and drop `HYPRLAND_CONFIG` from the environment.
2. Start `Hyprland --config <tmp>/hypr/hyprland.lua` with that environment. Find
   its instance as the new entry in `hyprctl -j instances`.
3. Address it with `hyprctl -i <instance> ...` and give the service
   `HYPRLAND_INSTANCE_SIGNATURE=<instance>` and a private `dbus-daemon`.
4. Kill the compositor, bus and service when done, and confirm the user's real
   files are unchanged.
