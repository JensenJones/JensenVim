"""Completion expands placeholders without injected commands or tab-stop sessions."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BLINK = Path.home()/'.local/share/jvim/lazy/blink.cmp'


class CompletionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('nvim') and BLINK.is_dir(), 'Neovim and Blink required')
    def test_expansion_preserves_text_mode_and_cursor_without_snippet_jumps(self):
        env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_BLINK=str(BLINK))
        result = subprocess.run(
            ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(ROOT/'tests/completion.lua')],
            env=env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
