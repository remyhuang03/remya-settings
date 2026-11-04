"""System updates and active hours CLI/D-Bus parity on a private session bus; never upgrades."""
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


def stop(service):
    call('Quit'); service.wait(timeout=10)


def check_parity():
    service, state = launch()
    try:
        assert state['phase'] == 'idle' and not state['busy']
        assert not state['missing'], state['missing']
        assert state['updater'] in ('installed', 'missing', 'outdated')
        assert cli('get', 'updates')['phase'] == 'idle'
        assert call('Get', 'updates.status')['id'] == 'updates.status'
        assert 'ReadOnly' in call('Set', 'updates.output', 'clear', ok=False)
        if state['updater'] != 'installed':
            # Never call upgrade when the real updater is installed: it would upgrade this machine.
            assert 'Unavailable' in call('Set', 'updates.upgrade', 'upgrade', ok=False)
        assert call('Get', 'updates.upgrade')['availability'] == 'available'
        assert cli('set', 'updates.include-held', 'true')['all']
        assert call('Set', 'updates.include-held', 'false')['all'] is False
        assert call('Set', 'updates.retry', 'true')['retry']
        assert not cli('set', 'updates.retry', 'false')['retry']
        assert cli('set', 'updates.check', 'check')['kind'] == 'check'
        deadline = time.monotonic() + 120
        state = call('Get', 'updates')
        while state['busy']:
            assert time.monotonic() < deadline, state
            time.sleep(.25)
            state = call('Get', 'updates')
        assert state['phase'] == 'completed', state
        assert state['checked_at'] and state['output']
        assert all(package['name'] and package['installed'] and package['available'] for package in state['packages'])
        print(json.dumps({'result': 'PASS', 'phase': state['phase'], 'packages': len(state['packages']),
                          'held_candidates': sum(p['held'] for p in state['packages'])}))
        stop(service)
    finally:
        if service.poll() is None:
            service.terminate(); service.wait(timeout=10)


def schedule_checks():
    # Active hours always cover the test, so enabling never starts a real upgrade.
    now = time.localtime()
    minute = now.tm_hour * 60 + now.tm_min
    start, end = (f'{m // 60 % 24:02}:{m % 60:02}' for m in ((minute - 60) % 1440, (minute + 120) % 1440))
    service = None
    try:
        service, state = launch()
        assert state['schedule']['enabled'] is False
        assert cli('set', 'active-hours.e8868af6', start)['schedule']['active_start'] == start
        assert call('Set', 'active-hours.a0bb9f49', end)['schedule']['active_end'] == end
        assert 'InvalidArgument' in call('Set', 'active-hours.a0bb9f49', '25:00', ok=False)
        assert 'InvalidArgument' in call('Set', 'active-hours.a0bb9f49', start, ok=False)
        enabled = call('Set', 'updates.automatic', 'true')['schedule']
        assert enabled['enabled'] and enabled['last_run_day'], enabled
        assert call('Get', 'updates')['phase'] == 'idle'
        stop(service); service = None
        service, state = launch()
        assert state['schedule']['enabled'] and state['schedule']['active_start'] == start
        assert not state['busy']
        assert not cli('set', 'updates.automatic', 'false')['schedule']['enabled']
        stop(service); service = None
        configuration = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/updates.json'
        configuration.write_text('{broken configuration')
        service, state = launch()
        assert state['schedule']['error'] and state['schedule']['editable'] is False
        call('Set', 'updates.automatic', 'true', ok=False)
        assert configuration.read_text() == '{broken configuration'
        stop(service); service = None
        print('PASS: active hours and schedule writes, restart persistence, invalid input and malformed file protection; no upgrade started')
    finally:
        if service is not None and service.poll() is None:
            service.terminate(); service.wait(timeout=10)


if __name__ == '__main__':
    if '--session' in sys.argv:
        check_parity()
        schedule_checks()
    else:
        with tempfile.TemporaryDirectory(prefix='remya-updates-') as temporary:
            environment = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary + '/config',
                XDG_DATA_HOME=temporary + '/data', XDG_CACHE_HOME=temporary + '/cache',
                XDG_STATE_HOME=temporary + '/state', GSETTINGS_BACKEND='keyfile',
                GIO_USE_VFS='local', NO_AT_BRIDGE='1', GTK_USE_PORTAL='0')
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session'], env=environment,
                           check=True, timeout=200)
