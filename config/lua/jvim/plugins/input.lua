return {
  'folke/snacks.nvim',
  lazy = false,
  priority = 1000,
  opts = {
    input = {
      enabled = true,
      win = {
        -- Clicking elsewhere cancels the prompt instead of leaving it floating over the editor.
        on_win = function(win)
          win:on('WinLeave', function(self)
            vim.schedule(function() if self:valid() then self:execute 'cancel' end end)
          end, { buf = true })
        end,
        keys = {
          -- jvim prompts confirm/cancel directly, without a Normal-mode step.
          i_esc = { '<Esc>', 'cancel', mode = { 'i', 's' } },
          i_cr = { '<CR>', 'confirm', mode = { 'i', 'n', 's' } },
        },
      },
    },
  },
}
