local M = {}

function M.setup()
  if vim.fn.has 'win32' ~= 1 then return end
  -- Neovide forwards these directly; terminals may reserve Ctrl combinations.
  for _, mode in ipairs { 'n', 'i', 's', 'x', 'c' } do
    for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
      if mapping.lhs:find('[<%-]D%-') then
        local key = mapping.lhs:gsub('([<%-])D%-', '%1C-')
        -- Command+Shift+letter is normalized to an uppercase letter. Ctrl
        -- needs an explicit Shift modifier or it collapses onto Ctrl+letter.
        if mapping.lhs:match '%-([A-Z])>$' and not key:find '[<%-]S%-' then
          key = key:gsub('%-([A-Z])>$', '-S-%1>')
        end
        vim.keymap.set(mode, key, mapping.callback or mapping.rhs, {
          desc = mapping.desc,
          expr = mapping.expr == 1,
          remap = mapping.noremap == 0,
          silent = mapping.silent == 1,
        })
      end
    end
  end
  vim.keymap.set({ 'n', 'i' }, '<C-LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= 0 and vim.api.nvim_win_is_valid(mouse.winid) then
      require('custom.definition_links').jump(mouse.winid, vim.api.nvim_win_get_buf(mouse.winid), mouse.line, math.max(0, mouse.column - 1))
    end
  end, { desc = 'Go to clicked symbol definition' })
end

return M
