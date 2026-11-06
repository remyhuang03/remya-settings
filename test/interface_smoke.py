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


def default_apps_fixtures(environment):
    applications = Path(environment['XDG_DATA_HOME']) / 'applications'
    applications.mkdir(parents=True, exist_ok=True)
    types = 'application/x-remya-smoke;text/plain;x-scheme-handler/http;x-scheme-handler/https;'
    for name in ('a', 'b'):
        (applications / f'remya-smoke-{name}.desktop').write_text(
            f'[Desktop Entry]\nType=Application\nName=Remya smoke {name}\nExec=/usr/bin/true %U\nMimeType={types}\n')
    subprocess.run(['update-desktop-database', str(applications)], check=True, env=environment)
    config = Path(environment['XDG_CONFIG_HOME'])
    config.mkdir(parents=True, exist_ok=True)
    (config / 'mimeapps.list').write_text('[Default Applications]\napplication/x-remya-smoke=remya-smoke-a.desktop;\n')


def appimage_fixture(home):
    """A real release with damaged blocks, so the update must fetch a zsync delta."""
    source = Path.home() / 'AppImages/GridCraft.AppImage'
    target = home / 'Downloads %/Grid Craft.AppImage'
    target.parent.mkdir()
    data = bytearray(source.read_bytes())
    data[len(data) // 2:len(data) // 2 + 65536] = bytes(65536)
    target.write_bytes(data)
    return target


def appimages_wait(predicate, timeout=180):
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        state = cli('get', 'appimages')
        seen.append(state)
        if predicate(state):
            return state, seen
        time.sleep(0.15)
    raise AssertionError(('AppImage state did not settle', seen[-1]))


def appimages_checks():
    home = Path(os.environ['HOME'])
    data = Path(os.environ['XDG_DATA_HOME'])
    fixture = home / 'Downloads %/Grid Craft.AppImage'
    assert 'InvalidArgument' in cli('set', 'appimages.install', 'relative.AppImage', ok=False)
    assert 'InvalidArgument' in cli('set', 'appimages.install', str(home / 'hyprland.lua'), ok=False)
    assert cli('install-appimage', str(fixture)) == {'installing': fixture.name}
    state, _ = appimages_wait(lambda s: not s['installing'] and s['apps'])
    assert state['error'] is None and fixture.exists(), state
    app = state['apps'][0]
    image = home / 'AppImages/GridCraft.AppImage'
    assert app['id'] == image.name and app['integrated'] and app['source_origin'] == 'embedded', app
    # Exec escapes the '%' in this HOME as '%%', so match the file name.
    entries = [e for e in (data / 'applications').glob('*.desktop') if '/AppImages/GridCraft.AppImage' in e.read_text()]
    assert len(entries) == 1, entries
    subprocess.run(['desktop-file-validate', str(entries[0])], check=True)
    assert 'Icon=' + str(data / 'icons') in entries[0].read_text()
    assert cli('get', 'appimages') == dbus('Get', 'appimages')
    assert 'InvalidArgument' in cli('set', 'appimages.uninstall', 'missing.AppImage', ok=False)
    assert 'InvalidArgument' in cli('set', 'appimages.source', json.dumps({'id': app['id'], 'source': 'http://example.org/a.zsync', 'updates': True}), ok=False)
    cli('set', 'appimages.source', json.dumps({'id': app['id'], 'source': 'https://github.com/storytold/gridcraft', 'updates': True}))
    assert cli('get', 'appimages')['apps'][0]['source_origin'] == 'custom'
    dbus('Set', 'appimages.source', json.dumps({'id': app['id'], 'source': None, 'updates': True}))
    assert cli('get', 'appimages')['apps'][0]['source_origin'] == 'embedded'
    monitor = subprocess.Popen(['gdbus', 'monitor', '--session', '--dest', BUS], stdout=subprocess.PIPE, text=True)
    try:
        assert cli('set', 'appimages.check', app['id']) == {'started': [app['id']]}
        state, _ = appimages_wait(lambda s: s['apps'][0]['job'] is None)
        assert state['apps'][0]['available'] and state['apps'][0]['error'] is None, state
        assert dbus('Set', 'appimages.update', 'all') == {'started': [app['id']]}
        state, seen = appimages_wait(lambda s: s['apps'][0]['job'] is None, timeout=900)
    finally:
        monitor.terminate()
        signals = monitor.communicate(timeout=5)[0]
    assert state['apps'][0]['error'] is None and state['apps'][0]['available'] is None, state
    jobs = [s['apps'][0]['job'] for s in seen if s['apps'][0]['job']]
    assert any(j['status'] == 'downloading' and 0 < j['bytes'] <= j['total'] for j in jobs), jobs
    assert signals.count("'appimages'") >= 3, signals[-2000:]
    # The re-check below compares the file with the release's published checksum.
    assert os.access(image, os.X_OK)
    assert not [p for p in image.parent.iterdir() if p.name.startswith('.')]
    cli('set', 'appimages.check', 'all')
    state, _ = appimages_wait(lambda s: s['apps'][0]['job'] is None)
    assert state['apps'][0]['checked'] and not state['apps'][0]['available'] and state['last_check'] > 0, state
    assert cli('set', 'appimages.auto-update', 'true') == {'id': 'appimages.auto-update', 'value': True}
    assert 'InvalidArgument' in cli('set', 'appimages.auto-check', 'maybe', ok=False)
    assert cli('set', 'appimages.uninstall', app['id']) == {'removed': app['id']}
    assert not image.exists() and not entries[0].exists()
    assert (data / 'Trash/files/GridCraft.AppImage').exists()
    assert cli('get', 'appimages')['apps'] == []
    print('PASS: AppImage install without execution, launcher, sources, zsync delta update with live progress signals, checksum readback, Trash removal and CLI/D-Bus parity', flush=True)


def night_light_checks():
    # Isolated XDG roots do not isolate the user's systemd, so only paths that cannot
    # restart hyprsunset run here; writes are covered by the Rust tests and on the desktop.
    state = cli('get', 'night-light')
    assert state == dbus('Get', 'night-light')
    assert state['conflict'] is False and state['temperature'] == 6000
    for bad in ('999', 'warm'):
        assert 'InvalidArgument' in cli('set', 'night-light.temperature', bad, ok=False)
    assert 'Unavailable' in cli('set', 'night-light.50840111', 'Set hours', ok=False)


def default_apps_checks():
    mime = 'application/x-remya-smoke'
    setting = 'defaults.b131ac5a'
    state = cli('get', 'default-apps')
    assert state == dbus('Get', 'default-apps')
    assert state['initialized'] and state['writable'] and not state['conflict'] and state['error'] is None
    assert state['saved'][mime] == state['system'][mime] == 'remya-smoke-a.desktop'
    assert cli('get', 'default-types:remya-smoke')['types'] == [{'type': mime, 'application': 'remya-smoke-a.desktop'}]
    assert any(t['type'] == 'application/pdf' for t in cli('get', 'default-types:.pdf')['types'])
    applications = cli('get', 'default-applications:Remya smoke')['applications']
    assert {a['id'] for a in applications} == {'remya-smoke-a.desktop', 'remya-smoke-b.desktop'}
    assert cli('get', 'default-applications:Remya smoke') == dbus('Get', 'default-applications:Remya smoke')
    assert len(cli('get', 'default-candidates:' + mime)['applications']) == 2
    request = json.dumps({'application': 'remya-smoke-b.desktop', 'types': [mime]})
    state = cli('set', setting, request)
    assert state['saved'][mime] == state['system'][mime] == 'remya-smoke-b.desktop'
    output = subprocess.check_output(['gio', 'mime', mime], text=True)
    assert 'remya-smoke-b.desktop' in output.splitlines()[0], output
    assert 'InvalidArgument' in cli('set', setting, json.dumps({'application': '../bad.desktop', 'types': [mime]}), ok=False)
    assert 'InvalidArgument' in cli('set', setting, json.dumps({'application': 'remya-smoke-b.desktop', 'types': ['image/png']}), ok=False)
    subprocess.run(['gio', 'mime', mime, 'remya-smoke-a.desktop'], check=True, stdout=subprocess.DEVNULL)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        state = cli('get', 'default-apps')
        if state['conflict'] and state['system'][mime] == 'remya-smoke-a.desktop':
            break
        time.sleep(0.2)
    else:
        raise AssertionError(('No external default conflict', state))
    assert 'Conflict' in cli('set', setting, request, ok=False)
    assert not dbus('Resolve', 'default-apps', 'settings')['conflict']
    assert cli('get', 'default-apps')['system'][mime] == 'remya-smoke-b.desktop'
    subprocess.run(['gio', 'mime', mime, 'remya-smoke-a.desktop'], check=True, stdout=subprocess.DEVNULL)
    deadline = time.monotonic() + 8
    while cli('get', 'default-apps')['system'][mime] != 'remya-smoke-a.desktop':
        assert time.monotonic() < deadline
        time.sleep(0.2)
    assert not cli('resolve', 'default-apps', 'system')['conflict']
    assert cli('get', 'default-apps')['saved'][mime] == 'remya-smoke-a.desktop'
    browser = json.dumps({'application': 'remya-smoke-b.desktop'})
    state = dbus('Set', 'defaults.ccac113f', browser)
    assert all(state['system']['x-scheme-handler/' + scheme] == 'remya-smoke-b.desktop' for scheme in ('http', 'https'))
    assert cli('get', 'defaults.ccac113f')['value'] == dbus('Get', 'defaults.ccac113f')['value']
    config = Path(os.environ['XDG_CONFIG_HOME']) / 'mimeapps.list'
    valid = config.read_text()
    config.write_text('invalid [')
    failed = cli('get', 'default-apps')
    assert failed['error'] and not failed['writable'] and failed['saved'] == state['saved']
    config.write_text(valid)
    assert cli('get', 'default-apps')['writable']
    assert 'Unavailable' in cli('set', 'defaults.ff4c4bec', 'true', ok=False)
    print('PASS: isolated XDG defaults, real GIO writes/readback, external conflicts, both resolutions, validation, browser group and CLI/D-Bus parity', flush=True)


def installed_apps_fixture(environment):
    root=Path(environment['HOME']) / 'flatpak-fixture'
    build=root / 'build'
    (build / 'files/bin').mkdir(parents=True)
    (build / 'files/bin/smoke').write_text('#!/bin/sh\nexit 0\n')
    (build / 'files/bin/smoke').chmod(0o755)
    (build / 'export/share/applications').mkdir(parents=True)
    (build / 'metadata').write_text('[Application]\nname=org.remya.InstalledSmoke\nruntime=org.remya.SmokePlatform/x86_64/1\ncommand=smoke\n')
    (build / 'export/share/applications/org.remya.InstalledSmoke.desktop').write_text('[Desktop Entry]\nType=Application\nName=Remya Installed Smoke\nExec=smoke\n')
    subprocess.run(['flatpak','build-export',str(root/'repo'),str(build),'stable'],env=environment,check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['flatpak','install','--user','--assumeyes','--noninteractive','--no-deps','--no-related',str(root/'repo'),'org.remya.InstalledSmoke'],env=environment,check=True,stdout=subprocess.DEVNULL)
    data=Path(environment['HOME']) / '.var/app/org.remya.InstalledSmoke/retain'
    data.parent.mkdir(parents=True);data.write_text('retain application data')


def installed_apps_checks():
    state=cli('get','installed-apps')
    assert state==dbus('Get','installed-apps')
    assert not state['warnings'],state['warnings']
    app=next(a for a in state['applications'] if a['id'].startswith('flatpak:user:org.remya.InstalledSmoke/'))
    assert app['uninstallable'] and app['size']>0 and app['token']
    assert cli('get','installed-app:'+app['id'])==app
    query='installed-apps:'+json.dumps({'query':app['name'],'sort':'size','source':'flatpak-user'})
    assert cli('get',query)==dbus('Get',query)
    assert cli('get',query)['applications']==[app]
    assert 'InvalidArgument' in cli('get','installed-apps:{"sort":"invalid"}',ok=False)
    native=next(a for a in state['applications'] if a['source']=='pacman')
    version=subprocess.check_output(['pacman','-Q',native['package']],text=True).split()[1]
    assert version==native['version'] and native['installed']>0
    assert 'authorize' in cli('set','installed.c3c4a29c',json.dumps({'id':native['id'],'token':native['token']}),ok=False).lower()
    assert 'Conflict' in cli('set','installed.c3c4a29c',json.dumps({'id':app['id'],'token':'outdated'}),ok=False)
    request=json.dumps({'id':app['id'],'token':app['token']})
    assert dbus('Set','installed.c3c4a29c',request)=={'removed':app['id']}
    assert not any(a['id']==app['id'] for a in cli('get','installed-apps')['applications'])
    assert (Path(os.environ['HOME'])/'.var/app/org.remya.InstalledSmoke/retain').read_text()=='retain application data'
    assert cli('get','calendar-date:2026-11-02')==dbus('Get','calendar-date:2026-11-02')
    print('PASS: native package readback and authorization rejection, real isolated user Flatpak uninstall, stale-version rejection, retained data, CLI/D-Bus parity',flush=True)


def bar_clock_checks():
    setting = 'remya-bar.clock-seconds'
    config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/remya-bar.toml'
    assert not config.exists()
    assert cli('get', setting) == dbus('Get', setting) == {
        'id': setting, 'availability': 'available', 'value': True,
    }
    monitor = subprocess.Popen(
        ['stdbuf', '-oL', 'gdbus', 'monitor', '--session', '--dest', BUS],
        stdout=subprocess.PIPE,
    )
    try:
        assert select.select([monitor.stdout], [], [], 5)[0]
        os.read(monitor.stdout.fileno(), 4096)
        assert cli('set', setting, 'false') == dbus('Get', setting)
        assert cli('get', setting)['value'] is False
        assert select.select([monitor.stdout], [], [], 5)[0]
    finally:
        monitor.terminate()
        signals = monitor.communicate(timeout=5)[0].decode()
    assert f"'{setting}'" in signals, signals
    assert config.read_text().strip() == 'clock_seconds = false'
    assert 'InvalidArgument' in cli('set', setting, 'maybe', ok=False)
    assert cli('get', setting)['value'] is False
    assert dbus('Set', setting, 'true') == cli('get', setting)
    assert cli('get', setting)['value'] is True
    config.write_text('clock_seconds = "invalid"\n')
    cli('get', setting, ok=False)
    cli('set', setting, 'false', ok=False)
    assert config.read_text() == 'clock_seconds = "invalid"\n'
    config.unlink()
    print('PASS: Bar clock default, CLI and D-Bus read/write parity, Changed, persistence and invalid input')


def bar_tray_checks():
    setting = 'remya-bar.folded-apps'
    config = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/remya-bar-tray.toml'
    assert cli('get', setting) == dbus('Get', setting)
    assert cli('get', setting)['value'] == []
    assert cli('set', setting, '{"id":"app-a","folded":true}') == dbus('Get', setting)
    assert dbus('Set', setting, '{"id":"app-b","folded":true}') == cli('get', setting)
    assert cli('get', setting)['value'] == ['app-a', 'app-b']
    assert cli('set', setting, '{"id":"app-a","folded":false}')['value'] == ['app-b']
    assert 'InvalidArgument' in cli('set', setting, '{"id":"","folded":true}', ok=False)
    assert cli('get', setting)['value'] == ['app-b']
    config.write_text('folded_apps = false\n')
    cli('set', setting, '{"id":"app-b","folded":false}', ok=False)
    assert config.read_text() == 'folded_apps = false\n'
    config.unlink()
    print('PASS: Bar tray CLI and D-Bus parity, per-app edits, validation and persistence')


def session_checks():
    pid = None
    watcher = None
    bar = None
    before = None
    try:
        initial = cli('get', 'theme')
        tools = cli('get', 'input-method-tools')
        assert tools == dbus('Get', 'input-method-tools')
        for group in ('time','system','appearance'):
            assert cli('get','external-tools:'+group) == dbus('Get','external-tools:'+group)
        assert 'InvalidArgument' in cli('get','external-tools:unknown',ok=False)
        for tool in cli('get','external-tools:system')['tools']:
            if tool.get('launch_error'):
                assert 'Unavailable' in cli('set',tool['id'],'open',ok=False)
        for group, entries in {'system':[('system-more.kde','systemsettings'),('system-more.gnome','gnome-control-center'),('system-more.localsend','localsend')],'appearance':[('appearance-more.qt6ct','qt6ct'),('appearance-more.kvantum','kvantummanager'),('appearance-more.gtk','nwg-look'),('appearance-more.gnome-tweaks','gnome-tweaks')]}.items():
            assert {t['id'] for t in cli('get','external-tools:'+group)['tools']} == {id for id,binary in entries if os.access('/usr/bin/'+binary,os.X_OK)}
        assert {t['id'] for t in tools['tools']} == {id for id, binary in [('time-more.fcitx5','fcitx5-configtool'),('time-more.ibus','ibus-setup')] if os.access('/usr/bin/'+binary, os.X_OK)}
        assert 'InvalidArgument' in cli('set','time-more.fcitx5','invalid',ok=False)
        pid = service_pid()
        assert initial == dbus('Get', 'theme')
        bar_clock_checks()
        bar_tray_checks()
        default_apps_checks()
        night_light_checks()
        installed_apps_checks()
        appimages_checks()
        # Read-only here: test/network_smoke.py exercises writes on a private stub.
        assert set(cli('get', 'network')) == set(dbus('Get', 'network'))
        assert cli('get', 'wifi.enabled')['availability'] == 'available'
        assert 'Unavailable' in cli('set', 'known-networks.mac', 'stable', ok=False)
        assert 'InvalidArgument' in cli('set', 'wifi.connect', 'not json', ok=False)
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
        assert any(control['availability'] == 'available' for control in controls)
        unavailable = next(control for control in controls if control['availability'] != 'available')
        assert 'Unavailable' in cli('set', unavailable['id'], 'true', ok=False)
        assert 'InvalidArgument' in cli('set', 'themes.material-theme-mode', 'system', ok=False)
        assert cli('get', unavailable['id'])['availability'] != 'available'
        # Background writes reach the real desktop, so only reads and rejections run here.
        background = cli('get', 'background')
        assert background['initialized'] and background == dbus('Get', 'background')
        assert cli('get', 'configuration')['background']['initialized']
        assert (Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/background.toml').exists()
        assert 'InvalidArgument' in cli('set', 'background.56c289eb', 'stretch', ok=False)
        assert 'InvalidArgument' in cli('set', 'background.99b01ada', 'slideshow', ok=False)
        assert 'InvalidArgument' in cli('set', 'background.9e58290b', 'relative.png', ok=False)
        assert 'InvalidArgument' in cli('set', 'background.display', 'DP-1', ok=False)
        accent = cli('get', 'accent')
        assert accent['source'] == 'custom' and accent == dbus('Get', 'accent')
        assert not (Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/accent.toml').exists()
        assert cli('set', 'themes.6f67371e', '#123abc')['color'] == '#123ABC'
        assert dbus('Get', 'accent')['color'] == '#123ABC'
        assert cli('get', 'theme')['theme'].keys() == {'style_variant', 'theme_mode'}
        assert 'InvalidArgument' in cli('set', 'themes.6f67371e', 'blue', ok=False)
        assert 'InvalidArgument' in cli('set', 'themes.8983f367', 'other', ok=False)
        cli('set', 'themes.6f67371e', '#8054C9')
        fonts = cli('get', 'fonts')
        assert fonts == dbus('Get', 'fonts') and fonts['families']
        assert fonts['directory'] == str(Path(os.environ['XDG_DATA_HOME']) / 'fonts')
        system_font = next(f for f in fonts['families'] if f['user_files'] == 0 and f['files'][0].endswith(('.ttf', '.otf')))
        assert cli('get', 'font-search:' + system_font['family'])['families']
        assert cli('get', 'font:' + system_font['family']) == system_font
        assert 'whole system' in cli('set', 'fonts.f869cae5', system_font['family'], ok=False)
        assert 'ReadOnly' in cli('set', 'fonts.fc3969c7', system_font['family'], ok=False)
        assert 'InvalidArgument' in cli('set', 'fonts.158ba0bb', '/etc/hostname', ok=False)
        installed = cli('set', 'fonts.158ba0bb', system_font['files'][0])['installed']
        assert installed.startswith(fonts['directory'])
        assert 'already installed' in cli('set', 'fonts.158ba0bb', system_font['files'][0], ok=False)
        assert any(f.startswith(fonts['directory']) for f in cli('get', 'font:' + system_font['family'])['files'])
        assert installed in cli('set', 'fonts.f869cae5', system_font['family'])['removed']
        assert not Path(installed).exists() and Path(system_font['files'][0]).exists()
        hostname = cli('get', 'hostname')
        assert hostname == dbus('Get', 'hostname')
        assert hostname['initialized'] and not hostname['conflict'] and hostname['error'] is None
        assert cli('get', 'about.0f142010')['value'] == hostname['static_hostname']
        hostname_file = Path(os.environ['XDG_CONFIG_HOME']) / 'remya/settings/hostname.toml'
        assert 'static_hostname' in hostname_file.read_text()
        assert 'InvalidArgument' in cli('set', 'about.0f142010', 'Bad Name', ok=False)
        hostname_file.write_text('version = 1\nstatic_hostname = "saved-hostname"\n')
        assert cli('get', 'hostname')['conflict']
        assert cli('get', 'configuration')['hostname']['conflict']
        assert 'Conflict' in cli('set', 'about.0f142010', 'new-hostname', ok=False)
        assert not dbus('Resolve', 'hostname', 'system')['hostname']['conflict']
        assert cli('get', 'hostname')['static_hostname'] == hostname['static_hostname']
        # hostnamed is the real system service: never attempt this once authorized.
        assert not cli('get', 'hostname')['authorized'], 'Refusing to test rename with an authorized helper'
        assert 'authorize' in cli('set', 'about.0f142010', 'new-hostname', ok=False).lower()
        assert cli('get', 'hostname')['error']
        cli('resolve', 'hostname', 'system')
        info = cli('get', 'system-information')
        assert info == dbus('Get', 'system-information')
        assert info['values']
        for setting_id, field in info['values'].items():
            assert (field['value'] is None) != (field['error'] is None)
            assert cli('get', setting_id)['value'] == field['value']
            assert 'ReadOnly' in cli('set', setting_id, 'changed', ok=False)
        assert info['values']['about.4433eb13']['value'] == os.uname().nodename
        assert os.uname().release in info['values']['about.kernel-version']['value']
        cpu_model = next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name'))
        assert cpu_model == info['values']['about.b4366749']['value']
        for setting, filename in {'manufacturer':'sys_vendor', 'model':'product_name', 'model-version':'product_version', 'board-manufacturer':'board_vendor', 'board-model':'board_name', 'firmware-manufacturer':'bios_vendor', 'firmware-version':'bios_version'}.items():
            assert info['values'][f'about.{setting}']['value'] == Path('/sys/class/dmi/id', filename).read_text().strip()
        raw_date = Path('/sys/class/dmi/id/bios_date').read_text().strip()
        month, day, year = raw_date.split('/')
        locale_values = subprocess.check_output(['gdbus', 'call', '--system', '--dest', 'org.freedesktop.locale1', '--object-path', '/org/freedesktop/locale1', '--method', 'org.freedesktop.DBus.Properties.Get', 'org.freedesktop.locale1', 'Locale'], text=True)
        time_locale = re.search(r"'LC_TIME=([^']+)'", locale_values) or re.search(r"'LANG=([^']+)'", locale_values)
        date_env = dict(os.environ, LC_TIME=time_locale[1] if time_locale else 'C', TZ='UTC0')
        date_env.pop('LC_ALL', None)
        expected_date = subprocess.check_output(['/usr/bin/date', '--date', f'{year}-{month}-{day}', '+%x'], env=date_env, text=True).strip()
        assert info['values']['about.firmware-date']['value'] == expected_date
        assert all('\u00b7' not in (field['value'] or '') for field in info['values'].values())
        ram_kib = next(int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:'))
        assert f'{ram_kib / 1024**2:.2f} GiB' == info['values']['about.d014ab77']['value']
        pages = cli('get', 'catalog')['pages']
        assert pages
        for operation, target in [('get', 'page:unknown-page'), ('open', 'unknown-page')]:
            assert 'InvalidArgument' in cli(operation, target, ok=False)
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
        print(f'PASS: installed bar on {len(bars)} outputs follows live D-Bus Light/Dark changes', flush=True)
        assert cli('open', 'system-information') == {'opened': 'system-information'}
        assert cli('open', 'about') == {'opened': 'about'}
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            clients = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))
            if any(client['class'] == 'top.remya.settings' and Path(f"/proc/{client['pid']}/exe").resolve().is_relative_to(Path(os.environ['XDG_DATA_HOME'])) for client in clients):
                break
            time.sleep(0.1)
        else:
            raise AssertionError('Open did not show the settings window')
        for page in ('defaults', 'installed', 'date-time', 'updates'):
            assert cli('open', page) == {'opened': page}
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
        for entry in ('top.remya.settings', 'top.remya.settings.appimage'):
            subprocess.run(['desktop-file-validate', str(home / f'data $/applications/{entry}.desktop')], check=True)
        default_apps_fixtures(environment)
        installed_apps_fixture(environment)
        appimage_fixture(home)
        subprocess.run(['dbus-run-session', '--', sys.executable, str(Path(__file__).resolve()), '--session'],
                       env=environment, check=True, timeout=1200)


if __name__ == '__main__':
    main()
