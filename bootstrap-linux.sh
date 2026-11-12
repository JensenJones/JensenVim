#!/bin/sh
# One-line jvim setup for Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/JensenJones/JensenVim/main/bootstrap-linux.sh | sh
#
# Installs Neovim and tree-sitter into ~/.local from their official releases (no root needed),
# clones (or fast-forwards) the repository into ~/JensenVim and installs jvim and its WezTerm
# settings. System packages need root, so when any are missing it prints the one command to run.
# Rerun it any time to update. Set JVIM_DIR to clone somewhere other than ~/JensenVim.
set -eu
REPO=${JVIM_REPO:-https://github.com/JensenJones/JensenVim.git}
CHECKOUT=${JVIM_DIR:-$HOME/JensenVim}
BIN="$HOME/.local/bin"
OPT="$HOME/.local/opt"
export PATH="$BIN:$PATH"

case "$(uname -m)" in
  x86_64 | amd64) NVIM_ARCH=x86_64 TS_ARCH=x64 ;;
  aarch64 | arm64) NVIM_ARCH=arm64 TS_ARCH=arm64 ;;
  *) echo "Unsupported processor: $(uname -m)" >&2; exit 1 ;;
esac

system_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    cat <<'EOF'
sudo apt-get update && sudo apt-get install -y build-essential curl git gpg ripgrep wl-clipboard xclip poppler-utils imagemagick &&
curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg &&
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list &&
sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg &&
sudo apt-get update && sudo apt-get install -y wezterm
EOF
  elif command -v dnf >/dev/null 2>&1; then
    echo 'sudo dnf install -y gcc make curl git ripgrep wl-clipboard xclip poppler-utils ImageMagick'
    echo '# WezTerm: https://wezterm.org/install/linux.html'
  elif command -v pacman >/dev/null 2>&1; then
    echo 'sudo pacman -S --needed base-devel curl git ripgrep wl-clipboard xclip poppler imagemagick wezterm'
  else
    echo '# Install: a C compiler, curl, git, ripgrep, wl-clipboard or xclip, poppler, ImageMagick and WezTerm.'
  fi
}

echo 'jvim setup for Linux'
missing=''
for tool in git curl cc rg; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "Missing:$missing. Run this (it asks for your password), then rerun the setup line:" >&2
  echo >&2
  system_packages >&2
  exit 1
fi

optional=''
command -v wezterm >/dev/null 2>&1 || optional="$optional wezterm"
command -v wl-copy >/dev/null 2>&1 || command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1 || optional="$optional clipboard"
command -v pdftoppm >/dev/null 2>&1 || optional="$optional poppler"

mkdir -p "$BIN" "$OPT"
if nvim --headless -u NONE -i NONE -c 'if has("nvim-0.12") | qall! | else | cquit! | endif' >/dev/null 2>&1; then
  echo "  ok  nvim"
else
  echo "  installing Neovim into $OPT"
  rm -rf "$OPT/nvim-linux-$NVIM_ARCH"
  curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/nvim-linux-$NVIM_ARCH.tar.gz" | tar xz -C "$OPT"
  ln -sfn "$OPT/nvim-linux-$NVIM_ARCH/bin/nvim" "$BIN/nvim"
fi
if command -v tree-sitter >/dev/null 2>&1; then
  echo "  ok  tree-sitter"
else
  echo "  installing tree-sitter into $BIN"
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$TS_ARCH.gz" | gunzip > "$BIN/tree-sitter"
  chmod +x "$BIN/tree-sitter"
fi

if [ -d "$CHECKOUT/.git" ]; then
  echo "  updating $CHECKOUT"
  git -C "$CHECKOUT" pull -q --ff-only
else
  echo "  cloning into $CHECKOUT"
  git clone -q "$REPO" "$CHECKOUT"
fi
"$CHECKOUT/install-linux.sh" --apply

if [ -n "$optional" ]; then
  echo
  echo "Optional pieces are missing:$optional. For the full setup, run this (it asks for your password):"
  echo
  system_packages
fi
echo
echo 'Open WezTerm and run: jvim .'
