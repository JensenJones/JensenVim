# Per-Pane Tabs and Project Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each jvim editor pane its own file tabs, persist theme choice, and restore the repository workspace after closing and reopening jvim.

**Architecture:** Track ordered buffers and views by editor window, render tabs in each pane's winbar, and route open/cycle/close operations to that pane. Save Neovim's split/buffer layout in a project-keyed session file and pane tabs/views in a JSON sidecar. Persist validated theme names separately in jvim's state directory.

**Tech Stack:** Neovim Lua, native `:mksession`, Telescope or `vim.ui.select`, Python `unittest` integration harness.

**Spec:** `docs/superpowers/specs/2026-11-08-per-pane-editor-tabs-design.md`

## Global Constraints

- Do not alter terminal tabs or OS window behavior.
- A new split begins with its displayed file as its only tab.
- Closing a pane-local tab must preserve a buffer displayed or listed in another pane.
- Explicit file arguments at startup must not be replaced by a saved workspace.
- Do not write unsaved file contents as a side effect of workspace saving.
- Theme choices must work without adding a theme plugin dependency.

## Review Focus

- Switching a pane while another pane displays a file must not replace that pane; test two-pane cycling.
- Opening a file from Neo-tree must add it to the focused pane; test the real tree-open path.
- A tab click must affect the pane whose winbar was clicked; test click dispatch using its window ID.
- Closing a shared tab must preserve the same file in another pane; test pane-local close.
- Deleted files, invalid theme-state files, and invalid workspace-session files must fall back safely without aborting startup; test missing-file filtering and corrupted-state recovery.
- A restored pane must keep its independent tab order and each tab's view; test a two-process save/restore scenario.

---

### Task 1: Add pane-local file collections, cycling, and views

**Files:**
- Modify: `config/lua/jvim/files.lua`
- Modify: `config/lua/jvim/keymaps.lua`
- Test: `tests/navigation.lua`
- Test: `tests/test_navigation.py`

**Interfaces:**
- `jvim.files.list()` remains the global buffer list for existing callers; `jvim.files.pane_tabs(win?)` returns valid buffers in the selected/current editor pane's tab order.
- `jvim.files.show(buf, cycling?, win?)` displays a buffer in the selected pane.
- `jvim.files.cycle(direction)` cycles only within the focused editor pane, or the last editor pane when focus is in Neo-tree.
- `jvim.files.snapshot()` returns ordered pane tab paths, active tab, and per-tab views; `restore_snapshot(data)` reapplies that state to restored editor windows.

- [x] Add an integration case with two panes and distinct file lists; assert cycling in either pane leaves the other pane unchanged.
- [x] Run `python3 -m unittest tests.test_navigation.NavigationTests.test_pane_local_file_cycling -v`; confirm the new behavior fails before implementation.
- [x] Implement pane state keyed by editor window, update views on pane/file changes, seed new splits with their current file, and scope `show` and `cycle` to the target pane.
- [x] Run the focused pane-local test and existing navigation tests; confirm they pass.

### Task 2: Render pane-local tabs and close tabs locally

**Files:**
- Modify: `config/lua/jvim/files.lua`
- Modify: `config/lua/jvim/keymaps.lua`
- Modify: `config/lua/jvim/plugins.lua`
- Test: `tests/navigation.lua`
- Test: `tests/test_navigation.py`

**Interfaces:**
- `jvim.files.render_winbar()` renders the active pane's tab strip.
- `jvim.files.click_tab(minwid, clicks, button, mods)` switches the clicked pane to its selected tab.
- Closing a tab removes it only from the current pane and deletes a buffer only if no pane still references it.

- [x] Add tests for a tab strip on each editor window, clicking a tab in one pane, and closing a file still open in another pane.
- [x] Run those cases and confirm they fail with the global `mini.tabline` behavior.
- [x] Set per-window winbars, hide the global `mini.tabline`, route clicks to the clicked window, and make Cmd+W close only the pane-local tab.
- [x] Run the new and existing close/navigation cases; confirm they pass.

### Task 3: Persist theme choices and expose more built-in schemes

**Files:**
- Modify: `config/lua/jvim/theme.lua`
- Modify: `tests/theme.lua`
- Modify: `tests/test_theme.py`

**Interfaces:**
- `jvim.theme.names()` returns the existing charcoal and Dark Ubuntu choices plus available built-in `habamax`, `slate`, `desert`, and `morning` themes.
- `jvim.theme.apply(name)` applies a supported scheme and persists its name under `stdpath('state')/jvim`.
- `jvim.theme.setup()` restores the saved supported scheme, defaulting to charcoal for missing/invalid state.

- [x] Add tests for all added theme entries, persisted selection after module restart, and invalid saved-name fallback.
- [x] Run the new tests and confirm they fail because only two themes are exposed and setup always chooses charcoal.
- [x] Add the available built-in themes, save successful selections to state, and load the validated saved choice at startup.
- [x] Run all theme tests; confirm picker selection still applies immediately and persists.

### Task 4: Save and restore per-repository workspace sessions

**Files:**
- Create: `config/lua/jvim/session.lua`
- Modify: `config/lua/jvim/files.lua`
- Modify: `config/lua/jvim/keymaps.lua`
- Modify: `config/lua/jvim/action_picker.lua`
- Test: `tests/session.lua`
- Create: `tests/test_session.py`

**Interfaces:**
- `jvim.session.save(root?)` writes a native session plus a JSON sidecar under `stdpath('state')/jvim/sessions`, keyed by canonical root.
- `jvim.session.restore(root?)` restores only when launching the same project without an explicit file argument; returns whether restoration succeeded.
- `jvim.files.snapshot()` and `restore_snapshot(data)` from Task 1 persist pane-local tabs and views alongside native split layout.

- [x] Add a two-process test: create a project with two split panes, different tab orders and cursor/scroll positions; save and exit; relaunch and restore; assert layout, buffers, order, and views.
- [ ] Add tests that explicit file arguments bypass restore and a corrupt session falls back to normal startup.
- [x] Run new session tests and confirm they fail because no session module or persisted workspace exists.
- [x] Implement canonical-root state paths, native session save/restore, JSON pane metadata, and safe fallback on invalid state.
- [x] Update Cmd+Shift+W to save the workspace before its existing confirmed quit; make startup restore before normal project-tree initialization.
- [x] Run the session tests and related startup/navigation tests; confirm they pass.

### Task 5: Document and run full verification

**Files:**
- Modify: `docs/KEYBOARD.md`
- Test: `tests/test_navigation.py`
- Test: `tests/test_theme.py`
- Test: `tests/test_session.py`

- [x] Document per-pane tabs, project restore on launch, and Cmd+Shift+W workspace close.
- [x] Run `python3 -m unittest discover -s tests -v`; confirm all applicable tests pass.
- [x] Run `nvim --headless -u config/init.lua --cmd 'qa!'`; confirm config startup has no Lua errors.
