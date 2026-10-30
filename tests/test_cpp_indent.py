"""Exercise a real Enter key inside a C++ designated initializer."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SITE = Path.home()/'.local/share/jvim/site'


class CppIndentTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('nvim') and (SITE/'parser/cpp.so').exists(), 'Neovim C++ parser required')
    def test_enter_aligns_designated_fields(self):
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_SITE=str(SITE))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(ROOT/'tests/cpp_indent.lua')],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
