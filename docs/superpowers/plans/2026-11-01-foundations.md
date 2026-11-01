# jvim foundations implementation plan

**Goal:** A maintainable, portable Neovim editor whose modeless editing and development workflows are dependable.

**Spec:** `docs/superpowers/specs/2026-11-01-foundations-design.md`.

**Architecture:** Incremental modules with explicit ownership, a trusted external settings layer and a public company-overlay API. Keep Neovim and existing libraries; verify behaviour through isolated headless and terminal integration tests.

## Tasks

- [x] Establish the full baseline and record failures.
- [x] Harden input/context/history/file lifecycle with regression tests.
- [x] Stage safe installers and preserve external configuration and managed caches.
- [x] Implement run sessions, project terminal reuse and conflict-marker workflows with tests.
- [x] Add validated settings, offline/company policies, bootstrap modules, health checks and a public overlay entry point.
- [x] Consolidate implementation modules under `jvim`, integrate action/status controls and document configuration and workflows.
- [x] Add CI and a repeatable validation command; run the complete suite and independent review.
- [x] Install with backups and verify the complete editor. Commit/push after the granted approval.

## Ownership

Input worker: keymaps, ordinary editing, files/history/scroll and dedicated editing tests. Package worker: installers/launcher and package tests. Workflow worker: run/terminal/merge modules and dedicated workflow tests. Coordinator: settings/bootstrap/public API, final namespace migration, integration, documentation, CI and validation. Workers do not overlap edits to the coordinator-owned integration files.

## Completion evidence

- Baseline: 84 tests, four failures (three outdated shortcut expectations and one real mouse-history failure); all resolved.
- Final: `python3 scripts/check.py` — 152 passed, three Windows execution tests skipped; Python/Lua syntax passed.
- Three independent reviews completed; all confirmed findings fixed with regression coverage.
- Installed with managed-file backups and cache preservation; full installed offline TUI smoke passed for startup, picker, run and merge workflows.
- Details and honest platform/CI boundaries: `docs/VALIDATION.md`.
