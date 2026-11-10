local M = {}
local configured = false
local keymaps_configured = false

local function inside_snippet(ls)
  local snippet = ls.get_active_snip()
  if not snippet then return false end
  local ok, first, last = pcall(snippet.mark.pos_begin_end, snippet.mark)
  if not ok then return false end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  return (row > first[1] or row == first[1] and col >= first[2])
    and (row < last[1] or row == last[1] and col <= last[2])
end

function M.stop()
  local ls = package.loaded.luasnip
  if not ls then return end
  while ls.session.current_nodes[vim.api.nvim_get_current_buf()] do ls.unlink_current() end
end

local function engine()
  local ls = require 'luasnip'
  if not configured then
    ls.config.setup {
      keep_roots = false,
      link_roots = false,
      exit_roots = true,
      -- Jumps update dependent fields. Automatic cursor restoration during
      -- editing races with modeless mouse and Shift+arrow selections.
      update_events = 'User',
      delete_check_events = 'TextChanged,TextChangedI',
    }
    -- LuaSnip requires an update event. Remove its catch-all User listener
    -- so unrelated plugins' User events cannot restore an old selection.
    vim.api.nvim_clear_autocmds { group = 'luasnip', event = 'User' }
    local group = vim.api.nvim_create_augroup('jvim-completion-placeholders', { clear = true })
    vim.api.nvim_create_autocmd('BufLeave', {
      group = group,
      callback = M.stop,
    })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = function()
        if not ls.session.jump_active and not inside_snippet(ls) then M.stop() end
      end,
    })
    configured = true
  end
  return ls
end

function M.snippets()
  return {
    preset = 'luasnip',
    expand = function(body) engine().lsp_expand(body) end,
    active = function(filter)
      local ls = engine()
      return inside_snippet(ls) and ls.locally_jumpable(filter and filter.direction or 1)
    end,
    jump = function(direction)
      local ls = engine()
      if ls.locally_jumpable(direction) then ls.jump(direction) end
    end,
  }
end

-- Execute after the expression mapping unlocks buffer edits, but before any
-- following typed characters. vim.schedule would let rapid typing overtake
-- accepting the completion or selecting its next argument.
local function queue(call)
  vim.api.nvim_feedkeys(vim.keycode('<Cmd>lua require("jvim.completion").' .. call .. '<CR>'), 'ni', false)
  return true
end

function M.accept(range)
  local config = require('blink.cmp.config').completion
  config.keyword.range = range
  -- This is the operation Blink's public select_and_accept schedules. The
  -- <Cmd> queue already provides its required separation from the expr map.
  local list = require 'blink.cmp.completion.list'
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local before = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local done = false
  local accepted = list.accept { index = list.selected_item_idx or 1, callback = function() done = true end }
  if accepted then
    -- Resolve is asynchronous (and bounded by Blink's resolve timeout). Keep
    -- the input loop here until insertion occurs, while servicing LSP/timer
    -- events, so following argument text cannot be replaced by a late edit.
    vim.wait(config.accept.resolve_timeout_ms + 1000, function()
      return done or not vim.api.nvim_buf_is_valid(buf)
        or vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] ~= before
    end, 1)
  end
end

function M.jump(direction)
  M.snippets().jump(direction)
end

local function hide_menu(cmp) cmp.hide() end

local function jump_key(direction)
  return function()
    if M.snippets().active { direction = direction } then return queue('jump(' .. direction .. ')') end
  end
end

function M.keymap()
  if not keymaps_configured then
    -- Modeless buffer switches do not necessarily emit InsertEnter, the event
    -- Blink normally uses to install its buffer-local completion bindings.
    vim.api.nvim_create_autocmd('BufEnter', {
      group = vim.api.nvim_create_augroup('jvim-completion-keymaps', { clear = true }),
      callback = function(args)
        vim.schedule(function()
          local apply = package.loaded['blink.cmp.keymap.apply']
          if not apply or vim.api.nvim_get_current_buf() ~= args.buf or vim.fn.mode() ~= 'i' then return end
          local config = require 'blink.cmp.config'
          if config.enabled() then
            apply.keymap_to_current_buffer(require('blink.cmp.keymap').get_mappings(config.keymap, 'default'))
          end
        end)
      end,
    })
    keymaps_configured = true
  end
  return {
    preset = 'super-tab',
    -- Navigate suggestions with arrows while the menu is open; otherwise let
    -- Neovim move the cursor as usual.
    ['<Left>'] = { hide_menu, 'fallback' },
    ['<Right>'] = { hide_menu, 'fallback' },
    ['<Up>'] = { 'select_prev', 'fallback' },
    ['<Down>'] = { 'select_next', 'fallback' },
    ['<Tab>'] = {
      function(cmp)
        if cmp.is_menu_visible() then return queue("accept('full')") end
      end,
      jump_key(1),
      'fallback',
    },
    ['<S-Tab>'] = { jump_key(-1), 'fallback' },
    ['<CR>'] = {
      function(cmp)
        if not cmp.is_menu_visible() then return false end
        return queue("accept('prefix')")
      end,
      'fallback',
    },
  }
end

return M
