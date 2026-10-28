local M = {}

function M.open()
  local cwd = vim.fn.getcwd()
  vim.cmd 'botright 12new'
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.termopen(vim.o.shell, { cwd = cwd })
  if job <= 0 then
    vim.notify('Could not start a terminal in ' .. cwd, vim.log.levels.ERROR)
    vim.cmd.close()
    return
  end
  vim.b[buf].jvim_command_terminal = true
  vim.cmd.startinsert()
end

return M
