"""Exercise the real Settings CLI and D-Bus clipboard API against a private Launcher socket."""

import ast
import json
import os
from pathlib import Path
import select
import socketserver
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "build/linux/x64/release/bundle/remya_settings"
BUS = "top.remya.settings.Service1"
OBJECT = "/top/remya/settings"
INTERFACE = "top.remya.settings.Settings1"


class Launcher(socketserver.StreamRequestHandler):
    preferences = {"enabled": True, "maxItems": 500, "retentionDays": 30}
    requests = []

    def handle(self):
        request = json.loads(self.rfile.readline(4096))
        self.requests.append(request)
        if request["op"] == "setPreference":
            self.preferences[request["key"]] = request["value"]
        value = None if request["op"] == "clear" else self.preferences
        self.wfile.write((json.dumps({"ok": True, "value": value}) + "\n").encode())


def command(args, *, error=None):
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    if error:
        assert result.returncode != 0 and error in result.stderr, (args, result)
        return None
    assert result.returncode == 0, (args, result)
    return result.stdout


def cli(*args, error=None):
    output = command([str(BUNDLE), *args], error=error)
    return json.loads(output) if output is not None else None


def dbus(method, *args, error=None):
    output = command(
        ["gdbus", "call", "--session", "--dest", BUS, "--object-path", OBJECT,
         "--method", f"{INTERFACE}.{method}", *args],
        error=error,
    )
    return json.loads(ast.literal_eval(output)[0]) if output is not None else None


def verify():
    service = subprocess.Popen([str(BUNDLE), "--service"])
    try:
        deadline = time.monotonic() + 15
        while True:
            ready = command([
                "gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
                "--object-path", "/org/freedesktop/DBus", "--method",
                "org.freedesktop.DBus.NameHasOwner", BUS,
            ])
            if "(true,)" in ready:
                break
            assert service.poll() is None and time.monotonic() < deadline
            time.sleep(0.05)

        cli("get", "clipboard", error="Unavailable")
        dbus("Set", "clipboard.history-enabled", "false", error="Unavailable")
        socket_path = Path(os.environ["XDG_RUNTIME_DIR"]) / "remya-launcher/clipboard.sock"
        socket_path.parent.mkdir(mode=0o700)
        with socketserver.UnixStreamServer(str(socket_path), Launcher) as launcher:
            thread = threading.Thread(target=launcher.serve_forever)
            thread.start()
            monitor = subprocess.Popen(
                ["gdbus", "monitor", "--session", "--dest", BUS, "--object-path", OBJECT],
                stdout=subprocess.PIPE,
                text=True,
            )
            try:
                assert select.select([monitor.stdout], [], [], 5)[0], "No D-Bus monitor"
                monitor.stdout.readline()
                assert cli("get", "clipboard") == dbus("Get", "clipboard")
                for key, value, wire_key, expected in (
                    ("history-enabled", "false", "enabled", False),
                    ("max-items", "123", "maxItems", 123),
                    ("retention-days", "14", "retentionDays", 14),
                ):
                    id = f"clipboard.{key}"
                    reply = cli("set", id, value)
                    assert reply == dbus("Get", id) and reply["value"] == expected
                    assert dbus("Set", id, value) == cli("get", id)
                    assert Launcher.preferences[wire_key] == expected
                before = len(Launcher.requests)
                cli("set", "clipboard.max-items", "5001", error="InvalidArgument")
                dbus("Set", "clipboard.retention-days", "0", error="InvalidArgument")
                dbus("Set", "clipboard.clear-history", "false", error="InvalidArgument")
                assert len(Launcher.requests) == before
                assert cli("set", "clipboard.clear-history", "true")["value"] is None
                assert Launcher.requests[-1] == {"op": "clear"}
                assert select.select([monitor.stdout], [], [], 5)[0], "No Settings signals"
            finally:
                monitor.terminate()
                signals = monitor.communicate(timeout=5)[0]
                launcher.shutdown()
                thread.join()
            for id in ("history-enabled", "max-items", "retention-days", "clear-history"):
                assert f".Changed ('clipboard.{id}'," in signals, signals
        cli("get", "clipboard", error="Unavailable")
    finally:
        service.terminate()
        service.wait(timeout=10)


def main():
    if "--session" in sys.argv:
        verify()
        return
    with tempfile.TemporaryDirectory(prefix="remya-clipboard-") as temp:
        root = Path(temp)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ, HOME=temp, GSETTINGS_BACKEND="keyfile",
                           GIO_USE_VFS="local", XDG_RUNTIME_DIR=str(runtime))
        for name in ("CONFIG", "CACHE", "DATA", "STATE"):
            environment[f"XDG_{name}_HOME"] = str(root / name.lower())
        environment.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        environment.pop("WAYLAND_DISPLAY", None)
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--session"],
                       env=environment, check=True, timeout=60)
    print("PASS: Settings clipboard CLI/D-Bus parity, live readback, Changed and validation")


if __name__ == "__main__":
    main()
