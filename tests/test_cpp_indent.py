"""Exercise real Enter keys across common C++ continuation expressions."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

from tests.support import jvim_data

ROOT = Path(__file__).resolve().parents[1]
SITE = jvim_data()/'site'
TREESITTER = SITE.parent/'lazy/nvim-treesitter'
AUTOPAIRS = SITE.parent/'lazy/nvim-autopairs'


class CppIndentTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('nvim') and (SITE/'parser/cpp.so').exists() and TREESITTER.is_dir() and AUTOPAIRS.is_dir(),
                         'Neovim, Tree-sitter, its C++ parser and nvim-autopairs required')
    def test_enter_aligns_designated_fields(self):
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_SITE=str(SITE))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(ROOT/'tests/cpp_indent.lua')],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
