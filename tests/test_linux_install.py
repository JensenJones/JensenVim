"""Check the Linux installer in an isolated home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'posix' and shutil.which('nvim'), 'POSIX shell and Neovim are required')
class LinuxInstallTests(unittest.TestCase):
    def run_installer(self, home, *args, shell='/bin/bash'):
        env = {key: value for key, value in os.environ.items() if not key.startswith('XDG_')}
        env.update(HOME=str(home), SHELL=shell)
        return subprocess.run(['sh', str(ROOT/'install-linux.sh'), *args], env=env, capture_output=True, text=True, timeout=30)

    def test_fish_users_get_the_launcher_folder_on_path(self):
        with tempfile.TemporaryDirectory(prefix='jvim-linux-') as temporary:
            home = Path(temporary)
            result = self.run_installer(home, '--apply', shell='/usr/bin/fish')
            self.assertEqual(result.returncode, 0, result.stderr)
            fish = home/'.config/fish/config.fish'
            self.assertEqual(fish.read_text(), 'fish_add_path -g "$HOME/.local/bin"\n')
            self.assertFalse((home/'.profile').exists())

    def test_preview_apply_and_reinstall(self):
        with tempfile.TemporaryDirectory(prefix='jvim-linux-') as temporary:
            home = Path(temporary)
            before = sorted(path.name for path in (ROOT/'config').iterdir())
            preview = self.run_installer(home)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertIn('Preview only', preview.stdout)
            self.assertEqual(list(home.iterdir()), [], 'preview changed files')

            first = self.run_installer(home, '--apply')
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue((home/'.config/jvim').is_symlink())
            self.assertEqual((home/'.config/jvim').resolve(), (ROOT/'config').resolve())
            share = home/'.local/share/jvim'
            self.assertEqual((share/'wezterm.lua').resolve(), (ROOT/'integrations/wezterm/jvim.lua').resolve())
            self.assertEqual((share/'wezterm-config.lua').resolve(), (ROOT/'integrations/wezterm/wezterm.lua').resolve())
            self.assertEqual((home/'.wezterm.lua').read_text(), (ROOT/'integrations/wezterm/starter.lua').read_text())
            (home/'.wezterm.lua').write_text('my own wezterm settings')
            launcher = home/'.local/bin/jvim'
            self.assertTrue(os.access(launcher, os.X_OK))
            appname = subprocess.run([str(launcher), '--headless', '-u', 'NONE', '-i', 'NONE', '+lua io.write(vim.env.NVIM_APPNAME)', '+qall!'],
                                     env=dict(os.environ, HOME=str(home)), capture_output=True, text=True, timeout=15)
            self.assertEqual(appname.stdout, 'jvim', appname.stderr)

            second = self.run_installer(home, '--apply')
            self.assertEqual(second.returncode, 0, second.stderr)
            backups = list((home/'.local/state/jvim/backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertTrue((backups[0]/'launcher').is_file())
            self.assertEqual(sorted(path.name for path in (ROOT/'config').iterdir()), before, 'reinstalling wrote into the repository')
            self.assertEqual((home/'.bashrc').read_text().count('.local/bin'), 1, 'PATH entry duplicated')
            self.assertEqual((home/'.wezterm.lua').read_text(), 'my own wezterm settings', 'reinstalling replaced the WezTerm config')

    def test_existing_copied_configuration_is_backed_up(self):
        with tempfile.TemporaryDirectory(prefix='jvim-linux-') as temporary:
            home = Path(temporary)
            old = home/'.config/jvim/init.lua'
            old.parent.mkdir(parents=True)
            old.write_text('old copy')
            result = self.run_installer(home, '--apply')
            self.assertEqual(result.returncode, 0, result.stderr)
            backups = list((home/'.local/state/jvim/backups').iterdir())
            self.assertEqual((backups[0]/'config/init.lua').read_text(), 'old copy')
            self.assertTrue((home/'.config/jvim').is_symlink())

    def test_desktop_shortcuts_that_clash_with_jvim_are_listed_and_freed(self):
        with tempfile.TemporaryDirectory(prefix='jvim-gsettings-') as temporary:
            tools = Path(temporary)
            (tools/'gsettings').write_text('''#!/usr/bin/env python3
import json, os, sys
state = os.path.join(os.path.dirname(__file__), 'state.json')
data = json.load(open(state)) if os.path.exists(state) else {
    'org.gnome.desktop.wm.keybindings': {'switch-to-workspace-left': "['<Super>Page_Up', '<Control><Alt>Left']", 'begin-move': "['<Alt>F7']", 'close': "['<Alt>F4']", 'cycle-group': "@as []"},
    'org.gnome.settings-daemon.plugins.media-keys': {'terminal': "['<Primary><Alt>t']", 'screensaver': "'<Primary><Alt>l'"}}
if sys.argv[1] == 'list-schemas': print('\\n'.join(data))
elif sys.argv[1] == 'list-recursively': print('\\n'.join(f'{sys.argv[2]} {k} {v}' for k, v in data[sys.argv[2]].items()))
elif sys.argv[1] == 'set': data[sys.argv[2]][sys.argv[3]] = sys.argv[4]; json.dump(data, open(state, 'w'))
''')
            (tools/'gsettings').chmod(0o755)
            env = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}')
            script = str(ROOT/'integrations/linux/desktop-keys.py')
            listed = subprocess.run([sys.executable, script], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(listed.returncode, 0, listed.stderr)
            for expected in ('Ctrl+Alt+Left: org.gnome.desktop.wm.keybindings switch-to-workspace-left', 'Alt+F7:', 'Ctrl+Alt+L:'):
                self.assertIn(expected, listed.stdout)
            self.assertNotIn('Alt+F4', listed.stdout)
            self.assertNotIn('Ctrl+Alt+T', listed.stdout)
            self.assertFalse((tools/'state.json').exists(), 'listing changed settings')
            subprocess.run([sys.executable, script, '--apply'], env=env, check=True, capture_output=True, timeout=30)
            state = json.loads((tools/'state.json').read_text())
            self.assertEqual(state['org.gnome.desktop.wm.keybindings']['switch-to-workspace-left'], "['<Super>Page_Up']")
            self.assertEqual(state['org.gnome.desktop.wm.keybindings']['close'], "['<Alt>F4']")
            self.assertEqual(state['org.gnome.settings-daemon.plugins.media-keys']['screensaver'], "''")
            again = subprocess.run([sys.executable, script], env=env, capture_output=True, text=True, timeout=30)
            self.assertIn('No desktop shortcuts clash with jvim.', again.stdout)

    def test_bootstrap_stops_with_package_command_when_tools_are_missing(self):
        with tempfile.TemporaryDirectory(prefix='jvim-bootstrap-') as temporary:
            tools = Path(temporary)/'bin'
            tools.mkdir()
            for name in ('uname', 'cat'):
                (tools/name).symlink_to(shutil.which(name))
            result = subprocess.run(['/bin/sh', str(ROOT/'bootstrap-linux.sh')], env={'HOME': temporary, 'PATH': str(tools)},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('Missing: git curl cc rg', result.stderr)
            self.assertFalse((Path(temporary)/'JensenVim').exists(), 'bootstrap cloned before checking prerequisites')
