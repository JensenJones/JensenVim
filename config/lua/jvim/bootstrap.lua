local M = {}

local function warn(message)
  vim.schedule(function() vim.notify(message, vim.log.levels.WARN, { title = 'jvim startup' }) end)
end

function M.setup(opts)
  if not opts.plugins.enabled then return false end
  local path = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
  if not vim.uv.fs_stat(path) then
    if not opts.plugins.install then
      warn('Plugin installation is disabled and lazy.nvim is not cached. Core editing remains available; provision plugins before enabling the full interface.')
      return false
    end
    local output = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', 'https://github.com/folke/lazy.nvim.git', path }
    if vim.v.shell_error ~= 0 then warn('Could not install lazy.nvim: ' .. output); return false end
  end
  local lockfile = vim.api.nvim_get_runtime_file('lazy-lock.json', false)[1]
  if lockfile and opts.plugins.install then
    local lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), '\n'))
    local pinned = lock['lazy.nvim'] and lock['lazy.nvim'].commit
    local marker = path .. '/.jvim-pinned'
    local recorded = vim.fn.filereadable(marker) == 1 and vim.fn.readfile(marker)[1]
    if pinned and recorded ~= pinned then
      local output = vim.fn.system { 'git', '-C', path, 'checkout', '--detach', pinned }
      if vim.v.shell_error ~= 0 then warn('Could not pin lazy.nvim: ' .. output); return false end
      vim.fn.writefile({ pinned }, marker)
    end
  end
  vim.opt.rtp:prepend(path)
  local specs = require 'jvim.plugins'
  vim.list_extend(specs, opts.plugins.specs)
  require('lazy').setup(specs, {
    lockfile = lockfile,
    install = { missing = opts.plugins.install },
    checker = { enabled = false },
    change_detection = { notify = false },
    ui = { icons = opts.ui.icons and {} or {
      cmd = '⌘', config = '🛠', event = '📅', ft = '📂', init = '⚙', keys = '🗝',
      plugin = '🔌', runtime = '💻', require = '🌙', source = '📄', start = '🚀', task = '📌', lazy = '💤',
    } },
  })
  return true
end

return M
