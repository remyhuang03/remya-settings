#!/usr/bin/env python3
"""End-to-end desktop options check: blur, fallback background and display wake.

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

        # A live change made elsewhere is a conflict; adopting it rewrites only the saved copy.
        hyprctl("eval", "hl.config({ decoration = { blur = { passes = 2 } } })")
        assert call("Get", "desktop")["conflicts"] == ["background.blur-passes"]
        call("Set", "background.blur-xray", "true", ok=False)
        call("Resolve", "desktop", "system")
        state = call("Get", "desktop")
        assert not state["conflict"] and state["saved"]["background.blur-passes"] == 2

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
