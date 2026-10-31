local M = {}

local themes = {
  { name = 'jvim-charcoal', label = 'CoderPad-inspired (default)' },
  { name = 'dark-ubuntu', label = 'Dark Ubuntu (previous)' },
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

local function apply_focus(name)
  for group, colour in pairs {
    RainbowDelimiterYellow = '#e6cc00',
    RainbowDelimiterBlue = '#69a9df',
    RainbowDelimiterViolet = '#c17cbf',
    RainbowDelimiterCyan = '#56b8df',
    RainbowDelimiterOrange = '#d28e76',
    RainbowDelimiterGreen = '#95b86d',
    RainbowDelimiterRed = '#e88a85',
  } do
    vim.api.nvim_set_hl(0, group, { fg = colour })
  end
  for group, spec in pairs(focus_groups[name] or {}) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

function M.names()
  return vim.deepcopy(themes)
end

function M.apply(name)
  if not allowed[name] then return false, ('Unsupported jvim theme: %s'):format(tostring(name)) end
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then return false, err end
  apply_focus(name)
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimThemeFocus', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function(args) apply_focus(args.match) end,
  })
  return M.apply('jvim-charcoal')
end

function M.pick()
  local pickers, finders = require 'telescope.pickers', require 'telescope.finders'
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
