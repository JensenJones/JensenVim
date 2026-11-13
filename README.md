# JensenVim (`jvim`)

By Jensen Jones.

A lightweight Neovim setup with ordinary typing, mouse selection, CLion-style Mac shortcuts, a single-click project tree, Markdown rendering and autosave. Based on kickstart.nvim; the original MIT license is preserved in LICENSE.

**Mac + WezTerm, including Herdr panes, is the primary setup; iTerm2 is also supported.** Linux and Windows run the same editor with Ctrl in place of Cmd: see [Linux](#linux-installation) and [Windows](#windows-installation). Run configurations and conflict resolution use Neovim's terminal and diff engine. CLion's debugger and full refactoring engine are not reproduced.

## macOS installation

Install Python 3, Neovim 0.12 or newer, ripgrep, Git, Poppler, ImageMagick and WezTerm. Poppler renders PDF pages and ImageMagick displays them through the terminal graphics protocol. Development checks used Neovim 0.12.5. With Homebrew, for example:

```sh
brew install neovim ripgrep tree-sitter-cli python poppler imagemagick
brew install --cask wezterm
```

Tree-sitter parsers and some plugins need the Xcode Command Line Tools (`xcode-select --install`). C++ projects need a working compiler/toolchain; language tooling installs through Mason on first launch. CLion itself is not required. The bundled shortcuts are a snapshot of the customized CLion macOS keymap used to build JensenVim.

With Homebrew and the Xcode Command Line Tools installed, paste this block into any
macOS terminal running Bash or Zsh. It installs the required tools, downloads jvim,
installs it, adds the launcher to your shell PATH, and opens the current folder:

```sh
PROJECT_DIR="$PWD"
brew install neovim ripgrep tree-sitter-cli python poppler imagemagick &&
brew install --cask wezterm &&
git clone https://github.com/JensenJones/JensenVim.git "$HOME/JensenVim" &&
"$HOME/JensenVim/install-macos.sh" --apply &&
if [ -n "${ZSH_VERSION:-}" ]; then PROFILE="$HOME/.zprofile"; else PROFILE="$HOME/.bash_profile"; fi
touch "$PROFILE" &&
{ grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$PROFILE" || printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE"; } &&
export PATH="$HOME/.local/bin:$PATH" &&
jvim "$PROJECT_DIR"
```

### Terminal setup

jvim's WezTerm settings live in this checkout ([`integrations/wezterm/`](integrations/wezterm)) and every installer sets them up the same way, so a new Mac, Linux or Windows machine gets the same terminal in one step. If you have no WezTerm config yet, the installer creates `~/.wezterm.lua`, which loads jvim's settings and leaves room for your own at the end (font, colours, background). If you already have one, the installer leaves it alone: copy [`integrations/wezterm/starter.lua`](integrations/wezterm/starter.lua) over it and move your settings to its end.

The settings give jvim its shortcuts and make shells and prompts outside jvim (zsh, bash, Claude Code, Codex) edit like a Mac text field:

| | macOS | Linux and Windows |
|---|---|---|
| Paste | Cmd+V | Ctrl+V (or Ctrl+Shift+V) |
| Copy selected text | Cmd+C | Ctrl+C (interrupts when nothing is selected) |
| Delete to start of line (line in jvim) | Cmd+Backspace | Alt+Backspace |
| Delete word | Option+Backspace | Ctrl+Backspace |

Every jvim shortcut follows the same rule: on Linux and Windows press Ctrl wherever the Mac uses Cmd, and Alt for Option. Backspace is the exception: as in Windows and Linux text fields, Ctrl+Backspace deletes a word and Alt+Backspace the line. Super stays with the desktop, because GNOME and Windows already use Super+V, Super+A, Super+L and Super+arrows. A few Cmd shortcuts whose Ctrl form jvim already uses keep the Ctrl meaning; for example Ctrl+Left and Ctrl+Right move to the previous and next file, so use Home and End for line start and end. The settings update with the checkout and WezTerm reloads them automatically.

To open a file later, run `jvim path/to/file.cpp` from any terminal in which the shell PATH is loaded. Herdr panes inside WezTerm get the same keys, since WezTerm checks which pane is running jvim.

To use iTerm2 instead, install it (`brew install --cask iterm2`), enable **iTerm2 Settings → General → Magic → Enable Python API** and permit the launcher when iTerm requests automation/API access.

The first editor launch downloads plugins and language tools, including Git reads/writes for plugin installation. The installer does not invoke Git itself. Python dependencies are pinned; Neovim plugins are pinned in `config/lazy-lock.json`. Mason's language server versions are not pinned.

The configuration is linked from this checkout to `~/.config/jvim` and runs with `NVIM_APPNAME=jvim`, so editing `config/` takes effect on the next launch without reinstalling. Keep the checkout where it is; moving it breaks the link until you reinstall. It leaves `~/.config/nvim` in place. The Mac integration manages `~/.local/bin/jvim*`, selected integration files under `~/.local/share/jvim` and iTerm's `DynamicProfiles/jvim.json`. Updates stage files before replacement and restore the old installation if publication fails. Existing managed files move into a timestamped backup under `~/.local/state/jvim/backups`; plugin, parser and Mason caches stay in place. Python runtimes use versioned directories for rollback. Inspect the preview before applying. Custom XDG directory overrides are not supported by these installers.

With iTerm2, keyboard mappings apply while the editor pane is focused and restore afterward. The launcher does not create tabs or windows. Code hyperlinks default off to keep the editor free of dashed link underlines. Use **Ctrl-click** or **Cmd+B** for definitions. The bridge enables Ctrl-click reporting while jvim is focused and restores the prior behavior afterward. In the action menu, **Toggle Cmd-click code links (dashed underlines)** opts into native Cmd-click and its link decoration, only for jvim. The installer does not change iTerm's global underline preference.

In another terminal, the editor can start but the Mac shortcut transport and native Cmd-click are not provided. Use WezTerm or iTerm2 for the full workflow.

## Linux installation

On Debian or Ubuntu, first install the system packages and WezTerm (this asks for your password once):

```sh
sudo apt-get update && sudo apt-get install -y build-essential curl git gpg ripgrep wl-clipboard xclip poppler-utils imagemagick &&
curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg &&
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list &&
sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg &&
sudo apt-get update && sudo apt-get install -y wezterm
```

Then paste this line, which needs no password:

```sh
curl -fsSL https://raw.githubusercontent.com/JensenJones/JensenVim/main/bootstrap-linux.sh | sh
```

Last, hand jvim the desktop shortcuts that clash with it. On a stock Ubuntu desktop those are Alt+F7 (jvim: Find usages; GNOME: move window) and Ctrl+Alt+Left/Right (jvim: Navigate back/forward; GNOME: switch workspace). The installer lists any it finds. This needs no password, removes only the clashing key from each desktop shortcut (Super+Page Up still switches workspaces) and prints what it changed; undo one with `gsettings reset <schema> <key>`:

```sh
~/JensenVim/integrations/linux/desktop-keys.py --apply
```

Setting up with Claude Code or another coding agent? Ask it to "set up and check jvim on this machine"; [AGENTS.md](AGENTS.md) tells it to install, run the test suite and fix what fails. Otherwise, before your first session, check:

- `wl-copy --version` (Wayland) or `xclip -version` (X11) works, or copy and paste will not reach other apps. The first command above installs both.
- `~/JensenVim/integrations/linux/desktop-keys.py` says "No desktop shortcuts clash with jvim."
- You open **WezTerm**, not the desktop's default terminal, and run `jvim .` there. Other terminals keep many shortcuts for themselves.

It installs Neovim and tree-sitter into `~/.local` from their official releases (distribution packages are usually too old), clones the repository into `~/JensenVim` and runs `install-linux.sh --apply`. If system packages are missing it stops and prints the command for your distribution (apt, dnf or pacman). Rerun the same line to update; set `JVIM_DIR` to clone somewhere else. For WezTerm outside Debian, Ubuntu and Arch, see [wezterm.org](https://wezterm.org/install/linux.html). Neovim needs `wl-clipboard` (Wayland) or `xclip` (X11) to share the clipboard with other apps, and fresh Ubuntu ships neither.

The installer links `config/` to `~/.config/jvim`, adds a `jvim` launcher in `~/.local/bin`, puts that folder on PATH in your shell's startup file and sets up WezTerm as described in [Terminal setup](#terminal-setup). It first moves any previous installation into `~/.local/state/jvim/backups`. Open WezTerm and run `jvim .`; shortcuts use Ctrl where the Mac uses Cmd (Ctrl+S, Ctrl+W, Ctrl+Shift+A). In another terminal jvim still runs, but shortcuts that terminal reserves or cannot encode will not arrive. The iTerm bridge is macOS only; Herdr panes inside WezTerm get the same keys.

## Windows installation

Paste this one line into PowerShell (Windows 10/11 with winget):

```powershell
irm https://raw.githubusercontent.com/JensenJones/JensenVim/main/bootstrap-windows.ps1 | iex
```

Then open a project with `jvim .` (open a new terminal first if `jvim` is not found yet). The script installs whatever is missing of Git, Neovim, ripgrep, tree-sitter-cli and Neovide with winget, clones the repository into `$HOME\JensenVim`, installs jvim and adds the `jvim` command to your user PATH. If winget cannot install Neovide without administrator approval, the script uses Neovide's official portable build instead. It does not change PowerShell's execution policy, so it also works where scripts must be signed. Rerun the same line to update.

Optional settings, set in the same PowerShell window before running it: `$env:JVIM_FRONTEND = 'nvim'` runs jvim inside your terminal instead of Neovide, and `$env:JVIM_DIR = 'D:\src\jvim'` clones somewhere else.

Tree-sitter builds syntax parsers with a C compiler. An existing Visual Studio installation with the C++ workload is found automatically; otherwise the script prints the command to install **Visual Studio Build Tools**. C++ compiler checks need Python 3 (the `py` launcher is used, because the Microsoft Store `python` alias is only a placeholder).

For terminal mode, install WezTerm with `winget install wez.wezterm`; the installer sets it up as described in [Terminal setup](#terminal-setup). The WezTerm setup on Windows has been checked by tests on macOS and Linux only.

To install from an existing checkout instead, run `install-windows.ps1 -Apply -AddToPath` (add `-Frontend nvim` for terminal mode). jvim installs separately at `%LOCALAPPDATA%\jvim`, backs up existing managed files, and keeps plugins in `%LOCALAPPDATA%\jvim-data`. Personal settings go in `%LOCALAPPDATA%\jvim-user\init.lua`.

On Windows, Cmd-based editor mappings become Ctrl-based mappings: Ctrl+B for definition, F4 for the tree, Ctrl+W to close, Ctrl+A to select all, and Ctrl+Alt+arrows for history. Windows reads Ctrl+Alt as AltGr, so Ctrl+Alt+; often never reaches jvim; Ctrl+` opens the terminal instead. Ctrl-click is mapped inside Neovim. PDF and image previews are off on Windows because image.nvim does not support it. Installation, first-launch plugin, parser and language-server setup, health checks, run configurations and the test suite have been verified on Windows 11. Keyboard and mouse delivery inside Neovide has been checked through Neovim's mapping API only, and OS-reserved keys may need remapping. Windows Terminal integration and Herdr on Windows are not included.

## Everyday editing

| Shortcut on Mac | Action |
| --- | --- |
| Cmd+S | Save all; choose a filename for an unnamed buffer |
| Cmd+W | Close file; exit after the last file |
| Cmd+Shift+W | Save the workspace (splits, tabs, positions) and exit, asking about unsaved buffers |
| F4 (Fn+F4 if needed) | Toggle the project tree from any editor mode |
| Cmd+N | Add a file beside the selected tree file or inside the selected folder |
| Cmd+Shift+A | Search actions and shortcuts |
| Ctrl+Shift+G | Git changes: changed-file tree with side-by-side diffs |
| Cmd+Shift+T | Reopen the last closed file, recreating its split if needed |
| Cmd+Option+\\ | Move the current file to a new jvim window (WezTerm), for example to put it on another monitor |
| Cmd+Option+R | Run the selected configuration in its own window instead of the output pane (WezTerm) |
| Cmd+B / Ctrl-click | Go to definition (Cmd-click is optional) |
| Cmd+Option+Left / Right | Navigate back / forward |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+Shift+O | Find a file |
| Cmd+Shift+F | Search the project; a space also matches a line break, so `bob is` finds "bob" at a line end followed by "is" |

Accept a function completion with **Tab** or **Enter** to select its first argument. Type to replace it, use **Tab** for the next argument and **Shift+Tab** for the previous one. The final Tab leaves the cursor after the closing parenthesis. Escape, clicking outside the call or switching files ends argument navigation.

Named writable files autosave after an 800 ms typing pause, on file switches, on focus loss and on exit. New unnamed files require Cmd+S to choose a name. Read-only files are not automatically written. Write failures are reported and leave the buffer modified. Autosave does not run formatting or import sorting, so undo stays undone. Explicit saves and the Format file action can format.

For C/C++, Save and Format file alphabetise includes into library and project groups, separated by a blank line, with another blank line before the code. Quoted headers are treated as project headers; angle-bracket headers also join that group when they resolve beside the file or under the project root, `include/` or `src/`. Other formatting follows the project's `.clang-format` settings.

If Neovim finds a stale swap file, jvim saves a backup and recovers its edits automatically. A file still open in a live editor keeps Neovim's normal protection.

Markdown renders while typing; search **Toggle Markdown preview** in the action menu to view/edit raw source. Markdown and README files wrap long lines at word boundaries to fit the pane; code files remain unwrapped. Click once to open a tree file or expand a folder. Press **F4** (or **Fn+F4** if needed) to toggle the project tree from any editor mode. PDFs open as rendered pages; use `]` and `[` to turn pages and `q` to close the viewer. See [the full keymap](docs/KEYBOARD.md).

Ctrl+Tab toggles to the most recently used open file; Ctrl+Shift+Tab walks through older files in recent-use order. Cmd+Option+minus/equal collapse and expand code folds.

C++ definition navigation/diagnostics require clangd and correct project compile flags. Supply a `compile_commands.json` (for CMake: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) or a suitable `compile_flags.txt`.

After a C/C++ Rename, jvim also checks the project with its compiler using `compile_commands.json`. Compiler errors appear at their source locations, including template errors in headers that clangd can miss. Checks run asynchronously in syntax-only mode and repeat after saved edits in that project; they do not build or run the program. You can start a check yourself with **Cmd+Shift+A → Check C++ project (syntax only)**. This needs Python 3, a Clang/GCC-style compiler command, and a compilation database covering all source files, including tests. Keep the database current when adding files or changing compiler flags.

Clangd can omit dependent template references from Rename. These are not changed by guessing from matching text; the compiler check reports broken references that are instantiated by your project. Uninstantiated template code can still need manual review. See [clangd's documented rename limits](https://clangd.llvm.org/features#rename).

## Configuration and project workflows

Keep your own settings in `~/.config/jvim-user/init.lua`, outside the managed installation. Choose **Edit personal jvim configuration** in the action picker. Profiles, company language-server overrides and `JVIM_OFFLINE=1` are documented in [Configuration and company integrations](docs/CONFIGURATION.md). The public `require('jvim').setup()` API can add jvim editing to an existing company Neovim configuration without taking over its plugin manager or servers.

Click **Config** in the status line to create a run configuration: give it a name and one or more shell commands, one per line. **Run** runs them in order in a terminal split, stopping at the first failure; commands run only when requested. Terminal output survives hiding the pane with Cmd+W. The action picker exposes rerun, stop and output actions.

**Resolve merge conflicts** opens native diff previews and an editable result, with clickable Ours/Theirs/Both/Base controls and undo. See [Project workflows](docs/WORKFLOWS.md) for run configuration examples, merge controls and moving files in the tree.

Use **Check jvim health** in the picker, or `:checkhealth jvim`, to inspect configuration, dependency policies and tools.

## Repository contents and updating

`config/` is the editor; `install-linux.sh` and `install-windows.ps1` install it on Linux and Windows, and `bootstrap-linux.sh` and `bootstrap-windows.ps1` are the one-line setups; `bin/` contains the Mac launchers; `integrations/macos/` contains the shortcut preset, AppleScript sources and Python requirements. No compiled Mac app, plugin cache, Python environment, editing history, credentials, sockets or project source is bundled. The installer builds the app and runtime on the destination computer.

After updating the repository, rerun the installer. It backs up the previous managed installation. To roll back, close jvim and restore the desired files from the reported backup directory. The installer does not alter iTerm's global underline preference.

There is no published Homebrew formula yet; Homebrew installs prerequisites and the supplied installer installs jvim.

## Local validation

```sh
python3 scripts/check.py
```

The tests use temporary installation homes and mocked external registration/runtime commands. Navigation and terminal startup integration tests use existing Neo-tree, Plenary, Nui and Mini installations when available, with Git features disabled; otherwise those tests skip. Tests do not launch the desktop UI, install plugins, access Git or change your installed editor. The checker validates Python/Lua syntax and reports every optional skip. CI runs isolated Linux/macOS checks and Windows packaging checks; fresh runners lack optional plugin caches, so plugin-dependent tests skip there. Local terminal input tests exercise the cached plugins. Windows desktop behavior is not verified. See [Validation](docs/VALIDATION.md).
