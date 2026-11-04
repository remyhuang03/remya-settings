"""CLI/D-Bus Sound parity on private buses/audio; never touches desktop audio.

Usage: python test/sound_smoke.py [debug|release]
Requires a compiled Rust service and a Linux bundle containing the generic CLI.
"""
import ast
from contextlib import ExitStack
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
    result = subprocess.run(args, capture_output=True, text=True, timeout=40)
    assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
    return result.stdout if ok else result.stderr


def dbus(method, *args):
    result = run('gdbus', 'call', '--session', '--dest', BUS,
                 '--object-path', '/top/remya/settings', '--method', f'{API}.{method}', *args)
    return json.loads(ast.literal_eval(result)[0])


def check(profile, cli):
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    with ExitStack() as processes:
        def start(*args, stdout=subprocess.DEVNULL):
            child = subprocess.Popen(args, stdout=stdout, stderr=subprocess.DEVNULL)
            def stop():
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            processes.callback(stop)
            return child

        def wait(predicate):
            deadline = time.monotonic() + 10
            while not predicate():
                assert time.monotonic() < deadline, 'Private test service did not become ready'
                time.sleep(0.05)

        start('pipewire')
        wait(lambda: (runtime / 'pipewire-0').exists())
        start('pipewire-pulse')
        wait(lambda: (runtime / 'pulse/native').exists())
        # Policy manages virtual nodes; no hardware monitor profile is started.
        start('wireplumber', '--profile', 'policy')
        time.sleep(0.2)
        for name in ('remya_api_a', 'remya_api_b'):
            run('pactl', 'load-module', 'module-null-sink', f'sink_name={name}')
        service = start(str(ROOT / f'target/{profile}/remya-settings-service'))
        def ready():
            try:
                return dbus('Get', 'sound')['available']
            except AssertionError:
                return False
        wait(ready)
        def command(*args, ok=True):
            output = run(cli, *args, ok=ok)
            return json.loads(output) if ok else output
        initial = command('get', 'sound')
        assert initial == dbus('Get', 'sound')
        assert initial['available'], initial
        assert not {'saved', 'conflict', 'initialized'} & initial.keys(), initial
        assert all(d['name'].startswith('remya_api_') for d in initial['system']['devices'])
        assert command('get', 'sound.devices')['id'] == 'sound.devices'
        assert 'ReadOnly' in command('set', 'sound.devices', '{}', ok=False)
        assert 'InvalidArgument' in command('set', 'sound.output-volume', '{"percent":151}', ok=False)
        signals = processes.enter_context(tempfile.TemporaryFile(mode='w+t'))
        start('gdbus', 'monitor', '--session', '--dest', BUS,
              '--object-path', '/top/remya/settings', stdout=signals)
        time.sleep(0.1)
        for method, setting, body in (
            ('Set', 'sound.output-device', {'name': 'remya_api_b'}),
            ('Set', 'sound.output-volume', {'percent': 43}),
            ('Set', 'sound.output-muted', {'muted': True}),
            ('Set', 'sound.input-device', {'name': 'remya_api_b.monitor'}),
            ('Set', 'sound.input-muted', {'muted': True}),
        ):
            expected = dbus(method, setting, json.dumps(body))
            assert command('get', 'sound') == expected
        run('pactl', 'set-sink-mute', 'remya_api_b', '0')
        run('pactl', 'set-sink-volume', 'remya_api_b', '27%')
        run('pactl', 'set-source-mute', 'remya_api_b.monitor', '0')
        run('pactl', 'set-source-volume', 'remya_api_b.monitor', '31%')
        run('pactl', 'set-default-sink', 'remya_api_a')
        run('pactl', 'set-default-source', 'remya_api_a.monitor')
        live = command('get', 'sound')
        assert live == dbus('Get', 'sound') and live['error'] is None, live
        assert live['system']['default_output'] == 'remya_api_a'
        assert live['system']['default_input'] == 'remya_api_a.monitor'
        for name, expected in [('remya_api_b', 27), ('remya_api_b.monitor', 31)]:
            device = next(d for d in live['system']['devices'] if d['name'] == name)
            assert not device['preferences']['muted'], device
            assert abs(max(device['preferences']['channels']) * 100 / 65536 - expected) < 0.01
        assert 'Unknown feature' in command('resolve', 'sound', 'settings', ok=False)
        assert 'Unknown feature' in command('resolve', 'sound', 'system', ok=False)
        error = run('gdbus', 'call', '--session', '--dest', BUS,
                    '--object-path', '/top/remya/settings', '--method', f'{API}.Resolve',
                    'sound', 'settings', ok=False)
        assert 'Unknown feature' in error, error
        config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/sound.toml'
        assert not config.exists(), config
        # Restart only the private Settings service, retaining the live audio server.
        service.terminate()
        service.wait(timeout=5)
        start(str(ROOT / f'target/{profile}/remya-settings-service'))
        wait(ready)
        assert command('get', 'sound')['system'] == live['system']
        assert not config.exists(), config
        signals.seek(0)
        assert 'Changed (\'sound\'' in signals.read(), 'Missing Sound change notification'
        command('quit')
        print('Sound CLI/D-Bus parity, live state, removed resolutions, restart and signals passed')


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--inside':
        check(sys.argv[2], sys.argv[3])
        return
    profile = sys.argv[1] if len(sys.argv) > 1 else 'debug'
    assert profile in ('debug', 'release')
    cli = ROOT / f'build/linux/x64/{profile}/bundle/libexec/remya_settings_cli'
    if not cli.exists():
        cli = ROOT / 'build/linux/x64/release/bundle/libexec/remya_settings_cli'
    assert cli.exists(), 'Build a Linux bundle to supply the generic CLI'
    with tempfile.TemporaryDirectory(prefix='remya-sound-api-') as tmp:
        root = Path(tmp)
        env = os.environ.copy()
        env.update(HOME=tmp, XDG_CONFIG_HOME=f'{tmp}/config', XDG_DATA_HOME=f'{tmp}/data',
                   XDG_STATE_HOME=f'{tmp}/state', XDG_CACHE_HOME=f'{tmp}/cache',
                   XDG_RUNTIME_DIR=tmp, PIPEWIRE_RUNTIME_DIR=tmp, PIPEWIRE_REMOTE='pipewire-0',
                   PULSE_RUNTIME_PATH=f'{tmp}/pulse', PULSE_SERVER=f'unix:{tmp}/pulse/native',
                   GSETTINGS_BACKEND='keyfile', HYPRLAND_INSTANCE_SIGNATURE='',
                   DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={tmp}/no-system-bus')
        subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--inside', profile,
                        str(cli)], env=env, cwd=ROOT, check=True, timeout=90)


if __name__ == '__main__':
    main()
