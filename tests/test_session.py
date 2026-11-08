"""Check that jvim restores project workspaces across Neovim processes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required for workspace checks')
class SessionTests(unittest.TestCase):
    def test_project_workspace_restores_between_processes(self):
        with tempfile.TemporaryDirectory(prefix='jvim-session-') as temporary:
            home = Path(temporary)
            project = home/'project'
            project.mkdir()
            (project/'.git').mkdir()
            (project/'nested').mkdir()
            for phase in ('save', 'restore', 'restore_startup'):
                env = dict(os.environ, HOME=str(home), NVIM_APPNAME='jvim', JVIM_TEST_CONFIG=str(ROOT/'config'),
                           JVIM_TEST_PROJECT=str(project), JVIM_SESSION_PHASE=phase)
                result = subprocess.run(
                    ['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/session.lua')],
                    env=env, capture_output=True, text=True, timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

