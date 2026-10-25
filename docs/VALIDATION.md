# Package validation — 2026-10-25

- Seven package checks passed: preview without writes; separate config plus repeat-install backups; Mac URL-app metadata/registration command plan without UI; launcher selects NVIM_APPNAME=jvim; legacy profile migration preserves unrelated profiles and records the actual iTerm parent; idle/focus-independent core autosave plus last-file exit and Windows mapping translation; closing an empty editor.
- Python, shell and JSON syntax checked. All Lua files compile with Neovim 0.12.5. Both AppleScript source files compile.
- Independent read-only review completed. Follow-up fixes pin the manager bootstrap across interrupted installs and preserve unrelated profiles during legacy migration.
- Tests use temporary homes and do not invoke Git or interact with desktop windows. Runtime package installation and LaunchServices registration are mocked in installer tests.
- Existing Mac desktop integration was exercised before packaging. The newly packaged installer has not been applied to the real home, and a clean-machine first launch has not been tested. It needs network access and plugin Git operations.
- Windows desktop delivery and the PowerShell installer remain untested on Windows; support is experimental.
- The iTerm hyperlink underline preference is cached. Correct UnderlineHyperlinks=false is saved, but no iTerm restart was performed and the current session may retain the old rendering.
