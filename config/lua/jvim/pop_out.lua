local M = {}

local function notify(message) vim.notify(message, vim.log.levels.WARN) end

function M.wezterm()
  local found = vim.fn.exepath 'wezterm'
  if found ~= '' then return found end
  local gui = vim.env.WEZTERM_EXECUTABLE
  if not gui then return nil end
  local cli = vim.fs.joinpath(vim.fs.dirname(gui), vim.fn.has 'win32' == 1 and 'wezterm.exe' or 'wezterm')
  return vim.fn.executable(cli) == 1 and cli or nil
end

-- The new window starts through the launcher when it is on PATH, otherwise straight through this Neovim.
local function jvim_command()
  local launcher = vim.fn.exepath 'jvim'
  if launcher ~= '' then return { launcher } end
  return { 'env', 'NVIM_APPNAME=' .. (vim.env.NVIM_APPNAME or 'jvim'), vim.v.progpath }
end

-- Arguments for the new window; the caller closes the file here first so the new jvim can edit it.
function M.command(path, cursor, root)
  local cli = M.wezterm()
  if not cli or not vim.env.WEZTERM_PANE then return nil, 'Opening a file in a new window needs WezTerm' end
  local command = { cli, 'cli', 'spawn', '--new-window', '--cwd', root, '--' }
  vim.list_extend(command, jvim_command())
  vim.list_extend(command, { ('+call cursor(%d, %d)'):format(cursor[1], cursor[2] + 1), path })
  return command
end

function M.open()
  local files = require 'jvim.files'
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or path == '' or not vim.tbl_contains(files.editor_windows(), vim.api.nvim_get_current_win()) then
    return notify 'Open a file in the editor to move it to a new window'
  end
  local command, err = M.command(path, vim.api.nvim_win_get_cursor(0), require('jvim.run').root())
  if not command then return notify(err) end
  if vim.bo[buf].modified then vim.cmd.write() end
  if not files.close_current_tab() then vim.cmd.enew() end
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, {}) end
  vim.system(command, { text = true }, function(result)
    if result.code ~= 0 then vim.schedule(function() notify('Could not open a new window: ' .. vim.trim(result.stderr)) end) end
  end)
end

return M
