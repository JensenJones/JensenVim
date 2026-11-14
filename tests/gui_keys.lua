-- Lists WezTerm key-table entries whose action a graphical frontend cannot reach with the key itself.
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require 'jvim.keymaps'
package.loaded.wezterm = {
  action = setmetatable({}, { __index = function() return function() end end }),
  target_triple = 'aarch64-apple-darwin',
}
local names = { Backspace = 'BS', Delete = 'Del', DownArrow = 'Down', UpArrow = 'Up', LeftArrow = 'Left', RightArrow = 'Right',
  Enter = 'CR', ['\\'] = 'Bslash', ['|'] = 'Bar' }
local modifiers = { CMD = 'D', CTRL = 'C', ALT = 'M', SHIFT = 'S' }
local unreachable = {}
for _, entry in ipairs(dofile(vim.env.JVIM_TEST_MODULE).keys) do
  local code = tonumber(entry[3]:match '^\27%[23;5~(%d+)$')
  if code then
    local transport = (code <= 37 and code ~= 35) and ('<F' .. code .. '>') or ('<F35>' .. code)
    local parts = {}
    for name in entry[2]:gmatch '[^|]+' do parts[#parts + 1] = modifiers[name] end
    table.sort(parts, function(a, b) return ('DCMS'):find(a) < ('DCMS'):find(b) end)
    parts[#parts + 1] = names[entry[1]] or entry[1]
    local direct = '<' .. table.concat(parts, '-') .. '>'
    local wanted = vim.fn.maparg(transport, 'i', false, true).desc
    if vim.fn.maparg(direct, 'i', false, true).desc ~= wanted then unreachable[#unreachable + 1] = direct .. ' ' .. tostring(wanted) end
  end
end
table.sort(unreachable)
io.write(vim.json.encode(unreachable))
vim.cmd 'qall!'
