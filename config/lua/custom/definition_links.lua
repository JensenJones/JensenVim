local M = {}

function M.jump(win, buf, row, col)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return 0 end
  if row < 1 or row > vim.api.nvim_buf_line_count(buf) then return 0 end
  vim.cmd "normal! m'"
  vim.api.nvim_set_current_win(win)
  if vim.api.nvim_win_get_buf(win) ~= buf then vim.api.nvim_win_set_buf(win, buf) end
  local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  vim.api.nvim_win_set_cursor(win, { row, math.min(col, #text) })
  vim.lsp.buf.definition()
  return 1
end

function M.setup()
  local token = vim.env.JVIM_LINK_TOKEN
  if not token or #token ~= 32 or not token:match '^[a-f0-9]+$' then return end
  local root = vim.fn.expand '~/.local/state/jvim/jvim-links'
  vim.fn.mkdir(root, 'p', 448)
  local registry = root .. '/' .. token .. '.json'
  if vim.v.servername == '' then vim.fn.serverstart() end
  vim.fn.writefile({ vim.json.encode { socket = vim.v.servername } }, registry)
  vim.uv.fs_chmod(registry, 384)
  local ns = vim.api.nvim_create_namespace 'jvim-definition-links'
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, buf)
      if vim.bo[buf].buftype ~= '' then return false end
      return #vim.lsp.get_clients { bufnr = buf, method = 'textDocument/definition' } > 0
    end,
    on_line = function(_, win, buf, row)
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      local offset = 1
      while true do
        local first, last = line:find('[%a_][%w_]*', offset)
        if not first then break end
        local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, first - 1 } })
        local kind = ok and node and node:type() or 'identifier'
        if kind:find('identifier', 1, true) or kind:find('name', 1, true) then
          local url = ('jvim-definition://%s/%d/%d/%d/%d'):format(token, win, buf, row + 1, first - 1)
          vim.api.nvim_buf_set_extmark(buf, ns, row, first - 1, { end_col = last, url = url, ephemeral = true })
        end
        offset = last + 1
      end
    end,
  })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('jvim-definition-links', { clear = true }),
    callback = function()
      vim.schedule(function() vim.cmd.redraw() end)
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = 'jvim-definition-links',
    callback = function() vim.uv.fs_unlink(registry) end,
  })
  vim.keymap.set({ 'n', 'i' }, '<C-LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= 0 and vim.api.nvim_win_is_valid(mouse.winid) then
      M.jump(mouse.winid, vim.api.nvim_win_get_buf(mouse.winid), mouse.line, math.max(0, mouse.column - 1))
    end
  end, { desc = 'Go to clicked symbol definition' })
end

return M
