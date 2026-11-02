"""Exercise Settings network operations against a stub NetworkManager.

Runs the service on a private session bus and a private "system" bus, so no real
connection, radio or saved network is touched. Usage: network_smoke.py [debug|release]
"""
import ast
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[1]
NM = 'org.freedesktop.NetworkManager'
BASE = '/org/freedesktop/NetworkManager'
DEVICE = f'{NM}.Device'
WIRELESS = f'{DEVICE}.Wireless'
ACTIVE = f'{NM}.Connection.Active'
AP = f'{NM}.AccessPoint'
CONNECTION = f'{NM}.Settings.Connection'
BUS = 'top.remya.settings.Service1'
INTERFACE = 'top.remya.settings.Settings1'
XML = f'''<node>
<interface name="org.freedesktop.DBus.ObjectManager">
  <method name="GetManagedObjects"><arg type="a{{oa{{sa{{sv}}}}}}" direction="out"/></method></interface>
<interface name="{NM}">
  <property name="WirelessEnabled" type="b" access="readwrite"/>
  <method name="GetPermissions"><arg type="a{{ss}}" direction="out"/></method>
  <method name="ActivateConnection"><arg type="o"/><arg type="o"/><arg type="o"/><arg type="o" direction="out"/></method>
  <method name="AddAndActivateConnection2"><arg type="a{{sa{{sv}}}}"/><arg type="o"/><arg type="o"/><arg type="a{{sv}}"/>
    <arg type="o" direction="out"/><arg type="o" direction="out"/><arg type="a{{sv}}" direction="out"/></method></interface>
<interface name="{NM}.Settings">
  <method name="AddConnection"><arg type="a{{sa{{sv}}}}"/><arg type="o" direction="out"/></method></interface>
<interface name="{CONNECTION}">
  <method name="GetSettings"><arg type="a{{sa{{sv}}}}" direction="out"/></method>
  <method name="Update"><arg type="a{{sa{{sv}}}}"/></method>
  <method name="Delete"/><method name="Save"/></interface>
<interface name="{DEVICE}"><method name="Disconnect"/>
  <signal name="StateChanged"><arg type="u"/><arg type="u"/><arg type="u"/></signal></interface>
<interface name="{WIRELESS}"><method name="RequestScan"><arg type="a{{sv}}"/></method></interface>
<interface name="top.remya.smoke.Control">
  <method name="Calls"><arg type="s" direction="out"/></method>
  <method name="ExternalMetered"><arg type="s"/><arg type="i"/></method>
  <method name="Quit"/></interface>
</node>'''
PERSONAL = 0x100


def v(signature, value):
    return GLib.Variant(signature, value)


class Stub:
    """Implements only the NetworkManager calls the Settings backend makes."""

    def __init__(self):
        self.enabled = True
        self.calls = []
        self.next = 10
        self.active = None
        self.profiles = {}
        self.secrets = {}
        self.flags = {}
        self.loop = GLib.MainLoop()
        self.info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        self.add_profile({'id': 'Home', 'ssid': b'Home', 'key': 'wpa-psk'}, 'home-uuid')
        for path, names in {
            '/org/freedesktop': ['org.freedesktop.DBus.ObjectManager'],
            BASE: [NM, 'top.remya.smoke.Control'],
            f'{BASE}/Settings': [f'{NM}.Settings'],
            f'{BASE}/Devices/1': [DEVICE, WIRELESS],
            f'{BASE}/Devices/2': [DEVICE, WIRELESS],
            f'{BASE}/Devices/3': [DEVICE],
        }.items():
            for name in names:
                self.register(path, name)
        Gio.bus_own_name_on_connection(self.bus, NM, Gio.BusNameOwnerFlags.NONE, None, None)

    def register(self, path, name):
        self.bus.register_object(
            path, self.info.lookup_interface(name), self.method, self.get_property, self.set_property)

    def get_property(self, *_):
        return v('b', self.enabled)

    def set_property(self, _bus, _sender, _path, _interface, name, value):
        self.calls.append(f'set {name} {value.get_boolean()}')
        self.enabled = value.get_boolean()
        self.changed()
        return True

    def changed(self):
        self.bus.emit_signal(None, BASE, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                             v('(sa{sv}as)', (NM, {}, [])))

    def add_profile(self, spec, uuid, unsaved=False):
        path = f'{BASE}/Settings/{self.next}'
        self.next += 1
        self.profiles[path] = {
            'connection': {'id': v('s', spec['id']), 'uuid': v('s', uuid), 'type': v('s', '802-11-wireless'),
                           'autoconnect': v('b', spec.get('autoconnect', True))},
            '802-11-wireless': {'ssid': v('ay', list(spec['ssid'])), 'mode': v('s', 'infrastructure')},
        }
        if spec.get('key'):
            self.profiles[path]['802-11-wireless-security'] = {'key-mgmt': v('s', spec['key'])}
        self.flags[path] = 1 if unsaved else 0
        if hasattr(self, 'bus') and path not in getattr(self, 'registered', set()):
            self.register(path, CONNECTION)
        return path

    def adopt(self, settings, unsaved):
        """Stores a request as a profile; the password is kept apart like NM's secret store."""
        settings = {k: dict(s) for k, s in settings.items()}
        security = settings.get('802-11-wireless-security', {})
        password = security.pop('psk', None)
        path = f'{BASE}/Settings/{self.next}'
        self.next += 1
        self.profiles[path] = settings
        self.flags[path] = 1 if unsaved else 0
        self.secrets[path] = password
        self.register(path, CONNECTION)
        return path

    def start(self, profile, device, password):
        self.active = {'path': f'{BASE}/ActiveConnection/{self.next}', 'profile': profile,
                       'device': device, 'state': 1}
        self.next += 1
        active = self.active

        def finish():
            if self.active is not active:
                return False
            if password == 'wrong-password':
                self.active = None
                self.bus.emit_signal(None, device, DEVICE, 'StateChanged', v('(uuu)', (120, 50, 7)))
            else:
                active['state'] = 2
            self.changed()
            return False

        GLib.timeout_add(100, finish)
        self.changed()
        return active['path']

    def method(self, _bus, _sender, path, interface, name, args, invocation):
        values = args.unpack()
        if interface != 'top.remya.smoke.Control' and name not in ('GetManagedObjects', 'GetPermissions', 'GetSettings'):
            self.calls.append(f'{name} {path}')
        reply = None
        if name == 'GetManagedObjects':
            reply = v('(a{oa{sa{sv}}})', (self.objects(),))
        elif name == 'GetPermissions':
            reply = v('(a{ss})', ({f'{NM}.wifi.scan': 'yes'},))
        elif name == 'GetSettings':
            reply = v('(a{sa{sv}})', (self.packed(path),))
        elif name == 'Update':
            settings = args.get_child_value(0)
            unpacked = self.unpack(settings)
            security = unpacked.get('802-11-wireless-security', {})
            if 'psk' in security:
                self.secrets[path] = security.pop('psk').get_string()
                self.calls.append(f'psk-flags {security["psk-flags"].get_uint32()}')
            self.profiles[path] = unpacked
            self.flags[path] = 0
            self.changed()
        elif name == 'Delete':
            del self.profiles[path]
            self.changed()
        elif name == 'Save':
            self.flags[path] = 0
            self.changed()
        elif name == 'AddConnection':
            created = self.adopt(self.unpack(args.get_child_value(0)), False)
            self.changed()
            reply = v('(o)', (created,))
        elif name == 'ActivateConnection':
            reply = v('(o)', (self.start(values[0], values[1], self.secrets.get(values[0])),))
        elif name == 'AddAndActivateConnection2':
            settings = self.unpack(args.get_child_value(0))
            self.calls.append(f'persist {values[3]["persist"]}')
            created = self.adopt(settings, True)
            active = self.start(created, values[1], self.secrets[created].get_string())
            reply = v('(ooa{sv})', (created, active, {}))
        elif name == 'Disconnect':
            self.active = None
            self.changed()
        elif name == 'Calls':
            reply = v('(s)', (json.dumps(self.calls),))
        elif name == 'ExternalMetered':
            for profile in self.profiles.values():
                if profile['connection']['uuid'].get_string() == values[0]:
                    profile['connection']['metered'] = v('i', values[1])
            self.changed()
        elif name == 'Quit':
            invocation.return_value(None)
            self.bus.flush_sync()
            self.loop.quit()
            return
        invocation.return_value(reply)

    def unpack(self, value):
        result = {}
        for i in range(value.n_children()):
            entry = value.get_child_value(i)
            section = entry.get_child_value(1)
            result[entry.get_child_value(0).get_string()] = {
                section.get_child_value(j).get_child_value(0).get_string():
                    section.get_child_value(j).get_child_value(1).get_variant()
                for j in range(section.n_children())}
        return result

    def packed(self, path):
        return self.profiles[path]

    def access_point(self, ssid, strength, flags, rsn, frequency=2412):
        return {AP: {'Ssid': v('ay', list(ssid.encode())), 'Strength': v('y', strength),
                     'Frequency': v('u', frequency), 'Flags': v('u', flags),
                     'WpaFlags': v('u', 0), 'RsnFlags': v('u', rsn)}}

    def objects(self):
        points = {'/ap/1': self.access_point('Home', 40, 1, PERSONAL), '/ap/2': self.access_point('Home', 80, 1, PERSONAL),
                  '/ap/3': self.access_point('Cafe', 60, 1, PERSONAL), '/ap/4': self.access_point('Corp', 50, 1, 0x200),
                  '/ap/5': self.access_point('Old', 30, 1, 0), '/ap/6': self.access_point('Free', 20, 0, 0)}
        result = {'/org/freedesktop/NetworkManager/ap' + path[3:]: value for path, value in points.items()}
        active = self.active
        active_ap = f'{BASE}/ap/3' if active and active['device'].endswith('/1') else '/'
        result[BASE] = {NM: {'Connectivity': v('u', 4), 'ConnectivityCheckAvailable': v('b', True),
                             'ConnectivityCheckEnabled': v('b', True), 'WirelessEnabled': v('b', self.enabled),
                             'WirelessHardwareEnabled': v('b', True),
                             'PrimaryConnection': v('o', active['path'] if active and active['state'] == 2 else '/')}}
        for index, kind, name in ((1, 2, 'wlan0'), (2, 2, 'wlan1'), (3, 1, 'eth0'), (4, 30, 'p2p0'), (5, 32, 'lo')):
            path = f'{BASE}/Devices/{index}'
            connected = active and active['device'] == path
            device = {DEVICE: {'Interface': v('s', name), 'DeviceType': v('u', kind), 'Real': v('b', True),
                               'Capabilities': v('u', 1), 'State': v('u', 100 if connected else 30),
                               'HwAddress': v('s', '02:00:00:00:00:0%d' % index),
                               'ActiveConnection': v('o', active['path'] if connected else '/'),
                               'Ip4Config': v('o', f'{BASE}/IP4/1' if connected else '/'),
                               'Ip6Config': v('o', '/')}}
            if kind == 2:
                device[WIRELESS] = {'AccessPoints': v('ao', list(result)[:6] if index == 1 else []),
                                    'ActiveAccessPoint': v('o', active_ap if index == 1 else '/'), 'Bitrate': v('u', 300000)}
            result[path] = device
        result[f'{BASE}/IP4/1'] = {f'{NM}.IP4Config': {
            'AddressData': v('aa{sv}', [{'address': v('s', '10.0.0.2'), 'prefix': v('u', 24)}]),
            'Gateway': v('s', '10.0.0.1'), 'NameserverData': v('aa{sv}', [{'address': v('s', '10.0.0.1')}])}}
        if active:
            connection = self.profiles.get(active['profile'], {}).get('connection', {})
            result[active['path']] = {ACTIVE: {'Uuid': connection.get('uuid', v('s', 'gone')),
                                               'Id': connection.get('id', v('s', 'gone')),
                                               'Type': v('s', '802-11-wireless'), 'State': v('u', active['state'])}}
        for path in self.profiles:
            result[path] = {CONNECTION: {'Flags': v('u', self.flags.get(path, 0))}}
        return result


def stub():
    instance = Stub()
    instance.secrets[next(iter(instance.profiles))] = None
    instance.loop.run()


def call(method, *args, ok=True):
    result = subprocess.run(
        ['gdbus', 'call', '--session', '--dest', BUS, '--object-path', '/top/remya/settings',
         '--method', f'{INTERFACE}.{method}', *args], capture_output=True, text=True, timeout=30)
    if not ok:
        assert result.returncode != 0, (args, result.stdout)
        return result.stderr
    assert result.returncode == 0, (args, result.stderr)
    return json.loads(ast.literal_eval(result.stdout)[0])


def control(method, *args):
    result = subprocess.check_output(
        ['gdbus', 'call', '--address', os.environ['DBUS_SYSTEM_BUS_ADDRESS'], '--dest', NM,
         '--object-path', BASE, '--method', f'top.remya.smoke.Control.{method}', *args], text=True, timeout=10)
    return json.loads(ast.literal_eval(result)[0]) if method == 'Calls' else None


def wait(predicate, what):
    for _ in range(100):
        state = call('Get', 'network')
        if predicate(state):
            return state
        time.sleep(0.1)
    raise AssertionError(f'{what}: {json.dumps(state)[:600]}')


def checks():
    state = wait(lambda s: s['available'], 'stub should be readable')
    assert state['initialized'] and state['writable'] and not state['conflict']
    assert sorted(d['interface'] for d in state['devices']) == ['eth0', 'wlan0', 'wlan1']
    assert state['adapter'] == 'wlan0'
    networks = {n['ssid']: n for n in next(d for d in state['devices'] if d['interface'] == 'wlan0')['networks']}
    assert networks['Home']['signal'] == 80 and networks['Home']['known_uuid'] == 'home-uuid'
    assert networks['Corp']['security'] == 'enterprise' and networks['Old']['security'] == 'wep'
    assert networks['Free']['security'] == 'open' and networks['Cafe']['security'] == 'wpa2'

    # Radio, scan and adapter choice reach the expected objects.
    assert call('Set', 'wifi.enabled', 'false')['wifi_enabled'] is False
    assert 'Unavailable' in call('Set', 'wifi.refresh', 'scan', ok=False)
    assert call('Set', 'wifi.enabled', 'true')['wifi_enabled'] is True
    call('Set', 'wifi.adapter', 'wlan1')
    call('Set', 'wifi.refresh', 'scan')
    assert f'RequestScan {BASE}/Devices/2' in control('Calls')
    call('Set', 'wifi.adapter', 'wlan0')

    # Unavailable and malformed requests are rejected without simulating success.
    assert 'Unavailable' in call('Set', 'known-networks.mac', 'stable', ok=False)
    assert 'Unavailable' in call('Set', 'network-status.data-usage', 'open', ok=False)
    assert 'Unavailable' in call('Set', 'wifi.connect', '{"ssid":"Corp","password":"long-enough"}', ok=False)
    assert 'Unavailable' in call('Set', 'wifi.connect', '{"ssid":"Old","password":"long-enough"}', ok=False)
    assert 'InvalidArgument' in call('Set', 'wifi.connect', '{"ssid":"Cafe","password":"short"}', ok=False)

    # A wrong password leaves no profile and asks again.
    call('Set', 'wifi.connect', '{"ssid":"Cafe","password":"wrong-password"}')
    state = wait(lambda s: s['failure'], 'wrong password should fail')
    assert state['failure']['needs_password'] and state['connecting'] is None
    assert not any(p['ssid'] == 'Cafe' for p in state['profiles'])
    assert 'persist memory' in control('Calls')

    # The right password connects, then saves.
    call('Set', 'wifi.connect', '{"ssid":"Cafe","password":"right-password"}')
    state = wait(lambda s: any(p['ssid'] == 'Cafe' for p in s['profiles']) and s['connecting'] is None, 'should save')
    assert any(c.startswith('Save ') for c in control('Calls'))
    assert state['primary_uuid'] and call('Get', 'network-status.ipv4')['value'] == ['10.0.0.2/24']
    assert call('Get', 'wifi.current')['value']['ssid'] == 'Cafe'
    assert call('Get', 'network-traffic')['interface'] == 'wlan0'

    call('Set', 'wifi.disconnect', 'disconnect')
    assert wait(lambda s: s['primary_uuid'] is None, 'should disconnect')

    # Saved networks: activation, preferences and secret handling.
    call('Set', 'wifi.connect', '{"uuid":"home-uuid"}')
    wait(lambda s: s['primary_uuid'] == 'home-uuid', 'known network should activate')
    call('Set', 'wifi.disconnect', 'disconnect')
    call('Set', 'known-networks.add', '{"ssid":"Lab","security":"wpa3","password":"long-enough","hidden":true,"autoconnect":false}')
    state = call('Get', 'network')
    lab = next(p for p in state['profiles'] if p['ssid'] == 'Lab')
    assert lab['security'] == 'wpa3' and lab['hidden'] is True
    assert not lab['autoconnect']
    uuid = lab['uuid']
    for setting, value, field in (('autoconnect', 'true', 'autoconnect'), ('metered', '"yes"', 'metered')):
        call('Set', f'known-networks.{setting}', f'{{"uuid":"{uuid}","value":{value}}}')
        lab = next(p for p in call('Get', 'network')['profiles'] if p['uuid'] == uuid)
        assert lab[field] == json.loads(value)
    assert 'InvalidArgument' in call('Set', 'known-networks.metered', f'{{"uuid":"{uuid}","value":"maybe"}}', ok=False)
    assert 'Unavailable' in call('Set', 'known-networks.priority', f'{{"uuid":"{uuid}","value":5}}', ok=False)
    call('Set', 'known-networks.change-password', f'{{"uuid":"{uuid}","value":"another-password"}}')
    assert 'psk-flags 0' in control('Calls')

    # Conflict resolution in both directions.
    control('ExternalMetered', uuid, '2')
    state = wait(lambda s: s['conflict'], 'external change should conflict')
    assert state['conflicts'][0]['saved']['metered'] == 'yes' and state['conflicts'][0]['system']['metered'] == 'no'
    assert 'Conflict' in call('Set', 'known-networks.autoconnect', f'{{"uuid":"{uuid}","value":false}}', ok=False)
    assert not call('Resolve', 'network', 'settings')['conflict']
    control('ExternalMetered', uuid, '0')
    wait(lambda s: s['conflict'], 'second change should conflict')
    assert not call('Resolve', 'network', 'system')['conflict']
    assert next(p for p in call('Get', 'network')['profiles'] if p['uuid'] == uuid)['metered'] == 'automatic'

    call('Set', 'known-networks.forget', uuid)
    assert not any(p['uuid'] == uuid for p in call('Get', 'network')['profiles'])

    # Inventory changes never conflict; a stopped service is reported, not simulated.
    assert not call('Get', 'network')['conflict']
    control('Quit')
    state = wait(lambda s: not s['available'], 'stopped NetworkManager should be reported')
    assert state['error'] and 'devices' not in state
    assert 'Unavailable' in call('Set', 'known-networks.mac', 'x', ok=False)
    assert 'NetworkManager' in call('Set', 'wifi.enabled', 'true', ok=False)
    call('Quit')


def session(binary, root):
    assert os.environ['DBUS_SYSTEM_BUS_ADDRESS'].startswith('unix:path=' + root), 'refusing the real system bus'
    log = open(Path(root) / 'signals.log', 'w')
    monitor = subprocess.Popen(['dbus-monitor', '--session'], stdout=log, stderr=subprocess.DEVNULL)
    service = subprocess.Popen([binary, '--debug-root', root])
    try:
        for _ in range(50):
            if subprocess.run(['gdbus', 'call', '--session', '--dest', BUS, '--object-path', '/top/remya/settings',
                               '--method', f'{INTERFACE}.Get', 'about'], capture_output=True).returncode == 0:
                break
            time.sleep(0.1)
        checks()
    finally:
        service.terminate()
        service.wait(timeout=10)
        monitor.terminate()
        monitor.wait(timeout=5)
        log.close()
    # Requests necessarily carry passwords, but nothing the service emits may.
    text = (Path(root) / 'signals.log').read_text()
    messages = re.split(r'\n(?=(?:signal|method call|method return|error) )', text)
    emitted = [m for m in messages if not m.startswith('method call')]
    assert len(emitted) > 10 and not any(
        secret in m for m in emitted
        for secret in ('right-password', 'wrong-password', 'another-password'))
    assert 'password' not in (Path(root) / 'config/network.toml').read_text()


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--stub':
        stub()
        return
    if len(sys.argv) > 1 and sys.argv[1] == '--session':
        session(sys.argv[2], sys.argv[3])
        return
    profile = sys.argv[1] if len(sys.argv) > 1 else 'debug'
    binary = ROOT / 'target' / profile / 'remya-settings-service'
    with tempfile.TemporaryDirectory(prefix='remya-network-smoke-') as root:
        (Path(root) / 'config').mkdir()
        address = f'unix:path={root}/system-bus'
        daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', f'--address={address}'])
        environment = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address, HOME=root,
                           XDG_CONFIG_HOME=f'{root}/c', XDG_DATA_HOME=f'{root}/d', XDG_CACHE_HOME=f'{root}/k',
                           XDG_STATE_HOME=f'{root}/s', GIO_USE_VFS='local', GSETTINGS_BACKEND='keyfile')
        time.sleep(0.3)
        stubbed = subprocess.Popen([sys.executable, __file__, '--stub'], env=environment)
        time.sleep(0.5)
        try:
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session', str(binary), root],
                           env=environment, check=True, timeout=120)
        finally:
            stubbed.terminate()
            daemon.terminate()
            stubbed.wait(timeout=5)
            daemon.wait(timeout=5)
    print('Network smoke passed')


if __name__ == '__main__':
    main()
