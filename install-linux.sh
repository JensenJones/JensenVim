#!/bin/sh
# Install the jvim configuration and launcher for Linux. Preview by default; --apply changes files.
set -eu
SOURCE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
CONFIG="$CONFIG_HOME/jvim"
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/jvim"
NVIM=${JVIM_NVIM:-nvim}

case "$(basename "${SHELL:-sh}")" in
  zsh) PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bashrc" ;;
  *) PROFILE="$HOME/.profile" ;;
esac
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

echo "Configuration: $CONFIG"
echo "Launcher: $BIN/jvim"
echo "WezTerm settings: $SHARE/wezterm-config.lua"
echo "PATH entry: $PROFILE"
if [ "${1:-}" != "--apply" ]; then
  echo "Preview only. Run $0 --apply to install."
  exit 0
fi

if ! command -v "$NVIM" >/dev/null 2>&1; then
  echo "Neovim 0.12 or newer is required. Install it first; see README.md." >&2
  exit 1
fi
if ! "$NVIM" --headless -u NONE -i NONE -c 'if has("nvim-0.12") | qall! | else | cquit! | endif' >/dev/null 2>&1; then
  echo "$("$NVIM" --version | head -n 1) is too old; jvim needs Neovim 0.12 or newer. See README.md." >&2
  exit 1
fi
for tool in git rg; do
  command -v "$tool" >/dev/null 2>&1 || echo "Warning: $tool is not on PATH; some features will be unavailable." >&2
done
if ! command -v wl-copy >/dev/null 2>&1 && ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
  echo "Warning: no clipboard tool (wl-clipboard or xclip), so copy and paste cannot reach other apps. See README.md." >&2
fi

BACKUP="$STATE_HOME/jvim/backups/$(date +%Y%m%d-%H%M%S)-$$"
for entry in "$CONFIG:config" "$BIN/jvim:launcher"; do
  target=${entry%:*}
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -e "$target" ]; then
    mkdir -p "$BACKUP"
    mv "$target" "$BACKUP/${entry##*:}"
  fi
done

mkdir -p "$CONFIG_HOME" "$BIN"
ln -s "$SOURCE/config" "$CONFIG"
cat > "$BIN/jvim" <<EOF
#!/bin/sh
NVIM_APPNAME=jvim exec "\${JVIM_NVIM:-$NVIM}" "\$@"
EOF
chmod +x "$BIN/jvim"

mkdir -p "$SHARE"
ln -sfn "$SOURCE/integrations/wezterm/jvim.lua" "$SHARE/wezterm.lua"
ln -sfn "$SOURCE/integrations/wezterm/wezterm.lua" "$SHARE/wezterm-config.lua"
if [ -e "$HOME/.wezterm.lua" ] || [ -e "$CONFIG_HOME/wezterm/wezterm.lua" ]; then
  echo "WezTerm config left unchanged. To use jvim's terminal settings, see README.md."
else
  cp "$SOURCE/integrations/wezterm/starter.lua" "$HOME/.wezterm.lua"
  echo "Created ~/.wezterm.lua with jvim's terminal settings; add your own settings at its end."
fi
if command -v gsettings >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  python3 "$SOURCE/integrations/linux/desktop-keys.py" || echo "Warning: could not check desktop shortcuts." >&2
fi
command -v wezterm >/dev/null 2>&1 || echo "WezTerm is not installed. jvim runs in any terminal, but its shortcuts need WezTerm; see README.md." >&2

touch "$PROFILE"
grep -qxF "$PATH_LINE" "$PROFILE" || printf '%s\n' "$PATH_LINE" >> "$PROFILE"

[ -d "$BACKUP" ] && echo "Previous files saved to: $BACKUP"
echo "Installed. Open a new terminal (or run: $PATH_LINE), then run: jvim ."
echo "The first launch downloads plugins and language tools."
