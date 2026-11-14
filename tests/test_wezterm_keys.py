"""Check that every key WezTerm and iTerm send to jvim reaches the intended action."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
KEY = re.compile(r"^\s*\{ '((?:[^'\\]|\\.)+)', '([A-Z|]+)', '((?:[^'\\]|\\.)*)' \},$", re.MULTILINE)
EXPECTED = {
    ('\\\\', 'CMD'): 'Split right',
    ('\\\\', 'CMD|SHIFT'): 'Split down',
    ('w', 'CMD'): 'Close file',
    ('t', 'CMD|SHIFT'): 'Reopen closed file',
    ('a', 'CMD|SHIFT'): 'Find action or shortcut',
    ('f', 'CMD'): 'Find in file',
    ('s', 'CMD'): 'Save all',
    ('F7', 'SHIFT'): 'Previous change',
}


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for WezTerm key checks')
class WeztermKeyTests(unittest.TestCase):
    def test_transport_codes_reach_jvim_actions(self):
        entries = KEY.findall((ROOT/'integrations/wezterm/jvim.lua').read_text())
        self.assertGreater(len(entries), 50, 'key table was not parsed')
        codes = {(key, mods): int(match.group(1)) for key, mods, sent in entries
                 if (match := re.fullmatch(r'\\x1b\[23;5~(\d+)', sent))}
        for binding in EXPECTED:
            self.assertIn(binding, codes, f'WezTerm no longer sends {binding} to jvim')
        with tempfile.TemporaryDirectory(prefix='jvim-wezterm-') as temporary:
            script = Path(temporary)/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('jvim.keymaps')
local actions = {}
for _, code in ipairs(vim.json.decode(vim.env.JVIM_TEST_CODES)) do
  local mapping = vim.fn.maparg('<F35>' .. code, 'n', false, true)
  actions[tostring(code)] = mapping.desc or vim.NIL
end
io.write(vim.json.encode(actions))
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=dict(os.environ, HOME=temporary, JVIM_TEST_CONFIG=str(ROOT/'config'),
                                             JVIM_TEST_CODES=json.dumps(sorted(set(codes.values())))),
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            actions = json.loads(result.stdout)
        unmapped = sorted(f'{mods}+{key} -> {code}' for (key, mods), code in codes.items() if actions[str(code)] is None)
        self.assertEqual(unmapped, [], 'WezTerm sends codes jvim does not map')
        for binding, action in EXPECTED.items():
            self.assertEqual(actions[str(codes[binding])], action, f'{binding} reaches the wrong action')

    def test_graphical_frontends_reach_the_same_actions_with_the_keys_themselves(self):
        # Neovide and other GUIs report Cmd+S as <D-s>, not as a transport code, so every action in the
        # terminal key table needs a direct mapping too. These are the deliberate exceptions.
        exceptions = [
            '<C-Left> Previous file',        # word movement, as in every text field
            '<C-Right> Next file',
            '<C-m> Go to matching bracket',  # Ctrl+M is Enter to Neovim
            '<D-S-Bar> Split down',          # reported as <D-Bar> or <D-S-Bslash>, both mapped
            '<S-Down> Select down',          # Shift+arrows select natively through 'keymodel'
            '<S-Up> Select up',
        ]
        with tempfile.TemporaryDirectory(prefix='jvim-gui-keys-') as temporary:
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/gui_keys.lua')],
                                    env=dict(os.environ, HOME=temporary, JVIM_TEST_CONFIG=str(ROOT/'config'),
                                             JVIM_TEST_MODULE=str(ROOT/'integrations/wezterm/jvim.lua')),
                                    capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), exceptions, 'actions a graphical frontend cannot reach, or stale exceptions')

    def test_iterm_codes_reach_jvim_actions(self):
        keys = json.loads((ROOT/'integrations/macos/keyboard.json').read_text())
        codes = {}
        for binding, entry in keys.items():
            sent = bytes(int(part, 16) for part in entry['Text'].split()) if entry.get('Action') == 11 else b''
            if match := re.fullmatch(rb'\x1b\[23;5~(\d+)', sent):
                codes[binding] = int(match.group(1))
        self.assertGreater(len(codes), 30, 'iTerm key map was not parsed')
        expected = {'0x5c-0x100000': 'Split right', '0x7c-0x120000': 'Split down', '0xf70a-0x20000': 'Previous change'}
        with tempfile.TemporaryDirectory(prefix='jvim-iterm-') as temporary:
            script = Path(temporary)/'check.lua'
            script.write_text('''
vim.opt.rtp:prepend(vim.env.JVIM_TEST_CONFIG)
require('jvim.keymaps')
local actions = {}
for _, code in ipairs(vim.json.decode(vim.env.JVIM_TEST_CODES)) do
  actions[tostring(code)] = vim.fn.maparg('<F35>' .. code, 'n', false, true).desc or vim.NIL
end
io.write(vim.json.encode(actions))
vim.cmd 'qall!'
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(script)],
                                    env=dict(os.environ, HOME=temporary, JVIM_TEST_CONFIG=str(ROOT/'config'),
                                             JVIM_TEST_CODES=json.dumps(sorted(set(codes.values())))),
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            actions = json.loads(result.stdout)
        unmapped = sorted(f'{binding} -> {code}' for binding, code in codes.items() if actions[str(code)] is None)
        self.assertEqual(unmapped, [], 'iTerm sends codes jvim does not map')
        for binding, action in expected.items():
            self.assertEqual(actions[str(codes[binding])], action, f'iTerm {binding} reaches the wrong action')

    def test_linux_and_windows_use_ctrl_where_the_mac_uses_cmd(self):
        for triple in ('x86_64-unknown-linux-gnu', 'aarch64-apple-darwin'):
            with self.subTest(triple=triple), tempfile.TemporaryDirectory(prefix='jvim-wezterm-') as temporary:
                result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/wezterm_keys.lua')],
                                        env=dict(os.environ, HOME=temporary, JVIM_TEST_TRIPLE=triple,
                                                 JVIM_TEST_MODULE=str(ROOT/'integrations/wezterm/jvim.lua')),
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
