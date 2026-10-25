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
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  ---@module 'neo-tree'
  ---@type neotree.Config
  opts = {
    window = { width = 30 },
    filesystem = {
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true,
      window = {
        mappings = {
          ['\\'] = 'close_window',
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
