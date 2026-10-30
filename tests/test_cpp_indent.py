"""Exercise real Enter keys across common C++ continuation expressions."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SITE = Path.home()/'.local/share/jvim/site'
TREESITTER = SITE.parent/'lazy/nvim-treesitter'


class CppIndentTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('nvim') and (SITE/'parser/cpp.so').exists() and TREESITTER.is_dir(),
                         'Neovim, Tree-sitter and its C++ parser required')
    def test_enter_aligns_designated_fields(self):
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_SITE=str(SITE))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(ROOT/'tests/cpp_indent.lua')],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
