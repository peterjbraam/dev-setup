#!/usr/bin/env bash
# Appends clipboard text (copied AI response) to current chat log

set -euo pipefail
AI_DIR="$HOME/ai"
CTX_FILE="$HOME/.ai-context"

if [[ ! -f "$CTX_FILE" ]]; then
  echo "❌ No .ai-context file found; run ai-sync.sh first."
  exit 1
fi

WORKSPACE=$(cat "$CTX_FILE")
CHAT_LOG="$AI_DIR/${WORKSPACE}-ai/chats/current-chat.txt"

if [[ ! -f "$CHAT_LOG" ]]; then
  echo "❌ Chat log not found: $CHAT_LOG"
  exit 1
fi

TS=$(date '+%Y-%m-%d %H:%M:%S')
echo -e "\n\n### AI RESPONSE ($TS)\n" >>"$CHAT_LOG"

if pbpaste >/dev/null 2>&1; then
  pbpaste >>"$CHAT_LOG"
elif xclip -o >/dev/null 2>&1; then
  xclip -o >>"$CHAT_LOG"
elif wl-paste >/dev/null 2>&1; then
  wl-paste >>"$CHAT_LOG"
else
  echo "Clipboard not accessible." >&2
  exit 1
fi

echo "✅ Appended AI response to $CHAT_LOG"
