local M = {}
local last_file
local recent = {}
local panes = {}
local last_editor_win
local click_targets = {}
local next_click_target = 0
local closed_tabs = {}
-- Buffers that have belonged to a pane; others (such as extra startup arguments) join the pane that cycles first.
local placed = {}

local function image_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'image_nvim'
    and vim.api.nvim_buf_get_name(buf) ~= ''
end

local function valid_file(buf)
  if type(buf) ~= 'number' or not vim.api.nvim_buf_is_valid(buf) then return false end
  if (vim.bo[buf].buftype ~= '' and not image_buffer(buf)) or not vim.bo[buf].buflisted then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return (name ~= '' and vim.fn.isdirectory(name) == 0) or vim.bo[buf].modified
end

local function remember(buf)
  if not valid_file(buf) then return false end
  recent = vim.tbl_filter(function(other) return other ~= buf end, recent)
  table.insert(recent, 1, buf)
  return true
end

function M.list()
  return vim.tbl_filter(valid_file, vim.api.nvim_list_bufs())
end

local function editor_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return (vim.bo[buf].buftype == '' or image_buffer(buf) or vim.b[buf].jvim_pdf_viewer) and vim.bo[buf].filetype ~= 'neo-tree'
end

function M.editor_windows()
  return vim.tbl_filter(editor_window, vim.api.nvim_tabpage_list_wins(0))
end

local function remove_value(list, value)
  return vim.tbl_filter(function(item) return item ~= value end, list)
end

local function prune(pane)
  pane.tabs = vim.tbl_filter(valid_file, pane.tabs)
  pane.recent = vim.tbl_filter(function(buf) return vim.tbl_contains(pane.tabs, buf) end, pane.recent)
  if pane.cycle_order then
    pane.cycle_order = vim.tbl_filter(function(buf) return vim.tbl_contains(pane.tabs, buf) end, pane.cycle_order)
    if #pane.cycle_order == 0 then pane.cycle_order, pane.cycle_index = nil, nil end
  end
end

local function ensure_pane(win)
  if not editor_window(win) then return nil end
  local pane = panes[win]
  if not pane then
    pane = { tabs = {}, recent = {}, views = {}, current = nil }
    panes[win] = pane
  end
  prune(pane)
  local buf = vim.api.nvim_win_get_buf(win)
  if valid_file(buf) then
    if not vim.tbl_contains(pane.tabs, buf) then pane.tabs[#pane.tabs + 1] = buf end
    if not vim.tbl_contains(pane.recent, buf) then pane.recent[#pane.recent + 1] = buf end
    pane.current, placed[buf] = buf, true
  end
  last_editor_win = win
  return pane
end

local function touch(pane, buf)
  if not vim.tbl_contains(pane.tabs, buf) then pane.tabs[#pane.tabs + 1] = buf end
  pane.recent = remove_value(pane.recent, buf)
  table.insert(pane.recent, 1, buf)
  pane.current, placed[buf] = buf, true
end

local function save_view(win, pane, buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local ok, view = pcall(vim.api.nvim_win_call, win, vim.fn.winsaveview)
  if ok and type(view) == 'table' then pane.views[buf] = view end
end

local function activate(win, buf, reset_cycle)
  local pane = ensure_pane(win)
  if not pane or not valid_file(buf) then return end
  touch(pane, buf)
  if reset_cycle then pane.cycle_order, pane.cycle_index = nil, nil end
  remember(buf)
  last_file = buf
end

function M.pane_tabs(win)
  win = win or vim.api.nvim_get_current_win()
  local pane = ensure_pane(win)
  return pane and vim.deepcopy(pane.tabs) or {}
end

function M.render_winbar(win)
  local pane = ensure_pane(win)
  if not pane then return '' end
  local current = vim.api.nvim_win_get_buf(win)
  local focused = tonumber(vim.g.actual_curwin) or vim.api.nvim_get_current_win()
  local selected_group = win == focused and 'TabLineSel' or 'JvimTabLineSelNC'
  local parts = {}
  for _, buf in ipairs(pane.tabs) do
    if valid_file(buf) then
      next_click_target = next_click_target + 1
      click_targets[next_click_target] = { win = win, buf = buf }
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t'):gsub('%%', '%%%%')
      if name == '' then name = '[No Name]' end
      if vim.bo[buf].modified then name = name .. ' +' end
      local group = buf == current and selected_group or 'TabLine'
      parts[#parts + 1] = ('%%#%s#%%T%%%d@v:lua.JvimTabClick@ %s %%T'):format(group, next_click_target, name)
    end
  end
  return table.concat(parts, ' ')
end

function M.click_tab(target)
  local item = click_targets[tonumber(target)]
  if item and editor_window(item.win) and valid_file(item.buf) then M.show(item.buf, false, item.win) end
end

local function split_anchor(win)
  for _, side in ipairs { { 'h', 'right' }, { 'l', 'left' }, { 'k', 'below' }, { 'j', 'above' } } do
    local neighbour = vim.api.nvim_win_call(win, function() return vim.fn.win_getid(vim.fn.winnr(side[1])) end)
    if neighbour ~= win and editor_window(neighbour) then return neighbour, side[2] end
  end
end

function M.close_current_tab()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local pane = ensure_pane(win)
  if not pane then return false end
  save_view(win, pane, buf)
  local closed = { path = vim.api.nvim_buf_get_name(buf), view = pane.views[buf], win = win }
  local tab_position = vim.fn.index(pane.tabs, buf) + 1
  pane.tabs = remove_value(pane.tabs, buf)
  pane.recent = remove_value(pane.recent, buf)
  pane.views[buf] = nil
  pane.cycle_order, pane.cycle_index = nil, nil
  local next_buf
  for _, candidate in ipairs(pane.recent) do if valid_file(candidate) then next_buf = candidate; break end end
  if not next_buf then
    for _, candidate in ipairs(pane.tabs) do if valid_file(candidate) then next_buf = candidate; break end end
  end
  if next_buf then
    if closed.path ~= '' then closed_tabs[#closed_tabs + 1] = closed end
    M.show(next_buf, false, win)
    pane.tabs = remove_value(pane.tabs, buf)
    pane.recent = remove_value(pane.recent, buf)
    pane.views[buf] = nil
    local elsewhere = false
    for other_win, other_pane in pairs(panes) do
      if other_win ~= win and vim.tbl_contains(other_pane.tabs, buf) then elsewhere = true; break end
    end
    if not elsewhere and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.cmd, 'confirm bdelete ' .. buf)
      if valid_file(buf) then
        table.insert(pane.tabs, math.min(tab_position, #pane.tabs + 1), buf)
        table.insert(pane.recent, 1, buf)
      end
    end
    return true
  end
  local other_win
  for candidate in pairs(panes) do
    if candidate ~= win and editor_window(candidate) then other_win = candidate; break end
  end
  if other_win then
    closed.win, closed.anchor, closed.split = nil, split_anchor(win)
    if closed.path ~= '' then closed_tabs[#closed_tabs + 1] = closed end
    vim.api.nvim_win_close(win, true)
    if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then pcall(vim.cmd, 'confirm bdelete ' .. buf) end
    return true
  end
  return false
end

function M.show(buf, cycling, target_win)
  if type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf) and (vim.bo[buf].buftype == '' or image_buffer(buf)) then
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= '' and vim.fn.isdirectory(name) == 0 then vim.bo[buf].buflisted = true end
  end
  if not valid_file(buf) then return end
  local win = target_win or vim.api.nvim_get_current_win()
  if not editor_window(win) then
    win = editor_window(last_editor_win) and last_editor_win or nil
    if not win then
      for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if editor_window(candidate) then win = candidate; break end
      end
    end
  end
  if not win then
    win = vim.api.nvim_open_win(buf, true, { split = 'right' })
    local pane = ensure_pane(win)
    if pane then
      for _, previous_buf in ipairs(recent) do
        if valid_file(previous_buf) and not vim.tbl_contains(pane.tabs, previous_buf) then pane.tabs[#pane.tabs + 1], placed[previous_buf] = previous_buf, true end
      end
      touch(pane, buf)
    end
    return
  end

  local pane = ensure_pane(win)
  if not pane then return end
  local previous = vim.api.nvim_win_get_buf(win)
  save_view(win, pane, previous)
  touch(pane, buf)
  if not cycling then pane.cycle_order, pane.cycle_index = nil, nil end
  pane.expected_buf = buf
  vim.api.nvim_set_current_win(win)
  if previous ~= buf then vim.api.nvim_win_set_buf(win, buf) end
  pane.expected_buf = nil
  local view = pane.views[buf]
  if view then pcall(vim.api.nvim_win_call, win, function() vim.fn.winrestview(view) end) end
  last_editor_win, last_file = win, buf
end

function M.cycle(direction)
  local win = vim.api.nvim_get_current_win()
  if not editor_window(win) then win = editor_window(last_editor_win) and last_editor_win or nil end
  local pane = win and ensure_pane(win)
  if not pane then
    local buffers = vim.tbl_filter(valid_file, recent)
    if #buffers == 0 then buffers = M.list() end
    if #buffers > 0 then
      local current_index = 0
      local current = valid_file(last_file) and last_file or vim.api.nvim_get_current_buf()
      for index, buf in ipairs(buffers) do if buf == current then current_index = index; break end end
      if current_index == 0 then current_index = direction > 0 and #buffers or 1 end
      local target = buffers[(current_index - 1 + direction) % #buffers + 1]
      M.show(target, true)
    end
    return
  end
  prune(pane)
  local current = vim.api.nvim_win_get_buf(win)
  for _, buf in ipairs(M.list()) do
    if not placed[buf] then pane.tabs[#pane.tabs + 1], placed[buf] = buf, true end
  end
  if #pane.tabs < 2 then return end

  local continuing = pane.cycle_order and pane.cycle_order[pane.cycle_index] == current
    and #pane.cycle_order == #pane.tabs
  if continuing then
    for _, buf in ipairs(pane.tabs) do
      if not vim.tbl_contains(pane.cycle_order, buf) then continuing = false; break end
    end
  end
  if not continuing then
    if valid_file(current) then touch(pane, current) end
    pane.cycle_order = vim.deepcopy(pane.recent)
    for _, buf in ipairs(pane.tabs) do
      if not vim.tbl_contains(pane.cycle_order, buf) then pane.cycle_order[#pane.cycle_order + 1] = buf end
    end
    pane.cycle_index = nil
    for index, buf in ipairs(pane.cycle_order) do
      if buf == current then pane.cycle_index = index; break end
    end
    if not pane.cycle_index then pane.cycle_index = 1 end
  end
  local next_index = (pane.cycle_index - 1 + direction) % #pane.cycle_order + 1
  local target = pane.cycle_order[next_index]
  pane.cycle_index = next_index
  M.show(target, true, win)
end

local function buffer_for_path(path)
  if type(path) ~= 'string' or path == '' or vim.fn.filereadable(path) ~= 1 then return nil end
  local buf = vim.fn.bufnr(path)
  if buf < 0 then buf = vim.fn.bufadd(path) end
  if buf < 0 then return nil end
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  return valid_file(buf) and buf or nil
end

local function record_opened_buffer(event_win, buf)
  if not valid_file(buf) then return end
  -- A file joins only a pane that is showing it; events can arrive late or from another window's context.
  local win = editor_window(event_win) and vim.api.nvim_win_get_buf(event_win) == buf and event_win or nil
  if not win then
    for _, candidate in ipairs(vim.fn.win_findbuf(buf)) do
      if editor_window(candidate) then win = candidate; break end
    end
  end
  if not win then remember(buf); last_file = buf; return end
  local pane = ensure_pane(win)
  if not pane then return end
  touch(pane, buf)
  pane.cycle_order, pane.cycle_index = nil, nil
  remember(buf)
  last_file = buf
end

local function pane_state(win)
  local pane = ensure_pane(win)
  save_view(win, pane, vim.api.nvim_win_get_buf(win))
  local function paths(buffers)
    local values = {}
    for _, buf in ipairs(buffers) do
      if valid_file(buf) and vim.api.nvim_buf_get_name(buf) ~= '' then values[#values + 1] = vim.api.nvim_buf_get_name(buf) end
    end
    return values
  end
  local views = {}
  for buf, view in pairs(pane.views) do
    if valid_file(buf) and vim.api.nvim_buf_get_name(buf) ~= '' then views[vim.api.nvim_buf_get_name(buf)] = vim.deepcopy(view) end
  end
  return {
    tabs = paths(pane.tabs), recent = paths(pane.recent), views = views,
    current = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)),
    width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win),
    focused = win == vim.api.nvim_tabpage_get_win(vim.api.nvim_win_get_tabpage(win)) or nil,
  }
end

-- The editor splits of the current tab page as a tree; tool windows such as the tree and terminals are left out.
function M.snapshot()
  local function walk(node)
    if node[1] == 'leaf' then
      return editor_window(node[2]) and { kind = 'leaf', pane = pane_state(node[2]) } or nil
    end
    local children = {}
    for _, child in ipairs(node[2]) do children[#children + 1] = walk(child) end
    if #children <= 1 then return children[1] end
    return { kind = node[1], children = children }
  end
  local tab = vim.api.nvim_get_current_tabpage()
  if vim.t[tab].jvim_changes then tab = vim.api.nvim_list_tabpages()[1] end
  return walk(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)))
end

local function restore_pane(win, saved)
  local pane = { tabs = {}, recent = {}, views = {}, current = nil }
  panes[win] = pane
  for _, path in ipairs(saved.tabs or {}) do
    local buf = buffer_for_path(path)
    if buf and not vim.tbl_contains(pane.tabs, buf) then pane.tabs[#pane.tabs + 1], placed[buf] = buf, true end
  end
  for _, path in ipairs(saved.recent or {}) do
    local buf = buffer_for_path(path)
    if buf and vim.tbl_contains(pane.tabs, buf) and not vim.tbl_contains(pane.recent, buf) then pane.recent[#pane.recent + 1] = buf end
  end
  for path, view in pairs(saved.views or {}) do
    local buf = buffer_for_path(path)
    if buf and type(view) == 'table' then pane.views[buf] = view end
  end
  local current = buffer_for_path(saved.current) or pane.recent[1] or pane.tabs[1]
  if not current then return false end
  touch(pane, current)
  pane.expected_buf = current
  vim.api.nvim_win_set_buf(win, current)
  pane.expected_buf = nil
  local view = pane.views[current]
  if view then pcall(vim.api.nvim_win_call, win, function() vim.fn.winrestview(view) end) end
  return true
end

function M.restore_snapshot(layout)
  if type(layout) ~= 'table' or not layout.kind then return false end
  local root = vim.api.nvim_get_current_win()
  if not editor_window(root) then return false end
  local placeholder = vim.api.nvim_win_get_buf(root)
  vim.cmd 'silent! only'
  local leaves, focused = {}, nil
  local function build(node, win)
    if node.kind == 'leaf' and type(node.pane) == 'table' then
      leaves[#leaves + 1] = { win = win, pane = node.pane }
      return
    end
    local children = type(node.children) == 'table' and node.children or {}
    local wins = { win }
    for index = 2, #children do
      wins[index] = vim.api.nvim_open_win(vim.api.nvim_win_get_buf(wins[index - 1]), false,
        { win = wins[index - 1], split = node.kind == 'row' and 'right' or 'below' })
    end
    for index, child in ipairs(children) do build(child, wins[index]) end
  end
  build(layout, root)
  local empty = {}
  for _, leaf in ipairs(leaves) do
    if restore_pane(leaf.win, leaf.pane) then
      if leaf.pane.focused then focused = leaf.win end
    else
      empty[#empty + 1] = leaf.win
    end
  end
  for _, win in ipairs(empty) do
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, true) end
  end
  for _, leaf in ipairs(leaves) do
    if vim.api.nvim_win_is_valid(leaf.win) then
      if tonumber(leaf.pane.width) then pcall(vim.api.nvim_win_set_width, leaf.win, leaf.pane.width) end
      if tonumber(leaf.pane.height) then pcall(vim.api.nvim_win_set_height, leaf.win, leaf.pane.height) end
    end
  end
  focused = focused and vim.api.nvim_win_is_valid(focused) and focused or vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(focused)
  last_editor_win = focused
  if vim.api.nvim_buf_is_valid(placeholder) and not valid_file(placeholder) and not vim.bo[placeholder].modified
    and #vim.fn.win_findbuf(placeholder) == 0 then
    pcall(vim.api.nvim_buf_delete, placeholder, {})
  end
  return true
end

function M.reopen_closed()
  local closed = table.remove(closed_tabs)
  if not closed then return false end
  local buf = buffer_for_path(closed.path)
  if not buf then
    vim.notify('Cannot reopen ' .. closed.path .. ': the file no longer exists', vim.log.levels.WARN)
    return false
  end
  local win = editor_window(closed.win) and closed.win or nil
  if not win and editor_window(closed.anchor) then
    win = vim.api.nvim_open_win(buf, true, { win = closed.anchor, split = closed.split })
  end
  M.show(buf, false, win)
  if closed.view then pcall(vim.fn.winrestview, closed.view) end
  return true
end

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
  _G.JvimTabClick = function(minwid) M.click_tab(minwid) end
  vim.api.nvim_exec2([[function! MiniTablineSwitchBuffer(buf_id, clicks, button, mod)
    call luaeval("require('jvim.files').show(_A)", a:buf_id)
  endfunction]], {})
end

function M.setup(group, opts)
  opts = opts or {}
  if opts.tree ~= false then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.api.nvim_create_augroup('FileExplorer', { clear = true })
  end
  local history_group = vim.api.nvim_create_augroup('JvimFileHistory', { clear = true })
  vim.o.showtabline = 0
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'BufFilePost', 'BufModifiedSet' }, {
    group = history_group,
    callback = function()
      vim.schedule(function()
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if editor_window(win) then vim.wo[win].winbar = '%{%v:lua.JvimPaneWinbar(' .. win .. ')%}' end
        end
      end)
    end,
  })
  _G.JvimPaneWinbar = function(win) return M.render_winbar(tonumber(win)) end
  vim.api.nvim_create_autocmd('BufEnter', {
    group = history_group,
    callback = function(args)
      local win = vim.api.nvim_get_current_win()
      local pane = panes[win]
      if pane and pane.expected_buf == args.buf then
        pane.expected_buf = nil
        activate(win, args.buf, false)
      else
        vim.schedule(function() record_opened_buffer(win, args.buf) end)
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = history_group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local pane = ensure_pane(win)
      if pane then activate(win, vim.api.nvim_win_get_buf(win), true) end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = history_group,
    callback = function(args)
      local win = args.event == 'WinLeave' and vim.fn.win_getid() or vim.api.nvim_get_current_win()
      local pane = panes[win]
      if pane and vim.api.nvim_win_is_valid(win) then save_view(win, pane, vim.api.nvim_win_get_buf(win)) end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = history_group,
    callback = function(args)
      local win = tonumber(args.match)
      panes[win] = nil
      if last_editor_win == win then last_editor_win = nil end
    end,
  })
  M.setup_tabline()
  vim.api.nvim_create_autocmd('VimEnter', {
    group = history_group,
    callback = function()
      if #vim.api.nvim_list_uis() == 0 or vim.fn.argc() > 1 then return end
      local has_file_argument = false
      for _, argument in ipairs(vim.fn.argv()) do
        if vim.fn.isdirectory(argument) ~= 1 then has_file_argument = true; break end
      end
      if has_file_argument then return end
      local buf = vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_get_name(buf)
      local root = name ~= '' and vim.fn.isdirectory(name) == 1 and name
        or (name ~= '' and (vim.fs.root(name, { '.git', 'CMakeLists.txt', 'compile_commands.json', 'compile_flags.txt', 'package.json', 'pyproject.toml' }) or vim.fs.dirname(name)))
        or vim.fn.getcwd()
      require('jvim.session').restore(root)
    end,
  })
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
