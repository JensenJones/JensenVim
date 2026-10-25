# jvim

Run in your existing Herdr pane:

    jvim .

The editor stays in that pane. It does not create iTerm tabs or windows. Its terminal keyboard mappings apply only while its pane is focused; your normal mappings return when you leave. Fonts and window layout are preserved.

- **Ctrl-click a code symbol:** jump to its definition, using the language server. Native Cmd-click is optional: search **Toggle Cmd-click code links (dashed underlines)** in the action menu.
- **Cmd+B:** keyboard navigation to a definition. Autosave preserves edits and undo without formatting or sorting imports; explicit saves can format.
- **Cmd+Shift+A:** search editor actions and see their shortcuts.
- **Cmd+1:** open/focus the project tree; press again while in the tree to hide it.
- Named files autosave after 800 ms without typing, when switching files, when leaving the editor, and on exit. New unnamed files still need **Cmd+S** to choose a filename.
- **Cmd+W:** close the current file; closing the last file exits jvim.
- **Single-click** a tree folder to expand/collapse it or a file to open it.
- Markdown renders in the editor, including while typing. Find **Toggle Markdown preview** in the action menu to switch between preview and source.
- **Cmd+Shift+W:** close the editor, asking about unsaved files.

Typing, mouse selection, Shift-selection and clipboard shortcuts use ordinary editing. Escape cancels a selection or popup and keeps you ready to type.

Use Herdr's normal **Ctrl+B, then N/P** to switch Herdr tabs. No extra iTerm tabs are needed.

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
| Cmd+1 | Project files |
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
| Option+Up | Extend selection |
| Option+Down | Shrink selection |
| Option+Shift+Up | Move line up |
| Option+Shift+Down | Move line down |
| Cmd+Backspace | Delete line |
| F2 | Next problem |
| Shift+F2 | Previous problem |
| F3, Ctrl+L, Cmd+G | Next search match |
| Shift+F3, Ctrl+Shift+L, Cmd+Shift+G | Previous search match |
| Cmd+- | Collapse code fold |
| Cmd+= | Expand code fold |
| Ctrl+M | Go to matching bracket |
| Cmd+Shift+Backspace | Last edit location |
| Cmd+Shift+E | Recent locations |

Extra conveniences: **Cmd+Shift+W closes the editor**, asking about unsaved files. Ctrl+Tab / Ctrl+Shift+Tab switch files; F12 also jumps to a definition. Home/End and Cmd+Left/Right move to line boundaries, Option+Left/Right move by word, and Shift extends selections. Tab/Shift+Tab indent/unindent selections. Copy/cut uses the current line when no text is selected. Cmd+D duplicates selected text or the current line. Cmd+S saves modified named files and asks for a path for a new unnamed file.

Find in file uses a literal query shared by next/previous search. File and project replacement treat search/replacement text literally and ask before replacing matches. Project replacement first offers a matching-file review and leaves edits unsaved until Save All.

## Scrolling and code assistance

Wheel/trackpad browsing remembers the editing position and returns there before the next keyboard action. Click to choose a new editing position. Neovim's visible cursor still moves when it reaches the viewport edge.

C/C++ uses your installed clangd for completion, diagnostics while typing, definitions, types, implementations, references, rename, fixes, documentation, and parameter information. Accurate includes and project symbols depend on the project's compiler flags or compilation database.

The supported actions cover editing and code navigation. CLion's project model, debugger, build/run configurations, and every language-specific refactoring are not reproduced by these bindings.

## Configuration and validation

- lua/custom/keymaps.lua: ordinary editing and main actions; loaded once after plugin setup.
- lua/custom/clion_actions.lua: selection, navigation history, find/replace and code actions.
- clion-keymap-audit.json: imported keybindings and action inventory.
- scripts/clion_profile.py: regenerate shortcut mappings from installed CLion settings.
- ~/Library/Application Support/iTerm2/DynamicProfiles/neovim-clion.json: separate terminal profile.
- ~/.local/bin/jvim: launcher in the current terminal pane.

Original backup: ~/.local/state/nvim-config-backups/20261025-122543/. Follow-up backup: ~/.local/state/nvim-config-backups/20261025-131701/. Git metadata was not copied, and the original iTerm profile was not edited.

Tests require Python with pynvim. clion_editing.py is isolated from plugins and uses an in-memory clipboard. clion_startup.py, clion_tree.py, and clion_workflows.py exercise installed plugins and may perform Git reads. clion_terminal.py checks terminal escape sequences. The Herdr checks used genuine macOS key and mouse events in an isolated pane, checking actions, clipboard, undo/redo, file operations, definition links, and keyboard restoration.

## Herdr integration

jvim uses your already-enabled iTerm scripting API to apply only keyboard mappings, through a small local helper that exits with the editor. It does not change the default profile or font settings. Profile focus ownership is shared safely between jvim panes.

Native Cmd-click uses invisible terminal hyperlink metadata attached to code identifiers. The local JvimLinks helper opens a definition in the same running editor. The original files and syntax colours are unchanged. A language server must support definition navigation for the current file.

Follow-up backup: ~/.local/state/nvim-config-backups/20261025-141724/.

The terminal integration uses iTerm's [local scripting API](https://iterm2.com/python-api/) and [dynamic-profile format](https://iterm2.com/documentation-dynamic-profiles.html).
