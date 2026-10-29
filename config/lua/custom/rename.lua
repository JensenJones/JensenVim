local M = {}

local function node_at_cursor(buf)
  local filetype = vim.bo[buf].filetype
  local ok, parser = pcall(vim.treesitter.get_parser, buf, filetype)
  if not ok then return nil end
  local parsed = pcall(parser.parse, parser)
  if not parsed then return nil end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { cursor[1] - 1, cursor[2] } })
  return ok and node or nil
end

function M.namespace_declaration_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= 'cpp' and vim.bo[buf].filetype ~= 'c' then return nil end
  local node = node_at_cursor(buf)
  if not node or node:type() ~= 'namespace_identifier' then return nil end
  local parent = node:parent()
  if not parent or parent:type() ~= 'namespace_definition' then return nil end
  return vim.treesitter.get_node_text(node, buf)
end

local function location_is_namespace(location, encoding)
  local uri = location.uri or location.targetUri
  local range = location.range or location.targetSelectionRange or location.targetRange
  if not uri or not range then return false end
  local path = vim.uri_to_fname(uri)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  local filetype = vim.filetype.match { filename = path }
  if filetype ~= 'cpp' and filetype ~= 'c' then return false end
  if vim.bo[buf].filetype == '' then vim.bo[buf].filetype = filetype end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, filetype)
  if not ok or not pcall(parser.parse, parser) then return false end
  local position = range.start
  local line = vim.api.nvim_buf_get_lines(buf, position.line, position.line + 1, false)[1] or ''
  local col = vim.str_byteindex(line, encoding or 'utf-16', position.character)
  local got_node, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { position.line, col } })
  if not got_node or not node then return false end
  return node:type() == 'namespace_identifier' and node:parent() and node:parent():type() == 'namespace_definition'
end

local function namespace_name_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= 'cpp' and vim.bo[buf].filetype ~= 'c' then return nil end
  local node = node_at_cursor(buf)
  if node and node:type() == 'namespace_identifier' then return vim.treesitter.get_node_text(node, buf) end
end

local function project_root(buf)
  return vim.fs.root(buf, { '.git', 'compile_commands.json', 'compile_flags.txt', 'CMakeLists.txt' }) or vim.fn.getcwd()
end

local function standard_rename()
  vim.lsp.buf.rename()
end

function M.symbol()
  local buf = vim.api.nvim_get_current_buf()
  local declared_name = M.namespace_declaration_at_cursor()
  local candidate_name = declared_name or namespace_name_at_cursor()
  if not candidate_name then return standard_rename() end
  local root = project_root(buf)
  if declared_name then
    return require('custom.project_replace').rename_namespace(declared_name, root)
  end

  local clients = vim.lsp.get_clients { bufnr = buf, method = 'textDocument/definition' }
  local client = clients[1]
  if not client then return standard_rename() end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local requested = client:request('textDocument/definition', params, function(err, result)
    if not err then
      local locations = result and (result.uri and { result } or result) or {}
      for _, location in ipairs(locations) do
        if location_is_namespace(location, client.offset_encoding) then
          require('custom.project_replace').rename_namespace(candidate_name, root)
          return
        end
      end
    end
    standard_rename()
  end, buf)
  if not requested then standard_rename() end
end

return M
