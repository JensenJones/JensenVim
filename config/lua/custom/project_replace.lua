local M = {}

function M.open()
  local root = vim.fn.getcwd()
  vim.ui.input({ prompt = 'Replace in project — find literal text: ' }, function(find)
    if not find or find == '' then return end
    vim.system({ 'rg', '--files-with-matches', '--null', '--fixed-strings', '--', find, root }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify(result.code == 1 and 'No matching files' or result.stderr, result.code == 1 and vim.log.levels.INFO or vim.log.levels.ERROR)
          return
        end
        local files = vim.split(result.stdout, '\0', { trimempty = true })
        local items = vim.tbl_map(function(file) return { filename = file, lnum = 1, col = 1, text = find } end, files)
        vim.fn.setqflist({}, ' ', { title = 'Project matches: ' .. find, items = items })
        vim.ui.select({ 'Review matching files', 'Replace with confirmation at each match' }, { prompt = #files .. ' matching files' }, function(choice)
          if choice == 'Review matching files' then
            vim.cmd.copen()
          elseif choice == 'Replace with confirmation at each match' then
            vim.ui.input({ prompt = 'Replace with: ' }, function(replacement)
              if replacement == nil then return end
              local pattern = '\\V' .. vim.fn.escape(find, '\\/')
              local value = vim.fn.escape(replacement, '\\/&')
              -- Leave changes in buffers for review and explicit Save All.
              vim.cmd('cfdo %s/' .. pattern .. '/' .. value .. '/gce')
              vim.cmd.startinsert()
            end)
          end
        end)
      end)
    end)
  end)
end

return M
