local M = {}

local markers = { '.git', 'CMakeLists.txt', 'compile_commands.json', 'compile_flags.txt', 'package.json', 'pyproject.toml' }

local function project_root(root)
  root = root or vim.fn.getcwd()
  root = vim.fn.fnamemodify(root, ':p')
  if vim.fn.isdirectory(root) ~= 1 then root = vim.fs.dirname(root) end
  return vim.uv.fs_realpath(root) or root
end

local active_root

local function metadata_path(root)
  local directory = vim.fn.stdpath('state') .. '/jvim/sessions'
  vim.fn.mkdir(directory, 'p')
  return directory .. '/' .. vim.fn.sha256(root) .. '.json'
end

function M.root(root)
  root = project_root(root)
  return vim.fs.root(root, markers) or root
end

-- Saves under the root jvim started in, so closing and relaunching in that repository use the same workspace.
function M.save(root)
  root = M.root(root or active_root)
  local layout = require('jvim.files').snapshot()
  if not layout then return false, 'no editor splits to save' end
  local file, open_err = io.open(metadata_path(root), 'w')
  if not file then return false, open_err end
  local wrote, write_err = pcall(file.write, file, vim.json.encode { version = 2, root = root, layout = layout })
  file:close()
  if not wrote then return false, write_err end
  return true
end

function M.restore(root)
  root = M.root(root)
  active_root = root
  local file = io.open(metadata_path(root), 'r')
  if not file then return false end
  local contents = file:read('*a')
  file:close()
  local ok, metadata = pcall(vim.json.decode, contents)
  if not ok or type(metadata) ~= 'table' or metadata.version ~= 2 or metadata.root ~= root then return false end
  local restored, err = pcall(require('jvim.files').restore_snapshot, metadata.layout)
  if not restored then
    vim.notify('Could not restore jvim workspace: ' .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return err
end

return M
