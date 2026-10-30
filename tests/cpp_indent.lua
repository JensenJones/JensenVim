vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_SITE)
vim.o.autoindent=true
vim.bo.filetype='cpp'
vim.bo.indentexpr="v:lua.require'custom.cpp_indent'.indent()"
local line='                auto filledResult = otherBook.matchBestResting(Aggressor{.id = message.id, .quantity = remainingQuantity});'
vim.api.nvim_buf_set_lines(0,0,-1,false,{'void f() {',line,'}'})
local split=assert(line:find('.quantity',1,true))-1
local expected=assert(line:find('.id',1,true))-1
vim.api.nvim_win_set_cursor(0,{2,split})
vim.api.nvim_feedkeys(vim.keycode('i<CR><Esc>'),'xt',false)
local lines=vim.api.nvim_buf_get_lines(0,0,-1,false)
assert(vim.fn.indent(3)==expected,vim.inspect(lines)..' expected '..expected..' got '..vim.fn.indent(3))
assert(lines[3]:match('^%s*(%.quantity)'),vim.inspect(lines))
print('Enter aligns .quantity with .id at column '..expected)
vim.cmd 'qa!'
