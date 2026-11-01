local M = {}
local entries, index, native = {}, nil, {}
local navigating = false
local resume = function() end

local function same(a, b)
  return a and b and a.buf == b.buf and a.row == b.row and a.col == b.col
end
local function push(entry)
  if same(entries[index or #entries], entry) then return end
  if index then
    for i = #entries, index + 1, -1 do entries[i] = nil end
    index = nil
  end
  entries[#entries + 1] = entry
  -- Keep long sessions bounded without retaining dead buffers indefinitely.
  if #entries > 500 then table.remove(entries, 1) end
end
local function native_entries()
  local result = {}
  for _, item in ipairs(vim.fn.getjumplist()[1]) do
    result[#result + 1] = { buf = item.bufnr, row = item.lnum, col = item.col }
  end
  return result
end
local function collect_native()
  local current = native_entries()
  -- Native jumps may remove an older duplicate from the middle of the list.
  -- Import only entries after the previous tail, rather than replaying the
  -- whole changed suffix and making old locations appear new again.
  local after = 0
  if #native > 0 then
    for i = #current, 1, -1 do
      if same(current[i], native[#native]) then after = i break end
    end
  end
  if not navigating then
    for i = after + 1, #current do
      local entry = current[i]
      if vim.api.nvim_buf_is_valid(entry.buf) and entry.row > 0 and vim.bo[entry.buf].buftype == ''
        and vim.api.nvim_buf_get_name(entry.buf) ~= '' then push(entry) end
    end
  end
  native = current
end
function M.remember(buf, position)
  if navigating then return false end
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not buf or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= ''
    or vim.api.nvim_buf_get_name(buf) == '' then return false end
  collect_native()
  if not position then
    local win = vim.fn.bufwinid(buf)
    if win < 0 then return false end
    position = vim.api.nvim_win_get_cursor(win)
  end
  push { buf = buf, row = position[1], col = position[2] }
  return true
end
local function travel(direction)
  collect_native()
  if not index then
    if direction > 0 then return end
    local in_editor = M.remember(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0))
    index = #entries + (in_editor and 0 or 1)
  end
  local next_index = index + direction
  while next_index >= 1 and next_index <= #entries do
    local entry = entries[next_index]
    if vim.api.nvim_buf_is_valid(entry.buf) then
      navigating = true
      local ok, err = pcall(function()
        require('jvim.files').show(entry.buf)
        local row = math.max(1, math.min(entry.row, vim.api.nvim_buf_line_count(entry.buf)))
        local line = vim.api.nvim_buf_get_lines(entry.buf, row - 1, row, false)[1]
        vim.api.nvim_win_set_cursor(0, { row, math.min(entry.col, #line) })
      end)
      navigating = false
      native = native_entries()
      if not ok then vim.notify(err, vim.log.levels.WARN) else index = next_index end
      resume()
      return
    end
    next_index = next_index + direction
  end
end
function M.back() travel(-1) end
function M.forward() travel(1) end
function M.setup(resume_editing)
  resume = resume_editing or resume
  collect_native()
  local group = vim.api.nvim_create_augroup('JvimNavigationHistory', { clear = true })
  vim.api.nvim_create_autocmd('BufLeave', { group = group, callback = function(args) M.remember(args.buf) end })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, { group = group, callback = collect_native })
end
return M
