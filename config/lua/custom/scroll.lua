local M = {}

-- Neovim moves its native cursor to keep it on screen. During wheel browsing,
-- hide that cursor and show a stationary marker at the original edit position.
function M.setup()
  local ns = vim.api.nvim_create_namespace 'clion-scroll'
  local group = vim.api.nvim_create_augroup('clion-scroll', { clear = true })
  local anchor
  local function highlights()
    vim.api.nvim_set_hl(0, 'JvimScrollHiddenCursor', { blend = 100, reverse = true })
    vim.api.nvim_set_hl(0, 'JvimScrollAnchor', { link = 'Cursor' })
  end
  highlights()
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
  local function clear()
    if not anchor then return end
    if vim.api.nvim_buf_is_valid(anchor.buf) then vim.api.nvim_buf_clear_namespace(anchor.buf, ns, 0, -1) end
    if vim.api.nvim_win_is_valid(anchor.win) then
      vim.wo[anchor.win].cursorline = anchor.cursorline
      vim.wo[anchor.win].cursorcolumn = anchor.cursorcolumn
    end
    vim.o.guicursor = anchor.guicursor
    anchor = nil
  end
  local function restore()
    if not anchor or not vim.api.nvim_buf_is_valid(anchor.buf) or not vim.api.nvim_win_is_valid(anchor.win) then return end
    if vim.api.nvim_win_get_buf(anchor.win) ~= anchor.buf then return end
    local pos = vim.api.nvim_buf_get_extmark_by_id(anchor.buf, ns, anchor.mark, {})
    if #pos == 2 then vim.api.nvim_win_set_cursor(anchor.win, { pos[1] + 1, pos[2] }) end
  end
  function M.resume()
    restore()
    clear()
  end
  vim.on_key(function(key, typed)
    if typed == '' then return end
    local name = vim.fn.keytrans(typed)
    if name:find('ScrollWheel', 1, true) then
      local mouse = vim.fn.getmousepos()
      if mouse.winid ~= 0 and mouse.winid ~= vim.api.nvim_get_current_win() then return end
      if not anchor and vim.bo.buftype == '' then
        local pos = vim.api.nvim_win_get_cursor(0)
        local text = vim.api.nvim_get_current_line()
        local character = vim.fn.strcharpart(text:sub(pos[2] + 1), 0, 1)
        anchor = {
          buf = vim.api.nvim_get_current_buf(),
          win = vim.api.nvim_get_current_win(),
          guicursor = vim.o.guicursor,
          cursorline = vim.wo.cursorline,
          cursorcolumn = vim.wo.cursorcolumn,
          mark = vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, pos[2], {
            virt_text = { { character ~= '' and character or ' ', 'JvimScrollAnchor' } },
            virt_text_pos = 'overlay',
            hl_mode = 'replace',
            priority = 200,
          }),
        }
        vim.wo.cursorline = false
        vim.wo.cursorcolumn = false
        vim.o.guicursor = 'a:JvimScrollHiddenCursor'
      end
    elseif anchor then
      if name:find('MouseMove', 1, true) then return end
      -- Mouse interaction intentionally chooses a new position.
      if
        not name:find('Mouse', 1, true)
        and not name:find('Drag', 1, true)
        and not name:find('Release', 1, true)
        and anchor.win == vim.api.nvim_get_current_win()
        and anchor.buf == vim.api.nvim_get_current_buf()
      then
        restore()
      elseif name:find('Mouse', 1, true) and vim.fn.getmousepos().winid ~= anchor.win then
        restore()
      end
      clear()
    end
  end, ns)
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = group,
    callback = M.resume,
  })
end

return M
