"""Check the Git changes panel and side-by-side diffs against a real repository."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required for changes checks')
class ChangesTests(unittest.TestCase):
    def test_changed_file_tree_and_diff(self):
        with tempfile.TemporaryDirectory(prefix='jvim-changes-') as temporary:
            project = Path(temporary)/'project'
            (project/'src/core').mkdir(parents=True)
            env = dict(os.environ, HOME=temporary, GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='jvim', GIT_AUTHOR_EMAIL='jvim@example.com',
                       GIT_COMMITTER_NAME='jvim', GIT_COMMITTER_EMAIL='jvim@example.com')
            def git(*args):
                subprocess.run(['git', *args], cwd=project, env=env, check=True, capture_output=True)
            git('init', '-q')
            (project/'src/core/edit.txt').write_text('one\ntwo\nthree\n')
            (project/'gone.txt').write_text('a\nb\n')
            (project/'before.txt').write_text('moved contents\n')
            git('add', '.')
            git('commit', '-q', '-m', 'base')
            (project/'src/core/edit.txt').write_text('one\nTWO\nthree\n')
            (project/'src/core/new.txt').write_text('new\nfile\n')
            (project/'notes.txt').write_text('1\n2\n3\n')
            (project/'gone.txt').unlink()
            git('mv', 'before.txt', 'moved.txt')
            git('add', 'src/core/new.txt')
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/changes.lua')],
                env=dict(env, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(project)),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_diff_panes_scroll_together(self):
        with tempfile.TemporaryDirectory(prefix='jvim-changes-') as temporary:
            project = Path(temporary)/'project'
            project.mkdir()
            env = dict(os.environ, HOME=temporary, GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='jvim', GIT_AUTHOR_EMAIL='jvim@example.com',
                       GIT_COMMITTER_NAME='jvim', GIT_COMMITTER_EMAIL='jvim@example.com')
            lines = [f'line {number}' for number in range(1, 301)]
            (project/'long.txt').write_text('\n'.join(lines) + '\n')
            subprocess.run(['git', 'init', '-q'], cwd=project, env=env, check=True)
            subprocess.run(['git', 'add', '.'], cwd=project, env=env, check=True)
            subprocess.run(['git', 'commit', '-q', '-m', 'base'], cwd=project, env=env, check=True)
            del lines[49:59]
            (project/'long.txt').write_text('\n'.join(lines) + '\n')
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-l', str(ROOT/'tests/changes.lua')],
                env=dict(env, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(project), JVIM_TEST_CASE='scroll'),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
