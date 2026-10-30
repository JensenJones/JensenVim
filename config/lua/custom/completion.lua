local M = {}

-- Keep LSP placeholder defaults, but insert them as ordinary editable text.
-- Snippet engines select placeholders by injecting Normal-mode commands;
-- those commands can race with modeless mouse/keyboard selections.
function M.expand(body)
  local utils = require 'blink.cmp.sources.snippets.utils'
  local parsed = utils.safe_parse(body)
  if not parsed then error('Cannot parse completion snippet') end
  local lines = vim.split(utils.add_current_line_indentation(tostring(parsed)), '\n', { plain = true })
  local position = vim.api.nvim_win_get_cursor(0)
  local row, col = position[1] - 1, position[2]
  vim.api.nvim_buf_set_text(0, row, col, row, col, lines)
  vim.api.nvim_win_set_cursor(0, {
    row + #lines,
    #lines == 1 and col + #lines[1] or #lines[#lines],
  })
end

function M.snippets()
  return {
    expand = M.expand,
    active = function() return false end,
    jump = function() end,
  }
end

return M
