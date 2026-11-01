return {
  'folke/snacks.nvim',
  lazy = false,
  priority = 1000,
  opts = {
    input = {
      enabled = true,
      win = {
        keys = {
          -- jvim prompts confirm/cancel directly, without a Normal-mode step.
          i_esc = { '<Esc>', 'cancel', mode = { 'i', 's' } },
          i_cr = { '<CR>', 'confirm', mode = { 'i', 'n', 's' } },
        },
      },
    },
  },
}
