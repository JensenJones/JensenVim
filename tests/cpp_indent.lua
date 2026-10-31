vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_CONFIG .. '/after')
vim.opt.rtp:append(vim.env.JVIM_TEST_SITE)
local ts = vim.fs.dirname(vim.env.JVIM_TEST_SITE) .. '/lazy/nvim-treesitter'
vim.opt.rtp:append(ts)
vim.opt.rtp:append(ts .. '/runtime')
vim.o.autoindent = true
vim.bo.filetype = 'cpp'
vim.bo.shiftwidth = 4
vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

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
-- Start a new field after a comma, before typing its name. Test both an
-- existing closing suffix and an incomplete initializer still being written.
for _, suffix in ipairs { '});', '' } do
  local first = '    auto result = book.match(Aggressor{.id = message.id,'
  local expected = assert(first:find('.id',1,true))-1
  local second = string.rep(' ',expected)..'.quantity = remainingQuantity'
  vim.api.nvim_buf_set_lines(0,0,-1,false,{'void f() {',first,second..suffix,'}'})
  vim.api.nvim_win_set_cursor(0,{3,#second-1})
  vim.api.nvim_feedkeys(vim.keycode('a,<CR>.next = value<Esc>'),'xt',false)
  assert(vim.fn.indent(4)==expected, 'comma + Enter lost initializer alignment: '..vim.inspect(vim.api.nvim_buf_get_lines(0,0,-1,false)))
end
local call = '    consume(first, second);'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'void f() {',call,'}'})
vim.api.nvim_win_set_cursor(0,{2,assert(call:find(');',1,true))-2})
vim.api.nvim_feedkeys(vim.keycode('a,<CR>third<Esc>'),'xt',false)
assert(vim.fn.indent(3)==assert(call:find('first',1,true))-1,'comma + Enter lost function argument alignment')
vim.cmd 'normal! G=='
assert(vim.fn.indent(vim.fn.line('$'))==0,'closing function brace should still dedent')
print('Enter aligns initializer fields, arguments, commas, parameters, templates and ternary operators')
vim.api.nvim_buf_set_lines(0,0,-1,false,{
  '#include <matchingEngine/OrderBookSide.hpp>', '', 'namespace {',
  '    using namespace book;', '', '    void storeOrderSavesOrder() {',
  '        OrderBookSide<Side::BUY> buySide;',
  '        buySide.storeOrder({.id = 1, .quantity = 10, .price = 100});',
  '    }', '}',
})
vim.api.nvim_win_set_cursor(0,{8,0})
vim.api.nvim_feedkeys(vim.keycode('A<CR>nextStatement();<Esc>'),'xt',false)
assert(vim.fn.indent(9)==8, 'Enter after storeOrder should stay inside function: '..vim.inspect(vim.api.nvim_buf_get_lines(0,0,-1,false)))
vim.cmd 'normal! G=='
assert(vim.fn.indent(11)==0,'namespace closing brace should dedent')
vim.cmd '10normal! =='
assert(vim.fn.indent(10)==4,'function closing brace should stay inside namespace')
vim.cmd 'qa!'
