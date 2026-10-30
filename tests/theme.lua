vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local theme = require 'custom.theme'
local case = vim.env.JVIM_TEST_CASE

local function contrast(fg, bg)
  local function luminance(color)
    local channels = { (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff }
    local function linear(value)
      value = value / 255
      if value <= 0.04045 then return value / 12.92 end
      return ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * linear(channels[1]) + 0.7152 * linear(channels[2]) + 0.0722 * linear(channels[3])
  end
  local a, b = luminance(fg), luminance(bg)
  if a < b then a, b = b, a end
  return (a + 0.05) / (b + 0.05)
end

local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function assert_text_contrast(name, fg, bg)
  local ratio = contrast(fg, bg)
  assert(ratio >= 4.5, string.format('%s contrast is %.2f:1, expected at least 4.5:1', name, ratio))
end

if case == 'default' then
  theme.setup()
  assert(vim.g.colors_name == 'jvim-charcoal', 'jvim startup theme is not jvim-charcoal')
elseif case == 'switch' then
  theme.setup()
  assert(theme.apply('dark-ubuntu'), 'could not apply dark-ubuntu')
  assert(vim.g.colors_name == 'dark-ubuntu', 'dark-ubuntu fallback was not applied')
  assert(theme.apply('jvim-charcoal'), 'could not restore jvim-charcoal')
  assert(vim.g.colors_name == 'jvim-charcoal', 'jvim-charcoal was not restored')
elseif case == 'invalid' then
  theme.setup()
  local before = highlight('Normal')
  local ok = theme.apply('missing-theme')
  assert(not ok, 'unknown theme was accepted')
  assert(vim.g.colors_name == 'jvim-charcoal', 'unknown theme changed colorscheme')
  assert(vim.deep_equal(before, highlight('Normal')), 'unknown theme changed Normal highlight')
elseif case == 'groups' then
  theme.setup()
  for _, name in ipairs {
    'Normal', 'NormalFloat', 'Cursor', 'CursorLine', 'Visual', 'MatchParen', 'JvimWord', 'JvimFoldButton',
    'Comment', 'String', 'Number', 'Function', 'Type', 'Keyword', 'Constant', 'DiagnosticError',
    'DiagnosticWarn', 'DiagnosticInfo', 'DiagnosticHint', 'Pmenu', 'PmenuSel', 'StatusLine', 'StatusLineNC',
    'NeoTreeNormal', 'NeoTreeDirectoryName', 'TelescopeResultsNormal', 'TelescopePromptNormal',
    'BlinkCmpMenu', 'BlinkCmpMenuSelection',
  } do
    assert(next(highlight(name)) ~= nil, name .. ' is not defined')
  end
elseif case == 'contrast' then
  theme.setup()
  local normal, cursor = highlight('Normal'), highlight('Cursor')
  assert_text_contrast('Normal', normal.fg, normal.bg)
  for _, name in ipairs { 'Comment', 'String', 'Number', 'Function', 'Type', 'Keyword', 'Constant', 'DiagnosticError', 'DiagnosticWarn', 'DiagnosticInfo', 'DiagnosticHint' } do
    assert_text_contrast(name, highlight(name).fg, normal.bg)
  end
  local visual = highlight('Visual')
  assert_text_contrast('Visual', normal.fg, visual.bg)
  assert_text_contrast('Cursor', cursor.fg, cursor.bg)
elseif case == 'picker_groups' then
  theme.setup()
  for _, name in ipairs { 'TelescopeResultsNormal', 'TelescopePromptNormal', 'TelescopeSelection', 'BlinkCmpMenu', 'BlinkCmpMenuSelection' } do
    local group = highlight(name)
    assert(group.fg and group.bg, name .. ' needs explicit foreground and background colors')
    assert_text_contrast(name, group.fg, group.bg)
  end
elseif case == 'action_entry' then
  local before = vim.api.nvim_get_keymap 'n'
  local entries = require('custom.action_picker').entries()
  local entry
  for _, item in ipairs(entries) do
    if item.name == 'Choose color theme' then entry = item; break end
  end
  assert(entry, 'theme action is missing from the action picker')
  assert(entry.shortcut == '', 'theme action unexpectedly has a shortcut')
  assert(entry.key == nil, 'theme action is dispatched as a key instead of a menu callback')
  assert(type(entry.action) == 'function', 'theme action has no menu callback')
  assert(vim.deep_equal(before, vim.api.nvim_get_keymap 'n'), 'building the theme action added a normal-mode keymap')
elseif case == 'picker_selection' then
  theme.setup()
  local select_callback
  package.loaded['telescope.pickers'] = {
    new = function(_, options)
      return {
        find = function()
          options.attach_mappings(1)
          assert(select_callback, 'theme picker did not register its select action')
          select_callback()
        end,
      }
    end,
  }
  package.loaded['telescope.finders'] = { new_table = function(options) return options end }
  package.loaded['telescope.actions'] = {
    select_default = { replace = function(_, callback) select_callback = callback end },
    close = function() end,
  }
  package.loaded['telescope.actions.state'] = {
    get_selected_entry = function() return { value = { name = 'dark-ubuntu' } } end,
  }
  package.loaded['telescope.config'] = { values = { generic_sorter = function() return {} end } }
  theme.pick()
  assert(vim.wait(1000, function() return vim.g.colors_name == 'dark-ubuntu' end), 'selecting Dark Ubuntu did not apply it')
else
  error('unknown theme test case: ' .. tostring(case))
end

assert(vim.v.errmsg == '', vim.v.errmsg)
vim.cmd 'qall!'
