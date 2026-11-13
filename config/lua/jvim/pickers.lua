local M = {}

local function edit(path, win)
  if not path or path == '' or not vim.api.nvim_win_is_valid(win) then return end
  vim.api.nvim_win_call(win, function() vim.cmd.edit(vim.fn.fnameescape(path)) end)
end

-- Telescope's grep preview puts the matching line at column 0; scroll sideways so a match far right is on screen.
function M.show_match(previewer, entry, attempts)
  attempts = attempts or 0
  local win, buf = previewer.state and previewer.state.winid, previewer.state and previewer.state.bufnr
  if not entry.lnum or not entry.col or not win or not vim.api.nvim_win_is_valid(win) or previewer.jvim_entry ~= entry then return end
  local ready = vim.api.nvim_win_get_buf(win) == buf and vim.api.nvim_win_get_cursor(win)[1] == entry.lnum
  if not ready then
    if attempts < 50 then vim.defer_fn(function() M.show_match(previewer, entry, attempts + 1) end, 10) end
    return
  end
  vim.api.nvim_win_call(win, function()
    local line = vim.api.nvim_buf_get_lines(buf, entry.lnum - 1, entry.lnum, false)[1] or ''
    local column = vim.fn.strdisplaywidth(line:sub(1, entry.col - 1))
    local width = vim.api.nvim_win_get_width(win)
    vim.fn.winrestview { leftcol = column < width * 2 / 3 and 0 or math.floor(column - width / 3) }
  end)
end

function M.grep_previewer(opts)
  local previewer = require('telescope.previewers').vim_buffer_vimgrep.new(opts)
  local preview = previewer.preview
  function previewer.preview(self, entry, status)
    self.jvim_entry = entry
    local result = preview(self, entry, status)
    M.show_match(self, entry)
    return result
  end
  return previewer
end

function M.open(name)
  local ok, builtin = pcall(require, 'telescope.builtin')
  if ok and builtin[name] then return builtin[name]() end
  local win = vim.api.nvim_get_current_win()
  if name == 'find_files' then
    local root = require('jvim.run').root()
    return vim.ui.input({ prompt = 'Open file: ', default = root .. '/', completion = 'file' }, function(path) edit(path, win) end)
  elseif name == 'oldfiles' then
    local paths, seen = {}, {}
    for _, path in ipairs(vim.v.oldfiles) do
      if not seen[path] and vim.fn.filereadable(path) == 1 then paths[#paths + 1] = path; seen[path] = true end
    end
    return vim.ui.select(paths, { prompt = 'Recent files:', format_item = function(path) return vim.fn.fnamemodify(path, ':~:.') end }, function(path) edit(path, win) end)
  elseif name == 'lsp_references' then
    return vim.lsp.buf.references()
  elseif name == 'lsp_dynamic_workspace_symbols' then
    return vim.lsp.buf.workspace_symbol()
  elseif name == 'live_grep' then
    if vim.fn.executable('rg') ~= 1 then
      vim.notify('Project search requires ripgrep (rg) on PATH', vim.log.levels.WARN)
      return
    end
    local root = require('jvim.run').root()
    return vim.ui.input({ prompt = 'Search project: ' }, function(query)
      if not query or query == '' then return end
      vim.system({ 'rg', '--vimgrep', '--fixed-strings', '--', query, root }, { text = true }, function(result)
        vim.schedule(function()
          if result.code > 1 then vim.notify(result.stderr, vim.log.levels.ERROR); return end
          vim.fn.setqflist({}, ' ', { title = 'Project search: ' .. query, lines = vim.split(result.stdout, '\n'), efm = '%f:%l:%c:%m' })
          vim.cmd.copen()
        end)
      end)
    end)
  end
  vim.notify('This action needs Telescope: ' .. name, vim.log.levels.WARN)
end

return M
