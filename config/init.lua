-- Standalone entry point. Company configurations can call require('jvim').setup()
-- after adding this config directory to runtimepath; see docs/CONFIGURATION.md.
local root = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. '/after')
require('jvim').setup { mode = 'standalone' }
