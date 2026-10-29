"""Check that jvim recognizes C++ namespace declarations for its rename fallback."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARSER = Path.home()/'.local/share/jvim/site/parser/cpp.so'


@unittest.skipUnless(shutil.which('nvim') and PARSER.is_file(), 'Neovim and the C++ Tree-sitter parser are required')
class NamespaceRenameTests(unittest.TestCase):
    def test_detects_namespace_declaration_but_not_class_names(self):
        with tempfile.TemporaryDirectory(prefix='jvim-namespace-') as directory:
            script = Path(directory)/'check.lua'
            script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.treesitter.language.add('cpp', { path = vim.env.JVIM_TEST_CPP_PARSER })
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'namespace target_ns { int value(); }',
  'class SomeType {};',
})
vim.bo.filetype = 'cpp'
local rename = require('custom.rename')
vim.api.nvim_win_set_cursor(0, { 1, 10 })
assert(rename.namespace_declaration_at_cursor() == 'target_ns', 'namespace name was not recognized')
vim.api.nvim_win_set_cursor(0, { 2, 6 })
assert(rename.namespace_declaration_at_cursor() == nil, 'class name was misidentified as a namespace')
vim.cmd 'qa!'
''')
            env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_CPP_PARSER=str(PARSER))
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('clangd'), 'clangd is required for namespace reference checks')
    def test_namespace_reference_uses_project_rename_fallback(self):
        with tempfile.TemporaryDirectory(prefix='jvim-namespace-lsp-') as directory:
            root = Path(directory)
            (root/'compile_flags.txt').write_text('-std=c++20\n')
            (root/'api.hpp').write_text('namespace target_ns { int value(); }\n')
            source = root/'main.cpp'
            source.write_text('#include "api.hpp"\nint use() { return target_ns::value(); }\n')
            script = root/'check.lua'
            script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.treesitter.language.add('cpp', { path = vim.env.JVIM_TEST_CPP_PARSER })
local root = vim.env.JVIM_TEST_PROJECT
vim.cmd.edit(vim.fn.fnameescape(root .. '/api.hpp'))
vim.bo.filetype = 'cpp'
local header = vim.api.nvim_get_current_buf()
local id = vim.lsp.start({ name = 'clangd', cmd = { 'clangd' }, root_dir = root }, { bufnr = header })
local client = assert(vim.lsp.get_client_by_id(id))
vim.cmd.edit(vim.fn.fnameescape(root .. '/main.cpp'))
vim.bo.filetype = 'cpp'
local source = vim.api.nvim_get_current_buf()
vim.lsp.buf_attach_client(source, id)
assert(vim.wait(10000, function() return client.initialized end, 50), 'clangd did not initialize')
vim.api.nvim_win_set_cursor(0, { 2, 20 })
local project_replace = require('custom.project_replace')
local original = project_replace.rename_namespace
local renamed
project_replace.rename_namespace = function(name) renamed = name end
require('custom.rename').symbol()
assert(vim.wait(5000, function() return renamed ~= nil end, 25), 'namespace reference did not use the project rename fallback')
assert(renamed == 'target_ns', 'the wrong namespace was selected: ' .. tostring(renamed))
project_replace.rename_namespace = original
vim.cmd 'qa!'
''')
            env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_CPP_PARSER=str(PARSER), JVIM_TEST_PROJECT=str(root))
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_namespace_search_is_word_bounded_and_limits_candidates_to_cpp(self):
        with tempfile.TemporaryDirectory(prefix='jvim-namespace-search-') as directory:
            root = Path(directory)
            (root/'one.hpp').write_text('namespace old_name {}\n')
            (root/'two.cpp').write_text('using namespace old_name;\nold_name::run();\n')
            (root/'similar.cpp').write_text('old_name_extra::run();\n')
            (root/'notes.txt').write_text('old_name appears here too\n')
            script = root/'check.lua'
            script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.ui.input = function(_, callback) callback('new_name') end
local selected
vim.ui.select = function(items, _, callback)
  selected = items
  callback('Review matching files')
end
require('custom.project_replace').rename_namespace('old_name', vim.env.JVIM_TEST_PROJECT)
assert(vim.wait(5000, function() return selected ~= nil end, 25), 'namespace matches were not presented for review')
local paths = vim.tbl_map(function(item)
  local name = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
  return vim.fn.fnamemodify(name, ':t')
end, vim.fn.getqflist())
table.sort(paths)
assert(vim.deep_equal(paths, { 'one.hpp', 'two.cpp' }), 'namespace candidates were not word-bounded C++ files: ' .. vim.inspect(paths))
vim.cmd 'qa!'
''')
            env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(root))
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
