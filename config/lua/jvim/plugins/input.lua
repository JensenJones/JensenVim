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
          -- Like IntelliJ, a prefilled value starts selected so typing replaces it and Enter reuses it.
          vim.schedule(function()
            if win:valid() and vim.api.nvim_get_current_win() == win.win and win:text() ~= '' then
              vim.api.nvim_feedkeys(vim.keycode '<Home><S-End>', 'n', false)
            end
          end)
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
