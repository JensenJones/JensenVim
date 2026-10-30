"""Check the shipped color scheme through Neovim's real highlight API."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for theme checks')
class ThemeTests(unittest.TestCase):
    def check_case(self, case):
        with tempfile.TemporaryDirectory(prefix='jvim-theme-') as home:
            config = Path(home)/'.config/jvim'
            config.mkdir(parents=True)
            shutil.copy2(ROOT/'config/clion-keymap-audit.json', config/'clion-keymap-audit.json')
            env = dict(os.environ, HOME=home, NVIM_APPNAME='jvim', JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_CASE=case)
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/theme.lua')],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_default_theme_is_charcoal(self):
        self.check_case('default')

    def test_apply_switches_between_supported_themes(self):
        self.check_case('switch')

    def test_invalid_theme_does_not_change_current_scheme(self):
        self.check_case('invalid')

    def test_required_highlight_groups_are_defined(self):
        self.check_case('groups')

    def test_contrast_floor_for_text_selection_and_cursor(self):
        self.check_case('contrast')

    def test_theme_groups_remain_legible_with_picker_groups(self):
        self.check_case('picker_groups')

    def test_coderpad_inspired_palette_roles(self):
        self.check_case('coderpad_palette')

    def test_theme_action_has_no_shortcut_or_keymap(self):
        self.check_case('action_entry')

    def test_theme_picker_selection_applies_theme(self):
        self.check_case('picker_selection')
