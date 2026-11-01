local M = {}

-- Neovim positions are byte offsets; keyboard motions count characters.
function M.previous(line, after)
  if after <= 0 then return 0 end
  local index = vim.fn.charidx(line, after - 1)
  return math.max(0, vim.fn.byteidx(line, index))
end

function M.distance(line, a, b)
  local first, last = math.min(a,b), math.max(a,b)
  return vim.fn.strchars(line:sub(first + 1, last), true)
end

local function identifier_spans(line)
  local spans, offset = {}, 0
  while offset < #line do
    local match = vim.fn.matchstrpos(line, [[\k\+]], offset)
    local first, after = match[2], match[3]
    if first < 0 then break end
    spans[#spans + 1] = { first, after }
    offset = math.max(after, first + 1)
  end
  return spans
end

function M.target(direction, insert_mode)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local col = cursor[2]
  local spans = identifier_spans(line)
  if direction > 0 then
    for _, span in ipairs(spans) do
      local first, after = span[1], span[2]
      if insert_mode then
        if col >= first and col < after then return after end
        if first >= col then return after end
      else
        if col >= first and col < M.previous(line, after) then return M.previous(line, after) end
        if first > col then return M.previous(line, after) end
      end
    end
  else
    for index = #spans, 1, -1 do
      local first, after = spans[index][1], spans[index][2]
      if insert_mode then
        if col > first and col <= after then return first end
        if after < col then return first end
      else
        if col > first then return first end
      end
    end
  end
  -- Once identifiers run out, consume the remaining punctuation instead of
  -- trapping the cursor at the final word (for example, begin|();).
  if direction > 0 then return insert_mode and #line or M.previous(line, #line) end
  return 0
end

function M.select(direction)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local target = M.target(direction, true)
  local distance = M.distance(vim.api.nvim_get_current_line(), target, cursor[2])
  if distance == 0 then return '' end
  return string.rep(direction > 0 and '<S-Right>' or '<S-Left>', distance)
end

return M
