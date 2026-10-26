local M = {}
local last_file

function M.list()
  return vim.tbl_filter(function(buf)
    if not vim.bo[buf].buflisted or vim.bo[buf].buftype ~= '' then return false end
    local name = vim.api.nvim_buf_get_name(buf)
    return (name ~= '' and vim.fn.isdirectory(name) == 0) or vim.bo[buf].modified
  end, vim.api.nvim_list_bufs())
end

local function editor_window(win)
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == '' and vim.bo[buf].filetype ~= 'neo-tree'
end

function M.show(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local win = vim.api.nvim_get_current_win()
  if not editor_window(win) then
    win = nil
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if editor_window(candidate) then
        win = candidate
        break
      end
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, buf)
  else
    -- Put the file directly into a new editor pane. Never replace the tree or
    -- create a listed scratch buffer that can enter the file rotation.
    vim.api.nvim_open_win(buf, true, { split = 'right' })
  end
  last_file = buf
end

function M.cycle(direction)
  local files = M.list()
  if #files == 0 then return end
  local current = vim.api.nvim_get_current_buf()
  if vim.bo.filetype == 'neo-tree' then current = last_file end
  for index, buf in ipairs(files) do
    if buf == current then
      M.show(files[(index - 1 + direction) % #files + 1])
      return
    end
  end
  M.show(direction > 0 and files[1] or files[#files])
end

function M.setup_tabline()
  vim.api.nvim_exec2(
    [[
    function! MiniTablineSwitchBuffer(buf_id, clicks, button, mod)
      call luaeval("require('custom.files').show(_A)", a:buf_id)
    endfunction
  ]],
    {}
  )
end

function M.setup(group)
  -- Neo-tree is the only directory browser. Disabling its netrw hijack alone
  -- leaves the built-in explorer free to open a second window at startup.
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1
  vim.api.nvim_create_augroup('FileExplorer', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      if vim.tbl_contains(M.list(), args.buf) then last_file = args.buf end
    end,
  })
  if package.loaded['mini.tabline'] then M.setup_tabline() end
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    callback = function()
      if #vim.api.nvim_list_uis() == 0 or vim.fn.argc() > 1 then return end
      local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
      local name = vim.api.nvim_buf_get_name(buf)
      local directory = name ~= '' and vim.fn.isdirectory(name) == 1
      local empty = name == '' and not vim.bo[buf].modified and vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
      local project_start = not vim.bo[buf].modified and (directory or empty)
      vim.schedule(function()
        local root = directory and name
          or (name ~= '' and (vim.fs.root(name, { '.git', 'CMakeLists.txt', 'compile_commands.json', 'compile_flags.txt', 'package.json', 'pyproject.toml' }) or vim.fs.dirname(
            name
          )))
          or vim.fn.getcwd()
        require('neo-tree.command').execute {
          action = project_start and 'focus' or 'show',
          position = 'left',
          dir = root,
          reveal = name ~= '' and not directory,
          reveal_force_cwd = true,
        }
        if project_start and vim.bo.filetype == 'neo-tree' then
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win and vim.api.nvim_win_get_buf(win) == buf then
            vim.api.nvim_win_close(win, false)
          end
          if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 0 then vim.api.nvim_buf_delete(buf, {}) end
        end
      end)
    end,
  })
end

return M
