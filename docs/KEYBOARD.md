# jvim

Run in your existing Herdr pane:

    jvim .

The editor stays in that pane and does not create tabs or windows. Its keyboard mappings apply only while its pane is focused; your normal mappings return when you leave. Fonts and window layout are preserved.

`jvim` and `jvim /project/path/` start in the project tree without an empty file tab. Opening a file creates the editor pane beside the tree. Each editor pane has its own clickable file tabs and remembers its own cursor and scroll position in each file; Ctrl+Tab and Ctrl+Shift+Tab switch only among that pane's files. The focused pane's current tab is filled in; other panes show their current tab underlined. Closing a file keeps the remaining file visible, and closing a pane's last file closes the pane. **Cmd+Shift+T** reopens the last closed file in its pane at the same location, recreating the pane if it was closed.

- **Ctrl-click a code symbol:** jump to its definition, using the language server. Native Cmd-click is optional: search **Toggle Cmd-click code links (dashed underlines)** in the action menu.
- **Cmd+B:** keyboard navigation to a definition. Autosave preserves edits and undo without formatting or sorting imports; explicit saves can format.
- **Cmd+Shift+A:** search editor actions and see their shortcuts.
- **F4:** toggle the project tree from any editor mode, including while the tree has focus. Use **Fn+F4** if the Mac reserves F4 for Launchpad.
- **PDF viewer:** `[` previous page, `]` next page, `q` close.
- **Cmd+N:** add a file beside the selected tree file or inside the selected folder, without toggling its expansion.
- Named files autosave after 800 ms without typing, when switching files, when leaving the editor, and on exit. New unnamed files still need **Cmd+S** to choose a filename.
- Stale swap files are backed up and recovered automatically; active editors keep Neovim's normal swap protection.
- **Cmd+W:** close the current file; closing the last file exits jvim.
- **Single-click** a tree folder to expand/collapse it or a file to open it.
- Markdown renders in the editor, including while typing. Find **Toggle Markdown preview** in the action menu to switch between preview and source.
- **Cmd+Shift+W:** save the current project's split layout and sizes, each pane's tabs, and cursor and scroll positions, then close the editor after asking about unsaved files. Launch jvim in that project again to restore the workspace. Choose **Save workspace and close editor** in the action menu to do the same.

Typing, mouse selection, Shift-selection and clipboard shortcuts use ordinary editing. Double-click selects a word; typing replaces the selected text. Escape cancels a selection or popup and keeps you ready to type.

**Shift+Arrow** extends a character or line selection; **Shift+Option+Left/Right** extends by a word. **Cmd+Left** moves to the first nonblank column (preserving indentation), and **Cmd+Right** moves to the end of the line.

Use Herdr's normal **Ctrl+B, then N/P** to switch Herdr tabs. No extra terminal tabs are needed.

## Keymap

These bindings are generated from your active macOS copy keymap and its bundled Mac OS X 10.5+ parent. The importer accounts for CLion's Control/Command conversion on inherited shortcuts. **Cmd+Option+Left/Right** navigates backward/forward through mouse locations, file switches, searches, and definition jumps.

| CLion shortcut | Action |
| --- | --- |
| Cmd+C | Copy |
| Cmd+X, Shift+Delete | Cut |
| Cmd+V | Paste |
| Cmd+S | Save all |
| Cmd+Shift+O | Find file |
| Cmd+Shift+F | Search project |
| Cmd+E | Recent files |
| Cmd+W | Close file |
| Cmd+Option+minus/equal | Collapse / expand code fold |
| Shift+F6 | Rename symbol |
| Option+Return | Quick fix |
| Cmd+Option+L | Format file |
| Cmd+A | Select all |
| Cmd+Z | Undo |
| Cmd+Shift+Z, Option+Shift+Backspace | Redo |
| Cmd+D | Duplicate line or selection |
| Cmd+/ | Toggle comment |
| Cmd+F | Find in file |
| Cmd+B | Go to definition |
| Option+F7 | Find usages |
| Cmd+[, Cmd+Option+Left | Navigate back |
| Cmd+], Cmd+Option+Right | Navigate forward |
| Shift+Cmd+T | Reopen closed file |
| Cmd+Shift+], Ctrl+Right | Next file |
| Cmd+Shift+[, Ctrl+Left | Previous file |
| Cmd+Shift+A | Find action or shortcut |
| Cmd+Option+B | Go to implementation |
| Cmd+Shift+B, Ctrl+Shift+B | Go to type declaration |
| F1, Ctrl+J | Quick documentation |
| Cmd+P | Parameter info |
| Cmd+F12 | File structure |
| Cmd+Option+O | Find symbol |
| Cmd+O | Find class |
| Cmd+L | Go to line |
| Cmd+R | Replace in file (confirm each match) |
| Cmd+Shift+R | Replace in project (preview and confirmation) |
| Ctrl+Shift+G | Show Git changes: changed-file tree with side-by-side diffs |
| Option+Up | Extend selection |
| Option+Down | Shrink selection |
| Option+Shift+Up | Move line up |
| Option+Shift+Down | Move line down |
| Cmd+Backspace | Delete line |
| F2 | Next problem |
| Shift+F2 | Previous problem |
| F3, Ctrl+L, Cmd+G | Next search match |
| Shift+F3, Ctrl+Shift+L, Cmd+Shift+G | Previous search match |
| Ctrl+M | Go to matching bracket |
| Cmd+Shift+Backspace | Last edit location |
| Cmd+Shift+E | Recent locations |

**Cmd+plus/minus** keep their normal terminal font zoom behaviour. When a Tree-sitter parser is available, **Cmd+Option+minus** collapses the fold at the cursor and **Cmd+Option+equal** expands it. Matching brackets use an underline so the cursor remains visible; nested brackets use rainbow colours when a parser is available.

The status line also has clickable **[- Fold]** and **[+ Fold]** controls. **Cmd+Option+semicolon** opens a shell in the current project; close its pane with **Cmd+W**. Horizontal trackpad swipes move the text with your finger.

Extra conveniences: Ctrl+Tab / Ctrl+Shift+Tab switch files in the active pane; F12 also jumps to a definition. The colour theme picker remembers the chosen theme. Home/End move to line boundaries; Cmd+Left goes to the first nonblank column, and Cmd+Right to the line end. Option+Left/Right move between identifier ends, skipping punctuation and spaces; Shift+Option extends selection by identifier. Tab/Shift+Tab indent/unindent ordinary selections; inside a completion's argument placeholders they move to the next/previous argument. Copy/cut uses the current line when no text is selected. Cmd+D duplicates selected text or the current line. Cmd+S saves modified named files and asks for a path for a new unnamed file.

Tab or Enter accepts a function suggestion and selects the first argument for typing over. Continue through arguments with Tab, or go back with Shift+Tab; the final Tab exits after `)`. Escape, switching files or moving outside the call abandons the placeholder session.

Find in file uses a literal query shared by next/previous search. File and project replacement treat search/replacement text literally and ask before replacing matches. Project replacement first offers a matching-file review and leaves edits unsaved until Save All.

## Scrolling and code assistance

Wheel/trackpad browsing keeps a stationary marker at the editing position and hides the native cursor so it does not appear to follow the viewport edge. Typing returns to the saved position; clicking chooses a new editing position.

C/C++ uses your installed clangd for completion, diagnostics while typing, definitions, types, implementations, references, rename, fixes, documentation, and parameter information. Accurate includes and project symbols depend on the project's compiler flags or compilation database.

Successful C/C++ renames also trigger asynchronous syntax-only compiler checks using `compile_commands.json`, so errors in instantiated header templates appear in the editor. Checked projects recheck after saved edits. Use **Cmd+Shift+A → Check C++ project (syntax only)** to start a check manually. Include test sources in the database. Some dependent template references remain outside clangd's rename support; uninstantiated templates may need review even when compiler checks pass.

Run configurations and merge-conflict controls are available in the action picker and status line. See [Project workflows](WORKFLOWS.md). CLion's debugger and full refactoring engine are not reproduced.

## Configuration and validation

Personal settings live outside the managed configuration, in `~/.config/jvim-user/init.lua` (or `%LOCALAPPDATA%/jvim-user/init.lua` on Windows). **Edit personal jvim configuration** opens this file. See [Configuration and company integrations](CONFIGURATION.md) for profiles, tool policies, offline startup and the company overlay API.

Implementation modules live in `config/lua/jvim/`; `config/init.lua` is the standalone entry. The Mac launcher is `~/.local/bin/jvim`, and its iTerm dynamic profile is `~/Library/Application Support/iTerm2/DynamicProfiles/jvim.json`.

Run `python3 scripts/check.py` for syntax and isolated tests. Optional plugin/parser checks report skips when their local dependencies are unavailable. See [Validation](VALIDATION.md) for coverage and limitations.

## Terminal integration

In WezTerm, `integrations/wezterm/jvim.lua` (linked to `~/.local/share/jvim/wezterm.lua`) sends jvim's shortcut codes only while the focused pane, or focused Herdr pane, is running jvim; elsewhere each key keeps its normal WezTerm action.

In iTerm2, jvim uses your already-enabled iTerm scripting API to apply only keyboard mappings, through a small local helper that exits with the editor. It does not change the default profile or font settings. Profile focus ownership is shared safely between jvim panes.

Native Cmd-click uses invisible terminal hyperlink metadata attached to code identifiers. The local JvimLinks helper opens a definition in the same running editor. The original files and syntax colours are unchanged. A language server must support definition navigation for the current file.

The terminal integration uses iTerm's [local scripting API](https://iterm2.com/python-api/) and [dynamic-profile format](https://iterm2.com/documentation-dynamic-profiles.html).
