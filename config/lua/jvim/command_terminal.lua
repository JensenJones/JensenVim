local M = {}
local sessions = {}

function M.show(session)
  if not session or not vim.api.nvim_buf_is_valid(session.buf) then return nil end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == session.buf then
      vim.api.nvim_set_current_win(win)
      if session.status == 'running' then vim.cmd.startinsert() end
      return session
    end
  end
  vim.cmd 'botright 12split'
  vim.api.nvim_win_set_buf(0, session.buf)
  if session.status == 'running' then vim.cmd.startinsert() else vim.cmd.stopinsert() end
  return session
end

function M.get(key) return sessions[key] end

-- Closing a pane hides output; stopping a job is always an explicit action.
function M.hide()
  if not vim.b.jvim_command_terminal then return end
  vim.cmd.stopinsert()
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.cmd.close()
  else
    vim.cmd.enew()
  end
end

function M.stop(session)
  if not session or session.status ~= 'running' then return false end
  local stopped = vim.fn.jobstop(session.job) == 1
  if stopped then session.status = 'stopping' end
  return stopped
end

function M.open(opts)
  opts = opts or {}
  local cwd = vim.fs.normalize(opts.cwd or vim.fn.getcwd())
  local key = opts.key or ('shell:' .. cwd)
  if opts.restart == nil and opts.command == nil then opts.restart = true end
  local previous = sessions[key]
  if previous and vim.api.nvim_buf_is_valid(previous.buf) then
    if not opts.restart or previous.status == 'running' or previous.status == 'stopping' then return M.show(previous) end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  vim.b[buf].jvim_command_terminal = true
  vim.b[buf].jvim_project_root = opts.root
  local session = { buf = buf, key = key, cwd = cwd, status = 'running', title = opts.title or 'Shell' }
  M.show(session)
  local ok, job = pcall(vim.fn.termopen, opts.command or vim.o.shell, {
    cwd = cwd,
    env = opts.env,
    on_exit = function(_, code)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].jvim_terminal_exit_code = code
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '[' .. session.title .. ': exit ' .. code .. ']' })
          vim.bo[buf].modifiable = false
        end
        session.status, session.exit_code = 'exited', code
        vim.cmd.redrawstatus()
      end)
    end,
  })
  if not ok or job <= 0 then
    session.status = 'failed'
    vim.api.nvim_buf_delete(buf, { force = true })
    local err = 'Could not start ' .. session.title .. ': ' .. tostring(job)
    vim.notify(err, vim.log.levels.ERROR)
    return nil, err
  end
  session.job = job
  sessions[key] = session
  vim.b[buf].jvim_terminal_title = session.title
  vim.cmd.startinsert()
  return session
end

return M
