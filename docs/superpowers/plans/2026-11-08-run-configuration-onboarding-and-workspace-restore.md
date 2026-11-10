# Run Configuration Onboarding and Workspace Restore Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project run configs easy to create and sequence, and reliably restore the active repository workspace after Cmd+Shift+W.

**Architecture:** Keep `.jvim/run.json` as the portable source of truth, adding a setup picker and backwards-compatible command sequences. Execute each sequence step as an argv process in the existing terminal pane. Resolve session roots from active project context consistently at save and startup.

**Tech Stack:** Neovim Lua, JSON config files, Neovim terminal jobs, Python `unittest` harness.

**Spec:** `docs/superpowers/specs/2026-11-08-run-configuration-setup-design.md`

## Global Constraints

- Keep version 1 and all existing `command` configurations valid.
- Keep commands as argv arrays to preserve spaces and avoid shell-specific command quoting.
- Presets only write starter text; they never run commands during setup or project discovery.
- No new dependencies.
- Restore saved workspaces only when launching without explicit file arguments.

## Review Focus

- **Missing or empty `.jvim/run.json`:** Config opens setup choices rather than reporting an empty-config error. Cover with `test_empty_config_opens_setup_picker`.
- **Existing or malformed `.jvim/run.json`:** Preserve valid configurations; show a path and field-specific error for invalid JSON/schema. Cover existing validation cases and `test_setup_preserves_existing_configurations`.
- **A step failing in a sequence:** Stop before later steps, show the failed step and status, and allow a full rerun. Cover with `test_sequence_stops_after_failure_and_reruns_from_first_step`.
- **A session saved while the tree or a file in a nested directory is active:** Save and startup must resolve the same repository root. Cover with `test_close_action_saves_active_repository_root` and the existing two-process startup restore case.
- **A fresh launch with explicit file arguments:** Do not replace those arguments with a saved session. Cover with `test_explicit_file_arguments_bypass_workspace_restore`.

---

### Task 1: Validate backward-compatible command sequences

**Files:**
- Modify: `config/lua/jvim/run.lua`
- Test: `tests/workflows.lua`
- Test: `tests/test_workflows.py`

**Interfaces:**
- `run.load(root)` continues returning validated entries with normalized `cwd` and `root`.
- An entry accepts exactly one execution field: existing `command: string[]` or new `steps: string[][]`; `cwd` and `env` continue applying to every step.

- [ ] Add validation cases for a valid two-step entry, empty steps, an invalid argv in a later step, and entries that specify both `command` and `steps`.
- [ ] Run `python3 -m unittest tests.test_workflows.WorkflowTests.test_run_config_validation_rejects_bad_commands_paths_and_environment -v` and confirm the new sequence cases fail.
- [ ] Validate each step argv and return normalized entries with a `steps` array; normalize existing `command` entries into a single-step internal representation without changing their public compatibility.
- [ ] Run the focused workflow validation test and confirm existing single-command cases pass.

### Task 2: Execute steps in order in one run session

**Files:**
- Modify: `config/lua/jvim/run.lua`
- Modify: `config/lua/jvim/command_terminal.lua`
- Test: `tests/workflows.lua`
- Test: `tests/test_workflows.py`

**Interfaces:**
- `command_terminal.open(opts)` accepts the existing `command` argv and optional `steps: string[][]`.
- Existing session key, cwd, env, status, output buffer, stop, and rerun behavior remain intact.

- [ ] Add an execution case that records step order and a failure case that proves later steps do not start after a nonzero exit.
- [ ] Run the new sequence cases and confirm they fail because only one command runs today.
- [ ] Add a sequential argv job runner for `steps` that appends progress and exit status to the existing output buffer, stops on the first failure, and restarts from step one on rerun.
- [ ] Run sequence, lifecycle, and existing single-command execution tests.

### Task 3: Add empty-config setup and detected editable presets

**Files:**
- Modify: `config/lua/jvim/run.lua`
- Modify: `config/lua/jvim/fold_controls.lua`
- Modify: `config/lua/jvim/action_picker.lua`
- Test: `tests/workflows.lua`
- Test: `tests/test_workflows.py`

**Interfaces:**
- Add `run.setup(root)` to show project-detected starter presets and a custom-command starter.
- Keep `run.choose(root, execute)` selecting existing configurations; when missing or empty, route to `run.setup(root)`.
- Presets cover detected Make, CMake, Python/pytest, Node/npm, and Rust/Cargo markers and write editable JSON without running commands.

- [ ] Add tests for missing and empty files, each detected preset, custom starter creation, and preserving existing entries when adding another preset.
- [ ] Run the setup workflow tests and confirm they fail because no setup picker exists and empty configs error.
- [ ] Implement setup selection, starter JSON writing, and reopening the config editor for review; preserve valid entries and report malformed files clearly.
- [ ] Run the workflow tests, action picker checks, and status-line Config checks.

### Task 4: Resolve workspace sessions from active project context

**Files:**
- Modify: `config/lua/jvim/session.lua`
- Modify: `config/lua/jvim/clion_actions.lua`
- Modify: `config/lua/jvim/files.lua`
- Test: `tests/session.lua`
- Test: `tests/test_session.py`

**Interfaces:**
- `session.root(root?)` resolves explicit root, active Neo-tree root, active file ancestry, and finally cwd, then canonicalizes repository markers consistently.
- `session.save(root?)` and `session.restore(root?)` use that same canonical root.
- Cmd+Shift+W continues confirming unsaved changes and saves the session for the active repository.

- [ ] Add a two-process test that saves through the Cmd+Shift+W action while Neo-tree or a nested project file is active, then launches in the same repository and verifies splits, tabs, and views restore.
- [ ] Add a test proving explicit file arguments bypass session restoration.
- [ ] Run the new cases and reproduce the current save/restore root mismatch or missing action wiring.
- [ ] Resolve project root consistently at save and launch, and verify the close shortcut reaches `session.save`.
- [ ] Run all session, startup, and navigation tests.

### Task 5: Document behavior and verify the full change

**Files:**
- Modify: `docs/WORKFLOWS.md`
- Test: `tests/test_workflows.py`
- Test: `tests/test_session.py`

- [ ] Document empty-config setup, the preset list, `command` and `steps` examples, failure behavior, and workspace restore.
- [ ] Run `python3 -m unittest discover -s tests -v` and confirm all applicable tests pass.
- [ ] Run `nvim --headless -u config/init.lua --cmd 'qa!'` and `git diff --check`.
- [ ] Before any Git operation, follow the user's approval requirement for Git reads, commits, or pushes.
