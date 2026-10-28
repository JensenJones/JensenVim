local M = {}
local matches = {}

local function clear(win)
  local match = matches[win]
  if not match then return end
  matches[win] = nil
  if not vim.api.nvim_win_is_valid(win) then return end
  pcall(vim.api.nvim_win_call, win, function() pcall(vim.fn.matchdelete, match) end)
end

function M.update(win)
  win = win or vim.api.nvim_get_current_win()
  clear(win)
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then return end

  vim.api.nvim_win_call(win, function()
    local word = vim.fn.expand '<cword>'
    if word == '' then return end
    local pattern = '\\V\\<' .. vim.fn.escape(word, '\\') .. '\\>'
    matches[win] = vim.fn.matchadd('JvimWord', pattern, 120)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimWordHighlight', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then M.update(win) end
      end, 80)
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    callback = function() clear(vim.api.nvim_get_current_win()) end,
  })
end

return M
