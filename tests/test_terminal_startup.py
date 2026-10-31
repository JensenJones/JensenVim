"""Run actual TUI startup, including Neovim's built-in runtime plugins."""
import json
import os
import re
from pathlib import Path
import shutil
import shlex
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
DEPENDENCIES = ('neo-tree.nvim', 'plenary.nvim', 'nui.nvim', 'mini.nvim', 'telescope.nvim')


@unittest.skipUnless(pty is not None and shutil.which('nvim') and all((PLUGINS/name).is_dir() for name in DEPENDENCIES),
                     'Neovim and installed Neo-tree dependencies needed for terminal checks')
class TerminalStartupTests(unittest.TestCase):
    def check_startup(self, directory_argument, interaction=None):
        with tempfile.TemporaryDirectory(prefix='jvim-terminal-') as temporary:
            home = Path(temporary).resolve()
            project = home/'Honours'
            project.mkdir()
            (project/'main.txt').write_text('alpha target omega\n' + ''.join(f'line_{row:03d} value_{row:03d}\n' for row in range(2, 301)))
            clipboard_file = home/'clipboard'
            clipboard_commands = home/'clipboard-bin'
            clipboard_commands.mkdir()
            (clipboard_commands/'pbcopy').write_text('#!/bin/sh\ncat > ' + shlex.quote(str(clipboard_file)) + '\n')
            (clipboard_commands/'pbpaste').write_text('#!/bin/sh\ncat ' + shlex.quote(str(clipboard_file)) + '\n')
            (clipboard_commands/'pbcopy').chmod(0o755)
            (clipboard_commands/'pbpaste').chmod(0o755)
            jvim_config = home/'.config/jvim'
            jvim_config.mkdir(parents=True)
            shutil.copy2(ROOT/'config/clion-keymap-audit.json', jvim_config/'clion-keymap-audit.json')
            init = home/'init.lua'
            init.write_text('''
vim.o.swapfile = false
vim.o.termguicolors = true
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
for _, plugin in ipairs { 'plenary.nvim', 'nui.nvim', 'neo-tree.nvim', 'mini.nvim', 'telescope.nvim' } do
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
require('mini.statusline').setup { use_icons = false }
require('custom.keymaps')
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
  vim.defer_fn(function() _G.jvim_test_started = true end, 300)
end })
''')
            env = dict(os.environ, HOME=str(home), NVIM_APPNAME='jvim', TERM='xterm-256color',
                       JVIM_TEST_CONFIG=os.environ.get('JVIM_TERMINAL_CONFIG', str(ROOT/'config')),
                       JVIM_TEST_PLUGINS=str(PLUGINS), JVIM_TEST_PROJECT=str(project),
                       PATH=str(clipboard_commands)+os.pathsep+os.environ.get('PATH', ''))
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
                    raise AssertionError('remote nvim expression failed: ' + result.stderr)
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
                    except Exception:
                        process.terminate()
                        process.wait(timeout=3)
                os.close(master)
                reader.join(timeout=1)

    def test_directory_launch_opens_one_focused_tree_with_short_root(self):
        self.check_startup(True)

    def test_bare_launch_opens_one_focused_tree_with_short_root(self):
        self.check_startup(False)

    def test_single_click_in_tree_opens_file(self):
        self.check_startup(True, 'tree_single_click')

    def test_theme_action_opens_picker(self):
        self.check_startup(True, 'theme_picker')

    def test_shift_enter_transport_opens_line_below(self):
        self.check_startup(True, 'shift_enter')

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
        if interaction == 'tree_single_click':
            click_pos = state("(function() local s=require('neo-tree.sources.manager').get_state('filesystem'); for i,line in ipairs(vim.api.nvim_buf_get_lines(s.bufnr,0,-1,false)) do if line:find('main.txt',1,true) then local p=vim.fn.screenpos(s.winid,i,1); return {row=p.row-1,col=p.col-1,line=line} end end end)()")
            self.assertIsNotNone(click_pos, 'main.txt is not visible in Neo-tree')
            os.write(master, f"\x1b[<0;{click_pos['col'] + 1};{click_pos['row'] + 1}M\x1b[<0;{click_pos['col'] + 1};{click_pos['row'] + 1}m".encode())
            time.sleep(0.1)
            self.assertTrue(state('vim.api.nvim_buf_get_name(0)').endswith('/main.txt'), 'one click in Neo-tree did not open main.txt')
            return
        if interaction == 'theme_picker':
            lua("(function() require('custom.theme').setup(); require('custom.action_picker').open(); return true end)()")
            time.sleep(0.2)
            def picker_state():
                return state("{theme=vim.g.colors_name,mode=vim.fn.mode(),windows=vim.tbl_map(function(w) local b=vim.api.nvim_win_get_buf(w); return {ft=vim.bo[b].filetype,lines=vim.api.nvim_buf_get_lines(b,0,3,false)} end,vim.api.nvim_list_wins())}")
            self.assertTrue(any(w['ft'] == 'TelescopePrompt' for w in picker_state()['windows']), 'action picker did not open: ' + repr(picker_state()))
            os.write(master, b'Choose colour theme')
            time.sleep(0.2)
            self.assertTrue(any('Choose colour theme' in line for w in picker_state()['windows'] for line in w['lines']), 'action picker did not receive its filter: ' + repr(picker_state()))
            os.write(master, b'\r')
            time.sleep(0.2)
            self.assertTrue(any(w['ft'] == 'TelescopePrompt' for w in picker_state()['windows']), 'theme picker did not open after choosing its action: ' + repr(picker_state()))
            self.assertEqual(state("require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf()):_get_prompt()"), '', 'theme picker started with unwanted text')
            os.write(master, b'Dark Ubuntu')
            time.sleep(0.2)
            os.write(master, b'\r')
            time.sleep(0.2)
            self.assertEqual(state('vim.g.colors_name'), 'dark-ubuntu', 'selecting Dark Ubuntu through the theme picker did not apply it')
            self.assertEqual(state('vim.fn.getline(1)'), 'alpha target omega', 'picker handoff inserted text into the editor')
            return
        if interaction == 'shift_enter':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'    preserve this line','next line'}); vim.api.nvim_win_set_cursor(0,{1,8}); vim.cmd.startinsert(); return true end)()")
            os.write(master, b'\x1b[23;5~69')
            time.sleep(0.1)
            actual = state("vim.api.nvim_buf_get_lines(0,0,-1,false)")
            self.assertEqual(actual[0], '    preserve this line', 'Shift+Enter changed the current line: ' + repr(actual))
            self.assertEqual(actual[1].strip(), '', 'Shift+Enter did not create a blank line below: ' + repr(actual))
            return
        if interaction == 'tree_toggle':
            lua("assert(vim.fn.maparg('\\\\', 'n') ~= '', 'project tree toggle was not installed')")
            os.write(master, b'\\')
            time.sleep(0.1)
            self.assertEqual(state("vim.tbl_contains(vim.tbl_map(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' end,vim.api.nvim_tabpage_list_wins(0)),true)"), False, 'Backslash did not hide the tree from the editor')
            os.write(master, b'\\')
            time.sleep(0.1)
            self.assertEqual(state("vim.tbl_contains(vim.tbl_map(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' end,vim.api.nvim_tabpage_list_wins(0)),true)"), True, 'Backslash did not bring back the hidden tree')
            os.write(master, b'\\')
            time.sleep(0.1)
            self.assertEqual(state("vim.tbl_contains(vim.tbl_map(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' end,vim.api.nvim_tabpage_list_wins(0)),true)"), False, 'Backslash did not hide the tree while it had focus')
            os.write(master, b'\\')
            time.sleep(0.1)
            self.assertEqual(state("vim.tbl_contains(vim.tbl_map(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' end,vim.api.nvim_tabpage_list_wins(0)),true)"), True, 'Backslash did not restore the tree after hiding it from tree focus')
            return
        if interaction == 'fold_buttons':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'function start','  first','  second','end','after'}); vim.wo.foldmethod='manual'; vim.wo.foldenable=true; vim.wo.foldlevel=99; vim.cmd('1,4fold'); vim.cmd('normal! zo'); vim.api.nvim_win_set_cursor(0,{1,0}); return true end)()")
            self.assertEqual(state('vim.fn.foldclosed(1)'), -1)
            click_state = state("(function() local w=vim.api.nvim_get_current_win(); local s=vim.api.nvim_eval_statusline(vim.wo[w].statusline,{winid=w}); local i=assert(s.str:find('[- Fold]',1,true)); local p=vim.api.nvim_win_get_position(w); local c=p[2]+vim.fn.strdisplaywidth(s.str:sub(1,i-1)); local h=vim.api.nvim_win_get_height(w); local r=p[1]+h; return {str=s.str,width=s.width,pos=p,height=h,row=r,col=c} end)()")
            os.write(master, f"\x1b[<0;{click_state['col'] + 1};{click_state['row'] + 1}M\x1b[<0;{click_state['col'] + 1};{click_state['row'] + 1}m".encode())
            time.sleep(0.1)
            self.assertEqual(state('vim.fn.foldclosed(1)'), 1, 'clicking [- Fold] did not collapse code: ' + repr(click_state))
            expand_click = state("(function() local w=vim.api.nvim_get_current_win(); local s=vim.api.nvim_eval_statusline(vim.wo[w].statusline,{winid=w}); local i=assert(s.str:find('[+ Fold]',1,true)); local p=vim.api.nvim_win_get_position(w); local c=p[2]+vim.fn.strdisplaywidth(s.str:sub(1,i-1)); local r=p[1]+vim.api.nvim_win_get_height(w); return {row=r,col=c} end)()")
            os.write(master, f"\x1b[<0;{expand_click['col'] + 1};{expand_click['row'] + 1}M\x1b[<0;{expand_click['col'] + 1};{expand_click['row'] + 1}m".encode())
            time.sleep(0.05)
            self.assertEqual(state('vim.fn.foldclosed(1)'), -1, 'clicking [+ Fold] did not expand code')
            return
        if interaction == 'command_terminal':
            lua("require('custom.command_terminal').open()")
            self.assertEqual(state('vim.bo.buftype'), 'terminal')
            self.assertTrue(state('vim.fn.getcwd()').endswith('/Honours'))
            lua("vim.api.nvim_input('echo JVIM_COMMAND_OK\\r')")
            self.assertEqual(lua("vim.wait(3000,function() for _,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do if line:find('JVIM_COMMAND_OK',1,true) then return true end end return false end,25)"), 'true')
            return
        if interaction == 'shift_word_selection':
            mouse('left', 'press')
            mouse('left', 'release')
            mouse('left', 'press')
            mouse('left', 'release')
            selected_before = state("{mode=vim.fn.mode(),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true}),line=vim.fn.getline(1)}")
            self.assertEqual(selected_before['line'], 'alpha target omega', selected_before)
            self.assertIn(selected_before['mode'], ('s', 'v'), selected_before)
            time.sleep(0.05)
            os.write(master, b'\x1b[23;5~75')
            time.sleep(0.1)
            selected = state("{mode=vim.fn.mode(),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true}),line=vim.fn.getline(1)}")
            self.assertEqual(selected['line'], 'alpha target omega', selected)
            self.assertIn(selected['mode'], ('s', 'v'), selected)
            self.assertNotEqual(selected['text'], selected_before['text'], 'Option+Shift+Left did not extend the word selection')
            mouse('left', 'press')
            mouse('left', 'release')
            self.assertEqual(state('vim.fn.getline(1)'), 'alpha target omega', 'clicking away after word selection edited the line')
            lua("(function() vim.cmd.stopinsert(); vim.cmd('normal! \\27'); vim.api.nvim_buf_set_lines(0,0,1,false,{'alpha target omega'}); vim.api.nvim_win_set_cursor(0,{1,#vim.fn.getline(1)}); vim.cmd.startinsert(); return true end)()")
            os.write(master, b'\x1b[23;5~71')
            time.sleep(0.1)
            shifted = state("{mode=vim.fn.mode(),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true}),line=vim.fn.getline(1)}")
            self.assertEqual(shifted['mode'], 's', shifted)
            self.assertEqual(shifted['line'], 'alpha target omega', 'Shift+Left inserted terminal sequence text')
            self.assertEqual(shifted['text'], ['a'], 'Shift+Left should select exactly one character')
            return
        if interaction == 'shift_left_across_line':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha target','    next'}); vim.api.nvim_win_set_cursor(0,{2,0}); vim.cmd('normal! v'); return true end)()")
            os.write(master, b'\x1b[1;2D')
            time.sleep(0.1)
            state_after = state("{mode=vim.fn.mode(),cursor=vim.api.nvim_win_get_cursor(0),selection=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})}")
            self.assertEqual(state_after['cursor'][0], 1, 'Shift+Left stopped on the next line instead of reaching the prior line end: ' + repr(state_after))
            self.assertNotIn('    ', state_after['selection'], 'Shift+Left selected the next line indentation: ' + repr(state_after))
            return
        if interaction == 'option_shift_right_word':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'word    ','next'}); vim.api.nvim_win_set_cursor(0,{1,0}); vim.cmd.startinsert(); return true end)()")
            os.write(master, b'\x1b[1;4C')
            time.sleep(0.1)
            selected = state("{mode=vim.fn.mode(),cursor=vim.api.nvim_win_get_cursor(0),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})}")
            self.assertIn(selected['mode'], ('s', 'v'), selected)
            self.assertEqual(selected['cursor'][0], 1, 'Option+Shift+Right crossed onto the next line: ' + repr(selected))
            self.assertEqual(selected['text'], ['word'], 'Option+Shift+Right selected trailing spaces with the word: ' + repr(selected))
            return
        if interaction == 'iterm_option_shift_right':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'word    next'}); vim.api.nvim_win_set_cursor(0,{1,0}); vim.cmd.startinsert(); return true end)()")
            os.write(master, b'\x1b[23;5~76')
            time.sleep(0.1)
            selected = state("{mode=vim.fn.mode(),line=vim.fn.getline(1),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})}")
            self.assertEqual(selected['line'], 'word    next', 'iTerm Option+Shift+Right inserted shortcut transport bytes: ' + repr(selected))
            self.assertIn(selected['mode'], ('s', 'v'), 'iTerm Option+Shift+Right did not select text: ' + repr(selected))
            self.assertEqual(selected['text'], ['word'], 'iTerm Option+Shift+Right selected spaces or the wrong word: ' + repr(selected))
            return
        if interaction == 'cmd_left_indent':
            for payload in (b'\x1b[23;5~70', b'\x1b[1~', b'\x1b[H', b'\x01'):
                lua("(function() vim.api.nvim_buf_set_lines(0,0,1,false,{'    indented value'}); vim.api.nvim_win_set_cursor(0,{1,17}); vim.cmd.stopinsert(); return true end)()")
                os.write(master, payload)
                time.sleep(0.1)
                self.assertEqual(state('vim.api.nvim_win_get_cursor(0)[2]'), 4, 'Cmd+Left should move to first nonblank column: ' + repr(payload))
                lua('(function() vim.api.nvim_win_set_cursor(0,{1,17}); vim.cmd.startinsert(); return true end)()')
                os.write(master, payload)
                time.sleep(0.1)
                self.assertEqual(state('vim.api.nvim_win_get_cursor(0)[2]'), 4, 'Cmd+Left in Insert mode should keep indentation: ' + repr(payload))
            self.assertEqual(state('vim.fn.getline(1)'), '    indented value', 'Cmd+Left inserted key-sequence text')
            return
        if interaction == 'option_word_motion':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,1,false,{'leftIt->timestamp, call()'}); vim.api.nvim_win_set_cursor(0,{1,0}); vim.cmd.startinsert(); return true end)()")
            for expected in (6, 17, 23):
                os.write(master, b'\x1b[1;5C')
                time.sleep(0.05)
                actual = state('vim.api.nvim_win_get_cursor(0)[2]')
                self.assertEqual(actual, expected, f'Option+Right should stop at the next identifier boundary, got {actual}')
            self.assertEqual(state('vim.fn.getline(1)'), 'leftIt->timestamp, call()', 'Option+Right inserted text')
            return
        if interaction == 'terminal_cmdw':
            lua("require('custom.command_terminal').open()")
            self.assertEqual(state('vim.bo.buftype'), 'terminal')
            lua("vim.cmd.startinsert()")
            time.sleep(0.05)
            self.assertTrue(state('vim.fn.mode()').startswith('t'), 'test must send Cmd+W while terminal input is active')
            lua("vim.api.nvim_input('<C-F11>20')")
            time.sleep(0.1)
            self.assertNotEqual(state('vim.bo.buftype'), 'terminal', 'iTerm Cmd+W sequence did not close only the terminal pane')
            return
        if interaction == 'clipboard_copy_paste':
            lua("(function() vim.api.nvim_win_set_cursor(0,{1,6}); vim.cmd('normal! v'); vim.api.nvim_win_set_cursor(0,{1,12}); return true end)()")
            lua("vim.api.nvim_feedkeys(vim.keycode('<C-F11>13'),'mxt',false)")
            time.sleep(0.2)
            self.assertEqual(state('vim.fn.getreg("+" )'), 'target', 'iTerm Cmd+C sequence did not copy the selection')
            lua("(function() local b=vim.fn.bufadd(vim.env.JVIM_TEST_PROJECT..'/other.txt'); vim.fn.bufload(b); vim.api.nvim_buf_set_lines(b,0,-1,false,{'destination'}); require('custom.files').show(b); vim.api.nvim_win_set_cursor(0,{1,0}); return true end)()")
            lua("vim.api.nvim_feedkeys(vim.keycode('<C-F11>15'),'mxt',false)")
            time.sleep(0.2)
            self.assertEqual(state('vim.fn.getline(1)'), 'targetdestination', 'iTerm Cmd+V sequence did not paste into another file')
            return
        if interaction == 'code_action_undo':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,1,false,{'before'}); vim.cmd('let &undolevels = &undolevels'); vim.lsp.util.apply_text_edits({{range={start={line=0,character=0},['end']={line=0,character=6}},newText='after'}},vim.api.nvim_get_current_buf(),'utf-16'); return true end)()")
            self.assertEqual(state('vim.fn.getline(1)'), 'after')
            lua("vim.api.nvim_input('<F26>')")
            time.sleep(0.1)
            self.assertEqual(state('vim.fn.getline(1)'), 'before', 'undo should reverse an LSP-applied code action')
            return
        if interaction == 'horizontal_scroll':
            lua("(function() vim.api.nvim_buf_set_lines(0,0,1,false,{string.rep('0123456789',30)}); vim.wo.wrap=false; vim.api.nvim_win_set_cursor(0,{1,250}); vim.cmd.redraw(); return true end)()")
            before = state('vim.fn.winsaveview().leftcol')
            self.assertGreater(before, 0, 'test needs a nonzero horizontal viewport')
            mouse('wheel', 'left')
            time.sleep(0.1)
            moved_right = state('vim.fn.winsaveview().leftcol')
            self.assertGreater(moved_right, before, 'leftward trackpad gesture should move the viewport right')
            mouse('wheel', 'right')
            time.sleep(0.1)
            moved_left = state('vim.fn.winsaveview().leftcol')
            self.assertLess(moved_left, moved_right, 'rightward trackpad gesture should move the viewport left')
            return
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
        elif interaction == 'mouse_drag_selection':
            start = state('vim.fn.screenpos(vim.api.nvim_get_current_win(),1,7)')
            end = state('vim.fn.screenpos(vim.api.nvim_get_current_win(),1,13)')
            lua(f"vim.api.nvim_input_mouse('left','press','',0,{start['row']-1},{start['col']-1})")
            lua(f"vim.api.nvim_input_mouse('left','drag','',0,{end['row']-1},{end['col']-1})")
            lua(f"vim.api.nvim_input_mouse('left','release','',0,{end['row']-1},{end['col']-1})")
            selected = state("{mode=vim.fn.mode(),line=vim.fn.getline(1),text=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})}")
            self.assertEqual(selected['line'], 'alpha target omega', 'dragging to highlight text changed the source line: ' + repr(selected))
            self.assertIn(selected['mode'], ('s', 'v'), 'mouse drag did not create a selection: ' + repr(selected))
            lua("vim.api.nvim_input('X')")
            self.assertEqual(state('vim.fn.getline(1)'), 'alpha X omega', 'typing after mouse drag did not replace only the selected word: ' + repr(selected))
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

    def test_mouse_drag_selection_does_not_insert_input_garbage(self):
        self.check_startup(False, 'mouse_drag_selection')

    def test_option_shift_arrow_selects_word_without_inserting_key_sequence(self):
        self.check_startup(False, 'shift_word_selection')

    def test_shift_left_crosses_line_boundary_without_selecting_indentation(self):
        self.check_startup(False, 'shift_left_across_line')

    def test_option_shift_right_selects_word_without_trailing_spaces(self):
        self.check_startup(False, 'option_shift_right_word')

    def test_iterm_option_shift_right_transport_selects_word(self):
        self.check_startup(False, 'iterm_option_shift_right')

    def test_command_left_moves_to_indentation(self):
        self.check_startup(False, 'cmd_left_indent')

    def test_option_right_steps_over_identifiers_and_skips_separators(self):
        self.check_startup(False, 'option_word_motion')

    def test_scrolling_hides_displaced_cursor_and_preserves_edit_location(self):
        self.check_startup(False, 'scroll')

    def test_click_after_scrolling_sets_a_new_edit_location(self):
        self.check_startup(False, 'scroll_click')

    def test_paste_after_scrolling_uses_original_edit_location(self):
        self.check_startup(False, 'scroll_paste')

    def test_statusline_fold_buttons_collapse_and_expand(self):
        self.check_startup(False, 'fold_buttons')

    def test_command_terminal_runs_a_shell_command_in_project(self):
        self.check_startup(False, 'command_terminal')

    def test_iterm_copy_and_paste_work_between_files(self):
        self.check_startup(False, 'clipboard_copy_paste')

    def test_iterm_command_one_hides_and_restores_the_tree(self):
        self.check_startup(False, 'tree_toggle')

    def test_iterm_command_w_closes_only_the_jvim_terminal_pane(self):
        self.check_startup(False, 'terminal_cmdw')

    def test_horizontal_trackpad_scroll_follows_gesture_direction(self):
        self.check_startup(False, 'horizontal_scroll')

    def test_undo_reverses_a_suggested_code_action(self):
        self.check_startup(False, 'code_action_undo')
