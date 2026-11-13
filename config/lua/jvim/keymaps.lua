local map = vim.keymap.set
local settings = require('jvim.config').get()

-- Neovim's modeless mouse selection bypasses buffer-local <LeftMouse>
-- mappings. Open Neo-tree nodes after the mouse event has updated its row.
vim.on_key(function(_, typed)
  if typed == '' or vim.fn.keytrans(typed) ~= '<LeftMouse>' then return end
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or not vim.api.nvim_win_is_valid(mouse.winid) then return end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  if vim.bo[buf].filetype ~= 'neo-tree' then return end
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(mouse.winid) then return end
    local state = require('neo-tree.sources.manager').get_state 'filesystem'
    if not state or state.winid ~= mouse.winid or mouse.line < 1 or mouse.line > vim.api.nvim_buf_line_count(state.bufnr) then return end
    vim.api.nvim_set_current_win(mouse.winid)
    vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
    state.commands.open(state)
  end)
end, vim.api.nvim_create_namespace 'jvim-tree-single-click')

local selection = require 'jvim.selection'
local identifier_target = selection.target
local select_identifier = selection.select
local editing = require 'jvim.editing'

-- Familiar selection: Shift+arrows select; typing replaces the selection.
vim.o.keymodel = 'startsel,stopsel'
vim.o.selectmode = 'mouse,key'
vim.o.selection = 'exclusive'
vim.o.virtualedit = 'onemore'
vim.o.mouse = 'a'
vim.o.mousemodel = 'extend'
vim.o.scrolloff = 0
vim.o.sidescrolloff = 0
vim.o.wrap = false
vim.o.hidden = true
-- Let Insert/Replace-mode arrows cross line boundaries without changing the
-- wrapping behavior of Normal-mode motions.
vim.opt.whichwrap:append { ['<'] = true, ['>'] = true, ['['] = true, [']'] = true }

-- macOS trackpads report horizontal wheel direction as finger movement, while
-- Neovim's defaults move the viewport the opposite way. Keep content following
-- the gesture: swipe left reveals content to the right, and vice versa.
-- WezTerm already reports the natural direction and flags its focus in this file.
local wezterm_focused = vim.fn.expand '~/.local/state/jvim/wezterm-focused'
local function scroll_keys(toward_right)
  if vim.uv.fs_stat(wezterm_focused) then toward_right = not toward_right end
  return toward_right and '6zl' or '6zh'
end
for key, toward_right in pairs { ['<ScrollWheelLeft>'] = true, ['<ScrollWheelRight>'] = false } do
  map({ 'n', 'i' }, key, function()
    local win = vim.fn.getmousepos().winid
    if win == 0 or not vim.api.nvim_win_is_valid(win) then win = vim.api.nvim_get_current_win() end
    vim.api.nvim_win_call(win, function() vim.cmd.normal { args = { scroll_keys(toward_right) }, bang = true } end)
  end, { desc = 'Scroll horizontally' })
  map('x', key, function() return scroll_keys(toward_right) end, { expr = true, desc = 'Scroll horizontally' })
  -- :normal in Select mode types its keys over the selection, so scroll from Visual and switch back.
  map('s', key, function() return '<C-g>' .. scroll_keys(toward_right) .. '<C-g>' end, { expr = true, desc = 'Scroll horizontally' })
end

for key, target in pairs {
  ['<M-Left>'] = '<C-Left>',
  ['<M-b>'] = '<C-Left>',
  ['<M-Right>'] = '<C-Right>',
  ['<M-f>'] = '<C-Right>',
} do
  map({ 'n', 'i', 's' }, key, target)
end
map({ 'n', 'i', 's', 'x' }, '<M-S-Left>', function() return select_identifier(-1) end,
  { expr = true, replace_keycodes = true, desc = 'Select previous word' })
map({ 'n', 'i', 's', 'x' }, '<C-S-Left>', function() return select_identifier(-1) end,
  { expr = true, replace_keycodes = true, desc = 'Select previous word' })
map({ 'n', 'i', 's', 'x' }, '<M-S-Right>', function() return select_identifier(1) end,
  { expr = true, replace_keycodes = true, desc = 'Select next word' })
map({ 'n', 'i', 's', 'x' }, '<C-S-Right>', function() return select_identifier(1) end,
  { expr = true, replace_keycodes = true, desc = 'Select next word' })
map('i', '<M-BS>', '<C-S-w>', { desc = 'Delete previous word' })
map('i', '<M-d>', '<C-o>de', { desc = 'Delete next word' })
-- iTerm Natural Text Editing sends these for Command+Backspace/Left/Right.
map('i', '<C-u>', '<C-g>u<C-u>', { desc = 'Delete to line start' })
map({ 'n', 'i', 's' }, '<C-e>', '<End>')
-- Command+Right arrives as CSI 4~, which Neovim names Select; unmapped, Insert mode types "<Select>".
map({ 'n', 'i', 's' }, '<Select>', '<End>')

local function shortcut(key, normal, insert, select, visual, desc)
  for mode, rhs in pairs { n = normal, i = insert, s = select, x = visual } do
    map(mode, key, rhs, { desc = desc })
  end
end

-- Command+Left can arrive as Home, Find (CSI 1~), or Ctrl+A in Mac terminals,
-- or as a direct Command key in a GUI. All should stop after indentation.
-- On Windows and Linux Ctrl+A is select all, so it stays free for the translated Cmd+A.
local line_start_keys = { '<Home>', '<Find>', '<D-Left>' }
if vim.fn.has 'mac' == 1 then table.insert(line_start_keys, '<C-a>') end
for _, key in ipairs(line_start_keys) do
  shortcut(key, '^', '<C-o>^', '<C-g>^', '^', 'Move to first nonblank column')
end

-- F13-F37 and F35-prefixed sequences carry actions from the iTerm profile.
-- Direct Command mappings also work in GUIs that report the modifier.
for _, prefix in ipairs { 'D', 'C' } do
  shortcut('<' .. prefix .. '-c>', '"+yy', '<C-o>"+yy', '<C-g>"+ygv<C-g>', '"+ygv', 'Copy')
  shortcut('<' .. prefix .. '-x>', '"+ddi', '<C-o>"+dd', '<C-g>"+di', '"+di', 'Cut')
  shortcut('<' .. prefix .. '-v>', 'i<C-r><C-o>+', '<C-r><C-o>+', '<C-g>"_c<C-r><C-o>+', '"_c<C-r><C-o>+', 'Paste')
end
shortcut('<F13>', '"+yy', '<C-o>"+yy', '<C-g>"+ygv<C-g>', '"+ygv', 'Copy')
shortcut('<F14>', '"+ddi', '<C-o>"+dd', '<C-g>"+di', '"+di', 'Cut')
shortcut('<F15>', 'i<C-r><C-o>+', '<C-r><C-o>+', '<C-g>"_c<C-r><C-o>+', '"_c<C-r><C-o>+', 'Paste')
shortcut('<F25>', 'gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', 'Select all')
map({ 'n', 'i', 's', 'x' }, '<D-a>', '<Esc>gg0vG$<C-g>', { desc = 'Select all' })
-- iTerm sends Shift+Enter as the packaged F35 action 69. Open a line below
-- without replacing the current line, in both normal and editing modes.
shortcut('<F35>69', 'o', '<C-o>o', '<C-g><Esc>o', '<Esc>o', 'Insert line below')
-- Give modified arrows explicit iTerm transport codes so terminal escape
-- parsing cannot turn them into literal text.
shortcut('<F35>70', '^', '<C-o>^', '<C-g>^', '^', 'Move to first nonblank column')
shortcut('<F35>71', '<S-Left>', '<S-Left>', '<S-Left>', '<S-Left>', 'Select left')
shortcut('<F35>72', '<S-Right>', '<S-Right>', '<S-Right>', '<S-Right>', 'Select right')
shortcut('<F35>73', '<S-Up>', '<S-Up>', '<S-Up>', '<S-Up>', 'Select up')
shortcut('<F35>74', '<S-Down>', '<S-Down>', '<S-Down>', '<S-Down>', 'Select down')
map({ 'n', 'i', 's', 'x' }, '<F35>75', function() return select_identifier(-1) end,
  { expr = true, replace_keycodes = true, desc = 'Select previous word' })
map({ 'n', 'i', 's', 'x' }, '<F35>76', function() return select_identifier(1) end,
  { expr = true, replace_keycodes = true, desc = 'Select next word' })

map('c', '<F15>', '<C-r>+', { desc = 'Paste into command line' })
map('c', '<D-v>', '<C-r>+', { desc = 'Paste into command line' })
local close_terminal = '<C-\\><C-n><Cmd>lua require("jvim.command_terminal").hide()<CR>'
map('t', '<F20>', close_terminal, { desc = 'Close terminal pane' })
map('t', '<D-w>', close_terminal, { desc = 'Close terminal pane' })

local function action(keys, fn, desc)
  for _, key in ipairs(keys) do
    map({ 'n', 'i', 's', 'x' }, key, fn, { desc = desc })
  end
end
action({ '<F35>67', '<D-M-;>' }, function() require('jvim.command_terminal').open() end, 'Open terminal')
for _, key in ipairs { '<F35>68', '<D-n>' } do
  map({ 'n', 'i', 's', 'x' }, key, '<C-\\><C-n><Cmd>lua require("jvim.files").new_file()<CR>',
    { desc = 'New file in selected project folder' })
end
local function telescope(name)
  return function() require('jvim.pickers').open(name) end
end
local resume_editing = editing.resume
local undo_cursors = {}
local function undo()
  local buf = vim.api.nvim_get_current_buf()
  undo_cursors[buf] = undo_cursors[buf] or {}
  undo_cursors[buf][vim.fn.undotree().seq_cur] = vim.api.nvim_win_get_cursor(0)
  vim.cmd.undo()
end
local function redo()
  vim.cmd.redo()
  local positions = undo_cursors[vim.api.nvim_get_current_buf()] or {}
  local position = positions[vim.fn.undotree().seq_cur]
  if position then
    local row = math.min(position[1], vim.api.nvim_buf_line_count(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    vim.api.nvim_win_set_cursor(0, { row, math.min(position[2], #line) })
  end
end

action({ '<F16>', '<D-s>', '<C-s>' }, function()
  local function save()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].modified and vim.api.nvim_buf_get_name(buf) ~= '' then
        vim.api.nvim_buf_call(buf, function() vim.cmd 'write' end)
      end
    end
  end
  if vim.api.nvim_buf_get_name(0) == '' then
    local context = editing.capture()
    vim.ui.input({ prompt = 'Save as: ', completion = 'file' }, function(name)
      if name and name ~= '' then
        context:apply(function()
          vim.cmd('confirm saveas ' .. vim.fn.fnameescape(name))
          save()
        end)
      end
    end)
  else
    save()
  end
end, 'Save all')
action({ '<F17>', '<D-S-o>' }, telescope 'find_files', 'Find file')
action({ '<F18>', '<D-S-f>', '<C-S-f>' }, telescope 'live_grep', 'Search project')
action({ '<F19>', '<D-e>' }, telescope 'oldfiles', 'Recent files')
action({ '<F35>38', '<C-S-a>', '<D-S-a>' }, function() require('jvim.action_picker').open() end, 'Find action or shortcut')
vim.api.nvim_create_user_command('Shortcuts', function() require('jvim.action_picker').open() end, { desc = 'Find an editor action or shortcut' })
-- The message pager at the bottom closes first, wherever focus is.
local function close_popup()
  local ok, ui2 = pcall(require, 'vim._core.ui2')
  local pager = ok and ui2.wins and ui2.wins.pager
  if pager and vim.api.nvim_win_is_valid(pager) and not vim.api.nvim_win_get_config(pager).hide then
    return vim.api.nvim_win_close(pager, true) or true
  end
end
local function quit_or_hide_terminal()
  if not require('jvim.command_terminal').hide_visible() then vim.cmd 'confirm qall' end
end
action({ '<F20>', '<D-w>' }, function()
  if close_popup() then return end
  if vim.b.jvim_command_terminal then
    require('jvim.command_terminal').hide()
    return
  end
  if vim.t.jvim_changes then
    require('jvim.changes').close()
    return
  end
  if vim.bo.filetype == 'neo-tree' then
    if #require('jvim.files').editor_windows() == 0 then return quit_or_hide_terminal() end
    require('neo-tree.command').execute { action = 'close', position = 'left' }
    return
  end
  if vim.b.jvim_pdf_viewer then
    require('jvim.pdf_viewer').close(vim.api.nvim_get_current_buf())
    return
  end
  if settings.features.autosave then require('jvim.autosave').save_all() end
  if not require('jvim.files').close_current_tab() then quit_or_hide_terminal() end
end, 'Close file')
local function split(command)
  local files = require 'jvim.files'
  local editors = files.editor_windows()
  if #editors == 0 then return end
  if not vim.tbl_contains(editors, vim.api.nvim_get_current_win()) then vim.api.nvim_set_current_win(editors[1]) end
  local from_pdf = vim.b.jvim_pdf_viewer
  vim.cmd(command)
  -- One image can't render in two windows, so give the new pane an open text file.
  if from_pdf then
    local text_file = files.list()[1]
    if text_file then files.show(text_file) end
  end
end
action({ '<F35>78' }, function() split 'vsplit' end, 'Split right')
action({ '<F35>79' }, function() split 'split' end, 'Split down')
action({ '<F35>81' }, function() require('jvim.pop_out').open() end, 'Move file to a new window')
action({ '<F35>82' }, function() require('jvim.run').run_in_window() end, 'Run in a new window')
local function toggle_project_tree()
  local available, tree = pcall(require, 'neo-tree.command')
  if not available then vim.notify('The project tree requires Neo-tree; enable it through your plugin manager', vim.log.levels.WARN); return end
  local tree_open = vim.tbl_contains(
    vim.tbl_map(function(win) return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree' end, vim.api.nvim_tabpage_list_wins(0)),
    true
  )
  if tree_open then
    tree.execute { action = 'close', position = 'left' }
  else
    local name = vim.api.nvim_buf_get_name(0)
    tree.execute { action = 'focus', reveal = name ~= '' and vim.fn.isdirectory(name) == 0, reveal_force_cwd = true }
  end
end
action({ '<F4>' }, toggle_project_tree, 'Toggle project tree')
action({ '<F22>', '<S-F6>' }, function() require('jvim.rename').symbol() end, 'Rename symbol')
local function fix_spelling()
  if not vim.wo.spell then return false end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local first, last = col, col
  while first > 0 and line:sub(first, first):match "[%w']" do first = first - 1 end
  while last < #line and line:sub(last + 1, last + 1):match "[%w']" do last = last + 1 end
  local word = line:sub(first + 1, last)
  if word == '' or vim.fn.spellbadword(word)[1] == '' then return false end
  local choices = vim.fn.spellsuggest(word, 9)
  local add = 'Add "' .. word .. '" to dictionary'
  table.insert(choices, add)
  vim.ui.select(choices, { prompt = 'Spelling' }, function(choice)
    if choice == add then
      vim.cmd.spellgood(word)
    elseif choice then
      vim.api.nvim_buf_set_text(0, row - 1, first, row - 1, last, { choice })
    end
  end)
  return true
end
action({ '<F23>', '<M-CR>' }, function()
  if not fix_spelling() then vim.lsp.buf.code_action() end
end, 'Quick fix')
action({ '<F24>', '<C-M-l>', '<D-M-l>' }, function()
  local available, conform = pcall(require, 'conform')
  if available then conform.format { async = true, lsp_format = 'fallback' }
  else vim.lsp.buf.format { async = true } end
end, 'Format file')
action({ '<F26>', '<D-z>', '<C-z>' }, undo, 'Undo')
action({ '<F27>', '<D-S-z>' }, redo, 'Redo')
action({ '<F28>', '<D-d>' }, function()
  local mode = vim.fn.mode()
  if mode == 's' or mode == 'v' then
    local first, last = vim.fn.getpos 'v', vim.fn.getpos '.'
    local lines = vim.fn.getregion(first, last, { type = 'v', exclusive = true })
    if first[2] > last[2] or (first[2] == last[2] and first[3] > last[3]) then
      first, last = last, first
    end
    local row, col = last[2] - 1, last[3] - 1
    vim.cmd 'normal! \27'
    vim.api.nvim_buf_set_text(0, row, col, row, col, lines)
    vim.api.nvim_win_set_cursor(0, { row + 1, col })
    vim.cmd 'normal! v'
    vim.api.nvim_win_set_cursor(0, { row + #lines, #lines == 1 and col + #lines[1] or #lines[#lines] })
    vim.cmd 'normal! \7'
  else
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row, row, false, { vim.api.nvim_get_current_line() })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  end
end, 'Duplicate line or selection')
action({ '<F30>', '<D-f>', '<C-f>' }, telescope 'current_buffer_fuzzy_find', 'Find in file')
action({ '<F35>45', '<D-o>' }, telescope 'lsp_dynamic_workspace_symbols', 'Find class')
action({ '<F31>', '<D-b>', '<F12>' }, vim.lsp.buf.definition, 'Go to definition')
action({ '<F32>', '<M-F7>' }, telescope 'lsp_references', 'Find usages')
action({ '<F36>', '<C-Tab>' }, function() require('jvim.files').cycle(1) end, 'Next file')
action({ '<F37>', '<C-S-Tab>' }, function() require('jvim.files').cycle(-1) end, 'Previous file')
action({ '<F2>' }, function() vim.diagnostic.jump { count = 1, float = true } end, 'Next problem')
action({ '<S-F2>' }, function() vim.diagnostic.jump { count = -1, float = true } end, 'Previous problem')
-- Keep Option+arrows for word movement, as on macOS.
map('s', '<M-Left>', '<C-Left>')
map('s', '<M-Right>', '<C-Right>')
-- Like a Mac text field, word movement carries on past a line end to the neighbouring line.
local function word_motion(direction)
  map('n', direction > 0 and '<C-Right>' or '<C-Left>', function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local target = identifier_target(direction, false)
    local row = cursor[1] + direction
    if target == cursor[2] and row >= 1 and row <= vim.api.nvim_buf_line_count(0) then
      local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
      return vim.api.nvim_win_set_cursor(0, { row, direction > 0 and 0 or selection.previous(line, #line) })
    end
    vim.api.nvim_win_set_cursor(0, { cursor[1], target })
  end, { desc = direction > 0 and 'Move to next identifier' or 'Move to previous identifier' })
  map('i', direction > 0 and '<C-Right>' or '<C-Left>', function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local target = identifier_target(direction, true)
    local distance = selection.distance(vim.api.nvim_get_current_line(), target, cursor[2])
    if distance == 0 then
      local row = cursor[1] + direction
      if row < 1 or row > vim.api.nvim_buf_line_count(0) then return '' end
      return direction > 0 and '<Down><Home>' or '<Up><End>'
    end
    return '<C-o>' .. distance .. (target < cursor[2] and 'h' or 'l')
  end, { expr = true, replace_keycodes = true, desc = direction > 0 and 'Move to next identifier' or 'Move to previous identifier' })
end
word_motion(-1)
word_motion(1)
for key, target in pairs { ['<M-Left>'] = '<C-Left>', ['<M-Right>'] = '<C-Right>' } do
  map({ 'n', 'i' }, key, target, { remap = true })
end

for _, key in ipairs { '<C-_>', '<D-/>', '<F29>' } do
  map('n', key, 'gcc', { remap = true, desc = 'Toggle comment' })
  map('i', key, function() vim.cmd 'normal gcc' end, { desc = 'Toggle comment' })
  map('s', key, '<C-g>gc', { remap = true, desc = 'Toggle comment' })
  map('x', key, 'gc', { remap = true, desc = 'Toggle comment' })
end
map('n', '<M-S-Up>', '<cmd>move .-2<CR>==', { desc = 'Move line up' })
map('n', '<M-S-Down>', '<cmd>move .+1<CR>==', { desc = 'Move line down' })
map('i', '<M-S-Up>', '<Esc><cmd>move .-2<CR>==gi', { desc = 'Move line up' })
map('i', '<M-S-Down>', '<Esc><cmd>move .+1<CR>==gi', { desc = 'Move line down' })

action({ '<F35>35', '<D-S-t>' }, function() require('jvim.files').reopen_closed() end, 'Reopen closed file')
action({ '<F35>77', '<C-S-g>' }, function() require('jvim.changes').open() end, 'Show Git changes')
-- Terminals report Shift+F7 as F19 (Recent files), so WezTerm sends transport code 80 for it.
for keys, forward in pairs { [{ '<F7>' }] = true, [{ '<F35>80', '<S-F7>' }] = false } do
  action(keys, function()
    local changes = require 'jvim.changes'
    if changes.is_open() then return changes.jump(forward) end
    local ok, signs = pcall(require, 'gitsigns')
    if ok then signs.nav_hunk(forward and 'next' or 'prev') end
  end, forward and 'Next change' or 'Previous change')
end
vim.api.nvim_create_user_command('Changes', function() require('jvim.changes').open() end, { desc = 'Show Git changes' })

local group = vim.api.nvim_create_augroup('clion-editing', { clear = true })
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'FileType' }, {
  group = group,
  callback = function(args)
    local name = vim.fs.basename(vim.api.nvim_buf_get_name(args.buf)):lower()
    local wrap = vim.bo[args.buf].filetype == 'markdown' or name == 'readme' or name:match('^readme%.') ~= nil
    for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
      vim.wo[win].wrap = wrap
      vim.wo[win].linebreak = wrap
    end
  end,
})
vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = function() vim.schedule(resume_editing) end,
})
-- Wheel scrolling leaves Terminal mode; typing afterwards goes back to the shell instead of running Normal commands.
vim.on_key(function(_, typed)
  if not (typed:match('^[%g ]$') or typed == '\r') or vim.api.nvim_get_mode().mode ~= 'nt' or not editing.running_terminal() then return end
  local job = vim.b.terminal_job_id
  vim.schedule(function()
    vim.cmd.startinsert()
    vim.api.nvim_chan_send(job, typed)
  end)
  return ''
end, vim.api.nvim_create_namespace 'jvim-terminal-typing')
-- Bracketed paste should not replace the system clipboard with deleted text.
local original_paste = vim.paste
vim.paste = function(lines, phase)
  -- Bracketed paste bypasses on_key, so restore the edit point explicitly.
  require('jvim.scroll').resume()
  local clipboard = vim.o.clipboard
  vim.o.clipboard = ''
  local ok, result = pcall(original_paste, lines, phase)
  vim.o.clipboard = clipboard
  if not ok then error(result) end
  return result
end
require('jvim.scroll').setup()

require('jvim.files').setup(group, { tree = settings.features.project_tree, tabline = settings.ui.tabline })

require('jvim.clion_actions').setup(action, resume_editing)

require('jvim.herdr_host').setup()

require('jvim.definition_links').setup()

-- In the terminal, shortcuts behave like a Mac shell: paste and line editing go to the job, editor-wide
-- actions leave the terminal first, and every other code is swallowed so its digits never reach the shell.
local function send_to_job(bytes) return function() vim.api.nvim_chan_send(vim.bo.channel, bytes) end end
local terminal_keys = {
  [15] = { function() vim.api.nvim_paste(vim.fn.getreg '+', true, -1) end, 'Paste into terminal' },
  [26] = { send_to_job '\31', 'Undo shell edit' },
  [53] = { send_to_job '\21', 'Delete to line start' },
  [67] = { function() require('jvim.command_terminal').hide() end, 'Hide terminal' },
  [70] = { send_to_job '\1', 'Move to line start' },
}
local editor_wide = { [16] = true, [17] = true, [18] = true, [19] = true, [38] = true, [44] = true, [45] = true,
                      [63] = true, [68] = true, [77] = true, [78] = true, [79] = true }
for number = 13, 99 do
  local key = number <= 37 and number ~= 35 and ('<F' .. number .. '>') or ('<F35>' .. number)
  local terminal_key, editor = terminal_keys[number], vim.fn.maparg(key, 'n', false, true)
  if terminal_key then
    map('t', key, terminal_key[1], { desc = terminal_key[2] })
  elseif editor_wide[number] and editor.callback then
    map('t', key, function() vim.cmd.stopinsert(); editor.callback() end, { desc = editor.desc })
  elseif editor_wide[number] and editor.rhs then
    map('t', key, '<C-\\><C-n>' .. editor.rhs, { desc = editor.desc, remap = editor.noremap == 0 })
  elseif vim.fn.maparg(key, 't') == '' then
    map('t', key, '<Nop>', { desc = 'Ignore editor shortcut in terminal' })
  end
end

require('jvim.shortcut_transport').setup()

if settings.features.autosave then require('jvim.autosave').setup() end

require('jvim.windows_keys').setup()

require('jvim.swap_recovery').setup()

if settings.features.word_highlight then require('jvim.word_highlight').setup() end

if settings.ui.statusline and package.loaded['mini.statusline'] then require('jvim.fold_controls').setup(require('mini.statusline')) end
