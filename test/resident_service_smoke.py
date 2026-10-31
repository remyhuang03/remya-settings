"""Verify native residency, repeated GUI close/reopen and PSS on an isolated bus."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / 'build/linux/x64/release/bundle'


def pss(pid):
    fields = dict(line.split(':', 1) for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines() if ':' in line)
    return int(fields['Pss'].split()[0])


def checks():
    service = subprocess.Popen([str(BUNDLE / 'libexec/remya-settings-service')])
    gui = None
    cli = BUNDLE / 'libexec/remya_settings_cli'
    def call(*args):
        result = subprocess.run([str(cli), *args], capture_output=True, text=True, timeout=35)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)
    try:
        deadline = time.monotonic() + 10
        while True:
            try:
                call('get', 'theme')
                break
            except AssertionError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(.1)
        initial = pss(service.pid)
        rounds = []
        for _ in range(3):
            # The private GUI entrypoint exercises real window closure without
            # requiring an administrator password in an isolated test session.
            gui = subprocess.Popen([str(BUNDLE / 'remya_settings'), '--gui', 'date-time'])
            deadline = time.monotonic() + 15
            while True:
                clients = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))
                if any(c['pid'] == gui.pid for c in clients):
                    break
                assert gui.poll() is None, 'GUI failed to start'
                assert time.monotonic() < deadline, 'GUI did not map'
                time.sleep(.1)
            time.sleep(.5)
            visible = pss(service.pid) + pss(gui.pid)
            call('close')
            gui.wait(timeout=10)
            assert call('get', 'date-time')['timezone']
            closed = pss(service.pid)
            assert visible > closed + 20 * 1024, (visible, closed)
            rounds.append({'visible_pss_kib': visible, 'closed_pss_kib': closed})
            gui = None
        assert max(r['closed_pss_kib'] for r in rounds) - initial < 5 * 1024, 'Resident memory grew unexpectedly'
        output = {'native_initial_pss_kib': initial, 'rounds': rounds}
        (ROOT / 'build/resident-memory.json').write_text(json.dumps(output, indent=2))
        print('PASS: native residency, 3 GUI close/reopen rounds, engine memory released:', output)
        call('quit')
        service.wait(timeout=10)
    finally:
        if gui is not None and gui.poll() is None:
            gui.terminate()
            gui.wait(timeout=10)
        if service.poll() is None:
            service.terminate()
            service.wait(timeout=10)


if __name__ == '__main__':
    if '--session' in sys.argv:
        checks()
    else:
        with tempfile.TemporaryDirectory(prefix='remya-resident-') as temporary:
            environment = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary + '/config',
                               XDG_DATA_HOME=temporary + '/data', GSETTINGS_BACKEND='keyfile',
                               GIO_USE_VFS='local', NO_AT_BRIDGE='1', GTK_USE_PORTAL='0')
            subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--session'], env=environment, check=True, timeout=90)
