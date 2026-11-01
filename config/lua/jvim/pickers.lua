local M = {}

local function edit(path, win)
  if not path or path == '' or not vim.api.nvim_win_is_valid(win) then return end
  vim.api.nvim_win_call(win, function() vim.cmd.edit(vim.fn.fnameescape(path)) end)
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
