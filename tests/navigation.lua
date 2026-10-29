vim.o.swapfile = false
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
for _, plugin in ipairs { 'plenary.nvim', 'nui.nvim', 'neo-tree.nvim', 'mini.nvim' } do
  vim.opt.rtp:append(vim.env.JVIM_TEST_PLUGINS .. '/' .. plugin)
end
vim.fn.mkdir(vim.fn.stdpath 'data', 'p')
vim.api.nvim_create_augroup('FileExplorer', {})
local opts = require('kickstart.plugins.neo-tree').opts
opts.enable_git_status = false
opts.enable_diagnostics = false
opts.sources = { 'filesystem' }
opts.filesystem.use_libuv_file_watcher = false
opts.filesystem.filtered_items = { hide_gitignored = false }
require('neo-tree').setup(opts)
vim.cmd 'runtime plugin/neo-tree.lua'
require('mini.tabline').setup()
require 'custom.keymaps'
vim.v.errmsg = ''
-- Exercise desktop startup without starting a desktop UI or plugin manager.
vim.api.nvim_list_uis = function() return { {} } end
local root = vim.env.JVIM_TEST_PROJECT
local main, other = root .. '/main.txt', root .. '/other.txt'
local third = root .. '/third.txt'
local function settle()
  vim.wait(150, function() return false end, 10)
end
local function press(key)
  vim.fn.maparg(key, 'n', false, true).callback()
  settle()
end
local function press_typed(key)
  vim.api.nvim_feedkeys(vim.keycode(key), 'mxt', false)
  settle()
end
local function tree_state() return require('neo-tree.sources.manager').get_state 'filesystem' end
local function focus_tree()
  require('neo-tree.command').execute { action = 'focus', position = 'left', dir = root }
  settle()
end
local function open(path)
  require('neo-tree.utils').open_file(tree_state(), path)
  settle()
  return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
end
local function assert_no_placeholder()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
      local name = vim.api.nvim_buf_get_name(buf)
      assert(name ~= '' and vim.fn.isdirectory(name) == 0, 'startup left an empty or directory buffer: ' .. buf)
    end
  end
end
local case = vim.env.JVIM_TEST_CASE
if case == 'directory' or case == 'bare' then
  vim.cmd.cd(vim.fn.fnameescape(root))
  if case == 'directory' then vim.cmd.args(vim.fn.fnameescape(root)) end
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  assert(vim.bo.filetype == 'neo-tree', 'project startup did not focus tree')
  assert(#vim.api.nvim_list_wins() == 1, 'project startup left a blank editor pane')
  assert_no_placeholder()
  local buf, win = open(main)
  assert(vim.api.nvim_buf_get_name(buf) == main, 'tree did not open main: ' .. vim.api.nvim_buf_get_name(buf))
  for _ = 1, 3 do
    press '<C-Tab>'
    assert(vim.api.nvim_get_current_buf() == buf, 'single-file cycling selected a placeholder')
    assert(vim.api.nvim_get_current_win() == win, 'single-file cycling changed editor panes')
  end
  assert_no_placeholder()
elseif case == 'switch_from_tree' or case == 'click_from_tree' or case == 'restore_hidden_file' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf, win = open(main)
  local otherbuf = open(other)
  focus_tree()
  local unloaded = {}
  vim.api.nvim_create_autocmd('BufUnload', {
    callback = function(args)
      if args.buf == mainbuf or args.buf == otherbuf then table.insert(unloaded, args.buf) end
    end,
  })
  if case == 'restore_hidden_file' then vim.api.nvim_win_close(win, false) end
  if case == 'click_from_tree' then
    vim.fn.MiniTablineSwitchBuffer(mainbuf, 1, 'l', '')
    settle()
  else
    press '<C-Tab>'
  end
  if case ~= 'restore_hidden_file' then assert(vim.api.nvim_get_current_win() == win, 'switching from tree did not focus existing editor pane') end
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'switching from tree did not display main')
  assert(vim.api.nvim_buf_is_loaded(otherbuf), 'switching unloaded another open file')
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == otherbuf, 'next file was not displayed')
  press '<C-S-Tab>'
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'previous file was not displayed')
  assert(#unloaded == 0, 'switching from tree unloaded an open file')
  assert_no_placeholder()
elseif case == 'close_blank' or case == 'close_file' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf, win = open(main)
  local closing
  if case == 'close_file' then
    closing = open(other)
  else
    vim.cmd.enew()
    closing = vim.api.nvim_get_current_buf()
  end
  press '<D-w>'
  assert(vim.api.nvim_get_current_win() == win, 'closing a buffer destroyed editor pane')
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'closing a buffer did not display remaining main file')
  assert(not vim.api.nvim_buf_is_valid(closing) or not vim.bo[closing].buflisted, 'closed buffer stayed in file rotation')
  for _ = 1, 3 do
    press '<C-Tab>'
    assert(vim.api.nvim_get_current_buf() == mainbuf, 'cycling after close lost main file')
  end
elseif case == 'modified_startup' then
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved work' })
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  assert(vim.api.nvim_get_current_buf() == buf and vim.bo.buflisted, 'startup hid unsaved work')
  assert(vim.fn.getline(1) == 'unsaved work', 'startup changed unsaved work')
elseif case == 'tree_toggle' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  local mainbuf = open(main)
  press_typed '\\'
  assert(vim.bo.filetype ~= 'neo-tree', 'Backslash did not close tree from Normal mode')
  press_typed '\\'
  assert(vim.bo.filetype == 'neo-tree', 'Backslash did not reopen a closed tree')
  require('custom.files').show(mainbuf)
  press_typed '\\'
  assert(vim.bo.filetype ~= 'neo-tree', 'Backslash did not close a visible tree from the editor')
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'closing the tree lost the current file')
  press_typed '\\'
  assert(vim.bo.filetype == 'neo-tree', 'Backslash did not reopen a closed tree')
elseif case == 'recent_files' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf = open(main)
  local otherbuf = open(other)
  local thirdbuf = open(third)
  require('custom.files').show(mainbuf)
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == thirdbuf,
    'Ctrl+Tab did not select the most recently used other file: ' .. vim.inspect({ current = vim.api.nvim_get_current_buf(), expected = thirdbuf }))
  require('custom.files').show(mainbuf)
  press '<C-S-Tab>'
  assert(vim.api.nvim_get_current_buf() == otherbuf, 'Ctrl+Shift+Tab did not select the oldest file in recent order')
elseif case == 'add_file_from_editor' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf = open(main)
  assert(vim.api.nvim_get_current_buf() == mainbuf and vim.bo.filetype ~= 'neo-tree', 'file click did not leave the editor focused')
  local inputs = require('neo-tree.ui.inputs')
  local original_input = inputs.input
  local default_path
  inputs.input = function(_, default, callback)
    default_path = default
    callback('created-from-editor.txt')
  end
  press '<D-n>'
  inputs.input = original_input
  settle()
  assert(default_path ~= nil, 'Cmd+N did not open the tree add-file flow')
  assert(vim.uv.fs_stat(root .. '/created-from-editor.txt'), 'Cmd+N did not create a file beside the selected file')
else
  error('unknown navigation case: ' .. tostring(case))
end
assert(vim.v.errmsg == '', vim.v.errmsg)
vim.cmd 'qall!'
