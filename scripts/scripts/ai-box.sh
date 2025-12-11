#!/usr/bin/env bash
set -euo pipefail

NOW=`date`
TMPPROMPT=$(mktemp /tmp/ai-prompt.XXXXXX)
mv $TMPPROMPT $TMPPROMPT.md
TMPPROMPT="$TMPPROMPT".md
echo $TMPPROMPT


cat <<'INTRO' >> "$TMPPROMPT"
# Peter's AI Prompt Composer, v1
INTRO
echo "$NOW  Prompt:"  >> "$TMPPROMPT"

# 1. Open editable text box (blocks until closed)
open -W -e "$TMPPROMPT"

# 2. Run diff collector
bash ~/scripts/ai-diff.sh > /tmp/_aidiff.txt

# 3. Combine prompt + diff
{
  tail -n +2 "$TMPPROMPT"   # skip intro
  echo
  echo "### DIFF"
  echo
  cat /tmp/_aidiff.txt
} | pbcopy

# 4. Clean up
rm -f "$TMPPROMPT" /tmp/_aidiff.txt

echo "✅ Prompt + diff copied to clipboard. Paste into ChatGPT/Gemini."
