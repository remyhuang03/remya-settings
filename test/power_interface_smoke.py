"""Run on a private session bus with isolated XDG roots and copied hypridle.conf.

Usage: dbus-run-session -- python test/power_interface_smoke.py
Uses the release bundle; reads real hardware but never writes host settings.
"""
import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / 'build/linux/x64/release/bundle'
BUS = 'top.remya.settings.Service1'

def call(method, *args):
    text = subprocess.check_output(['gdbus', 'call', '--session', '--dest', BUS,
        '--object-path', '/top/remya/settings', '--method',
        f'top.remya.settings.Settings1.{method}', *args], text=True, stderr=subprocess.PIPE)
    return json.loads(ast.literal_eval(text)[0])

with tempfile.TemporaryDirectory(prefix='remya-power-api-') as directory:
    root = Path(directory)
    original = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'hypr/hypridle.conf'
    config = root / 'config'
    (config / 'hypr').mkdir(parents=True)
    shutil.copyfile(original, config / 'hypr/hypridle.conf')
    env = os.environ | {'XDG_CONFIG_HOME': str(config), 'XDG_STATE_HOME': str(root / 'state'),
        'XDG_DATA_HOME': str(root / 'data'), 'XDG_CACHE_HOME': str(root / 'cache')}
    log = open(root / 'service.log', 'w+')
    service = subprocess.Popen([str(BUNDLE / 'libexec/remya-settings-service')], env=env, stdout=log, stderr=log)
    try:
        for _ in range(100):
            try:
                owner = subprocess.check_output(['gdbus','call','--session','--dest','org.freedesktop.DBus','--object-path','/org/freedesktop/DBus','--method','org.freedesktop.DBus.NameHasOwner',BUS],text=True)
                if 'true' not in owner:
                    time.sleep(.1)
                    continue
                state = call('Get', 'power')
                break
            except subprocess.CalledProcessError:
                time.sleep(.1)
        else:
            raise AssertionError('service not ready')
        assert state['available'] and state['error'] is None, state
        cli = subprocess.check_output([str(BUNDLE / 'libexec/remya_settings_cli'), 'get', 'power'], env=env, text=True)
        assert json.loads(cli)['system']['profile'] == state['system']['profile']
        assert call('Resolve', 'power', 'system')['conflict'] is False
        assert call('Set', 'battery-saver.power-source', 'false')['saved']['include_ac'] is False
        auto_on = 'battery-saver.9b0caf70'
        auto_off = 'battery-saver.off-threshold'
        cli = [str(BUNDLE / 'libexec/remya_settings_cli')]
        assert call('Get', auto_off)['value'] == -1
        assert call('Set', auto_off, '80')['saved']['off_threshold'] == 80
        assert json.loads(subprocess.check_output([*cli, 'get', auto_off], env=env))['value'] == 80
        subprocess.run([*cli, 'set', auto_off, '0'], env=env, check=True, stdout=subprocess.DEVNULL)
        assert call('Get', auto_off)['value'] == 0
        assert call('Set', auto_on, 'false')['saved']['threshold'] == 0
        saved = json.loads((config / 'remya/settings/power.json').read_text())
        assert saved['threshold'] == 0 and saved['off_threshold'] == 0
        try:
            call('Set', auto_on, '101')
            raise AssertionError('invalid threshold accepted')
        except subprocess.CalledProcessError:
            pass
        result = call('Get', 'battery-history:' + json.dumps({'from': 0, 'to': int(time.time()) + 1}))
        assert result['observations'], result
        assert list((root / 'state/remya/settings').glob('power.sqlite3'))
        call('Quit')
        service.wait(timeout=15)
        import sqlite3
        with sqlite3.connect(root / 'state/remya/settings/power.sqlite3') as db:
            assert db.execute("SELECT value FROM observations WHERE kind='session' ORDER BY id DESC LIMIT 1").fetchone()[0] == '"stop"'
        print('Power CLI/D-Bus readback, validation, persistence, SQLite query and clean stop passed')
    finally:
        if service.poll() is None:
            service.terminate()
            service.wait(timeout=15)
        log.close()
