# Per-Pane Tabs and Project Workspace Design

## Intent

Make split editor panes behave like separate IntelliJ editor groups, persist the selected
colour theme, and restore a repository's editor workspace when jvim is reopened.

## Current behavior

`jvim.files` tracks one global file list and recent-file order. The `mini.tabline` click
handler and Ctrl+Tab mappings switch the buffer in the focused editor window. As a result,
tabs are shared across panes and switching files can feel like replacing a pane's contents.
The theme picker exists, but the selected theme is reset at startup and the picker offers
only two choices. jvim has no project workspace restore; closing the editor loses the split
layout and each pane's tab order.

## Proposed behavior

- Each editor window owns an ordered list of file buffers.
- A file opened from Neo-tree is added to, and displayed in, the focused editor pane. If no
  editor pane exists, jvim creates one as it does today.
- Ctrl+Tab and Ctrl+Shift+Tab cycle only through the current pane's files.
- Each pane shows its own clickable tab strip in its winbar. Clicking a tab changes only
  that pane.
- A newly created split starts with the current file as its only tab. Tabs opened later in
  either split remain local to that split.
- Closing a tab removes it from the current pane. If another pane still has that file open,
  its buffer remains available there.
- Replace the global `mini.tabline` display with the per-pane strips. Do not change terminal
  tabs or OS window behavior.
- Persist the selected theme under jvim's user state directory. Keep `jvim-charcoal` and
  `dark-ubuntu`, and add the built-in `habamax`, `slate`, `desert`, and `morning` schemes
  when available in the installed Neovim runtime. Use charcoal if there is no valid saved
  choice. Do not add a theme plugin dependency.
- Cmd+Shift+W closes jvim and saves the current repository workspace. When jvim is next
  launched from that repository, restore the editor split layout, files in each pane,
  pane-local tab order, cursor positions, and scroll positions. A launch with an explicit
  file argument opens that file normally instead of restoring over it.
- Store workspace state under jvim's state directory, keyed by canonical project root. Keep
  the existing unsaved-buffer confirmation behavior; workspace saving must not silently
  write unsaved file contents to disk.

## Approaches considered

1. Use Neovim tabpages as editor groups. This is simpler, but a Neovim tabpage contains an
   entire split layout; it does not give each split pane its own tab strip.
2. Keep the global tabline and only make Ctrl+Tab pane-local. This reduces code changes but
   still displays a shared tab list, so it does not provide the IntelliJ-like behavior asked
   for.
3. Track buffers per editor window and render a local tab strip in each window's winbar.
   This matches the requested behavior and does not require another plugin, at the cost of
   replacing the current global tabline integration.

Use approach 3 for editor tabs. For workspace restoration, use a native Neovim session file
for split and buffer layout, with a JSON sidecar for pane-local tab order and per-file views.
The sidecar keeps independent pane state separate from global buffer order. Persist the
validated theme name in jvim's state directory.

## Scope and checks

Update file/tab management, the project-close action, startup restoration, the theme module,
and tabline setup. Verify pane-local open, click, cycle, split, and close behavior; theme
selection persistence and fallback; and saving/restoring a repository workspace with two
panes, independent tab order, and saved views.

## Not included

There will be no changes to terminal tabs or OS window behavior. jvim will not save unsaved
buffer contents unless the existing autosave/confirmation behavior does so.
