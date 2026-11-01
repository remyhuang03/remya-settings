"""Exercise the installed CLI and D-Bus API in isolated XDG and session-bus state.

Requires both release bundles and a running graphical session. System appearance
writes stay inside a temporary HOME/config root and the keyfile GSettings backend.
"""
import ast
import json
import io
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import tempfile
import time

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUS = 'top.remya.settings.Service1'
INTERFACE = 'top.remya.settings.Settings1'
OBJECT = '/top/remya/settings'


def cli(*args, ok=True):
    executable = Path(os.environ['HOME']) / '.local/bin/remya_settings'
    result = subprocess.run([str(executable), *args], capture_output=True, text=True, timeout=40)
    assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
    return json.loads(result.stdout) if ok else result.stderr


def dbus(method, *args):
    result = subprocess.check_output([
        'gdbus', 'call', '--session', '--dest', BUS, '--object-path', OBJECT,
        '--method', f'{INTERFACE}.{method}', *args,
    ], text=True, timeout=40)
    return json.loads(ast.literal_eval(result)[0])


def service_pid():
    result = subprocess.check_output([
        'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
        '--object-path', '/org/freedesktop/DBus',
        '--method', 'org.freedesktop.DBus.GetConnectionUnixProcessID', BUS,
    ], text=True)
    return int(re.search(r'uint32 (\d+)', result)[1])


def session_checks():
    pid = None
    watcher = None
    bar = None
    before = None
    try:
        initial = cli('get', 'theme')
        pid = service_pid()
        assert initial == dbus('Get', 'theme')
        clock = cli('get', 'date-time')
        zone_options = cli('get', 'timezones')
        zones = zone_options['options']
        assert all('(GMT' in zone_options['labels'][zone] for zone in zones)
        assert cli('get', 'time-locales')['options']
        for setting in ['date-time.db451de3', 'date-time.098d06ec', 'date-time.7e33a213', 'date-time.format']:
            assert cli('get', setting)['value'] == dbus('Get', setting)['value']
        assert 'InvalidArgument' in cli('set', 'date-time.7e33a213', '["https://invalid"]', ok=False)
        assert clock['timezone'] in zones and clock['saved_timezone'] == clock['timezone']
        assert not clock['conflict'] and int(clock['unix_micros']) > 0
        assert cli('get', 'date-time.fb2a23dc')['value'] == clock['timezone']
        assert 'InvalidArgument' in cli('set', 'date-time.fb2a23dc', 'Invalid/Zone', ok=False)
        assert 'InvalidArgument' in cli('set', 'date-time.6422d209', '{}', ok=False)
        zone_config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/date-time.toml'
        alternate = next(zone for zone in zones if zone != clock['timezone'])
        zone_config.write_text('version = 1\ntimezone = ' + json.dumps(alternate) + '\n')
        assert cli('get', 'configuration')['date-time']['conflict']
        assert not cli('resolve', 'date-time', 'system')['date-time']['conflict']
        assert cli('get', 'date-time')['timezone'] == clock['timezone']
        assert not any(client['pid'] == pid for client in json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))), 'Background service showed a window'
        assert cli('set', 'themes.material-style-variant', 'vibrant')['theme']['style_variant'] == 'vibrant'
        assert dbus('Set', 'themes.material-theme-mode', 'dark')['theme']['theme_mode'] == 'dark'
        assert cli('get', 'system')['mode'] == 'dark'
        controls = cli('list')['controls']
        assert len([control for control in controls if control['availability'] == 'available']) == 37
        unavailable = next(control for control in controls if control['availability'] != 'available')
        assert 'Unavailable' in cli('set', unavailable['id'], 'true', ok=False)
        assert 'InvalidArgument' in cli('set', 'themes.material-theme-mode', 'system', ok=False)
        assert cli('get', unavailable['id'])['availability'] != 'available'
        assert cli('get', 'catalog')['pages']
        assert cli('search', 'material')['pages']
        assert cli('reload')['theme'] == dbus('Get', 'theme')
        executable = Path(os.environ['HOME']) / '.local/bin/remya_settings'
        watcher = subprocess.Popen([str(executable), 'watch', 'all'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert select.select([watcher.stdout], [], [], 5)[0], 'No initial watch state'
        assert json.loads(watcher.stdout.readline())['topic'] == 'theme'
        time.sleep(0.2)
        dbus('Set', 'themes.material-style-variant', 'neutral')
        assert select.select([watcher.stdout], [], [], 5)[0], 'No D-Bus theme signal'
        assert json.loads(watcher.stdout.readline())['value']['theme']['style_variant'] == 'neutral'
        config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/config.toml'
        valid = config.read_text()
        config.write_text('invalid TOML [')
        time.sleep(1)
        assert 'OperationFailed' in cli('get', 'theme', ok=False)
        assert config.read_text() == 'invalid TOML ['
        config.write_text(valid)
        time.sleep(1)
        assert cli('get', 'theme')['theme']['style_variant'] == 'neutral'
        # The release bar must consume the service, with one view on every output.
        before = {monitor['name']: monitor['reserved'] for monitor in json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))}
        bar = subprocess.Popen([str(Path(os.environ['HOME']) / '.local/bin/remya_bar')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 10
        bars = []
        while time.monotonic() < deadline:
            layers = json.loads(subprocess.check_output(['hyprctl', 'layers', '-j']))
            bars = [layer for monitor in layers.values() for level in monitor['levels'].values() for layer in level if layer['pid'] == bar.pid]
            if len(bars) == len(before):
                break
            assert bar.poll() is None, 'Installed bar exited'
            time.sleep(0.1)
        assert len(bars) == len(before)
        assert all(layer['namespace'] == 'top.remya.bar' and layer['h'] == 40 for layer in bars)
        assert not any(client['pid'] == bar.pid for client in json.loads(subprocess.check_output(['hyprctl', 'clients', '-j'])))
        time.sleep(1)
        def samples():
            colors = []
            for layer in bars:
                png = subprocess.check_output(['grim', '-s', '1', '-g', f"{layer['x']},{layer['y']} {layer['w']}x40", '-'])
                image = Image.open(io.BytesIO(png)).convert('RGB')
                colors.append(image.getpixel((10, 20)))
            return colors
        dark = samples()
        cli('set', 'themes.material-theme-mode', 'light')
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            light = samples()
            if all(sum(now) > sum(previous) + 200 for previous, now in zip(dark, light)):
                break
            time.sleep(0.2)
        else:
            raise AssertionError(('Bar did not follow settings on all outputs', dark, light))
        # Light bar corners must reveal the compositor beneath the capsule.
        artifacts = ROOT / 'build/interface-smoke'
        artifacts.mkdir(parents=True, exist_ok=True)
        for index, layer in enumerate(bars):
            png = subprocess.check_output(['grim', '-s', '1', '-g', f"{layer['x']},{layer['y']} {layer['w']}x40", '-'])
            (artifacts / f'bar-{index}.png').write_bytes(png)
            image = Image.open(io.BytesIO(png)).convert('RGB')
            fill = image.getpixel((image.width // 2, 20))
            assert image.getpixel((0, 0)) != fill and image.getpixel((image.width - 1, 0)) != fill, 'Capsule corners were filled'
        print(f'PASS: installed bar on {len(bars)} outputs follows live D-Bus Light/Dark changes', flush=True)
        assert cli('open', 'about') == {'opened': 'about'}
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            clients = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))
            if any(client['class'] == 'top.remya.settings' and Path(f"/proc/{client['pid']}/exe").resolve().is_relative_to(Path(os.environ['XDG_DATA_HOME'])) for client in clients):
                break
            time.sleep(0.1)
        else:
            raise AssertionError('Open did not show the settings window')
        subprocess.run(['gtk-launch', 'top.remya.settings'], check=True, timeout=5)
        assert len([client for client in json.loads(subprocess.check_output(['hyprctl', 'clients', '-j'])) if client['class'] == 'top.remya.settings' and Path(f"/proc/{client['pid']}/exe").resolve().is_relative_to(Path(os.environ['XDG_DATA_HOME']))]) == 1
        assert cli('quit') == {'quitting': True}
        print('PASS: installed CLI/D-Bus parity, activation without UI, actual isolated Rust writes/readback, signals, validation/recovery, navigation, and quit')
    finally:
        if bar is not None:
            bar.terminate()
            bar.wait(timeout=5)
            monitors = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
            assert all(monitor['reserved'] == before[monitor['name']] for monitor in monitors), 'Bar reserved space was not released'
        if watcher is not None:
            watcher.terminate()
            watcher.wait(timeout=5)
        if pid is not None:
            time.sleep(0.3)
            process = Path(f'/proc/{pid}/exe')
            try:
                if process.resolve().is_relative_to(Path(os.environ['XDG_DATA_HOME'])):
                    os.kill(pid, signal.SIGTERM)
            except (OSError, RuntimeError):
                pass


def main():
    if '--session' in sys.argv:
        session_checks()
        return
    with tempfile.TemporaryDirectory(prefix='remya api smoke %-') as temporary:
        home = Path(temporary)
        environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'),
                           XDG_DATA_HOME=str(home / 'data $'), XDG_CACHE_HOME=str(home / 'cache'),
                           XDG_STATE_HOME=str(home / 'state'), GSETTINGS_BACKEND='keyfile',
                           HYPRLAND_CONFIG=str(home / 'hyprland.lua'), NO_AT_BRIDGE='1', GIO_USE_VFS='local', GTK_USE_PORTAL='0')
        (home / 'hyprland.lua').write_text('-- Isolated appearance smoke-test entrypoint\n')
        subprocess.run([sys.executable, str(ROOT / 'tool/install.py')], env=environment, check=True)
        subprocess.run([sys.executable, str(ROOT.parent / 'remya_bar/tool/install.py')], env=environment, check=True)
        subprocess.run(['desktop-file-validate', str(home / 'data $/applications/top.remya.settings.desktop')], check=True)
        subprocess.run(['dbus-run-session', '--', sys.executable, str(Path(__file__).resolve()), '--session'],
                       env=environment, check=True, timeout=100)


if __name__ == '__main__':
    main()
