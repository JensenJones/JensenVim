local M = {}
function M.open_clicked()
  if vim.bo.filetype ~= 'neo-tree' then return end
  local mouse = vim.fn.getmousepos()
  if mouse.line < 1 or mouse.line > vim.api.nvim_buf_line_count(0) then return end
  local state = require('neo-tree.sources.manager').get_state 'filesystem'
  if state and state.commands then state.commands.open(state) end
end
function M.setup()
  local function install(buf)
    vim.keymap.set({ 'n', 'i', 's', 'x' }, '<LeftMouse>', function()
      local mouse = vim.fn.getmousepos()
      if mouse.winid == 0 or not vim.api.nvim_win_is_valid(mouse.winid) then return '<LeftMouse>' end
      if vim.api.nvim_win_get_buf(mouse.winid) ~= buf then return '<LeftMouse>' end
      return '<LeftMouse><Cmd>lua require("custom.tree_mouse").open_clicked()<CR>'
    end, { expr = true, buffer = buf, desc = 'Open clicked project item' })
  end

  local group = vim.api.nvim_create_augroup('JvimTreeMouse', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'neo-tree',
    callback = function(args) install(args.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'neo-tree' then install(buf) end
  end
end
return M
