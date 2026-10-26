"""Run actual TUI startup, including Neovim's built-in runtime plugins."""
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import threading
import time
import unittest

try:
    import fcntl
    import pty
    import termios
except ImportError:
    pty = None

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = Path.home()/'.local/share/nvim/lazy'
DEPENDENCIES = ('neo-tree.nvim', 'plenary.nvim', 'nui.nvim', 'mini.nvim')


@unittest.skipUnless(pty is not None and shutil.which('nvim') and all((PLUGINS/name).is_dir() for name in DEPENDENCIES),
                     'Neovim and installed Neo-tree dependencies needed for terminal checks')
class TerminalStartupTests(unittest.TestCase):
    def check_startup(self, directory_argument, interaction=None):
        with tempfile.TemporaryDirectory(prefix='jvim-terminal-') as temporary:
            home = Path(temporary).resolve()
            project = home/'Honours'
            project.mkdir()
            (project/'main.txt').write_text('alpha target omega\n' + ''.join(f'line_{row:03d} value_{row:03d}\n' for row in range(2, 301)))
            init = home/'init.lua'
            init.write_text('''
vim.o.swapfile = false
vim.o.termguicolors = true
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
for _, plugin in ipairs { 'plenary.nvim', 'nui.nvim', 'neo-tree.nvim', 'mini.nvim' } do
  vim.opt.rtp:append(vim.env.JVIM_TEST_PLUGINS .. '/' .. plugin)
end
vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
local opts = require('kickstart.plugins.neo-tree').opts
opts.enable_git_status = false
opts.enable_diagnostics = false
opts.sources = { 'filesystem' }
opts.filesystem.use_libuv_file_watcher = false
opts.filesystem.filtered_items = { hide_gitignored = false }
require('neo-tree').setup(opts)
require('mini.tabline').setup()
require('custom.keymaps')
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
  vim.defer_fn(function() _G.jvim_test_started = true end, 300)
end })
''')
            env = dict(os.environ, HOME=str(home), TERM='xterm-256color',
                       JVIM_TEST_CONFIG=os.environ.get('JVIM_TERMINAL_CONFIG', str(ROOT/'config')),
                       JVIM_TEST_PLUGINS=str(PLUGINS), JVIM_TEST_PROJECT=str(project))
            env.pop('JVIM_HOST_SOCKET', None)
            env.pop('JVIM_LINK_TOKEN', None)
            server = str(home/'nvim.sock')
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 100, 0, 0))
            args = ['nvim', '-u', str(init), '-i', 'NONE', '--listen', server]
            if directory_argument:
                args.append(str(project) + '/')
            process = subprocess.Popen(args, cwd=home if directory_argument else project, env=env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            terminal_output = []
            def read_terminal():
                try:
                    while True:
                        chunk = os.read(master, 8192)
                        if not chunk:
                            return
                        terminal_output.append(chunk)
                except OSError:
                    pass
            reader = threading.Thread(target=read_terminal, daemon=True)
            reader.start()
            def remote(expression):
                result = subprocess.run(['nvim', '-u', 'NONE', '--server', server, '--remote-expr', expression],
                                        env=env, capture_output=True, text=True, timeout=3)
                if result.returncode:
                    return None
                return result.stdout.strip()
            try:
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        self.fail('editor exited during startup: ' + b''.join(terminal_output).decode(errors='replace'))
                    if Path(server).exists() and remote('luaeval("_G.jvim_test_started or false")') == 'true':
                        break
                    time.sleep(0.05)
                else:
                    self.fail('terminal startup did not finish')
                state = json.loads(remote('luaeval("vim.json.encode({mode=vim.fn.mode(),windows=vim.tbl_map(function(w) local b=vim.api.nvim_win_get_buf(w); return {ft=vim.bo[b].filetype,relative=vim.api.nvim_win_get_config(w).relative,lines=vim.api.nvim_buf_get_lines(b,0,-1,false)} end,vim.api.nvim_list_wins()),buffers=vim.tbl_map(function(b) return {name=b.name,listed=b.listed,ft=vim.bo[b.bufnr].filetype} end,vim.fn.getbufinfo({bufloaded=1})),root=require(\\\"neo-tree.sources.manager\\\").get_state(\\\"filesystem\\\").path})")'))
                self.assertEqual(len(state['windows']), 1, state)
                window = state['windows'][0]
                self.assertEqual(window['ft'], 'neo-tree', state)
                self.assertEqual(window['relative'], '', state)
                self.assertEqual(state['mode'], 'n', state)
                self.assertEqual(state['root'], str(project), state)
                self.assertIn('Honours', window['lines'][0])
                self.assertNotIn(str(home), window['lines'][0], 'tree root shows the full ancestor path')
                self.assertNotIn('~/', window['lines'][0], 'tree root should show only the directory name')
                self.assertTrue(all(b['ft'] == 'neo-tree' for b in state['buffers']), state)
                if interaction:
                    self.check_mouse(interaction, remote, terminal_output, master)
            finally:
                if process.poll() is None:
                    try:
                        remote('execute("qall!")')
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.terminate()
                        process.wait(timeout=3)
                os.close(master)
                reader.join(timeout=1)

    def test_directory_launch_opens_one_focused_tree_with_short_root(self):
        self.check_startup(True)

    def test_bare_launch_opens_one_focused_tree_with_short_root(self):
        self.check_startup(False)

    def check_mouse(self, interaction, remote, terminal_output, master):
        def lua(expression):
            return remote('luaeval(' + json.dumps(expression) + ')')
        def state(expression):
            return json.loads(lua('vim.json.encode(' + expression + ')'))
        lua("(function() local s=require('neo-tree.sources.manager').get_state('filesystem'); require('neo-tree.utils').open_file(s,vim.env.JVIM_TEST_PROJECT..'/main.txt'); return true end)()")
        time.sleep(0.05)
        pos = state('vim.fn.screenpos(vim.api.nvim_get_current_win(),1,9)')
        row, col = pos['row'] - 1, pos['col'] - 1
        def mouse(button, action):
            lua(f"vim.api.nvim_input_mouse('{button}','{action}','',0,{row},{col})")
        mouse('left', 'press')
        mouse('left', 'release')
        if interaction == 'double_click':
            mouse('left', 'press')
            mouse('left', 'release')
            selected = state("{mode=vim.fn.mode(),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})}")
            self.assertIn(selected['mode'], ('s', 'v'), selected)
            self.assertEqual(selected['text'], ['target'], selected)
            lua("vim.api.nvim_input('X')")
            self.assertEqual(state('vim.fn.getline(1)'), 'alpha X omega')
        elif interaction in ('scroll', 'scroll_click', 'scroll_paste'):
            anchor = state('vim.api.nvim_win_get_cursor(0)')
            original = state('vim.fn.getline(1)')
            for _ in range(15):
                mouse('wheel', 'down')
            view = state('vim.fn.winsaveview()')
            self.assertGreater(view['topline'], anchor[0], view)
            time.sleep(0.05)
            visibility = re.findall(rb'\x1b\[\?25([hl])', b''.join(terminal_output))
            self.assertTrue(visibility, 'terminal did not report cursor visibility')
            self.assertEqual(visibility[-1], b'l', 'cursor remains visible at the scrolled viewport edge')
            if interaction == 'scroll_click':
                clicked_line = view['topline'] + 3
                pos = state(f'vim.fn.screenpos(vim.api.nvim_get_current_win(),{clicked_line},9)')
                row, col = pos['row'] - 1, pos['col'] - 1
                mouse('left', 'press')
                mouse('left', 'release')
                anchor = state('vim.api.nvim_win_get_cursor(0)')
                original = state(f'vim.fn.getline({clicked_line})')
                self.assertEqual(anchor[0], clicked_line)
            insertion = 'X'
            if interaction == 'scroll_paste':
                insertion = 'PASTED'
                os.write(master, b'\x1b[200~PASTED\x1b[201~')
                time.sleep(0.05)
            else:
                lua("vim.api.nvim_input('X')")
            changed = state(f'vim.fn.getline({anchor[0]})')
            self.assertEqual(changed, original[:anchor[1]] + insertion + original[anchor[1]:])
            time.sleep(0.05)
            visibility = re.findall(rb'\x1b\[\?25([hl])', b''.join(terminal_output))
            self.assertEqual(visibility[-1], b'h', 'typing did not restore the visible cursor')
        else:
            self.fail('unknown mouse interaction')

    def test_double_click_selects_word_and_typing_replaces_it(self):
        self.check_startup(False, 'double_click')

    def test_scrolling_hides_displaced_cursor_and_preserves_edit_location(self):
        self.check_startup(False, 'scroll')

    def test_click_after_scrolling_sets_a_new_edit_location(self):
        self.check_startup(False, 'scroll_click')

    def test_paste_after_scrolling_uses_original_edit_location(self):
        self.check_startup(False, 'scroll_paste')
