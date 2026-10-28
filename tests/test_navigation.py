"""Exercise file navigation with installed Neo-tree, without Git or a plugin manager."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = Path.home()/'.local/share/nvim/lazy'
DEPENDENCIES = ('neo-tree.nvim', 'plenary.nvim', 'nui.nvim', 'mini.nvim')


@unittest.skipUnless(shutil.which('nvim') and all((PLUGINS/name).is_dir() for name in DEPENDENCIES),
                     'Neovim and installed Neo-tree dependencies needed for integration checks')
class NavigationTests(unittest.TestCase):
    def check_case(self, case):
        with tempfile.TemporaryDirectory(prefix='jvim-navigation-') as directory:
            home = Path(directory).resolve()
            project = home/'project'
            project.mkdir()
            (project/'main.txt').write_text('main contents\n')
            (project/'other.txt').write_text('other contents\n')
            (project/'third.txt').write_text('third contents\n')
            env = dict(os.environ, HOME=str(home), JVIM_TEST_CONFIG=str(ROOT/'config'),
                       JVIM_TEST_PLUGINS=str(PLUGINS), JVIM_TEST_PROJECT=str(project), JVIM_TEST_CASE=case)
            env.pop('JVIM_HOST_SOCKET', None)
            env.pop('JVIM_LINK_TOKEN', None)
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE',
                                     '-l', str(ROOT/'tests/navigation.lua')],
                                    env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_directory_startup_has_no_placeholder(self):
        self.check_case('directory')

    def test_bare_startup_has_no_placeholder(self):
        self.check_case('bare')

    def test_switch_from_tree_displays_file_in_editor(self):
        self.check_case('switch_from_tree')

    def test_click_tab_from_tree_displays_file_in_editor(self):
        self.check_case('click_from_tree')

    def test_switch_from_tree_restores_hidden_file_without_placeholder(self):
        self.check_case('restore_hidden_file')

    def test_close_blank_keeps_remaining_file_visible(self):
        self.check_case('close_blank')

    def test_close_file_keeps_remaining_file_visible(self):
        self.check_case('close_file')

    def test_startup_preserves_modified_unnamed_file(self):
        self.check_case('modified_startup')

    def test_project_tree_shortcut_toggles_tree_from_editor(self):
        self.check_case('tree_toggle')

    def test_control_tab_uses_recent_file_order(self):
        self.check_case('recent_files')
