"""Execute packaging on Windows; desktop keyboard delivery is a separate check."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell execution required')
class WindowsPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='jvim-windows-')
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.local = self.home/'fresh local appdata'
        tools = self.home/'tools with spaces'
        tools.mkdir()
        for name in ('nvim', 'rg', 'git'):
            text = '@echo off\n'
            text += 'echo %NVIM_APPNAME%:%~1\nexit /b 17\n' if name == 'nvim' else 'exit /b 0\n'
            (tools/(name+'.cmd')).write_text(text)
        self.env = dict(os.environ, LOCALAPPDATA=str(self.local), PATH=str(tools)+os.pathsep+os.environ['PATH'])
        for name in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'JVIM_NVIM'):
            self.env.pop(name, None)

    def run_script(self, script, *arguments, env=None):
        return subprocess.run([POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script), *arguments],
                              env=env or self.env, capture_output=True, text=True, timeout=30)

    def test_terminal_install_creates_parents_and_launcher_forwards_status(self):
        installed = self.run_script(ROOT/'install-windows.ps1', '-Apply', '-Frontend', 'nvim')
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertTrue((self.local/'jvim/init.lua').is_file())
        launched = self.run_script(self.local/'JensenVim/bin/jvim.ps1', 'file with spaces.cpp')
        self.assertEqual(launched.returncode, 17, launched.stderr)
        self.assertEqual(launched.stdout.strip(), 'jvim:file with spaces.cpp')

    def test_preview_and_xdg_rejection_do_not_create_destinations(self):
        preview = self.run_script(ROOT/'install-windows.ps1', '-Frontend', 'nvim')
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertFalse(self.local.exists())
        env = dict(self.env, XDG_DATA_HOME=str(self.home/'other-data'))
        rejected = self.run_script(ROOT/'install-windows.ps1', '-Apply', '-Frontend', 'nvim', env=env)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('XDG_DATA_HOME', rejected.stderr)
        self.assertFalse(self.local.exists())

    def test_reinstall_preserves_tools_personal_settings_and_backs_up_config(self):
        self.assertEqual(self.run_script(ROOT/'install-windows.ps1', '-Apply', '-Frontend', 'nvim').returncode, 0)
        sentinels = [self.local/'jvim-data/lazy/example/plugin.lua', self.local/'jvim-user/init.lua']
        for path in sentinels:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('preserve')
        (self.local/'jvim/init.lua').write_text('old managed settings')
        result = self.run_script(ROOT/'install-windows.ps1', '-Apply', '-Frontend', 'nvim')
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in sentinels:
            self.assertEqual(path.read_text(), 'preserve')
        saved = list((self.local/'JensenVim/backups').glob('*/jvim/init.lua'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_text(), 'old managed settings')
