local M = {}

local function preserve_swap(path)
  local directory = vim.fs.joinpath(vim.fn.stdpath 'state', 'jvim', 'recovered-swaps')
  if vim.fn.mkdir(directory, 'p', 448) == 0 and vim.fn.isdirectory(directory) == 0 then return nil end
  local name = ('%s-%s'):format(os.date '%Y%m%d-%H%M%S', vim.fs.basename(path))
  local backup = vim.fs.joinpath(directory, name)
  local ok = vim.uv.fs_copyfile(path, backup)
  return ok and backup or nil
end

-- Swap files record the Windows NetBIOS computer name, which can differ in case and length from the DNS host name.
local function this_host(host)
  if host == vim.uv.os_gethostname() then return true end
  return vim.fn.has 'win32' == 1 and host:upper() == (vim.env.COMPUTERNAME or ''):upper()
end

local function opened_read_only(name)
  vim.schedule(function() vim.notify(vim.fs.basename(name) .. ' is open in another jvim; opened read-only') end)
end

-- With the ATTENTION message suppressed, Neovim gives the buffer the next free swap name (.swo, ...)
-- when another editor holds .swp; a live owner of .swp means the file is being edited elsewhere.
local function held_elsewhere(buf)
  local swap = vim.fn.swapname(buf)
  if swap == '' or swap:match '%.swp$' then return false end
  local info = vim.fn.swapinfo((swap:gsub('%.sw.$', '.swp')))
  return not info.error and info.pid > 0 and info.pid ~= vim.fn.getpid()
end

-- Load a buffer in the background without the swap ATTENTION screen; files open in another jvim become read-only.
function M.load(buf)
  local shortmess = vim.o.shortmess
  vim.opt.shortmess:append 'A'
  local ok, err = pcall(vim.fn.bufload, buf)
  vim.o.shortmess = shortmess
  if not vim.api.nvim_buf_is_loaded(buf) then return false, err end
  if held_elsewhere(buf) then
    vim.bo[buf].readonly = true
    opened_read_only(vim.api.nvim_buf_get_name(buf))
  end
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimSwapRecovery', { clear = true })
  vim.api.nvim_create_autocmd('SwapExists', {
    group = group,
    callback = function()
      local swap = vim.v.swapname
      local info = vim.fn.swapinfo(swap)
      -- Unreadable swapfiles keep the usual warning prompt.
      if info.error then return end
      -- A running jvim on this machine is editing the file: open it read-only instead of prompting.
      if info.pid > 0 then
        if this_host(info.host) then
          vim.v.swapchoice = 'o'
          opened_read_only(vim.fn.expand '<afile>:p')
        end
        return
      end

      local original = info.fname and vim.fn.expand(info.fname) or ''
      local stat = original ~= '' and vim.uv.fs_stat(original) or nil
      -- swapinfo.mtime is the original file's timestamp recorded in the swap.
      -- Recovering it over a subsequently saved file replaces newer work.
      local disk_is_newer = stat and stat.mtime and stat.mtime.sec > (tonumber(info.mtime) or 0)

      local backup = preserve_swap(swap)
      if not backup then
        vim.notify('Could not back up stale swap; leaving Neovim recovery prompt open.', vim.log.levels.ERROR)
        return
      end

      if info.dirty == 1 and not disk_is_newer then
        vim.v.swapchoice = 'r'
        vim.notify('Recovered edits from a stale swap. Backup: ' .. backup, vim.log.levels.WARN)
      else
        vim.v.swapchoice = 'd'
        local reason = disk_is_newer and 'A newer saved file exists; archived the older swap without recovery.'
          or 'Archived a stale, clean swap.'
        vim.notify(reason .. ' Backup: ' .. backup, vim.log.levels.INFO)
      end
    end,
  })
end

return M
