local M = {}

function M.open()
  local audit = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath 'config' .. '/clion-keymap-audit.json'), '\n'))
  local entries = {}
  table.insert(entries, { name = 'Close editor (ask about unsaved files)', shortcut = 'Cmd+Shift+W', key = '<F35>63' })
  table.insert(entries, { name = 'Toggle Markdown preview', shortcut = '', key = '<F35>65' })
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
          if entry then vim.schedule(function() vim.api.nvim_feedkeys(vim.keycode(entry.value.key), 'm', false) end) end
        end)
        return true
      end,
    })
    :find()
end

return M
