local M = {}

function M.indent()
  local row = vim.v.lnum - 1
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ''
  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0)
  if parser_ok and line:match('^%s*%.[%a_]') then
    local trees = parser:parse()
    local col = #(line:match('^%s*') or '')
    local node = trees[1]:root():named_descendant_for_range(row, col, row, col)
    while node do
      if node:type() == 'initializer_list' then
        local first = node:named_child(0)
        if first then
          local first_row, first_col = first:start()
          if first_row < row then
            local anchor = vim.api.nvim_buf_get_lines(0, first_row, first_row + 1, false)[1]
            return vim.fn.strdisplaywidth(anchor:sub(1, first_col))
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
