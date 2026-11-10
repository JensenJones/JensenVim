local M = {}
local effective, source, selected_profile
local problems = {}

local defaults = {
  mode = 'standalone',
  offline = false,
  plugins = { enabled = true, install = true, specs = {} },
  tools = { mason = true, install = true, path = 'prepend' },
  lsp = { default_servers = true, servers = {} },
  treesitter = {
    auto_install = true,
    parsers = { 'bash', 'c', 'cpp', 'java', 'python', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
  },
  formatting = { on_save = true, organise_includes = true, formatters_by_ft = {}, formatters = {} },
  completion = { fuzzy = 'prefer_rust' },
  -- PDF/image previews use image.nvim, which does not support Windows.
  features = { project_tree = true, autosave = true, compiler_checks = true, pdf = vim.fn.has 'win32' ~= 1, folds = true, word_highlight = true },
  ui = { theme = 'jvim-charcoal', icons = true, tabline = true, statusline = true },
}

local function merge(base, override)
  local result = vim.deepcopy(base)
  for key, value in pairs(override) do
    local previous = result[key]
    if type(value) == 'table' and type(previous) == 'table'
      and not (vim.islist(value) and #value > 0) and not (vim.islist(previous) and #previous > 0) then
      result[key] = merge(previous, value)
    else
      result[key] = vim.deepcopy(value)
    end
  end
  return result
end

local function expect(value, kind, path)
  assert(type(value) == kind, ('jvim option %s must be %s'):format(path, kind))
end

local function string_list(value, path)
  expect(value, 'table', path)
  assert(vim.islist(value), 'jvim option ' .. path .. ' must be a list')
  for _, item in ipairs(value) do expect(item, 'string', path .. '[]') end
end

local function validate(opts)
  local allowed = { profile = true, before_setup = true, after_setup = true }
  for key in pairs(defaults) do allowed[key] = true end
  for key in pairs(opts) do assert(allowed[key], 'Unknown jvim option: ' .. tostring(key)) end
  assert(opts.mode == 'standalone' or opts.mode == 'overlay', 'jvim mode must be standalone or overlay')
  expect(opts.offline, 'boolean', 'offline')
  for _, section in ipairs { 'plugins', 'tools', 'lsp', 'treesitter', 'formatting', 'completion', 'features', 'ui' } do
    expect(opts[section], 'table', section)
    for key in pairs(opts[section]) do
      assert(defaults[section][key] ~= nil, 'Unknown jvim option: ' .. section .. '.' .. tostring(key))
    end
  end
  for _, path in ipairs {
    { 'plugins', 'enabled' }, { 'plugins', 'install' }, { 'tools', 'mason' }, { 'tools', 'install' },
    { 'lsp', 'default_servers' }, { 'treesitter', 'auto_install' }, { 'formatting', 'on_save' },
    { 'formatting', 'organise_includes' }, { 'ui', 'icons' }, { 'ui', 'tabline' }, { 'ui', 'statusline' },
  } do expect(opts[path[1]][path[2]], 'boolean', table.concat(path, '.')) end
  for key, value in pairs(opts.features) do expect(value, 'boolean', 'features.' .. key) end
  assert(opts.ui.theme == false or type(opts.ui.theme) == 'string', 'jvim ui.theme must be a colour scheme name or false')
  assert(vim.tbl_contains({ 'lua', 'prefer_rust', 'prefer_rust_with_warning', 'rust' }, opts.completion.fuzzy), 'Invalid jvim completion.fuzzy')
  expect(opts.plugins.specs, 'table', 'plugins.specs')
  assert(vim.islist(opts.plugins.specs), 'jvim plugins.specs must be a list')
  for _, spec in ipairs(opts.plugins.specs) do assert(type(spec) == 'string' or type(spec) == 'table', 'jvim plugin specifications must be strings or tables') end
  assert(vim.tbl_contains({ 'prepend', 'append', 'skip' }, opts.tools.path), 'Invalid jvim tools.path')
  string_list(opts.treesitter.parsers, 'treesitter.parsers')
  expect(opts.lsp.servers, 'table', 'lsp.servers')
  for name, server in pairs(opts.lsp.servers) do
    expect(name, 'string', 'lsp.servers key')
    assert(server == false or type(server) == 'table', 'jvim lsp.servers.' .. name .. ' must be a table or false')
    if type(server) == 'table' and server.cmd then
      string_list(server.cmd, 'lsp.servers.' .. name .. '.cmd')
      assert(#server.cmd > 0, 'jvim server command cannot be empty')
    end
  end
  expect(opts.formatting.formatters_by_ft, 'table', 'formatting.formatters_by_ft')
  expect(opts.formatting.formatters, 'table', 'formatting.formatters')
  for _, callback in ipairs { 'before_setup', 'after_setup' } do
    if opts[callback] ~= nil then expect(opts[callback], 'function', callback) end
  end
end

local function user_path()
  if vim.env.JVIM_CONFIG and vim.env.JVIM_CONFIG ~= '' then return vim.fn.expand(vim.env.JVIM_CONFIG) end
  return vim.fs.dirname(vim.fn.stdpath 'config') .. '/jvim-user/init.lua'
end

function M.setup(overrides)
  overrides = overrides or {}
  expect(overrides, 'table', 'setup')
  problems = {}
  source = user_path()
  selected_profile = overrides.profile or vim.env.JVIM_PROFILE
  local personal = {}
  if vim.fn.filereadable(source) == 1 then
    local ok, result = pcall(dofile, source)
    if not ok or type(result) ~= 'table' then
      problems[#problems + 1] = 'Cannot load ' .. source .. ': ' .. tostring(result)
    else
      personal = result
    end
  elseif vim.env.JVIM_CONFIG and vim.env.JVIM_CONFIG ~= '' then
    problems[#problems + 1] = 'Personal configuration does not exist: ' .. source
  end
  local profiles = personal.profiles
  personal.profiles = nil
  if selected_profile and selected_profile ~= '' then
    if type(profiles) ~= 'table' or type(profiles[selected_profile]) ~= 'table' then
      problems[#problems + 1] = 'Unknown jvim profile: ' .. tostring(selected_profile)
    else
      personal = merge(personal, profiles[selected_profile])
    end
  end
  local base = vim.deepcopy(defaults)
  if overrides.mode == 'overlay' then
    base.mode = 'overlay'
    base.plugins.enabled, base.plugins.install = false, false
    base.tools.mason, base.tools.install = false, false
    base.tools.path = 'skip'
    base.lsp.default_servers = false
    base.treesitter.auto_install = false
    base.formatting.on_save, base.formatting.organise_includes = false, false
    for key in pairs(base.features) do base.features[key] = false end
    base.ui.theme, base.ui.tabline, base.ui.statusline = false, false, false
  end
  local ok, combined = pcall(function()
    local value = merge(base, personal)
    validate(value)
    return value
  end)
  if not ok then
    problems[#problems + 1] = tostring(combined)
    combined = base
  end
  combined = merge(combined, overrides)
  validate(combined)
  if #problems > 0 or vim.tbl_contains({ '1', 'true', 'yes' }, (vim.env.JVIM_OFFLINE or ''):lower()) then combined.offline = true end
  if combined.offline then
    combined.plugins.install = false
    combined.tools.install = false
    combined.treesitter.auto_install = false
    combined.completion.fuzzy = 'lua'
  end
  effective = combined
  for _, problem in ipairs(problems) do
    vim.schedule(function() vim.notify(problem, vim.log.levels.ERROR, { title = 'jvim configuration' }) end)
  end
  return effective
end

function M.get() return effective or M.setup {} end
function M.source() return source or user_path() end
function M.profile() return selected_profile end
function M.errors() return vim.deepcopy(problems) end
M.merge = merge

return M
