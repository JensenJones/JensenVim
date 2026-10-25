local map = vim.keymap.set

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

for key, target in pairs {
  ['<M-Left>'] = '<C-Left>',
  ['<M-b>'] = '<C-Left>',
  ['<M-Right>'] = '<C-Right>',
  ['<M-f>'] = '<C-Right>',
  ['<M-S-Left>'] = '<C-S-Left>',
  ['<M-S-Right>'] = '<C-S-Right>',
} do
  map({ 'n', 'i', 's' }, key, target)
end
map('i', '<M-BS>', '<C-w>', { desc = 'Delete previous word' })
map('i', '<M-d>', '<C-o>de', { desc = 'Delete next word' })
-- iTerm Natural Text Editing sends these for Command+Backspace/Left/Right.
map('i', '<C-u>', '<C-g>u<C-u>', { desc = 'Delete to line start' })
map({ 'n', 'i', 's' }, '<C-a>', '<Home>')
map({ 'n', 'i', 's' }, '<C-e>', '<End>')

local function shortcut(key, normal, insert, select, visual, desc)
  for mode, rhs in pairs { n = normal, i = insert, s = select, x = visual } do
    map(mode, key, rhs, { desc = desc })
  end
end

-- F13-F37 and F35-prefixed sequences carry actions from the iTerm profile.
-- Direct Command mappings also work in GUIs that report the modifier.
for _, prefix in ipairs { 'D', 'C' } do
  shortcut('<' .. prefix .. '-c>', '"+yy', '<C-o>"+yy', '<C-g>"+ygv<C-g>', '"+ygv', 'Copy')
  shortcut('<' .. prefix .. '-x>', '"+ddi', '<C-o>"+dd', '<C-g>"+di', '"+di', 'Cut')
  shortcut('<' .. prefix .. '-v>', 'i<C-r><C-p>+', '<C-r><C-p>+', '<C-g>"_c<C-r><C-p>+', '"_c<C-r><C-p>+', 'Paste')
end
shortcut('<F13>', '"+yy', '<C-o>"+yy', '<C-g>"+ygv<C-g>', '"+ygv', 'Copy')
shortcut('<F14>', '"+ddi', '<C-o>"+dd', '<C-g>"+di', '"+di', 'Cut')
shortcut('<F15>', 'i<C-r><C-p>+', '<C-r><C-p>+', '<C-g>"_c<C-r><C-p>+', '"_c<C-r><C-p>+', 'Paste')
shortcut('<F25>', 'gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', '<Esc>gg0vG$<C-g>', 'Select all')
map({ 'n', 'i', 's', 'x' }, '<D-a>', '<Esc>gg0vG$<C-g>', { desc = 'Select all' })

map('c', '<F15>', '<C-r>+', { desc = 'Paste into command line' })
map('c', '<D-v>', '<C-r>+', { desc = 'Paste into command line' })

local function action(keys, fn, desc)
  for _, key in ipairs(keys) do
    map({ 'n', 'i', 's', 'x' }, key, fn, { desc = desc })
  end
end
local function telescope(name)
  return function() require('telescope.builtin')[name]() end
end
local function resume_editing()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype == 'neo-tree' then
    vim.cmd.stopinsert()
  elseif vim.bo[buf].buftype == '' and vim.bo[buf].modifiable and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 0 then
    vim.cmd.startinsert()
  end
end
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
    vim.ui.input({ prompt = 'Save as: ', completion = 'file' }, function(name)
      if name and name ~= '' then
        vim.cmd('confirm saveas ' .. vim.fn.fnameescape(name))
        save()
      end
    end)
  else
    save()
  end
end, 'Save all')
action({ '<F17>', '<D-S-o>' }, telescope 'find_files', 'Find file')
action({ '<F18>', '<D-S-f>', '<C-S-f>' }, telescope 'live_grep', 'Search project')
action({ '<F19>', '<D-e>' }, telescope 'oldfiles', 'Recent files')
action({ '<F35>38', '<C-S-a>', '<D-S-a>' }, function() require('custom.action_picker').open() end, 'Find action or shortcut')
vim.api.nvim_create_user_command('Shortcuts', function() require('custom.action_picker').open() end, { desc = 'Find an editor action or shortcut' })
local closed_files = {}
action({ '<F20>', '<D-w>' }, function()
  if vim.bo.filetype == 'neo-tree' then
    require('neo-tree.command').execute { action = 'close', position = 'left' }
    return
  end
  require('custom.autosave').save_all()
  local buf, name = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_name(0)
  local other_files = false
  for _, other in ipairs(vim.api.nvim_list_bufs()) do
    if other ~= buf and vim.bo[other].buflisted and vim.bo[other].buftype == ''
      and (vim.api.nvim_buf_get_name(other) ~= '' or vim.bo[other].modified) then
      other_files = true
      break
    end
  end
  if not other_files then
    vim.cmd 'confirm qall'
    return
  end
  vim.cmd 'confirm bdelete'
  if name ~= '' and not vim.api.nvim_buf_is_loaded(buf) then table.insert(closed_files, name) end
end, 'Close file')
action({ '<F21>', '<D-1>' }, function()
  local tree = require 'neo-tree.command'
  if vim.bo.filetype == 'neo-tree' then
    tree.execute { action = 'close', position = 'left' }
  else
    local name = vim.api.nvim_buf_get_name(0)
    tree.execute { action = 'focus', reveal = name ~= '' and vim.fn.isdirectory(name) == 0, reveal_force_cwd = true }
  end
end, 'Project files')
action({ '<F22>', '<S-F6>' }, vim.lsp.buf.rename, 'Rename symbol')
action({ '<F23>', '<M-CR>' }, vim.lsp.buf.code_action, 'Quick fix')
action({ '<F24>', '<C-M-l>', '<D-M-l>' }, function() require('conform').format { async = true, lsp_format = 'fallback' } end, 'Format file')
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
action({ '<F36>', '<C-Tab>' }, function() vim.cmd 'bnext' end, 'Next file')
action({ '<F37>', '<C-S-Tab>' }, function() vim.cmd 'bprevious' end, 'Previous file')
action({ '<F2>' }, function() vim.diagnostic.jump { count = 1, float = true } end, 'Next problem')
action({ '<S-F2>' }, function() vim.diagnostic.jump { count = -1, float = true } end, 'Previous problem')
-- Keep Option+arrows for word movement, as on macOS.
map('i', '<M-Left>', '<C-Left>')
map('i', '<M-Right>', '<C-Right>')
map('s', '<M-Left>', '<C-Left>')
map('s', '<M-Right>', '<C-Right>')

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

action({ '<F35>35', '<D-S-t>' }, function()
  local name = table.remove(closed_files)
  if name then vim.cmd.edit(vim.fn.fnameescape(name)) end
end, 'Reopen closed file')

local group = vim.api.nvim_create_augroup('clion-editing', { clear = true })
vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'WinEnter' }, {
  group = group,
  callback = function() vim.schedule(resume_editing) end,
})
-- Bracketed paste should not replace the system clipboard with deleted text.
local original_paste = vim.paste
vim.paste = function(lines, phase)
  local clipboard = vim.o.clipboard
  vim.o.clipboard = ''
  local ok, result = pcall(original_paste, lines, phase)
  vim.o.clipboard = clipboard
  if not ok then error(result) end
  return result
end
require('custom.scroll').setup()

-- Start with a project sidebar without taking focus away from the editor.
vim.api.nvim_create_autocmd('VimEnter', {
  group = group,
  callback = function()
    if #vim.api.nvim_list_uis() == 0 or vim.fn.argc() > 1 then return end
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= '' and vim.fn.isdirectory(name) == 1 then return end
    vim.schedule(function()
      local root = name ~= ''
          and (vim.fs.root(name, { '.git', 'CMakeLists.txt', 'compile_commands.json', 'compile_flags.txt', 'package.json', 'pyproject.toml' }) or vim.fs.dirname(
            name
          ))
        or vim.fn.getcwd()
      require('neo-tree.command').execute { action = 'show', position = 'left', dir = root, reveal = name ~= '', reveal_force_cwd = true }
      resume_editing()
    end)
  end,
})

require('custom.clion_actions').setup(action, resume_editing)

require('custom.tree_mouse').setup()

require('custom.herdr_host').setup()

require('custom.definition_links').setup()

require('custom.shortcut_transport').setup()

require('custom.autosave').setup()

require('custom.windows_keys').setup()
