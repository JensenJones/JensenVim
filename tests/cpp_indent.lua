vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_SITE)
vim.o.autoindent = true
vim.bo.filetype = 'cpp'
vim.bo.shiftwidth = 4
vim.bo.indentexpr = "v:lua.require'custom.cpp_indent'.indent()"

local function split_before(line, fragment, anchor)
  vim.cmd 'normal! \27'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'void f() {', line, '}' })
  local split = assert(line:find(fragment, 1, true)) - 1
  local expected = assert(line:find(anchor, 1, true)) - 1
  vim.api.nvim_win_set_cursor(0, { 2, split })
  vim.api.nvim_feedkeys(vim.keycode('i<CR><Esc>'), 'xt', false)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.fn.indent(3) == expected,
    vim.inspect(lines) .. ' expected column ' .. expected .. ', got ' .. vim.fn.indent(3))
end

split_before('                auto filledResult = otherBook.matchBestResting(Aggressor{.id = message.id, .quantity = remainingQuantity});', '.quantity', '.id')
split_before('    consume(first, second, third);', 'second', 'first')
split_before('    consume(first, second, third);', ', third', ', second')
split_before('    void work(int first, double second);', 'double', 'int')
split_before('    using Pair = std::pair<int, double>;', 'double', 'int')
split_before('    auto value = ready ? first : second;', ': second', '? first')
local ternary = '    auto value = ready ? first : second;'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'void f() {',ternary,'}'})
vim.api.nvim_win_set_cursor(0,{2,assert(ternary:find('?',1,true))-1})
vim.api.nvim_feedkeys(vim.keycode('i<CR><Esc>'),'xt',false)
local question = vim.api.nvim_buf_get_lines(0,2,3,false)[1]
vim.api.nvim_win_set_cursor(0,{3,assert(question:find(':',1,true))-1})
vim.api.nvim_feedkeys(vim.keycode('i<CR><Esc>'),'xt',false)
assert(vim.fn.indent(3)==vim.fn.indent(4),'split ? and : did not align')
print('Enter aligns initializer fields, arguments, commas, parameters, templates and ternary operators')
vim.cmd 'qa!'
