local M = {}
function M.open_clicked()
  if vim.bo.filetype ~= 'neo-tree' then return end
  local mouse = vim.fn.getmousepos()
  if mouse.line < 1 or mouse.line > vim.api.nvim_buf_line_count(0) then return end
  local state = require('neo-tree.sources.manager').get_state 'filesystem'
  if state and state.commands then state.commands.open(state) end
end
function M.setup()
  vim.keymap.set({ 'n', 'i', 's', 'x' }, '<LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= 0 and vim.api.nvim_win_is_valid(mouse.winid) and vim.bo[vim.api.nvim_win_get_buf(mouse.winid)].filetype == 'neo-tree' then
      return '<LeftMouse><Cmd>lua require("custom.tree_mouse").open_clicked()<CR>'
    end
    return '<LeftMouse>'
  end, { expr = true, desc = 'Select text or open clicked project item' })
end
return M
