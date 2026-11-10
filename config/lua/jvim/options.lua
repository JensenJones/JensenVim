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
  -- Hide the empty command row; ui2 shows messages in a popup so cmdheight=0 never asks to press Enter.
  local has_ui2, ui2 = pcall(require, 'vim._core.ui2')
  if has_ui2 then
    ui2.enable { msg = { targets = 'msg' } }
    vim.o.cmdheight = 0
  end
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
  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
    group = vim.api.nvim_create_augroup('jvim-diagnostic-float', { clear = true }),
    callback = function() vim.diagnostic.open_float { scope = 'line', focus = false } end,
  })
  -- Thesis chapters pulled in with \input have no \documentclass, so Neovim would guess plain TeX.
  vim.g.tex_flavor = 'latex'
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('jvim-spell', { clear = true }),
    pattern = { 'tex', 'plaintex', 'bib', 'markdown', 'text', 'gitcommit' },
    callback = function()
      vim.opt_local.spell = true
      vim.opt_local.spelllang = 'en_gb'
    end,
  })
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = vim.api.nvim_create_augroup('jvim-yank', { clear = true }),
    callback = function() vim.hl.on_yank() end,
  })
end

return M
