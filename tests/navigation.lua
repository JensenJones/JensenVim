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
require 'jvim.keymaps'
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
  press_typed '<F4>'
  assert(vim.bo.filetype ~= 'neo-tree', 'F4 did not close tree from Normal mode')
  press_typed '<F4>'
  assert(vim.bo.filetype == 'neo-tree', 'F4 did not reopen a closed tree')
  require('jvim.files').show(mainbuf)
  press_typed '<F4>'
  assert(vim.bo.filetype ~= 'neo-tree', 'F4 did not close a visible tree from the editor')
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'closing the tree lost the current file')
  press_typed '<F4>'
  assert(vim.bo.filetype == 'neo-tree', 'F4 did not reopen a closed tree')
elseif case == 'save_as_origin' then
  vim.cmd.enew()
  local origin = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(origin, 0, -1, false, { 'saved from origin' })
  local answer
  vim.ui.input = function(_, callback) answer = callback end
  press '<F16>'
  vim.cmd.edit(vim.fn.fnameescape(main))
  local other_buf = vim.api.nvim_get_current_buf()
  answer(root .. '/saved-origin.txt')
  assert(vim.api.nvim_get_current_buf() == other_buf, 'Save as changed the active file')
  assert(vim.api.nvim_buf_get_name(other_buf) == main, 'Save as renamed the wrong buffer')
  assert(vim.api.nvim_buf_get_name(origin) == root .. '/saved-origin.txt', 'Save as lost its origin')
  assert(vim.fn.readfile(root .. '/saved-origin.txt')[1] == 'saved from origin')
elseif case == 'new_header' then
  require('jvim.cpp_header').setup()
  vim.cmd.edit(vim.fn.fnameescape(root .. '/manual.hpp'))
  assert(vim.fn.getline(1) == '#pragma once', 'new .hpp buffer did not start with #pragma once')
elseif case == 'recent_files' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf = open(main)
  local otherbuf = open(other)
  local thirdbuf = open(third)
  require('jvim.files').show(mainbuf)
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == thirdbuf,
    'Ctrl+Tab did not select the most recently used other file: ' .. vim.inspect({ current = vim.api.nvim_get_current_buf(), expected = thirdbuf }))
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == otherbuf, 'repeated Ctrl+Tab did not continue through older recent files')
  require('jvim.files').show(mainbuf)
  press '<C-S-Tab>'
  assert(vim.api.nvim_get_current_buf() == thirdbuf, 'Ctrl+Shift+Tab did not move backward in the recent-file cycle')
elseif case == 'pane_local_file_cycling' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf, first_win = open(main)
  local otherbuf = open(other)
  assert(vim.api.nvim_get_current_win() == first_win, 'opening files did not reuse the first editor pane')
  require('jvim.files').show(mainbuf)
  vim.cmd.vsplit()
  local second_win = vim.api.nvim_get_current_win()
  focus_tree()
  local thirdbuf, opened_win = open(third)
  assert(opened_win == second_win, 'opening from the tree did not target the focused editor pane')
  local files = require('jvim.files')
  local first_bar, second_bar = files.render_winbar(first_win), files.render_winbar(second_win)
  assert(first_bar:find('other.txt', 1, true), 'first pane winbar did not show its local tab')
  assert(second_bar:find('third.txt', 1, true), 'second pane winbar did not show its local tab')
  vim.cmd.edit(root .. '/a_much_longer_file_name.txt')
  vim.o.columns = 240
  vim.api.nvim_win_set_width(second_win, 80)
  local rendered = vim.api.nvim_eval_statusline(files.render_winbar(second_win), { winid = second_win, use_winbar = true, highlights = true })
  local widths = {}
  for index, highlight in ipairs(rendered.highlights) do
    local stop = rendered.highlights[index + 1] and rendered.highlights[index + 1].start or #rendered.str
    if highlight.group ~= 'TabLineFill' then widths[#widths + 1] = vim.fn.strdisplaywidth(rendered.str:sub(highlight.start + 1, stop)) end
  end
  assert(#widths == 3 and widths[1] == widths[2] and widths[2] == widths[3], 'tabs differ in width: ' .. vim.inspect(widths))
  assert(rendered.highlights[#rendered.highlights].group == 'TabLineFill', 'the last tab colour runs to the edge of the pane')
  assert(rendered.width <= vim.api.nvim_win_get_width(second_win) and rendered.str:find('a_much_longer_file_na', 1, true),
    'tabs did not share the pane width: ' .. rendered.str)
  assert(files.close_current_tab(), 'closing the long-named tab failed')
  local click_target = tonumber(second_bar:match('%%(%d+)@'))
  files.click_tab(click_target)
  assert(vim.api.nvim_get_current_win() == second_win and vim.api.nvim_get_current_buf() == mainbuf,
    'clicking a tab did not switch the pane that owns it')
  assert(files.close_current_tab(), 'closing a pane-local tab failed')
  assert(vim.api.nvim_win_get_buf(first_win) == mainbuf and vim.api.nvim_buf_is_valid(mainbuf),
    'closing a shared tab removed the file from the other pane')
  assert(not vim.tbl_contains(files.pane_tabs(second_win), mainbuf), 'closed tab remained in the second pane')
  files.show(mainbuf, false, second_win)
  files.show(thirdbuf, false, second_win)
  vim.api.nvim_set_current_win(second_win)
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == mainbuf, 'second pane did not cycle only through its own files')
  assert(vim.api.nvim_win_get_buf(first_win) == mainbuf, 'cycling in the second pane changed the first pane')
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == thirdbuf, 'second pane cycle included a file from the first pane')
  assert(vim.api.nvim_win_get_buf(first_win) == mainbuf, 'second-pane cycle changed the first pane')
  vim.api.nvim_set_current_win(first_win)
  press '<C-Tab>'
  assert(vim.api.nvim_get_current_buf() == otherbuf, 'first pane did not cycle through its own files')
  assert(vim.api.nvim_win_get_buf(second_win) == thirdbuf, 'cycling in the first pane changed the second pane')
  assert(vim.api.nvim_buf_get_name(thirdbuf) == third, 'third file was not retained in the second pane tab set')
elseif case == 'last_tab_leaves_tree' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local files = require('jvim.files')
  local mainbuf, editor_win = open(main)
  vim.api.nvim_set_current_win(editor_win)
  assert(#files.pane_tabs(editor_win) == 1, 'expected a single open tab: ' .. vim.inspect(files.pane_tabs(editor_win)))
  assert(files.close_current_tab(), 'closing the last tab should keep jvim open')
  local wins = vim.tbl_filter(function(win) return vim.api.nvim_win_get_config(win).relative == '' end, vim.api.nvim_tabpage_list_wins(0))
  assert(#wins == 1 and vim.bo.filetype == 'neo-tree', 'closing the last tab did not leave only the tree')
  assert(not vim.api.nvim_buf_is_valid(mainbuf) or not vim.bo[mainbuf].buflisted, 'closed file stayed listed')
  assert(files.reopen_closed() and vim.api.nvim_buf_get_name(0) == main, 'Command+Shift+T did not reopen the last file')
  assert(vim.fn.win_screenpos(0)[2] > 1, 'reopened file did not open beside the tree')
elseif case == 'image_file_replacement' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local image, image_win = open(root .. '/preview.png')
  vim.bo[image].buftype = 'nowrite'
  vim.bo[image].filetype = 'image_nvim'
  focus_tree()
  local second_image, second_image_win = open(root .. '/preview-again.png')
  vim.bo[second_image].buftype = 'nowrite'
  vim.bo[second_image].filetype = 'image_nvim'
  assert(second_image_win == image_win, 'opening a second image preview created a new split')
  press '<D-w>'
  assert(vim.api.nvim_get_current_win() == image_win and vim.api.nvim_get_current_buf() == image,
    'Cmd+W exited jvim or closed every tab instead of closing the active image tab')
  focus_tree()
  second_image = open(root .. '/preview-again.png')
  vim.bo[second_image].buftype = 'nowrite'
  vim.bo[second_image].filetype = 'image_nvim'
  focus_tree()
  local text, text_win = open(main)
  assert(text_win == image_win, 'opening a text file after an image preview created a new split')
  assert(vim.api.nvim_get_current_win() == image_win and vim.api.nvim_get_current_buf() == text,
    'the text file did not replace the image in the existing pane')
  assert(#vim.api.nvim_list_wins() == 2, 'opening after an image preview changed the split count')
elseif case == 'add_file_from_editor' or case == 'add_file_closed_tree' then
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  settle()
  focus_tree()
  local mainbuf = open(main)
  assert(vim.api.nvim_get_current_buf() == mainbuf and vim.bo.filetype ~= 'neo-tree', 'file click did not leave the editor focused')
  if case == 'add_file_closed_tree' then require('neo-tree.command').execute { action = 'close', position = 'left' } end
  local inputs = require('neo-tree.ui.inputs')
  local original_input = inputs.input
  local default_path
  inputs.input = function(_, default, callback)
    default_path = default
    callback('created-from-editor.hpp')
  end
  press_typed '<D-n>'
  inputs.input = original_input
  settle()
  assert(default_path ~= nil, 'Cmd+N did not open the tree add-file flow')
  local header = root .. '/created-from-editor.hpp'
  assert(vim.uv.fs_stat(header), 'Cmd+N did not create a file beside the selected file')
  assert(vim.fn.readfile(header)[1] == '#pragma once', 'new .hpp file did not start with #pragma once')
else
  error('unknown navigation case: ' .. tostring(case))
end
assert(vim.v.errmsg == '', vim.v.errmsg)
vim.cmd 'qall!'
