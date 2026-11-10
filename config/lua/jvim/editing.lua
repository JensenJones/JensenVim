local M = {}

function M.eligible(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].modifiable
    and vim.bo[buf].filetype ~= 'neo-tree'
    and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 0
end

function M.running_terminal(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local job = vim.bo[buf].buftype == 'terminal' and vim.b[buf].terminal_job_id
  return job and vim.fn.jobwait({ job }, 0)[1] == -1 or false
end

function M.resume()
  if vim.bo.filetype == 'neo-tree' then
    vim.cmd.stopinsert()
  elseif M.running_terminal() then
    if vim.fn.mode() ~= 't' then vim.cmd.startinsert() end
  elseif M.eligible() and vim.fn.mode() == 'n' then
    vim.cmd.startinsert()
  end
end

function M.capture()
  local context = { buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() }
  function context:valid()
    return vim.api.nvim_buf_is_valid(self.buf) and vim.api.nvim_buf_is_loaded(self.buf)
  end
  function context:apply(callback)
    if not self:valid() then return false end
    if vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf then
      vim.api.nvim_win_call(self.win, callback)
    else
      vim.api.nvim_buf_call(self.buf, callback)
    end
    return true
  end
  return context
end

return M
