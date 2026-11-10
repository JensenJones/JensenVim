vim.o.swapfile = false
vim.o.columns, vim.o.lines = 200, 50
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root = vim.uv.fs_realpath(vim.env.JVIM_TEST_PROJECT)
vim.cmd.cd(vim.fn.fnameescape(root))
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect { actual = actual, expected = expected })
end
local changes = require 'jvim.changes'
local items = assert(changes.collect(root))
local summary = {}
for _, item in ipairs(items) do summary[item.path] = { item.status, item.added, item.removed, item.old } end
equal(summary, {
  ['src/core/edit.txt'] = { 'M', 1, 1 },
  ['src/core/new.txt'] = { 'A', 2, 0 },
  ['notes.txt'] = { 'U', 3, 0 },
  ['gone.txt'] = { 'D', 0, 2 },
  ['moved.txt'] = { 'R', 0, 0, 'before.txt' },
})
vim.cmd.edit(vim.fn.fnameescape(root .. '/notes.txt'))
local editor_tab = vim.api.nvim_get_current_tabpage()
changes.open()
assert(vim.api.nvim_get_current_tabpage() ~= editor_tab and vim.t.jvim_changes, 'changes did not open in their own tab')
local panel = vim.api.nvim_get_current_win()
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1]:find('Changes  5 files  +6 -3', 1, true), lines[1])
assert(vim.tbl_contains(lines, '▾ src/core'), 'single-child folders were not compressed: ' .. vim.inspect(lines))
assert(vim.tbl_contains(lines, '  M  edit.txt  +1 -1'), vim.inspect(lines))
assert(vim.tbl_contains(lines, 'R  moved.txt  ← before.txt'), vim.inspect(lines))
local function row_of(text)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do if line == text then return row end end
end
vim.api.nvim_win_set_cursor(panel, { row_of('  M  edit.txt  +1 -1'), 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
local wins = vim.api.nvim_tabpage_list_wins(0)
assert(#wins == 3 and vim.api.nvim_get_current_win() == panel, 'moving onto a file should preview its diff and keep focus')
local diffs = vim.tbl_filter(function(win) return vim.wo[win].diff end, wins)
assert(#diffs == 2, 'expected two windows in diff mode')
local work = vim.tbl_filter(function(win) return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == root .. '/src/core/edit.txt' end, wins)[1]
assert(work, 'working file is not shown')
local base = vim.tbl_filter(function(win) return win ~= work and win ~= panel end, wins)[1]
equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(base), 0, -1, false), { 'one', 'two', 'three' })
assert(not vim.bo[vim.api.nvim_win_get_buf(base)].modifiable, 'HEAD side should be read-only')
assert(vim.fn.screenpos(base, 1, 1).col < vim.fn.screenpos(work, 1, 1).col, 'HEAD should be on the left')
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
assert(vim.api.nvim_get_current_win() == work, 'Enter should focus the editable working file')
vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'two' })
vim.cmd.write()
vim.wait(1000, function() return #assert(changes.collect(root)) == 4 end, 10)
vim.wait(500, function() return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(panel), 0, 1, false)[1]:find('4 files', 1, true) end, 10)
assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(panel), 0, 1, false)[1]:find('4 files', 1, true), 'panel did not refresh after saving')
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'diff for a file without changes stayed open')
vim.api.nvim_set_current_win(panel)
vim.api.nvim_win_set_cursor(panel, { row_of('▾ src/core'), 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), '▸ src/core'), 'folder did not collapse')
vim.api.nvim_win_set_cursor(panel, { row_of('D  gone.txt  -2'), 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'deleted file diff did not open')
changes.close()
assert(vim.api.nvim_get_current_tabpage() == editor_tab and #vim.api.nvim_list_tabpages() == 1, 'closing changes did not return to the editor tab')
vim.cmd 'qall!'
