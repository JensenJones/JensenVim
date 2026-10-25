local M = {}

-- Neovim keeps its cursor on screen. Remember the original editing position
-- during wheel browsing and restore it before the next keyboard action.
function M.setup()
  local ns = vim.api.nvim_create_namespace 'clion-scroll'
  local anchor
  local function clear()
    if anchor and vim.api.nvim_buf_is_valid(anchor.buf) then vim.api.nvim_buf_clear_namespace(anchor.buf, ns, 0, -1) end
    anchor = nil
  end
  vim.on_key(function(key, typed)
    if typed == '' then return end
    local name = vim.fn.keytrans(typed)
    if name:find('ScrollWheel', 1, true) then
      local mouse = vim.fn.getmousepos()
      if mouse.winid ~= 0 and mouse.winid ~= vim.api.nvim_get_current_win() then return end
      if not anchor and vim.bo.buftype == '' then
        local pos = vim.api.nvim_win_get_cursor(0)
        anchor = {
          buf = vim.api.nvim_get_current_buf(),
          win = vim.api.nvim_get_current_win(),
          mark = vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, pos[2], {}),
        }
      end
    elseif anchor then
      -- Mouse interaction intentionally chooses a new position.
      if
        not name:find('Mouse', 1, true)
        and not name:find('Drag', 1, true)
        and not name:find('Release', 1, true)
        and anchor.win == vim.api.nvim_get_current_win()
        and anchor.buf == vim.api.nvim_get_current_buf()
      then
        local pos = vim.api.nvim_buf_get_extmark_by_id(anchor.buf, ns, anchor.mark, {})
        if #pos == 2 then vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] }) end
      end
      clear()
    end
  end, ns)
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = vim.api.nvim_create_augroup('clion-scroll', { clear = true }),
    callback = clear,
  })
end

return M
