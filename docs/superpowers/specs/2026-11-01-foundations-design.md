# jvim foundations

## Intent

Keep Neovim as the engine so jvim can adopt company language servers, build tools and debugger integrations. Preserve ordinary typing, terminal/Herdr operation, the current editing shortcuts and lightweight startup. The user has authorised a comprehensive implementation, with routine choices made autonomously.

## Architecture

- Provide a public `jvim` module and keep implementation modules in its namespace; do not compete with a host configuration's generic `custom` modules.
- Separate startup/bootstrap, personal configuration, editing contexts, history, files, completion, project execution, conflict resolution and platform integration.
- Load trusted personal/company Lua configuration from outside the managed installation. Expose explicit policies for plugin/tool/parser installation, LSP defaults and server overrides, formatting and callbacks. Never load project Lua automatically.
- Support a company overlay entry point that installs jvim editing without replacing the host plugin manager or language servers. Keep standalone `NVIM_APPNAME=jvim` installation as the default.
- Centralise editor eligibility/context capture and preserve asynchronous request origins. Use native APIs and existing libraries for editing and terminal operations.

## Deliverables

1. Correct UTF-8 editing, mouse/cross-file history, complete recent-file cycling, asynchronous prompt targeting and tree focus/new-file workflows. Fix actual failing baseline checks; update obsolete shortcut expectations explicitly.
2. Safe installation/update: stage before replacement, preserve plugin/parser/tool caches and external personal configuration, validate environment and paths, and make failure recovery explicit.
3. Validated run configurations stored as JSON; integrated terminal sessions with correct cwd/environment, reusable output, stop/rerun and discoverable menu/status controls. Run commands only after a user action.
4. Conflict-marker resolution with native diff panes, editable result, ours/theirs/base support, per-conflict acceptance and undo. Git discovery/staging is separate and remains subject to Git permission.
5. Accurate health diagnostics, portable configuration documentation, CI and a repeatable test command. Exercise real terminal input and asynchronous process lifecycles.

## Trade-offs and boundaries

An incremental modular refactor preserves working behaviour and existing integration support. A replacement editor would lose the company Neovim compatibility the user explicitly needs. No additional editor engine or dependency framework is introduced. Existing library functionality is reused; optional integrations must fail gracefully. No production deployments or automatic project-code execution. Run configurations are data, not executable configuration.

The user approved Git reads, branching, commits and pushes for this foundations task. Source changes and installation are reversible and preserve backups. Mac terminal behaviour is the primary validation target; actual Windows desktop testing must remain labelled separately.
