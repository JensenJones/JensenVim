# Ergonomic colour scheme design

## Intent

Replace jvim's `dark-ubuntu` default with a purpose-built theme based on the user's CoderPad screenshot. Keep the existing scheme available as a quick fallback.

## Goals

- Use the screenshot's charcoal background, soft grey text, mauve keywords, blue types, cyan identifiers, peach strings, gold functions, and green comments.
- Keep the palette restrained while giving syntax roles distinct hues; do not rely on red/green differences alone.
- Keep the cursor, selections, matching brackets, diagnostics, current word, file tree, completion menu, and statusline easy to distinguish.
- Check normal foreground and key UI text/background pairs against a 4.5:1 contrast floor. This is an accessibility target, not a promise that one palette is optimal for every person or room.
- Switch between the new theme and `dark-ubuntu` from a searchable submenu under the existing Cmd+Shift+A action picker. Add no keybind.
- Make the new theme the default at startup; apply choices immediately for the current session.

## Non-goals

- No automatic day/night switching or light theme in this change.
- No changes to typing, navigation, or editor layout.

## Approaches considered

1. **Action-picker submenu (selected):** Add a hidden `Choose colour theme` action to the existing Telescope action picker, opening a compact theme list. This matches the request for a menu with no new shortcut and keeps the theme choice discoverable through the existing action search.
2. **Command only:** Add a `:Theme` command. This is smaller but less visible and less consistent with jvim's existing action menu.
3. **Automatic day/night theme:** Switch palettes by time or ambient conditions. It is more complex and may change appearance unexpectedly; it is outside the requested quick manual swap.

## Implementation outline

- Add the new theme as a maintained jvim Lua colorscheme rather than patching a third-party theme.
- Load the charcoal theme by default and expose `dark-ubuntu` as the fallback option.
- Build the submenu using the existing Telescope UI and use the same theme loader at startup and during switching.
- Reapply jvim-specific highlights after theme changes, including the cursor, scroll anchor, bracket match, word match, and fold controls.
- Verify contrast values for text and major UI states; launch a fresh editor to inspect plugin highlights and ensure the picker switches immediately.

## Design choices

The user selected the palette from the attached CoderPad screenshot and requested quick switching from a hidden menu, without a new keybind. The existing `dark-ubuntu` theme remains available as the fallback. Exact hex values are adapted to the screenshot and checked for readable contrast.
