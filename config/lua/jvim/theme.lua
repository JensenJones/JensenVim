local M = {}

local themes = {
  { name = 'jvim-charcoal', label = 'Gangster Jvim (default)' },
  { name = 'jvim-neon-dusk', label = 'Neon Dusk (synthwave midnight)' },
  { name = 'jvim-ember', label = 'Ember (warm fire on charcoal)' },
  { name = 'jvim-aurora', label = 'Aurora (polar night, northern lights)' },
  { name = 'jvim-blood-moon', label = 'Blood Moon (crimson on black, high contrast)' },
  { name = 'dark-ubuntu', label = 'Dark Ubuntu (previous)' },
  { name = 'habamax', label = 'Habamax' },
  { name = 'slate', label = 'Slate' },
  { name = 'desert', label = 'Desert' },
  { name = 'morning', label = 'Morning' },
}

local allowed = {}
for _, theme in ipairs(themes) do allowed[theme.name] = true end

local focus_groups = {
  ['jvim-charcoal'] = {
    Cursor = { fg = '#202126', bg = '#e6cc00', bold = true },
    lCursor = { fg = '#202126', bg = '#e6cc00', bold = true },
    Visual = { fg = '#d6d6d8', bg = '#454957' },
    MatchParen = { underline = true, sp = '#69a9df', bold = true },
    JvimWord = { underline = true, sp = '#e6cc00' },
    JvimFoldButton = { fg = '#69a9df', bold = true },
  },
  ['dark-ubuntu'] = {
    Cursor = { fg = '#252321', bg = '#66d9ef', bold = true },
    lCursor = { fg = '#252321', bg = '#66d9ef', bold = true },
    Visual = { bg = '#b05332' },
    MatchParen = { underline = true, sp = '#66d9ef', bold = true },
    JvimWord = { underline = true, sp = '#d9a343' },
    JvimFoldButton = { fg = '#66d9ef', bold = true },
  },
}

local default_rainbow = { yellow = '#e6cc00', blue = '#69a9df', violet = '#c17cbf', cyan = '#56b8df', orange = '#d28e76', green = '#95b86d', red = '#e88a85' }

local function apply_focus(name)
  local rainbow = require('jvim.palette').rainbow[name] or default_rainbow
  for colour, value in pairs(rainbow) do
    vim.api.nvim_set_hl(0, 'RainbowDelimiter' .. colour:sub(1, 1):upper() .. colour:sub(2), { fg = value })
  end
  for group, spec in pairs(focus_groups[name] or {}) do
    vim.api.nvim_set_hl(0, group, spec)
  end
  local selected = vim.api.nvim_get_hl(0, { name = 'TabLineSel', link = false })
  local tabs = vim.api.nvim_get_hl(0, { name = 'TabLine', link = false })
  vim.api.nvim_set_hl(0, 'JvimTabLineSelNC', { fg = selected.bg or selected.fg, bg = tabs.bg, bold = true, underline = true })
end

function M.names()
  return vim.deepcopy(themes)
end

function M.apply(name)
  if not allowed[name] then return false, ('Unsupported jvim theme: %s'):format(tostring(name)) end
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then return false, err end
  apply_focus(name)
  local path = vim.fn.stdpath('state') .. '/jvim/theme'
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local file, write_err = io.open(path, 'w')
  if file then file:write(name .. '\n'); file:close()
  else vim.notify('Could not save colour theme: ' .. tostring(write_err), vim.log.levels.WARN) end
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimThemeFocus', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function(args) apply_focus(args.match) end,
  })
  local path = vim.fn.stdpath('state') .. '/jvim/theme'
  local file = io.open(path, 'r')
  local saved = file and file:read('*l')
  if file then file:close() end
  if not allowed[saved] then saved = 'jvim-charcoal' end
  local ok = M.apply(saved)
  if not ok then return M.apply('jvim-charcoal') end
  return true
end

function M.pick()
  -- Cancel a pending modeless startinsert from returning to the editor.
  -- Telescope queues its own append command to enter its new prompt; an
  -- outstanding startinsert would turn that command into a literal 'A'.
  vim.cmd.stopinsert()
  local available, pickers = pcall(require, 'telescope.pickers')
  if not available then
    return vim.ui.select(M.names(), { prompt = 'Choose colour theme:', format_item = function(theme) return theme.label end }, function(theme)
      if theme then
        local ok, err = M.apply(theme.name)
        if not ok then vim.notify(err, vim.log.levels.ERROR) end
      end
    end)
  end
  local finders = require 'telescope.finders'
  local actions, state = require 'telescope.actions', require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'jvim colour theme',
      finder = finders.new_table {
        results = M.names(),
        entry_maker = function(theme)
          return { value = theme, display = theme.label, ordinal = theme.label }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(buf)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(buf)
          if entry then
            vim.schedule(function()
              local ok, err = M.apply(entry.value.name)
              if not ok then vim.notify(err, vim.log.levels.ERROR) end
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
