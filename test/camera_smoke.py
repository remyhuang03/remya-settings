"""Camera CLI/D-Bus parity on a private bus/PipeWire, without hardware monitors."""
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUS = 'top.remya.settings.Service1'
API = 'top.remya.settings.Settings1'

def run(*args, ok=True):
    p = subprocess.run(args, capture_output=True, text=True, timeout=30)
    assert (p.returncode == 0) == ok, (args, p.stdout, p.stderr)
    return p.stdout if ok else p.stderr

def check(profile, cli):
    children = []
    def start(*args):
        p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        children.append(p)
        return p
    def dbus(method, *args, ok=True):
        output = run('gdbus', 'call', '--session', '--dest', BUS, '--object-path', '/top/remya/settings', '--method', f'{API}.{method}', *args, ok=ok)
        return json.loads(ast.literal_eval(output)[0]) if ok else output
    def command(*args, ok=True):
        output = run(cli, *args, ok=ok)
        return json.loads(output) if ok else output
    try:
        start('pipewire')
        deadline = time.monotonic() + 10
        while not (Path(os.environ['XDG_RUNTIME_DIR']) / 'pipewire-0').exists():
            assert time.monotonic() < deadline
            time.sleep(.05)
        start(str(ROOT / f'target/{profile}/remya-settings-service'))
        while True:
            try:
                state = dbus('Get', 'cameras')
                break
            except AssertionError:
                assert time.monotonic() < deadline
                time.sleep(.1)
        signals = tempfile.TemporaryFile(mode='w+t')
        monitor = subprocess.Popen(['gdbus', 'monitor', '--session', '--dest', BUS, '--object-path', '/top/remya/settings'], stdout=signals, stderr=subprocess.DEVNULL)
        children.append(monitor)
        time.sleep(.15)
        assert state == command('get', 'cameras')
        assert state['available'] and state['initialized'] and state['devices'] == []
        assert command('get', 'cameras.devices')['id'] == 'cameras.devices'
        assert 'ReadOnly' in command('set', 'cameras.devices', '{}', ok=False)
        for setting, body in [('cameras.brightness', '{"camera":"missing","serial":1,"value":2}'), ('cameras.reset', '{}')]:
            a = command('set', setting, body, ok=False)
            b = dbus('Set', setting, body, ok=False)
            assert ('identity' in a and 'identity' in b) or ('InvalidArgument' in a and 'InvalidArgument' in b), (a,b)
        for source in ['system', 'settings']:
            assert 'no longer available' in command('resolve', 'cameras:missing', source, ok=False)
        for page in ['pen', 'pen-shortcuts', 'recovery']:
            assert 'Unknown page' in command('get', f'page:{page}', ok=False)
        assert command('get', 'configuration')['cameras']['devices'] == []
        config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/cameras.toml'
        assert config.exists()
        signals.seek(0)
        assert "Changed ('cameras'" in signals.read(), 'Missing camera change notification'
        signals.close()
        command('quit')
        print('PASS Camera CLI/D-Bus parity, initialization, validation and removed pages')
    finally:
        for p in reversed(children):
            p.terminate()
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--inside':
        check(sys.argv[2], sys.argv[3]); return
    profile = sys.argv[1] if len(sys.argv)>1 else 'debug'
    assert profile in ('debug', 'release')
    cli = ROOT / 'build/linux/x64/release/bundle/libexec/remya_settings_cli'
    with tempfile.TemporaryDirectory(prefix='remya-camera-api-') as tmp:
        env = os.environ.copy()
        env.update(HOME=tmp, XDG_CONFIG_HOME=f'{tmp}/config', XDG_DATA_HOME=f'{tmp}/data', XDG_STATE_HOME=f'{tmp}/state', XDG_CACHE_HOME=f'{tmp}/cache', XDG_RUNTIME_DIR=tmp, PIPEWIRE_RUNTIME_DIR=tmp, PIPEWIRE_REMOTE='pipewire-0', GSETTINGS_BACKEND='keyfile', HYPRLAND_INSTANCE_SIGNATURE='', DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={tmp}/no-system-bus')
        subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--inside', profile, str(cli)], env=env, cwd=ROOT, check=True, timeout=60)
if __name__ == '__main__': main()
