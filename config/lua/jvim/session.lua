local M = {}

local markers = { '.git', 'CMakeLists.txt', 'compile_commands.json', 'compile_flags.txt', 'package.json', 'pyproject.toml' }

local function project_root(root)
  root = root or vim.fn.getcwd()
  root = vim.fn.fnamemodify(root, ':p')
  if vim.fn.isdirectory(root) ~= 1 then root = vim.fs.dirname(root) end
  return vim.uv.fs_realpath(root) or root
end

local function paths(root)
  local directory = vim.fn.stdpath('state') .. '/jvim/sessions'
  vim.fn.mkdir(directory, 'p')
  local stem = directory .. '/' .. vim.fn.sha256(root)
  return stem .. '.vim', stem .. '.json'
end

function M.root()
  local cwd = project_root()
  return vim.fs.root(cwd, markers) or cwd
end

function M.save(root)
  root = project_root(root or M.root())
  local session_path, metadata_path = paths(root)
  local ok, err = pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(session_path))
  if not ok then return false, err end
  local metadata = { root = root, panes = require('jvim.files').snapshot() }
  local file, open_err = io.open(metadata_path, 'w')
  if not file then return false, open_err end
  local wrote, write_err = pcall(file.write, file, vim.json.encode(metadata))
  file:close()
  if not wrote then return false, write_err end
  return true
end

function M.restore(root)
  root = project_root(root or M.root())
  local session_path, metadata_path = paths(root)
  if vim.fn.filereadable(session_path) ~= 1 or vim.fn.filereadable(metadata_path) ~= 1 then return false end
  local file = io.open(metadata_path, 'r')
  if not file then return false end
  local contents = file:read('*a')
  file:close()
  local ok, metadata = pcall(vim.json.decode, contents)
  if not ok or type(metadata) ~= 'table' or metadata.root ~= root or type(metadata.panes) ~= 'table' then return false end
  local sourced, err = pcall(vim.cmd, 'silent source ' .. vim.fn.fnameescape(session_path))
  if not sourced then
    vim.notify('Could not restore jvim workspace: ' .. tostring(err), vim.log.levels.WARN)
    return false
  end
  require('jvim.files').restore_snapshot(metadata.panes)
  return true
end

return M
