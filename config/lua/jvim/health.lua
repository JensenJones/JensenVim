local M = {}

local function policy(label, enabled)
  vim.health.info(label .. ': ' .. (enabled and 'enabled' or 'disabled'))
end

local function executable(label, command)
  local resolved = vim.fn.exepath(command)
  if resolved ~= '' then
    vim.health.ok(label .. ': ' .. resolved)
    return true
  end
  vim.health.warn(label .. ': ' .. command .. ' missing; provide it on PATH or configure your company tool command')
  return false
end

local function compiler()
  for _, command in ipairs { 'clang++', 'g++', 'clang', 'gcc', 'cl' } do
    local resolved = vim.fn.exepath(command)
    if resolved ~= '' then
      vim.health.ok('C/C++ compiler: ' .. resolved)
      return
    end
  end
  vim.health.warn('C/C++ compiler missing; compiler checks need the compiler named in compile_commands.json')
end

local function language_servers(opts)
  local servers = opts.lsp.default_servers and {
    clangd = { cmd = { 'clangd' } },
    lua_ls = { cmd = { 'lua-language-server' } },
  } or {}
  for name, server in pairs(opts.lsp.servers) do servers[name] = server end
  local names = vim.tbl_keys(servers)
  table.sort(names)
  for _, name in ipairs(names) do
    local server = servers[name]
    if server ~= false then
      -- Prefer the effective configuration, including host-supplied commands.
      local configured = vim.lsp.config[name]
      local command = configured and configured.cmd or server.cmd
      if type(command) == 'table' and type(command[1]) == 'string' then
        executable('LSP ' .. name, command[1])
      else
        vim.health.info('LSP ' .. name .. ': command supplied by the host or resolved when the server attaches')
      end
    end
  end
  if opts.mode == 'overlay' then
    vim.health.info('Host language servers, build tools and debugger adapters remain managed by the company configuration')
  end
end

local function platform()
  if vim.fn.has 'win32' == 1 then
    vim.health.info('Platform integration: Windows terminal/Neovide; desktop keyboard and mouse delivery require Windows validation')
  elseif vim.fn.has 'macunix' == 1 then
    local terminal = vim.env.TERM_PROGRAM or 'terminal'
    vim.health.info('Platform integration: macOS ' .. terminal .. (vim.env.HERDR_ENV == '1' and ' / Herdr' or ''))
    local socket = vim.env.JVIM_HOST_SOCKET
    if socket and socket ~= '' then
      local stat = vim.uv.fs_stat(socket)
      if stat and stat.type == 'socket' then
        vim.health.ok('iTerm shortcut bridge socket: ' .. socket .. ' (connection not probed)')
      else
        vim.health.warn('iTerm shortcut bridge socket unavailable: ' .. socket .. '; launch through jvim to reconnect')
      end
    else
      vim.health.info('iTerm shortcut bridge is not attached; use the jvim launcher in iTerm for Mac shortcut transport')
    end
    if terminal == 'iTerm.app' then
      local share = vim.fn.expand '~/.local/share/jvim'
      if vim.fn.filereadable(share .. '/host-profile.applescript') ~= 1 then
        vim.health.warn('Mac integration files missing; run the macOS installer to enable the optional shortcut bridge')
      end
      executable('Mac integration Python', share .. '/runtime/bin/python3')
    end
  else
    vim.health.info('Platform integration: terminal editing; iTerm/Herdr shortcut transport is available on macOS')
  end
end

function M.check()
  local config = require 'jvim.config'
  local opts = config.get()
  vim.health.start 'jvim foundations'
  if vim.fn.has 'nvim-0.12' == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()) .. ' (minimum 0.12)')
  else
    vim.health.error('Neovim 0.12 or newer is required; running ' .. tostring(vim.version()))
  end
  vim.health.info('Mode: ' .. opts.mode)
  vim.health.info('Personal configuration: ' .. config.source())
  vim.health.info('Profile: ' .. (config.profile() or 'default'))
  for _, problem in ipairs(config.errors()) do vim.health.error(problem) end
  policy('Offline', opts.offline)
  policy('Plugin installation', opts.plugins.enabled and opts.plugins.install)
  policy('Mason', opts.tools.mason)
  policy('Tool installation', opts.tools.mason and opts.tools.install)
  policy('Parser installation', opts.treesitter.auto_install)
  vim.health.info('Completion matcher: ' .. opts.completion.fuzzy)
  local lazy = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
  if vim.fn.filereadable(lazy .. '/lua/lazy/init.lua') == 1 then
    vim.health.ok('Lazy cache: ' .. lazy)
  elseif opts.mode == 'overlay' or not opts.plugins.enabled then
    vim.health.info('Lazy cache missing; plugin management belongs to the host configuration')
  else
    vim.health.warn('Lazy cache missing: ' .. lazy .. '; prepare plugins with installation enabled before using offline mode')
  end
  vim.health.start 'Tools (only needed for features you use)'
  language_servers(opts)
  executable('Project search', 'rg')
  if opts.features.compiler_checks then
    executable('Python 3 for compiler checks', 'python3')
    compiler()
  else
    vim.health.info('Compiler checks: disabled')
  end
  if opts.features.pdf then
    executable('PDF metadata', 'pdfinfo')
    executable('PDF rendering', 'pdftoppm')
    local image = vim.fn.exepath 'magick'
    if image == '' then image = vim.fn.exepath 'convert' end
    if image == '' then
      vim.health.warn('ImageMagick missing; PDF image display needs magick or convert and a supported graphics terminal')
    else
      vim.health.ok('ImageMagick: ' .. image)
    end
  else
    vim.health.info('PDF support: disabled')
  end
  vim.health.start 'Platform'
  platform()
end

return M
