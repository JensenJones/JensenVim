local M = {}

local function clang_format_args(_, ctx)
  local root = vim.fs.root(ctx.filename, { '.git', 'compile_commands.json', 'CMakeLists.txt', 'Makefile' })
    or vim.fs.dirname(ctx.filename)
  local directories = { vim.fs.dirname(ctx.filename), root, root .. '/include', root .. '/src' }
  local local_headers = {}
  -- Project headers can use angle brackets too. Resolve only the headers in
  -- this buffer instead of scanning the project or guessing from extensions.
  for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
    local delimiter, header = line:match '^%s*#%s*include%s*([<"])([^>"]+)[>"]'
    if header then
      if delimiter == '"' then
        local_headers[header] = true
      else
        for _, directory in ipairs(directories) do
          if vim.fn.filereadable(directory .. '/' .. header) == 1 then
            local_headers[header] = true
            break
          end
        end
      end
    end
  end
  local headers = vim.tbl_keys(local_headers)
  table.sort(headers, function(a, b)
    if a:lower() == b:lower() then return a < b end
    return a:lower() < b:lower()
  end)
  local categories = {}
  for index, header in ipairs(headers) do
    local escaped = header:gsub('([%.%[%]%(%)%*%+%?%^%$%{%}%|\\])', '\\%1')
    -- SortPriority lets quoted and angle-bracket project headers interleave
    -- alphabetically while retaining one shared project-header group.
    table.insert(categories, { Regex = '^[<"]' .. escaped .. '[>"]$', Priority = 2, SortPriority = index + 2 })
  end
  table.insert(categories, { Regex = '^<', Priority = 1 })
  table.insert(categories, { Regex = '.*', Priority = 2 })
  return {
    '--style=' .. vim.json.encode {
      BasedOnStyle = 'InheritParentConfig',
      SortIncludes = 'CaseInsensitive',
      IncludeBlocks = 'Regroup',
      IncludeIsMainRegex = 'a^', -- Keep the matching header alphabetised too.
      IncludeCategories = categories,
    },
  }
end

M.formatters = {
  ['clang-format'] = { prepend_args = clang_format_args },
  jvim_include_spacing = {
    format = function(_, ctx, lines, callback)
      -- Use syntax nodes so include-looking text in comments and raw strings
      -- stays untouched. jvim installs C/C++ parsers when those files open.
      local text = table.concat(lines, '\n')
      local language = vim.treesitter.language.get_lang(vim.bo[ctx.buf].filetype)
      local ok, parser = pcall(vim.treesitter.get_string_parser, text, language)
      if not ok then return callback(nil, lines) end
      local tree = parser:parse()[1]
      local query = vim.treesitter.query.parse(language, '(preproc_include) @include')
      local include_ends = {}
      for _, node in query:iter_captures(tree:root(), text) do
        local _, _, row, column = node:range()
        include_ends[row + (column > 0 and 1 or 0)] = true
      end
      local result = {}
      for index, line in ipairs(lines) do
        table.insert(result, line)
        local next_line = lines[index + 1]
        if include_ends[index] and next_line and next_line:find('%S') and not next_line:match('^%s*#') then
          table.insert(result, '')
        end
      end
      callback(nil, result)
    end,
  },
}

M.formatters_by_ft = {
  lua = { 'stylua' },
  c = { 'clang-format', 'jvim_include_spacing' },
  cpp = { 'clang-format', 'jvim_include_spacing' },
}

function M.on_save(bufnr)
  -- Autosave persists edits and undo exactly; explicit saves can format.
  if vim.b[bufnr].jvim_autosaving or not require('jvim.config').get().formatting.on_save then return nil end
  return { timeout_ms = 500, lsp_format = 'fallback' }
end

function M.options()
  local config = require 'jvim.config'
  local opts = config.get().formatting
  local defaults = opts.organise_includes and M.formatters_by_ft or {
    lua = { 'stylua' }, c = { 'clang-format' }, cpp = { 'clang-format' },
  }
  return {
    formatters_by_ft = config.merge(defaults, opts.formatters_by_ft),
    formatters = config.merge(opts.organise_includes and M.formatters or {}, opts.formatters),
  }
end

return M
