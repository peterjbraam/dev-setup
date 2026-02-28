#!/usr/bin/env bash
set -euo pipefail

# Root of the repo (assumes script is run from repo root)
ROOT="$(pwd)"

# Output file
OUT="site-text-dump.txt"

# Image / binary extensions to exclude
EXCLUDE_EXT_REGEX='\.((png|jpg|jpeg|gif|webp|svg|ico|pdf))$'

# Clear output
: > "$OUT"

echo "### SITE TEXT DUMP" >> "$OUT"
echo "### Generated: $(date -u)" >> "$OUT"
echo "### Root: $ROOT" >> "$OUT"
echo >> "$OUT"

# List tracked files (authoritative)
git ls-files | while read -r file; do
  # Skip images / binaries
  if [[ "$file" =~ $EXCLUDE_EXT_REGEX ]]; then
    continue
  fi

  echo "================================================================" >> "$OUT"
  echo "FILE: $file" >> "$OUT"
  echo "================================================================" >> "$OUT"
  echo >> "$OUT"

  # Guard: only dump regular text files
  if file "$file" | grep -q text; then
    sed 's/\t/    /g' "$file" >> "$OUT"
  else
    echo "[NON-TEXT FILE SKIPPED]" >> "$OUT"
  fi

  echo >> "$OUT"
done

echo "### END OF DUMP" >> "$OUT"

echo "Wrote $OUT"
