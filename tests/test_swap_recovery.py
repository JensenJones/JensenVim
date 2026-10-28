"""Check automatic recovery from a stale Neovim swap file."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for swap recovery checks')
class SwapRecoveryTests(unittest.TestCase):
    def test_stale_swap_recovers_edits_and_keeps_a_backup(self):
        with tempfile.TemporaryDirectory(prefix='jvim-swap-') as directory:
            home = Path(directory)
            target = home/'sample.cpp'
            marker = home/'writer-ready'
            target.write_text('disk version\n')
            env = dict(os.environ, HOME=str(home),
                       JVIM_TEST_CONFIG=os.environ.get('JVIM_SWAP_CONFIG', str(ROOT/'config')),
                       JVIM_TEST_FILE=str(target))
            writer = subprocess.Popen([
                'nvim', '--headless', '-u', 'NONE', '-i', 'NONE', str(target),
                '-c', "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'recovered edit'})",
                '-c', 'preserve', '-c', "lua vim.fn.writefile({vim.fn.swapname(0), vim.o.directory, vim.o.swapfile and 'on' or 'off'}, vim.env.JVIM_TEST_MARKER)", '-c', 'sleep 60',
            ], env=dict(env, JVIM_TEST_MARKER=str(marker)), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                swap_dir = home/'.local/state/nvim/swap'
                deadline = time.monotonic() + 5
                swapfiles = []
                while time.monotonic() < deadline:
                    swapfiles = list(swap_dir.glob('*.swp')) if swap_dir.exists() else []
                    if swapfiles and marker.exists():
                        break
                    time.sleep(0.05)
                self.assertTrue(swapfiles, 'writer did not create its swap file')
            finally:
                writer.kill()
                writer.wait(timeout=5)

            script = home/'recover.lua'
            script.write_text('''\
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('custom.swap_recovery').setup()
vim.cmd.edit(vim.fn.fnameescape(vim.env.JVIM_TEST_FILE))
local backups = vim.fn.glob(vim.fn.stdpath('state') .. '/jvim/recovered-swaps/*.swp', false, true)
assert(vim.fn.getline(1) == 'recovered edit', 'stale swap content was not recovered: ' .. vim.inspect({line=vim.fn.getline(1),swap=vim.v.swapname,backups=backups}))
assert(#backups == 1, 'stale swap was not backed up')
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-c', 'luafile ' + str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
