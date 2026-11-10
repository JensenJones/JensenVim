"""Check that action search matches the words people type, not only action names."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tests.support import isolated_env

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for action picker checks')
class ActionPickerTests(unittest.TestCase):
    def test_search_keywords_find_related_actions(self):
        with tempfile.TemporaryDirectory(prefix='jvim-actions-') as temporary:
            script = Path(temporary)/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('jvim.keymaps')
local picker = require('jvim.action_picker')
local function matches(word)
  local names = {}
  for _, entry in ipairs(picker.entries()) do
    if picker.search_text(entry):lower():find(word, 1, true) then names[entry.name] = true end
  end
  return names
end
local git = matches('git')
for _, name in ipairs { 'Show Git changes', 'Resolve merge conflicts', 'Accept ours for current conflict',
                        'Next merge conflict', 'Git: blame current line', 'Git: revert change under cursor' } do
  assert(git[name], 'searching git misses ' .. name .. ': ' .. vim.inspect(vim.tbl_keys(git)))
end
assert(matches('build')['Run selected configuration'], 'searching build misses running a configuration')
assert(matches('diff')['Show Git changes'], 'searching diff misses the changes view')
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=isolated_env(temporary, JVIM_TEST_CONFIG=str(ROOT/'config')),
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
