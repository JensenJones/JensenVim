local M = {}

function M.setup()
  vim.treesitter.query.add_predicate('jvim-namespace-indented?', function(match, _, _, predicate)
    local body = match[predicate[2]][1]
    local namespace_row, namespace_column = body:parent():start()
    for child in body:iter_children() do
      if child:named() and child:type() ~= 'comment' then
        local row, column = child:start()
        return row > namespace_row and column > namespace_column
      end
    end
    -- Empty namespaces follow jvim's default until their contents establish
    -- a style. Existing flush-left namespaces must not gain an extra level.
    return true
  end, { force = true })
end

return M
