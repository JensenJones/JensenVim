"""Drive the full jvim configuration in a real terminal, where startup restore and scroll events only happen with a UI."""
import json
import os
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
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home()/'.local/share'))/'jvim'


class Editor:
    """One jvim process in a pseudo-terminal, controlled through its RPC socket."""

    def __init__(self, test, home, cwd, *args):
        self.test, self.server = test, str(home/f'nvim-{time.monotonic_ns()}.sock')
        self.env = dict(os.environ, HOME=str(home), NVIM_APPNAME='jvim', TERM='xterm-256color', JVIM_OFFLINE='1',
                        XDG_CONFIG_HOME=str(home/'config'), XDG_DATA_HOME=str(home/'data'), XDG_STATE_HOME=str(home/'state'))
        for name in ('JVIM_HOST_SOCKET', 'JVIM_LINK_TOKEN', 'XDG_CACHE_HOME'):
            self.env.pop(name, None)
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 160, 0, 0))
        self.process = subprocess.Popen(['nvim', '-i', 'NONE', '--listen', self.server, *args], cwd=cwd, env=self.env,
                                        stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        threading.Thread(target=self._drain, daemon=True).start()
        self.wait_for('vim.v.vim_did_enter == 1 and vim.bo.filetype ~= "" and true', timeout=15)

    def _drain(self):
        try:
            while os.read(self.master, 65536):
                pass
        except OSError:
            pass

    def lua(self, code):
        result = subprocess.run(['nvim', '-u', 'NONE', '--server', self.server, '--remote-expr',
                                 'luaeval("vim.json.encode((function() ' + code.replace('\\', '\\\\').replace('"', '\\"') + ' end)())")'],
                                env=self.env, capture_output=True, text=True, timeout=5)
        if result.returncode or not result.stdout.strip():
            raise AssertionError('remote call failed: ' + code + '\n' + result.stderr)
        return json.loads(result.stdout)

    def wait_for(self, expression, timeout=5):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                self.test.fail('jvim exited early')
            if Path(self.server).exists():
                try:
                    last = self.lua('return ' + expression)
                    if last:
                        return last
                except AssertionError:
                    pass
            time.sleep(0.1)
        self.test.fail(f'timed out waiting for {expression}; last value {last!r}')

    def send(self, data):
        os.write(self.master, data)

    def close(self):
        if self.master is None:
            return
        if self.process.poll() is None:
            try:
                self.lua('vim.cmd "qall!"')
            except Exception:
                pass
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        os.close(self.master)
        self.master = None


@unittest.skipUnless(pty is not None and shutil.which('nvim') and shutil.which('git') and (DATA/'lazy/lazy.nvim').is_dir(),
                     'Needs Neovim, Git and jvim plugins already downloaded (run jvim once)')
class UiSessionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='jvim-ui-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name).resolve()
        (self.home/'config').mkdir()
        (self.home/'config/jvim').symlink_to(ROOT/'config', target_is_directory=True)
        (self.home/'data').mkdir()
        # Offline mode never installs or updates, so the downloaded plugins are only read.
        (self.home/'data/jvim').symlink_to(DATA, target_is_directory=True)
        self.project = self.home/'thesis'
        (self.project/'chapters').mkdir(parents=True)
        (self.project/'main.tex').write_text('\\documentclass{article}\n\\begin{document}\n\\input{chapters/intro}\n\\end{document}\n')
        (self.project/'chapters/intro.tex').write_text('\\section{Intro}\nSome $x^2$ text.\n')
        lines = [f'line {number}' for number in range(1, 301)]
        (self.project/'long.txt').write_text('\n'.join(lines) + '\n')
        env = dict(os.environ, HOME=str(self.home), GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='jvim', GIT_AUTHOR_EMAIL='jvim@example.com',
                   GIT_COMMITTER_NAME='jvim', GIT_COMMITTER_EMAIL='jvim@example.com')
        for command in (['init', '-q'], ['add', '.'], ['commit', '-q', '-m', 'base']):
            subprocess.run(['git', *command], cwd=self.project, env=env, check=True)
        del lines[49:59]
        (self.project/'long.txt').write_text('\n'.join(lines) + '\n')

    def editor(self, *args):
        editor = Editor(self, self.home, self.project, *args, '.')
        self.addCleanup(editor.close)
        return editor

    def test_restored_files_are_highlighted_and_closing_the_last_leaves_the_tree(self):
        first = self.editor()
        first.lua('vim.cmd.edit "chapters/intro.tex"; return true')
        self.assertTrue(first.lua('return require("jvim.session").save() and true or false'))
        first.close()

        second = self.editor()
        second.wait_for('vim.api.nvim_buf_get_name(0):match("intro%.tex$") ~= nil')
        state = second.lua('local buf = vim.api.nvim_get_current_buf(); return { ft = vim.bo[buf].filetype, '
                           'parser = vim.treesitter.language.add("latex") or false, '
                           'highlighted = vim.treesitter.highlighter.active[buf] ~= nil }')
        self.assertEqual(state['ft'], 'tex', 'restored file has no filetype')
        if state['parser']:
            self.assertTrue(state['highlighted'], 'restored file is not highlighted')

        # Startup opens the tree after restoring the file; a person cannot press Cmd+W before that settles.
        second.wait_for('vim.iter(vim.api.nvim_tabpage_list_wins(0)):any(function(w) '
                        'return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "neo-tree" end)')
        second.send(b'\x1b[23;5~20')
        second.wait_for('vim.bo.filetype == "neo-tree"')
        chapters = str(self.project/'chapters')
        tree = second.lua('local wins = vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end, '
                          'vim.api.nvim_tabpage_list_wins(0)); local state = require("neo-tree.sources.manager").get_state("filesystem"); '
                          f'local node = state.tree:get_node("{chapters}"); return {{ wins = #wins, expanded = node ~= nil and node:is_expanded() }}')
        self.assertEqual(tree['wins'], 1, 'Command+W on the last tab should leave only the tree')
        self.assertTrue(tree['expanded'], 'the folder of the closed file collapsed')

    def test_diff_panes_follow_the_wheel_over_either_pane(self):
        editor = self.editor()
        editor.lua('require("jvim.changes").open(); return true')
        editor.wait_for('#vim.tbl_filter(function(w) return vim.wo[w].diff end, vim.api.nvim_tabpage_list_wins(0)) == 2')
        panes = editor.lua('local out = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.wo[w].diff then '
                           'local pos = vim.api.nvim_win_get_position(w); out[#out + 1] = { row = pos[1] + 5, col = pos[2] + 5 } end end '
                           'table.sort(out, function(a, b) return a.col < b.col end); return out')
        top_lines = ('local out = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.wo[w].diff then '
                     'local top = vim.api.nvim_win_call(w, vim.fn.winsaveview).topline; '
                     'out[#out + 1] = { col = vim.api.nvim_win_get_position(w)[2], text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), top - 1, top, false)[1] } end end '
                     'table.sort(out, function(a, b) return a.col < b.col end); return { out[1].text, out[2].text }')
        for pane, direction, count in ((panes[1], 'down', 25), (panes[0], 'down', 20), (panes[1], 'up', 6)):
            for _ in range(count):
                editor.lua(f'vim.api.nvim_input_mouse("wheel", "{direction}", "", 0, {pane["row"]}, {pane["col"]}); return true')
            time.sleep(0.3)
            left, right = editor.lua('return ' + '(function() ' + top_lines + ' end)()')
            self.assertEqual(left, right, f'panes out of step after wheeling {direction} over column {pane["col"]}')
        self.assertNotEqual(left, 'line 1', 'the wheel did not scroll')

    def test_paste_and_shortcuts_reach_the_built_in_terminal(self):
        # The stub must exist before Neovim loads its clipboard provider, or the real clipboard is used.
        clipboard = ('lua local held = { "echo pasted-$((40+2))" } vim.g.clipboard = { name = "test", '
                     'copy = { ["+"] = function(lines) held = lines end, ["*"] = function(lines) held = lines end }, '
                     'paste = { ["+"] = function() return held end, ["*"] = function() return held end } }')
        editor = self.editor('--cmd', clipboard)
        editor.send(b'\x1b[23;5~67')
        editor.wait_for('vim.api.nvim_get_mode().mode == "t"')
        time.sleep(1)
        editor.send(b'\x1b[23;5~15')
        editor.send(b'\x1b[23;5~29')
        editor.send(b'\r')
        screen = editor.wait_for('(function() local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\\n") '
                                 'return text:find("pasted%-42") and text end)()', timeout=8)
        self.assertNotIn('29', screen.split('pasted-42')[0][-40:], 'shortcut digits reached the shell')
        editor.send(b'\x1b[23;5~67')
        editor.wait_for('vim.bo.buftype ~= "terminal"')

    def test_cmd_w_closes_the_pager_and_run_output_before_quitting(self):
        (self.project/'.jvim').mkdir()
        (self.project/'.jvim/run.json').write_text(json.dumps({'version': 1, 'configurations': [{'name': 'Quick', 'command': ['true']}]}))
        editor = self.editor()
        editor.lua('vim.cmd.edit "main.tex" return true')
        terminal_open = '#vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "terminal" end, vim.api.nvim_tabpage_list_wins(0)) > 0'
        editor.lua('require("jvim.run").run("Quick") return true')
        editor.wait_for('(function() local s = require("jvim.run").current() return s and s.status == "exited" end)()')
        editor.send(b'\x1b[23;5~20')
        editor.wait_for('vim.fn.expand("%:t") == "main.tex" and not (' + terminal_open + ')')
        editor.lua('require("jvim.run").show() vim.cmd.wincmd "p" vim.schedule(function() vim.cmd "messages" end) return true')
        pager_open = '(function() local w = require("vim._core.ui2").wins.pager return vim.api.nvim_win_is_valid(w) and not vim.api.nvim_win_get_config(w).hide end)()'
        editor.wait_for(pager_open)
        editor.send(b'\x1b[23;5~20')
        editor.wait_for('not ' + pager_open + ' and vim.fn.expand("%:t") == "main.tex"')
        editor.send(b'\x1b[23;5~20')
        editor.wait_for('vim.bo.filetype == "neo-tree" and (' + terminal_open + ')')
        editor.send(b'\x1b[23;5~20')
        editor.wait_for('vim.bo.filetype == "neo-tree" and not (' + terminal_open + ')')

    def test_saving_with_run_output_open_restores_without_a_tall_command_line(self):
        (self.project/'.jvim').mkdir()
        (self.project/'.jvim/run.json').write_text(json.dumps({'version': 1, 'configurations': [{'name': 'Quick', 'command': ['true']}]}))
        editor = self.editor()
        editor.lua('vim.cmd.edit "main.tex" return true')
        editor.lua('require("jvim.run").run("Quick") return true')
        editor.wait_for('(function() local s = require("jvim.run").current() return s and s.status == "exited" end)()')
        editor.send(b'\x1b[23;5~63')
        editor.process.wait(timeout=5)
        editor.close()
        editor = self.editor()
        editor.wait_for('vim.fn.expand("%:t") == "main.tex"')
        time.sleep(0.5)
        self.assertEqual(editor.lua('return vim.o.cmdheight'), 0)
        self.assertEqual(editor.lua('return vim.api.nvim_win_get_height(0)'), editor.lua('return vim.o.lines - 1'))

    def test_wheel_scrolling_keeps_the_selection_and_the_next_key_uses_it(self):
        clipboard = ('lua local held = {} vim.g.clipboard = { name = "test", '
                     'copy = { ["+"] = function(lines) held = lines end, ["*"] = function(lines) held = lines end }, '
                     'paste = { ["+"] = function() return held end, ["*"] = function() return held end } }')
        editor = self.editor('--cmd', clipboard)
        editor.lua('vim.cmd.edit "long.txt" return true')
        editor.wait_for('vim.fn.expand("%:t") == "long.txt" and vim.api.nvim_buf_line_count(0) > 100')
        editor.lua('vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        # Select lines 10-12 the way Shift+Down does (Select mode).
        editor.send(b'\x1b[1;2B\x1b[1;2B')
        editor.wait_for('vim.fn.mode() == "s"')
        editor.send(b'\x1b[23;5~13')
        unscrolled = editor.wait_for('vim.fn.getreg("+") ~= "" and vim.fn.getreg("+")')
        editor.send(b'\x1b')
        editor.wait_for('vim.fn.mode() ~= "s"')
        editor.lua('vim.fn.setreg("+", "") vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        editor.send(b'\x1b[1;2B\x1b[1;2B')
        editor.wait_for('vim.fn.mode() == "s"')
        win = editor.lua('local p = vim.fn.win_screenpos(0) return { row = p[1] + 2, col = p[2] + 5 }')
        for _ in range(6):
            editor.send(f"\x1b[<65;{win['col']};{win['row']}M".encode())
        editor.wait_for('vim.fn.line("w0") > 12')
        time.sleep(0.3)
        drawn = editor.lua('local ns = vim.api.nvim_get_namespaces()["clion-scroll-selection"] '
                           'local marks = ns and vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) or {} return #marks > 0 and marks[1][2] + 1')
        editor.send(b'\x1b[23;5~13')
        editor.wait_for('vim.fn.getreg("+") ~= ""')
        self.assertEqual(editor.lua('return vim.fn.getreg("+")'), unscrolled, 'scrolling changed what was selected')
        self.assertEqual(drawn, 10, 'the selection is not drawn where it was')
        self.assertEqual(unscrolled, 'line 10\nline 11\n')
        self.assertEqual(editor.lua('return { vim.fn.mode(), vim.fn.getline(10), vim.fn.getline(11) }'), ['s', 'line 10', 'line 11'])
        editor.send(b'\x1b')
        editor.wait_for('vim.fn.mode() ~= "s"')
        editor.lua('vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        editor.send(b'\x1b[1;2B')
        editor.wait_for('vim.fn.mode() == "s"')
        for _ in range(6):
            editor.send(f"\x1b[<65;{win['col']};{win['row']}M".encode())
        editor.wait_for('vim.fn.line("w0") > 12')
        time.sleep(0.3)
        editor.send(b'X')
        editor.wait_for('vim.fn.getline(10) == "Xline 11"')
        self.assertEqual(editor.lua('return vim.fn.getline(11)'), 'line 12')

    @unittest.skipUnless(shutil.which('rg'), 'project search needs ripgrep')
    def test_project_search_preview_scrolls_to_a_match_far_right(self):
        (self.project/'wide.txt').write_text('short line\n' + ' ' * 300 + 'needle_far_right here\n')
        editor = self.editor()
        editor.send(b'\x1b[23;5~18')
        editor.wait_for('vim.bo.filetype == "TelescopePrompt"')
        editor.send(b'needle_far_right')
        view = editor.wait_for('(function() local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf()) '
                               'local win = picker and picker.previewer and picker.previewer.state and picker.previewer.state.winid '
                               'if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_cursor(win)[1] ~= 2 then return false end '
                               'local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end) '
                               'return leftcol > 0 and { leftcol = leftcol, width = vim.api.nvim_win_get_width(win) } end)()', timeout=10)
        self.assertLessEqual(view['leftcol'], 300)
        self.assertLess(300 + len('needle_far_right'), view['leftcol'] + view['width'], 'the match is still off screen')

    @unittest.skipUnless(shutil.which('rg'), 'project search needs ripgrep')
    def test_project_search_matches_words_split_across_lines(self):
        (self.project/'prose.tex').write_text('The man named bob\nis tall.\nNothing here.\n')
        editor = self.editor()
        editor.send(b'\x1b[23;5~18')
        editor.wait_for('vim.bo.filetype == "TelescopePrompt"')
        editor.send(b'bob is')
        found = editor.wait_for('(function() local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf()) '
                                'if not picker or picker.manager == nil or picker.manager:num_results() == 0 then return false end '
                                'local entry = picker.manager:get_entry(1) return { vim.fs.basename(entry.filename), entry.lnum, entry.col } end)()', timeout=10)
        self.assertEqual(found, ['prose.tex', 1, 15])

    def test_run_form_completes_commands_configurations_and_paths_like_a_shell(self):
        tools = self.home/'tools'
        tools.mkdir()
        (tools/'jvimfaketool').write_text('#!/bin/sh\n')
        (tools/'jvimfaketool').chmod(0o755)
        (self.project/'.jvim').mkdir()
        (self.project/'.jvim/run.json').write_text(json.dumps({'version': 1, 'configurations': [{'name': 'Build thesis', 'command': ['true']}]}))
        path = os.environ['PATH']
        os.environ['PATH'] = f'{tools}:{path}'
        try:
            editor = self.editor()
        finally:
            os.environ['PATH'] = path
        editor.lua('require("jvim.run").form() return true')
        editor.wait_for('vim.bo.filetype == "jvimrun" and vim.fn.mode() == "i"')
        menu = ('(function() local list = require("blink.cmp.completion.list") if #list.items == 0 then return false end '
                'return vim.tbl_map(function(item) return item.source_id .. ":" .. item.label end, list.items) end)()')
        editor.lua('vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        editor.send(b'jvimfake')
        time.sleep(1)  # Polling over RPC while blink debounces the first keystrokes hides the menu.
        items = editor.wait_for(menu, timeout=10)
        self.assertIn('jvim_shell:jvimfaketool', items)
        self.assertTrue(all(item.split(':')[0] in ('jvim_shell', 'path') for item in items), items)
        editor.lua('require("blink.cmp").hide() vim.api.nvim_buf_set_lines(0, 9, 10, false, { "" }) vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        editor.send(b'Run')
        time.sleep(1)  # Polling over RPC while blink debounces the first keystrokes hides the menu.
        self.assertIn('jvim_shell:Run: Build thesis', editor.wait_for(menu, timeout=10))
        editor.lua('require("blink.cmp").hide() vim.api.nvim_buf_set_lines(0, 9, 10, false, { "" }) vim.api.nvim_win_set_cursor(0, { 10, 0 }) return true')
        editor.send(b'cat ./ma')
        time.sleep(1)  # Polling over RPC while blink debounces the first keystrokes hides the menu.
        self.assertIn('path:main.tex', editor.wait_for(menu, timeout=10))

    def test_diagnostic_details_open_on_click_not_when_the_cursor_rests(self):
        editor = self.editor()
        editor.lua('vim.cmd.edit "long.txt" return true')
        editor.wait_for('vim.fn.expand("%:t") == "long.txt" and vim.api.nvim_buf_line_count(0) > 100')
        time.sleep(1)
        editor.lua('local ns = vim.api.nvim_create_namespace("test-diag") vim.diagnostic.set(ns, vim.fn.bufnr("long.txt"), { { lnum = 2, col = 0, end_col = 4, '
                   'severity = vim.diagnostic.severity.WARN, message = "made-up warning" } }) local win = vim.fn.bufwinid("long.txt") vim.api.nvim_set_current_win(win) vim.api.nvim_win_set_width(win, 120) vim.api.nvim_win_set_cursor(win, { 3, 1 }) return true')
        floats = ('#vim.tbl_filter(function(w) local c = vim.api.nvim_win_get_config(w) local b = vim.api.nvim_win_get_buf(w) '
                  'return c.relative ~= "" and not c.hide and table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\\n"):find("made%-up warning") ~= nil end, vim.api.nvim_list_wins())')
        time.sleep(max(1.0, editor.lua('return vim.o.updatetime') / 1000 + 0.5))
        self.assertEqual(editor.lua('return ' + floats), 0, 'resting the cursor opened the details')
        screen = editor.lua('local info = vim.fn.getwininfo(vim.fn.bufwinid("long.txt"))[1] '
                            'return { row = info.winrow + info.winbar + 3 - info.topline, gutter = info.wincol, text = info.wincol + info.textoff }')
        def click(col, row=None):
            row = row or screen['row']
            editor.send(f"\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m".encode())
        click(screen['text'] + 5)
        time.sleep(0.5)
        self.assertEqual(editor.lua('return ' + floats), 0, 'clicking text without a diagnostic opened the details')
        click(screen['gutter'])
        editor.wait_for(floats + ' == 1')
        editor.lua('vim.api.nvim_win_set_cursor(vim.fn.bufwinid("long.txt"), { 20, 0 }) return true')
        editor.wait_for(floats + ' == 0')
        click(screen['text'] + 1)
        editor.wait_for(floats + ' == 1')

    def test_second_editor_restores_files_held_by_the_first_without_swap_warnings(self):
        first = self.editor()
        first.lua('vim.cmd.edit "chapters/intro.tex"; vim.cmd.edit "main.tex"; return true')
        self.assertTrue(first.lua('return require("jvim.session").save() and true or false'))
        second = self.editor()
        second.wait_for('vim.api.nvim_buf_get_name(0):match("%.tex$") ~= nil')
        state = second.lua('local buf = vim.api.nvim_get_current_buf(); return { mode = vim.api.nvim_get_mode().mode, '
                           'readonly = vim.bo[buf].readonly, lines = vim.api.nvim_buf_line_count(buf), '
                           'first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] }')
        self.assertFalse(state['mode'].startswith('r'), f"restoring left a swap prompt waiting (mode {state['mode']})")
        self.assertTrue(state['readonly'], 'a file open in the other jvim should restore read-only')
        self.assertGreater(state['lines'], 1, 'restored file came back empty')
        self.assertTrue(state['first'].startswith('\\'), state)
        messages = second.lua('return vim.api.nvim_exec2("messages", { output = true }).output')
        self.assertNotIn('Found a swap file', messages)

    def test_clicking_a_checkbox_ticks_the_file_for_commit(self):
        editor = self.editor()
        editor.lua('require("jvim.changes").open(); return true')
        editor.wait_for('vim.bo.filetype == "jvim-changes"')
        find_row = ('for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do '
                    'if text:find("long.txt", 1, true) then local win = vim.api.nvim_get_current_win() '
                    'local box = vim.fn.screenpos(win, line, #text:match("^ *") + 1) '
                    'local name = vim.fn.screenpos(win, line, (text:find("long.txt", 1, true))) '
                    'return { row = box.row - 1, col = box.col - 1, name = name.col - 1, text = text } end end')
        target = editor.lua(find_row)
        self.assertTrue(target['text'].lstrip().startswith('☐'), target)

        def click(col):
            editor.lua(f'vim.api.nvim_input_mouse("left", "press", "", 0, {target["row"]}, {col}); '
                       f'vim.api.nvim_input_mouse("left", "release", "", 0, {target["row"]}, {col}); return true')

        click(target['name'])
        time.sleep(0.5)
        self.assertTrue(editor.lua(find_row)['text'].lstrip().startswith('☐'), 'clicking the file name ticked it')
        click(target['col'])
        ticked = editor.wait_for('(function() ' + find_row + ' end)().text:find("☑") ~= nil')
        self.assertTrue(ticked)
        staged = subprocess.run(['git', 'diff', '--cached', '--name-only'], cwd=self.project, capture_output=True, text=True).stdout
        self.assertEqual(staged.strip(), 'long.txt')
        click(target['col'])
        editor.wait_for('(function() ' + find_row + ' end)().text:find("☐") ~= nil')

    def test_selecting_lines_and_clicking_a_hunk_box_stages_only_those_lines(self):
        long = self.project/'long.txt'
        lines = long.read_text().splitlines()
        lines[4], lines[5] = 'changed 5', 'changed 6'
        long.write_text('\n'.join(lines) + '\n')
        editor = self.editor()
        editor.lua('require("jvim.changes").open(); return true')
        editor.wait_for('vim.bo.filetype == "jvim-changes"')
        editor.lua('for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do '
                   'if text:find("long.txt", 1, true) then vim.api.nvim_win_set_cursor(0, { line, 0 }) end end return true')
        work = editor.wait_for('(function() for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do '
                               'if vim.wo[win].statuscolumn ~= "" then return win end end end)()')
        box = editor.lua(f'vim.api.nvim_set_current_win({work}); vim.api.nvim_win_set_cursor(0, {{ 5, 0 }}); vim.cmd "normal! V"; '
                         f'local pos = vim.fn.screenpos({work}, 5, 1); '
                         f'return {{ row = pos.row - 1, col = pos.col - 1 - vim.fn.getwininfo({work})[1].textoff }}')
        editor.lua(f'vim.api.nvim_input_mouse("left", "press", "", 0, {box["row"]}, {box["col"]}); '
                   f'vim.api.nvim_input_mouse("left", "release", "", 0, {box["row"]}, {box["col"]}); return true')

        def staged():
            return subprocess.run(['git', 'diff', '--cached', '-U0'], cwd=self.project, capture_output=True, text=True).stdout

        deadline = time.monotonic() + 5
        while '+changed 5' not in staged() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertIn('-line 5\n+changed 5\n', staged())
        self.assertNotIn('changed 6', staged())
        self.assertNotIn('-line 50', staged())
        editor.lua('require("jvim.changes").close(); vim.cmd.buffer(vim.fn.bufnr("long.txt")); return true')
        self.assertEqual(editor.lua('return vim.wo.statuscolumn'), '', 'checkbox column followed the file out of the diff')
