local wezterm = require 'wezterm'
local share = wezterm.target_triple:find 'windows' and os.getenv 'LOCALAPPDATA' .. '/JensenVim/wezterm'
  or wezterm.home_dir .. '/.local/share/jvim'
local jvim = share .. '/wezterm-config.lua'
wezterm.add_to_config_reload_watch_list(jvim)
-- Without jvim installed, WezTerm still starts with its defaults.
local loaded, config = pcall(dofile, jvim)
if not loaded then
  wezterm.log_error('jvim terminal settings not loaded: ' .. tostring(config))
  config = wezterm.config_builder()
end

-- Your own settings go here, for example: config.font_size = 13

return config
