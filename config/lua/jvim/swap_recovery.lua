local M = {}

local function preserve_swap(path)
  local directory = vim.fs.joinpath(vim.fn.stdpath 'state', 'jvim', 'recovered-swaps')
  if vim.fn.mkdir(directory, 'p', 448) == 0 and vim.fn.isdirectory(directory) == 0 then return nil end
  local name = ('%s-%s'):format(os.date '%Y%m%d-%H%M%S', vim.fs.basename(path))
  local backup = vim.fs.joinpath(directory, name)
  local ok = vim.uv.fs_copyfile(path, backup)
  return ok and backup or nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimSwapRecovery', { clear = true })
  vim.api.nvim_create_autocmd('SwapExists', {
    group = group,
    callback = function()
      local swap = vim.v.swapname
      local info = vim.fn.swapinfo(swap)
      -- Keep Neovim's own handling for a live local owner, and leave remote
      -- owners or unreadable swapfiles to the usual warning prompt.
      if info.error or info.pid > 0 then return end

      local backup = preserve_swap(swap)
      if not backup then
        vim.notify('Could not back up stale swap; leaving Neovim recovery prompt open.', vim.log.levels.ERROR)
        return
      end

      if info.dirty == 1 then
        vim.v.swapchoice = 'r'
        vim.notify('Recovered edits from a stale swap. Backup: ' .. backup, vim.log.levels.WARN)
      else
        vim.v.swapchoice = 'd'
        vim.notify('Archived a stale, clean swap. Backup: ' .. backup, vim.log.levels.INFO)
      end
    end,
  })
end

return M
