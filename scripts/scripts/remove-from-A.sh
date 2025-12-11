#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <A-dir> <B-dir> [--dryrun]"
    exit 1
fi

A=$(cd "$1" && pwd)
B=$(cd "$2" && pwd)
DRYRUN="${3:-}"

echo "A: $A"
echo "B: $B"
echo "Dry run: ${DRYRUN:-no}"
echo

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# jdupes output uses blank lines to separate groups
jdupes -r -1 -Q "$A" "$B" > "$TMP"

# State machine in pure shell
group=()
foundA=0
foundB=0

flush_group() {
    if [ $foundA -eq 1 ] && [ $foundB -eq 1 ]; then
        for f in "${group[@]}"; do
            case "$f" in
                "$A"/*)
                    if [ "$DRYRUN" = "--dryrun" ]; then
                        echo "[DRYRUN] Would delete: $f"
                    else
                        echo "Deleting: $f"
                        rm -f -- "$f"
                    fi
                    ;;
            esac
        done
    fi

    group=()
    foundA=0
    foundB=0
}

while IFS= read -r line; do
    if [ -z "$line" ]; then
        flush_group
        continue
    fi

    group+=("$line")

    case "$line" in
        "$A"/*) foundA=1 ;;
        "$B"/*) foundB=1 ;;
    esac

done < "$TMP"

# flush last group if file didn't end with newline
flush_group
