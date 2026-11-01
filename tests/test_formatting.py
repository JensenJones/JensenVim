"""Check C++ include organisation through the real Conform/clang-format pipeline."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFORM = Path.home()/'.local/share/jvim/lazy/conform.nvim'
SITE = Path.home()/'.local/share/jvim/site'


@unittest.skipUnless(shutil.which('nvim') and shutil.which('clang-format') and CONFORM.is_dir(),
                     'Neovim, Conform and clang-format required')
class FormattingTests(unittest.TestCase):
    def test_includes_are_grouped_sorted_and_separated_from_code(self):
        with tempfile.TemporaryDirectory(prefix='jvim-formatting-') as temporary:
            project = Path(temporary)
            (project/'Makefile').touch()
            (project/'matchingEngine').mkdir()
            (project/'matchingEngine/OrderBook.hpp').touch()
            (project/'local.hpp').touch()
            # Include preferences override these settings; other style survives.
            (project/'.clang-format').write_text('BasedOnStyle: LLVM\nIndentWidth: 7\nSortIncludes: Never\nIncludeBlocks: Preserve\n')
            source = project/'main.cpp'
            source.write_text('#include "zebra.hpp"\n#include <vector>\n#include <matchingEngine/OrderBook.hpp>\n#include <algorithm>\n#include "local.hpp"\n#include <fmt/core.h>\nusing namespace std;\nclass Example {\nvoid run();\n};\n')
            script = project/'test.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_CONFORM)
vim.opt.rtp:append(vim.env.JVIM_TEST_SITE)
vim.cmd.edit(vim.env.JVIM_TEST_SOURCE)
vim.bo.filetype = 'cpp'
local formatting = require 'jvim.formatting'
require('conform').setup {
  formatters = formatting.formatters,
  formatters_by_ft = formatting.formatters_by_ft,
  format_on_save = formatting.on_save,
}
vim.cmd.write()
local expected = {
  '#include <algorithm>', '#include <fmt/core.h>', '#include <vector>', '',
  '#include "local.hpp"', '#include <matchingEngine/OrderBook.hpp>', '#include "zebra.hpp"', '',
  'using namespace std;', 'class Example {', '       void run();', '};',
}
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0,0,-1,false), expected), vim.inspect(vim.api.nvim_buf_get_lines(0,0,-1,false)))
require('conform').format { async = false }
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0,0,-1,false), expected), 'formatting is not idempotent')
for _, declaration in ipairs { 'class Example {};', 'namespace example {}', 'int value;', 'using Size = int;' } do
  vim.api.nvim_buf_set_lines(0,0,-1,false,{'#include <vector>', declaration})
  require('conform').format { async = false }
  assert(vim.api.nvim_buf_get_lines(0,1,2,false)[1] == '', 'missing blank line before ' .. declaration)
end
vim.api.nvim_buf_set_lines(0,0,-1,false,{'#include <vector>', '#include <algorithm>', 'int value;'})
vim.b.jvim_autosaving = true
vim.cmd.write()
assert(vim.api.nvim_get_current_line() == '#include <vector>', 'autosave unexpectedly sorted includes while typing')
vim.b.jvim_autosaving = false
local raw = {'auto text = R"(', '#include <vector>', 'literal text', ')";'}
vim.api.nvim_buf_set_lines(0,0,-1,false,raw)
require('conform').format { async = false }
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0,0,-1,false), raw), 'formatting changed include-like text inside a raw string')
vim.bo.modified = false
vim.cmd.quit()
''')
            env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_CONFORM=str(CONFORM),
                       JVIM_TEST_SOURCE=str(source), JVIM_TEST_SITE=str(SITE))
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
