# A jvim desktop app: design

Status: proposal, 2026-11-15. Nothing here is built except the key parity in step 0.

## Why consider it

jvim's features live in the Lua configuration. The terminal is only the window, and it is where most of the platform-specific work goes:

- WezTerm needs a 94-entry key table that turns Cmd and Ctrl shortcuts into private escape codes, because terminals cannot report most modified keys.
- iTerm needs a profile switch driven by AppleScript, a Python runtime and a socket bridge.
- GNOME needs a script that frees desktop shortcuts, and Linux needs a clipboard tool installed.
- Each terminal differs in mouse, scrolling and image support, so each needs its own validation.

A graphical Neovim frontend receives real key events. Cmd+S arrives as `<D-s>`, with no table, bridge or escape codes. Windows already works this way: its installer starts jvim in Neovide by default.

## Options

1. **Neovide as the window, packaged as a "jvim" app on each platform.** Neovide is a maintained GPU frontend for macOS, Linux and Windows. jvim supplies a launcher, an icon and file associations.
2. **A custom app** (Tauri or Electron hosting Neovim over its RPC API). Full control of the window, at the cost of re-implementing text rendering, input methods, fonts and scrolling. Months of work before it matches a terminal.
3. **Terminal only**, as today on macOS and Linux.

## Recommendation

Option 1, alongside the terminal rather than instead of it. The editor stays one codebase; only the launcher differs. Terminal mode remains for SSH, Herdr panes and anyone who prefers it. Option 2 buys nothing jvim needs today.

## What already works

After the 2026-11-15 change, 88 of the 94 terminal shortcuts reach the same action in a graphical frontend through the key itself. The other six are deliberate (Ctrl+Left and Ctrl+Right stay word movement, Ctrl+M is Enter, Shift+Up and Shift+Down select natively, and one is a duplicate). `tests/test_wezterm_keys.py` fails if a new terminal shortcut is added without a direct key, so the two stay in step.

The Fold, Run and Config buttons already move to the winbar under Neovide, and Windows already opens PDFs in the system viewer.

## What is missing, in build order

0. Key parity. Done, and tested.
1. **Launchers.**
   - macOS: a small `jvim.app` bundle whose executable starts `neovide --neovim-bin <nvim>` with `NVIM_APPNAME=jvim`. Its `Info.plist` declares source-file document types, so Finder's "Open With" and the Dock work. `install/macos.py` already builds and registers an app bundle for the URL handler and can build this one the same way.
   - Linux: a `jvim.desktop` entry and icon under `~/.local/share`, written by `install-linux.sh`.
   - Windows: a Start Menu shortcut to the existing `jvim.cmd`.
   - `jvim --gui` and `jvim --terminal` on every platform, with the default set by `JVIM_FRONTEND`.
2. **Mac keyboard setting.** Neovide must treat Option as Alt (`vim.g.neovide_input_macos_option_key_is_meta = 'both'`), or Option+arrows type symbols instead of moving by word.
3. **Font.** A GUI needs `guifont`. Default to a short fallback list and expose it as `ui.font` in the personal configuration.
4. **Features that currently depend on the terminal.**
   - PDF and image preview use the Kitty graphics protocol, which Neovide does not draw. Open them in the system viewer, as Windows does.
   - "Move file to a new window" and "Run in a new window" call `wezterm cli spawn`. Under a GUI, start a second jvim window or a terminal emulator instead.
   - The horizontal scroll direction reads a WezTerm focus file. Under a GUI the direction is fixed, so skip the check.
   - Cmd-click code links use terminal hyperlinks. The existing Ctrl-click and Cmd-click mapping covers a GUI.
5. **Validation.** The headless tests do not depend on the frontend. Add one launch check per platform that starts the app, opens a file and quits.

Steps 1 to 3 are about two days of work and give a usable app. Step 4 is another two or three days.

## Costs

- Neovide becomes a dependency (about 30 MB) with its own release cadence and bugs.
- Two frontends to keep working. The parity test and shared configuration limit this, and Windows already carries the cost.
- No in-editor PDF or image preview in the app until Neovide supports image protocols.

## Decision needed

Whether the app becomes the documented default on macOS and Linux or stays an alternative to the terminal. Building steps 1 to 3 first and using it for a week answers that with experience instead of a guess.
