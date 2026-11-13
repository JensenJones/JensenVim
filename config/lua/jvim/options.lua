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
  -- Diagnostic details open on a click: on the sign beside the line number or the message after the line
  -- shows the whole line's diagnostics, on the underlined text the ones under it. Resting the cursor does nothing.
  vim.on_key(function(_, typed)
    if typed == '' or vim.fn.keytrans(typed) ~= '<LeftRelease>' then return end
    vim.schedule(function()
      local mouse = vim.fn.getmousepos()
      if mouse.winid == 0 or mouse.line == 0 or not vim.api.nvim_win_is_valid(mouse.winid) then return end
      if vim.fn.mode():find '^[vVsS\22\19]' then return end
      local buf = vim.api.nvim_win_get_buf(mouse.winid)
      local info = vim.fn.getwininfo(mouse.winid)[1]
      local text = vim.api.nvim_buf_get_lines(buf, mouse.line - 1, mouse.line, false)[1] or ''
      local gutter = mouse.wincol <= info.textoff
      local after_line = not gutter and mouse.column > #text
      vim.api.nvim_win_call(mouse.winid, function()
        vim.diagnostic.open_float {
          bufnr = buf, focus = false, scope = (gutter or after_line) and 'line' or 'cursor',
          pos = { mouse.line - 1, math.max(mouse.column - 1, 0) },
        }
      end)
    end)
  end, vim.api.nvim_create_namespace 'jvim-diagnostic-click')
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
