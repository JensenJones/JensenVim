local M = {}
function M.setup()
  -- One prefix avoids terminal-dependent encodings of Shift/Ctrl+F1..F4.
  -- iTerm encodes Command shortcuts as Ctrl+F11 followed by an action number
  -- (for example, Cmd+C arrives as <C-F11>13 and Cmd+W as <C-F11>20). Map
  -- that actual sequence as well as the standalone function-key forms.
  for number = 13, 76 do
    local source = number <= 37 and number ~= 35 and ('<F' .. number .. '>') or ('<F35>' .. number)
    local destination = '<F35>' .. number
    for _, mode in ipairs { 'n', 'i', 's', 'x', 'c', 't' } do
      local mapping = vim.fn.maparg(source, mode, false, true)
      local rhs = mapping.callback or mapping.rhs
      if rhs then
        local options = {
          desc = mapping.desc,
          remap = mapping.noremap == 0,
          expr = mapping.expr == 1,
          silent = mapping.silent == 1,
          nowait = mapping.nowait == 1,
        }
        if source ~= destination then vim.keymap.set(mode, destination, rhs, options) end
        vim.keymap.set(mode, '<C-F11>' .. number, rhs, options)
      end
    end
  end
end
return M
