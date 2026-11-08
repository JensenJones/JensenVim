vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root = vim.uv.fs_realpath(vim.env.JVIM_TEST_PROJECT)
local phase = vim.env.JVIM_SESSION_PHASE
vim.cmd.cd(vim.fn.fnameescape(root))
local function path(name) return root .. '/' .. name end
if phase == 'save' then
  for _, name in ipairs { 'main.txt', 'other.txt', 'third.txt' } do vim.fn.writefile(vim.fn.range(1, 100), path(name)) end
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
  vim.api.nvim_set_current_win(first)
  files.show(buffer('third.txt'))
  vim.api.nvim_win_set_cursor(0, { 23, 0 })
  assert(#files.pane_tabs(first) == 2 and #files.pane_tabs(second) == 2,
    'test setup did not create separate pane tabs: ' .. vim.inspect({ first = files.pane_tabs(first), second = files.pane_tabs(second) }))
  local ok, err = require('jvim.session').save(root)
  assert(ok, tostring(err))
elseif phase == 'restore' then
  local group = vim.api.nvim_create_augroup('session-test-files', { clear = true })
  require('jvim.files').setup(group, { tree = false })
  assert(require('jvim.session').restore(root), 'workspace did not restore')
  local wins = vim.api.nvim_tabpage_list_wins(0)
  assert(#wins == 2, 'expected two restored panes, got ' .. #wins)
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
  assert(positions[path('third.txt')] == 23 or positions[path('other.txt')] == 42, 'saved cursor location was not restored')
else
  error('unknown session phase: ' .. tostring(phase))
end
vim.cmd 'qall!'
