#!/usr/bin/env bash
# File: ai-sync.sh
# Purpose: Efficiently sync the active repo to ~/ai/<repo>-ai/<repo>
# without large artifacts or binaries, respecting .gitignore rules.

set -euo pipefail

if [[ ! -d .git ]]; then
    echo "Run this from a repo root for consistency."
    exit 1
fi

CONTEXT=$(basename "$PWD")

# --- Configuration ---
SRC_REPO="$PWD"
DST_REPO="$HOME/ai/${CONTEXT}-ai"
DST_WORKSPACE="$DST_REPO/$CONTEXT"
MAX_SIZE="${MAX_SIZE:-100k}"
GITIGNORE_FILE="$SRC_REPO/.gitignore"
NOW=$(date '+%Y-%m-%d_%H-%M-%S')

# --- Ensure destination structure ---
mkdir -p "$DST_WORKSPACE" "$DST_REPO/chats"

# --- Perform sync ---
echo "--> Syncing workspace to AI repo..."
rsync -av --delete \
  --exclude-from="$GITIGNORE_FILE" \
  --exclude=".git/" \
  --max-size="$MAX_SIZE" \
  --human-readable \
  ./ "$DST_WORKSPACE/"

# copy the .gitignore so it travels
cp "$SRC_REPO/.gitignore" "$DST_WORKSPACE/.gitignore"

# --- Commit snapshot in AI repo ---
cd "$DST_REPO"
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
  echo "--> Changes detected, committing snapshot..."
  CHAT_FILE="chats/chat-${NOW}.txt"
  touch "$CHAT_FILE"
  ln -sf "$(basename "$CHAT_FILE")" chats/current-chat.txt
  git add -A
  git commit -m "AI sync: $NOW"
else
  echo "--> No changes to commit."
fi

# --- Run summariser if available ---
if command -v sst >/dev/null 2>&1; then
  echo "--> Running sst summarise..."
  sst summarise || echo "⚠️ sst summarise failed (non-fatal)"
else
  echo "(sst not found — skipping summarise)"
fi

# --- Update global AI context ---
echo "$CONTEXT" > ~/.ai-context

echo "✅ AI sync complete: $SRC_REPO → $DST_REPO"
