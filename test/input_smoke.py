#!/usr/bin/env python3
"""End-to-end input check: the real service against a nested Hyprland.

Uses a nested compositor, a private session bus and isolated XDG roots, so the
user's input settings, shortcuts and configuration are never touched.

    python test/input_smoke.py [path/to/remya-settings-service]
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
    home = Path(tempfile.mkdtemp(prefix="remya-input-smoke-"))
    config = home / "config"
    hypr = config / "hypr"
    hypr.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(MAIN)
    before = {i["instance"] for i in json.loads(run("hyprctl", "-j", "instances").stdout)}
    compositor = subprocess.Popen(
        ["Hyprland", "--config", str(hypr / "hyprland.lua")],
        cwd=hypr, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env={**os.environ, "XDG_CONFIG_HOME": str(config)},
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
        env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": bus.stdout.readline().strip(),
               "HYPRLAND_INSTANCE_SIGNATURE": instance, "XDG_CONFIG_HOME": str(config),
               "HOME": str(home), "GSETTINGS_BACKEND": "keyfile"}
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

        owned = hypr / "remya-settings/input.lua"
        state = call("Get", "input")
        assert state["error"] is None and state["write_blocked"] is None, state
        assert not state["conflict"] and not owned.exists(), "first use changed the system"
        assert (hypr / "hyprland.lua").read_text() == MAIN

        # Options apply live, persist through the managed require and survive a reload.
        call("Set", "mouse.pointer-speed", "0.4")
        call("Set", "touchpad.tap-to-click", "false")
        assert "require(\"remya-settings.input\")" in (hypr / "hyprland.lua").read_text()
        hyprctl("reload")
        time.sleep(1)
        assert json.loads(hyprctl("-j", "getoption", "input:sensitivity"))["float"] == 0.4
        assert json.loads(hyprctl("-j", "getoption", "input:touchpad:tap-to-click"))["bool"] is False
        assert "InvalidArgument" in call("Set", "mouse.pointer-speed", "4", ok=False)

        # A live change made elsewhere is a conflict until resolved.
        hyprctl("eval", "hl.config({ input = { sensitivity = -0.2 } })")
        assert call("Get", "input")["conflicts"] == ["mouse.pointer-speed"]
        call("Set", "mouse.natural-scroll", "true", ok=False)
        call("Resolve", "input", "settings")
        assert json.loads(hyprctl("-j", "getoption", "input:sensitivity"))["float"] == 0.4

        # Shortcuts: conflicts need replace, keycodes become key names, restore reloads.
        add = {"keys": "SUPER + code:24", "action": "command", "command": "true", "description": "Smoke", "replace": False}
        assert "already used" in call("Set", "keyboard-shortcuts.add", json.dumps(add), ok=False)
        lookup = call("Get", "keyboard-shortcuts.lookup:" + json.dumps({"keys": "SUPER + code:24"}))
        assert lookup["keys"] == "SUPER + q" and lookup["conflicts"][0]["description"] == "Window: Close"
        state = call("Set", "keyboard-shortcuts.add", json.dumps({**add, "replace": True}))
        assert state["custom"][0]["keys"] == "SUPER + q" and state["disabled"][0]["keys"] == "SUPER + Q"
        assert [b for b in json.loads(hyprctl("-j", "binds")) if b["key"].lower() == "q"][0]["description"] == "Smoke"
        call("Set", "keyboard-shortcuts.disable", json.dumps({"keys": "SUPER + J", "disabled": True}))
        assert (64, "j") not in binds()
        call("Set", "keyboard-shortcuts.disable", json.dumps({"keys": "SUPER + J", "disabled": False}))
        assert (64, "j") in binds()
        call("Set", "keyboard-shortcuts.remove", json.dumps({"keys": "SUPER + q"}))
        # Window group actions compile and read back as labelled shortcuts.
        for keys, action in [("SUPER + G", "group"), ("SUPER + TAB", "group-next")]:
            state = call("Set", "keyboard-shortcuts.add", json.dumps({**add, "keys": keys, "action": action, "command": ""}))
            assert any(s["action"] == action for s in state["custom"]), state["custom"]
        labels = {e["keys"]: e["actions"] for e in call("Get", "input")["shortcuts"]}
        assert labels["SUPER + g"] == ["Group or ungroup windows"], labels
        assert labels["SUPER + Tab"] == ["Switch tab in group"], labels
        for keys in ["SUPER + g", "SUPER + Tab"]:
            call("Set", "keyboard-shortcuts.remove", json.dumps({"keys": keys}))

        # Recording suspends compositor shortcuts in a pass-through submap.
        call("Set", "keyboard-shortcuts.record", "true")
        assert json.loads(hyprctl("-j", "submap")) == "remya-settings-record"
        call("Set", "keyboard-shortcuts.record", "false")
        assert json.loads(hyprctl("-j", "submap")) == "default"

        # A hand-edited file is never overwritten.
        owned.write_text(owned.read_text() + 'hl.config({ input = { kb_layout = "us" } })\n')
        state = call("Get", "input")
        assert state["write_blocked"], state
        call("Set", "mouse.natural-scroll", "true", ok=False)
        assert owned.read_text().endswith('kb_layout = "us" } })\n')
        print("input smoke test passed")
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
