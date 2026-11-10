local M = {}

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
  table.insert(entries, { name = 'Open terminal', shortcut = 'Cmd+Option+;', key = '<F35>67' })
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
            ordinal = entry.name .. ' ' .. entry.shortcut,
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
