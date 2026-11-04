"""Read-only updater parity on a private session bus; never starts an upgrade."""
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


def session():
    service = subprocess.Popen([str(SERVICE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def dbus(method, *args, ok=True):
        result = subprocess.run(['gdbus', 'call', '--session', '--dest', 'top.remya.settings.Service1',
            '--object-path', '/top/remya/settings', '--method', f'top.remya.settings.Settings1.{method}',
            *args], capture_output=True, text=True, timeout=10)
        assert (result.returncode == 0) == ok, (result.stdout, result.stderr)
        return json.loads(ast.literal_eval(result.stdout)[0]) if ok else result.stderr

    def cli(*args):
        result = subprocess.run([str(CLI), *args], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)

    try:
        deadline = time.monotonic() + 10
        while True:
            try:
                state = dbus('Get', 'updates')
                break
            except AssertionError:
                assert time.monotonic() < deadline
                time.sleep(.1)
        assert state['phase'] == 'idle' and not state['busy']
        assert not state['missing'], state['missing']
        assert state['updater'] in ('installed', 'missing', 'outdated')
        assert cli('get', 'updates')['phase'] == 'idle'
        assert dbus('Get', 'updates.status')['id'] == 'updates.status'
        assert 'ReadOnly' in dbus('Set', 'updates.output', 'clear', ok=False)
        if state['updater'] != 'installed':
            # Never call upgrade when the real updater is installed: it would upgrade this machine.
            assert 'Unavailable' in dbus('Set', 'updates.upgrade', 'upgrade', ok=False)
        assert dbus('Get', 'updates.upgrade')['availability'] == 'available'
        assert cli('set', 'updates.include-held', 'true')['all']
        assert dbus('Set', 'updates.include-held', 'false')['all'] is False
        assert dbus('Set', 'updates.retry', 'true')['retry']
        assert not cli('set', 'updates.retry', 'false')['retry']
        assert not dbus('Get', 'updates')['busy']
        assert cli('set', 'updates.check', 'check')['busy']
        state = dbus('Get', 'updates')
        assert state['kind'] == 'check'
        if state['busy']:
            assert 'Busy' in dbus('Quit', ok=False)
            assert dbus('Get', 'theme')
        deadline = time.monotonic() + 120
        while state['busy']:
            assert time.monotonic() < deadline, state
            time.sleep(.25)
            state = dbus('Get', 'updates')
        assert state['phase'] == 'completed', state
        assert state['checked_at'] and state['output']
        assert all(package['name'] and package['installed'] and package['available'] for package in state['packages'])
        print(json.dumps({'result': 'PASS', 'phase': state['phase'], 'packages': len(state['packages']),
                          'held_candidates': sum(p['held'] for p in state['packages']), 'output_lines': len(state['output'])}))
        dbus('Quit')
        service.wait(timeout=10)
    finally:
        if service.poll() is None:
            service.terminate()
            service.wait(timeout=10)


if __name__ == '__main__':
    if '--session' in sys.argv:
        session()
    else:
        with tempfile.TemporaryDirectory(prefix='remya-updates-check-') as temporary:
            environment = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary + '/config',
                XDG_DATA_HOME=temporary + '/data', XDG_CACHE_HOME=temporary + '/cache',
                XDG_STATE_HOME=temporary + '/state', GSETTINGS_BACKEND='keyfile',
                GIO_USE_VFS='local', NO_AT_BRIDGE='1', GTK_USE_PORTAL='0')
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session'], env=environment,
                           check=True, timeout=150)
