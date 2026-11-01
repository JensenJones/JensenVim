local M = {}

function M.setup()
  require('telescope').load_extension 'ui-select'
  local select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    -- Telescope queues an append command for its prompt. Cancel any pending
    -- modeless startinsert so that command cannot become a literal 'A'.
    vim.cmd.stopinsert()
    return select(items, opts, on_choice)
  end
end

return M
