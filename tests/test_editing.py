"""Focused editing foundations, independent of plugin installation."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which('nvim'), 'Neovim required')
class EditingTests(unittest.TestCase):
    def lua(self, body):
        with tempfile.TemporaryDirectory(prefix='jvim-editing-') as directory:
            script = Path(directory)/'test.lua'
            script.write_text("vim.opt.rtp:prepend(" + repr(str(ROOT/'config')) + ")\nvim.o.swapfile=false\n" + body + "\nvim.cmd('qall!')\n")
            result = subprocess.run(['nvim','--headless','-u','NONE','-i','NONE','-l',str(script)], capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_horizontal_swipes_move_text_with_the_finger(self):
        self.lua("""
local home = vim.fn.tempname()
vim.fn.mkdir(home .. '/.local/state/jvim', 'p')
vim.env.HOME = home
require('jvim.keymaps')
vim.o.wrap = false
vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep('x', 400) })
local function swipe(key)
  vim.api.nvim_win_set_cursor(0, { 1, 100 })
  vim.fn.winrestview { leftcol = 60 }
  vim.api.nvim_feedkeys(vim.keycode(key), 'x', false)
  return vim.fn.winsaveview().leftcol
end
assert(swipe('<ScrollWheelLeft>') > 60, 'trackpad swipe left must reveal text to the right')
assert(swipe('<ScrollWheelRight>') < 60, 'trackpad swipe right must reveal text to the left')
vim.fn.writefile({}, home .. '/.local/state/jvim/wezterm-focused')
assert(swipe('<ScrollWheelLeft>') < 60, 'WezTerm already reports natural direction, so it must not be flipped again')
""")

    def test_utf8_boundaries_and_character_distances(self):
        self.lua("""
local selection = require('jvim.selection')
vim.api.nvim_buf_set_lines(0,0,-1,false,{'αβ next'})
vim.api.nvim_win_set_cursor(0,{1,0})
assert(selection.target(1,true)==4)
assert(selection.select(1)=='<S-Right><S-Right>')
assert(selection.target(1,false)==2, 'normal target must start on β')
vim.o.virtualedit='onemore'
vim.api.nvim_win_set_cursor(0,{1,4})
assert(selection.select(-1)=='<S-Left><S-Left>')
""")

    def test_cycle_includes_unvisited_listed_files(self):
        self.lua("""
local files=require('jvim.files')
files.setup(vim.api.nvim_create_augroup('test',{}))
local a=vim.api.nvim_create_buf(true,false)
local b=vim.api.nvim_create_buf(true,false)
vim.api.nvim_buf_set_name(a,'/tmp/jvim-test-a')
vim.api.nvim_buf_set_name(b,'/tmp/jvim-test-b')
vim.api.nvim_set_current_buf(a)
files.cycle(1)
assert(vim.api.nvim_get_current_buf()==b,'unvisited listed file omitted')
""")

    def test_context_retains_origin_and_rejects_deleted_buffer(self):
        self.lua("""
local editing=require('jvim.editing')
local origin=vim.api.nvim_get_current_buf()
local context=editing.capture()
vim.cmd.enew()
local other=vim.api.nvim_get_current_buf()
assert(context:apply(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'origin'}) end))
assert(vim.api.nvim_get_current_buf()==other)
assert(vim.api.nvim_buf_get_lines(origin,0,-1,false)[1]=='origin')
vim.api.nvim_buf_delete(origin,{force=true})
assert(not context:apply(function() error('must not run') end))
""")

    def test_history_preserves_mouse_and_native_jumps(self):
        self.lua("""
local history=require('jvim.navigation_history')
vim.api.nvim_buf_set_name(0,'/tmp/jvim-test-history')
vim.api.nvim_buf_set_lines(0,0,-1,false,{'one','two','three','four'})
history.setup(function() end)
history.remember(0,{1,0})
vim.api.nvim_win_set_cursor(0,{2,0})
vim.cmd('normal! G')
history.back()
assert(vim.api.nvim_win_get_cursor(0)[1]==2,'native jump origin omitted')
history.back()
assert(vim.api.nvim_win_get_cursor(0)[1]==1,'mouse origin omitted')
history.forward()
assert(vim.api.nvim_win_get_cursor(0)[1]==2)
history.forward()
assert(vim.api.nvim_win_get_cursor(0)[1]==4)
""")

    def test_native_lsp_cross_file_jump_and_departures(self):
        self.lua("""
local history=require('jvim.navigation_history')
local a=vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(a,'/tmp/jvim-history-source')
vim.api.nvim_buf_set_lines(a,0,-1,false,{'one','two','three'})
history.setup(function() end)
vim.api.nvim_win_set_cursor(0,{2,0})
local b=vim.api.nvim_create_buf(true,false)
vim.api.nvim_buf_set_name(b,'/tmp/jvim-history-target')
vim.api.nvim_buf_set_lines(b,0,-1,false,{'target','second'})
vim.lsp.util.show_document({uri=vim.uri_from_bufnr(b),range={start={line=1,character=0},['end']={line=1,character=1}}},'utf-8',{focus=true})
history.back()
assert(vim.api.nvim_get_current_buf()==a)
assert(vim.api.nvim_win_get_cursor(0)[1]==2)
history.forward()
assert(vim.api.nvim_get_current_buf()==b)
assert(vim.api.nvim_win_get_cursor(0)[1]==2)
""")

    def test_delayed_go_to_line_targets_origin_window(self):
        self.lua("""
local actions={}
require('jvim.clion_actions').setup(function(_,callback,desc) actions[desc]=callback end,function() end)
local origin=vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(origin,0,-1,false,{'first','second'})
local origin_win=vim.api.nvim_get_current_win()
local answer
vim.ui.input=function(_,callback) answer=callback end
actions['Go to line']()
vim.cmd('vnew')
local other=vim.api.nvim_get_current_buf()
answer('2')
assert(vim.api.nvim_get_current_buf()==other)
assert(vim.api.nvim_win_get_cursor(origin_win)[1]==2)
assert(vim.api.nvim_win_get_cursor(0)[1]==1)
""")

    def test_cycle_from_nonfile_does_not_duplicate_first_file(self):
        self.lua("""
local files=require('jvim.files')
vim.bo.buftype='nofile'
local a=vim.api.nvim_create_buf(true,false)
local b=vim.api.nvim_create_buf(true,false)
vim.api.nvim_buf_set_name(a,'/tmp/jvim-cycle-a')
vim.api.nvim_buf_set_name(b,'/tmp/jvim-cycle-b')
files.cycle(1)
assert(vim.api.nvim_get_current_buf()==a)
files.cycle(1)
assert(vim.api.nvim_get_current_buf()==b,'first file duplicated in cycle')
files.cycle(1)
assert(vim.api.nvim_get_current_buf()==a)
""")

    def test_back_from_tool_window_restores_latest_file_location(self):
        self.lua("""
local history=require('jvim.navigation_history')
local a=vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(a,'/tmp/jvim-history-editor')
vim.api.nvim_buf_set_lines(a,0,-1,false,{'one','two','three'})
history.setup(function() end)
history.remember(a,{1,0})
vim.api.nvim_win_set_cursor(0,{3,0})
vim.cmd.enew()
vim.bo.buftype='nofile'
history.back()
assert(vim.api.nvim_get_current_buf()==a)
assert(vim.api.nvim_win_get_cursor(0)[1]==3,'back skipped latest editor departure')
""")
