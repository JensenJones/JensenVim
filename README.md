# JensenVim (`jvim`)

By Jensen Jones.

A lightweight Neovim setup with ordinary typing, mouse selection, CLion-style Mac shortcuts, a single-click project tree, Markdown rendering and autosave. Based on kickstart.nvim; the original MIT license is preserved in LICENSE.

**Mac + iTerm2, including existing Herdr panes, is the primary setup. Windows + Neovide support is experimental and has not been tested on a Windows machine.** This does not reproduce CLion's debugger, build system or full refactoring engine.

## macOS installation

Install Python 3, Neovim 0.12 or newer, ripgrep, Git and iTerm2. Development checks used Neovim 0.12.5. With Homebrew, for example:

```sh
brew install neovim ripgrep python
brew install --cask iterm2
```

Tree-sitter parsers and some plugins need the Xcode Command Line Tools (`xcode-select --install`). C++ projects need a working compiler/toolchain; language tooling installs through Mason on first launch. CLion itself is not required. The bundled shortcuts are a snapshot of the customized CLion macOS keymap used to build JensenVim.

Download/extract this repository, then run:

```sh
./install-macos.sh          # preview destinations; no changes
./install-macos.sh --apply  # install and back up previous jvim-managed files
```

Add `~/.local/bin` to your PATH. Enable **iTerm2 Settings → General → Magic → Enable Python API** and permit the launcher when iTerm requests automation/API access. Then run:

```sh
jvim .
jvim path/to/file.cpp
```

The first editor launch downloads plugins and language tools, including Git reads/writes for plugin installation. The installer does not invoke Git itself. Python dependencies are pinned; Neovim plugins are pinned in `config/lazy-lock.json`. Mason's language server versions are not pinned.

The configuration installs separately at `~/.config/jvim` using `NVIM_APPNAME=jvim`. It leaves `~/.config/nvim` in place. The Mac integration manages `~/.local/bin/jvim*`, `~/.local/share/jvim` and iTerm's `DynamicProfiles/jvim.json`. Existing managed destinations move into a timestamped backup under `~/.local/state/jvim/backups`. Inspect the preview before applying. Custom XDG directory overrides are not supported by these installers.

Within iTerm/Herdr, keyboard mappings apply while the editor pane is focused and restore afterward. The launcher does not create tabs or windows. Code hyperlinks default off to keep the editor free of dashed link underlines. Use **Ctrl-click** or **Cmd+B** for definitions. The bridge enables Ctrl-click reporting while jvim is focused and restores the prior behavior afterward. In the action menu, **Toggle Cmd-click code links (dashed underlines)** opts into native Cmd-click and its link decoration, only for jvim. The installer does not change iTerm's global underline preference.

In another terminal, the editor can start but the Mac shortcut transport and native Cmd-click are not provided. Use the primary setup for the full workflow.

## Everyday editing

| Shortcut on Mac | Action |
| --- | --- |
| Cmd+S | Save all; choose a filename for an unnamed buffer |
| Cmd+W | Close file; exit after the last file |
| Cmd+Shift+W | Exit, asking about unsaved buffers |
| Cmd+1 | Open/focus the project tree; hide it when already focused |
| Cmd+Shift+A | Search actions and shortcuts |
| Cmd+B / Ctrl-click | Go to definition (Cmd-click is optional) |
| Cmd+Option+Left / Right | Navigate back / forward |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+Shift+O | Find a file |
| Cmd+Shift+F | Search the project |

Named writable files autosave after an 800 ms typing pause, on file switches, on focus loss and on exit. New unnamed files require Cmd+S to choose a name. Read-only files are not automatically written. Write failures are reported and leave the buffer modified. Autosave does not run formatting or import sorting, so undo stays undone. Explicit saves and the Format file action can format.

Markdown renders while typing; search **Toggle Markdown preview** in the action menu to view/edit raw source. Click once to open a tree file or expand a folder. After closing the tree with `q`, Cmd+1 brings it back without leaving ordinary typing. See [the full keymap](docs/KEYBOARD.md).

C++ definition navigation/diagnostics require clangd and correct project compile flags. Supply a `compile_commands.json` (for CMake: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) or a suitable `compile_flags.txt`.

## Windows (experimental)

Install Neovim 0.12+, Neovide, ripgrep and Git, plus a compiler suitable for Tree-sitter and your projects. Neovide is a lightweight Neovim GUI; iTerm2 is not required. Run the following from PowerShell in this extracted repository:

```powershell
./install-windows.ps1         # preview
./install-windows.ps1 -Apply  # install
```

Add `%LOCALAPPDATA%\JensenVim\bin` to PATH, then run `jvim.ps1 .`. This installs separately at `%LOCALAPPDATA%\jvim`, backing up existing managed files. PowerShell's execution policy must permit local scripts.

On Windows, Cmd-based editor mappings become Ctrl-based mappings: Ctrl+B for definition, Ctrl+1 for the tree, Ctrl+W to close, and Ctrl+Alt+arrows for history. Ctrl-click is mapped inside Neovim. These mappings have been checked through Neovim's mapping API, but real Windows keyboard delivery, mouse delivery, dependency installation and the PowerShell installer need Windows testing. OS-reserved keys may need remapping. Windows Terminal integration and Herdr on Windows are not included.

## Repository contents and updating

`config/` is the editor; `bin/` contains the Mac launchers; `integrations/macos/` contains the shortcut preset, AppleScript sources and Python requirements. No compiled Mac app, plugin cache, Python environment, editing history, credentials, sockets or project source is bundled. The installer builds the app and runtime on the destination computer.

After updating the repository, rerun the installer. It backs up the previous managed installation. To roll back, close jvim and restore the desired files from the reported backup directory. The installer does not alter iTerm's global underline preference.

To connect this prepared directory to GitHub, inspect the destination repository before choosing whether to clone/merge into existing history or initialize an empty repository. Do not force-push over existing work.

## Local validation

```sh
python3 -m unittest discover -s tests -v
```

The tests use temporary installation homes and mocked external registration/runtime commands. They do not launch the desktop UI, install plugins, access Git or change your installed editor. Mac desktop behavior was exercised during development; Windows desktop behavior is not verified.
