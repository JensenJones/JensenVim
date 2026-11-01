local M = {}
local selected = {}

function M.root()
  if vim.b.jvim_project_root then return vim.b.jvim_project_root end
  local name = vim.api.nvim_buf_get_name(0)
  local start = vim.bo.buftype == '' and name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  if vim.bo.filetype == 'neo-tree' then
    local ok, manager = pcall(require, 'neo-tree.sources.manager')
    local state = ok and manager.get_state('filesystem')
    if state and state.path then start = state.path end
  end
  local directory = vim.fs.normalize(start)
  while directory do
    if vim.fn.filereadable(directory .. '/.jvim/run.json') == 1 then return directory end
    local parent = vim.fs.dirname(directory)
    if parent == directory then break end
    directory = parent
  end
  return vim.fs.root(start, { '.git', 'CMakeLists.txt', 'package.json', 'pyproject.toml' }) or vim.fn.getcwd()
end

local function text(value) return type(value) == 'string' and not value:find('\0', 1, true) end
local function list(value) return type(value) == 'table' and vim.islist(value) end

function M.load(root)
  root = vim.fs.normalize(root or M.root())
  local path = root .. '/.jvim/run.json'
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  if not ok then return nil, 'Cannot read run configurations at ' .. path .. ': ' .. tostring(data) end
  if type(data) ~= 'table' or data.version ~= 1 or not list(data.configurations) then
    return nil, 'Run configurations require version 1 and a configurations array'
  end
  local entries, names = {}, {}
  for index, item in ipairs(data.configurations) do
    local prefix = 'Run configuration ' .. index .. ': '
    if type(item) ~= 'table' or not text(item.name) or item.name == '' or names[item.name] then
      return nil, prefix .. 'name must be a unique nonempty string'
    end
    if not list(item.command) or #item.command == 0 then return nil, prefix .. 'command must be a nonempty argument array' end
    for _, arg in ipairs(item.command) do
      if not text(arg) then return nil, prefix .. 'command arguments must be strings without NUL bytes' end
    end
    if item.command[1] == '' then return nil, prefix .. 'executable cannot be empty' end
    if item.cwd ~= nil and not text(item.cwd) then return nil, prefix .. 'cwd must be a path string' end
    local cwd = item.cwd or '.'
    if not vim.startswith(cwd, '/') and not cwd:match('^%a:[/\\]') then cwd = root .. '/' .. cwd end
    cwd = vim.fs.normalize(cwd)
    if vim.fn.isdirectory(cwd) ~= 1 then return nil, prefix .. 'cwd is not a directory: ' .. cwd end
    if item.env ~= nil and (type(item.env) ~= 'table' or vim.islist(item.env)) then return nil, prefix .. 'env must be an object' end
    for key, value in pairs(item.env or {}) do
      if not text(key) or not key:match('^[%a_][%w_]*$') or not text(value) then
        return nil, prefix .. 'env requires variable names and string values without NUL bytes'
      end
    end
    names[item.name] = true
    entries[#entries + 1] = { name = item.name, command = item.command, cwd = cwd, env = item.env, root = root }
  end
  return entries
end

local function error_message(err)
  vim.notify(err, vim.log.levels.ERROR)
  return nil, err
end

local function find(name, root)
  local entries, err = M.load(root)
  if not entries then return nil, err end
  for _, entry in ipairs(entries) do
    if entry.name == name then return entry end
  end
  return nil, 'No run configuration named ' .. tostring(name)
end

function M.run(name, root, restart)
  root = vim.fs.normalize(root or M.root())
  name = name or selected[root]
  if not name then return M.choose(root, true) end
  local entry, err = find(name, root)
  if not entry then return error_message(err) end
  local executable = entry.command[1]
  if executable:find('[/\\]') and not vim.startswith(executable, '/') and not executable:match('^%a:[/\\]') then
    executable = entry.cwd .. '/' .. executable
  end
  if not executable:find('[/\\]') and entry.env and entry.env.PATH then
    local found
    local separator = package.config:sub(1, 1) == '\\' and ';' or ':'
    for _, directory in ipairs(vim.split(entry.env.PATH, separator, { plain = true })) do
      if not vim.startswith(directory, '/') and not directory:match('^%a:[/\\]') then directory = entry.cwd .. '/' .. directory end
      local candidate = directory .. '/' .. executable
      if vim.fn.executable(candidate) == 1 then found = candidate; break end
    end
    executable = found or executable
    if not found then return error_message('Run executable not found in configured PATH: ' .. executable) end
  elseif vim.fn.executable(executable) ~= 1 then
    return error_message('Run executable not found: ' .. executable)
  end
  local command = vim.deepcopy(entry.command)
  command[1] = executable
  selected[root] = name
  return require('jvim.command_terminal').open {
    key = 'run:' .. root .. ':' .. name, cwd = entry.cwd, command = command,
    env = entry.env, title = name, restart = restart, root = root,
  }
end

function M.choose(root, execute)
  root = vim.fs.normalize(root or M.root())
  local entries, err = M.load(root)
  if not entries then return error_message(err) end
  if #entries == 0 then return error_message('No run configurations in ' .. root .. '/.jvim/run.json') end
  vim.ui.select(entries, { prompt = execute and 'Run configuration' or 'Choose run configuration', format_item = function(item) return item.name end }, function(entry)
    if not entry then return end
    selected[root] = entry.name
    if execute then M.run(entry.name, root) end
    vim.cmd.redrawstatus()
  end)
end

function M.current(root)
  root = vim.fs.normalize(root or M.root())
  local name = selected[root]
  return name and require('jvim.command_terminal').get('run:' .. root .. ':' .. name), name
end

function M.show(root)
  local session = M.current(root)
  if not session then return error_message('No run output for this project') end
  return require('jvim.command_terminal').show(session)
end

function M.stop(root)
  local session = M.current(root)
  return require('jvim.command_terminal').stop(session)
end

function M.rerun(root) return M.run(nil, root, true) end

function M.edit(root)
  root = vim.fs.normalize(root or M.root())
  vim.fn.mkdir(root .. '/.jvim', 'p')
  local buf = vim.fn.bufadd(root .. '/.jvim/run.json')
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  if vim.fn.filereadable(root .. '/.jvim/run.json') == 0 and not vim.bo[buf].modified then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{', '  "version": 1,', '  "configurations": []', '}' })
  end
  require('jvim.files').show(buf)
end

return M
