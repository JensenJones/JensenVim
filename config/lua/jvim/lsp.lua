local M = {}
local started = false

function M.servers(opts)
  opts = opts or require('jvim.config').get()
  local servers = opts.lsp.default_servers and {
    -- clangd logs every request to stderr, which Neovim records as LSP errors; keep only real errors.
    clangd = { cmd = { 'clangd', '--background-index', '--clang-tidy', '--completion-style=detailed', '--header-insertion=iwyu', '--log=error' } },
    lua_ls = { settings = { Lua = { workspace = { checkThirdParty = false }, completion = { callSnippet = 'Replace' } } } },
  } or {}
  return require('jvim.config').merge(servers, opts.lsp.servers)
end

local function rotate_log()
  local path = vim.lsp.log.get_filename()
  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > 10 * 1024 * 1024 then vim.uv.fs_rename(path, path .. '.old') end
end

function M.setup()
  if started then return end
  started = true
  rotate_log()
  local opts = require('jvim.config').get()
  local servers = M.servers(opts)
  local group = vim.api.nvim_create_augroup('jvim-lsp', { clear = true })
  local highlight_events = { 'CursorHold', 'CursorHoldI', 'CursorMoved', 'CursorMovedI' }
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(event)
      local function map(key, callback, description)
        vim.keymap.set('n', key, callback, { buffer = event.buf, desc = description })
      end
      map('grn', function() require('jvim.rename').symbol() end, 'Rename symbol')
      map('grD', vim.lsp.buf.declaration, 'Go to declaration')
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client:supports_method('textDocument/documentHighlight', event.buf) then
        vim.api.nvim_clear_autocmds { group = group, buffer = event.buf, event = highlight_events }
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, { group = group, buffer = event.buf, callback = vim.lsp.buf.document_highlight })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, { group = group, buffer = event.buf, callback = vim.lsp.buf.clear_references })
      end
    end,
  })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(event.buf) then return end
        for _, client in ipairs(vim.lsp.get_clients { bufnr = event.buf }) do
          if client.id ~= event.data.client_id and client:supports_method('textDocument/documentHighlight', event.buf) then return end
        end
        vim.api.nvim_clear_autocmds { group = group, buffer = event.buf, event = highlight_events }
        vim.api.nvim_buf_call(event.buf, vim.lsp.buf.clear_references)
      end)
    end,
  })
  local packages = {}
  local mason_names = { clangd = 'clangd', lua_ls = 'lua-language-server' }
  for name, server in pairs(servers) do
    if server ~= false then
      server = vim.deepcopy(server)
      local ok, blink = pcall(require, 'blink.cmp')
      if ok then server.capabilities = blink.get_lsp_capabilities(server.capabilities) end
      vim.lsp.config(name, server)
      vim.lsp.enable(name)
      if mason_names[name] then table.insert(packages, mason_names[name]) end
    end
  end
  if opts.tools.mason and opts.tools.install then
    if opts.formatting.on_save then table.insert(packages, 'stylua') end
    local available, installer = pcall(require, 'mason-tool-installer')
    if available then installer.setup { ensure_installed = packages } end
  end
end

return M
