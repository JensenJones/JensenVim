-- blink.cmp source for the run configuration form: commands on PATH, shell builtins and "Run: <name>" lines.
local M = {}

local windows = vim.fn.has 'win32' == 1
-- Run lines go to sh -c, or cmd.exe on Windows.
local builtins = windows and { 'cd', 'copy', 'del', 'dir', 'echo', 'exit', 'mkdir', 'move', 'rmdir', 'set', 'type' }
  or { 'cd', 'echo', 'exit', 'export', 'false', 'printf', 'pwd', 'set', 'sleep', 'source', 'test', 'true', 'unset' }
local commands

-- On Windows only PATHEXT files are programs, and they are typed without the extension.
local function program_name(name)
  if not windows then return name end
  local stem, extension = name:match '^(.+)(%.[^.]+)$'
  if not stem then return nil end
  for allowed in (vim.env.PATHEXT or '.COM;.EXE;.BAT;.CMD'):gmatch '[^;]+' do
    if allowed:lower() == extension:lower() then return stem end
  end
end

local function command_names()
  if commands then return commands end
  local seen = {}
  commands = {}
  local function add(name)
    if not seen[name] then seen[name] = true; commands[#commands + 1] = name end
  end
  for _, name in ipairs(builtins) do add(name) end
  for directory in vim.gsplit(vim.env.PATH or '', windows and ';' or ':', { plain = true }) do
    if directory ~= '' and vim.fn.isdirectory(directory) == 1 then
      for name, kind in vim.fs.dir(directory) do
        local program = (kind == 'file' or kind == 'link') and program_name(name)
        if program then add(program) end
      end
    end
  end
  table.sort(commands)
  return commands
end

-- The folder commands run in: the form's Directory line, relative to the project root.
function M.cwd(bufnr)
  local root = vim.b[bufnr].jvim_run_root
  if not root then return vim.fn.expand(('#%d:p:h'):format(bufnr)) end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local directory = vim.trim(line):match '^Directory:%s*(.-)$'
    if directory and directory ~= '' then
      directory = vim.fs.normalize(vim.fn.expand(directory))
      if not vim.startswith(directory, '/') and not directory:match '^%a:[/\\]' then directory = root .. '/' .. directory end
      return vim.fn.isdirectory(directory) == 1 and directory or root
    end
  end
  return root
end

function M.new() return setmetatable({}, { __index = M }) end

function M:get_completions(context, callback)
  local before = context.line:sub(1, context.cursor[2])
  local items = {}
  -- Only the first word of a command line is a command; later words are paths, left to the path source.
  if before:match '^%s*[%w%._%-]*$' then
    local kind = require('blink.cmp.types').CompletionItemKind
    for _, name in ipairs(command_names()) do items[#items + 1] = { label = name, kind = kind.Function } end
    for _, name in ipairs(vim.b[context.bufnr].jvim_run_names or {}) do
      items[#items + 1] = { label = 'Run: ' .. name, kind = kind.Reference, documentation = 'Run the configuration "' .. name .. '" here' }
    end
  end
  callback { items = items, is_incomplete_forward = false, is_incomplete_backward = false }
end

return M
