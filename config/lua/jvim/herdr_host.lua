local M = {}

function M.setup()
  local socket = vim.env.JVIM_HOST_SOCKET
  if not socket then return end
  local pipe, connected, connecting, leaving = nil, false, false, false
  local latest = 'focus'
  local connect
  local function retry(client)
    if client ~= pipe then return end
    connected, connecting = false, false
    if pipe and not pipe:is_closing() then pipe:close() end
    pipe = nil
    if not leaving then vim.defer_fn(function() if not connected and not connecting then connect() end end, 500) end
  end
  local function send(value)
    latest = value
    if not connected then return end
    local client = pipe
    local ok = pcall(function()
      client:write(value .. '\n', function(err) if err then vim.schedule(function() retry(client) end) end end)
    end)
    if not ok then retry(client) end
  end
  connect = function()
    if leaving then return end
    connecting = true
    pipe = vim.uv.new_pipe(false)
    local client = pipe
    client:connect(socket, function(err)
      if err then vim.schedule(function() retry(client) end); return end
      connected, connecting = true, false
      send(latest)
      client:read_start(function(read_err, data)
        if read_err or not data then vim.schedule(function() retry(client) end); return end
        if data:find('ERROR', 1, true) then vim.schedule(function() vim.notify(data, vim.log.levels.WARN) end) end
      end)
    end)
  end
  local group = vim.api.nvim_create_augroup('jvim-terminal-profile', { clear = true })
  vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = function() send 'focus' end })
  vim.api.nvim_create_autocmd('FocusLost', { group = group, callback = function() send 'blur' end })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function() leaving = true; send 'blur' end })
  connect()
end

return M
