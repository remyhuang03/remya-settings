"""Check both installers without touching personal data or requiring real builds."""
import importlib.util
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
                (packaging / f'{installer.PACKAGE}.desktop').write_text(
                    f'[Desktop Entry]\nType=Application\nName=Test\nExec={installer.APP_ID}\n')
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
                command.unlink()
                command.write_text('unrelated program')
                with self.assertRaisesRegex(RuntimeError, 'unrelated command'):
                    installer.install(root, environment)
                self.assertEqual(command.read_text(), 'unrelated program')
                self.assertEqual(installed.read_text(), 'version two')


if __name__ == '__main__':
    unittest.main()
