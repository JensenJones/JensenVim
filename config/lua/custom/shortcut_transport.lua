local M = {}
function M.setup()
  -- One prefix avoids terminal-dependent encodings of Shift/Ctrl+F1..F4.
  for number = 13, 37 do
    if number ~= 35 then
      local source, destination = '<F' .. number .. '>', '<F35>' .. number
      for _, mode in ipairs { 'n', 'i', 's', 'x', 'c' } do
        local mapping = vim.fn.maparg(source, mode, false, true)
        local rhs = mapping.callback or mapping.rhs
        if rhs then
          vim.keymap.set(mode, destination, rhs, {
            desc = mapping.desc,
            remap = mapping.noremap == 0,
            expr = mapping.expr == 1,
            silent = mapping.silent == 1,
            nowait = mapping.nowait == 1,
          })
        end
      end
    end
  end
end
return M
