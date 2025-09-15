#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

#----- helpers
have() { command -v "$1" >/dev/null 2>&1; }
link() {
  src="$1"; dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then rm -rf "$dst"; fi
  ln -s "$src" "$dst"
}


link "$REPO_DIR/bashrc" "$HOME/.bashrc"


brew_install_bundle() {
  brew update
  brew bundle --file="$REPO_DIR/Brewfile"
}

linuxbrew_bootstrap() {
  if ! have brew; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
  fi
}

ensure_node_npm() {
  if have corepack; then corepack enable || true; fi
  if ! have node || ! have npm; then
    if have brew; then brew install node
    elif have apt; then sudo apt update && sudo apt install -y nodejs npm
    elif have dnf; then sudo dnf install -y nodejs npm
    elif have yum; then sudo yum install -y nodejs npm
    else echo "Install Node.js + npm manually"; fi
  fi
  # Make sure global npm installs don't require sudo
  if [ -z "${NPM_CONFIG_PREFIX:-}" ]; then
    mkdir -p "$HOME/.npm-global"
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    if ! grep -q 'NPM_CONFIG_PREFIX' "$HOME/.bashrc" 2>/dev/null; then
      {
        echo 'export NPM_CONFIG_PREFIX="$HOME/.npm-global"'
        echo 'export PATH="$HOME/.npm-global/bin:$PATH"'
      } >> "$HOME/.bashrc"
    fi
  fi
}

install_npm_lsps() {
  ensure_node_npm
  # All the language servers you asked for (npm-based)
  npm -g install \
    bash-language-server \
    vscode-langservers-extracted \
    yaml-language-server \
    dockerfile-language-server-nodejs \
    markdown-language-server \
    @microsoft/compose-language-service || true
}

install_go_tools() {
  if ! have go; then
    if have brew; then brew install go
    elif have apt; then sudo apt install -y golang
    elif have dnf; then sudo dnf install -y golang
    elif have yum; then sudo yum install -y golang
    else echo "Install Go manually"; fi
  fi
  # gopls (Go LSP)
  GOBIN="${GOBIN:-$HOME/go/bin}"
  export GOBIN PATH="$GOBIN:$PATH"
  go install golang.org/x/tools/gopls@latest || true
}

install_python_helpers() {
  # You didn't request a Python LSP; keep this minimal (jq/shellcheck already elsewhere)
  if have pipx; then :; else
    if have brew; then brew install pipx
    elif have apt; then sudo apt install -y pipx || sudo apt install -y python3-pip && python3 -m pip install --user pipx
    fi
  fi
}

#----- OS packages
if [ "$OS" = "Darwin" ]; then
  have brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew_install_bundle
elif [ "$OS" = "Linux" ]; then
  if have apt; then
    sudo apt update
    if [ -f "$REPO_DIR/apt-packages.txt" ]; then xargs -a "$REPO_DIR/apt-packages.txt" sudo apt install -y; fi
    linuxbrew_bootstrap
    brew_install_bundle || true
  elif have dnf; then
    sudo dnf -y update
    if [ -f "$REPO_DIR/rpm-packages.txt" ]; then xargs -a "$REPO_DIR/rpm-packages.txt" sudo dnf install -y; fi
    linuxbrew_bootstrap
    brew_install_bundle || true
  elif have yum; then
    sudo yum -y update
    if [ -f "$REPO_DIR/rpm-packages.txt" ]; then xargs -a "$REPO_DIR/rpm-packages.txt" sudo yum install -y; fi
    linuxbrew_bootstrap
    brew_install_bundle || true
  else
    echo "Unsupported Linux package manager. Install base tools manually." >&2
  fi
else
  echo "Unsupported OS: $OS" >&2; exit 1
fi

#----- Fonts: JetBrains Mono Nerd
FONT_DIR="$HOME/Library/Fonts"; [ "$OS" != "Darwin" ] && FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ -d "$REPO_DIR/fonts/JetBrainsMonoNF" ]; then
  cp -f "$REPO_DIR/fonts/JetBrainsMonoNF/"*.ttf "$FONT_DIR"/
else
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/jbm.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -o "$tmp/jbm.zip" -d "$tmp/jbm"
  cp -f "$tmp/jbm/"*.ttf "$FONT_DIR"/
fi
[ "$OS" != "Darwin" ] && fc-cache -fv >/dev/null || true

#----- Shell defaults
if ! grep -q "dev-setup bootstrap" "$HOME/.bashrc" 2>/dev/null; then
cat >> "$HOME/.bashrc" <<'EOF'
# dev-setup bootstrap
export PATH="$HOME/.local/bin:$PATH"
[ -f ~/.bash_aliases ] && . ~/.bash_aliases
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
EOF
fi

cat > "$HOME/.bash_aliases" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'
EOF

cat > "$HOME/.ripgreprc" <<'EOF'
--hidden
--glob=!node_modules
--glob=!.git
--smart-case
EOF

#----- Emacs config
link "$REPO_DIR/emacs/.emacs.d" "$HOME/.emacs.d"

#----- tmux setup (no Emacs conflicts, mouse, vi keys, big history)
cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
setw -g mode-keys vi
set -g default-terminal "screen-256color"
set -g history-limit 200000
set -s escape-time 10

# Keep default prefix C-b to avoid Emacs conflicts
# Pane movement (hjkl)
bind -r h select-pane -L
bind -r j select-pane -D
bind -r k select-pane -U
bind -r l select-pane -R
# Resize with HJKL (shifted)
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Copy to system clipboard via OSC52 if available
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy || xclip -sel clip || wl-copy || cat >/dev/null"

# Statusline minimal
set -g status-interval 5
set -g status-left "#[bold]#S"
set -g status-right "%Y-%m-%d %H:%M"
EOF

#----- Language servers
install_go_tools
install_npm_lsps
install_python_helpers

echo "✅ Prep complete.
• Open a new shell (so PATH picks up npm global).
• Launch Emacs; LSPs should auto-hook in supported modes.
• Tip: run 'gopls version' and 'bash-language-server --version' to verify."
