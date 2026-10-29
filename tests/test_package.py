import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('jvim_install', ROOT/'install/macos.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jvim-package-')
        self.home = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def install(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(self.home, **kwargs)

    def test_preview_does_not_write(self):
        self.install()
        self.assertEqual(list(self.home.iterdir()), [])

    def test_install_isolated_and_repeat_install_backs_up_edits(self):
        existing = self.home/'.config/nvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('original user settings')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            self.install(apply=True, runtime=False, registration=False)
            copied = self.home/'.config/jvim/init.lua'
            self.assertTrue(copied.exists())
            copied.write_text('user edits to previous jvim')
            self.install(apply=True, runtime=False, registration=False)
        self.assertEqual(existing.read_text(), 'original user settings')
        backups = list((self.home/'.local/state/jvim/backups').glob('*/.config/jvim/init.lua'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'user edits to previous jvim')
        profile = json.loads((self.home/'Library/Application Support/iTerm2/DynamicProfiles/jvim.json').read_text())['Profiles'][0]
        self.assertEqual(profile['Name'], 'jvim')
        self.assertIn('0x62-0x100000', profile['Keyboard Map'])  # Cmd+B
        self.assertIn('0xf702-0x380000', profile['Keyboard Map'])
        self.assertNotIn('0xf702-0x2c0000', profile['Keyboard Map'])

    def test_install_keeps_terminal_plus_minus_bindings(self):
        zoom = {
            '0x2d-0x100000': {'Action': 10, 'Text': 'host-minus'},
            '0x3d-0x100000': {'Action': 10, 'Text': 'host-plus'},
        }
        prefs = self.home/'Library/Preferences/com.googlecode.iterm2.plist'
        prefs.parent.mkdir(parents=True)
        prefs.write_bytes(plistlib.dumps({
            'Default Bookmark Guid': 'parent',
            'New Bookmarks': [{'Name': 'Default', 'Guid': 'parent', 'Keyboard Map': zoom}],
        }))
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            self.install(apply=True, runtime=False, registration=False)
        path = self.home/'Library/Application Support/iTerm2/DynamicProfiles/jvim.json'
        mappings = json.loads(path.read_text())['Profiles'][0]['Keyboard Map']
        for key, binding in zoom.items():
            self.assertEqual(mappings[key], binding)
        self.assertIn('0x2d-0x180000', mappings)  # Cmd+Option+minus folds
        self.assertIn('0x3d-0x180000', mappings)  # Cmd+Option+equals unfolds
        self.assertIn('0x6e-0x100000', mappings)  # Cmd+N creates a project file

    def test_url_app_registration_builds_metadata_without_opening_ui(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[0] == 'osacompile':
                contents = Path(args[2])/'Contents'
                contents.mkdir(parents=True)
                (contents/'Info.plist').write_bytes(plistlib.dumps({}))
            return subprocess.CompletedProcess(args, 0)
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), patch.object(installer.subprocess, 'run', side_effect=run):
            self.install(apply=True, runtime=False)
        info = plistlib.loads((self.home/'.local/share/jvim/JvimLinks.app/Contents/Info.plist').read_bytes())
        self.assertTrue(info['LSUIElement'])
        self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], ['jvim-definition'])
        self.assertFalse(any(args[0] in ('open', 'git', 'herdr', 'defaults') for args in calls))

    def test_legacy_jvim_profile_is_backed_up_and_actual_parent_is_recorded(self):
        legacy = self.home/'Library/Application Support/iTerm2/DynamicProfiles/neovim-clion.json'
        legacy.parent.mkdir(parents=True)
        legacy.write_text(json.dumps({'Profiles': [{'Name': 'jvim'}, {'Name': 'Unrelated profile'}]}))
        prefs = self.home/'Library/Preferences/com.googlecode.iterm2.plist'
        prefs.parent.mkdir(parents=True)
        prefs.write_bytes(plistlib.dumps({'Default Bookmark Guid': 'parent-guid', 'New Bookmarks': [{'Name': 'My terminal', 'Guid': 'parent-guid'}]}))
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            self.install(apply=True, runtime=False, registration=False)
        self.assertEqual(json.loads(legacy.read_text())['Profiles'], [{'Name': 'Unrelated profile'}])
        self.assertEqual(len(list((self.home/'.local/state/jvim/backups').glob('*/Library/Application Support/iTerm2/DynamicProfiles/neovim-clion.json'))), 1)
        metadata = json.loads((self.home/'.local/share/jvim/runtime.json').read_text())
        self.assertEqual(metadata['parent_profile'], 'My terminal')

    def test_launcher_selects_separate_configuration(self):
        executable = self.home/'nvim'
        executable.write_text('#!/bin/sh\nprintf "%s" "$NVIM_APPNAME"\n')
        executable.chmod(0o755)
        env = dict(os.environ, HOME=str(self.home), JVIM_NVIM=str(executable))
        result = subprocess.run([shutil.which('python3'), str(ROOT/'bin/jvim')], env=env, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, 'jvim')

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_autosave_and_windows_shortcuts_without_plugins(self):
        target = self.home/'sample.txt'
        target.write_text('original\n')
        script = self.home/'check.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('custom.keymaps')
vim.cmd.edit(vim.env.JVIM_TEST_FILE)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'autosaved' })
vim.cmd 'doautocmd TextChangedI'
assert(vim.wait(2000, function() return not vim.bo.modified end, 20), 'idle autosave failed')
assert(vim.fn.readfile(vim.env.JVIM_TEST_FILE)[1] == 'autosaved')
local has = vim.fn.has
vim.fn.has = function(feature) if feature == 'win32' then return 1 end return has(feature) end
require('custom.windows_keys').setup()
vim.fn.has = has
for _, key in ipairs { '<C-b>', '<C-1>', '<C-w>', '<C-S-w>', '<C-M-Left>', '<C-LeftMouse>' } do
  assert(vim.fn.maparg(key, 'i') ~= '', 'missing Windows shortcut: ' .. key)
end
assert(vim.fn.maparg('<C-M-Right>', 'i', false, true).desc == 'Navigate forward')
for _, key in ipairs { '<D-->', '<D-=>', '<D-+>' } do
  assert(vim.fn.maparg(key, 'i') == '', 'editor steals terminal zoom: ' .. key)
end
assert(vim.fn.maparg('<F35>58', 'i', false, true).desc == 'Collapse code fold')
assert(vim.fn.maparg('<D-M-->', 'i', false, true).desc == 'Collapse code fold')
assert(vim.fn.maparg('<D-M-=>', 'i', false, true).desc == 'Expand code fold')
assert(vim.fn.maparg('<F35>67', 'i', false, true).desc == 'Open terminal')
assert(vim.fn.maparg('<C-F11>13', 'x') ~= '', 'missing iTerm Command+C transport in visual mode')
assert(vim.fn.maparg('<C-F11>15', 'i') ~= '', 'missing iTerm Command+V transport in insert mode')
assert(vim.fn.maparg('<C-F11>20', 't') ~= '', 'missing iTerm Command+W transport in terminal mode')
assert(vim.fn.maparg('<F35>68', 'n', false, true).desc == 'New file in selected project folder')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'saved on close' })
vim.fn.maparg('<D-w>', 'i', false, true).callback()
error('last-file close did not exit')
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_FILE=str(target))
        env.pop('JVIM_HOST_SOCKET', None)
        env.pop('JVIM_LINK_TOKEN', None)
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), 'saved on close\n')

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_editor_bridge_reconnects_after_socket_disconnect(self):
        path = str(self.home/'s')
        marker = self.home/'reconnected'
        messages, errors = [], []
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(path)
        listener.listen()
        listener.settimeout(5)
        def serve():
            try:
                for attempt in range(2):
                    client, _ = listener.accept()
                    with client:
                        client.settimeout(5)
                        messages.append(client.recv(4096))
                        if attempt:
                            client.sendall(b'OK\n')
                            marker.touch()
                            client.recv(4096)
            except Exception as error:
                errors.append(error)
            finally:
                listener.close()
        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        script = self.home/'reconnect.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('custom.herdr_host').setup()
assert(vim.wait(3000, function() return vim.fn.filereadable(vim.env.JVIM_TEST_MARKER)==1 end, 20), 'bridge did not reconnect')
assert(vim.v.errmsg=='', vim.v.errmsg)
vim.cmd 'qall'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_HOST_SOCKET=path, JVIM_TEST_MARKER=str(marker))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)], env=env, capture_output=True, text=True, timeout=8)
        worker.join(2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(errors, errors)
        self.assertEqual(messages, [b'focus\n', b'focus\n'])

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_code_link_toggle_is_scoped_and_keeps_diagnostics(self):
        script = self.home/'links.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.diagnostic.config({underline=true})
local provider
vim.api.nvim_set_decoration_provider=function(_, value) provider=value end
vim.lsp.get_clients=function() return {{}} end
local links=require('custom.definition_links')
links.setup()
assert(provider.on_win(nil,nil,0)==false, 'code hyperlinks should default off')
assert(vim.fn.maparg('<C-LeftMouse>','i')~='', 'Ctrl-click mapping missing')
links.toggle()
assert(provider.on_win(nil,nil,0)==true, 'Cmd-click links should be opt-in')
links.toggle()
assert(provider.on_win(nil,nil,0)==false)
assert(vim.diagnostic.config().underline==true, 'diagnostic underlines changed')
vim.cmd 'qall'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_LINK_TOKEN='a'*32)
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)], env=env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_autosave_preserves_import_order_after_undo(self):
        target = self.home/'imports.cpp'
        target.write_text('#include <vector>\n#include <algorithm>\n')
        script = self.home/'imports.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
local autosave = require('custom.autosave')
local policy = require('custom.formatting')
autosave.setup()
vim.cmd.edit(vim.env.JVIM_TEST_FILE)
vim.api.nvim_create_autocmd('BufWritePre', { callback = function(ev)
  if policy.on_save(ev.buf) then
    local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
    table.sort(lines)
    vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, lines)
  end
end })
vim.cmd 'write'
assert(vim.fn.getline(1) == '#include <algorithm>', 'explicit save should format')
vim.cmd 'undo'
assert(vim.fn.getline(1) == '#include <vector>', 'undo should restore original imports')
vim.cmd 'doautocmd TextChanged'
assert(vim.wait(2000, function() return not vim.bo.modified end, 20), 'autosave did not finish')
assert(vim.fn.getline(1) == '#include <vector>', 'autosave re-sorted imports after undo')
assert(vim.fn.readfile(vim.env.JVIM_TEST_FILE)[1] == '#include <vector>')
assert(vim.b.jvim_autosaving == nil, 'autosave flag leaked')
vim.cmd 'qall'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_FILE=str(target))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_clicking_away_from_selection_preserves_text_and_history(self):
        script = self.home/'mouse.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('custom.keymaps')
vim.api.nvim_buf_set_name(0, vim.env.JVIM_TEST_FILE)
local lines = { 'hello world', 'another line', 'last line' }
for _, selection in ipairs { 'v4l\7', 'V\7', '\22j2l\7', 'v4l' } do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd('normal! gg0' .. selection)
  local tick = vim.b.changedtick
  vim.api.nvim_feedkeys(vim.keycode('<LeftMouse>'), 'xt', false)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines),
    'clicking away from selection changed text: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
  assert(vim.b.changedtick == tick, 'clicking created an edit')
end
vim.cmd 'clearjumps'
vim.api.nvim_win_set_cursor(0, { 2, 3 })
vim.cmd 'normal! v2l\7'
local departure = vim.api.nvim_win_get_cursor(0)
vim.api.nvim_feedkeys(vim.keycode('<LeftMouse>'), 'xt', false)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.fn.maparg('<D-M-Left>', 'n', false, true).callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), departure), 'mouse departure missing from back history')
assert(vim.v.errmsg == '', vim.v.errmsg)
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'),
                   JVIM_TEST_FILE=str(self.home/'mouse.txt'))
        env.pop('JVIM_HOST_SOCKET', None)
        env.pop('JVIM_LINK_TOKEN', None)
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_project_startup_preserves_existing_buffers(self):
        script = self.home/'startup.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('custom.keymaps')
-- Headless runs have no desktop UI or project-tree plugin.
vim.api.nvim_list_uis = function() return { {} } end
local opened
package.loaded['neo-tree.command'] = { execute = function(opts) opened = opts end }
local function startup()
  opened = nil
  vim.api.nvim_exec_autocmds('VimEnter', { group = 'clion-editing' })
  assert(vim.wait(1000, function() return opened ~= nil end), 'project tree did not open')
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved work' })
startup()
assert(vim.bo.buflisted, 'modified unnamed buffer was hidden')
assert(opened.action == 'show', 'modified buffer lost editor focus')
vim.api.nvim_buf_set_name(0, vim.env.JVIM_TEST_FILE)
vim.bo.modified = false
startup()
assert(vim.bo.buflisted, 'named file was hidden')
assert(opened.action == 'show', 'named file lost editor focus')
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'),
                   JVIM_TEST_FILE=str(self.home/'opened.txt'))
        env.pop('JVIM_HOST_SOCKET', None)
        env.pop('JVIM_LINK_TOKEN', None)
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_close_empty_editor_exits(self):
        script = self.home/'close.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('custom.keymaps')
vim.fn.maparg('<D-w>', 'i', false, true).callback()
error('empty editor did not exit')
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'))
        env.pop('JVIM_HOST_SOCKET', None)
        env.pop('JVIM_LINK_TOKEN', None)
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
