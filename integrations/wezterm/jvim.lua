-- jvim keys for WezTerm. Load from ~/.wezterm.lua:
--   dofile(wezterm.home_dir .. '/.local/share/jvim/wezterm.lua').apply(config)
local wezterm = require 'wezterm'
local act = wezterm.action
local M = {}

-- { key, mods, bytes sent while jvim is focused }; jvim reads ESC[23;5~NN as <F35>NN.
M.keys = {
  { 'Backspace', 'ALT', '\x1b\x7f' },
  { 'Delete', 'ALT', '\x1bd' },
  { 'DownArrow', 'ALT', '\x1b[23;5~50' },
  { 'Enter', 'ALT', '\x1b[23;5~23' },
  { 'F7', 'ALT', '\x1b[23;5~32' },
  { 'LeftArrow', 'ALT', '\x1b[1;5D' },
  { 'RightArrow', 'ALT', '\x1b[1;5C' },
  { 'UpArrow', 'ALT', '\x1b[23;5~49' },
  { 'Backspace', 'ALT|SHIFT', '\x1b[23;5~27' },
  { 'DownArrow', 'ALT|SHIFT', '\x1b[23;5~52' },
  { 'LeftArrow', 'ALT|SHIFT', '\x1b[1;4D' },
  { 'RightArrow', 'ALT|SHIFT', '\x1b[1;4C' },
  { 'UpArrow', 'ALT|SHIFT', '\x1b[23;5~51' },
  { '/', 'CMD', '\x1b[23;5~29' },
  { 'Backspace', 'CMD', '\x1b[23;5~53' },
  { 'DownArrow', 'CMD', '\x1b[1;5F' },
  { 'F12', 'CMD', '\x1b[23;5~43' },
  { 'LeftArrow', 'CMD', '\x1b[23;5~70' },
  { 'RightArrow', 'CMD', '\x1b[4~' },
  { 'UpArrow', 'CMD', '\x1b[1;5H' },
  { '[', 'CMD', '\x1b[23;5~33' },
  { ']', 'CMD', '\x1b[23;5~34' },
  { 'a', 'CMD', '\x1b[23;5~25' },
  { 'b', 'CMD', '\x1b[23;5~31' },
  { 'c', 'CMD', '\x1b[23;5~13' },
  { 'd', 'CMD', '\x1b[23;5~28' },
  { 'e', 'CMD', '\x1b[23;5~19' },
  { 'f', 'CMD', '\x1b[23;5~30' },
  { 'g', 'CMD', '\x1b[23;5~56' },
  { 'l', 'CMD', '\x1b[23;5~46' },
  { 'n', 'CMD', '\x1b[23;5~68' },
  { 'o', 'CMD', '\x1b[23;5~45' },
  { 'p', 'CMD', '\x1b[23;5~42' },
  { 'r', 'CMD', '\x1b[23;5~47' },
  { 's', 'CMD', '\x1b[23;5~16' },
  { 'v', 'CMD', '\x1b[23;5~15' },
  { 'w', 'CMD', '\x1b[23;5~20' },
  { 'x', 'CMD', '\x1b[23;5~14' },
  { 'z', 'CMD', '\x1b[23;5~26' },
  { '-', 'CMD|ALT', '\x1b[23;5~58' },
  { ';', 'CMD|ALT', '\x1b[23;5~67' },
  { '=', 'CMD|ALT', '\x1b[23;5~59' },
  { 'LeftArrow', 'CMD|ALT', '\x1b[23;5~33' },
  { 'RightArrow', 'CMD|ALT', '\x1b[23;5~34' },
  { 'b', 'CMD|ALT', '\x1b[23;5~39' },
  { 'l', 'CMD|ALT', '\x1b[23;5~24' },
  { 'o', 'CMD|ALT', '\x1b[23;5~44' },
  { 'Backspace', 'CMD|SHIFT', '\x1b[23;5~61' },
  { 'DownArrow', 'CMD|SHIFT', '\x1b[1;6F' },
  { 'LeftArrow', 'CMD|SHIFT', '\x1b[1;2H' },
  { 'RightArrow', 'CMD|SHIFT', '\x1b[1;2F' },
  { 'UpArrow', 'CMD|SHIFT', '\x1b[1;6H' },
  { '[', 'CMD|SHIFT', '\x1b[23;5~37' },
  { ']', 'CMD|SHIFT', '\x1b[23;5~36' },
  { 'a', 'CMD|SHIFT', '\x1b[23;5~38' },
  { 'b', 'CMD|SHIFT', '\x1b[23;5~40' },
  { 'e', 'CMD|SHIFT', '\x1b[23;5~62' },
  { 'f', 'CMD|SHIFT', '\x1b[23;5~18' },
  { 'g', 'CMD|SHIFT', '\x1b[23;5~57' },
  { 'o', 'CMD|SHIFT', '\x1b[23;5~17' },
  { 'r', 'CMD|SHIFT', '\x1b[23;5~48' },
  { 't', 'CMD|SHIFT', '\x1b[23;5~35' },
  { 'w', 'CMD|SHIFT', '\x1b[23;5~63' },
  { 'z', 'CMD|SHIFT', '\x1b[23;5~27' },
  { 'LeftArrow', 'CTRL', '\x1b[23;5~37' },
  { 'RightArrow', 'CTRL', '\x1b[23;5~36' },
  { 'Tab', 'CTRL', '\x1b[23;5~36' },
  { 'j', 'CTRL', '\x1b[23;5~41' },
  { 'l', 'CTRL', '\x1b[23;5~56' },
  { 'm', 'CTRL', '\x1b[23;5~60' },
  { 'Tab', 'CTRL|SHIFT', '\x1b[23;5~37' },
  { 'a', 'CTRL|SHIFT', '\x1b[23;5~38' },
  { 'b', 'CTRL|SHIFT', '\x1b[23;5~40' },
  { 'l', 'CTRL|SHIFT', '\x1b[23;5~57' },
  { 'Delete', 'NONE', '\x1b[3~' },
  { 'F1', 'NONE', '\x1b[23;5~41' },
  { 'F12', 'NONE', '\x1b[23;5~31' },
  { 'F2', 'NONE', '\x1b[23;5~54' },
  { 'F3', 'NONE', '\x1b[23;5~56' },
  { 'Delete', 'SHIFT', '\x1b[23;5~14' },
  { 'DownArrow', 'SHIFT', '\x1b[23;5~74' },
  { 'Enter', 'SHIFT', '\x1b[23;5~69' },
  { 'F2', 'SHIFT', '\x1b[23;5~55' },
  { 'F3', 'SHIFT', '\x1b[23;5~57' },
  { 'F6', 'SHIFT', '\x1b[23;5~22' },
  { 'LeftArrow', 'SHIFT', '\x1b[1;2D' },
  { 'RightArrow', 'SHIFT', '\x1b[1;2C' },
  { 'UpArrow', 'SHIFT', '\x1b[23;5~73' },
  { '\\', 'CMD', '\x1b[23;5~78' },
  { '\\', 'CMD|SHIFT', '\x1b[23;5~79' },
  { '|', 'CMD|SHIFT', '\x1b[23;5~79' },
}

-- Like iTerm2: when the clipboard holds only an image, save it and paste its path instead.
local function clipboard_image_path()
  local ok, text = wezterm.run_child_process { '/usr/bin/pbpaste' }
  if ok and text ~= '' then return nil end
  local file = '/tmp/wezterm-clipboard-' .. os.time() .. '.png'
  local saved = wezterm.run_child_process {
    '/usr/bin/osascript',
    '-e', 'set f to open for access POSIX file "' .. file .. '" with write permission',
    '-e', 'write (the clipboard as «class PNGf») to f',
    '-e', 'close access f',
  }
  return saved and file or nil
end

local function jvim_focused(pane)
  if pane:get_foreground_process_name():match '[^/]*$' ~= 'herdr' then
    return pane:get_title():match '^jvim' ~= nil
  end
  local ok, stdout = wezterm.run_child_process { '/opt/homebrew/bin/herdr', 'pane', 'list' }
  if not ok then return false end
  for _, herdr_pane in ipairs(wezterm.json_parse(stdout).result.panes) do
    if herdr_pane.focused then return herdr_pane.terminal_title:match '^jvim' ~= nil end
  end
  return false
end

local function binding_id(key, mods)
  local names = {}
  for name in mods:gmatch '[^|]+' do
    table.insert(names, name == 'CMD' and 'SUPER' or name)
  end
  table.sort(names)
  return key:gsub('^mapped:', '') .. ':' .. table.concat(names, '|')
end

function M.apply(config)
  config.keys = config.keys or {}
  -- jvim reverses horizontal scrolling for iTerm2 unless this file exists.
  local focus_flag = wezterm.home_dir .. '/.local/state/jvim/wezterm-focused'
  wezterm.on('window-focus-changed', function()
    for _, gui_window in ipairs(wezterm.gui.gui_windows()) do
      if gui_window:is_focused() then
        local file = io.open(focus_flag, 'w')
        if file then file:close() end
        return
      end
    end
    os.remove(focus_flag)
  end)

  local defaults = {}
  for _, binding in ipairs(wezterm.gui.default_keys()) do
    defaults[binding_id(binding.key, binding.mods)] = binding.action
  end

  for _, entry in ipairs(M.keys) do
    local key, mods, bytes = entry[1], entry[2], entry[3]
    local fallback = defaults[binding_id(key, mods)] or act.SendKey { key = key, mods = mods }
    table.insert(config.keys, {
      key = key,
      mods = mods,
      action = wezterm.action_callback(function(window, pane)
        if key == 'c' and mods == 'CMD' and window:get_selection_text_for_pane(pane) ~= '' then
          return window:perform_action(act.CopyTo 'Clipboard', pane)
        end
        local focused = jvim_focused(pane)
        local image = not focused and key == 'v' and mods == 'CMD' and clipboard_image_path()
        if image then return pane:send_paste(image) end
        window:perform_action(focused and act.SendString(bytes) or fallback, pane)
      end),
    })
  end
end

return M
