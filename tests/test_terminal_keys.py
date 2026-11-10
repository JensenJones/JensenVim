"""Check editor shortcuts inside the built-in terminal reach the shell as shell actions, never as their transport digits."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for terminal key checks')
class TerminalKeyTests(unittest.TestCase):
    def test_every_shortcut_code_is_handled_inside_terminal(self):
        with tempfile.TemporaryDirectory(prefix='jvim-terminal-keys-') as temporary:
            script = Path(temporary)/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('jvim.keymaps')
for number = 13, 80 do
  assert(vim.fn.maparg('<C-F11>' .. number, 't') ~= '', 'transport code ' .. number .. ' would reach the shell as digits')
end
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=dict(os.environ, HOME=temporary, JVIM_TEST_CONFIG=str(ROOT/'config')),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
