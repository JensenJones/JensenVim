local M = {}
local sessions = {}

local function marker(line)
  local prefix = line:match('^([<>=|]+)')
  if not prefix or #prefix < 7 or prefix:find('[^' .. prefix:sub(1, 1) .. ']') then return end
  local kind = prefix:sub(1, 1)
  if kind == '=' and line:sub(#prefix + 1):match('%S') then return end
  return kind, #prefix
end

-- Parse the current buffer every time: manual edits must never leave stale
-- coordinates capable of replacing unrelated text.
function M.parse(lines)
  local conflicts, current, part, width = {}, nil, nil, nil
  for row, line in ipairs(lines) do
    local kind, count = marker(line)
    if kind then
      local invalid = 'Malformed conflict marker at line ' .. row
      if kind == '<' then
        if current then return nil, invalid .. ' (nested conflict)' end
        current, part, width = { first = row, ours = {}, theirs = {} }, 'ours', count
      elseif not current or count ~= width then
        return nil, invalid
      elseif kind == '|' then
        if part ~= 'ours' or current.base then return nil, invalid end
        current.base, part = {}, 'base'
      elseif kind == '=' then
        if part == 'theirs' then return nil, invalid end
        part = 'theirs'
      elseif kind == '>' then
        if part ~= 'theirs' then return nil, invalid end
        current.last = row
        conflicts[#conflicts + 1] = current
        current, part, width = nil, nil, nil
      end
    elseif current then
      table.insert(current[part], line)
    end
  end
  if current then return nil, 'Unclosed conflict marker at line ' .. current.first end
  return conflicts
end

function M.resolve(buf, index, choice)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then return nil, 'Result buffer is not editable' end
  local conflicts, err = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not conflicts then return nil, err end
  local conflict = conflicts[index]
  if not conflict then return nil, 'No conflict selected' end
  if choice ~= 'ours' and choice ~= 'theirs' and choice ~= 'both' and choice ~= 'base' then return nil, 'Unknown conflict choice' end
  if choice == 'base' and not conflict.base then return nil, 'This conflict has no base' end
  local replacement = vim.deepcopy(choice == 'both' and conflict.ours or conflict[choice])
  if choice == 'both' then vim.list_extend(replacement, conflict.theirs) end
  -- nvim_buf_call creates an independent undo boundary for an action, including
  -- when invoked by a mouse callback while the result was in Insert mode.
  vim.api.nvim_buf_call(buf, function()
    vim.cmd('let &undolevels = &undolevels')
    vim.api.nvim_buf_set_lines(buf, conflict.first - 1, conflict.last, false, replacement)
    vim.cmd('let &undolevels = &undolevels')
  end)
  return true
end

local function current()
  return sessions[vim.api.nvim_get_current_tabpage()]
end

local function report(err)
  vim.notify(err, vim.log.levels.WARN)
  return nil, err
end

local function materialize(lines, conflicts, side)
  local result, first = {}, 1
  for _, conflict in ipairs(conflicts) do
    for row = first, conflict.first - 1 do result[#result + 1] = lines[row] end
    vim.list_extend(result, conflict[side] or conflict.ours)
    first = conflict.last + 1
  end
  for row = first, #lines do result[#result + 1] = lines[row] end
  return result
end

local function refresh(session)
  if not vim.api.nvim_buf_is_valid(session.buf) then return end
  local lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  local conflicts, err = M.parse(lines)
  session.error = err
  if not conflicts then return end
  session.count = #conflicts
  for index, buf in ipairs(session.previews) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, materialize(lines, conflicts, session.sides[index]))
      vim.bo[buf].modifiable = false
    end
  end
  if vim.api.nvim_win_is_valid(session.win) then
    vim.wo[session.win].winbar = '%#StatusLine# Result  ' .. #conflicts .. ' conflicts  '
      .. '%@JvimMergeOurs@[Ours]%T %@JvimMergeTheirs@[Theirs]%T %@JvimMergeBoth@[Both]%T '
      .. '%@JvimMergePrevious@[Previous]%T %@JvimMergeNext@[Next]%T %@JvimMergeClose@[Close]%T'
  end
end

function M.navigate(direction)
  local session = current()
  if not session or not vim.api.nvim_win_is_valid(session.win) then return nil end
  local conflicts, err = M.parse(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
  if not conflicts then return report(err) end
  if #conflicts == 0 then return report('No unresolved conflicts') end
  local row = vim.api.nvim_win_get_cursor(session.win)[1]
  local target
  if direction > 0 then
    for index, conflict in ipairs(conflicts) do if conflict.first > row then target = index; break end end
    target = target or 1
  else
    for index = #conflicts, 1, -1 do if conflicts[index].first < row then target = index; break end end
    target = target or #conflicts
  end
  session.index = target
  vim.api.nvim_set_current_win(session.win)
  vim.api.nvim_win_set_cursor(session.win, { conflicts[target].first, 0 })
  return true
end

function M.accept(choice)
  local session = current()
  if not session or not vim.api.nvim_win_is_valid(session.win) then return report('Open conflict resolution first') end
  local conflicts, err = M.parse(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false))
  if not conflicts then return report(err) end
  local row = vim.api.nvim_win_get_cursor(session.win)[1]
  local index = math.min(session.index or 1, #conflicts)
  for candidate, conflict in ipairs(conflicts) do
    if row >= conflict.first and row <= conflict.last then index = candidate; break end
  end
  local ok
  ok, err = M.resolve(session.buf, index, choice)
  if not ok then return report(err) end
  refresh(session)
  return true
end

function M.close()
  local session = current()
  if not session then return end
  sessions[session.tab] = nil
  if session.group then vim.api.nvim_del_augroup_by_id(session.group) end
  if #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd.tabclose()
  else
    -- Keep the editable result even if the user already closed the origin tab.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= session.win then pcall(vim.api.nvim_win_close, win, true) end
    end
  end
  if vim.api.nvim_win_is_valid(session.win) then
    vim.api.nvim_win_call(session.win, function() vim.cmd.diffoff() end)
    vim.wo[session.win].winbar = ''
  end
  for _, buf in ipairs(session.previews) do
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
end

local function setup_clicks()
  local functions = {
    Ours = "accept('ours')", Theirs = "accept('theirs')", Both = "accept('both')",
    Previous = 'navigate(-1)', Next = 'navigate(1)', Close = 'close()',
  }
  for name, call in pairs(functions) do
    vim.api.nvim_exec2('function! JvimMerge' .. name .. '(minwid, clicks, button, mods)\n'
      .. 'call luaeval("require(\'jvim.merge\').' .. call .. '")\nendfunction', {})
  end
end

function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' or not vim.bo[buf].modifiable then
    return report('Select an editable file to resolve conflicts')
  end
  local conflicts, err = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not conflicts then return report(err) end
  if #conflicts == 0 then return report('No conflict markers in this file') end
  for tab, session in pairs(sessions) do
    if session.buf == buf and vim.api.nvim_tabpage_is_valid(tab) and vim.api.nvim_win_is_valid(session.win) then
      vim.api.nvim_set_current_tabpage(tab)
      vim.api.nvim_set_current_win(session.win)
      return session
    end
  end
  setup_clicks()
  vim.cmd.stopinsert()
  vim.cmd.tabnew()
  local placeholder = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_delete(placeholder, { force = true })
  local session = { tab = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win(), buf = buf,
    previews = {}, sides = { 'ours', 'theirs' }, index = 1 }
  for _, conflict in ipairs(conflicts) do
    if conflict.base then session.sides[#session.sides + 1] = 'base'; break end
  end
  sessions[session.tab] = session
  local filetype = vim.bo[buf].filetype
  for _, side in ipairs(session.sides) do
    local preview = vim.api.nvim_create_buf(false, true)
    vim.bo[preview].bufhidden = 'wipe'
    vim.bo[preview].filetype = filetype
    vim.bo[preview].readonly = true
    vim.bo[preview].modifiable = false
    session.previews[#session.previews + 1] = preview
    vim.cmd 'leftabove vsplit'
    vim.api.nvim_win_set_buf(0, preview)
    vim.wo.winbar = side:sub(1, 1):upper() .. side:sub(2) .. ' (read only)'
    vim.cmd.diffthis()
  end
  vim.api.nvim_set_current_win(session.win)
  vim.cmd.diffthis()
  session.group = vim.api.nvim_create_augroup('JvimMerge' .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = session.group, buffer = buf,
    callback = function() refresh(session) end,
  })
  refresh(session)
  vim.api.nvim_win_set_cursor(session.win, { conflicts[1].first, 0 })
  return session
end

function M.current() return current() end

return M
