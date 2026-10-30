local M = {}

local lists = {
  argument_list = true, parameter_list = true, initializer_list = true,
  template_argument_list = true, template_parameter_list = true,
}

local function column(node)
  local row, col = node:start()
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  return vim.fn.strdisplaywidth(line:sub(1, col))
end

function M.indent()
  local row = vim.v.lnum - 1
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ''
  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0)
  local previous = row > 0 and vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
  local comma = previous:find(',%s*$')
  -- During Enter, the new line may be empty or contain only the old closing
  -- suffix. Locate its list from the preceding comma instead of that suffix.
  local pending = comma and (not line:find('%S')
    or (vim.fn.mode():sub(1, 1) == 'i'
      and vim.api.nvim_win_get_cursor(0)[2] <= #(line:match('^%s*') or '')))
  if parser_ok and (pending or (line:find('%S') and not line:match('^%s*[%)%]%}]'))) then
    local trees = parser:parse()
    local col = #(line:match('^%s*') or '')
    local lookup_row, lookup_col = pending and row - 1 or row, pending and comma - 1 or col
    local node = trees[1]:root():named_descendant_for_range(lookup_row, lookup_col, lookup_row, lookup_col)
    while node do
      if node:type() == 'conditional_expression' and line:match('^%s*[?:]') then
        for child in node:iter_children() do
          if child:type() == '?' then
            local question_row = child:start()
            if question_row < row then return column(child) end
            local condition = node:named_child(0)
            if condition and condition:start() < row then
              return column(condition) + vim.fn.shiftwidth()
            end
          end
        end
      elseif lists[node:type()] then
        -- Leading commas align with the first separator; other continuations
        -- align with the first argument/parameter/initializer in the list.
        if line:match('^%s*,') then
          for child in node:iter_children() do
            if child:type() == ',' and child:start() < row then return column(child) end
          end
        end
        local first
        for child in node:iter_children() do
          if child:named() and child:type() ~= 'comment' then first = child; break end
        end
        if first then
          local first_row = first:start()
          if first_row < row then
            return column(first)
          end
        end
        break
      end
      node = node:parent()
    end
  end
  local ok, treesitter = pcall(require, 'nvim-treesitter')
  if parser_ok and ok then return treesitter.indentexpr() end
  return vim.fn.cindent(vim.v.lnum)
end

return M
