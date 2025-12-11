#!/usr/bin/env bash
# ai-diff.sh — produce minimal diff for AI chat (using git diff --no-index)
set -euo pipefail

# Context name, e.g. "sst"
if [[ ! -f "$HOME/.ai-context" ]]; then
  echo "Missing ~/.ai-context. Run ai-sync.sh from the repo root first."
  exit 1
fi

CONTEXT="$(cat "$HOME/.ai-context")"
SRC="${1:-$PWD}"                        # live workspace
DST_BASE="${2:-$HOME/ai/${CONTEXT}-ai}" # AI mirror root
DST="${DST_BASE}/${CONTEXT}"            # AI mirror workspace
MAX_KB="${MAX_KB:-100}"                 # limit size for chat
DIFF_FILE="$(mktemp /tmp/ai-diff.XXXXXX)"

echo "--> Generating AI diff (max ${MAX_KB} KB)..."

# Git diff (no index): compare arbitrary dirs, include only relevant files
git diff --no-index --unified=0 --no-prefix --color=never \
  "$DST" "$SRC" -- \
  '*.go' '*.sh' '*.yaml' '*.yml' '*.docker' '*.cue' '*.json' \
  '*.toml' '*.md' 'Makefile' '*.make' >"$DIFF_FILE" || true

# Enforce output size limit
DIFF_SIZE=$(du -k "$DIFF_FILE" | awk '{print $1}')
if (( DIFF_SIZE > MAX_KB )); then
  echo "Diff size ${DIFF_SIZE} KB exceeds ${MAX_KB} KB limit."
  echo "Showing first ${MAX_KB} KB..."
  head -c "$((MAX_KB * 1024))" "$DIFF_FILE"
  echo
  echo "[... truncated at ${MAX_KB} KB ...]"
else
  cat "$DIFF_FILE"
fi

rm -f "$DIFF_FILE"

