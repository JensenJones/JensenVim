# Package validation — 2026-10-25

- Twelve automated checks pass: isolated preview/install/backups; URL-app metadata without UI; launcher configuration isolation; legacy profile preservation; autosave and empty/last-file exit; Windows key translation; undo import-order stability through autosave; bridge socket reconnect; opt-in URL decoration with diagnostics retained; unique replacement-host resolution; focused-pane/terminal ownership, spurious blur handling and scoped Ctrl-click restoration.
- A separate headless check using the installed Conform plugin and real clang-format confirmed Cmd+Z restores original imports and autosave does not sort them again. No Git was needed for that check.
- Python, shell, JSON and Lua syntax checks pass. Both AppleScript sources compile. Development checks use Neovim 0.12.5.
- Independent read-only review identified cleanup and focus issues. Cleanup now restores the global Ctrl-click setting independently of terminal-setting failures and always unlinks the socket; the watcher checks the active iTerm host as well as Herdr's pane focus.
- Running local editor repaired without opening/switching tabs. Buffer changedtick, undo sequence and typing mode stayed unchanged during the repair. Code hyperlinks are off; keyboard definition and Ctrl-click mappings remain. New desktop keystrokes/mouse clicks were not simulated, so real Cmd+W/Ctrl-click delivery still needs user confirmation.
- Fresh-machine runtime dependency installation and LaunchServices registration are mocked in installer tests. First editor startup needs network access and plugin Git operations.
- Windows desktop delivery and PowerShell installation remain untested on Windows; support is experimental.
- The installer no longer changes iTerm's global underline setting. Native Cmd-click is an opt-in action, with iTerm's dashed link decoration. Default mouse definition navigation is Ctrl-click.
