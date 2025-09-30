#!/usr/bin/env bash
set -euo pipefail

# Where you keep your global dev setup repo
SETUP_DIR="${SETUP_DIR:-$HOME/dev-setup}"

# Cursor user config location
CURSOR_USER_DIR="$HOME/.config/Cursor/User"

echo "→ Setting up global Cursor configs from $SETUP_DIR"

# Safety: remove if User exists but is not a directory
if [ -e "$CURSOR_USER_DIR" ] && [ ! -d "$CURSOR_USER_DIR" ]; then
  echo "  Removing non-directory $CURSOR_USER_DIR"
  rm -f "$CURSOR_USER_DIR"
fi

# Ensure directory exists
mkdir -p "$CURSOR_USER_DIR"

# Symlink tracked configs
for f in settings.json keybindings.json snippets.code-snippets; do
  if [ -f "$SETUP_DIR/cursor/$f" ]; then
    ln -sf "$SETUP_DIR/cursor/$f" "$CURSOR_USER_DIR/$f"
    echo "  Linked $f"
  else
    echo "  Skipped $f (not found in $SETUP_DIR/cursor)"
  fi
done

echo "✅ Global Cursor config setup complete."
