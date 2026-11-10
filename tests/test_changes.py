"""Check the Git changes panel and side-by-side diffs against a real repository."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
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

    def test_file_open_in_another_editor_shows_read_only(self):
        with tempfile.TemporaryDirectory(prefix='jvim-changes-') as temporary:
            project = Path(temporary)/'project'
            project.mkdir()
            env = dict(os.environ, HOME=temporary, GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='jvim', GIT_AUTHOR_EMAIL='jvim@example.com',
                       GIT_COMMITTER_NAME='jvim', GIT_COMMITTER_EMAIL='jvim@example.com')
            (project/'shared.txt').write_text('one\n')
            for command in (['init', '-q'], ['add', '.'], ['commit', '-q', '-m', 'base']):
                subprocess.run(['git', *command], cwd=project, env=env, check=True)
            (project/'shared.txt').write_text('two\n')
            owner = subprocess.Popen(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', str(project/'shared.txt'), '-c', 'sleep 30'],
                                     cwd=project, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                swap_dir = Path(temporary)/'.local/state/nvim/swap'
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and not (swap_dir.exists() and list(swap_dir.glob('*.swp'))):
                    time.sleep(0.05)
                self.assertTrue(list(swap_dir.glob('*.swp')), 'owner did not create a swap file')
                result = subprocess.run(
                    # Script mode (-l) disables swap files, so source the checks the way a session would.
                    ['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE', '-c',
                     'lua local ok, err = pcall(dofile, vim.env.JVIM_TEST_SCRIPT) io.stderr:write(tostring(err)) vim.cmd(ok and "qall!" or "cquit!")'],
                    env=dict(env, JVIM_TEST_CONFIG=str(ROOT/'config'), JVIM_TEST_PROJECT=str(project), JVIM_TEST_CASE='live_swap',
                             JVIM_TEST_SCRIPT=str(ROOT/'tests/changes.lua')),
                    capture_output=True, text=True, timeout=20,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
            finally:
                owner.kill()
                owner.wait()
