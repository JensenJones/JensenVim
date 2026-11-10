"""Run execution and conflict resolution using Neovim's native jobs and buffers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim required')
class WorkflowTests(unittest.TestCase):
    def check_case(self, case):
        with tempfile.TemporaryDirectory(prefix='jvim-workflows-') as temporary:
            project = Path(temporary).resolve() / 'project with spaces'
            project.mkdir()
            env = dict(os.environ, JVIM_TEST_CONFIG=str(ROOT / 'config'),
                       JVIM_TEST_PROJECT=str(project), JVIM_TEST_CASE=case)
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--noplugin', '-i', 'NONE',
                                     '-l', str(ROOT / 'tests/workflows.lua')],
                                    env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_run_config_validation_rejects_bad_commands_paths_and_environment(self):
        self.check_case('validation')

    def test_run_preserves_argv_cwd_environment_and_exit_status(self):
        self.check_case('execution')

    def test_running_session_reuse_retained_output_rerun_and_stop(self):
        self.check_case('lifecycle')

    def test_shell_terminal_reuses_hidden_session(self):
        self.check_case('shell')

    def test_shell_line_steps_run_in_order_and_stop_on_failure(self):
        self.check_case('steps')

    def test_form_creates_edits_and_deletes_named_configurations(self):
        self.check_case('form')

    def test_project_discovery_and_configuration_path_executable(self):
        self.check_case('project')

    def test_edit_configuration_prepares_saveable_json_without_running(self):
        self.check_case('edit')

    def test_conflict_acceptance_preserves_context_and_undo(self):
        self.check_case('merge')

    def test_diff3_base_empty_sides_and_manual_edits(self):
        self.check_case('diff3')

    def test_malformed_markers_never_mutate_result(self):
        self.check_case('malformed')

    def test_native_conflict_ui_has_readonly_previews_and_keeps_result(self):
        self.check_case('merge_ui')

    def test_diff3_preview_navigation_and_clickable_acceptance(self):
        self.check_case('merge_navigation')

    def test_statusline_preserves_folding_and_exposes_run_actions(self):
        self.check_case('statusline')
