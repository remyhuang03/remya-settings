"""Persisted schedule parity on a private bus, with no authorization or upgrades."""
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / 'target/debug/remya-settings-service'
CLI = ROOT / 'build/linux/x64/release/bundle/libexec/remya_settings_cli'


def call(method, *args, ok=True):
    result = subprocess.run(['gdbus', 'call', '--session', '--dest', 'top.remya.settings.Service1',
        '--object-path', '/top/remya/settings', '--method', f'top.remya.settings.Settings1.{method}',
        *args], capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) == ok, (result.stdout, result.stderr)
    return json.loads(ast.literal_eval(result.stdout)[0]) if ok else result.stderr


def cli(*args):
    result = subprocess.run([str(CLI), *args], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def launch():
    service = subprocess.Popen([str(SERVICE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 10
    while True:
        try:
            return service, call('Get', 'updates')
        except AssertionError:
            if time.monotonic() >= deadline:
                service.terminate(); service.wait(timeout=10)
                raise
            time.sleep(.1)


def session():
    # Active hours always cover the test, so enabling never starts a real upgrade.
    now = time.localtime()
    minute = now.tm_hour * 60 + now.tm_min
    start, end = (f'{m // 60 % 24:02}:{m % 60:02}' for m in ((minute - 60) % 1440, (minute + 120) % 1440))
    service = None
    try:
        service, state = launch()
        assert state['schedule']['enabled'] is False
        assert not state['busy'] and state['phase'] == 'idle'
        assert cli('set', 'active-hours.e8868af6', start)['schedule']['active_start'] == start
        assert call('Set', 'active-hours.a0bb9f49', end)['schedule']['active_end'] == end
        assert 'InvalidArgument' in call('Set', 'active-hours.a0bb9f49', '25:00', ok=False)
        assert 'InvalidArgument' in call('Set', 'active-hours.a0bb9f49', start, ok=False)
        assert call('Get', 'updates')['schedule']['active_end'] == end
        enabled = call('Set', 'updates.automatic', 'true')['schedule']
        assert enabled['enabled'] and enabled['last_run_day'], enabled
        assert call('Get', 'updates')['phase'] == 'idle'
        call('Quit'); service.wait(timeout=10); service = None
        service, state = launch()
        assert state['schedule']['enabled'] and state['schedule']['active_start'] == start
        assert not state['busy']
        assert not cli('set', 'updates.automatic', 'false')['schedule']['enabled']
        call('Quit'); service.wait(timeout=10); service = None
        configuration = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/updates.json'
        configuration.write_text('{broken configuration')
        service, state = launch()
        assert state['schedule']['error'] and not state['schedule']['enabled']
        assert state['schedule']['editable'] is False
        call('Set', 'updates.automatic', 'true', ok=False)
        assert configuration.read_text() == '{broken configuration'
        assert not call('Get', 'updates')['busy']
        call('Quit'); service.wait(timeout=10); service = None
        print('PASS: default off, CLI/D-Bus active hours and schedule writes, restart persistence, invalid input retention, malformed file protection; no check or upgrade started')
    finally:
        if service is not None and service.poll() is None:
            service.terminate(); service.wait(timeout=10)


if __name__ == '__main__':
    if '--session' in sys.argv:
        session()
    else:
        with tempfile.TemporaryDirectory(prefix='remya-updates-schedule-') as temporary:
            environment = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary + '/config',
                XDG_DATA_HOME=temporary + '/data', XDG_CACHE_HOME=temporary + '/cache',
                XDG_STATE_HOME=temporary + '/state', GSETTINGS_BACKEND='keyfile',
                GIO_USE_VFS='local', NO_AT_BRIDGE='1', GTK_USE_PORTAL='0')
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session'], env=environment,
                           check=True, timeout=60)
