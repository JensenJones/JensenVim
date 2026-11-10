vim.o.swapfile = false
-- Leave 'columns' alone: headless Neovim 0.12 (no UI attached) segfaults opening a terminal after it
-- changes, on Linux and Windows alike. With a UI attached, any width works.
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root = vim.fs.normalize(vim.env.JVIM_TEST_PROJECT)
vim.cmd.cd(vim.fn.fnameescape(root))
local case = vim.env.JVIM_TEST_CASE
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect { actual = actual, expected = expected })
end
local function wait_for(predicate)
  assert(vim.wait(4000, predicate, 10), 'timed out waiting for process lifecycle')
end
local function configuration(command)
  return { version = 1, configurations = { { name = 'Example', command = command, cwd = '.', env = { JVIM_WORKFLOW_VALUE = 'hello spaces' } } } }
end
local function save_config(data)
  vim.fn.mkdir(root .. '/.jvim', 'p')
  vim.fn.writefile({ vim.json.encode(data) }, root .. '/.jvim/run.json')
end
if case == 'validation' then
  local run = require 'jvim.run'
  local valid = configuration { 'sh', '-c', 'echo hello' }
  save_config(valid)
  local entries, err = run.load(root)
  assert(entries and not err)
  equal(entries[1].cwd, root)
  for _, bad in ipairs {
    { version = 2, configurations = {} },
    configuration('echo hello'), configuration {}, configuration { '' }, configuration { 'sh', 3 },
    { version = 1, configurations = { { name = 'bad', command = { 'sh' }, cwd = 'missing' } } },
    { version = 1, configurations = { { name = 'bad', command = { 'sh' }, env = { ['BAD=KEY'] = 'x' } } } },
    { version = 1, configurations = { { name = 'bad', command = { 'sh' }, env = { X = 1 } } } },
    { version = 1, configurations = { { name = 'bad', command = { 'sh' }, env = {} } } },
    { version = 1, configurations = { { name = 'same', command = { 'sh' } }, { name = 'same', command = { 'sh' } } } },
  } do
    save_config(bad)
    local result, message = run.load(root)
    assert(not result and type(message) == 'string', 'invalid configuration accepted: ' .. vim.inspect(bad))
  end
  assert(#vim.tbl_filter(function(b) return vim.bo[b].buftype == 'terminal' end, vim.api.nvim_list_bufs()) == 0,
    'reading configuration executed a command')
elseif case == 'execution' then
  local run = require 'jvim.run'
  save_config(configuration { 'sh', '-c', 'printf "%s\\n%s\\n%s\\n" "$PWD" "$JVIM_WORKFLOW_VALUE" "$1"; exit 7', 'sh', 'literal $HOME; space' })
  local session = assert(run.run('Example', root))
  wait_for(function() return session.status == 'exited' end)
  equal(session.exit_code, 7)
  local text = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), '\n')
  for _, value in ipairs { root, 'hello spaces', 'literal $HOME; space' } do assert(text:find(value, 1, true), text) end
  assert(text:find('exit 7', 1, true), 'terminal output omitted exit status: ' .. text)
elseif case == 'lifecycle' then
  local run = require 'jvim.run'
  save_config(configuration { 'sh', '-c', 'echo started; sleep 30' })
  local first = assert(run.run('Example', root))
  equal(run.run('Example', root), first)
  require('jvim.command_terminal').hide()
  assert(vim.api.nvim_buf_is_valid(first.buf))
  equal(run.show(root), first)
  assert(run.stop(root))
  wait_for(function() return first.status == 'exited' end)
  local second = assert(run.rerun(root))
  assert(second ~= first and second.buf ~= first.buf)
  run.stop(root)
  wait_for(function() return second.status == 'exited' end)
elseif case == 'shell' then
  local terminal = require 'jvim.command_terminal'
  local first = assert(terminal.open())
  terminal.hide()
  local second = assert(terminal.open())
  equal(first, second)
  terminal.stop(first)
  wait_for(function() return first.status == 'exited' end)
elseif case == 'edit' then
  local run = require 'jvim.run'
  run.edit(root)
  assert(vim.fn.isdirectory(root .. '/.jvim') == 1)
  equal(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), root .. '/.jvim/run.json')
  assert(vim.bo.buflisted, 'configuration editor is missing from file tabs')
  assert(vim.tbl_contains(require('jvim.files').list(), vim.api.nvim_get_current_buf()))
  local data = vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'))
  equal(data.version, 1)
  equal(data.configurations, {})
  assert(vim.bo.modified)
  assert(vim.fn.filereadable(root .. '/.jvim/run.json') == 0, 'edit unexpectedly wrote configuration')
elseif case == 'steps' then
  local run = require 'jvim.run'
  vim.o.shell = 'sh'
  save_config { version = 1, configurations = { { name = 'Steps', commands = {
    'echo "first step" > order.txt', 'echo second | tr a-z A-Z >> order.txt && echo "$JVIM_STEP"', 'exit 3', 'echo never >> order.txt',
  }, env = { JVIM_STEP = 'env reached' } } } }
  local session = assert(run.run('Steps', root))
  wait_for(function() return session.status == 'exited' end)
  equal(session.exit_code, 3)
  equal(vim.fn.readfile(root .. '/order.txt'), { 'first step', 'SECOND' })
  local text = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), '\n')
  for _, value in ipairs { '$ echo "first step" > order.txt', 'env reached', '$ exit 3' } do assert(text:find(value, 1, true), text) end
  assert(not text:find('$ echo never', 1, true), 'run continued after a failing step: ' .. text)
elseif case == 'steps_windows' then
  local run = require 'jvim.run'
  save_config { version = 1, configurations = { { name = 'Steps', commands = {
    'echo first step> order.txt', 'echo %JVIM_STEP%>> order.txt', 'exit /b 3', 'echo never>> order.txt',
  }, env = { JVIM_STEP = 'env reached' } } } }
  local session = assert(run.run('Steps', root))
  wait_for(function() return session.status == 'exited' end)
  equal(session.exit_code, 3)
  equal(vim.fn.readfile(root .. '/order.txt'), { 'first step', 'env reached' })
elseif case == 'form' then
  local run = require 'jvim.run'
  local buf = run.form(root)
  assert(vim.bo[buf].buftype == 'acwrite' and vim.api.nvim_win_get_config(0).relative == 'editor', 'form is not a floating editor')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# comment', 'Name: Build and run', '', '# Commands', 'echo one', '', '  echo two  ' })
  vim.cmd.write()
  wait_for(function() return not vim.api.nvim_buf_is_valid(buf) end)
  local entries = assert(run.load(root))
  equal(entries[1].name, 'Build and run')
  equal(entries[1].commands, { 'echo one', 'echo two' })
  assert(table.concat(vim.fn.readfile(root .. '/.jvim/run.json'), '\n'):find('"name": "Build and run",\n      "commands": [', 1, true),
    'run.json is not readable: ' .. table.concat(vim.fn.readfile(root .. '/.jvim/run.json'), '\n'))
  equal(select(2, run.current(root)), 'Build and run')
  save_config(configuration { 'sh', '-c', 'echo legacy' })
  buf = run.form(root, 'Example')
  -- Legacy argv commands become one shell line quoted for the user's shell (cmd.exe uses double quotes).
  local legacy = vim.fn.has 'win32' == 1 and 'sh -c "echo legacy"' or "sh -c 'echo legacy'"
  equal(vim.api.nvim_buf_get_lines(buf, 5, 6, false), { legacy })
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'Name: Renamed' })
  vim.cmd.write()
  wait_for(function() return not vim.api.nvim_buf_is_valid(buf) end)
  entries = assert(run.load(root))
  equal({ entries[1].name, entries[1].commands, entries[1].command, entries[1].env.JVIM_WORKFLOW_VALUE }, { 'Renamed', { legacy }, nil, 'hello spaces' })
  assert(not run.save_form(root, nil, { 'Name: Renamed', 'echo x' }), 'duplicate name accepted')
  assert(not run.save_form(root, nil, { 'Name: Empty' }), 'configuration without commands accepted')
  equal(run.save_form(root, 'Renamed', { 'Name: Renamed' }), false)
  equal(assert(run.load(root)), {})
  assert(#vim.tbl_filter(function(b) return vim.bo[b].buftype == 'terminal' end, vim.api.nvim_list_bufs()) == 0, 'saving the form ran a command')
elseif case == 'project' then
  local run = require 'jvim.run'
  vim.fn.mkdir(root .. '/tools', 'p')
  vim.fn.mkdir(root .. '/src/nested', 'p')
  vim.fn.writefile({ '#!/bin/sh', 'printf "custom path command\\n"' }, root .. '/tools/jvim-workflow-command')
  vim.fn.setfperm(root .. '/tools/jvim-workflow-command', 'rwxr-xr-x')
  local data = configuration { 'jvim-workflow-command' }
  data.configurations[1].env.PATH = root .. '/tools'
  save_config(data)
  vim.cmd.cd(vim.fn.fnameescape(root .. '/src/nested'))
  vim.cmd.edit(vim.fn.fnameescape(root .. '/src/nested/main.txt'))
  equal(run.root(), root)
  local session = assert(run.run('Example'))
  wait_for(function() return session.status == 'exited' end)
  equal(session.exit_code, 0)
  assert(table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), '\n'):find('custom path command', 1, true))
  equal(run.root(), root)
else
  local merge = require 'jvim.merge'
  local buf = vim.api.nvim_get_current_buf()
  local lines = { 'before', '<<<<<<< ours', 'ours α', '=======', 'theirs β', '>>>>>>> theirs', 'after' }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd('let &undolevels = &undolevels')
  if case == 'merge' then
    local conflicts = assert(merge.parse(lines))
    equal(#conflicts, 1)
    assert(merge.resolve(buf, 1, 'both'))
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'before', 'ours α', 'theirs β', 'after' })
    vim.cmd.undo()
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines)
    assert(merge.resolve(buf, 1, 'theirs'))
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'before', 'theirs β', 'after' })
  elseif case == 'diff3' then
    lines = { 'before', '<<<<<<< ours', '||||||| base', 'original', '=======', 'incoming', '>>>>>>> theirs', 'after' }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local conflicts = assert(merge.parse(lines))
    equal(conflicts[1].ours, {})
    equal(conflicts[1].base, { 'original' })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'manual edit' })
    assert(merge.resolve(buf, 1, 'ours'))
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'manual edit', 'before', 'after' })
  elseif case == 'malformed' then
    for _, malformed in ipairs {
      { '<<<<<<< ours', 'oops' }, { '=======', 'orphan' },
      { '<<<<<<< ours', '<<<<<<< nested', '=======', 'x', '>>>>>>> end' },
      { '<<<<<<< ours', 'x', '>>>>>>> end' },
      { '<<<<<<< ours', '||||||| base', 'a', '||||||| twice', '=======', 'b', '>>>>>>> end' },
    } do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, malformed)
      local ok, err = merge.resolve(buf, 1, 'ours')
      assert(not ok and err)
      equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), malformed)
    end
  elseif case == 'merge_ui' then
    local session = assert(merge.open())
    equal(session.buf, buf)
    assert(#session.previews == 2)
    for _, preview in ipairs(session.previews) do
      assert(not vim.bo[preview].modifiable and vim.bo[preview].readonly)
      assert(vim.wo[vim.fn.bufwinid(preview)].diff)
    end
    assert(vim.bo[buf].modifiable)
    assert(merge.accept('ours'))
    merge.close()
    assert(vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified)
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'before', 'ours α', 'after' })
  elseif case == 'merge_navigation' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      'before', '<<<<<<< ours', 'a', '||||||| base', 'original', '=======', 'b', '>>>>>>> theirs',
      'middle', '<<<<<<< ours', 'c', '=======', 'd', '>>>>>>> theirs', 'after',
    })
    local session = assert(merge.open())
    equal(#session.previews, 3)
    assert(table.concat(vim.api.nvim_buf_get_lines(session.previews[3], 0, -1, false), '\n'):find('original', 1, true))
    assert(merge.navigate(1))
    equal(vim.api.nvim_win_get_cursor(session.win)[1], 10)
    vim.fn.JvimMergeTheirs(0, 1, 'l', '')
    equal(#assert(merge.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))), 1)
    assert(merge.navigate(-1))
    assert(merge.accept('base'))
    equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'before', 'original', 'middle', 'd', 'after' })
    merge.close()
  elseif case == 'statusline' then
    local fold = require 'jvim.fold_controls'
    local statusline = {}
    fold.setup(statusline)
    local value = statusline.section_location()
    assert(value:find('Fold', 1, true) and value:find('Run', 1, true) and value:find('Config', 1, true), value)
    save_config(configuration { 'sh' })
    vim.cmd.edit(vim.fn.fnameescape(root .. '/main.txt'))
    local origin = vim.api.nvim_get_current_win()
    vim.cmd 'botright new'
    vim.fn.mkdir(root .. '/other/.jvim', 'p')
    local other = configuration { 'sh' }
    other.configurations[1].name = 'Other project'
    vim.fn.writefile({ vim.json.encode(other) }, root .. '/other/.jvim/run.json')
    vim.api.nvim_buf_set_name(0, root .. '/other/main.txt')
    local names
    vim.ui.select = function(items) names = vim.tbl_map(function(item) return item.name end, items) end
    vim.fn.JvimRunConfig(origin, 1, 'l', '')
    equal(names, { 'Example' })
  else
    error('unknown workflow test: ' .. case)
  end
end
vim.cmd 'qall!'
