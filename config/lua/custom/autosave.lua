local M = {}

function M.save_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].modified
      and not vim.bo[buf].readonly and vim.bo[buf].modifiable
      and vim.api.nvim_buf_get_name(buf) ~= '' and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 0 then
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd 'silent update' end)
      if not ok then vim.notify('Autosave failed: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimAutosave', { clear = true })
  local generation = 0
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    callback = function()
      generation = generation + 1
      local pending = generation
      vim.defer_fn(function() if pending == generation then M.save_all() end end, 800)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'FocusLost', 'VimLeavePre' }, { group = group, callback = M.save_all })
end

return M
