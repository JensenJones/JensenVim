local M = {}
local started = false

local function callback(fn, label, opts)
  if not fn then return end
  local ok, err = pcall(fn, vim.deepcopy(opts))
  if not ok then vim.notify('jvim ' .. label .. ': ' .. tostring(err), vim.log.levels.ERROR) end
end

function M.setup(overrides)
  if started then return M end
  assert(vim.fn.has('nvim-0.12') == 1, 'jvim requires Neovim 0.12 or newer')
  overrides = overrides or {}
  if overrides.mode == nil then overrides = vim.tbl_extend('force', overrides, { mode = 'overlay' }) end
  local opts = require('jvim.config').setup(overrides)
  started = true
  vim.g.jvim_mode = opts.mode
  callback(opts.before_setup, 'before_setup', opts)
  if opts.mode == 'standalone' then require('jvim.options').setup() end
  local ok, plugins = pcall(require('jvim.bootstrap').setup, opts)
  if not ok then
    vim.notify('jvim plugin startup failed; core editing remains available: ' .. tostring(plugins), vim.log.levels.ERROR)
    plugins = false
  end
  vim.g.jvim_plugins_ready = plugins
  if opts.mode == 'standalone' and not plugins then
    opts.features.project_tree, opts.features.pdf = false, false
    opts.ui.tabline, opts.ui.statusline = false, false
  end
  if opts.ui.theme then
    if vim.tbl_contains(vim.tbl_map(function(theme) return theme.name end, require('jvim.theme').names()), opts.ui.theme) then
      require('jvim.theme').setup()
      if opts.ui.theme ~= 'jvim-charcoal' then require('jvim.theme').apply(opts.ui.theme) end
    else
      local ok, err = pcall(vim.cmd.colorscheme, opts.ui.theme)
      if not ok then vim.notify(err, vim.log.levels.WARN) end
    end
  end
  require('jvim.namespace_indent').setup()
  if opts.mode == 'standalone' then
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('jvim-cpp-options', { clear = true }),
      pattern = { 'c', 'cpp' },
      callback = function()
        vim.bo.expandtab, vim.bo.shiftwidth, vim.bo.tabstop, vim.bo.cindent = true, 4, 4, true
      end,
    })
    require('jvim.cpp_header').setup()
  end
  require 'jvim.keymaps'
  if opts.features.compiler_checks then require('jvim.rename').setup() end
  if opts.features.pdf then require('jvim.pdf_viewer').setup()
  elseif vim.fn.has 'win32' == 1 then require('jvim.pdf_viewer').setup_external() end
  if not plugins and next(opts.lsp.servers) then require('jvim.lsp').setup() end
  callback(opts.after_setup, 'after_setup', opts)
  return M
end

function M.get_config() return vim.deepcopy(require('jvim.config').get()) end

return M
