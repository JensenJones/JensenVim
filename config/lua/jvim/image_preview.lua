local M = {}

function M.setup(group)
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'image_nvim' then return end
      local win = vim.api.nvim_get_current_win()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) or not vim.api.nvim_win_is_valid(win)
          or vim.api.nvim_win_get_buf(win) ~= args.buf then return end
        local ok, image = pcall(require, 'image')
        if not ok then return end
        local images = image.get_images({ window = win, buffer = args.buf })
        for _, preview in ipairs(images) do
          preview:clear()
          preview:render()
        end
      end)
    end,
  })
end

return M
