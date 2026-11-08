"""Airplane CLI/D-Bus parity on private buses; never changes real radios.

Reuses the existing NetworkManager and BlueZ fixtures. Build the release bundle
first, then run: python test/airplane_smoke.py
"""
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import network_smoke as network
import bluetooth_smoke as bluetooth

ROOT = Path(__file__).resolve().parents[1]
B = '/org/bluez/hci1'


class Network(network.Stub):
    def __init__(self):
        network.XML = network.XML.replace(
            '<property name="WirelessEnabled" type="b" access="readwrite"/>',
            '<property name="WirelessEnabled" type="b" access="readwrite"/>'
            '<property name="WwanEnabled" type="b" access="readwrite"/>')
        self.wwan = True
        super().__init__()

    def get_property(self, _bus, _sender, _path, _interface, name):
        return network.v('b', self.wwan if name == 'WwanEnabled' else self.enabled)

    def set_property(self, _bus, _sender, _path, _interface, name, value):
        if name == 'WwanEnabled':
            self.calls.append(f'set {name} {value.get_boolean()}')
            self.wwan = value.get_boolean()
            return True
        return super().set_property(_bus, _sender, _path, _interface, name, value)


class Bluetooth(bluetooth.Stub):
    def __init__(self):
        self.second = False
        super().__init__()
        self.bus.register_object(B, self.info.lookup_interface(bluetooth.ADAPTER),
                                 self.method, self.get, self.set)

    def get(self, bus, sender, path, interface, name):
        return bluetooth.v('b', self.second) if path == B else super().get(bus, sender, path, interface, name)

    def set(self, bus, sender, path, interface, name, value):
        if path == B:
            self.calls.append('Powered second')
            if self.scenario == 'denied':
                return False
            self.second = value.get_boolean()
            return True
        return super().set(bus, sender, path, interface, name, value)

    def objects(self):
        result = super().objects()
        if self.adapter_present:
            result[B] = {bluetooth.ADAPTER: {'Powered': bluetooth.v('b', self.second)}}
        return result


def call(method, *args, cli=False, ok=True):
    command = [str(ROOT / 'build/linux/x64/release/bundle/libexec/remya_settings_cli'),
               method.lower(), *args] if cli else [
        'gdbus', 'call', '--session', '--dest', bluetooth.BUS,
        '--object-path', '/top/remya/settings', '--method', f'{bluetooth.API}.{method}', *args]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert (result.returncode == 0) == ok, (command, result.stdout, result.stderr)
    if not ok:
        return result.stderr
    return json.loads(result.stdout if cli else ast.literal_eval(result.stdout)[0])


def session(root):
    assert os.environ['DBUS_SYSTEM_BUS_ADDRESS'].startswith(f'unix:path={root}/')
    service = subprocess.Popen([str(ROOT / 'target/release/remya-settings-service'), '--debug-root', root],
                               stdout=subprocess.DEVNULL)
    try:
        for _ in range(100):
            probe = subprocess.run(['gdbus', 'call', '--session', '--dest', bluetooth.BUS,
                                    '--object-path', '/top/remya/settings', '--method', f'{bluetooth.API}.Get',
                                    'about'], capture_output=True)
            if probe.returncode == 0:
                break
            time.sleep(.1)
        for cli in (False, True):
            state = call('Get', 'airplane', cli=cli)
            assert state['api_version'] == 1 and not state['enabled'], state
            assert len(state['adapters']) == 2
            assert 'InvalidArgument' in call('Set', 'airplane.enabled', 'yes', cli=cli, ok=False)
            state = call('Set', 'airplane.enabled', 'true', cli=cli)
            assert state['enabled'] and not state['wifi_enabled'] and not state['wwan_enabled'], state
            assert all(not a['powered'] for a in state['adapters'])
            assert call('Get', 'airplane.enabled', cli=cli)['value'] is True
            state = call('Set', 'airplane.wifi', 'true', cli=cli)
            assert state['wifi_enabled'] and not state['enabled'] and not state['bluetooth_enabled'], state
            # Another client changes Wi-Fi; there is no aggregate preference to conflict.
            call('Set', 'wifi.enabled', 'false', cli=cli)
            assert call('Get', 'airplane', cli=cli)['enabled'] is True
            state = call('Set', 'airplane.enabled', 'false', cli=cli)
            assert state['wifi_enabled'] and state['wwan_enabled'] and all(a['powered'] for a in state['adapters'])
        bluetooth.control('Scenario', 'denied')
        assert 'partially failed' in call('Set', 'airplane.enabled', 'true', ok=False)
        state = call('Get', 'airplane')
        assert not state['enabled'] and not state['wifi_enabled'] and state['bluetooth_enabled'], state
        bluetooth.control('Scenario', 'RequestConfirmation')
        bluetooth.control('RemoveAdapter')
        assert call('Set', 'airplane.enabled', 'true')['enabled'] is True
        bluetooth.control('RestoreAdapter')
        bluetooth.control('ReleaseName')
        assert 'Unavailable' in call('Set', 'airplane.enabled', 'false', ok=False)
        assert 'Unavailable' in call('Get', 'airplane', ok=False)
        call('Quit')
    finally:
        service.terminate()
        service.wait(timeout=10)
    assert not list(Path(root).rglob('*airplane*'))


def main():
    if sys.argv[1:] == ['--network']:
        Network().loop.run()
        return
    if sys.argv[1:] == ['--bluetooth']:
        Bluetooth().loop.run()
        return
    if sys.argv[1:2] == ['--session']:
        session(sys.argv[2])
        return
    with tempfile.TemporaryDirectory(prefix='remya-radios-') as root:
        (Path(root) / 'config').mkdir()
        address = f'unix:path={root}/system-bus'
        environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address, HOME=root,
                           XDG_CONFIG_HOME=f'{root}/c', XDG_DATA_HOME=f'{root}/d',
                           XDG_CACHE_HOME=f'{root}/k', GSETTINGS_BACKEND='keyfile', GIO_USE_VFS='local')
        processes = [subprocess.Popen(['dbus-daemon', '--session', '--nofork', f'--address={address}'])]
        try:
            time.sleep(.2)
            processes.extend(subprocess.Popen([sys.executable, __file__, mode], env=environment)
                             for mode in ('--network', '--bluetooth'))
            time.sleep(.5)
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session', root],
                           env=environment, check=True, timeout=90)
        finally:
            for process in reversed(processes):
                process.terminate()
                process.wait(timeout=5)
    print('Airplane CLI/D-Bus integration passed')


if __name__ == '__main__':
    main()
