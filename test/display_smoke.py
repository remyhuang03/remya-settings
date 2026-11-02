#!/usr/bin/env python3
"""End-to-end display check: the real service against a nested Hyprland.

Runs a nested compositor with headless outputs, a private session bus, and isolated
XDG roots, so the user's displays and configuration are never touched. A small
nested window appears for the duration of the test.

    python test/display_smoke.py [path/to/remya-settings-service]
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
SCALE, TRANSFORM, LAYOUT = "display.12e2ed4d", "display.9843ad76", "display.7cb5dc06"
POSITION, RESERVED = "display.position", "display.reserved-area"


def run(*args, env=None, check=True):
    return subprocess.run(args, env=env, check=check, capture_output=True, text=True, timeout=30)


def main():
    home = Path(tempfile.mkdtemp(prefix="remya-display-smoke-"))
    config = home / "config"
    hypr = config / "hypr"
    hypr.mkdir(parents=True)
    (hypr / "monitors.lua").write_text('-- user comment\nhl.monitor({ output = "ABSENT-1", scale = 2 })\n')
    (hypr / "hyprland.lua").write_text(
        'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n'
        'hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })\n'
        'require("monitors")\n'
    )
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
            live = {i["instance"] for i in json.loads(run("hyprctl", "-j", "instances").stdout)}
            if new := live - before:
                instance = new.pop()
                break
        assert instance, "nested Hyprland did not start"
        time.sleep(1)

        def hypr_ctl(*args):
            return run("hyprctl", "-i", instance, *args).stdout

        def monitors():
            return {m["name"]: m for m in json.loads(hypr_ctl("-j", "monitors", "all"))}

        hypr_ctl("output", "create", "headless", "SMOKE-1")
        hypr_ctl("output", "create", "headless", "SMOKE-2")
        time.sleep(1)
        assert {"SMOKE-1", "SMOKE-2"} <= set(monitors())

        bus = subprocess.Popen(
            ["dbus-daemon", "--session", "--print-address", "--nofork"],
            stdout=subprocess.PIPE, text=True,
        )
        address = bus.stdout.readline().strip()
        env = {
            **os.environ,
            "DBUS_SESSION_BUS_ADDRESS": address,
            "HYPRLAND_INSTANCE_SIGNATURE": instance,
            "XDG_CONFIG_HOME": str(config),
            "HOME": str(home),
            "GSETTINGS_BACKEND": "keyfile",
        }
        service = subprocess.Popen([str(SERVICE)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

        def call(method, *args, ok=True):
            result = run("gdbus", "call", *DEST, "--method", METHOD + method, *args, env=env, check=False)
            if result.returncode:
                assert not ok, f"{method} {args}: {result.stderr}"
                return result.stderr
            assert ok, f"{method} {args} should have failed: {result.stdout}"
            # gdbus prints a GVariant string tuple; values here contain no quotes of that kind.
            text = result.stdout.strip()[2:-3]
            return json.loads(text.encode().decode("unicode_escape"))

        for _ in range(100):
            time.sleep(0.1)
            if run("gdbus", "call", *DEST, "--method", METHOD + "Get", "about", env=env, check=False).returncode == 0:
                break

        def state():
            return call("Get", "display")

        def output(name, data=None):
            return next(o for o in (data or state())["outputs"] if o["name"] == name)

        def request(name, value, confirm=None):
            body = {"output": name, "value": value}
            if confirm is not None:
                body["confirm_seconds"] = confirm
            return json.dumps(body)

        rules = hypr / "monitors.lua"
        saved = config / "remya/settings/display.toml"

        # First use adopts the system and writes nothing to it.
        data = state()
        assert data["error"] is None and data["write_blocked"] is None, data
        assert not data["conflict"] and saved.exists()
        assert rules.read_text().startswith("-- user comment"), "rule file changed on first use"
        assert "SMOKE" not in rules.read_text()

        # A confirmed change: live immediately, on disk only after Keep.
        wanted = "1.25" if "1.25" in output("SMOKE-1", data)["scale_options"] else output("SMOKE-1", data)["scale_options"][1]
        data = call("Set", SCALE, request("SMOKE-1", wanted, 15))
        assert data["pending"]["output"] == "SMOKE-1"
        assert abs(monitors()["SMOKE-1"]["scale"] - float(wanted)) < 0.01
        assert "SMOKE-1" not in rules.read_text()
        assert "previous display change" in call("Set", TRANSFORM, request("SMOKE-2", "1"), ok=False)
        call("Resolve", "display", "keep")
        assert "SMOKE-1" in rules.read_text()
        assert "-- user comment" in rules.read_text() and "ABSENT-1" in rules.read_text()
        assert (hypr / "monitors.lua.remya-backup").read_text().startswith("-- user comment")
        data = state()
        assert not data["conflict"], [o["conflict_fields"] for o in data["outputs"]]

        # Revert restores; an unanswered confirmation restores itself.
        call("Set", TRANSFORM, request("SMOKE-2", "1", 15))
        assert monitors()["SMOKE-2"]["transform"] == 1
        call("Resolve", "display", "revert")
        assert monitors()["SMOKE-2"]["transform"] == 0
        assert "transform" not in rules.read_text()
        call("Set", TRANSFORM, request("SMOKE-2", "3", 2))
        assert monitors()["SMOKE-2"]["transform"] == 3
        time.sleep(4)
        assert monitors()["SMOKE-2"]["transform"] == 0, "pending change did not expire"
        assert state()["pending"] is None
        assert "transform" not in rules.read_text()

        # Immediate settings persist at once, and a real config reload reproduces them.
        call("Set", POSITION, request("SMOKE-2", "5000x300"))
        call("Set", RESERVED, request("SMOKE-2", "1 2 3 4"))
        assert (monitors()["SMOKE-2"]["x"], monitors()["SMOKE-2"]["y"]) == (5000, 300)
        checked = run("Hyprland", "--verify-config", "--config", str(hypr / "hyprland.lua"), check=False,
                      env={**os.environ, "XDG_CONFIG_HOME": str(config)})
        assert "error" not in checked.stdout.lower().replace("no errors", ""), checked.stdout
        hypr_ctl("eval", 'hl.monitor({output="SMOKE-2",position="6000x0"})')
        time.sleep(0.5)
        hypr_ctl("reload")
        time.sleep(1.5)
        assert (monitors()["SMOKE-2"]["x"], monitors()["SMOKE-2"]["y"]) == (5000, 300), "rule did not survive reload"
        assert abs(monitors()["SMOKE-1"]["scale"] - float(wanted)) < 0.01
        assert not state()["conflict"]

        # Fields without live readback are confirmed through the rule file.
        icc = home / "profile.icc"
        icc.write_bytes(b"")
        for setting, value, literal in (
            ("display.2d80c2c4", "0", "vrr = 0"),
            ("display.sdr-eotf", "gamma22", 'sdr_eotf = "gamma22"'),
            ("display.supports-hdr", "-1", "supports_hdr = -1"),
            ("display.supports-wide-color", "-1", "supports_wide_color = -1"),
            ("display.min-luminance", "0", "min_luminance = 0"),
            ("display.max-luminance", "400", "max_luminance = 400"),
            ("display.max-avg-luminance", "300", "max_avg_luminance = 300"),
            ("display.sdrbrightness", "1.2", "sdrbrightness = 1.2"),
            ("display.sdrsaturation", "0.9", "sdrsaturation = 0.9"),
            ("display.sdr-min-luminance", "0.5", "sdr_min_luminance = 0.5"),
            ("display.sdr-max-luminance", "100", "sdr_max_luminance = 100"),
            ("display.91720250", "10", "bitdepth = 10"),
        ):
            call("Set", setting, request("SMOKE-1", value))
            assert literal in rules.read_text(), literal
            assert not state()["conflict"], setting
        assert monitors()["SMOKE-1"]["sdrBrightness"] == 1.2
        assert "2101010" in monitors()["SMOKE-1"]["currentFormat"]
        call("Set", "display.2d80c2c4", request("SMOKE-1", ""))
        assert "vrr" not in rules.read_text()
        assert "InvalidArgument" in call("Set", "display.2d80c2c4", request("SMOKE-1", "1"), ok=False)
        assert "not an ICC profile" in call("Set", "display.icc", request("SMOKE-1", str(icc)), ok=False)
        assert str(icc) not in rules.read_text(), "a rejected ICC profile was persisted"
        hypr_ctl("reload")
        time.sleep(1.5)
        assert monitors()["SMOKE-1"]["sdrBrightness"] == 1.2
        assert not state()["conflict"]

        # An external change is a conflict; both choices resolve it.
        hypr_ctl("eval", 'hl.monitor({output="SMOKE-2",transform=2})')
        time.sleep(0.5)
        data = state()
        assert data["conflict"] and output("SMOKE-2", data)["conflict_fields"] == ["transform"]
        call("Resolve", "display", "settings")
        assert monitors()["SMOKE-2"]["transform"] == 0 and not state()["conflict"]
        hypr_ctl("eval", 'hl.monitor({output="SMOKE-2",transform=2})')
        time.sleep(0.5)
        call("Resolve", "display", "system")
        assert monitors()["SMOKE-2"]["transform"] == 2 and not state()["conflict"]
        hypr_ctl("eval", 'hl.monitor({output="SMOKE-2",transform=0})')
        time.sleep(0.5)
        call("Resolve", "display", "system")

        # Mirroring and disabling, with the last display protected.
        call("Set", LAYOUT, request("SMOKE-2", "mirror:SMOKE-1"))
        assert monitors()["SMOKE-2"]["mirrorOf"] != "none"
        call("Set", LAYOUT, request("SMOKE-2", "extend"))
        assert monitors()["SMOKE-2"]["mirrorOf"] == "none"
        # The nested window may add its own output, so stop using every other one.
        others = [name for name in monitors() if name != "SMOKE-1"]
        for name in others:
            call("Set", LAYOUT, request(name, "disable"))
            assert monitors()[name]["disabled"]
        assert "must stay in use" in call("Set", LAYOUT, request("SMOKE-1", "disable"), ok=False)
        for name in others:
            call("Set", LAYOUT, request(name, "extend"))
            assert not monitors()[name]["disabled"]

        # Parity with catalog metadata and errors.
        value = call("Get", SCALE)
        assert value["availability"] == "available" and "SMOKE-1" in value["value"]
        for bad in (request("SMOKE-1", "x"), "not json", request("NOPE", "1")):
            assert "InvalidArgument" in call("Set", TRANSFORM, bad, ok=False)
        assert "Unavailable" in call("Set", "night-light.50840111", "Set hours", ok=False)
        assert call("Get", "configuration")["display"]["conflict"] is False

        # Malformed user files block writes without being replaced.
        original = rules.read_text()
        rules.write_text(original + "\nos.execute('x')\n")
        data = state()
        assert "cannot safely edit" in data["write_blocked"]
        call("Set", TRANSFORM, request("SMOKE-1", "1"), ok=False)
        assert monitors()["SMOKE-1"]["transform"] == 0
        assert "os.execute" in rules.read_text()
        rules.write_text(original)
        assert state()["write_blocked"] is None

        call("Quit")
        print("display smoke test passed")
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
