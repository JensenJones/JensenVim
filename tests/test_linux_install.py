"""Check the Linux installer in an isolated home."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'posix' and shutil.which('nvim'), 'POSIX shell and Neovim are required')
class LinuxInstallTests(unittest.TestCase):
    def run_installer(self, home, *args):
        env = {key: value for key, value in os.environ.items() if not key.startswith('XDG_')}
        env.update(HOME=str(home), SHELL='/bin/bash')
        return subprocess.run(['sh', str(ROOT/'install-linux.sh'), *args], env=env, capture_output=True, text=True, timeout=30)

    def test_preview_apply_and_reinstall(self):
        with tempfile.TemporaryDirectory(prefix='jvim-linux-') as temporary:
            home = Path(temporary)
            preview = self.run_installer(home)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertIn('Preview only', preview.stdout)
            self.assertEqual(list(home.iterdir()), [], 'preview changed files')

            first = self.run_installer(home, '--apply')
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue((home/'.config/jvim/lua/jvim/init.lua').is_file())
            self.assertFalse(list((home/'.config/jvim').rglob('__pycache__')))
            launcher = home/'.local/bin/jvim'
            self.assertTrue(os.access(launcher, os.X_OK))
            appname = subprocess.run([str(launcher), '--headless', '-u', 'NONE', '-i', 'NONE', '+lua io.write(vim.env.NVIM_APPNAME)', '+qall!'],
                                     env=dict(os.environ, HOME=str(home)), capture_output=True, text=True, timeout=15)
            self.assertEqual(appname.stdout, 'jvim', appname.stderr)

            second = self.run_installer(home, '--apply')
            self.assertEqual(second.returncode, 0, second.stderr)
            backups = list((home/'.local/state/jvim/backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertTrue((backups[0]/'jvim/lua/jvim/init.lua').is_file())
            self.assertEqual((home/'.bashrc').read_text().count('.local/bin'), 1, 'PATH entry duplicated')
