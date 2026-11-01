# C++ Rename Checks Implementation Plan

**Goal:** Surface compiler errors left by incomplete clangd member renames without building or running user programs.

**Architecture:** Keep clangd's semantic rename. After a successful C/C++ rename, save the edited buffers through the existing autosave path and asynchronously run syntax-only checks using the project's compilation database. Publish compiler diagnostics at their actual source locations, including headers. Supply a menu action for repeating the check. Refresh Vatic's generated database from its Makefile, including unit tests.

**Tech stack:** Neovim diagnostics and quickfix errorformat, Python standard library, the project's compiler, compiledb for the one-off database refresh.

**Constraints:** Preserve user source. Never perform a textual member rename automatically. Do not execute built programs or produce object/dependency files. Cancel superseded checks and discard stale results. No Git operations without the user's requested approval.

- [x] Add regression tests for template-member errors in headers, command quoting, multi-input compile entries, and diagnostic clearing after a correction.
- [x] Implement the syntax-only runner and Neovim diagnostic integration, including cancellation and the Rename handler/menu action.
- [x] Refresh and validate Vatic's compilation database; install the editor changes with backups and verify the installed behaviour.

Validation covers real clangd rename, compiler diagnostics on headers, clearing errors after save, cancellation of a compiler ignoring SIGTERM, stale results from newly opened buffers, incomplete compiler runs, quoted response files, and suppression of build/dependency/diagnostic output files. A read-only code review found no remaining critical or high-impact issues after corrections. Git operations remain pending user approval.

Clangd documents that template references may be omitted from rename and some template diagnostics are suppressed in headers. The compiler check makes these failures visible; it does not claim to make clangd's template rename complete.
