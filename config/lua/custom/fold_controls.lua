local M = {}

local function fold(win, command)
  win = win or tonumber(vim.g.statusline_winid)
  if not win or win == 0 then win = vim.api.nvim_get_current_win() end
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' or vim.bo[buf].filetype == 'neo-tree' then return end
  pcall(vim.api.nvim_win_call, win, function() vim.cmd('silent! normal! ' .. command) end)
end

function M.collapse(win) fold(win, 'zc') end
function M.expand(win) fold(win, 'zo') end

function M.section()
  return '%#JvimFoldButton#%@JvimFoldCollapse@[- Fold]%T %@JvimFoldExpand@[+ Fold]%T'
end

function M.setup(statusline)
  vim.api.nvim_exec2(
    [[
    function! JvimFoldCollapse(minwid, clicks, button, mods)
      call luaeval("require('custom.fold_controls').collapse()")
    endfunction
    function! JvimFoldExpand(minwid, clicks, button, mods)
      call luaeval("require('custom.fold_controls').expand()")
    endfunction
  ]],
    {}
  )
  statusline.section_location = function()
    local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
    local location = '%2l:%-2v'
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= '' or vim.bo[buf].filetype == 'neo-tree' then return location end
    return location .. '  ' .. M.section()
  end
end

return M
