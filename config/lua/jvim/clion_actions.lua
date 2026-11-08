local M = {}

function M.setup(action, resume_editing)
  local map = vim.keymap.set
  local group = vim.api.nvim_create_augroup('clion-ordinary-editing', { clear = true })
  local selections = {}
  local editing = require 'jvim.editing'
  -- Escape cancels UI and selection; it never makes ordinary typing into commands.
  map('i', '<Esc>', function()
    selections[vim.api.nvim_get_current_buf()] = nil
    require('jvim.completion').stop()
    if package.loaded['blink.cmp'] then require('blink.cmp').hide() end
    vim.cmd.nohlsearch()
  end, { desc = 'Cancel completion' })
  map('s', '<Esc>', function()
    selections[vim.api.nvim_get_current_buf()] = nil
    require('jvim.completion').stop()
    local position = vim.api.nvim_win_get_cursor(0)
    vim.cmd 'normal! \27'
    vim.api.nvim_win_set_cursor(0, position)
    vim.cmd.startinsert()
  end, { desc = 'Cancel selection' })
  -- Mouse highlighting enters Select mode, where ordinary typing replaces
  -- the selection. Treat opening delimiters as surround actions instead.
  for opener, closer in pairs {
    ['('] = ')', ['['] = ']', ['{'] = '}', ['<'] = '>',
    ['"'] = '"', ["'"] = "'", [string.char(96)] = string.char(96),
  } do
    map('s', opener, function()
      local anchor, cursor = vim.fn.getpos 'v', vim.fn.getpos '.'
      local forward = anchor[2] < cursor[2] or (anchor[2] == cursor[2] and anchor[3] <= cursor[3])
      local first, last = forward and anchor or cursor, forward and cursor or anchor
      local exclusive = vim.o.selection == 'exclusive'
      local selected = vim.fn.getregion(anchor, cursor, { type = 'v', exclusive = exclusive })
      if #selected == 0 then selected = { '' } end
      local start_row, start_col = first[2] - 1, first[3] - 1
      local end_row, end_col = last[2] - 1, last[3] - 1 + (exclusive and 0 or 1)
      vim.cmd 'normal! \27'
      selected[1] = opener .. selected[1]
      selected[#selected] = selected[#selected] .. closer
      vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, selected)
      vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col + (#selected == 1 and #opener or 0) })
      vim.cmd.startinsert()
    end, { desc = 'Surround selection with ' .. opener .. closer })
  end
  -- Some selection paths leave Visual mode active. Printable input must still
  -- replace the selection, rather than execute operators or text objects.
  -- Remap the character in Select mode so delimiter-surround actions also work.
  for byte = 32, 126 do
    local char = string.char(byte)
    local key = char == '<' and '<lt>' or char
    map('x', key, '<C-g>' .. key, { remap = true, nowait = true, desc = 'Type over selection' })
  end
  for _, key in ipairs { '<BS>', '<Del>' } do
    map('x', key, '"_c', { desc = 'Delete highlighted text' })
    map('s', key, '<C-g>"_c', { desc = 'Delete highlighted text' })
  end
  map('n', '<Esc>', function()
    vim.cmd.nohlsearch()
    resume_editing()
  end, { desc = 'Cancel and resume editing' })
  vim.api.nvim_create_autocmd('CmdlineLeave', { group = group, callback = function() vim.schedule(resume_editing) end })

  -- Mouse positions join the same timeline as native LSP/definition jumps.
  local history = require 'jvim.navigation_history'
  history.setup(resume_editing)
  vim.on_key(function(_, typed)
    if typed ~= '' and vim.fn.keytrans(typed) == '<LeftMouse>' then
      local buf = vim.api.nvim_get_current_buf()
      local position = vim.api.nvim_win_get_cursor(0)
      selections[buf] = nil
      -- Recording is pure Lua/API bookkeeping, so it can happen before the
      -- click even when a caller immediately asks to navigate backward.
      history.remember(buf, position)
      vim.schedule(function()
        if vim.fn.mode() == 'n' then resume_editing() end
      end)
    end
  end, vim.api.nvim_create_namespace 'clion-mouse-history')
  action({ '<F33>', '<D-M-Left>', '<D-[>' }, history.back, 'Navigate back')
  action({ '<F34>', '<D-M-Right>', '<D-]>' }, history.forward, 'Navigate forward')

  action({ '<F35>39', '<C-M-b>', '<D-M-b>' }, vim.lsp.buf.implementation, 'Go to implementation')
  action({ '<F35>40', '<D-S-b>', '<C-S-b>' }, vim.lsp.buf.type_definition, 'Go to type declaration')
  action({ '<F35>41', '<F1>', '<C-j>' }, vim.lsp.buf.hover, 'Quick documentation')
  action({ '<F35>42', '<D-p>', '<C-p>' }, vim.lsp.buf.signature_help, 'Parameter info')
  action({ '<F35>43', '<D-F12>', '<C-F12>', '<D-7>' }, vim.lsp.buf.document_symbol, 'File structure')
  action({ '<F35>44', '<D-M-o>' }, function() require('jvim.pickers').open('lsp_dynamic_workspace_symbols') end, 'Find symbol')
  action({ '<F35>46', '<D-l>' }, function()
    local context = editing.capture()
    vim.ui.input({ prompt = 'Go to line:column: ' }, function(value)
      if not value then return end
      local row, col = value:match '^(%d+):?(%d*)$'
      if not row then return end
      context:apply(function()
        row = math.max(1, math.min(tonumber(row), vim.api.nvim_buf_line_count(0)))
        vim.api.nvim_win_set_cursor(0, { row, math.max(0, tonumber(col) and tonumber(col) - 1 or 0) })
      end)
      resume_editing()
    end)
  end, 'Go to line')
  action({ '<F35>47', '<C-r>', '<D-r>' }, function()
    local context = editing.capture()
    vim.ui.input({ prompt = 'Replace in file — find: ' }, function(find)
      if not find or find == '' then return end
      vim.ui.input({ prompt = 'Replace with: ' }, function(replacement)
        if replacement == nil then return end
        local pattern = '\\V' .. vim.fn.escape(find, '\\/')
        local value = vim.fn.escape(replacement, '\\/&')
        context:apply(function() vim.cmd('%s/' .. pattern .. '/' .. value .. '/gce') end)
        resume_editing()
      end)
    end)
  end, 'Replace in file (confirm each match)')
  action({ '<F35>48', '<D-S-r>' }, function() require('jvim.project_replace').open() end, 'Replace in project (preview and confirmation)')
  local last_search = ''
  action({ '<F30>', '<D-f>', '<C-f>' }, function()
    local context = editing.capture()
    vim.ui.input({ prompt = 'Find in file: ', default = last_search }, function(query)
      if not query or query == '' then return end
      last_search = query
      local pattern = '\\V' .. vim.fn.escape(query, '\\')
      vim.fn.setreg('/', pattern)
      vim.o.hlsearch = true
      context:apply(function()
        vim.cmd "normal! m'"
        if vim.fn.search(pattern, 'cw') == 0 then vim.notify('No matches for ' .. query) end
      end)
      resume_editing()
    end)
  end, 'Find in file')
  action({ '<F35>54', '<F2>' }, function() vim.diagnostic.jump { count = 1, float = true } end, 'Next problem')
  action({ '<F35>55', '<S-F2>' }, function() vim.diagnostic.jump { count = -1, float = true } end, 'Previous problem')
  action({ '<F35>56', '<D-g>', '<F3>' }, function() vim.cmd 'normal! n' end, 'Next search match')
  action({ '<F35>57', '<D-S-g>', '<S-F3>' }, function() vim.cmd 'normal! N' end, 'Previous search match')
  action({ '<F35>58', '<D-M-->' }, function() vim.cmd 'silent! normal! zc' end, 'Collapse code fold')
  action({ '<F35>59', '<D-M-=>' }, function() vim.cmd 'silent! normal! zo' end, 'Expand code fold')
  action({ '<F35>60' }, function() vim.cmd 'normal! %' end, 'Go to matching bracket')
  action({ '<F35>61', '<C-S-BS>' }, function() vim.cmd 'normal! g;' end, 'Last edit location')
  action({ '<F35>62', '<C-S-e>' }, function() require('telescope.builtin').jumplist() end, 'Recent locations')
  action({ '<F35>63', '<D-S-w>' }, function()
    if require('jvim.config').get().features.autosave then require('jvim.autosave').save_all() end
    local saved, err = require('jvim.session').save()
    if not saved then vim.notify('Could not save jvim workspace: ' .. tostring(err), vim.log.levels.WARN) end
    vim.cmd 'confirm qall'
  end, 'Close editor (ask about unsaved files)')
  action({ '<F35>65' }, function()
    if vim.bo.filetype == 'markdown' then
      require('render-markdown').buf_toggle()
    else
      vim.notify 'Open a Markdown file to toggle its preview'
    end
  end, 'Toggle Markdown preview')
  action({ '<F35>66' }, function() require('jvim.definition_links').toggle() end, 'Toggle Cmd-click code links (dashed underlines)')

  -- Expand and shrink a selection using the syntax tree already installed.
  local selection_buffers = {}
  local selection_origins = {}
  local function track_selection(buf)
    if selection_buffers[buf] then return end
    selection_buffers[buf] = vim.api.nvim_buf_attach(buf, false, {
      -- changedtick also advances on writes; autosave must preserve selection
      -- history. Invalidate syntax nodes only when buffer text changes.
      on_lines = function() selections[buf] = nil end,
      on_detach = function()
        selections[buf] = nil
        selection_buffers[buf] = nil
      end,
    })
  end
  local function node_selection(node)
    local sr, sc, er, ec = node:range()
    if sr == er and sc == ec then
      resume_editing()
      return false
    end
    local count = vim.api.nvim_buf_line_count(0)
    if er >= count then
      er = count - 1
      ec = #vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1]
    end
    vim.cmd 'normal! \27'
    vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
    vim.cmd 'normal! v'
    vim.api.nvim_win_set_cursor(0, { er + 1, ec })
    vim.cmd 'normal! \7'
    return true
  end
  map('n', '<Plug>(JvimExtendSelection)', function()
    local buf = vim.api.nvim_get_current_buf()
    track_selection(buf)
    local current = selection_origins[buf] or vim.api.nvim_win_get_cursor(0)
    selection_origins[buf] = nil
    vim.api.nvim_win_set_cursor(0, current)
    local previous = selections[buf]
    local node
    if previous then
      node = previous.node:parent()
      if not node then
        node_selection(previous.node)
        return
      end
    else
      local ok
      ok, node = pcall(vim.treesitter.get_node)
      if not ok or not node then
        vim.cmd 'normal! \27viw\7'
        if not vim.fn.mode():find '^[sS]' then resume_editing() end
        return
      end
    end
    if not node_selection(node) then return end
    selections[buf] = { node = node, previous = previous, cursor = current, last_cursor = vim.api.nvim_win_get_cursor(0) }
  end, { desc = 'Extend selection' })
  map('n', '<Plug>(JvimShrinkSelection)', function()
    local state = selections[vim.api.nvim_get_current_buf()]
    if not state then
      resume_editing()
      return
    end
    selections[vim.api.nvim_get_current_buf()] = state.previous
    if state.previous then
      node_selection(state.previous.node)
    else
      vim.api.nvim_win_set_cursor(0, state.cursor)
      resume_editing()
    end
  end, { desc = 'Shrink selection' })
  -- Exit both Insert and Select input loops before changing a syntax
  -- selection. Running :normal inside a Select callback can edit the text
  -- when Neovim restores that old selection after the callback returns.
  for _, binding in ipairs {
    { keys = { '<F35>49', '<M-Up>' }, target = '<Plug>(JvimExtendSelection)', desc = 'Extend selection' },
    { keys = { '<F35>50', '<M-Down>' }, target = '<Plug>(JvimShrinkSelection)', desc = 'Shrink selection' },
  } do
    for _, key in ipairs(binding.keys) do
      map({ 'n', 'i', 's', 'x' }, key, function()
        local buf = vim.api.nvim_get_current_buf()
        local state = selections[buf]
        local mode = vim.fn.mode()
        if binding.target == '<Plug>(JvimShrinkSelection)' and mode:find '^i' then
          selections[buf] = nil
          return ''
        end
        selection_origins[buf] = mode:find '^i' and vim.api.nvim_win_get_cursor(0) or nil
        if state and (not mode:find '^[svSV]'
          or not vim.deep_equal(state.last_cursor, vim.api.nvim_win_get_cursor(0))) then
          selections[buf] = nil
        end
        return '<C-\\><C-n>' .. binding.target
      end, { expr = true, remap = true, desc = binding.desc })
    end
  end

  map('i', '<F35>51', '<Esc><cmd>move .-2<CR>==gi', { desc = 'Move line up' })
  map('i', '<F35>52', '<Esc><cmd>move .+1<CR>==gi', { desc = 'Move line down' })
  map('n', '<F35>51', '<cmd>move .-2<CR>==', { desc = 'Move line up' })
  map('n', '<F35>52', '<cmd>move .+1<CR>==', { desc = 'Move line down' })
  map('s', '<F35>51', "<C-g>:move '<-2<CR>gv<C-g>", { desc = 'Move selected lines up' })
  map('s', '<F35>52', "<C-g>:move '>+1<CR>gv<C-g>", { desc = 'Move selected lines down' })
  action({ '<F35>53', '<D-BS>' }, function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, {})
  end, 'Delete line')
  map('s', '<Tab>', '<C-g>>gv<C-g>', { desc = 'Indent selection' })
  map('s', '<S-Tab>', '<C-g><gv<C-g>', { desc = 'Unindent selection' })
  map('i', '<S-Tab>', '<C-d>', { desc = 'Unindent' })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(args)
      if not require('jvim.config').get().features.folds then return end
      if vim.bo[args.buf].buftype == '' and vim.treesitter.get_parser(args.buf, nil, { error = false }) then
        vim.wo.foldmethod = 'expr'
        vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        vim.wo.foldlevel = 99
      end
    end,
  })

  if package.loaded['mini.statusline'] then require('mini.statusline').section_mode = function() return '', 'MiniStatuslineModeInsert' end end
end

return M
