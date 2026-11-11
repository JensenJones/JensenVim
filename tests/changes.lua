vim.o.swapfile = false
vim.o.columns, vim.o.lines = 200, 50
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root = vim.uv.fs_realpath(vim.env.JVIM_TEST_PROJECT)
vim.cmd.cd(vim.fn.fnameescape(root))
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect { actual = actual, expected = expected })
end
local changes = require 'jvim.changes'
if vim.env.JVIM_TEST_CASE == 'live_swap' then
  vim.o.swapfile = true
  local messages = {}
  vim.notify = function(message) messages[#messages + 1] = message end
  changes.open()
  local diffs = vim.tbl_filter(function(win) return vim.wo[win].diff end, vim.api.nvim_tabpage_list_wins(0))
  assert(#diffs == 2, 'diff did not open for a file with a live swap: ' .. vim.inspect(messages))
  local work = vim.tbl_filter(function(win) return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' end, diffs)[1]
  assert(vim.bo[vim.api.nvim_win_get_buf(work)].readonly, 'file open elsewhere should be read-only: ' .. vim.inspect({ messages, vim.o.directory, vim.fn.swapname(vim.api.nvim_win_get_buf(work)), vim.fn.glob(vim.fn.stdpath('state') .. '/swap/*') }))
  vim.wait(200, function() return #messages > 0 end)
  assert(messages[1] and messages[1]:find('open in another jvim', 1, true), vim.inspect(messages))
  vim.cmd 'qall!'
end
if vim.env.JVIM_TEST_CASE == 'scroll' then
  changes.open()
  local panel = vim.api.nvim_get_current_win()
  local diffs = vim.tbl_filter(function(win) return vim.wo[win].diff end, vim.api.nvim_tabpage_list_wins(0))
  local base, work = diffs[1], diffs[2]
  if vim.fn.screenpos(base, 1, 1).col > vim.fn.screenpos(work, 1, 1).col then base, work = work, base end
  local panel_width = vim.api.nvim_win_get_width(panel)
  assert(panel_width < 30, 'file tree is wider than its contents need: ' .. panel_width)
  local function top_text(win)
    local top = vim.api.nvim_win_call(win, vim.fn.winsaveview).topline
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), top - 1, top, false)[1]
  end
  -- Scroll each pane while the tree keeps focus, as the mouse wheel does.
  for _, case in ipairs { { work, 150, 'line 160' }, { base, 40, 'line 40' }, { work, 120, 'line 130' } } do
    local win, top, expected = case[1], case[2], case[3]
    vim.api.nvim_win_call(win, function() vim.fn.winrestview { topline = top, lnum = top } end)
    vim.api.nvim_exec_autocmds('WinScrolled', {})
    equal({ top_text(base), top_text(work) }, { expected, expected })
  end
  assert(vim.api.nvim_get_current_win() == panel, 'scrolling moved focus away from the tree')
  vim.api.nvim_win_set_cursor(work, { 1, 0 })
  changes.jump(true)
  local change_line = vim.api.nvim_win_get_cursor(work)[1]
  assert(change_line >= 48 and change_line <= 50, 'F7 did not reach the deleted block: ' .. change_line)
  changes.jump(true)
  equal(vim.api.nvim_win_get_cursor(work)[1], change_line)
  changes.toggle_fold()
  assert(vim.wo[base].foldenable and vim.wo[work].foldenable, 'fold toggle did not fold unchanged lines')
  local asked
  vim.fn.confirm = function(_, choices) asked = choices; return 2 end
  local head = vim.system({ 'git', '-C', root, 'rev-parse', 'HEAD' }, { text = true }):wait().stdout
  changes.commit()
  local keys = {}
  for key in assert(asked, 'committing with nothing staged did not ask first'):gmatch '&(.)' do
    assert(not keys[key:lower()], 'commit buttons share the shortcut ' .. key .. ': ' .. asked)
    keys[key:lower()] = true
  end
  equal(vim.system({ 'git', '-C', root, 'rev-parse', 'HEAD' }, { text = true }):wait().stdout, head)
  vim.cmd 'qall!'
end
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
assert(vim.tbl_contains(lines, '▾ ◩ src/core'), 'single-child folders were not compressed: ' .. vim.inspect(lines))
assert(vim.tbl_contains(lines, '2 of 5 selected to commit'), 'selection count missing: ' .. vim.inspect(lines))
assert(vim.tbl_contains(lines, '  ☐ M  edit.txt  +1 -1'), vim.inspect(lines))
assert(vim.tbl_contains(lines, '☑ R  moved.txt  ← before.txt'), 'staged rename lacks its marker: ' .. vim.inspect(lines))
assert(vim.tbl_contains(lines, '☐ U  notes.txt  +3'), vim.inspect(lines))
local function row_of(text)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do if line == text then return row end end
end
vim.api.nvim_win_set_cursor(panel, { row_of('  ☐ M  edit.txt  +1 -1'), 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
local wins = vim.api.nvim_tabpage_list_wins(0)
assert(#wins == 3 and vim.api.nvim_get_current_win() == panel, 'moving onto a file should preview its diff and keep focus')
local diffs = vim.tbl_filter(function(win) return vim.wo[win].diff end, wins)
assert(#diffs == 2, 'expected two windows in diff mode')
local work = vim.tbl_filter(function(win) return vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) == vim.fs.normalize(root .. '/src/core/edit.txt') end, wins)[1]
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
vim.api.nvim_win_set_cursor(panel, { row_of('▾ ☑ src/core'), 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), '▸ ☑ src/core'), 'folder did not collapse')
vim.api.nvim_win_set_cursor(panel, { row_of('▸ ☑ src/core'), 0 })
changes.toggle_stage()
assert(row_of('▸ ☐ src/core'), 'unticking a folder did not unstage its files: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
local function rows_for(...)
  local rows = {}
  for _, text in ipairs { ... } do
    local row = assert(row_of(text), text)
    rows[#rows + 1] = row
  end
  return rows
end
local panel_rows = rows_for('▸ ☐ src/core', '☐ D  gone.txt  -2')
vim.cmd(('normal! %dGV%dG'):format(panel_rows[1], panel_rows[2]))
vim.api.nvim_feedkeys(' ', 'mx', false)
assert(row_of('▸ ☑ src/core') and row_of('☑ D  gone.txt  -2'), 'ticking a selection did not stage every selected row: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.cmd(('normal! %dGV%dG'):format(panel_rows[1], panel_rows[2]))
vim.api.nvim_feedkeys(' ', 'mx', false)
assert(row_of('▸ ☐ src/core') and row_of('☐ D  gone.txt  -2'), 'unticking a selection did not unstage every row')
vim.api.nvim_win_set_cursor(panel, { row_of('☐ D  gone.txt  -2'), 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'deleted file diff did not open')
vim.api.nvim_set_current_win(panel)
vim.api.nvim_win_set_cursor(panel, { row_of('☐ U  notes.txt  +3'), 0 })
changes.toggle_stage()
assert(row_of('☑ A  notes.txt  +3'), 'staging did not mark the file: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.api.nvim_win_set_cursor(panel, { row_of('☑ A  notes.txt  +3'), 0 })
changes.toggle_stage()
assert(row_of('☐ U  notes.txt  +3'), 'unstaging did not clear the marker')
vim.api.nvim_win_set_cursor(panel, { row_of('☐ U  notes.txt  +3'), 0 })
changes.toggle_stage()
local staged_only = vim.system({ 'git', '-C', root, 'diff', '--cached', '--name-only' }, { text = true }):wait().stdout
vim.ui.input = function(_, on_confirm) on_confirm('Add notes') end
changes.commit()
local subject = vim.system({ 'git', '-C', root, 'log', '-1', '--format=%s' }, { text = true }):wait().stdout
equal(subject, 'Add notes\n')
local committed = vim.system({ 'git', '-C', root, 'show', '--name-only', '--format=', 'HEAD' }, { text = true }):wait().stdout
equal(committed, staged_only)
assert(not row_of('☐ U  notes.txt  +3') and not row_of('☑ A  notes.txt  +3'), 'committed file still listed')
changes.close()
assert(vim.api.nvim_get_current_tabpage() == editor_tab and #vim.api.nvim_list_tabpages() == 1, 'closing changes did not return to the editor tab')
vim.cmd 'qall!'
