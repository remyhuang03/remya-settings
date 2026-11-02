"""Bluetooth integration on private session/system buses; never touches hardware.

Usage: python test/bluetooth_smoke.py [debug|release] [--timers]
--timers additionally waits for the real 60-second scan and 120-second pair limits.
"""
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[1]
BLUEZ = 'org.bluez'
ADAPTER = f'{BLUEZ}.Adapter1'
DEVICE = f'{BLUEZ}.Device1'
AGENT = f'{BLUEZ}.Agent1'
A = '/org/bluez/hci0'
D = f'{A}/dev_AA_BB_CC_DD_EE_FF'
BUS = 'top.remya.settings.Service1'
USE_CLI = False
CLI = None
API = 'top.remya.settings.Settings1'
XML = f'''<node>
<interface name="org.freedesktop.DBus.ObjectManager"><method name="GetManagedObjects"><arg type="a{{oa{{sa{{sv}}}}}}" direction="out"/></method></interface>
<interface name="org.bluez.AgentManager1"><method name="RegisterAgent"><arg type="o"/><arg type="s"/></method></interface>
<interface name="{ADAPTER}">
<property name="Powered" type="b" access="readwrite"/>
<method name="SetDiscoveryFilter"><arg type="a{{sv}}"/></method><method name="StartDiscovery"/><method name="StopDiscovery"/>
<method name="RemoveDevice"><arg type="o"/></method></interface>
<interface name="{DEVICE}">
<property name="Connected" type="b" access="read"/><property name="Paired" type="b" access="read"/>
<method name="Pair"/><method name="CancelPairing"/><method name="Connect"/><method name="Disconnect"/></interface>
<interface name="top.remya.bluetooth.Test">
<method name="Scenario"><arg type="s"/></method><method name="Calls"><arg type="s" direction="out"/></method>
<method name="CompleteDisplay"/><method name="ForeignAgent"/><method name="RemoveAdapter"/><method name="RestoreAdapter"/>
<method name="ReleaseName"/><method name="OwnName"/><method name="Reset"/><method name="ExternalScan"><arg type="b"/></method>
</interface></node>'''


def v(signature, value):
    return GLib.Variant(signature, value)


class Stub:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        self.loop = GLib.MainLoop()
        self.info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.owner = None
        self.agent = None
        self.pair = None
        self.scenario = 'RequestConfirmation'
        self.powered = True
        self.connected = False
        self.paired = False
        self.present = True
        self.adapter_present = True
        self.external_scan = False
        self.scanning = False
        self.visible = False
        self.calls = []
        for path, interfaces in {
            '/': ['org.freedesktop.DBus.ObjectManager'],
            '/org/bluez': ['org.bluez.AgentManager1', 'top.remya.bluetooth.Test'],
            A: [ADAPTER], D: [DEVICE],
        }.items():
            for interface in interfaces:
                self.bus.register_object(path, self.info.lookup_interface(interface), self.method, self.get, self.set)
        self.own()

    def own(self):
        self.owner = Gio.bus_own_name_on_connection(self.bus, BLUEZ, Gio.BusNameOwnerFlags.NONE, None, None)

    def get(self, _bus, _sender, path, _interface, name):
        return v('b', {'Powered': self.powered, 'Connected': self.connected, 'Paired': self.paired}[name])

    def set(self, _bus, _sender, _path, _interface, _name, value):
        self.calls.append('Powered')
        if self.scenario == 'denied':
            return False
        self.powered = value.get_boolean()
        self.changed()
        return True

    def objects(self):
        if not self.adapter_present:
            return {}
        result = {A: {ADAPTER: {
            'Address': v('s', '00:11:22:33:44:55'), 'Alias': v('s', 'Test adapter'),
            'Powered': v('b', self.powered), 'Discovering': v('b', self.scanning or self.external_scan),
            'Discoverable': v('b', self.visible), 'Pairable': v('b', False),
        }}}
        if self.present:
            result[D] = {DEVICE: {
                'Address': v('s', 'AA:BB:CC:DD:EE:FF'), 'Alias': v('s', 'Test keyboard'),
                'Adapter': v('o', A), 'Paired': v('b', self.paired), 'Bonded': v('b', self.paired),
                'Connected': v('b', self.connected), 'Icon': v('s', 'input-keyboard'),
            }, 'org.bluez.Battery1': {'Percentage': v('y', 0)}}
        return result

    def changed(self):
        self.bus.emit_signal(None, A, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                             v('(sa{sv}as)', (ADAPTER, {}, [])))

    def finish_pair(self, error=None):
        if self.pair is None:
            return
        invocation, self.pair = self.pair, None
        if error:
            invocation.return_dbus_error('org.bluez.Error.AuthenticationFailed', error)
        else:
            self.paired = True
            invocation.return_value(v('()', ()))
            self.changed()

    def request_agent(self, method):
        args = {
            'RequestPinCode': v('(o)', (D,)), 'RequestPasskey': v('(o)', (D,)),
            'RequestConfirmation': v('(ou)', (D, 123456)),
            'RequestAuthorization': v('(o)', (D,)),
            'AuthorizeService': v('(os)', (D, '00001124-0000-1000-8000-00805f9b34fb')),
            'DisplayPinCode': v('(os)', (D, '001234')),
            'DisplayPasskey': v('(ouq)', (D, 1234, 2)),
        }[method]

        def finished(bus, result):
            try:
                reply = bus.call_finish(result).unpack()
                if method == 'RequestPinCode' and reply != ('1234',):
                    self.finish_pair('Wrong PIN')
                elif method == 'RequestPasskey' and reply != (123456,):
                    self.finish_pair('Wrong passkey')
                elif not method.startswith('Display'):
                    self.finish_pair()
            except GLib.Error:
                self.finish_pair('Pairing rejected or cancelled')
        self.bus.call(self.agent[0], self.agent[1], AGENT, method, args, None,
                      Gio.DBusCallFlags.NONE, 130000, None, finished)

    def method(self, _bus, sender, path, interface, method, args, invocation):
        values = args.unpack()
        if interface == 'top.remya.bluetooth.Test':
            if method == 'Reset':
                self.calls.clear()
                self.scenario = 'RequestConfirmation'
                self.present = self.powered = self.adapter_present = True
                self.paired = self.connected = self.scanning = self.visible = self.external_scan = False
            elif method == 'ExternalScan':
                self.external_scan = values[0]
            elif method == 'Scenario':
                self.scenario = values[0]
                self.present = True
                self.paired = False
                self.connected = False
            elif method == 'Calls':
                invocation.return_value(v('(s)', (json.dumps(self.calls),)))
                return
            elif method == 'CompleteDisplay':
                self.finish_pair()
            elif method == 'ForeignAgent':
                address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SYSTEM)
                foreign = Gio.DBusConnection.new_for_address_sync(address,
                    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
                try:
                    foreign.call_sync(self.agent[0], self.agent[1], AGENT, 'RequestConfirmation',
                                      v('(ou)', (D, 999999)), None, Gio.DBusCallFlags.NONE, 2000, None)
                    raise AssertionError('Foreign agent callback accepted')
                except GLib.Error as error:
                    assert 'Rejected' in str(error), error
                finally:
                    foreign.close_sync()
            elif method == 'RemoveAdapter':
                self.adapter_present = False
            elif method == 'RestoreAdapter':
                self.adapter_present = True
            elif method == 'ReleaseName':
                Gio.bus_unown_name(self.owner)
                self.owner = None
                self.scanning = self.visible = False
            elif method == 'OwnName':
                self.own()
            self.changed()
            invocation.return_value(v('()', ()))
            return
        if method not in ('GetManagedObjects',):
            self.calls.append(method)
        if method == 'GetManagedObjects':
            invocation.return_value(v('(a{oa{sa{sv}}})', (self.objects(),)))
        elif method == 'RegisterAgent':
            self.agent = (sender, values[0])
            assert values[1] == 'KeyboardDisplay'
            invocation.return_value(v('()', ()))
        elif method == 'SetDiscoveryFilter':
            self.visible = values[0].get('Discoverable', False)
            invocation.return_value(v('()', ()))
        elif method == 'StartDiscovery':
            self.scanning = True
            invocation.return_value(v('()', ()))
        elif method == 'StopDiscovery':
            self.scanning = False
            self.visible = False
            invocation.return_value(v('()', ()))
        elif method == 'Pair':
            self.pair = invocation
            self.request_agent('RequestConfirmation' if self.scenario == 'paired-connect-failed' else self.scenario)
        elif method == 'CancelPairing':
            self.finish_pair('Cancelled')
            invocation.return_value(v('()', ()))
        elif method == 'Connect':
            if self.scenario in ('connect-failed', 'paired-connect-failed'):
                invocation.return_dbus_error('org.bluez.Error.Failed', 'Profile unavailable')
            else:
                self.connected = True
                invocation.return_value(v('()', ()))
        elif method == 'Disconnect':
            self.connected = False
            invocation.return_value(v('()', ()))
        elif method == 'RemoveDevice':
            self.paired = self.connected = self.present = False
            invocation.return_value(v('()', ()))
        self.changed()


def call(method, *args, ok=True):
    command = [str(CLI), method.lower(), *args] if USE_CLI else ['gdbus', 'call', '--session', '--dest', BUS, '--object-path', '/top/remya/settings', '--method', f'{API}.{method}', *args]
    result = subprocess.run(command, capture_output=True, text=True, timeout=15)
    assert (result.returncode == 0) == ok, (method, args, result.stdout, result.stderr)
    return json.loads(result.stdout if USE_CLI else ast.literal_eval(result.stdout)[0]) if ok else result.stderr


def control(method, *args):
    return subprocess.check_output(['gdbus', 'call', '--system', '--dest', 'org.bluez', '--object-path', '/org/bluez',
                                    '--method', f'top.remya.bluetooth.Test.{method}', *args], text=True, timeout=5)


def change(action, **values):
    return call('Set', 'bluetooth.' + action, json.dumps({'adapter': A, **values}))


def wait(predicate, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = call('Get', 'bluetooth')
        if predicate(state):
            return state
        time.sleep(.1)
    raise AssertionError(('Bluetooth did not settle', state))


def settled():
    return wait(lambda s: s['operation']['status'] != 'running')


def pair(method, **response):
    control('Scenario', method)
    call('Get', 'bluetooth')
    accepted = change('pair', device=D)
    assert accepted['operation']['status'] == 'running'
    state = wait(lambda s: s['prompt'] and s['prompt']['kind'] == method)
    assert call('Get', 'about')['api_version'] == 1  # Pair must not hold the service lock.
    if method.startswith('Display'):
        assert state['prompt']['code'] == ('001234' if method == 'DisplayPinCode' else '001234')
        control('CompleteDisplay')
    else:
        request_id = state['prompt']['id']
        error = call('Set', 'bluetooth.respond', json.dumps({'request': request_id + 1, 'accept': True}), ok=False)
        assert 'expired' in error
        change('respond', request=request_id, **response)
    return settled()


def checks(timers):
    state = wait(lambda s: s['available'])
    assert state['devices'][0]['battery'] == 0 and state['error'] is None
    assert call('Get', 'bluetooth.devices')['availability'] == 'available'
    assert not ast.literal_eval(control('Calls'))[0].strip('[]')  # First use only reads.
    assert 'InvalidArgument' in call('Set', 'bluetooth.connect', json.dumps({'adapter': A, 'device': '/wrong'}), ok=False)
    assert 'secret-pin' not in call('Set', 'bluetooth.respond', '{"pin":"secret-pin","unknown":true}', ok=False)
    change('enabled', enabled=False)
    assert not settled()['adapters'][0]['powered']
    change('enabled', enabled=True)
    assert settled()['adapters'][0]['powered']
    control('ExternalScan', 'true')
    change('scan', enabled=True)
    assert settled()['scanning'] == [A]
    change('scan', enabled=False)
    wait(lambda s: not s['scanning'])
    assert call('Get', 'bluetooth')['adapters'][0]['discovering']
    control('ExternalScan', 'false')
    change('discoverable', enabled=True)
    assert settled()['adapters'][0]['discoverable']
    change('scan', enabled=False)
    wait(lambda s: not s['adapters'][0]['discoverable'])
    for method, response in [
        ('RequestPinCode', {'pin': '1234'}), ('RequestPasskey', {'passkey': 123456}),
        ('RequestConfirmation', {'accept': True}), ('RequestAuthorization', {'accept': True}),
        ('AuthorizeService', {'accept': True}), ('DisplayPinCode', {}), ('DisplayPasskey', {}),
    ]:
        state = pair(method, **response)
        assert state['operation']['status'] == 'completed', state
        assert state['devices'][0]['paired'] and state['devices'][0]['connected']
    state = pair('RequestPinCode', pin='0000')
    assert state['operation']['status'] == 'failed' and not state['devices'][0]['paired']
    state = pair('RequestConfirmation', accept=False)
    assert state['operation']['status'] == 'failed'
    control('Scenario', 'RequestConfirmation')
    call('Get', 'bluetooth')
    change('pair', device=D)
    wait(lambda s: s['prompt'])
    control('ForeignAgent')
    change('cancel')
    assert settled()['operation']['status'] == 'cancelled'
    wait(lambda s: not s['prompt'])
    control('Scenario', 'RequestConfirmation')
    call('Get', 'bluetooth')
    change('pair', device=D)
    wait(lambda s: s['prompt'])
    control('RemoveAdapter')
    state = wait(lambda s: not s['adapters'])
    assert state['operation']['status'] == 'failed' and state['prompt'] is None
    control('RestoreAdapter')
    wait(lambda s: bool(s['adapters']))
    # Restart the daemon's name without replacing the private system bus.
    control('ReleaseName')
    state = wait(lambda s: not s['available'])
    assert state['error']
    subprocess.check_output(['gdbus', 'call', '--system', '--dest', ':1.0', '--object-path', '/org/bluez',
                             '--method', 'top.remya.bluetooth.Test.OwnName'], text=True)
    wait(lambda s: s['available'])
    state = pair('RequestConfirmation', accept=True)
    assert state['operation']['status'] == 'completed'
    control('Scenario', 'paired-connect-failed')
    call('Get', 'bluetooth')
    change('pair', device=D)
    prompt = wait(lambda s: s['prompt'])['prompt']
    change('respond', request=prompt['id'], accept=True)
    state = settled()
    assert state['operation']['status'] == 'failed' and state['devices'][0]['paired'] and not state['devices'][0]['connected'], state
    change('disconnect', device=D)
    assert not settled()['devices'][0]['connected']
    control('Scenario', 'connect-failed')
    call('Get', 'bluetooth')
    change('connect', device=D)
    state = settled()
    assert state['operation']['status'] == 'failed' and state['error']
    change('forget', device=D)
    state = settled()
    assert state['operation']['status'] == 'completed' and state['devices'] == [], state
    control('Scenario', 'denied')
    call('Get', 'bluetooth')
    change('enabled', enabled=False)
    state = settled()
    assert state['operation']['status'] == 'failed' and state['adapters'][0]['powered']
    if timers:
        control('Scenario', 'RequestConfirmation')
        call('Get', 'bluetooth')
        change('scan', enabled=True)
        settled()
        change('pair', device=D)
        wait(lambda s: s['prompt'])
        wait(lambda s: not s['scanning'], timeout=65)
        state = wait(lambda s: s['operation']['status'] != 'running', timeout=65)
        assert state['operation']['status'] == 'cancelled' and 'timed out' in state['error'], state


def session(binary, root, timers):
    global USE_CLI, CLI
    profile = Path(binary).parent.name
    CLI = ROOT / f'build/linux/x64/{profile}/bundle/libexec/remya_settings_cli'
    assert CLI.is_file(), 'Build the Flutter bundle before testing CLI parity'
    assert os.environ['DBUS_SYSTEM_BUS_ADDRESS'].startswith('unix:path=' + root)
    service = subprocess.Popen([binary, '--debug-root', root], stdout=subprocess.DEVNULL)
    try:
        for _ in range(100):
            result = subprocess.run(['gdbus', 'call', '--session', '--dest', BUS, '--object-path', '/top/remya/settings',
                                     '--method', f'{API}.Get', 'about'], capture_output=True)
            if result.returncode == 0:
                break
            time.sleep(.1)
        checks(timers)
        control('Reset')
        USE_CLI = True
        change('scan', enabled=True)
        assert settled()['scanning'] == [A]
        change('scan', enabled=False)
        wait(lambda s: not s['scanning'])
        control('Scenario', 'RequestPinCode')
        call('Get', 'bluetooth')
        change('pair', device=D)
        prompt = wait(lambda s: s['prompt'])['prompt']
        reply = subprocess.run([str(CLI), 'set', 'bluetooth.respond', '-'],
                               input=json.dumps({'request': prompt['id'], 'pin': '1234'}),
                               text=True, capture_output=True, timeout=10)
        assert reply.returncode == 0, reply.stderr
        state = settled()
        assert state['devices'][0]['paired'] and state['devices'][0]['connected']
        change('forget', device=D)
        assert settled()['devices'] == []
        call('Quit')
    finally:
        service.terminate()
        service.wait(timeout=10)
    assert not (Path(root) / 'config/bluetooth.toml').exists()


def main():
    if sys.argv[1:2] == ['--stub']:
        Stub().loop.run()
        return
    if sys.argv[1:2] == ['--session']:
        session(sys.argv[2], sys.argv[3], '--timers' in sys.argv)
        return
    profile = next((a for a in sys.argv[1:] if not a.startswith('--')), 'debug')
    with tempfile.TemporaryDirectory(prefix='remya-bluetooth-') as root:
        (Path(root) / 'config').mkdir()
        address = f'unix:path={root}/system-bus'
        daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', f'--address={address}'])
        environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address, HOME=root,
                           XDG_CONFIG_HOME=f'{root}/c', XDG_DATA_HOME=f'{root}/d',
                           XDG_CACHE_HOME=f'{root}/k', GSETTINGS_BACKEND='keyfile', GIO_USE_VFS='local')
        time.sleep(.2)
        stub = subprocess.Popen([sys.executable, __file__, '--stub'], env=environment)
        time.sleep(.4)
        try:
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session',
                            str(ROOT / 'target' / profile / 'remya-settings-service'), root,
                            *(['--timers'] if '--timers' in sys.argv else [])], env=environment, check=True, timeout=200)
        finally:
            stub.terminate()
            daemon.terminate()
            stub.wait(timeout=5)
            daemon.wait(timeout=5)
    print('Bluetooth integration passed')


if __name__ == '__main__':
    main()
