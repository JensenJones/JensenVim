# JensenVim packaging plan

Package the current editor as an isolated `NVIM_APPNAME=jvim` configuration. Preserve the existing editor installation. Bundle the Mac launchers, shortcut preset, URL-handler source, pinned Python dependencies and plugin lockfile. Do not include history, caches, registries, sockets or account credentials.

1. Remove machine-specific executable paths and make the Mac helpers installable.
2. Build an installer that plans changes by default, backs up only managed destinations when applied, creates its own runtime, and registers the URL app without opening windows. First plugin installation remains an explicit user action.
3. Include a Windows core installer with explicit limitations; do not claim Windows desktop integration is verified.
4. Test isolated installation, backup behavior, shortcut coverage, autosave and closing the last file without terminal UI changes. Create a zip and checksums.
5. With Git approval, inspect the supplied remote, preserve its existing content/history, then commit/push with the required approval.

Review focus: existing user config isolation; Mac ARM/Intel executable paths; no CLion installation required; offline installer checks do not invoke Git; Windows unsupported integration is explicit.
