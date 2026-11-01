local M = {}

function M.setup()
  vim.g.mapleader = vim.g.mapleader or ' '
  vim.g.maplocalleader = vim.g.maplocalleader or ' '
  vim.g.have_nerd_font = require('jvim.config').get().ui.icons
  for option, value in pairs {
    number = true, mouse = 'a', showmode = false, breakindent = true,
    undofile = true, ignorecase = true, smartcase = true, signcolumn = 'yes',
    updatetime = 250, timeoutlen = 300, splitright = true, splitbelow = true,
    list = true, inccommand = 'split', cursorline = true, confirm = true,
    termguicolors = true,
  } do vim.o[option] = value end
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
  vim.schedule(function() vim.o.clipboard = 'unnamedplus' end)
  vim.diagnostic.config {
    update_in_insert = true,
    severity_sort = true,
    underline = true,
    float = { border = 'rounded', source = true },
    virtual_text = { spacing = 2, prefix = '●' },
    signs = { text = {
      [vim.diagnostic.severity.ERROR] = '✘', [vim.diagnostic.severity.WARN] = '▲',
      [vim.diagnostic.severity.INFO] = '●', [vim.diagnostic.severity.HINT] = '⚑',
    } },
    jump = { float = true },
  }
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = vim.api.nvim_create_augroup('jvim-yank', { clear = true }),
    callback = function() vim.hl.on_yank() end,
  })
end

return M
