"""Check the language server log stays small."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for LSP log checks')
class LspLogTests(unittest.TestCase):
    def test_oversized_log_is_rotated_and_clangd_logs_errors_only(self):
        with tempfile.TemporaryDirectory(prefix='jvim-lsp-log-') as temporary:
            script = Path(temporary)/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local path = vim.lsp.log.get_filename()
vim.fn.mkdir(vim.fs.dirname(path), 'p')
local file = assert(io.open(path, 'w'))
file:write(string.rep('x', 11 * 1024 * 1024))
file:close()
require('jvim.lsp').setup()
local stat = vim.uv.fs_stat(path)
assert(not stat or stat.size < 1024, 'oversized LSP log was not rotated')
assert(vim.uv.fs_stat(path .. '.old'), 'rotated log was not kept')
assert(vim.tbl_contains(vim.lsp.config.clangd.cmd, '--log=error'), 'clangd still logs every request')
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=dict(os.environ, HOME=temporary, JVIM_TEST_CONFIG=str(ROOT/'config')),
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
