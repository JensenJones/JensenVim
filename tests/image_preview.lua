vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local calls = { clear = 0, render = 0 }
package.loaded.image = {
  get_images = function(options)
    assert(options.buffer == vim.api.nvim_get_current_buf(), 'redraw targeted the wrong buffer')
    return { {
      clear = function() calls.clear = calls.clear + 1 end,
      render = function() calls.render = calls.render + 1 end,
    } }
  end,
}
local group = vim.api.nvim_create_augroup('image-preview-test', { clear = true })
require('jvim.image_preview').setup(group)
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, '/tmp/jvim-preview.png')
vim.bo[buf].filetype = 'image_nvim'
vim.bo[buf].buftype = 'nowrite'
vim.api.nvim_exec_autocmds('BufEnter', { buffer = buf })
vim.wait(1000, function() return calls.render > 0 end, 10)
assert(calls.clear == 1 and calls.render == 1, 'returning to an image did not clear and redraw it')
vim.cmd 'qall!'
