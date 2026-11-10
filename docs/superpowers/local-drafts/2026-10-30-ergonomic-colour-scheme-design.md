# Ergonomic colour scheme design

## Intent

Replace jvim's `dark-ubuntu` default with a purpose-built soft-charcoal theme that is easier to scan during long coding sessions. Keep the existing scheme available as a quick fallback.

## Goals

- Use a charcoal background and warm, high-contrast foreground without pure black or glaring white.
- Give syntax roles distinct hue and lightness so meaning does not rely on red/green differences alone.
- Keep the cursor, selections, matching brackets, diagnostics, current word, file tree, completion menu, and statusline easy to distinguish.
- Check normal foreground and key UI text/background pairs against a 4.5:1 contrast floor. This is an accessibility target, not a promise that one palette is optimal for every person or room.
- Switch between the new theme and `dark-ubuntu` from a searchable submenu under the existing Cmd+Shift+A action picker. Add no keybind.
- Make the new theme the default at startup; apply choices immediately for the current session.

## Non-goals

- No automatic day/night switching or light theme in this change.
- No changes to typing, navigation, or editor layout.

## Approaches considered

1. **Action-picker submenu (selected):** Add a hidden `Choose color theme` action to the existing Telescope action picker, opening a compact theme list. This matches the request for a menu with no new shortcut and keeps the theme choice discoverable through the existing action search.
2. **Command only:** Add a `:Theme` command. This is smaller but less visible and less consistent with jvim's existing action menu.
3. **Automatic day/night theme:** Switch palettes by time or ambient conditions. It is more complex and may change appearance unexpectedly; it is outside the requested quick manual swap.

## Implementation outline

- Add the new theme as a maintained jvim Lua colorscheme rather than patching a third-party theme.
- Load the charcoal theme by default and expose `dark-ubuntu` as the fallback option.
- Build the submenu using the existing Telescope UI and use the same theme loader at startup and during switching.
- Reapply jvim-specific highlights after theme changes, including the cursor, scroll anchor, bracket match, word match, and fold controls.
- Verify contrast values for text and major UI states; launch a fresh editor to inspect plugin highlights and ensure the picker switches immediately.

## Design choices

The user approved the soft-charcoal direction and requested quick switching from a hidden menu, without a new keybind. The current theme remains available as the fallback. Exact hex colors are implementation choices; they will be chosen to meet the contrast and visibility goals above.
