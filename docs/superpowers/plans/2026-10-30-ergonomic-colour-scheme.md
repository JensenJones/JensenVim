# Ergonomic Colour Scheme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a soft-charcoal default jvim theme with a hidden, immediate switcher for the existing `dark-ubuntu` theme.

**Architecture:** Implement one project-owned Neovim colorscheme and a small `custom.theme` module that validates theme names and opens a Telescope submenu. Make startup and manual switching use the same application function, and define jvim-specific focus highlights after each switch.

**Tech Stack:** Neovim 0.12 Lua runtime, Telescope, Python `unittest` integration tests.

**Spec:** `docs/superpowers/specs/2026-10-30-ergonomic-colour-scheme-design.md`

## Global Constraints

- Keep the existing `dark-ubuntu` scheme as a manual fallback.
- Add no keybind for switching themes.
- Use a charcoal background and warm foreground without pure black or glaring white.
- Check normal text and key UI pairs against a 4.5:1 contrast floor.
- Keep cursor, selection, matching brackets, diagnostics, current-word highlight, file tree, completion menu, and statusline visually distinct.
- Distinguish syntax roles by hue and lightness; do not rely on red/green differences alone.

## Review Focus

- Theme changes while a completion menu or Telescope picker is open must keep readable foreground/background pairs; pin with `test_theme_groups_remain_legible_with_picker_groups` in Task 1.
- A selection and the cursor remain distinguishable on the same line; pin with the selected `Visual` and cursor group contrast assertions in Task 1.
- Reloading or switching repeatedly must not accumulate highlight overrides; pin by switching both themes twice and checking final groups in Task 1.
- The hidden menu must not add a mapped key or make ordinary action search execute a theme accidentally; pin with action-picker entry and mapping assertions in Task 2.
- Missing or invalid colorscheme names must not leave the editor partially changed; pin with invalid-name behavior in Task 1.

---

### Task 1: Add the charcoal colorscheme and theme application module

**Files:**
- Create: `config/colors/jvim-charcoal.lua`
- Create: `config/lua/custom/theme.lua`
- Modify: `config/init.lua`
- Test: `tests/test_theme.py`

**Interfaces:**
- `require('custom.theme').apply(name: string) -> boolean, string?` accepts only `jvim-charcoal` and `dark-ubuntu`, loads the requested scheme, and reapplies jvim focus highlights.
- `require('custom.theme').names() -> { { name: string, label: string } }` returns the supported switcher entries in display order.

- [x] **Step 1: Write failing tests** named `test_default_theme_is_charcoal`, `test_apply_switches_between_supported_themes`, `test_invalid_theme_does_not_change_current_scheme`, `test_required_highlight_groups_are_defined`, `test_contrast_floor_for_text_selection_and_cursor`, and `test_theme_groups_remain_legible_with_picker_groups`.
- [x] **Step 2: Run the targeted theme tests** and confirm they fail because the theme module and colorscheme do not exist.
- [x] **Step 3: Implement the custom palette** in `config/colors/jvim-charcoal.lua`; define base editor, Tree-sitter, diagnostics, folds, cursor, selection, bracket/current-word, statusline, Neo-tree, Telescope, and Blink groups.
- [x] **Step 4: Implement `custom.theme`** with the whitelist, `names`, shared application path, and stable jvim-specific focus highlights after every `ColorScheme` event.
- [x] **Step 5: Make `jvim-charcoal` the startup scheme** in `config/init.lua` using the shared application function.
- [x] **Step 6: Run the targeted theme tests** and confirm the required groups and contrast checks pass.
- [x] **Step 7: Commit** the colorscheme, loader, startup change, and tests. Task 1 was committed as `821cc85`.

### Task 2: Add the hidden theme submenu to the action picker

**Files:**
- Modify: `config/lua/custom/action_picker.lua`
- Modify: `config/lua/custom/theme.lua`
- Test: `tests/test_theme.py`
- Test: `tests/test_terminal_startup.py`

**Interfaces:**
- Consumes `custom.theme.names()` and `custom.theme.apply(name)` from Task 1.
- `require('custom.theme').pick()` opens a compact Telescope picker for supported themes; selecting one applies it immediately and closes the picker.

- [x] **Step 1: Write failing tests** for the hidden action and no-keymap behavior; exercise action-to-theme-picker opening in a terminal.
- [x] **Step 2: Run the picker test** and confirm the entry/action behavior is missing.
- [x] **Step 3: Implement `custom.theme.pick()`** with a Telescope list of supported themes.
- [x] **Step 4: Add the `Choose color theme` action** to `custom.action_picker`; let entries support a callback as well as existing key dispatch, and invoke the callback after closing the picker.
- [x] **Step 5: Run the picker and theme tests** and confirm picker opening, supported theme switching, and absence of a new keybind.
- [x] **Step 6: Commit** the menu and its tests.

### Independent fix: Shift+Enter

- [x] In Insert mode, run Normal `o` as a one-shot command (`<C-o>o`) so the current line remains intact and a line opens below it.
- [x] Verify both the mapped behavior and iTerm's `ESC[23;5~69` terminal input; autoindent remains on the new line.

## Self-review

- Spec coverage: default theme, contrast, focus highlights, current theme fallback, hidden manual menu, and no new shortcut are assigned to Tasks 1–2.
- Shift+Enter is handled as an independent keymap fix and verified through actual terminal input.
