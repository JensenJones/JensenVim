local M = {}

function M.on_save(bufnr)
  -- Autosave persists edits and undo exactly; explicit saves can format.
  if vim.b[bufnr].jvim_autosaving then return nil end
  return { timeout_ms = 500, lsp_format = 'fallback' }
end

return M
