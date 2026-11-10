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
    if item.commands ~= nil then
      if item.command ~= nil then return nil, prefix .. 'use either commands or command, not both' end
      if not list(item.commands) or #item.commands == 0 then return nil, prefix .. 'commands must be a nonempty list of shell lines' end
      for _, line in ipairs(item.commands) do
        if not text(line) or vim.trim(line) == '' then return nil, prefix .. 'commands must be nonempty strings without NUL bytes' end
      end
    else
      if not list(item.command) or #item.command == 0 then return nil, prefix .. 'command must be a nonempty argument array' end
      for _, arg in ipairs(item.command) do
        if not text(arg) then return nil, prefix .. 'command arguments must be strings without NUL bytes' end
      end
      if item.command[1] == '' then return nil, prefix .. 'executable cannot be empty' end
    end
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
    entries[#entries + 1] = { name = item.name, command = item.command, commands = item.commands, cwd = cwd, env = item.env, root = root }
  end
  return entries
end

-- Each line runs in the user's shell; the first failing line ends the run with its status.
local function shell_steps(commands)
  -- No space before &&: cmd.exe keeps it, so 'echo hi && ...' would print 'hi ' with a trailing space.
  if vim.fn.has('win32') == 1 then return { 'cmd.exe', '/s', '/c', table.concat(commands, '&& ') } end
  local script = {}
  for _, line in ipairs(commands) do
    script[#script + 1] = 'printf \'\\033[1m$ %s\\033[0m\\n\' ' .. vim.fn.shellescape(line)
    script[#script + 1] = '{ ' .. line .. '\n} || exit $?'
  end
  return { vim.o.shell, '-c', table.concat(script, '\n') }
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

local function resolve(entry)
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
    if not found then return nil, 'Run executable not found in configured PATH: ' .. executable end
    executable = found
  elseif vim.fn.executable(executable) ~= 1 then
    return nil, 'Run executable not found: ' .. executable
  end
  local command = vim.deepcopy(entry.command)
  command[1] = executable
  return command
end

function M.run(name, root, restart)
  root = vim.fs.normalize(root or M.root())
  name = name or selected[root]
  if not name then return M.choose(root, true) end
  local entry, err = find(name, root)
  if not entry then return error_message(err) end
  local command
  if entry.commands then
    command = shell_steps(entry.commands)
  else
    command, err = resolve(entry)
    if not command then return error_message(err) end
  end
  selected[root] = name
  return require('jvim.command_terminal').open {
    key = 'run:' .. root .. ':' .. name, cwd = entry.cwd, command = command,
    env = entry.env, title = name, restart = restart, root = root,
  }
end

local function read_raw(path)
  if vim.fn.filereadable(path) == 0 then return { version = 1, configurations = {} } end
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  if not ok or type(data) ~= 'table' or not list(data.configurations) then
    return nil, 'Fix ' .. path .. ' before editing configurations: it is not a valid run configuration file'
  end
  return data
end

local field_order = { 'name', 'commands', 'command', 'cwd', 'env' }

local function encode(data)
  if #data.configurations == 0 then return { '{', '  "version": 1,', '  "configurations": []', '}' } end
  local out = { '{', '  "version": 1,', '  "configurations": [' }
  for index, item in ipairs(data.configurations) do
    local keys = vim.tbl_filter(function(key) return item[key] ~= nil end, field_order)
    local extra = vim.tbl_filter(function(key) return not vim.tbl_contains(field_order, key) end, vim.tbl_keys(item))
    table.sort(extra)
    vim.list_extend(keys, extra)
    local fields = {}
    for _, key in ipairs(keys) do
      local value = vim.json.encode(item[key], { indent = '  ' }):gsub('\n', '\n      ')
      fields[#fields + 1] = '      ' .. vim.json.encode(key) .. ': ' .. value
    end
    out[#out + 1] = '    {'
    out[#out + 1] = table.concat(fields, ',\n')
    out[#out + 1] = '    }' .. (index < #data.configurations and ',' or '')
  end
  out[#out + 1] = '  ]'
  out[#out + 1] = '}'
  return vim.split(table.concat(out, '\n'), '\n')
end

local function shell_word(arg)
  if arg:match('^[%w%-%._/=:,+@%%]+$') then return arg end
  return vim.fn.shellescape(arg)
end

local function parse_form(lines)
  local name, commands
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if not commands then
      local value = trimmed:match('^Name:%s*(.-)$')
      if value then name, commands = value, {} end
    elseif trimmed ~= '' and not vim.startswith(trimmed, '#') then
      commands[#commands + 1] = trimmed
    end
  end
  return name, commands or {}
end

-- Saves the form into run.json. original is the configuration's previous name, nil for a new one.
function M.save_form(root, original, lines)
  local path = root .. '/.jvim/run.json'
  local name, commands = parse_form(lines)
  if not name or name == '' then return nil, 'Give the configuration a name on the "Name:" line' end
  local data, err = read_raw(path)
  if not data then return nil, err end
  local index
  for i, item in ipairs(data.configurations) do
    if type(item) == 'table' and item.name == original then index = i end
    if type(item) == 'table' and item.name == name and item.name ~= original then
      return nil, 'A run configuration named "' .. name .. '" already exists'
    end
  end
  if #commands == 0 then
    if not index then return nil, 'Add at least one command' end
    table.remove(data.configurations, index)
    if selected[root] == original then selected[root] = nil end
  else
    local item = index and data.configurations[index] or {}
    item.name, item.commands, item.command = name, commands, nil
    if not index then data.configurations[#data.configurations + 1] = item end
    selected[root] = name
  end
  vim.fn.mkdir(root .. '/.jvim', 'p')
  vim.fn.writefile(encode(data), path)
  return #commands > 0 and name or false
end

local forms = 0

function M.form(root, original)
  root = vim.fs.normalize(root or M.root())
  local commands = {}
  if original then
    local data, err = read_raw(root .. '/.jvim/run.json')
    if not data then return error_message(err) end
    for _, item in ipairs(data.configurations) do
      if type(item) == 'table' and item.name == original then
        commands = list(item.commands) and vim.deepcopy(item.commands)
          or { table.concat(vim.tbl_map(shell_word, item.command or {}), ' ') }
      end
    end
  end
  local lines = {
    '# Cmd+S saves, Cmd+W or Esc closes without saving.',
    'Name: ' .. (original or ''),
    '',
    '# Commands, one per line. They run in order in your shell',
    '# and stop at the first one that fails. Remove them all to delete.',
  }
  local first_command = #lines + 1
  vim.list_extend(lines, #commands > 0 and commands or { '' })
  local buf = vim.api.nvim_create_buf(false, true)
  forms = forms + 1
  vim.api.nvim_buf_set_name(buf, ('jvim-run://%d/%s'):format(forms, original or 'new'))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'acwrite', 'wipe', false
  vim.bo[buf].filetype, vim.bo[buf].syntax, vim.bo[buf].modified = 'jvimrun', 'sh', false
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(math.max(#lines + 4, 12), vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2), col = math.floor((vim.o.columns - width) / 2),
    title = original and ' Edit run configuration ' or ' New run configuration ', title_pos = 'center',
  })
  local function close()
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local saved, err = M.save_form(root, original, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      if saved == nil then return error_message(err) end
      vim.bo[buf].modified = false
      -- Wiping the buffer inside its own BufWriteCmd crashes Neovim, so close once the write finishes.
      vim.schedule(close)
      vim.notify(saved and ('Saved run configuration "' .. saved .. '"') or ('Deleted run configuration "' .. original .. '"'))
      vim.cmd.redrawstatus()
    end,
  })
  for _, key in ipairs { '<F16>', '<D-s>', '<C-s>' } do
    vim.keymap.set({ 'n', 'i', 's', 'x' }, key, '<Cmd>write<CR>', { buffer = buf, desc = 'Save run configuration' })
  end
  for _, key in ipairs { '<F20>', '<D-w>' } do
    vim.keymap.set({ 'n', 'i', 's', 'x' }, key, close, { buffer = buf, desc = 'Close run configuration' })
  end
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, desc = 'Close run configuration' })
  if original then
    vim.api.nvim_win_set_cursor(win, { first_command, #lines[first_command] })
  else
    vim.api.nvim_win_set_cursor(win, { 2, #lines[2] })
  end
  vim.cmd.startinsert { bang = true }
  return buf
end

function M.choose(root, execute)
  root = vim.fs.normalize(root or M.root())
  local entries, err = M.load(root)
  if not entries then
    if vim.fn.filereadable(root .. '/.jvim/run.json') == 0 then return M.form(root) end
    return error_message(err .. '\nEdit .jvim/run.json to correct this configuration.')
  end
  if #entries == 0 then return M.form(root) end
  if execute then
    return vim.ui.select(entries, { prompt = 'Run configuration', format_item = function(item) return item.name end }, function(entry)
      if not entry then return end
      M.run(entry.name, root)
      vim.cmd.redrawstatus()
    end)
  end
  local active = selected[root]
  local items = vim.deepcopy(entries)
  items[#items + 1] = { action = 'new', label = '+ New configuration' }
  if active then items[#items + 1] = { action = 'edit', label = 'Edit "' .. active .. '"' } end
  items[#items + 1] = { action = 'json', label = 'Open .jvim/run.json' }
  vim.ui.select(items, {
    prompt = 'Run configuration',
    format_item = function(item) return item.label or ((item.name == active and '● ' or '  ') .. item.name) end,
  }, function(item)
    if not item then return end
    if item.action == 'new' then return M.form(root) end
    if item.action == 'edit' then return M.form(root, active) end
    if item.action == 'json' then return M.edit(root) end
    selected[root] = item.name
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
