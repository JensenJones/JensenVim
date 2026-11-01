"""Exercise the validation command against small independent repositories."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CheckCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='jvim-check-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root/'scripts').mkdir()
        (self.root/'tests').mkdir()
        self.script = self.root/'scripts/check.py'
        source = ROOT/'scripts/check.py'
        self.assertTrue(source.is_file(), 'repeatable validation command is missing')
        shutil.copy2(source, self.script)

    def run_check(self, *arguments, env=None):
        return subprocess.run([sys.executable, str(self.script), *arguments],
                              env=env, capture_output=True, text=True, timeout=15)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim required for Lua validation')
    def test_success_and_skip_reasons_are_reported(self):
        (self.root/'tests/test_fixture.py').write_text('''
import unittest
class Example(unittest.TestCase):
    def test_pass(self): self.assertTrue(True)
    @unittest.skip('optional fixture tool unavailable')
    def test_skip(self): pass
''')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1 passed, 1 skipped', result.stdout)
        self.assertIn('optional fixture tool unavailable', result.stdout)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim required for Lua validation')
    def test_failed_test_returns_one(self):
        (self.root/'tests/test_fixture.py').write_text('import unittest\nclass Example(unittest.TestCase):\n    def test_fail(self): self.fail("fixture failure")\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn('fixture failure', result.stderr)

    def test_invalid_python_returns_two_before_running_tests(self):
        (self.root/'broken.py').write_text('def broken(:\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn('broken.py', result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim required for Lua validation')
    def test_invalid_lua_returns_two_with_filename(self):
        (self.root/'broken.lua').write_text('local value = )')
        result = self.run_check('--syntax-only')
        self.assertEqual(result.returncode, 2)
        self.assertIn('broken.lua', result.stderr)

    def test_missing_neovim_returns_two_instead_of_a_green_skip(self):
        env = dict(os.environ, PATH='')
        result = self.run_check('--syntax-only', env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Neovim', result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim required for Lua validation')
    def test_empty_test_selection_is_an_error(self):
        result = self.run_check('--pattern', 'test_missing_*.py')
        self.assertEqual(result.returncode, 2)
        self.assertIn('No tests', result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim required for Lua validation')
    def test_discovered_tests_can_import_repository_test_helpers(self):
        (self.root/'tests/__init__.py').touch()
        (self.root/'tests/helper.py').write_text('VALUE = 42\n')
        (self.root/'tests/test_fixture.py').write_text('from tests.helper import VALUE\nimport unittest\nclass Example(unittest.TestCase):\n    def test_import(self): self.assertEqual(VALUE,42)\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
