local M = {}

function M.initialize_file(path)
  if not path:lower():match('%.hpp$') then return end
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= 'file' or stat.size ~= 0 then return end
  vim.fn.writefile({ '#pragma once', '' }, path)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimCppHeader', { clear = true })
  vim.api.nvim_create_autocmd('BufNewFile', {
    group = group,
    pattern = '*.hpp',
    callback = function(args)
      vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, { '#pragma once', '' })
    end,
  })
end

return M
