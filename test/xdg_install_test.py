"""Check both installers without touching personal data or requiring real builds."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_installer(repository):
    spec = importlib.util.spec_from_file_location(repository.name, repository / 'tool/install.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class InstallTest(unittest.TestCase):
    def test_xdg_defaults_and_relative_values(self):
        for repository in [ROOT, ROOT.parent / 'remya_bar']:
            installer = load_installer(repository)
            self.assertEqual(installer.data_home({'HOME': '/home/test'}), Path('/home/test/.local/share'))
            self.assertEqual(installer.data_home({'HOME': '/home/test', 'XDG_DATA_HOME': 'relative'}), Path('/home/test/.local/share'))
            self.assertEqual(installer.data_home({'XDG_DATA_HOME': '/custom'}), Path('/custom'))
            with self.assertRaises(ValueError):
                installer.data_home({'HOME': 'relative'})

    def test_install_update_preserves_config_and_rejects_unrelated_commands(self):
        for repository in [ROOT, ROOT.parent / 'remya_bar']:
            installer = load_installer(repository)
            with self.subTest(app=installer.APP_ID), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                home = directory / 'home'
                data = home / 'data $ %'
                root = directory / 'source'
                bundle = root / 'build/linux/x64/release/bundle'
                bundle.mkdir(parents=True)
                executable = bundle / installer.APP_ID
                executable.write_text('version one')
                packaging = root / 'linux/packaging'
                packaging.mkdir(parents=True)
                for entry in (installer.PACKAGE, f'{installer.PACKAGE}.appimage'):
                    (packaging / f'{entry}.desktop').write_text(
                        f'[Desktop Entry]\nType=Application\nName=Test\nExec={installer.APP_ID} %f\n')
                (root / 'assets/icons').mkdir(parents=True)
                icon = 'bar.svg' if installer.APP_ID == 'remya_bar' else 'settings.svg'
                (root / 'assets/icons' / icon).write_text('<svg/>')
                (data / 'applications').mkdir(parents=True)
                (data / 'applications/top.remya.settings.desktop').write_text('dependency')
                config = home / '.config/remya/settings/config.toml'
                config.parent.mkdir(parents=True)
                config.write_text('preserve me')
                environment = {'HOME': str(home), 'XDG_DATA_HOME': str(data), 'XDG_DATA_DIRS': '/nonexistent'}
                with patch.object(installer.shutil, 'which', return_value=None):
                    installer.install(root, environment)
                    executable.write_text('version two')
                    installer.install(root, environment)
                installed = data / 'remya' / installer.APP_ID / installer.APP_ID
                self.assertEqual(installed.read_text(), 'version two')
                command = home / '.local/bin' / installer.APP_ID
                self.assertEqual(command.resolve(), installed)
                self.assertEqual(config.read_text(), 'preserve me')
                if installer.APP_ID == 'remya_settings':
                    unit = (data / 'systemd/user/top.remya.settings.service').read_text()
                    self.assertIn('BusName=top.remya.settings.Service1', unit)
                    self.assertIn('WantedBy=graphical-session.target', unit)
                    self.assertIn('ExecStart="' + str(installed).replace('$', '$$').replace('%', '%%') + '" --service', unit)
                    service = (data / 'dbus-1/services/top.remya.settings.Service1.service').read_text()
                    self.assertIn('SystemdService=top.remya.settings.service', service)
                command.unlink()
                command.write_text('unrelated program')
                with self.assertRaisesRegex(RuntimeError, 'unrelated command'):
                    installer.install(root, environment)
                self.assertEqual(command.read_text(), 'unrelated program')
                self.assertEqual(installed.read_text(), 'version two')


class SystemUpdaterTest(unittest.TestCase):
    def test_rule_allows_only_fixed_upgrades_for_one_valid_user(self):
        spec = importlib.util.spec_from_file_location('system_updater', ROOT / 'tool/install_system_updater.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        rule = module.rule('remy')
        self.assertIn(module.MARKER, rule)
        self.assertIn('subject.user == "remy"', rule)
        self.assertIn('command == "/usr/local/libexec/remya-settings-update upgrade"', rule)
        self.assertIn('command == "/usr/local/libexec/remya-settings-update upgrade --include-held"', rule)
        self.assertEqual(rule.count('polkit.Result.YES'), 1)
        for bad in ['', 'Remy', 'a" || true || "', 'x' * 40]:
            with self.assertRaises(ValueError):
                module.rule(bad)
        if os.geteuid() != 0:
            with self.assertRaisesRegex(SystemExit, 'sudo'):
                module.main(ROOT, {})


if __name__ == '__main__':
    unittest.main()
