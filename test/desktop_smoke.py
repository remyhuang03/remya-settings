#!/usr/bin/env python3
"""End-to-end desktop options and theme packs check: blur, fallback background,
display wake, window layout, workspace and window rules, session variables,
cursor options, cursor and icon themes, and text size.

Uses a nested compositor, a private session bus and isolated XDG roots, so the
user's Hyprland configuration is never touched.

    python test/desktop_smoke.py [path/to/remya-settings-service]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "target/debug/remya-settings-service"
DEST = ("--session", "--dest", "top.remya.settings.Service1", "--object-path", "/top/remya/settings")
METHOD = "top.remya.settings.Settings1."
MAIN = 'hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })\n' \
    'hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Window: Close" })\n' \
    'hl.bind("SUPER + J", hl.dsp.exec_cmd("true"))\n'


def run(*args, env=None, check=True):
    return subprocess.run(args, env=env, check=check, capture_output=True, text=True, timeout=30)


def main():
    home = Path(tempfile.mkdtemp(prefix="remya-desktop-smoke-"))
    config = home / "config"
    hypr = config / "hypr"
    hypr.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(MAIN)
    before = {i["instance"] for i in json.loads(run("hyprctl", "-j", "instances").stdout)}
    # Hyprland syncs its cursor theme into GSettings, so it gets the isolated keyfile too.
    isolated = {**{k: v for k, v in os.environ.items() if k != "HYPRLAND_CONFIG"},
                "XDG_CONFIG_HOME": str(config), "XDG_DATA_HOME": str(home / "data"),
                "HOME": str(home), "GSETTINGS_BACKEND": "keyfile"}
    compositor = subprocess.Popen(
        ["Hyprland", "--config", str(hypr / "hyprland.lua")],
        cwd=hypr, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=isolated,
    )
    bus = service = None
    try:
        instance = None
        for _ in range(100):
            time.sleep(0.1)
            if new := {i["instance"] for i in json.loads(run("hyprctl", "-j", "instances").stdout)} - before:
                instance = new.pop()
                break
        assert instance, "nested Hyprland did not start"
        time.sleep(1)

        def hyprctl(*args):
            return run("hyprctl", "-i", instance, *args).stdout

        def binds():
            return {(b["modmask"], b["key"].lower()) for b in json.loads(hyprctl("-j", "binds"))}

        bus = subprocess.Popen(["dbus-daemon", "--session", "--print-address", "--nofork"], stdout=subprocess.PIPE, text=True)
        env = {**isolated, "DBUS_SESSION_BUS_ADDRESS": bus.stdout.readline().strip(),
               "HYPRLAND_INSTANCE_SIGNATURE": instance}
        service = subprocess.Popen([str(SERVICE)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

        def call(method, *args, ok=True):
            result = run("gdbus", "call", *DEST, "--method", METHOD + method, *args, env=env, check=False)
            if result.returncode:
                assert not ok, f"{method} {args}: {result.stderr}"
                return result.stderr
            assert ok, f"{method} {args} should have failed"
            return json.loads(result.stdout.strip()[2:-3].encode().decode("unicode_escape"))

        for _ in range(100):
            time.sleep(0.1)
            if run("gdbus", "call", *DEST, "--method", METHOD + "Get", "about", env=env, check=False).returncode == 0:
                break

        owned = hypr / "remya-settings/desktop.lua"
        state = call("Get", "desktop")
        assert state["error"] is None and state["write_blocked"] is None, state
        assert not state["conflict"] and not owned.exists(), "first use changed the system"
        assert state["options"]["background.hide-logo"] is True, state["options"]

        def option(name, kind):
            return json.loads(hyprctl("-j", "getoption", name))[kind]

        # Options apply live, persist through their own require and survive a reload.
        call("Set", "background.blur-passes", "4")
        call("Set", "background.blur-noise", "0.05")
        call("Set", "background.fallback-color", "'\"#1E2030\"'")
        call("Set", "power.wake-key", "false")
        call("Set", "mouse.pointer-speed", "0.3")
        main = (hypr / "hyprland.lua").read_text()
        assert 'require("remya-settings.desktop")' in main and 'require("remya-settings.input")' in main
        assert 'background_color = "rgba(1e2030ff)"' in owned.read_text()
        hyprctl("reload")
        time.sleep(1)
        assert option("decoration:blur:passes", "int") == 4
        assert option("misc:key_press_enables_dpms", "bool") is False
        state = call("Get", "desktop")
        assert state["system"]["background.fallback-color"] == "#1e2030", state["system"]
        assert not state["conflict"], state
        for bad in [("background.blur-passes", "40"), ("background.fallback-color", "'\"red\"'"),
                    ("background.blur-enabled", "'\"yes\"'")]:
            assert "InvalidArgument" in call("Set", *bad, ok=False)

        # A live change made elsewhere is a conflict; adopting it also updates Settings' own file.
        hyprctl("eval", "hl.config({ decoration = { blur = { passes = 2 } } })")
        assert call("Get", "desktop")["conflicts"] == ["background.blur-passes"]
        call("Set", "background.blur-xray", "true", ok=False)
        call("Resolve", "desktop", "system")
        state = call("Get", "desktop")
        assert not state["conflict"] and state["saved"]["background.blur-passes"] == 2
        assert "passes = 2" in owned.read_text()

        # Window layout and cursor options, including a gap with four different sides.
        call("Set", "multitasking.layout", "'\"master\"'")
        call("Set", "multitasking.gaps-in", "7")
        call("Set", "multitasking.gaps-out", "'[10, 20, 30, 40]'")
        call("Set", "multitasking.snap", "true")
        call("Set", "cursor.inactive-timeout", "3.5")
        call("Set", "cursor.warp-on-change-workspace", "2")
        assert "gaps_out = { top = 10, right = 20, bottom = 30, left = 40 }" in owned.read_text()
        hyprctl("reload")
        time.sleep(1)
        assert option("general:layout", "str") == "master"
        assert option("cursor:inactive_timeout", "float") == 3.5
        state = call("Get", "desktop")
        assert state["system"]["multitasking.gaps-out"] == [10, 20, 30, 40], state["system"]
        assert state["system"]["multitasking.gaps-in"] == 7 and not state["conflict"], state
        for bad in [("multitasking.layout", "'\"spiral\"'"), ("multitasking.gaps-out", "'[1, 2]'"),
                    ("cursor.warp-on-change-workspace", "3")]:
            assert "InvalidArgument" in call("Set", *bad, ok=False)

        # Window appearance, animations and dwindle: translucent colors, nested `col` keys and offsets.
        bell = home / "bell.ogg"
        bell.write_bytes(b"OggS")
        call("Set", "window-appearance.active-border", "'\"#0DB7D455\"'")
        call("Set", "window-appearance.shadow-offset", "'[2, 6]'")
        call("Set", "window-appearance.rounding", "12")
        call("Set", "window-appearance.inactive-opacity", "0.9")
        call("Set", "animations.wobble", "true")
        call("Set", "multitasking.dwindle-force-split", "2")
        call("Set", "fonts.compositor-family", "'\"Monospace\"'")
        call("Set", "sound.compositor-bell", f"'\"{bell}\"'")
        text = owned.read_text()
        assert 'col = { active_border = "rgba(0db7d455)" }' in text and "offset = { 2, 6 }" in text, text
        assert 'font_family = "Monospace"' in text and f'bell_sound = "{bell}"' in text, text
        hyprctl("reload")
        time.sleep(1)
        assert option("decoration:rounding", "int") == 12
        assert option("dwindle:force_split", "int") == 2
        assert option("misc:font_family", "str") == "Monospace"
        assert option("misc:bell_sound", "str") == str(bell)
        state = call("Get", "desktop")
        assert state["system"]["window-appearance.active-border"] == "#0db7d455", state["system"]
        assert state["system"]["window-appearance.shadow-offset"] == [2, 6], state["system"]
        assert state["system"]["fonts.compositor-family"] == "Monospace", state["system"]
        assert state["system"]["sound.compositor-bell"] == str(bell), state["system"]
        assert state["system"]["animations.wobble"] is True and not state["conflict"], state
        call("Set", "sound.compositor-bell", "'\"none\"'")
        assert option("misc:bell_sound", "str") == "none"
        call("Set", "sound.compositor-bell", "'\"default\"'")
        assert option("misc:bell_sound", "str") == "default"
        for bad in [("window-appearance.active-border", "'\"#12345\"'"),
                    ("window-appearance.shadow-offset", "'[0, 500]'"),
                    ("window-appearance.shadow-render-power", "5"),
                    ("fonts.compositor-family", "'\"\"'"),
                    ("sound.compositor-bell", "'\"relative.ogg\"'"),
                    ("sound.compositor-bell", "'\"/tmp/missing-bell.ogg\"'"),
                    ("sound.compositor-bell", "'\"/etc/passwd\"'")]:
            assert "InvalidArgument" in call("Set", *bad, ok=False)

        # Workspace options and rules: rules reload, read back through workspacerules and
        # leave rules from the user's other files alone.
        def rules():
            return {r["workspaceString"]: r for r in json.loads(hyprctl("-j", "workspacerules"))}

        with (hypr / "hyprland.lua").open("a") as main_file:
            main_file.write('hl.workspace_rule({ workspace = "7", persistent = true })\n')
        hyprctl("reload")
        time.sleep(1)
        main = (hypr / "hyprland.lua").read_text()
        state = call("Get", "desktop")
        display = state["monitors"][0]["name"]
        assert state["monitors"][0]["width"] > 0 and not state["conflict"], state
        assert {"workspace": "7", "monitor": "", "default": False, "persistent": True,
                "default_name": "", "settings": False} in state["live_rules"], state["live_rules"]
        call("Set", "workspaces.close-special-on-empty", "false")
        call("Set", "workspaces.initial-workspace-tracking", "2")
        rule = json.dumps({"workspace": "3", "monitor": display, "persistent": True, "default_name": "Mail"})
        state = call("Set", "workspaces.rule-set", f"'{rule}'")
        assert rules()["3"]["persistent"] is True and rules()["3"]["defaultName"] == "Mail", rules()
        assert any(w["id"] == 3 and w["persistent"] for w in state["workspaces"]), state["workspaces"]
        assert f'hl.workspace_rule({{ workspace = "3", monitor = "{display}", persistent = true, default_name = "Mail" }})' \
            in owned.read_text()
        edited = json.dumps({"workspace": "name:mail", "persistent": True, "previous": "3"})
        call("Set", "workspaces.rule-set", f"'{edited}'")
        assert "defaultName" not in rules().get("3", {}) and rules()["name:mail"]["persistent"] is True, rules()
        hyprctl("reload")
        time.sleep(1)
        assert option("misc:close_special_on_empty", "bool") is False
        assert option("misc:initial_workspace_tracking", "int") == 2
        state = call("Get", "desktop")
        assert not state["conflict"] and state["rules"] == [{"workspace": "name:mail", "persistent": True}], state
        for bad in ['{"workspace": "mail"}', '{"workspace": "1", "default": true}',
                    '{"workspace": "1", "monitor": "DP 1"}', '{"workspace": "1", "gaps_in": 5}']:
            assert "InvalidArgument" in call("Set", "workspaces.rule-set", f"'{bad}'", ok=False)
        call("Set", "workspaces.rule-remove", "'{\"workspace\": \"name:mail\"}'")
        assert "name:mail" not in rules() and rules()["7"]["persistent"] is True, rules()
        assert "workspace_rule" not in owned.read_text()
        assert (hypr / "hyprland.lua").read_text() == main, "Settings changed the user's own rule"

        # Window rules and session variables: Hyprland checks each rule, a new window
        # follows it after the reload, and apps the compositor starts see the variable.
        rule = json.dumps({"class": "remya.smoke", "float": True, "center": True, "size": [50, 40]})
        state = call("Set", "window-rules.set", f"'{rule}'")
        assert state["window_rules"] == [json.loads(rule)] and not state["conflict"], state
        assert 'hl.window_rule({ match = { class = "^(remya\\\\.smoke)$" }, float = true, center = true' \
            in owned.read_text(), owned.read_text()
        for bad in ['{"class": "a"}', '{"class": "a", "no_anim": true}', '{"class": "a", "center": true}']:
            assert "InvalidArgument" in call("Set", "window-rules.set", f"'{bad}'", ok=False)
        call("Set", "environment.set", "'{\"name\": \"REMYA_SMOKE\", \"value\": \"a b;c\"}'")
        assert 'hl.env("REMYA_SMOKE", "a b;c")' in owned.read_text()
        assert "InvalidArgument" in call("Set", "environment.set", "'{\"name\": \"PATH\", \"value\": \"/x\"}'", ok=False)
        seen = home / "env.txt"
        hyprctl("eval", f'hl.dispatch(hl.dsp.exec_cmd("sh -c \'printf %s \\"$REMYA_SMOKE\\" > {seen}\'"))')
        hyprctl("eval", 'hl.dispatch(hl.dsp.exec_cmd("kitty --class remya.smoke -o confirm_os_window_close=0 sleep 30"))')
        window = None
        for _ in range(100):
            time.sleep(0.1)
            window = next((c for c in json.loads(hyprctl("-j", "clients")) if c["class"] == "remya.smoke"), None)
            if window and seen.exists():
                break
        assert seen.read_text() == "a b;c", seen.read_text() if seen.exists() else "no file"
        monitor = json.loads(hyprctl("-j", "monitors"))[0]
        assert window and window["floating"], window
        assert abs(window["size"][0] - monitor["width"] / monitor["scale"] * 0.5) <= 2, (window, monitor)
        listed = call("Get", "desktop")["windows"]
        assert any(w["class"] == "remya.smoke" for w in listed), listed
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.close({{ window = "address:{window["address"]}" }}))')
        call("Set", "window-rules.remove", "'{\"class\": \"remya.smoke\"}'")
        call("Set", "environment.remove", "'{\"name\": \"REMYA_SMOKE\"}'")
        assert "window_rule" not in owned.read_text() and "hl.env" not in owned.read_text()

        # Cursor and icon themes: first use adopts GSettings, then every target follows.
        # A second cursor theme in the isolated user folder, reusing installed cursor files.
        system_cursor = next((p for p in Path("/usr/share/icons").iterdir() if (p / "cursors/default").exists()), None)
        assert system_cursor, "the smoke test needs an installed cursor theme"
        smoke_cursor = home / "data/icons/Smoke-Cursors"
        smoke_cursor.mkdir(parents=True)
        (smoke_cursor / "index.theme").write_text("[Icon Theme]\nName=Smoke Cursors\n")
        (smoke_cursor / "cursors").symlink_to(system_cursor / "cursors")
        themes = call("Get", "themes")
        assert themes["error"] is None and not themes["conflict"], themes
        cursors = [t["id"] for t in themes["cursor_themes"]
                   if t["cursors"] and t["id"] != themes["options"]["cursor.theme"]]
        icons = [t["id"] for t in themes["icon_themes"] if t["id"] != themes["options"]["themes.icon-theme"]]
        assert cursors and icons, "the smoke test needs an installed cursor and icon theme"
        # KDE keys are written only where KDE configuration exists, through kwriteconfig6.
        kde = shutil.which("kwriteconfig6") is not None
        if kde:
            (config / "kdeglobals").write_text("[General]\nColorScheme=Keep\n")
        call("Set", "cursor.theme", f"'\"{cursors[0]}\"'")
        call("Set", "cursor.size", "32")
        call("Set", "themes.icon-theme", f"'\"{icons[0]}\"'")
        keyfile = (config / "glib-2.0/settings/keyfile").read_text()
        assert f"cursor-theme='{cursors[0]}'" in keyfile and "cursor-size=32" in keyfile, keyfile
        assert f"gtk-cursor-theme-name={cursors[0]}" in (config / "gtk-3.0/settings.ini").read_text()
        main = (hypr / "hyprland.lua").read_text()
        assert f'hl.env("XCURSOR_THEME", "{cursors[0]}")' in main and 'hl.env("HYPRCURSOR_SIZE", "32")' in main
        assert f"Inherits={cursors[0]}" in (home / "data/icons/default/index.theme").read_text()
        if kde:
            globals_ = (config / "kdeglobals").read_text()
            assert "ColorScheme=Keep" in globals_ and f"Theme={icons[0]}" in globals_, globals_
            assert "cursorSize=32" in (config / "kcminputrc").read_text()
        preview = call("Get", f"cursor-preview:{cursors[0]}@32")
        assert preview["images"] and preview["sizes"], preview
        assert "InvalidArgument" in call("Set", "cursor.theme", "'\"../etc\"'", ok=False)
        # A change made outside Settings is a conflict until adopted.
        run("gsettings", "set", "org.gnome.desktop.interface", "cursor-size", "48", env=env)
        assert call("Get", "themes")["conflicts"] == ["cursor.size"]
        call("Resolve", "themes", "system")
        assert call("Get", "cursor.size")["value"] == 48
        # A theme folder installs into the user's icon folder and can be removed again.
        pack = home / "download/Smoke-Icons"
        (pack / "48x48/apps").mkdir(parents=True)
        (pack / "index.theme").write_text("[Icon Theme]\nName=Smoke Icons\nDirectories=48x48/apps\n")
        added = call("Set", "themes.icon-install", f"'\"{pack}\"'")
        assert added["installed"] == ["Smoke-Icons"] and (home / "data/icons/Smoke-Icons/index.theme").is_file()
        assert "already installed" in call("Set", "themes.icon-install", f"'\"{pack}\"'", ok=False)
        call("Set", "themes.icon-remove", "'\"Smoke-Icons\"'")
        assert not (home / "data/icons/Smoke-Icons").exists()
        assert "ReadOnly" in call("Set", "cursor.folders", "'\"x\"'", ok=False)

        # Text size: first use adopts GSettings without writing, then writes the factor.
        keyfile = config / "glib-2.0/settings/keyfile"
        text = call("Get", "text-size")
        assert text["error"] is None and not text["conflict"] and text["options"]["text-size.scale"] == 1.0, text
        assert "text-scaling-factor" not in keyfile.read_text()
        call("Set", "text-size.scale", "1.25")
        assert "text-scaling-factor=1.25" in keyfile.read_text()
        assert run("gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor", env=env).stdout.strip() == "1.25"
        assert "InvalidArgument" in call("Set", "text-size.scale", "3.5", ok=False)
        run("gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "2.0", env=env)
        assert call("Get", "text-size")["conflicts"] == ["text-size.scale"]
        assert "conflict" in call("Set", "text-size.scale", "1.5", ok=False)
        call("Resolve", "text-size", "settings")
        assert call("Get", "text-size.scale")["value"] == 1.25
        run("gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "1.5", env=env)
        call("Resolve", "text-size", "system")
        assert "text_scaling_factor = 1.5" in (config / "remya/settings/text-size.toml").read_text()

        # Desktop files never hold shortcuts; a hand-edited file blocks writes.
        owned.write_text(owned.read_text() + 'hl.bind("SUPER + K", hl.dsp.window.close())\n')
        assert call("Get", "desktop")["write_blocked"]
        call("Set", "power.wake-pointer", "false", ok=False)
        print("desktop smoke test passed")
    finally:
        for process in (service, bus):
            if process:
                process.terminate()
                process.wait(timeout=10)
        compositor.terminate()
        compositor.wait(timeout=10)
        shutil.rmtree(home, ignore_errors=True)


if __name__ == "__main__":
    main()
