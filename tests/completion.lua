vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_BLINK)
vim.o.virtualedit = 'onemore'
local completion = require 'custom.completion'
local original_feedkeys = vim.api.nvim_feedkeys
vim.api.nvim_feedkeys = function() error('completion must not inject mode-changing keystrokes') end
vim.api.nvim_buf_set_lines(0,0,-1,false,{'    call: '})
vim.api.nvim_win_set_cursor(0,{1,10})
completion.expand('func(${1:argument}, ${2|first,second|})$0')
assert(vim.api.nvim_get_current_line() == '    call: func(argument, first)', vim.api.nvim_get_current_line())
assert(not completion.snippets().active({direction=1}), 'stale snippet navigation enabled')
local pos=vim.api.nvim_win_get_cursor(0)
completion.snippets().jump(1)
assert(vim.deep_equal(pos,vim.api.nvim_win_get_cursor(0)), 'snippet jump moved cursor')
vim.api.nvim_buf_set_lines(0,0,-1,false,{'    '})
vim.api.nvim_win_set_cursor(0,{1,4})
completion.expand('if (${1:condition}) {\n\t${2:body}\n}$0')
assert(vim.api.nvim_buf_get_lines(0,0,-1,false)[2]:find('body',1,true))
assert(vim.fn.mode() == 'n', 'expansion changed mode')
vim.api.nvim_feedkeys = original_feedkeys
print('plain snippet expansion, defaults, choices, multiline, mode and no-jump checks passed')
vim.cmd 'qa!'
