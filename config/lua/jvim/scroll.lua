local M = {}

-- Neovim moves its native cursor to keep it on screen. During wheel browsing,
-- hide that cursor and show a stationary marker at the original edit position.
function M.setup()
  -- Reconfiguration must release the previous cursor/viewport anchor first.
  if M.resume then M.resume() end
  local ns = vim.api.nvim_create_namespace 'clion-scroll'
  local selection_ns = vim.api.nvim_create_namespace 'clion-scroll-selection'
  local group = vim.api.nvim_create_augroup('clion-scroll', { clear = true })
  local anchor, held
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
  -- Keys that act on a selection. While a scrolled-away selection is held they reselect it first.
  local editing_keys = { '<Up>', '<Down>', '<Left>', '<Right>', '<S-Up>', '<S-Down>', '<S-Left>', '<S-Right>', '<Home>', '<End>',
    '<S-Home>', '<S-End>', '<C-Left>', '<C-Right>', '<M-Left>', '<M-Right>', '<BS>', '<Del>', '<CR>', '<Tab>', '<D-c>', '<D-x>', '<D-v>' }
  for number = 13, 99 do
    if number <= 37 and number ~= 35 then editing_keys[#editing_keys + 1] = '<F' .. number .. '>' end
    editing_keys[#editing_keys + 1] = '<F35>' .. number
    editing_keys[#editing_keys + 1] = '<C-F11>' .. number
  end
  local function release()
    if not held then return end
    if vim.api.nvim_buf_is_valid(held.buf) then
      vim.api.nvim_buf_clear_namespace(held.buf, selection_ns, 0, -1)
      for _, mapping in ipairs(held.maps) do pcall(vim.keymap.del, mapping[1], mapping[2], { buffer = held.buf }) end
    end
    held = nil
  end
  local function reselect(key)
    local select = held.select
    release()
    -- Both go to the front of the typeahead: the reselection first, then the key, now mapped for Select mode.
    vim.api.nvim_feedkeys(key, 'it', false)
    vim.api.nvim_feedkeys(vim.keycode(select and '<C-\\><C-n>gv<C-g>' or '<C-\\><C-n>gv'), 'ni', false)
  end
  function M.resume()
    restore()
    clear()
    release()
  end
  -- Scrolling would drag the selection's cursor end along with the view, so leave the selection while the
  -- wheel turns, keep it drawn in place, and reselect it (gv) before the next editing key acts on it.
  for _, key in ipairs { '<ScrollWheelUp>', '<ScrollWheelDown>' } do
    vim.keymap.set({ 'x', 's' }, key, function()
      local mode = vim.fn.mode()
      local visual = ({ s = 'v', S = 'V', ['\19'] = '\22' })[mode] or mode
      local from, to = vim.fn.getpos 'v', vim.fn.getpos '.'
      if from[2] > to[2] or (from[2] == to[2] and from[3] > to[3]) then from, to = to, from end
      local buf = vim.api.nvim_get_current_buf()
      release()
      held = { buf = buf, win = vim.api.nvim_get_current_win(), select = visual ~= mode, maps = {} }
      vim.schedule(function()
        if not held or held.buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then return end
        vim.hl.range(buf, selection_ns, 'Visual', { from[2] - 1, from[3] - 1 }, { to[2] - 1, to[3] - 1 },
          { regtype = visual, inclusive = vim.o.selection ~= 'exclusive', priority = 150 })
        for _, lhs in ipairs(editing_keys) do
          for _, map_mode in ipairs { 'n', 'i' } do
            if vim.fn.maparg(lhs, map_mode, false, true).buffer ~= 1 then
              vim.keymap.set(map_mode, lhs, function() reselect(vim.keycode(lhs)) end, { buffer = buf })
              held.maps[#held.maps + 1] = { map_mode, lhs }
            end
          end
        end
      end)
      return '<Esc>' .. key
    end, { expr = true, desc = 'Scroll without moving the selection' })
  end
  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = group,
    callback = function()
      if not held or held.buf ~= vim.api.nvim_get_current_buf() then return end
      local char = vim.v.char
      vim.v.char = ''
      held.select = true
      reselect(char)
    end,
  })
  vim.on_key(function(key, typed)
    if typed == '' then return end
    local name = vim.fn.keytrans(typed)
    -- A click chooses a new position, like clicking away from a selection.
    if held and name:find('Mouse', 1, true) and not name:find('MouseMove', 1, true) then release() end
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
