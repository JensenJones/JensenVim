# Foundation validation — 2026-11-01

`python3 scripts/check.py` passed on macOS with Neovim 0.12.5: **152 tests passed, 3 Windows-only tests skipped**, no failures or errors. Syntax validation covered 25 Python and 55 Lua source files. The command reports individual skip reasons and fails when prerequisites or syntax checks fail.

## Exercised locally

- Real Neovim terminal input with cached plugins: modeless typing/selection, mouse dragging and double-clicking, Option/Shift word movement, UTF-8 boundaries, selected-text replacement/surrounding, Shift+Enter, completion argument placeholders, clipboard indentation, tree focus/new-file actions, navigation history, file cycling and terminal closure.
- Isolated settings/profile precedence, list replacement, invalid settings, offline fresh/cached startup, standard plugin entry, overlay idempotence, preservation of the host namespace/explorer, native LSP fallback and highlight attachment/detachment.
- Native jobs and terminal buffers: argument/cwd/environment/PATH handling, retained output, reuse, rerun, stop and exit status. Ordinary/diff3 conflicts, malformed markers, native diff previews, click controls, acceptance and undo.
- Installer preparation failures, rollback, cache preservation, real virtual-environment paths, and direct installed launcher execution with interpreter paths containing spaces/apostrophes, empty PATH, argument forwarding and exit status.
- Compiler-check subprocess cancellation/reaping, compile-command sanitisation and diagnostics; rename inputs, include organisation, namespace indentation, themes, swap recovery and iTerm bridge ownership logic.

An additional smoke check used the newly installed full configuration and launcher in a pseudo-terminal, with offline policy and existing caches. It verified startup with one tree and no blank tab, an empty action-picker query, a run configuration's output/exit status, the listed configuration editor, and native merge acceptance. A headless installed startup also completed with plugins available and an empty `vim.v.errmsg`; image.nvim reported the expected lack of terminal geometry in headless mode.

Independent read-only reviews covered startup/configuration, packaging and editing/workflows. The reported optional-Mason startup failure, unlisted run-config editor and interpreter-path launcher failure were fixed and covered by regressions.

## Boundaries

Tests use temporary project/install homes. Plugin-dependent terminal tests use existing local Neo-tree/Telescope/Blink/LuaSnip caches; they do not bootstrap dependencies. Optional parser/plugin checks skip when those caches are absent. The complete local result above includes the available terminal/plugin tests.

CI is configured for Linux/macOS syntax and isolated tests, plus Windows PowerShell packaging tests. Fresh CI machines lack optional plugin caches and report those checks as skipped. Workflow execution after pushing is separate from the local result; no CI pass is claimed here.

Windows desktop keyboard/mouse delivery is unverified. The three Windows execution tests skipped on this Mac. Fresh-machine network dependency installation, desktop LaunchServices registration and real iTerm/Herdr hardware shortcut delivery were not repeated in this pass. The installed update preserved the existing Python runtime and URL helper app, and backed up managed files under `~/.local/state/jvim/backups/20261101-213021-9e362acf`.

Compiler diagnostics depend on a current compilation database and instantiated code; clangd rename cannot guarantee every dependent template reference is updated. No debugger, published Homebrew formula or universal company-integration compatibility is claimed.
