# Configuration and company integrations

jvim requires Neovim 0.12 or newer. The standalone launcher uses `NVIM_APPNAME=jvim`, leaving your regular Neovim configuration in place. Implementation modules live under `jvim.*` so a company's `custom.*` modules remain available.

## Personal settings

Keep personal settings outside the managed installation, in `~/.config/jvim-user/init.lua` on macOS/Linux or `%LOCALAPPDATA%/jvim-user/init.lua` on Windows. **Edit personal jvim configuration** in the action picker opens this file. Set `JVIM_CONFIG` to use another trusted Lua file.

```lua
return {
  ui = { theme = 'jvim-charcoal' },
  tools = { mason = false, install = false, path = 'skip' },
  lsp = {
    servers = {
      clangd = { cmd = { '/company/bin/clangd', '--background-index' } },
      lua_ls = false,
    },
  },
  profiles = {
    work = {
      offline = true,
      features = { compiler_checks = false },
      formatting = { on_save = false },
    },
  },
}
```

Use `JVIM_PROFILE=work jvim .` to select a profile. Precedence is defaults, personal settings, selected profile, then explicit `setup()` options. Dictionaries merge; lists replace. A server set to `false` disables jvim's default for that server. User settings are trusted executable Lua; project Lua is never loaded automatically.

Invalid personal settings produce an error and disable automatic installation for that session. Invalid explicit API options raise an error before editor setup. `:checkhealth jvim` reports the selected settings path/profile, errors, effective policies and resolved executables.

## Policies

| Option | Standalone default | Purpose |
| --- | --- | --- |
| `offline` | `false` | Disable plugin/tool/parser downloads and use Blink's Lua matcher |
| `plugins.enabled` | `true` | Let jvim configure its Lazy plugin set |
| `plugins.install` | `true` | Bootstrap/pin Lazy and install missing plugins |
| `plugins.specs` | `{}` | Additional Lazy plugin specifications |
| `tools.mason` | `true` | Configure Mason |
| `tools.install` | `true` | Install known language tools through Mason |
| `tools.path` | `'prepend'` | Mason PATH handling: `prepend`, `append` or `skip` |
| `lsp.default_servers` | `true` | Configure clangd and lua_ls |
| `lsp.servers` | `{}` | Native LSP options keyed by server name; `false` disables a default |
| `treesitter.auto_install` | `true` | Install configured and newly encountered parsers |
| `treesitter.parsers` | Bundled language list | Replace the baseline parser list |
| `formatting.on_save` | `true` | Format explicit saves; autosave does not format |
| `formatting.organise_includes` | `true` | Group/sort C/C++ includes and separate them from code |
| `formatting.formatters_by_ft`, `formatting.formatters` | `{}` | Override Conform's bundled settings |
| `completion.fuzzy` | `'prefer_rust'` | Blink matcher; use `'lua'` without a native download |
| `features` | All enabled | `project_tree`, `autosave`, `compiler_checks`, `pdf`, `folds`, `word_highlight` |
| `ui` | All enabled | `theme` (name or `false`), `icons`, `tabline`, `statusline` |
| `before_setup`, `after_setup` | Unset | Callbacks receiving a copy of effective options |

`JVIM_OFFLINE=1 jvim .` enforces offline policy even if settings say otherwise. Provision plugins, parsers and language servers beforehand for the complete interface. Without a cached plugin manager, core typing/navigation still starts and reports the missing interface. Offline policy governs jvim's automatic dependency installation; it does not prohibit explicitly chosen terminal commands, language-server processes or custom hooks/plugin specifications.

## Company overlay

Use jvim as a regular Neovim plugin, with the company's plugin manager. For example, a Lazy specification:

```lua
{
  'JensenJones/JensenVim',
  lazy = false,
  config = function()
    require('jvim').setup {
      mode = 'overlay',
      -- Existing company language servers and plugin manager remain in charge.
    }
  end,
}
```

Overlay is the default for the public API. It installs jvim's modeless editing and shortcuts, but defaults to no managed plugin downloads, Mason, default servers, parser installation, autosave, compiler checks, PDF/tree startup, theme or status/tabline replacement. It still intentionally changes editing mappings and selection/paste behaviour. Existing LSP clients remain usable; host plugins supply completion, formatting and tree UI when requested.

Configure explicit `lsp.servers` to let jvim enable selected native servers, or leave them empty to keep the host's setup. Enable other features deliberately. Shared personal settings also apply to overlays; use a dedicated `JVIM_CONFIG` or profile when home and company policies differ.

`require('jvim').setup(options)` is idempotent for a session. `require('jvim').get_config()` returns a copy of effective options. Restart Neovim after changing setup options. For standalone installations, the iTerm bridge rereads shortcut mappings each launch; an ordinary jvim restart is enough for source updates.
