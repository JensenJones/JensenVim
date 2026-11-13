local M = {}

local function fold(win, command)
  win = (tonumber(win) or 0) ~= 0 and tonumber(win) or tonumber(vim.g.statusline_winid)
  if not win or win == 0 then win = vim.api.nvim_get_current_win() end
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' or vim.bo[buf].filetype == 'neo-tree' then return end
  pcall(vim.api.nvim_win_call, win, function() vim.cmd('silent! normal! ' .. command) end)
end

function M.collapse(win) fold(win, 'zc') end
function M.expand(win) fold(win, 'zo') end

function M.run(win, choose)
  win = tonumber(win)
  if not win or not vim.api.nvim_win_is_valid(win) then win = vim.api.nvim_get_current_win() end
  local run = require 'jvim.run'
  local root = vim.api.nvim_win_call(win, run.root)
  if choose then return run.choose(root) end
  return run.run(nil, root)
end

-- Neovide sends a click on the statusline to the window's own grid, where it moves the cursor instead of
-- reaching the button, so there the buttons sit at the right of the winbar, which belongs to that grid.
function M.in_winbar() return vim.g.neovide == true end
M.width = 33 -- display width of section()

function M.section(win)
  win = win or vim.api.nvim_get_current_win()
  return '%#JvimFoldButton#%' .. win .. '@JvimFoldCollapse@[- Fold]%T %' .. win .. '@JvimFoldExpand@[+ Fold]%T'
    .. '  %' .. win .. '@JvimRun@[Run]%T %' .. win .. '@JvimRunConfig@[Config]%T'
end

function M.setup(statusline)
  vim.api.nvim_exec2(
    [[
    function! JvimFoldCollapse(minwid, clicks, button, mods)
      call luaeval("require('jvim.fold_controls').collapse(_A)", a:minwid)
    endfunction
    function! JvimFoldExpand(minwid, clicks, button, mods)
      call luaeval("require('jvim.fold_controls').expand(_A)", a:minwid)
    endfunction
    function! JvimRun(minwid, clicks, button, mods)
      call luaeval("require('jvim.fold_controls').run(_A, false)", a:minwid)
    endfunction
    function! JvimRunConfig(minwid, clicks, button, mods)
      call luaeval("require('jvim.fold_controls').run(_A, true)", a:minwid)
    endfunction
  ]],
    {}
  )
  statusline.section_location = function()
    local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
    local location = '%2l:%-2v'
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= '' or vim.bo[buf].filetype == 'neo-tree' or M.in_winbar() then return location end
    return location .. '  ' .. M.section(win)
  end
end

return M
