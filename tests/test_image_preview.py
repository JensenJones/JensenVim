"""Verify jvim redraws cached image previews when their buffers are re-entered."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tests.support import isolated_env

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for image preview checks')
class ImagePreviewTests(unittest.TestCase):
    def test_image_buffer_entry_clears_and_redraws_cached_preview(self):
        with tempfile.TemporaryDirectory(prefix='jvim-image-') as temporary:
            env = isolated_env(temporary, JVIM_TEST_CONFIG=str(ROOT/'config'))
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(ROOT/'tests/image_preview.lua')],
                env=env, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

