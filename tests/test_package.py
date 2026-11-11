import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('jvim_install', ROOT/'install/macos.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


@unittest.skipIf(os.name == 'nt', 'macOS iTerm/Herdr package; Windows packaging is covered by test_windows_package')
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

    def test_reinstall_preserves_tool_caches_and_external_settings(self):
        sentinels = [self.home/path for path in (
            '.local/share/jvim/lazy/example/plugin.lua',
            '.local/share/jvim/mason/bin/clangd',
            '.local/share/jvim/site/parser/cpp.so',
            '.config/jvim-user/init.lua',
        )]
        for path in sentinels:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('keep me')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            self.install(apply=True, runtime=False, registration=False)
        for path in sentinels:
            self.assertEqual(path.read_text() if path.exists() else None, 'keep me', str(path))

    def test_invalid_terminal_preferences_preserve_active_installation(self):
        existing = self.home/'.config/jvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('active editor')
        prefs = self.home/'Library/Preferences/com.googlecode.iterm2.plist'
        prefs.parent.mkdir(parents=True)
        prefs.write_bytes(b'not a plist')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            with self.assertRaises((RuntimeError, plistlib.InvalidFileException)):
                self.install(apply=True, runtime=False, registration=False)
        self.assertEqual(existing.read_text() if existing.exists() else None, 'active editor')

    def test_failed_runtime_preparation_preserves_active_installation(self):
        existing = self.home/'.config/jvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('active editor')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), \
                patch.object(installer.venv.EnvBuilder, 'create'), \
                patch.object(installer.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'pip')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.install(apply=True, registration=False)
        self.assertEqual(existing.read_text() if existing.exists() else None, 'active editor')

    def test_failed_app_preparation_preserves_active_installation(self):
        existing = self.home/'.config/jvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('active editor')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), \
                patch.object(installer.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'osacompile')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.install(apply=True, runtime=False)
        self.assertEqual(existing.read_text(), 'active editor')

    def test_published_python_runtime_keeps_its_original_location(self):
        builder = installer.venv.EnvBuilder
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), \
                patch.object(installer.venv, 'EnvBuilder', side_effect=lambda **kwargs: builder(with_pip=False)), \
                patch.object(installer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            self.install(apply=True, registration=False)
        runtime = self.home/'.local/share/jvim/runtime'
        self.assertTrue(runtime.is_symlink())
        self.assertEqual(runtime.resolve().parent, (self.home/'.local/share/jvim/runtimes').resolve())
        result = subprocess.run([str(runtime/'bin/python3'), '-c', 'import sys; print(sys.prefix)'],
                                capture_output=True, text=True, check=True)
        self.assertEqual(Path(result.stdout.strip()).resolve(), runtime.resolve())

    def test_xdg_override_is_rejected_before_writing(self):
        with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.home/'elsewhere')}):
            with self.assertRaisesRegex(RuntimeError, 'XDG_CONFIG_HOME'):
                self.install(apply=True, runtime=False, registration=False)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_failed_publish_restores_all_replaced_files(self):
        paths = [self.home/'.config/jvim/init.lua', self.home/'.local/bin/jvim']
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('old '+path.name)
        real_move = installer.shutil.move
        failed = False
        def move(source, destination, *args, **kwargs):
            nonlocal failed
            if Path(destination).resolve() == (self.home/'.local/bin/jvim').resolve() and not failed:
                failed = True
                raise OSError('simulated publish failure')
            return real_move(source, destination, *args, **kwargs)
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), \
                patch.object(installer.shutil, 'move', side_effect=move):
            with self.assertRaisesRegex(OSError, 'simulated publish failure'):
                self.install(apply=True, runtime=False, registration=False)
        for path in paths:
            self.assertEqual(path.read_text() if path.exists() else None, 'old '+path.name)

    def test_incomplete_recovery_reports_retained_backups(self):
        existing = self.home/'.config/jvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('old settings')
        real_move = installer.shutil.move
        def move(source, destination, *args, **kwargs):
            if Path(destination).resolve() == (self.home/'.local/bin/jvim').resolve():
                raise OSError('publish unavailable')
            if 'backups' in Path(source).parts:
                raise OSError('restore unavailable')
            return real_move(source, destination, *args, **kwargs)
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'), \
                patch.object(installer.shutil, 'move', side_effect=move):
            with self.assertRaises(Exception) as failure:
                self.install(apply=True, runtime=False, registration=False)
        self.assertIsInstance(failure.exception, RuntimeError)
        self.assertRegex(str(failure.exception), 'recovery incomplete.*backups')
        backups = list((self.home/'.local/state/jvim/backups').glob('*/.config/jvim/init.lua'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), 'old settings')

    def test_install_isolated_and_repeat_install_backs_up_edits(self):
        existing = self.home/'.config/nvim/init.lua'
        existing.parent.mkdir(parents=True)
        existing.write_text('original user settings')
        with patch.object(installer.shutil, 'which', return_value='/test/nvim'):
            self.install(apply=True, runtime=False, registration=False)
            linked = self.home/'.config/jvim'
            self.assertTrue(linked.is_symlink())
            self.assertEqual(linked.resolve(), (ROOT/'config').resolve())
            starter = self.home/'.wezterm.lua'
            self.assertEqual(starter.read_text(), (ROOT/'integrations/wezterm/starter.lua').read_text())
            starter.write_text('my own wezterm settings')
            self.install(apply=True, runtime=False, registration=False)
            self.assertEqual(linked.resolve(), (ROOT/'config').resolve())
        self.assertEqual(starter.read_text(), 'my own wezterm settings', 'reinstalling replaced the WezTerm config')
        self.assertEqual((self.home/'.local/share/jvim/wezterm-config.lua').resolve(), (ROOT/'integrations/wezterm/wezterm.lua').resolve())
        self.assertEqual(existing.read_text(), 'original user settings')
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
        self.assertIn('0xd-0x20000', mappings)  # Shift+Enter inserts a line below
        self.assertNotIn('0x31-0x100000', mappings)  # Tree toggle uses a direct Neovim key
        for key in ('0xf702-0x100000', '0xf702-0x20000', '0xf703-0x20000',
                    '0xf700-0x20000', '0xf701-0x20000', '0xf702-0x2a0000', '0xf703-0x2a0000'):
            self.assertIn(key, mappings, f'modified arrow transport missing: {key}')

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

    def test_installed_launcher_uses_exact_python_with_spaces_and_quotes(self):
        executable = self.home/'nvim'
        executable.write_text('#!/bin/sh\nprintf "%s:%s" "$NVIM_APPNAME" "$1"\nexit 17\n')
        executable.chmod(0o755)
        marker = self.home/'python-used'
        special_interpreter = self.home/"Python With Spaces and 'quotes'"/'python3'
        special_interpreter.parent.mkdir()
        special_interpreter.write_text('#!/bin/sh\n: > '+shlex.quote(str(marker))+'\nexec '
                                       +shlex.quote(sys.executable)+' "$@"\n')
        special_interpreter.chmod(0o755)
        for interpreter in (Path(sys.executable), special_interpreter):
            with self.subTest(interpreter=str(interpreter)):
                with patch.object(installer.sys, 'executable', str(interpreter)), \
                        patch.object(installer.shutil, 'which', return_value=str(executable)):
                    self.install(apply=True, runtime=False, registration=False)
                env = dict(os.environ, HOME=str(self.home), JVIM_NVIM=str(executable), PATH='')
                try:
                    result = subprocess.run([str(self.home/'.local/bin/jvim'), 'file with spaces.cpp'],
                                            env=env, capture_output=True, text=True)
                except OSError as error:
                    self.fail(f'Installed launcher could not execute: {error}')
                self.assertEqual(result.returncode, 17, result.stderr)
                self.assertEqual(result.stdout, 'jvim:file with spaces.cpp')
                if interpreter == special_interpreter:
                    self.assertTrue(marker.is_file(), 'installed interpreter was bypassed')

    def test_launcher_resolves_path_override_and_forwards_arguments_and_status(self):
        directory = self.home/'tools with spaces'
        directory.mkdir()
        executable = directory/'company-nvim'
        executable.write_text('#!/bin/sh\nprintf "%s:%s" "$NVIM_APPNAME" "$1"\nexit 17\n')
        executable.chmod(0o755)
        for override in ('company-nvim', str(executable)):
            env = dict(os.environ, HOME=str(self.home), JVIM_NVIM=override,
                       PATH=str(directory)+os.pathsep+os.environ.get('PATH', ''))
            result = subprocess.run([sys.executable, str(ROOT/'bin/jvim'), 'file with spaces.cpp'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 17, result.stderr)
            self.assertEqual(result.stdout, 'jvim:file with spaces.cpp')

    def test_launcher_reports_bad_metadata_and_missing_override_without_traceback(self):
        metadata = self.home/'.local/share/jvim/runtime.json'
        metadata.parent.mkdir(parents=True)
        metadata.write_text('{invalid')
        for override in ('', 'missing-company-nvim'):
            env = dict(os.environ, HOME=str(self.home), JVIM_NVIM=override)
            result = subprocess.run([sys.executable, str(ROOT/'bin/jvim')], env=env,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('jvim:', result.stderr)
            self.assertNotIn('Traceback', result.stderr)

    def test_launcher_reports_missing_override_with_valid_metadata(self):
        env = dict(os.environ, HOME=str(self.home), JVIM_NVIM='missing-company-nvim')
        result = subprocess.run([sys.executable, str(ROOT/'bin/jvim')], env=env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing-company-nvim', result.stderr)
        self.assertIn('JVIM_NVIM', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_launcher_rejects_unsupported_xdg_paths(self):
        env = dict(os.environ, HOME=str(self.home), XDG_DATA_HOME=str(self.home/'elsewhere'),
                   JVIM_NVIM='missing-company-nvim')
        result = subprocess.run([sys.executable, str(ROOT/'bin/jvim')], env=env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('XDG_DATA_HOME', result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_autosave_and_windows_shortcuts_without_plugins(self):
        target = self.home/'sample.txt'
        target.write_text('original\n')
        script = self.home/'check.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('jvim.keymaps')
vim.cmd.edit(vim.env.JVIM_TEST_FILE)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'autosaved' })
vim.cmd 'doautocmd TextChangedI'
assert(vim.wait(2000, function() return not vim.bo.modified end, 20), 'idle autosave failed')
assert(vim.fn.readfile(vim.env.JVIM_TEST_FILE)[1] == 'autosaved')
local has = vim.fn.has
vim.fn.has = function(feature) if feature == 'win32' then return 1 end return has(feature) end
require('jvim.windows_keys').setup()
vim.fn.has = has
for _, key in ipairs { '<C-b>', '<F4>', '<C-w>', '<C-S-w>', '<C-M-Left>', '<C-LeftMouse>' } do
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
require('jvim.herdr_host').setup()
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
local links=require('jvim.definition_links')
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
local autosave = require('jvim.autosave')
local policy = require('jvim.formatting')
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
require('jvim.keymaps')
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
    def test_select_mode_opening_delimiters_wrap_selected_text(self):
        script = self.home/'surround.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
vim.o.selection = 'exclusive'
require('jvim.clion_actions').setup(function() end, function() end)
local cases = { { '(', ')' }, { '[', ']' }, { '{', '}' }, { '"', '"' }, { "'", "'" }, { '`', '`' } }
for _, pair in ipairs(cases) do
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before word after' })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  vim.cmd.normal { args = { 'v4l\7' }, bang = true }
  assert(vim.fn.mode():match('^[sS]'), 'test did not enter Select mode: ' .. vim.fn.mode())
  vim.api.nvim_feedkeys(pair[1], 'xt', false)
  assert(vim.api.nvim_get_current_line() == 'before ' .. pair[1] .. 'word' .. pair[2] .. ' after',
    'opener ' .. pair[1] .. ' did not wrap selection: ' .. vim.api.nvim_get_current_line())
end
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for selection checks')
    def test_typing_over_visual_selection_replaces_instead_of_running_commands(self):
        script = self.home/'visual_overwrite.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
vim.o.selection = 'exclusive'
require('jvim.clion_actions').setup(function() end, function() end)
for char in ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,;!?'):gmatch('.') do
  vim.cmd 'normal! \27'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before word after' })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  vim.cmd 'normal! v4l'
  assert(vim.fn.mode() == 'v', 'fixture must exercise Visual mode')
  vim.api.nvim_feedkeys(char, 'xt', false)
  assert(vim.api.nvim_get_current_line() == 'before ' .. char .. ' after',
    'typing ' .. char .. ' executed a command: ' .. vim.api.nvim_get_current_line())
end
for _, mode in ipairs { 'v', 's' } do
  for _, key in ipairs { '<BS>', '<Del>' } do
    vim.cmd 'normal! \27'
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'before word after'})
    vim.api.nvim_win_set_cursor(0,{1,7})
    vim.cmd 'normal! v4l'
    if mode == 's' then vim.cmd 'normal! \7' end
    vim.api.nvim_feedkeys(vim.keycode(key) .. 'Z', 'xt', false)
    assert(vim.api.nvim_get_current_line() == 'before Z after', mode .. ' ' .. key .. ' did not delete selection and resume typing')
  end
end
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_shift_enter_opens_line_below_without_changing_current_line(self):
        script = self.home/'shift_enter.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('jvim.keymaps')
local key = vim.keycode('<C-F11>69')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'keep this text', 'following line' })
vim.api.nvim_win_set_cursor(0, { 1, 4 })
vim.api.nvim_feedkeys(key, 'xt', false)
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'keep this text', 'normal mode changed current line')
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[2] == '', 'normal mode did not open a blank line below')
vim.cmd.stopinsert()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'preserve me', 'after' })
vim.api.nvim_win_set_cursor(0, { 1, 3 })
vim.cmd.startinsert()
vim.api.nvim_feedkeys(key, 'xt', false)
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1] == 'preserve me', 'insert mode changed current line')
assert(lines[2] == '', 'insert mode did not create a blank line below')
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_option_right_advances_one_identifier_at_a_time(self):
        script = self.home/'word_motion.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('jvim.keymaps')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'leftIt->timestamp, call()' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode('<C-Right>'), 'xt', false)
assert(vim.api.nvim_win_get_cursor(0)[2] == 5, 'first Option+Right should end at leftIt')
vim.api.nvim_feedkeys(vim.keycode('<C-Right>'), 'xt', false)
assert(vim.api.nvim_win_get_cursor(0)[2] == 16, 'second Option+Right should skip -> and end at timestamp')
vim.api.nvim_feedkeys(vim.keycode('<C-Right>'), 'xt', false)
assert(vim.api.nvim_win_get_cursor(0)[2] == 22, 'third Option+Right should skip comma and space and end at call')
vim.api.nvim_feedkeys(vim.keycode('<C-Right>'), 'xt', false)
assert(vim.api.nvim_win_get_cursor(0)[2] == 24, 'Option+Right got stuck before trailing parentheses')
local line = 'auto [price, priveLevelIt] = *book.begin();'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
local paren = assert(line:find('()', 1, true)) - 1
vim.api.nvim_win_set_cursor(0, { 1, paren })
local move = vim.fn.maparg('<C-Right>', 'i', false, true).callback()
assert(move == '<C-o>3l', 'Insert-mode Option+Right should advance over ();, got ' .. move)
line = 'listener->onFullyFilled(FullyFilledMessage message);'
vim.api.nvim_buf_set_lines(0,0,-1,false,{line})
local message = assert(line:find(' message',1,true))
vim.api.nvim_win_set_cursor(0,{1,#line-2})
vim.cmd 'normal! v'
vim.api.nvim_win_set_cursor(0,{1,message})
vim.cmd 'normal! \7'
vim.api.nvim_feedkeys(vim.keycode('<M-S-Left>'), 'xt', false)
local selected = vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v',exclusive=true})
assert(table.concat(selected,'\n') == 'FullyFilledMessage message', 'backward word selection jumped across call: ' .. vim.inspect(selected))
vim.cmd 'qall!'
''')
        env = dict(os.environ, HOME=str(self.home), JVIM_TEST_CONFIG=str(ROOT/'config'))
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('nvim'), 'Neovim needed for core behavior checks')
    def test_project_startup_preserves_existing_buffers(self):
        script = self.home/'startup.lua'
        script.write_text(r'''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
vim.o.swapfile = false
require('jvim.keymaps')
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
require('jvim.keymaps')
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
