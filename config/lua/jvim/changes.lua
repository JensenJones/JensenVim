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
      item.staged = x ~= ' ' and x ~= '?' and y == ' '
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
      local prefix = indent .. item.status .. (item.staged and '●' or ' ') .. ' '
      local name = file.name .. (item.old and ('  ← ' .. item.old) or '')
      local plus, minus = item.added > 0 and ('+' .. item.added) or '', item.removed > 0 and ('-' .. item.removed) or ''
      local stats = plus .. (plus ~= '' and minus ~= '' and ' ' or '') .. minus
      local text = prefix .. name .. (stats ~= '' and '  ' .. stats or '')
      local stats_start = #prefix + #name + 2
      add(text, { item = item }, {
        { #indent, #indent + 1, status_groups[item.status] },
        { #indent + 1, #prefix - 1, 'Added' },
        { stats_start, stats_start + #plus, 'Added' },
        { #text - #minus, #text, 'Removed' },
      })
    end
  end
  walk(build_tree(state.items), 0)
  add('')
  local hint = 's stage  c commit  f fold'
  add(hint, nil, { { 0, #hint, 'Comment' } })
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

-- Some terminal multiplexers leave stale cells after partial-width scrolls; repaint once scrolling settles.
local repaint = vim.uv.new_timer()
local function repaint_soon()
  repaint:stop()
  repaint:start(150, 0, vim.schedule_wrap(function()
    if valid() and vim.api.nvim_get_current_tabpage() == state.tab then vim.cmd 'redraw!' end
  end))
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
  repaint_soon()
end

function M.show_diff(item, focus, at_end)
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
      -- bufload reads a file whose swap another editor holds, but reports E325 as an error.
      local loaded, err = pcall(vim.fn.bufload, work_buf)
      if not vim.api.nvim_buf_is_loaded(work_buf) then
        vim.api.nvim_buf_delete(base_buf, { force = true })
        return vim.notify('Cannot open ' .. item.path .. ': ' .. tostring(err), vim.log.levels.ERROR)
      end
      if not loaded and tostring(err):find('E325', 1, true) then
        vim.bo[work_buf].readonly = true
        vim.notify(item.path .. ' is open in another editor; showing it read-only')
      end
      vim.bo[work_buf].buflisted = true
    else
      work_buf = scratch(('jvim-changes://deleted/%s'):format(item.path), {}, filetype)
    end
    state.work_win = vim.api.nvim_open_win(work_buf, false, { win = state.panel_win, split = 'right' })
    state.base_win = vim.api.nvim_open_win(base_buf, false, { win = state.work_win, split = 'left' })
    vim.wo[state.base_win].winbar = '%#Comment# HEAD  ' .. (item.old or item.path):gsub('%%', '%%%%')
    for _, win in ipairs { state.base_win, state.work_win } do
      vim.api.nvim_win_call(win, function() vim.cmd 'diffthis' end)
      vim.wo[win].foldenable = state.fold or false
    end
    vim.api.nvim_win_set_width(state.panel_win, state.width)
    vim.cmd 'wincmd ='
    vim.api.nvim_win_set_width(state.panel_win, state.width)
    vim.api.nvim_win_call(state.work_win, function()
      local line = at_end and vim.api.nvim_buf_line_count(0) or 1
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      if vim.fn.diff_hlID(line, 1) == 0 then vim.cmd('silent! normal! ' .. (at_end and '[c' or ']c')) end
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

local function file_rows()
  local rows = {}
  for row = 1, vim.api.nvim_buf_line_count(state.panel_buf) do
    if state.rows[row] and state.rows[row].item then rows[#rows + 1] = row end
  end
  return rows
end

-- Like IntelliJ's diff viewer: F7 walks changes and carries on into the next file.
function M.jump(forward)
  if not valid() then return end
  local current = vim.api.nvim_get_current_win()
  local in_diff = current == state.work_win or current == state.base_win
  if state.work_win and vim.api.nvim_win_is_valid(state.work_win) then
    local win = in_diff and current or state.work_win
    local before = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_call(win, function() vim.cmd('silent! normal! ' .. (forward and ']c' or '[c')) end)
    if vim.api.nvim_win_get_cursor(win)[1] ~= before then return end
  end
  local rows, at = file_rows(), nil
  for index, row in ipairs(rows) do
    if state.rows[row].item.path == state.shown then at = index end
  end
  local next_row = rows[(at or (forward and 0 or #rows + 1)) + (forward and 1 or -1)]
  if not next_row then return vim.notify(forward and 'Last change' or 'First change') end
  vim.api.nvim_win_set_cursor(state.panel_win, { next_row, 0 })
  M.show_diff(state.rows[next_row].item, in_diff, not forward)
end

local function items_under(row)
  if row.item then return { row.item } end
  return vim.tbl_filter(function(item) return vim.startswith(item.path, row.dir .. '/') end, state.items)
end

function M.toggle_stage()
  local row = valid() and target()
  if not row then return end
  local items = items_under(row)
  local paths, staged = {}, true
  for _, item in ipairs(items) do
    paths[#paths + 1] = item.path
    if item.old then paths[#paths + 1] = item.old end
    staged = staged and item.staged
  end
  if #paths == 0 then return end
  local args = staged and { 'reset', '-q', '--' } or { 'add', '-A', '--' }
  local ok, err = git(state.root, vim.list_extend(args, paths))
  if not ok then vim.notify('Git ' .. args[1] .. ' failed: ' .. tostring(err), vim.log.levels.ERROR) end
  M.refresh()
end

function M.commit()
  if not valid() then return end
  local root = state.root
  local everything = (git(root, { 'diff', '--cached', '--name-only' }) or '') == ''
  if everything then
    if #state.items == 0 then return vim.notify 'Nothing to commit' end
    if vim.fn.confirm('Nothing is staged. Commit all ' .. #state.items .. ' changed files?', '&Commit all\n&Cancel', 2) ~= 1 then return end
  end
  vim.ui.input({ prompt = 'Commit message' }, function(message)
    if not message or message:match '^%s*$' then return end
    if everything then git(root, { 'add', '-A' }) end
    local ok, err = git(root, { 'commit', '-q', '-m', message })
    if ok then vim.notify('Committed: ' .. message) else vim.notify('Commit failed: ' .. tostring(err), vim.log.levels.ERROR) end
    M.refresh()
  end)
end

function M.toggle_fold()
  if not valid() then return end
  state.fold = not state.fold
  for _, win in ipairs { state.base_win, state.work_win } do
    if win and vim.api.nvim_win_is_valid(win) then vim.wo[win].foldenable = state.fold end
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
  key('s', M.toggle_stage, 'Stage or unstage')
  key('c', M.commit, 'Commit')
  key('f', M.toggle_fold, 'Fold unchanged lines')
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
  vim.api.nvim_create_autocmd('User', { group = group, pattern = 'GitSignsUpdate', callback = function() vim.schedule(M.refresh) end })
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
