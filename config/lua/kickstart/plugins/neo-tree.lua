-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

---@module 'lazy'
---@type LazySpec
return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  ---@module 'neo-tree'
  ---@type neotree.Config
  opts = {
    window = { width = 30 },
    filesystem = {
      -- custom.files owns directory startup and removes its placeholder.
      hijack_netrw_behavior = 'disabled',
      components = {
        name = function(config, node, state)
          local result = require('neo-tree.sources.common.components').name(config, node, state)
          if node.type == 'directory' and node:get_depth() == 1 then
            local name = vim.fs.basename(vim.fs.normalize(node.path))
            result.text = name ~= '' and name or node.path
          end
          return result
        end,
      },
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true,
      window = {
        mappings = {
          ['\\'] = 'close_window',
          -- macOS Delete sends Backspace; don't let it silently change roots.
          ['<BS>'] = 'none',
          ['<Del>'] = 'none',
          ['<Left>'] = 'close_node',
          ['<Right>'] = 'open',
          ['<2-LeftMouse>'] = 'none',
          ['<LeftMouse>'] = function(state)
            local mouse = vim.fn.getmousepos()
            if mouse.winid ~= state.winid or mouse.line < 1 or mouse.line > vim.api.nvim_buf_line_count(state.bufnr) then return end
            vim.api.nvim_set_current_win(state.winid)
            vim.api.nvim_win_set_cursor(state.winid, { mouse.line, 0 })
            state.commands.open(state)
          end,
        },
      },
    },
  },
}
