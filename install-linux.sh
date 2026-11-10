#!/bin/sh
# Install the jvim configuration and launcher for Linux. Preview by default; --apply changes files.
set -eu
SOURCE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
CONFIG="$CONFIG_HOME/jvim"
BIN="$HOME/.local/bin"
NVIM=${JVIM_NVIM:-nvim}

case "$(basename "${SHELL:-sh}")" in
  zsh) PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bashrc" ;;
  *) PROFILE="$HOME/.profile" ;;
esac
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

echo "Configuration: $CONFIG"
echo "Launcher: $BIN/jvim"
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

BACKUP="$STATE_HOME/jvim/backups/$(date +%Y%m%d-%H%M%S)-$$"
for target in "$CONFIG" "$BIN/jvim"; do
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP"
    mv "$target" "$BACKUP/$(basename "$target")"
  fi
done

mkdir -p "$CONFIG_HOME" "$BIN"
cp -R "$SOURCE/config" "$CONFIG"
find "$CONFIG" \( -name '__pycache__' -o -name '*.pyc' -o -name '.DS_Store' \) -prune -exec rm -rf {} +
cat > "$BIN/jvim" <<EOF
#!/bin/sh
NVIM_APPNAME=jvim exec "\${JVIM_NVIM:-$NVIM}" "\$@"
EOF
chmod +x "$BIN/jvim"

touch "$PROFILE"
grep -qxF "$PATH_LINE" "$PROFILE" || printf '%s\n' "$PATH_LINE" >> "$PROFILE"

[ -d "$BACKUP" ] && echo "Previous files saved to: $BACKUP"
echo "Installed. Open a new terminal (or run: $PATH_LINE), then run: jvim ."
echo "The first launch downloads plugins and language tools."
