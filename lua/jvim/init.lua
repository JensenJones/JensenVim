-- Standard plugin entry point for a host Neovim configuration. The standalone
-- application's runtime stays under config/ for NVIM_APPNAME isolation.
local file = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(file)))
vim.opt.rtp:prepend(root .. '/config')
vim.opt.rtp:append(root .. '/config/after')
return dofile(root .. '/config/lua/jvim/init.lua')
