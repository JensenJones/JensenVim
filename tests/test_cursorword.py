"""Verify current-word highlighting in both ordinary and insert editing."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MINI = Path.home()/'.local/share/nvim/lazy/mini.nvim'


@unittest.skipUnless(shutil.which('nvim') and MINI.is_dir(), 'Neovim and Mini.nvim needed for word highlight checks')
class CursorWordTests(unittest.TestCase):
    def test_highlights_all_whole_word_occurrences(self):
        with tempfile.TemporaryDirectory(prefix='jvim-word-') as directory:
            home = Path(directory)
            script = home/'check.lua'
            script.write_text('''
vim.o.swapfile = false
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_MINI)
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'propagate propogate propagateMore', '"propagate"' })
require('custom.word_highlight').setup()
vim.api.nvim_win_set_cursor(0, { 1, 2 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
assert(vim.wait(1000, function() return #vim.fn.getmatches() > 0 end, 10), 'current word was not highlighted')
local matches = vim.fn.getmatches()
assert(matches[1].group == 'JvimWord', 'word highlights use the wrong group')
local pattern = matches[1].pattern
local starts, offset = {}, 0
while true do
  local found = vim.fn.matchstrpos(vim.fn.getline(1), pattern, offset)
  if found[2] < 0 then break end
  table.insert(starts, found[2])
  offset = found[3]
end
assert(vim.deep_equal(starts, { 0 }), 'highlight matched a prefix or a different word: ' .. vim.inspect(starts))
local second_line = vim.fn.matchstrpos(vim.fn.getline(2), pattern, 0)
assert(second_line[2] == 1, 'highlight missed a matching word inside a string')
vim.cmd 'qall!'
''')
            env = dict(os.environ, HOME=str(home), JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_MINI=str(MINI))
            env.pop('JVIM_HOST_SOCKET', None)
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
