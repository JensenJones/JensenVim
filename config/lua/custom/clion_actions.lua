local M = {}

function M.setup(action, resume_editing)
  local map = vim.keymap.set
  local group = vim.api.nvim_create_augroup('clion-ordinary-editing', { clear = true })
  local selections = {}
  -- Escape cancels UI and selection; it never makes ordinary typing into commands.
  map('i', '<Esc>', function()
    selections[vim.api.nvim_get_current_buf()] = nil
    if package.loaded['blink.cmp'] then require('blink.cmp').hide() end
    vim.cmd.nohlsearch()
  end, { desc = 'Cancel completion' })
  map('s', '<Esc>', function()
    selections[vim.api.nvim_get_current_buf()] = nil
    local position = vim.api.nvim_win_get_cursor(0)
    vim.cmd 'normal! \27'
    vim.api.nvim_win_set_cursor(0, position)
    vim.cmd.startinsert()
  end, { desc = 'Cancel selection' })
  map('n', '<Esc>', function()
    vim.cmd.nohlsearch()
    resume_editing()
  end, { desc = 'Cancel and resume editing' })
  vim.api.nvim_create_autocmd('CmdlineLeave', { group = group, callback = function() vim.schedule(resume_editing) end })

  -- Record mouse locations and file departures in the same history used by
  -- definition jumps. Browsing backward must not create fresh history entries.
  local navigating = false
  local function remember()
    if not navigating and vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) ~= '' then vim.cmd "normal! m'" end
  end
  vim.on_key(function(_, typed)
    if typed ~= '' and vim.fn.keytrans(typed):find('LeftMouse', 1, true) then
      selections[vim.api.nvim_get_current_buf()] = nil
      remember()
    end
  end, vim.api.nvim_create_namespace 'clion-mouse-history')
  vim.api.nvim_create_autocmd('BufLeave', { group = group, callback = remember })
  local function history(key)
    return function()
      navigating = true
      -- A leading Ctrl-I is a tab, which :normal would strip as whitespace.
      local ok, err = pcall(vim.cmd.normal, { '1' .. key, bang = true })
      navigating = false
      if not ok then vim.notify(err, vim.log.levels.WARN) end
      resume_editing()
    end
  end
  action({ '<F33>', '<D-M-Left>', '<D-[>' }, history '\15', 'Navigate back')
  action({ '<F34>', '<D-M-Right>', '<D-]>' }, history '\9', 'Navigate forward')

  action({ '<F35>39', '<C-M-b>', '<D-M-b>' }, vim.lsp.buf.implementation, 'Go to implementation')
  action({ '<F35>40', '<D-S-b>', '<C-S-b>' }, vim.lsp.buf.type_definition, 'Go to type declaration')
  action({ '<F35>41', '<F1>', '<C-j>' }, vim.lsp.buf.hover, 'Quick documentation')
  action({ '<F35>42', '<D-p>', '<C-p>' }, vim.lsp.buf.signature_help, 'Parameter info')
  action({ '<F35>43', '<D-F12>', '<C-F12>', '<D-7>' }, function() require('telescope.builtin').lsp_document_symbols() end, 'File structure')
  action({ '<F35>44', '<D-M-o>' }, function() require('telescope.builtin').lsp_dynamic_workspace_symbols() end, 'Find symbol')
  action({ '<F35>46', '<D-l>' }, function()
    vim.ui.input({ prompt = 'Go to line:column: ' }, function(value)
      if not value then return end
      local row, col = value:match '^(%d+):?(%d*)$'
      if not row then return end
      row = math.max(1, math.min(tonumber(row), vim.api.nvim_buf_line_count(0)))
      vim.api.nvim_win_set_cursor(0, { row, math.max(0, tonumber(col) and tonumber(col) - 1 or 0) })
      resume_editing()
    end)
  end, 'Go to line')
  action({ '<F35>47', '<C-r>', '<D-r>' }, function()
    vim.ui.input({ prompt = 'Replace in file — find: ' }, function(find)
      if not find or find == '' then return end
      vim.ui.input({ prompt = 'Replace with: ' }, function(replacement)
        if replacement == nil then return end
        local pattern = '\\V' .. vim.fn.escape(find, '\\/')
        local value = vim.fn.escape(replacement, '\\/&')
        vim.cmd('%s/' .. pattern .. '/' .. value .. '/gce')
        resume_editing()
      end)
    end)
  end, 'Replace in file (confirm each match)')
  action({ '<F35>48', '<D-S-r>' }, function() require('custom.project_replace').open() end, 'Replace in project (preview and confirmation)')
  local last_search = ''
  action({ '<F30>', '<D-f>', '<C-f>' }, function()
    vim.ui.input({ prompt = 'Find in file: ', default = last_search }, function(query)
      if not query or query == '' then return end
      last_search = query
      local pattern = '\\V' .. vim.fn.escape(query, '\\')
      vim.fn.setreg('/', pattern)
      vim.o.hlsearch = true
      vim.cmd "normal! m'"
      if vim.fn.search(pattern, 'cw') == 0 then vim.notify('No matches for ' .. query) end
      resume_editing()
    end)
  end, 'Find in file')
  action({ '<F35>54', '<F2>' }, function() vim.diagnostic.jump { count = 1, float = true } end, 'Next problem')
  action({ '<F35>55', '<S-F2>' }, function() vim.diagnostic.jump { count = -1, float = true } end, 'Previous problem')
  action({ '<F35>56', '<D-g>', '<F3>' }, function() vim.cmd 'normal! n' end, 'Next search match')
  action({ '<F35>57', '<D-S-g>', '<S-F3>' }, function() vim.cmd 'normal! N' end, 'Previous search match')
  action({ '<F35>58', '<D-->' }, function() vim.cmd 'silent! normal! zc' end, 'Collapse code fold')
  action({ '<F35>59', '<D-=>', '<D-+>' }, function() vim.cmd 'silent! normal! zo' end, 'Expand code fold')
  action({ '<F35>60' }, function() vim.cmd 'normal! %' end, 'Go to matching bracket')
  action({ '<F35>61', '<C-S-BS>' }, function() vim.cmd 'normal! g;' end, 'Last edit location')
  action({ '<F35>62', '<C-S-e>' }, function() require('telescope.builtin').jumplist() end, 'Recent locations')
  action({ '<F35>63', '<D-S-w>' }, function()
    require('custom.autosave').save_all()
    vim.cmd 'confirm qall'
  end, 'Close editor (ask about unsaved files)')
  action({ '<F35>65' }, function()
    if vim.bo.filetype == 'markdown' then
      require('render-markdown').buf_toggle()
    else
      vim.notify 'Open a Markdown file to toggle its preview'
    end
  end, 'Toggle Markdown preview')
  action({ '<F35>66' }, function() require('custom.definition_links').toggle() end, 'Toggle Cmd-click code links (dashed underlines)')

  -- Expand and shrink a selection using the syntax tree already installed.
  local function node_selection(node)
    local sr, sc, er, ec = node:range()
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
  end
  action({ '<F35>49', '<M-Up>' }, function()
    local buf = vim.api.nvim_get_current_buf()
    local previous = selections[buf]
    if
      previous
      and (not vim.fn.mode():find '^[svSV]' or previous.tick ~= vim.b.changedtick or not vim.deep_equal(previous.last_cursor, vim.api.nvim_win_get_cursor(0)))
    then
      previous = nil
    end
    local node
    if previous then
      node = previous.node:parent()
      if not node then return end
    else
      local ok
      ok, node = pcall(vim.treesitter.get_node)
      if not ok or not node then
        vim.cmd 'normal! \27viw\7'
        return
      end
    end
    local current = vim.api.nvim_win_get_cursor(0)
    node_selection(node)
    selections[buf] = { node = node, previous = previous, cursor = current, tick = vim.b.changedtick, last_cursor = vim.api.nvim_win_get_cursor(0) }
  end, 'Extend selection')
  action({ '<F35>50', '<M-Down>' }, function()
    local state = selections[vim.api.nvim_get_current_buf()]
    if
      not state
      or not vim.fn.mode():find '^[svSV]'
      or state.tick ~= vim.b.changedtick
      or not vim.deep_equal(state.last_cursor, vim.api.nvim_win_get_cursor(0))
    then
      selections[vim.api.nvim_get_current_buf()] = nil
      return
    end
    selections[vim.api.nvim_get_current_buf()] = state.previous
    vim.cmd 'normal! \27'
    if state.previous then
      node_selection(state.previous.node)
    else
      vim.api.nvim_win_set_cursor(0, state.cursor)
      resume_editing()
    end
  end, 'Shrink selection')
  -- A callback entered from Insert mode resumes Insert when it returns, even
  -- if :normal temporarily selected text. Leave the insert loop first.
  for _, key in ipairs { '<F35>49', '<M-Up>' } do
    map('i', key, '<C-\\><C-n><F35>49', { remap = true, desc = 'Extend selection' })
  end
  for _, key in ipairs { '<F35>50', '<M-Down>' } do
    map('i', key, function() selections[vim.api.nvim_get_current_buf()] = nil end, { desc = 'Shrink selection' })
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
