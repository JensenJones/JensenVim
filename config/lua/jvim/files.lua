local M = {}
local last_file
local recent = {}
local cycle_order
local cycle_index

local function remember(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= '' or (name == '' and not vim.bo[buf].modified) or (name ~= '' and vim.fn.isdirectory(name) == 1) then return false end
  recent = vim.tbl_filter(function(other) return other ~= buf end, recent)
  table.insert(recent, 1, buf)
  return true
end

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

function M.show(buf, cycling)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not cycling then
    cycle_order = nil
    cycle_index = nil
  end
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
  remember(buf)
end

function M.cycle(direction)
  local files = M.list()
  if #files == 0 then return end
  local current = vim.api.nvim_get_current_buf()
  if vim.bo.filetype == 'neo-tree' then current = last_file end
  recent = vim.tbl_filter(function(buf) return vim.tbl_contains(files, buf) end, recent)
  local continuing = cycle_order and cycle_order[cycle_index] == current
    and #cycle_order == #files
    and vim.tbl_contains(files, current)
  if continuing then
    for _, buf in ipairs(cycle_order) do
      if not vim.tbl_contains(files, buf) then continuing = false break end
    end
  end
  if not continuing then
    if current and vim.tbl_contains(files, current) then remember(current) end
    cycle_order = vim.deepcopy(recent)
    for _, buf in ipairs(files) do
      if not vim.tbl_contains(cycle_order, buf) then table.insert(cycle_order, buf) end
    end
    cycle_index = nil
    for index, buf in ipairs(cycle_order) do
      if buf == current then
        cycle_index = index
        break
      end
    end
    if not cycle_index then
      table.insert(cycle_order, 1, files[1])
      cycle_index = 1
    end
  end
  local next_index = (cycle_index - 1 + direction) % #cycle_order + 1
  local target = cycle_order[next_index]
  cycle_index = next_index
  M.show(target, true)
end

-- Tree commands are explicit actions, never simulated printable keys.
function M.focus_tree()
  vim.cmd.stopinsert()
  local available, manager = pcall(require, 'neo-tree.sources.manager')
  local loaded, command = pcall(require, 'neo-tree.command')
  if not available or not loaded then
    vim.notify('The project tree requires Neo-tree; enable it through your plugin manager', vim.log.levels.WARN)
    return nil
  end
  command.execute { action = 'focus', source = 'filesystem', position = 'left', reveal = false }
  local state
  local ready = vim.wait(1000, function()
    state = manager.get_state 'filesystem'
    if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) or not state.tree then return false end
    local ok, node = pcall(state.tree.get_node, state.tree)
    return ok and node ~= nil
  end, 10)
  if not ready then
    vim.notify('Project tree did not become ready', vim.log.levels.WARN)
    return nil
  end
  vim.api.nvim_set_current_win(state.winid)
  return state
end

local function tree_command(name)
  local state = M.focus_tree()
  if state then
    -- Neo-tree normally supplies per-mapping config through its renderer.
    state.config = {}
    state.commands[name](state)
  end
end
function M.new_file() tree_command('add') end
function M.new_folder() tree_command('add_directory') end
function M.cut() tree_command('cut_to_clipboard') end
function M.paste() tree_command('paste_from_clipboard') end

function M.setup_tabline()
  vim.api.nvim_exec2(
    [[
    function! MiniTablineSwitchBuffer(buf_id, clicks, button, mod)
      call luaeval("require('jvim.files').show(_A)", a:buf_id)
    endfunction
  ]],
    {}
  )
end

function M.setup(group, opts)
  opts = opts or {}
  -- Neo-tree is the only directory browser. Disabling its netrw hijack alone
  -- leaves the built-in explorer free to open a second window at startup.
  if opts.tree ~= false then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.api.nvim_create_augroup('FileExplorer', { clear = true })
  end
  local history_group = vim.api.nvim_create_augroup('JvimFileHistory', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = history_group,
    callback = function(args)
      if remember(args.buf) then last_file = args.buf end
    end,
  })
  if opts.tabline ~= false and package.loaded['mini.tabline'] then M.setup_tabline() end
  if opts.tree == false then return end
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
