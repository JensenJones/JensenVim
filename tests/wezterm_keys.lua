local linux = vim.env.JVIM_TEST_TRIPLE:find 'linux' ~= nil
local function equal(actual, expected, what)
  assert(vim.deep_equal(actual, expected), what .. ': ' .. vim.inspect { actual = actual, expected = expected })
end
package.preload.wezterm = function()
  return {
    target_triple = vim.env.JVIM_TEST_TRIPLE,
    home_dir = vim.env.HOME,
    action = setmetatable({}, { __index = function(_, name) return function(argument) return { name, argument } end end }),
    on = function() end,
    gui = { default_keys = function()
      return { { key = 'v', mods = 'SUPER', action = { 'PasteFrom', 'Clipboard' } }, { key = 'w', mods = 'CTRL|SHIFT', action = { 'CloseCurrentTab' } } }
    end },
    action_callback = function(callback) return callback end,
    run_child_process = function() return false end,
  }
end
local config = {}
dofile(vim.env.JVIM_TEST_MODULE).apply(config)

local bindings = {}
for _, binding in ipairs(config.keys) do
  local id = binding.key .. ' ' .. binding.mods
  assert(not bindings[id], 'bound twice: ' .. id)
  bindings[id] = binding.action
end
local function press(id, title, selection)
  local action = assert(bindings[id], 'not bound: ' .. id)
  local performed
  local window = {
    get_selection_text_for_pane = function() return selection or '' end,
    perform_action = function(_, chosen) performed = chosen end,
  }
  local pane = { get_foreground_process_name = function() return '/bin/zsh' end, get_title = function() return title end }
  action(window, pane)
  return performed
end
local function jvim(code) return { 'SendString', '\27[23;5~' .. code } end

local cmd = linux and 'CTRL' or 'CMD'
for id in pairs(bindings) do
  assert(not (linux and id:find 'CMD'), 'Cmd binding on Linux: ' .. id)
end
equal(press('w ' .. cmd, 'jvim .'), jvim(20), 'close tab in jvim')
-- Off the Mac, Ctrl+Backspace deletes a word and Alt+Backspace the line.
local line_mod, word_mod = linux and 'ALT' or 'CMD', linux and 'CTRL' or 'ALT'
equal(press('Backspace ' .. line_mod, 'jvim .'), jvim(53), 'delete line in jvim')
equal(press('Backspace ' .. word_mod, 'jvim .'), { 'SendString', '\27\127' }, 'delete word in jvim')
equal(press('Backspace ' .. line_mod, 'zsh'), { 'SendString', '\21' }, 'delete line in the shell')
equal(press('Backspace ' .. word_mod, 'zsh'), { 'SendString', '\27\127' }, 'delete word in the shell')
equal(press('v ' .. cmd, 'zsh'), { 'PasteFrom', 'Clipboard' }, 'paste in the shell')
equal(press('c ' .. cmd, 'zsh', 'picked'), { 'CopyTo', 'Clipboard' }, 'copy a selection')
equal(press('w ' .. cmd .. '|SHIFT', 'jvim .'), jvim(63), 'close others in jvim')
if linux then
  equal(press('w CTRL', 'zsh'), { 'SendKey', { key = 'w', mods = 'CTRL' } }, 'Ctrl+W in the shell')
  equal(press('c CTRL', 'zsh'), { 'SendKey', { key = 'c', mods = 'CTRL' } }, 'Ctrl+C interrupts without a selection')
  equal(press('w CTRL|SHIFT', 'zsh'), { 'CloseCurrentTab' }, 'WezTerm keeps its own Ctrl+Shift+W outside jvim')
  equal(press('LeftArrow CTRL', 'jvim .'), jvim(37), 'Ctrl+Left keeps its explicit meaning')
end
vim.cmd 'qall!'
