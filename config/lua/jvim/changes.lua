local M = {}
local state
local collapsed = {}
local namespace = vim.api.nvim_create_namespace 'jvim-changes'
local empty_tree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

local function git(root, args)
  local result = vim.system(vim.list_extend({ 'git', '-C', root }, args), { text = true }):wait()
  return result.code == 0 and result.stdout or nil, result.stderr
end

function M.root(start)
  start = start or vim.api.nvim_buf_get_name(0)
  if start == '' or vim.fn.isdirectory(start) == 0 and vim.fn.filereadable(start) == 0 then start = vim.fn.getcwd() end
  local root = vim.fs.root(start, '.git')
  return root and vim.fs.normalize(root) or nil
end

local function base(root)
  return git(root, { 'rev-parse', '--verify', '-q', 'HEAD' }) and 'HEAD' or empty_tree
end

-- Files that differ from HEAD, including staged, unstaged and untracked changes.
function M.collect(root)
  local status, err = git(root, { 'status', '--porcelain=v1', '-z', '--untracked-files=all' })
  if not status then return nil, err end
  local items, by_path = {}, {}
  local fields = vim.split(status, '\0', { plain = true })
  local index = 1
  while index <= #fields do
    local field = fields[index]
    if #field > 3 then
      local x, y, path = field:sub(1, 1), field:sub(2, 2), field:sub(4)
      local item = { path = path, added = 0, removed = 0 }
      if x == 'R' or x == 'C' or y == 'R' or y == 'C' then
        index = index + 1
        item.old = fields[index]
      end
      if x == '?' then item.status = 'U'
      elseif x == 'D' or y == 'D' then item.status = 'D'
      elseif x == 'A' then item.status = 'A'
      elseif item.old then item.status = 'R'
      else item.status = 'M' end
      items[#items + 1], by_path[path] = item, item
    end
    index = index + 1
  end
  local numstat = git(root, { 'diff', '--numstat', '-z', base(root) }) or ''
  fields = vim.split(numstat, '\0', { plain = true })
  index = 1
  while index <= #fields do
    local added, removed, path = fields[index]:match('^(%S+)\t(%S+)\t(.*)$')
    if added and path == '' then path, index = fields[index + 2], index + 2 end
    if path and by_path[path] then by_path[path].added, by_path[path].removed = tonumber(added) or 0, tonumber(removed) or 0 end
    index = index + 1
  end
  for _, item in ipairs(items) do
    local file = root .. '/' .. item.path
    if item.status == 'U' and (vim.fn.getfsize(file) or 0) < 1024 * 1024 then
      item.added = #vim.fn.readfile(file)
    end
  end
  table.sort(items, function(a, b) return a.path < b.path end)
  return items
end

local function build_tree(items)
  local tree = { dirs = {}, files = {} }
  for _, item in ipairs(items) do
    local node = tree
    local parts = vim.split(item.path, '/', { plain = true })
    for depth = 1, #parts - 1 do
      node.dirs[parts[depth]] = node.dirs[parts[depth]] or { dirs = {}, files = {}, path = table.concat(parts, '/', 1, depth) }
      node = node.dirs[parts[depth]]
    end
    node.files[#node.files + 1] = { name = parts[#parts], item = item }
  end
  return tree
end

local status_groups = { M = 'Changed', A = 'Added', U = 'Added', D = 'Removed', R = 'Changed' }

local function render()
  local lines, marks, rows = {}, {}, {}
  local function add(text, row_target, highlights)
    lines[#lines + 1] = text
    rows[#lines] = row_target
    for _, mark in ipairs(highlights or {}) do marks[#marks + 1] = { #lines - 1, mark[1], mark[2], mark[3] } end
  end
  local added, removed = 0, 0
  for _, item in ipairs(state.items) do added, removed = added + item.added, removed + item.removed end
  local summary = ('Changes  %d file%s'):format(#state.items, #state.items == 1 and '' or 's')
  local counts = ('  +%d -%d'):format(added, removed)
  add(summary .. counts, nil, {
    { 0, #summary, 'Title' },
    { #summary + 2, #summary + 2 + #tostring(added) + 1, 'Added' },
    { #summary + #tostring(added) + 4, #summary + #counts, 'Removed' },
  })
  if #state.items == 0 then add('  No changes against HEAD') end
  local function walk(node, depth)
    local names = vim.tbl_keys(node.dirs)
    table.sort(names)
    for _, name in ipairs(names) do
      local dir, label = node.dirs[name], name
      while #dir.files == 0 and vim.tbl_count(dir.dirs) == 1 do
        local only = next(dir.dirs)
        dir, label = dir.dirs[only], label .. '/' .. only
      end
      local indent = string.rep('  ', depth)
      local open = not collapsed[dir.path]
      local text = indent .. (open and '▾ ' or '▸ ') .. label
      add(text, { dir = dir.path }, { { #indent, #text, 'Directory' } })
      if open then walk(dir, depth + 1) end
    end
    for _, file in ipairs(node.files) do
      local item = file.item
      local indent = string.rep('  ', depth)
      local prefix = indent .. item.status .. '  '
      local name = file.name .. (item.old and ('  ← ' .. item.old) or '')
      local plus, minus = item.added > 0 and ('+' .. item.added) or '', item.removed > 0 and ('-' .. item.removed) or ''
      local stats = plus .. (plus ~= '' and minus ~= '' and ' ' or '') .. minus
      local text = prefix .. name .. (stats ~= '' and '  ' .. stats or '')
      local stats_start = #prefix + #name + 2
      add(text, { item = item }, {
        { #indent, #indent + 1, status_groups[item.status] },
        { stats_start, stats_start + #plus, 'Added' },
        { #text - #minus, #text, 'Removed' },
      })
    end
  end
  walk(build_tree(state.items), 0)
  local buf = state.panel_buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for _, mark in ipairs(marks) do
    if mark[3] > mark[2] then vim.api.nvim_buf_set_extmark(buf, namespace, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] }) end
  end
  state.rows = rows
  local widest = 0
  for _, line in ipairs(lines) do widest = math.max(widest, vim.fn.strdisplaywidth(line)) end
  state.width = math.max(20, math.min(widest + 2, math.floor(vim.o.columns / 4)))
  vim.api.nvim_win_set_width(state.panel_win, state.width)
end

local function valid()
  return state and vim.api.nvim_tabpage_is_valid(state.tab) and vim.api.nvim_win_is_valid(state.panel_win)
end

local function close_diff()
  for _, win in ipairs { state.base_win, state.work_win } do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function() vim.cmd 'diffoff' end)
      vim.api.nvim_win_close(win, true)
    end
  end
  state.base_win, state.work_win, state.shown = nil, nil, nil
end

local function scratch(name, lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden, vim.bo[buf].modifiable, vim.bo[buf].readonly = 'wipe', false, true
  pcall(vim.api.nvim_buf_set_name, buf, name)
  if filetype then vim.bo[buf].filetype = filetype end
  return buf
end

local function view_key(win)
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  return ('%d:%d:%d'):format(view.topline, view.topfill, view.leftcol), view
end

local function remember_views()
  state.views = {}
  for _, win in ipairs { state.base_win, state.work_win } do state.views[win] = view_key(win) end
end

-- Scrollbind only follows the focused window, but the wheel scrolls whichever pane is under the mouse.
local function sync_scroll()
  if not valid() or not state.base_win then return end
  local panes = { state.base_win, state.work_win }
  if not vim.api.nvim_win_is_valid(panes[1]) or not vim.api.nvim_win_is_valid(panes[2]) then return end
  local moved = vim.tbl_filter(function(win) return view_key(win) ~= state.views[win] end, panes)
  if #moved == 1 then
    local source = moved[1]
    local other = source == panes[1] and panes[2] or panes[1]
    local _, view = view_key(source)
    vim.api.nvim_win_call(source, function() vim.cmd 'syncbind' end)
    vim.api.nvim_win_call(other, function() vim.fn.winrestview { leftcol = view.leftcol } end)
  end
  remember_views()
end

function M.show_diff(item, focus)
  if not valid() then return end
  if state.shown ~= item.path then
    close_diff()
    local root = state.root
    local filetype = vim.filetype.match { filename = item.path }
    local base_lines = {}
    if item.status ~= 'A' and item.status ~= 'U' then
      local text = git(root, { 'show', base(root) .. ':' .. (item.old or item.path) })
      base_lines = text and vim.split(text:gsub('\n$', ''), '\n', { plain = true }) or {}
    end
    local base_buf = scratch(('jvim-changes://HEAD/%s'):format(item.old or item.path), base_lines, filetype)
    local work_buf
    local file = root .. '/' .. item.path
    if vim.fn.filereadable(file) == 1 then
      work_buf = vim.fn.bufadd(file)
      vim.fn.bufload(work_buf)
      vim.bo[work_buf].buflisted = true
    else
      work_buf = scratch(('jvim-changes://deleted/%s'):format(item.path), {}, filetype)
    end
    state.work_win = vim.api.nvim_open_win(work_buf, false, { win = state.panel_win, split = 'right' })
    state.base_win = vim.api.nvim_open_win(base_buf, false, { win = state.work_win, split = 'left' })
    vim.wo[state.base_win].winbar = '%#Comment# HEAD  ' .. (item.old or item.path):gsub('%%', '%%%%')
    for _, win in ipairs { state.base_win, state.work_win } do
      vim.api.nvim_win_call(win, function() vim.cmd 'diffthis' end)
      vim.wo[win].foldenable = false
    end
    vim.api.nvim_win_set_width(state.panel_win, state.width)
    vim.cmd 'wincmd ='
    vim.api.nvim_win_set_width(state.panel_win, state.width)
    vim.api.nvim_win_call(state.work_win, function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      if vim.fn.diff_hlID(1, 1) == 0 then vim.cmd 'silent! normal! ]c' end
    end)
    state.shown = item.path
    remember_views()
  end
  if focus then
    vim.api.nvim_set_current_win(state.work_win)
    require('jvim.editing').resume()
  end
end

local function target()
  return state.rows[vim.api.nvim_win_get_cursor(state.panel_win)[1]]
end

local function activate(focus)
  local row = valid() and target()
  if not row then return end
  if row.dir then
    collapsed[row.dir] = not collapsed[row.dir] or nil
    render()
  else
    M.show_diff(row.item, focus)
  end
end

function M.refresh()
  if not valid() then return end
  local items, err = M.collect(state.root)
  if not items then return vim.notify('Cannot read Git changes: ' .. tostring(err), vim.log.levels.ERROR) end
  local current = target()
  local path = current and current.item and current.item.path
  state.items = items
  render()
  if state.shown and not vim.iter(items):any(function(item) return item.path == state.shown end) then close_diff() end
  for row, value in pairs(state.rows) do
    if path and value.item and value.item.path == path then vim.api.nvim_win_set_cursor(state.panel_win, { row, 0 }) end
  end
end

function M.close()
  if not valid() then return end
  local tab = state.tab
  state = nil
  if #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(tab))
  else
    vim.cmd 'silent! only'
    vim.cmd.enew()
  end
end

function M.open(root)
  root = root or M.root()
  if not root then return vim.notify('Changes need a Git repository', vim.log.levels.WARN) end
  if valid() and state.root == root then
    vim.api.nvim_set_current_tabpage(state.tab)
    vim.api.nvim_set_current_win(state.panel_win)
    return M.refresh()
  end
  if valid() then M.close() end
  local items, err = M.collect(root)
  if not items then return vim.notify('Cannot read Git changes: ' .. tostring(err), vim.log.levels.ERROR) end
  vim.cmd.stopinsert()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = 'wipe', 'jvim-changes'
  vim.cmd.tabnew()
  local placeholder = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(0, buf)
  if vim.api.nvim_buf_is_valid(placeholder) and placeholder ~= buf then pcall(vim.api.nvim_buf_delete, placeholder, {}) end
  vim.t.jvim_changes = true
  state = { tab = vim.api.nvim_get_current_tabpage(), panel_win = vim.api.nvim_get_current_win(), panel_buf = buf,
            root = root, items = items }
  local win = state.panel_win
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, 'no'
  vim.wo[win].cursorline, vim.wo[win].wrap, vim.wo[win].winfixwidth = true, false, true
  vim.wo[win].winbar = '%#Title# ' .. vim.fs.basename(root):gsub('%%', '%%%%')
  render()
  for row, value in pairs(state.rows) do
    if value.item then vim.api.nvim_win_set_cursor(win, { row, 0 }); break end
  end
  local function key(lhs, fn, desc) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc }) end
  key('<CR>', function() activate(true) end, 'Open change')
  key('<2-LeftMouse>', function() activate(true) end, 'Open change')
  key('<LeftRelease>', function() local row = target(); if row and row.dir then activate(false) end end, 'Toggle folder')
  key('r', M.refresh, 'Refresh changes')
  key('q', M.close, 'Close changes')
  key('<Esc>', M.close, 'Close changes')
  local group = vim.api.nvim_create_augroup('JvimChanges', { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group, buffer = buf,
    callback = function() local row = target(); if row and row.item then M.show_diff(row.item, false) end end,
  })
  vim.api.nvim_create_autocmd('BufEnter', { group = group, buffer = buf, callback = function() vim.cmd.stopinsert() end })
  vim.api.nvim_create_autocmd('BufWritePost', { group = group, callback = function() vim.schedule(M.refresh) end })
  vim.api.nvim_create_autocmd('WinScrolled', { group = group, callback = sync_scroll })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function() if state and not vim.api.nvim_tabpage_is_valid(state.tab) then state = nil end end,
  })
  local row = target()
  if row and row.item then M.show_diff(row.item, false) end
  vim.api.nvim_set_current_win(win)
end

function M.is_open() return valid() and vim.api.nvim_get_current_tabpage() == state.tab end

return M
