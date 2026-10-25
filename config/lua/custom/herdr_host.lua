local M = {}
function M.setup()
  local socket = vim.env.JVIM_HOST_SOCKET
  if not socket then return end
  local pipe = vim.uv.new_pipe(false)
  local connected, pending = false, {}
  pipe:connect(socket, function(err)
    if err then
      vim.schedule(function() vim.notify('jvim terminal shortcuts: ' .. err, vim.log.levels.WARN) end)
      return
    end
    connected = true
    for _, value in ipairs(pending) do
      pipe:write(value .. '\n')
    end
    pending = {}
    pipe:read_start(function(_, data)
      if data and data:find('ERROR', 1, true) then vim.schedule(function() vim.notify(data, vim.log.levels.WARN) end) end
    end)
  end)
  local function profile(value)
    if connected then
      pipe:write(value .. '\n')
    else
      table.insert(pending, value)
    end
  end
  local group = vim.api.nvim_create_augroup('jvim-terminal-profile', { clear = true })
  vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = function() profile 'focus' end })
  vim.api.nvim_create_autocmd('FocusLost', { group = group, callback = function() profile 'blur' end })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function() profile 'blur' end })
end
return M
