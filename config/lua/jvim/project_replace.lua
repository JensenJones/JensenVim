local M = {}

local function replace_matches(find, opts)
  opts = opts or {}
  local root = opts.root or vim.fn.getcwd()
  local args = { 'rg', '--files-with-matches', '--null', '--fixed-strings' }
  if opts.word then args[#args + 1] = '--word-regexp' end
  for _, glob in ipairs(opts.globs or {}) do
    vim.list_extend(args, { '--glob', glob })
  end
  vim.list_extend(args, { '--', find, root })
  vim.system(args, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify(result.code == 1 and 'No matching files' or result.stderr, result.code == 1 and vim.log.levels.INFO or vim.log.levels.ERROR)
          return
        end
        local files = vim.split(result.stdout, '\0', { trimempty = true })
        local items = vim.tbl_map(function(file) return { filename = file, lnum = 1, col = 1, text = find } end, files)
        vim.fn.setqflist({}, ' ', { title = (opts.title or 'Project matches') .. ': ' .. find, items = items })
        vim.ui.select({ 'Review matching files', 'Replace with confirmation at each match' }, { prompt = #files .. ' matching files' }, function(choice)
          if choice == 'Review matching files' then
            vim.cmd.copen()
          elseif choice == 'Replace with confirmation at each match' then
            local function apply(replacement)
              if replacement == nil then return end
              local pattern = '\\V' .. (opts.word and ('\\<' .. vim.fn.escape(find, '\\/') .. '\\>') or vim.fn.escape(find, '\\/'))
              local value = vim.fn.escape(replacement, '\\/&')
              -- Leave changes in buffers for review and explicit Save All.
              vim.cmd('cfdo %s/' .. pattern .. '/' .. value .. '/gce')
              if opts.resume_insert ~= false then vim.cmd.startinsert() end
            end
            if opts.replacement ~= nil then
              apply(opts.replacement)
            else
              vim.ui.input({ prompt = 'Replace with: ' }, apply)
            end
          end
        end)
      end)
  end)
end

function M.open()
  vim.ui.input({ prompt = 'Replace in project — find literal text: ' }, function(find)
    if find and find ~= '' then replace_matches(find) end
  end)
end

function M.rename_namespace(old_name, root)
  vim.ui.input({ prompt = 'Rename namespace ' .. old_name .. ' to: ' }, function(new_name)
    if not new_name or new_name == '' or new_name == old_name then return end
    if not new_name:match('^[%a_][%w_]*$') then
      vim.notify('Namespace names must be a single C++ identifier', vim.log.levels.ERROR)
      return
    end
    replace_matches(old_name, {
      root = root,
      word = true,
      globs = { '*.h', '*.hh', '*.hpp', '*.hxx', '*.c', '*.cc', '*.cpp', '*.cxx', '*.ipp', '*.inl', '*.cu', '*.cuh' },
      replacement = new_name,
      resume_insert = false,
      title = 'Namespace rename candidates',
    })
  end)
end

return M
