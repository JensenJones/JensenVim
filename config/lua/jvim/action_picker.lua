local M = {}

-- Extra search words for actions whose names lack the word people type, e.g. "git" for merge conflicts.
local keywords = {
  { 'git', 'vcs version control' },
  { 'changes', 'git diff status commit vcs' },
  { 'merge', 'git conflict diff' },
  { 'conflict', 'git merge' },
  { 'run', 'build compile execute launch' },
  { 'terminal', 'shell console command line' },
  { 'theme', 'colour color scheme appearance' },
  { 'tree', 'files explorer sidebar' },
  { 'workspace', 'session layout restore quit exit' },
  { 'definition', 'goto jump navigate' },
  { 'rename', 'refactor' },
  { 'markdown', 'preview render' },
  { 'health', 'check diagnose doctor' },
  { 'personal jvim configuration', 'settings preferences options' },
  { 'fold', 'collapse expand' },
}

function M.search_text(entry)
  local name, words = entry.name:lower(), {}
  for _, rule in ipairs(keywords) do
    if name:find(rule[1], 1, true) then words[#words + 1] = rule[2] end
  end
  return table.concat({ entry.name, entry.shortcut, unpack(words) }, ' ')
end

local function gitsigns(method, ...)
  local args = { ... }
  return function()
    local ok, signs = pcall(require, 'gitsigns')
    if not ok then return vim.notify('Git line actions need gitsigns.nvim', vim.log.levels.WARN) end
    signs[method](unpack(args))
  end
end

local modifier_names = { C = 'Ctrl', S = 'Shift', M = 'Alt', A = 'Alt' }
-- Neovim reports Ctrl+J and Ctrl+[ by their control-character names.
local key_names = { BS = 'Backspace', CR = 'Enter', Bslash = '\\', Lt = '<', NL = 'Ctrl+J', Esc = 'Ctrl+[' }

-- The audit file lists macOS strokes. Elsewhere, label an action with the
-- keys that are really mapped to it (e.g. Ctrl+W instead of Cmd+W).
local function platform_shortcut(transport, fallback)
  if vim.fn.has 'mac' == 1 or not transport then return fallback end
  local target = vim.fn.maparg(transport, 'i', false, true)
  if vim.tbl_isempty(target) then return fallback end
  local transport_name = vim.fn.keytrans(vim.keycode(transport))
  local labels, seen = {}, {}
  for _, m in ipairs(vim.api.nvim_get_keymap 'i') do
    local same = (target.callback and m.callback == target.callback) or (not target.callback and target.rhs ~= '' and m.rhs == target.rhs)
      or (target.desc and m.desc == target.desc)
    local name = vim.fn.keytrans(vim.keycode(m.lhs))
    if same and name ~= transport_name and not name:find '>%d+$' and not name:find '[<%-]D%-' and not name:find '^<F3[0-9]>' then
      local parts, rest = {}, name
      if name:sub(1, 1) == '<' then
        rest = name:sub(2, -2)
        while rest:match '^[CSMA]%-.' do
          table.insert(parts, modifier_names[rest:sub(1, 1)])
          rest = rest:sub(3)
        end
      end
      table.insert(parts, key_names[rest] or (#rest == 1 and rest:upper()) or rest)
      local label = table.concat(parts, '+')
      if not seen[label] then seen[label] = true; table.insert(labels, label) end
    end
  end
  table.sort(labels, function(a, b) return #a < #b end)
  return table.concat(labels, ', ')
end

function M.entries()
  local path = vim.api.nvim_get_runtime_file('clion-keymap-audit.json', false)[1]
  local audit = path and vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) or { actions = {} }
  local entries = {}
  table.insert(entries, {
    name = 'Choose colour theme',
    shortcut = '',
    action = function() require('jvim.theme').pick() end,
  })
  table.insert(entries, {
    name = 'Check C++ project (syntax only)',
    shortcut = '',
    action = function() require('jvim.cpp_check').run() end,
  })
  table.insert(entries, { name = 'Save workspace and close editor (ask about unsaved files)', shortcut = 'Cmd+Shift+W', key = '<F35>63' })
  table.insert(entries, { name = 'New file in selected project folder', shortcut = 'Cmd+N', key = '<F35>68' })
  table.insert(entries, { name = 'Show Git changes', shortcut = 'Ctrl+Shift+G', key = '<F35>77' })
  for _, entry in ipairs {
    { 'Git: blame current line', gitsigns('blame_line', { full = true }) },
    { 'Git: toggle inline blame', gitsigns('toggle_current_line_blame') },
    { 'Git: preview change under cursor', gitsigns('preview_hunk') },
    { 'Git: revert change under cursor', gitsigns('reset_hunk') },
    { 'Git: stage change under cursor', gitsigns('stage_hunk') },
  } do
    table.insert(entries, { name = entry[1], shortcut = '', action = entry[2] })
  end
  table.insert(entries, { name = 'Git: next change', shortcut = 'F7', key = '<F7>' })
  table.insert(entries, { name = 'Git: previous change', shortcut = 'Shift+F7', key = '<F35>80' })
  table.insert(entries, { name = 'Open terminal', shortcut = 'Cmd+Option+;', key = '<F35>67' })
  table.insert(entries, { name = 'Split editor right', shortcut = '', key = '<F35>78' })
  table.insert(entries, { name = 'Split editor down', shortcut = '', key = '<F35>79' })
  table.insert(entries, { name = 'Toggle Markdown preview', shortcut = '', key = '<F35>65' })
  table.insert(entries, { name = 'Toggle Cmd-click code links (dashed underlines)', shortcut = '', key = '<F35>66' })
  for _, entry in ipairs {
    { 'Focus project tree', 'files', 'focus_tree' },
    { 'New folder in project tree', 'files', 'new_folder' },
    { 'Mark tree files for moving', 'files', 'cut' },
    { 'Move marked files into tree folder', 'files', 'paste' },
    { 'Run selected configuration', 'run', 'run' },
    { 'Choose run configuration', 'run', 'choose' },
    { 'Rerun selected configuration', 'run', 'rerun' },
    { 'Stop run', 'run', 'stop' },
    { 'Show run output', 'run', 'show' },
    { 'New run configuration', 'run', 'form' },
    { 'Edit run configurations file', 'run', 'edit' },
    { 'Resolve merge conflicts', 'merge', 'open' },
    { 'Accept ours for current conflict', 'merge', 'accept', 'ours' },
    { 'Accept theirs for current conflict', 'merge', 'accept', 'theirs' },
    { 'Accept both sides of current conflict', 'merge', 'accept', 'both' },
    { 'Accept base for current conflict', 'merge', 'accept', 'base' },
    { 'Next merge conflict', 'merge', 'navigate', 1 },
    { 'Previous merge conflict', 'merge', 'navigate', -1 },
    { 'Close merge resolver', 'merge', 'close' },
  } do
    table.insert(entries, { name = entry[1], shortcut = '', action = function() require('jvim.' .. entry[2])[entry[3]](entry[4]) end })
  end
  table.insert(entries, { name = 'Check jvim health', shortcut = '', action = function() vim.cmd 'checkhealth jvim' end })
  table.insert(entries, { name = 'Edit personal jvim configuration', shortcut = '', action = function()
    local personal = require('jvim.config').source()
    vim.fn.mkdir(vim.fs.dirname(personal), 'p')
    vim.cmd.edit(vim.fn.fnameescape(personal))
  end })
  for _, item in pairs(audit.actions) do
    local number = item.transport
    local key = (number < 35 or number == 36 or number == 37) and ('<F' .. number .. '>') or ('<F35>' .. number)
    local mapping = vim.fn.maparg(key, 'i', false, true)
    if mapping.desc and (mapping.callback or mapping.rhs) then
      local labels = vim.tbl_map(
        function(stroke) return stroke:gsub('meta', 'Cmd'):gsub('control', 'Ctrl'):gsub('alt', 'Option'):gsub('shift', 'Shift'):gsub(' ', '+') end,
        item.shortcuts
      )
      table.insert(entries, { name = mapping.desc, shortcut = table.concat(labels, ', '), key = key })
    end
  end
  for _, entry in ipairs(entries) do entry.shortcut = platform_shortcut(entry.key, entry.shortcut) end
  table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  return entries
end

function M.open()
  local entries = M.entries()
  local available = pcall(require, 'telescope.pickers')
  if not available then
    return vim.ui.select(entries, { prompt = 'jvim actions:', format_item = function(entry) return entry.name .. (entry.shortcut ~= '' and ('  ' .. entry.shortcut) or '') end }, function(entry)
      if not entry then return end
      if entry.action then entry.action() else vim.api.nvim_feedkeys(vim.keycode(entry.key), 'mi', false) end
    end)
  end
  local name_width = 0
  for _, entry in ipairs(entries) do
    name_width = math.max(name_width, vim.fn.strdisplaywidth(entry.name))
  end
  local display = require('telescope.pickers.entry_display').create {
    separator = '   ',
    items = { { width = name_width }, { remaining = true } },
  }
  local pickers, finders = require 'telescope.pickers', require 'telescope.finders'
  local actions, state = require 'telescope.actions', require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'jvim actions',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = function() return display { entry.name, { entry.shortcut, 'TelescopeResultsComment' } } end,
            ordinal = M.search_text(entry),
          }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(buf)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(buf)
          if entry then
            vim.schedule(function()
              if entry.value.action then
                entry.value.action()
              elseif entry.value.key then
                vim.api.nvim_feedkeys(vim.keycode(entry.value.key), 'm', false)
              end
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
