-- jvim's WezTerm setup for macOS, Linux and Windows. ~/.wezterm.lua loads it, then adds personal settings.
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local share = wezterm.target_triple:find 'windows' and os.getenv 'LOCALAPPDATA' .. '/JensenVim/wezterm'
  or wezterm.home_dir .. '/.local/share/jvim'

local keys = share .. '/wezterm.lua'
wezterm.add_to_config_reload_watch_list(keys)
local loaded, module = pcall(dofile, keys)
if loaded then module.apply(config) else wezterm.log_error('jvim keys not loaded: ' .. tostring(module)) end

config.enable_kitty_graphics = true
-- WezTerm ships JetBrains Mono and Nerd Font symbols, so a fresh machine needs no font installs.
config.font = wezterm.font 'JetBrains Mono'
config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }
config.font_size = 12
config.window_padding = { left = 4, right = 4, top = 0, bottom = 0 }
return config
