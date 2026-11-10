vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root = vim.uv.fs_realpath(vim.env.JVIM_TEST_PROJECT)
local phase = vim.env.JVIM_SESSION_PHASE
vim.o.splitright, vim.o.splitbelow = true, true
vim.cmd.cd(vim.fn.fnameescape(root))
local function path(name) return root .. '/' .. name end
if phase == 'save' then
  for _, name in ipairs { 'main.txt', 'other.txt', 'third.txt', 'fourth.txt' } do vim.fn.writefile(vim.fn.range(1, 100), path(name)) end
  vim.cmd.edit(vim.fn.fnameescape(path('main.txt')))
  local first = vim.api.nvim_get_current_win()
  local group = vim.api.nvim_create_augroup('session-test-files', { clear = true })
  local files = require 'jvim.files'
  files.setup(group, { tree = false })
  local function buffer(name)
    local buf = vim.fn.bufadd(path(name))
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = true
    return buf
  end
  vim.cmd.vsplit()
  local second = vim.api.nvim_get_current_win()
  files.show(buffer('other.txt'))
  vim.api.nvim_win_set_cursor(second, { 42, 0 })
  vim.cmd.split()
  files.show(buffer('fourth.txt'))
  vim.api.nvim_win_set_cursor(0, { 77, 0 })
  vim.api.nvim_set_current_win(first)
  files.show(buffer('third.txt'))
  vim.api.nvim_win_set_cursor(0, { 23, 0 })
  vim.api.nvim_win_set_width(first, 50)
  assert(#files.pane_tabs(first) == 2 and #files.pane_tabs(second) == 2,
    'test setup did not create separate pane tabs: ' .. vim.inspect({ first = files.pane_tabs(first), second = files.pane_tabs(second) }))
  local ok, err = require('jvim.session').save(root .. '/nested')
  assert(ok, tostring(err))
elseif phase == 'restore' then
  local group = vim.api.nvim_create_augroup('session-test-files', { clear = true })
  require('jvim.files').setup(group, { tree = false })
  assert(require('jvim.session').restore(root .. '/nested'), 'workspace did not restore')
  local wins = vim.api.nvim_tabpage_list_wins(0)
  assert(#wins == 3, 'expected three restored panes, got ' .. #wins)
  local layout = vim.fn.winlayout()
  assert(layout[1] == 'row' and layout[2][2][1] == 'col', 'split layout was not restored: ' .. vim.inspect(layout))
  assert(vim.api.nvim_buf_get_name(0) == path('third.txt'), 'focused pane was not restored')
  assert(vim.api.nvim_win_get_width(0) == 50, 'pane width was not restored: ' .. vim.api.nvim_win_get_width(0))
  local files = require 'jvim.files'
  local sets = {}
  for _, win in ipairs(wins) do
    local names = {}
    for _, buf in ipairs(files.pane_tabs(win)) do names[#names + 1] = vim.api.nvim_buf_get_name(buf) end
    sets[table.concat(names, ',')] = true
  end
  assert(sets[path('main.txt') .. ',' .. path('third.txt')], 'first pane tab order was not restored: ' .. vim.inspect(sets))
  assert(sets[path('main.txt') .. ',' .. path('other.txt')], 'second pane tab order was not restored')
  local positions = {}
  for _, win in ipairs(wins) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    positions[name] = vim.api.nvim_win_get_cursor(win)[1]
  end
  equal_positions = { positions[path('third.txt')], positions[path('fourth.txt')] }
  assert(vim.deep_equal(equal_positions, { 23, 77 }), 'saved cursor locations were not restored: ' .. vim.inspect(positions))
  assert(#vim.tbl_filter(function(b) return vim.api.nvim_buf_get_name(b) == '' and vim.bo[b].buflisted end, vim.api.nvim_list_bufs()) == 0,
    'startup placeholder buffer was left behind')
elseif phase == 'restore_startup' then
  vim.cmd.cd(vim.fn.fnameescape(root .. '/nested'))
  local group = vim.api.nvim_create_augroup('clion-editing', { clear = true })
  require('jvim.files').setup(group, { tree = false })
  vim.api.nvim_list_uis = function() return { {} } end
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'JvimFileHistory' })
  vim.wait(500, function() return #vim.api.nvim_tabpage_list_wins(0) > 2 end, 10)
  assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'startup hook did not restore the project splits')
  assert(#require('jvim.files').pane_tabs(vim.api.nvim_tabpage_list_wins(0)[1]) > 0,
    'startup hook did not restore pane tabs')
elseif phase == 'panes' then
  for _, name in ipairs { 'a.txt', 'b.txt', 'c.txt', 'd.txt' } do vim.fn.writefile(vim.fn.range(1, 100), path(name)) end
  local files = require 'jvim.files'
  files.setup(vim.api.nvim_create_augroup('session-test-files', { clear = true }), { tree = false })
  local function names(win)
    return vim.tbl_map(function(buf) return vim.fs.basename(vim.api.nvim_buf_get_name(buf)) end, files.pane_tabs(win))
  end
  local function open(name, line)
    local buf = vim.fn.bufadd(path(name)); vim.fn.bufload(buf); vim.bo[buf].buflisted = true
    files.show(buf)
    if line then vim.api.nvim_win_set_cursor(0, { line, 0 }) end
  end
  vim.cmd.edit(vim.fn.fnameescape(path('a.txt')))
  local left = vim.api.nvim_get_current_win()
  open('b.txt', 10)
  vim.cmd.vsplit()
  local right = vim.api.nvim_get_current_win()
  open('c.txt')
  open('b.txt', 60)
  open('d.txt')
  assert(vim.deep_equal(names(left), { 'a.txt', 'b.txt' }), vim.inspect(names(left)))
  assert(vim.deep_equal(names(right), { 'b.txt', 'c.txt', 'd.txt' }), vim.inspect(names(right)))
  for _ = 1, 6 do
    files.cycle(1)
    assert(vim.tbl_contains({ 'b.txt', 'c.txt', 'd.txt' }, vim.fs.basename(vim.api.nvim_buf_get_name(0))), 'cycling left the pane tabs')
  end
  while vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= 'b.txt' do files.cycle(1) end
  assert(vim.api.nvim_win_get_cursor(0)[1] == 60, 'right pane lost its own location in b.txt')
  vim.api.nvim_set_current_win(left)
  while vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= 'b.txt' do files.cycle(1) end
  assert(vim.api.nvim_win_get_cursor(0)[1] == 10, 'left pane lost its own location in b.txt')
  local winbar = files.render_winbar(right)
  assert(winbar:find('JvimTabLineSelNC', 1, true) and not winbar:find('#TabLineSel#', 1, true), 'unfocused pane uses the focused selection colour')
  assert(files.render_winbar(left):find('#TabLineSel#', 1, true), 'focused pane lacks the selection colour')
  vim.api.nvim_set_current_win(right)
  open('c.txt', 33)
  files.close_current_tab()
  assert(not vim.tbl_contains(names(right), 'c.txt'), 'closed tab still in pane')
  assert(files.reopen_closed() and vim.api.nvim_get_current_win() == right and vim.api.nvim_win_get_cursor(0)[1] == 33,
    'reopen did not restore the tab in its pane at its location')
  for _ = 1, 3 do vim.api.nvim_set_current_win(right); files.close_current_tab() end
  assert(not vim.api.nvim_win_is_valid(right) and #vim.api.nvim_tabpage_list_wins(0) == 1, 'closing the last tab did not close the split')
  assert(files.reopen_closed(), 'reopen after closing the split failed')
  local wins = vim.api.nvim_tabpage_list_wins(0)
  assert(#wins == 2 and vim.fn.winlayout()[1] == 'row', 'reopening did not recreate the split: ' .. vim.inspect(vim.fn.winlayout()))
  assert(vim.api.nvim_get_current_win() ~= left and vim.fn.win_screenpos(0)[2] > vim.fn.win_screenpos(left)[2], 'split reopened on the wrong side')
  assert(#names(0) == 1, 'recreated split should start with only the reopened tab: ' .. vim.inspect(names(0)))
else
  error('unknown session phase: ' .. tostring(phase))
end
vim.cmd 'qall!'
