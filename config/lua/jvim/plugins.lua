local settings = require('jvim.config').get()

return {
  require 'jvim.plugins.input',

  {
    'mikavilpas/yazi.nvim',
    event = 'VeryLazy',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      open_for_directories = true,
    },
    keys = {
      { '<leader>y', '<cmd>Yazi<cr>', desc = 'Open yazi at current file' },
      { '<leader>Y', '<cmd>Yazi cwd<cr>', desc = 'Open yazi at cwd' },
      { '<C-up>', '<cmd>Yazi toggle<cr>', desc = 'Toggle yazi (resume)' },
    },
  },

  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {},
  },

  { -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' }, ---@diagnostic disable-line: missing-fields
        change = { text = '~' }, ---@diagnostic disable-line: missing-fields
        delete = { text = '_' }, ---@diagnostic disable-line: missing-fields
        topdelete = { text = '‾' }, ---@diagnostic disable-line: missing-fields
        changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
      },
    },
  },

  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      delay = 0,
      icons = { mappings = vim.g.have_nerd_font },

      spec = {
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } }, -- Enable gitsigns recommended keymaps first
        { 'gr', group = 'LSP Actions', mode = { 'n' } },
      },
    },
  },

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',

    enabled = true,
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',

        build = 'make',

        cond = function() return vim.fn.executable 'make' == 1 end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()

      require('telescope').setup {
        defaults = {
          mappings = {
            i = { ['<Esc>'] = require('telescope.actions').close },
          },
        },
        extensions = {
          ['ui-select'] = { require('telescope.themes').get_dropdown() },
        },
      }

      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('jvim.ui_select').setup)

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
        callback = function(event)
          local buf = event.buf

          vim.keymap.set('n', 'grr', builtin.lsp_references, { buffer = buf, desc = '[G]oto [R]eferences' })

          vim.keymap.set('n', 'gri', builtin.lsp_implementations, { buffer = buf, desc = '[G]oto [I]mplementation' })

          vim.keymap.set('n', 'gd', builtin.lsp_definitions, { buffer = buf, desc = '[G]oto [D]efinition' })

          vim.keymap.set('n', 'gO', builtin.lsp_document_symbols, { buffer = buf, desc = 'Open Document Symbols' })

          vim.keymap.set('n', 'gW', builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'Open Workspace Symbols' })

          vim.keymap.set('n', 'grt', builtin.lsp_type_definitions, { buffer = buf, desc = '[G]oto [T]ype Definition' })
        end,
      })

      vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code Action' })
      vim.keymap.set('n', '<leader>rn', function() require('jvim.rename').symbol() end, { desc = 'Rename symbol' })

      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      vim.keymap.set(
        'n',
        '<leader>s/',
        function()
          builtin.live_grep {
            grep_open_files = true,
            prompt_title = 'Live Grep in Open Files',
          }
        end,
        { desc = '[S]earch [/] in Open Files' }
      )

      vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config' } end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'mason-org/mason.nvim', enabled = settings.tools.mason, opts = { PATH = settings.tools.path } },
      { 'WhoIsSethDaniel/mason-tool-installer.nvim', enabled = settings.tools.mason and settings.tools.install },
      { 'j-hui/fidget.nvim', opts = {} },
    },
    config = function() require('jvim.lsp').setup() end,
  },

  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function() require('conform').format { async = true, lsp_format = 'fallback' } end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = require('jvim.formatting').on_save,
      formatters = require('jvim.formatting').options().formatters,
      formatters_by_ft = require('jvim.formatting').options().formatters_by_ft,
    },
  },

  { -- Autocompletion
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = { 'L3MON4D3/LuaSnip' },
    opts = {
      keymap = require('jvim.completion').keymap(),

      appearance = {
        nerd_font_variant = 'mono',
      },

      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = true },
      },

      sources = {
        default = function()
          local row, col = unpack(vim.api.nvim_win_get_cursor(0))
          local ok, node = pcall(vim.treesitter.get_node, { pos = { row - 1, math.max(col - 1, 0) } })
          if ok and node and node:type():find 'comment' then return {} end
          return { 'lsp', 'path', 'snippets', 'buffer' }
        end,
      },

      snippets = require('jvim.completion').snippets(),

      fuzzy = { implementation = settings.completion.fuzzy },

      signature = { enabled = true },
    },
  },

  {
    'folke/todo-comments.nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = false },
  },

  { -- Collection of various small independent plugins/modules
    'nvim-mini/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }

      require('mini.surround').setup()
      if settings.ui.tabline then
        require('mini.tabline').setup()
        require('jvim.files').setup_tabline()
      end
      if settings.ui.statusline then
        local statusline = require 'mini.statusline'
        statusline.setup { use_icons = settings.ui.icons }
        require('jvim.fold_controls').setup(statusline)
      end

    end,
  },

  {
    'HiPhish/rainbow-delimiters.nvim',
    lazy = false,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    init = function()
      vim.g.rainbow_delimiters = {
        highlight = {
          'RainbowDelimiterYellow', 'RainbowDelimiterBlue', 'RainbowDelimiterViolet',
          'RainbowDelimiterCyan', 'RainbowDelimiterOrange', 'RainbowDelimiterGreen',
          'RainbowDelimiterRed',
        },
      }
    end,
  },

  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    branch = 'main',
    config = function()
      require('jvim.namespace_indent').setup()
      if settings.treesitter.auto_install then require('nvim-treesitter').install(settings.treesitter.parsers) end

      local function treesitter_try_attach(buf, language)
        if not vim.treesitter.language.add(language) then return end
        vim.treesitter.start(buf, language)

        for _, win in ipairs(settings.features.folds and vim.api.nvim_list_wins() or {}) do
          if vim.api.nvim_win_get_buf(win) == buf then
            vim.wo[win].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
            vim.wo[win].foldmethod = 'expr'
            vim.wo[win].foldlevel = 99
          end
        end

        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end

      local available_parsers = require('nvim-treesitter').get_available()
      vim.api.nvim_create_autocmd('FileType', {
        callback = function(args)
          local buf, filetype = args.buf, args.match

          local language = vim.treesitter.language.get_lang(filetype)
          if not language then return end

          local installed_parsers = require('nvim-treesitter').get_installed 'parsers'

          if vim.tbl_contains(installed_parsers, language) then
            treesitter_try_attach(buf, language)
          elseif settings.treesitter.auto_install and vim.tbl_contains(available_parsers, language) then
            require('nvim-treesitter').install(language):await(function() treesitter_try_attach(buf, language) end)
          else
            treesitter_try_attach(buf, language)
          end
        end,
      })
    end,
  },

  { -- Render markdown in the buffer: styled headings, bullets, tables, code blocks
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    opts = {
      render_modes = true,
      anti_conceal = { enabled = false },
      debounce = 0,
      pipe_table = { preset = 'heavy' },
    },
  },

  vim.tbl_extend('force', require 'kickstart.plugins.neo-tree', { enabled = settings.features.project_tree }),
  vim.tbl_extend('force', require 'kickstart.plugins.image', { enabled = settings.features.pdf }),

}
