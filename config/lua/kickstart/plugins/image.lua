-- Kitty graphics are rendered by Herdr inside its panes.
return {
  '3rd/image.nvim',
  lazy = false,
  opts = {
    backend = 'kitty',
    processor = 'magick_cli',
    max_width_window_percentage = 96,
    max_height_window_percentage = 90,
    integrations = {
      markdown = { enabled = false },
      asciidoc = { enabled = false },
      neorg = { enabled = false },
      rst = { enabled = false },
      typst = { enabled = false },
      html = { enabled = false },
      css = { enabled = false },
    },
  },
  config = function(_, opts)
    -- Without a terminal (headless plugin installs) image.nvim cannot measure the screen and refuses to start.
    local ok, err = pcall(require('image').setup, opts)
    if not ok then
      if #vim.api.nvim_list_uis() > 0 then vim.notify('Image previews are unavailable: ' .. tostring(err), vim.log.levels.WARN) end
      return
    end
    require('jvim.image_preview').setup(vim.api.nvim_create_augroup('JvimImagePreview', { clear = true }))
  end,
}
