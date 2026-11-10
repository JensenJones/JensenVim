local M = {}
local namespace = vim.api.nvim_create_namespace 'jvim-cpp-compiler'
local projects, attached = {}, {}
local errorformat = '%DJvim checking directory: %f,%XJvim leaving directory,'
  .. '%f:%l:%c: %t%*[^:]: %m,%f:%l: %t%*[^:]: %m,%-G%.%#'

local function database_for(buf)
  local root = vim.fs.root(buf, { 'compile_commands.json' })
  if not root then return nil end
  return root, root .. '/compile_commands.json'
end

local function watch_buffers(root, state)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local filetype = vim.bo[buf].filetype
    if filetype == '' then filetype = vim.filetype.match { buf = buf } end
    if vim.api.nvim_buf_is_loaded(buf) and not attached[buf]
      and (filetype == 'cpp' or filetype == 'c')
      and vim.startswith(vim.api.nvim_buf_get_name(buf), root .. '/') then
      attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
          state.generation = state.generation + 1
          if state.job then state.job:kill(15); state.job = nil end
          state.needs_check = true
        end,
        on_detach = function() attached[buf] = nil end,
      })
    end
  end
end

-- Returns the argv prefix that starts Python 3, or nil. On Windows the Microsoft Store
-- "python3" alias is a stub that only opens the Store, so prefer the py launcher.
function M.python()
  if vim.fn.has 'win32' == 1 then
    local launcher = vim.fn.exepath 'py'
    if launcher ~= '' then return { launcher, '-3' } end
    for _, name in ipairs { 'python3', 'python' } do
      local path = vim.fn.exepath(name)
      if path ~= '' and not path:lower():find('microsoft[/\\]windowsapps[/\\]') then return { path } end
    end
    return nil
  end
  local python = vim.fn.exepath 'python3'
  return python ~= '' and { python } or nil
end

function M.run(buf, opts)
  opts = opts or {}
  if not buf or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local root, database = database_for(buf)
  if not root then
    if not opts.quiet then vim.notify('C++ check needs a compile_commands.json for this project', vim.log.levels.WARN) end
    return false
  end
  local python = M.python()
  local runner = vim.api.nvim_get_runtime_file('tools/cpp_check.py', false)[1]
  if not python or not runner then
    vim.notify('C++ compiler checks need Python 3 and the jvim check helper', vim.log.levels.ERROR)
    return false
  end
  local state = projects[root] or { generation = 0, buffers = {} }
  projects[root] = state
  state.pending = (state.pending or 0) + 1
  state.generation = state.generation + 1
  if state.job then state.job:kill(15); state.job = nil end
  state.saving = true
  require('jvim.autosave').save_all()
  state.saving = false
  watch_buffers(root, state)
  local generation = state.generation
  state.needs_check = true
  state.job = vim.system(vim.list_extend(vim.list_extend({}, python), { runner, database }), { text = true }, function(result)
    vim.schedule(function()
      if state.generation ~= generation then return end
      state.job = nil
      if result.code ~= 0 then
        vim.notify('C++ compiler check failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local ok, report = pcall(vim.json.decode, result.stdout)
      if not ok then vim.notify('Invalid C++ compiler check result', vim.log.levels.ERROR); return end
      local diagnostics, keys, failures = {}, {}, {}
      local function add(target, diagnostic)
        local key = table.concat({ target, diagnostic.lnum, diagnostic.col, diagnostic.severity, diagnostic.message }, ':')
        if keys[key] then return end
        keys[key] = true
        diagnostics[target] = diagnostics[target] or {}
        table.insert(diagnostics[target], diagnostic)
      end
      for _, run in ipairs(report.runs) do
        local source_error = false
        local items = vim.fn.getqflist { lines = vim.split(run.output, '\n'), efm = errorformat }.items
        for _, item in ipairs(items) do
          if item.valid == 1 and item.bufnr > 0 and (item.type == 'e' or item.type == 'f' or item.type == 'w') then
            if item.type ~= 'w' then source_error = true end
            add(item.bufnr, {
              lnum = item.lnum - 1, col = math.max(item.col - 1, 0), message = item.text,
              severity = item.type == 'w' and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
              source = 'C++ compiler',
            })
          end
        end
        if run.code ~= 0 and not source_error then table.insert(failures, run.output) end
      end
      local complete = #report.errors == 0 and #failures == 0 and report.checked > 0
      if complete then
        for previous in pairs(state.buffers) do
          if vim.api.nvim_buf_is_valid(previous) then vim.diagnostic.reset(namespace, previous) end
        end
        state.buffers = {}
      else
        -- A failed launch/timeout is not proof that previous errors are fixed.
        for previous in pairs(state.buffers) do
          if vim.api.nvim_buf_is_valid(previous) then
            for _, diagnostic in ipairs(vim.diagnostic.get(previous, { namespace = namespace })) do add(previous, diagnostic) end
          end
        end
      end
      for target, list in pairs(diagnostics) do
        vim.diagnostic.set(namespace, target, list)
        state.buffers[target] = true
      end
      state.needs_check = not complete or next(diagnostics) ~= nil
      if #report.errors > 0 then vim.notify(table.concat(report.errors, '\n'), vim.log.levels.WARN) end
      if #failures > 0 then
        vim.notify('C++ compiler failed without a source diagnostic:\n' .. table.concat(failures, '\n'), vim.log.levels.WARN)
      elseif report.checked == 0 and #report.errors == 0 then
        vim.notify('The compilation database has no source files to check', vim.log.levels.WARN)
      end
      if opts.on_complete then opts.on_complete(report) end
    end)
  end)
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup('jvim-cpp-check', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'FileType' }, {
    group = group,
    callback = function(args)
      local root = database_for(args.buf)
      if root and projects[root] then watch_buffers(root, projects[root]) end
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'cpp' and vim.bo[args.buf].filetype ~= 'c' then return end
      local root = database_for(args.buf)
      local state = root and projects[root]
      if not state or state.saving or not state.needs_check then return end
      state.pending = (state.pending or 0) + 1
      local pending = state.pending
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(args.buf) and state.pending == pending then M.run(args.buf, { quiet = true }) end
      end, 750)
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, state in pairs(projects) do
        state.generation = state.generation + 1
        if state.job then state.job:kill(15) end
      end
    end,
  })
end

return M
