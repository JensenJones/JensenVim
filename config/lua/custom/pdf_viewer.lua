local M = {}
local uv = vim.uv or vim.loop
local viewers = {}

local function set_message(buf, message)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message, '', '' })
  vim.bo[buf].modifiable = false
end

local function clear_image(state)
  if state.image then
    pcall(function() state.image:clear() end)
    state.image = nil
  end
end

local function show_page(buf, state, image_path)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local win = vim.fn.bufwinid(buf)
  if win < 0 then return end

  clear_image(state)
  local api_ok, api = pcall(require, 'image')
  if not api_ok then
    vim.notify('Image viewer is unavailable. Restart jvim to install its plugins.', vim.log.levels.ERROR)
    return
  end
  local ok, image = pcall(api.from_file, image_path, {
    window = win,
    buffer = buf,
    x = 1,
    y = 3,
    inline = true,
  })
  if not ok then
    vim.notify('Could not display PDF page: ' .. tostring(image), vim.log.levels.ERROR)
    return
  end
  state.image = image
  local rendered, err = pcall(function() image:render() end)
  if not rendered then
    state.image = nil
    vim.notify('Could not display PDF page: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

local function render_page(buf, state)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local page = state.page
  state.render_id = state.render_id + 1
  local render_id = state.render_id
  local prefix = state.cache_dir .. '/page-' .. page
  local png = prefix .. '.png'

  set_message(buf, string.format('%s  |  Page %d/%d  |  [ prev  ] next  |  q close', vim.fn.fnamemodify(state.path, ':t'), page, state.pages))
  if uv.fs_stat(png) then
    show_page(buf, state, png)
    return
  end

  if vim.fn.executable 'pdftoppm' == 0 then
    vim.notify('PDF rendering needs Poppler. Install it with: brew install poppler', vim.log.levels.ERROR)
    return
  end

  vim.system({
    'pdftoppm', '-f', tostring(page), '-l', tostring(page), '-scale-to', '1800', '-png', '-singlefile', state.path, prefix,
  }, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or viewers[buf] ~= state or render_id ~= state.render_id then return end
      if result.code ~= 0 or not uv.fs_stat(png) then
        local detail = (result.stderr or ''):gsub('%s+$', '')
        vim.notify('Could not render PDF page ' .. page .. (detail ~= '' and (': ' .. detail) or ''), vim.log.levels.ERROR)
        return
      end
      show_page(buf, state, png)
    end)
  end)
end

local function close_viewer(buf)
  local state = viewers[buf]
  if state then clear_image(state) end
  viewers[buf] = nil

  local previous = vim.fn.bufnr '#'
  if previous > 0 and previous ~= buf and vim.api.nvim_buf_is_valid(previous)
      and (viewers[previous] ~= nil or (vim.bo[previous].buftype == '' and vim.bo[previous].filetype ~= 'neo-tree'
        and vim.api.nvim_buf_get_name(previous) ~= '')) then
    vim.api.nvim_set_current_buf(previous)
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end

  local files = require('custom.files').list()
  for _, candidate in ipairs(files) do
    if candidate ~= buf then
      vim.api.nvim_set_current_buf(candidate)
      vim.api.nvim_buf_delete(buf, { force = true })
      return
    end
  end

  local editor_win = vim.fn.bufwinid(buf)
  local tree_state = require('neo-tree.sources.manager').get_state 'filesystem'
  if not tree_state or not tree_state.winid or not vim.api.nvim_win_is_valid(tree_state.winid) then
    require('neo-tree.command').execute { action = 'show', position = 'left' }
    tree_state = require('neo-tree.sources.manager').get_state 'filesystem'
  end
  if tree_state and tree_state.winid and vim.api.nvim_win_is_valid(tree_state.winid)
      and editor_win > 0 and editor_win ~= tree_state.winid then
    vim.api.nvim_set_current_win(tree_state.winid)
    vim.api.nvim_win_close(editor_win, true)
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  else
    vim.cmd 'confirm qall'
  end
end

M.close = close_viewer

local function open_pdf(buf, path)
  path = vim.fn.fnamemodify(path, ':p')
  local stat = uv.fs_stat(path)
  if not stat then
    vim.notify('PDF file not found: ' .. path, vim.log.levels.ERROR)
    return
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'pdf'
  vim.bo[buf].modifiable = false
  vim.b[buf].jvim_pdf_viewer = true
  set_message(buf, 'Loading PDF…')

  local cache_key = vim.fn.sha256(table.concat({ path, stat.size, stat.mtime.sec, stat.mtime.nsec or 0 }, ':'))
  local cache_dir = vim.fn.stdpath('cache') .. '/jvim-pdf/' .. cache_key
  vim.fn.mkdir(cache_dir, 'p')
  local state = { path = path, page = 1, pages = 1, cache_dir = cache_dir, image = nil, render_id = 0 }
  viewers[buf] = state

  vim.keymap.set('n', ']', function()
    if state.page < state.pages then state.page = state.page + 1; render_page(buf, state) end
  end, { buffer = buf, desc = 'Next PDF page' })
  vim.keymap.set('n', '[', function()
    if state.page > 1 then state.page = state.page - 1; render_page(buf, state) end
  end, { buffer = buf, desc = 'Previous PDF page' })
  vim.keymap.set('n', 'q', function() close_viewer(buf) end, { buffer = buf, desc = 'Close PDF viewer' })

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    callback = function() clear_image(state) end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    buffer = buf,
    callback = function() render_page(buf, state) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function() clear_image(state); viewers[buf] = nil end,
  })

  if vim.fn.executable 'pdfinfo' == 0 then
    set_message(buf, 'PDF rendering needs Poppler (pdfinfo and pdftoppm). Install with: brew install poppler')
    return
  end
  vim.system({ 'pdfinfo', path }, { text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or viewers[buf] ~= state then return end
      local pages = result.stdout and tonumber(result.stdout:match('Pages:%s*(%d+)'))
      if result.code ~= 0 or not pages then
        local detail = (result.stderr or ''):gsub('%s+$', '')
        set_message(buf, 'Could not read PDF' .. (detail ~= '' and (': ' .. detail) or ''))
        return
      end
      state.pages = pages
      render_page(buf, state)
    end)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('JvimPdfViewer', { clear = true })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = '*.pdf',
    callback = function(args) open_pdf(args.buf, args.file) end,
  })
end

return M
