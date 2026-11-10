"""Compiler checks catch template errors omitted by clangd's header diagnostics."""
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from tests.support import jvim_data

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT/'config/tools/cpp_check.py'


@unittest.skipUnless(shutil.which('clang++') and shutil.which('nvim'), 'C++ compiler and Neovim required')
class CppCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='jvim cpp check ')
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name).resolve()
        self.header = self.project/'record.hpp'
        self.header.write_text('#pragma once\nstruct Foo { int bob; };\ntemplate<class T> int read(T foo) { return foo.bar; }\n')
        (self.project/'main.cpp').write_text('#include "record.hpp"\nint main() { return read(Foo{1}); }\n')
        (self.project/'test.cpp').write_text('#include "record.hpp"\nint test() { return read(Foo{2}); }\n')
        self.arguments = [shutil.which('clang++'), '-std=c++23', '-I.', '-MMD', '-MF', 'dependencies.d',
                          'main.cpp', 'test.cpp', '-o', 'must-not-build']
        self.database = self.project/'compile_commands.json'
        self.database.write_text(json.dumps([{'directory': str(self.project), 'file': 'main.cpp', 'arguments': self.arguments}]))

    def run_checker(self):
        result = subprocess.run([sys.executable, str(RUNNER), str(self.database)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_checks_every_input_without_building_or_writing_dependencies(self):
        result = self.run_checker()
        self.assertEqual(result['checked'], 2)
        self.assertIn("no member named 'bar'", result['output'])
        self.assertIn(str(self.header), result['output'])
        self.assertFalse((self.project/'must-not-build').exists())
        self.assertFalse((self.project/'dependencies.d').exists())
        self.assertEqual(result['errors'], [])

    def test_shell_command_entries_preserve_quoted_paths(self):
        self.database.write_text(json.dumps([{'directory': str(self.project), 'file': 'main.cpp',
                                               'command': shlex.join(self.arguments)}]))
        result = self.run_checker()
        self.assertEqual(result['checked'], 2)
        self.assertIn("no member named 'bar'", result['output'])
        self.assertEqual(result['errors'], [])

    def test_response_files_and_preprocessor_flags_cannot_write_build_outputs(self):
        response = self.project/'flags with spaces.rsp'
        response.write_text(shlex.join(self.arguments[1:] + ['-Wp,-MD,hidden-deps.d', '-serialize-diagnostics', 'diagnostics.dia', '--save-temps=obj']))
        self.database.write_text(json.dumps([{'directory': str(self.project), 'file': 'main.cpp',
                                               'arguments': [self.arguments[0], '@' + str(response)]}]))
        result = self.run_checker()
        self.assertEqual(result['checked'], 2)
        self.assertIn("no member named 'bar'", result['output'])
        for output in ['hidden-deps.d', 'dependencies.d', 'diagnostics.dia', 'must-not-build']:
            self.assertFalse((self.project/output).exists(), output + ' was written by a syntax check')
        self.assertEqual(list(self.project.glob('*.ii')), [])

    @unittest.skipUnless(os.name == 'posix', 'POSIX process groups required')
    def test_cancellation_reaps_a_compiler_that_ignores_sigterm(self):
        marker=self.project/'compiler.pid'
        wrapper=self.project/'stubborn-compiler'
        wrapper.write_text('#!' + sys.executable + '\nimport os,signal,time\nfrom pathlib import Path\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nPath(' + repr(str(marker)) + ').write_text(str(os.getpid()))\ntime.sleep(30)\n')
        wrapper.chmod(0o755)
        self.database.write_text(json.dumps([{'directory':str(self.project),'file':'main.cpp','arguments':[str(wrapper),'main.cpp']}]))
        process=subprocess.Popen([sys.executable,str(RUNNER),str(self.database)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        compiler_pid=None
        try:
            deadline=time.monotonic()+5
            while not marker.exists() and time.monotonic()<deadline:
                time.sleep(.02)
            self.assertTrue(marker.exists(),'test compiler did not start')
            compiler_pid=int(marker.read_text())
            process.terminate()
            process.communicate(timeout=5)
            self.assertEqual(process.returncode,130)
            with self.assertRaises(ProcessLookupError):
                os.kill(compiler_pid,0)
        finally:
            if process.poll() is None:
                process.kill(); process.communicate()
            if compiler_pid is not None:
                try: os.kill(compiler_pid,signal.SIGKILL)
                except ProcessLookupError: pass

    def test_distinct_compilation_configurations_are_all_checked(self):
        source = self.project/'main.cpp'
        source.write_text('#ifdef BROKEN_CONFIGURATION\n#error this configuration is broken\n#endif\nint main() {}\n')
        base = [self.arguments[0], '-std=c++23', str(source)]
        self.database.write_text(json.dumps([
            {'directory': str(self.project), 'file': str(source), 'arguments': base},
            {'directory': str(self.project), 'file': str(source), 'arguments': base + ['-DBROKEN_CONFIGURATION']},
        ]))
        result = self.run_checker()
        self.assertEqual(result['checked'], 2)
        self.assertIn('this configuration is broken', result['output'])

    def test_header_errors_appear_and_clear_without_changing_other_diagnostics(self):
        script = self.project/'check.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.cmd.edit(vim.env.JVIM_TEST_PROJECT..'/record.hpp')
vim.bo.filetype='cpp'
local buf = vim.api.nvim_get_current_buf()
local unrelated = vim.api.nvim_create_namespace('unrelated')
vim.diagnostic.set(unrelated,buf,{{lnum=0,col=0,message='keep me',severity=vim.diagnostic.severity.WARN}})
local check = require 'jvim.cpp_check'
check.setup()
local completed = false
assert(check.run(buf,{on_complete=function() completed=true end}))
assert(vim.wait(10000,function() return completed end,25),'compiler check did not finish')
local function errors()
  return vim.tbl_filter(function(d) return d.source == 'C++ compiler' end,vim.diagnostic.get(buf))
end
assert(#errors() > 0,'template member error was not published on its header')
assert(errors()[1].lnum==2,'error was put on the wrong header line')
assert(#vim.diagnostic.get(buf,{namespace=unrelated})==1,'compiler check replaced unrelated diagnostics')
local database=vim.env.JVIM_TEST_PROJECT..'/compile_commands.json'
local original=vim.fn.readfile(database)
local broken=vim.json.decode(table.concat(original,'\\n'))
broken[1].arguments[1]='/missing/jvim/compiler'
vim.fn.writefile({vim.json.encode(broken)},database)
completed=false
check.run(buf,{on_complete=function() completed=true end})
assert(vim.wait(10000,function() return completed end,25))
assert(#errors()>0,'an incomplete check cleared existing compiler errors')
local driver_failure=vim.json.decode(table.concat(original,'\\n'))
driver_failure[1].arguments={driver_failure[1].arguments[1],'-invalid-option-for-jvim','main.cpp'}
local test_path=vim.env.JVIM_TEST_PROJECT..'/test.cpp'
local original_test=vim.fn.readfile(test_path)
vim.fn.writefile({'#warning checker warning','int test() {}'},test_path)
table.insert(driver_failure,{directory=vim.env.JVIM_TEST_PROJECT,file='test.cpp',arguments={vim.json.decode(table.concat(original,'\\n'))[1].arguments[1],'test.cpp'}})
vim.fn.writefile({vim.json.encode(driver_failure)},database)
completed=false
check.run(buf,{on_complete=function() completed=true end})
assert(vim.wait(10000,function() return completed end,25))
assert(#errors()>0,'another unit warning masked a driver failure and cleared existing errors')
vim.fn.writefile(original_test,test_path)
vim.fn.writefile(original,database)
vim.api.nvim_buf_set_lines(buf,2,3,false,{'template<class T> int read(T foo) { return foo.bob; }'})
vim.b.jvim_autosaving=true
vim.cmd.write()
vim.b.jvim_autosaving=false
assert(vim.wait(10000,function() return #errors()==0 end,25),'corrected compiler error did not clear after save')
assert(#vim.diagnostic.get(buf,{namespace=unrelated})==1,'clearing compiler errors replaced unrelated diagnostics')
vim.cmd 'qa!'
''')
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(self.project))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=25)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_include_is_reported_as_an_error(self):
        (self.project/'main.cpp').write_text('#include "missing-header.hpp"\n')
        script=self.project/'fatal.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.cmd.edit(vim.env.JVIM_TEST_PROJECT..'/main.cpp')
vim.bo.filetype='cpp'
local check=require 'jvim.cpp_check'
check.setup()
local completed=false
check.run(0,{on_complete=function() completed=true end})
assert(vim.wait(10000,function() return completed end,25))
local found=false
for _,d in ipairs(vim.diagnostic.get(0)) do
  if d.source=='C++ compiler' and d.severity==vim.diagnostic.severity.ERROR and d.message:find('missing-header.hpp',1,true) then found=true end
end
assert(found,'fatal missing-header error was discarded')
vim.cmd 'qa!'
''')
        result=subprocess.run(['nvim','--headless','-u','NONE','-i','NONE','-l',str(script)],
                              env=dict(os.environ,JVIM_TEST_CONFIG=str(ROOT/'config'),JVIM_TEST_PROJECT=str(self.project)),
                              capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_editing_a_newly_opened_header_discards_an_active_check(self):
        wrapper=self.project/'slow-compiler'
        wrapper.write_text('#!' + sys.executable + '\nimport os,sys,time\ntime.sleep(0.5)\nos.execv(' + repr(self.arguments[0]) + ',[' + repr(self.arguments[0]) + ']+sys.argv[1:])\n')
        wrapper.chmod(0o755)
        arguments=[str(wrapper)] + self.arguments[1:]
        self.database.write_text(json.dumps([{'directory':str(self.project),'file':'main.cpp','arguments':arguments}]))
        script=self.project/'stale.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
local root=vim.env.JVIM_TEST_PROJECT
vim.cmd.edit(root..'/main.cpp')
vim.bo.filetype='cpp'
local check=require 'jvim.cpp_check'
check.setup()
local completed=false
check.run(0,{on_complete=function() completed=true end})
vim.cmd.edit(root..'/record.hpp')
vim.bo.filetype='cpp'
vim.api.nvim_buf_set_lines(0,2,3,false,{'template<class T> int read(T foo) { return foo.bob; }'})
vim.wait(1800)
assert(not completed,'a check completed after a newly opened header changed')
for _,d in ipairs(vim.diagnostic.get(0)) do assert(d.source~='C++ compiler','stale compiler errors were published') end
vim.cmd 'qa!'
''')
        result=subprocess.run(['nvim','--headless','-u','NONE','-i','NONE','-l',str(script)],
                              env=dict(os.environ,JVIM_TEST_CONFIG=str(ROOT/'config'),JVIM_TEST_PROJECT=str(self.project)),
                              capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)

    @unittest.skipUnless(shutil.which('clangd'), 'clangd required for semantic rename checks')
    def test_semantic_member_rename_checks_the_compiler_result(self):
        self.header.write_text('#pragma once\nstruct Foo { int bar; };\ntemplate<class T> int read(T foo) { return foo.bar; }\n')
        (self.project/'main.cpp').write_text('#include "record.hpp"\nint main() { Foo foo{1}; return foo.bar + read(foo); }\n')
        script = self.project/'rename.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.opt.rtp:append(vim.env.JVIM_TEST_SITE)
local root = vim.env.JVIM_TEST_PROJECT
vim.cmd.edit(root..'/main.cpp')
vim.bo.filetype='cpp'
local id=vim.lsp.start({name='clangd',cmd={'clangd','--background-index'},root_dir=root})
local client=assert(vim.lsp.get_client_by_id(id))
assert(vim.wait(10000,function() return client.initialized end,25),'clangd did not initialize')
local source=vim.api.nvim_get_current_buf()
assert(vim.wait(10000,function()
  local response=client:request_sync('textDocument/references',{textDocument={uri=vim.uri_from_bufnr(source)},position={line=1,character=36},context={includeDeclaration=true}},1000,source)
  return response and response.result and #response.result>=2
end,50),'clangd did not index the ordinary field references')
vim.cmd.edit(root..'/record.hpp')
vim.bo.filetype='cpp'
local header=vim.api.nvim_get_current_buf()
vim.lsp.buf_attach_client(header,id)
local rename=require 'jvim.rename'
rename.setup()
vim.ui.input=function(_,callback) callback('bob') end
vim.api.nvim_win_set_cursor(0,{2,17})
rename.symbol()
assert(vim.wait(15000,function()
  for _,d in ipairs(vim.diagnostic.get(header)) do
    if d.source=='C++ compiler' and d.message:find("no member named 'bar'",1,true) then return true end
  end
end,25),'incomplete template rename was not reported by the compiler')
assert(vim.api.nvim_buf_get_lines(header,1,2,false)[1]=='struct Foo { int bob; };','member declaration was not renamed')
assert(vim.api.nvim_buf_get_lines(source,1,2,false)[1]:find('foo.bob',1,true),'ordinary member reference was not renamed')
vim.cmd 'qa!'
''')
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(self.project),
                   JVIM_TEST_SITE=str(jvim_data()/'site'))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=35)
        self.assertEqual(result.returncode, 0, result.stderr)
