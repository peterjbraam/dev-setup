#!/usr/bin/env bash
# We keep -u for undefined variables, but we will handle errors manually
set -u 
set -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
REMOTE="braam.io"
RECONCILE_DIR="reconcile-shared-with-me"

# Files from Spec
LOCAL_DIRS="local-dirs.txt"
RESTART_FILE="diff-restart.txt"
RESTORE_SCRIPT="restore-files.sh"
DIFFERENT_FILES="different-files.sh"
SHARED_MAP="shared-drive.txt"

touch "$RESTART_FILE" "$RESTORE_SCRIPT" "$DIFFERENT_FILES"
LAST_DIR=$(cat "$RESTART_FILE" 2>/dev/null || echo "")
TAB=$'\t'

escape_path() { printf '%s' "$1" | sed 's/"/\\"/g'; }

# Read loop with fallback for missing trailing newline
while IFS="$TAB" read -r TAG DIR_PATH || [[ -n "$DIR_PATH" ]]; do
    # Restart Logic
    if [[ -n "$LAST_DIR" && "$LAST_DIR" != "DONE" ]]; then
        [[ "$DIR_PATH" == "$LAST_DIR" ]] && LAST_DIR=""
        continue
    fi

    echo "Processing: [$TAG] $DIR_PATH"

    # Define Remote Target
    R_CMD=(rclone lsjson --max-depth 1)
    case "$TAG" in
        MD)  R_ROOT="$REMOTE:$DIR_PATH" ;;
        SD)
            DRIVE_NAME="${DIR_PATH%%/*}"
            SUB_PATH="${DIR_PATH#*/}"
            [[ "$SUB_PATH" == "$DIR_PATH" ]] && SUB_PATH=""
            DRIVE_ID=$(grep "^$DRIVE_NAME$TAB" "$SHARED_MAP" | cut -f2 || true)
            R_ROOT="$REMOTE:$SUB_PATH"
            R_CMD+=("--drive-team-drive" "$DRIVE_ID")
            ;;
        SWM) R_ROOT="$REMOTE:$DIR_PATH" ;;
    esac

    # Metadata Snapshot
    REMOTE_DATA=$(mktemp)
    if ! "${R_CMD[@]}" "$R_ROOT" 2>/dev/null > "$REMOTE_DATA"; then
        echo "[]" > "$REMOTE_DATA"
    fi

    # Identify Local Path
    LOCAL_BASE="Google Drive"
    [[ "$TAG" == "SD" ]] && LOCAL_BASE="Google Drive - Shared drives"
    [[ "$TAG" == "SWM" ]] && LOCAL_BASE="Google Drive - Shared with me"
    FULL_LOCAL="$LOCAL_BASE/$DIR_PATH"

    if [[ -d "$FULL_LOCAL" ]]; then
        # Use find to feed the loop
        while IFS= read -r -d '' FILE; do
            FNAME=$(basename "$FILE")
            
            # Trap: Ignore .DS_Store variants
            [[ "$FNAME" == *".DS_Store"* ]] && continue

            # Trap: Handle stat failure gracefully (e.g. permission issues)
            FSIZE=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null || echo "0")
            
            # Metadata matching
            REMOTE_ENTRY=$(grep -F "\"Path\":\"$FNAME\"" "$REMOTE_DATA" || true)

            if [[ -z "$REMOTE_ENTRY" ]]; then
                # File missing -> Add to restore script
                ESC_LOCAL=$(escape_path "$FILE")
                if [[ "$TAG" == "SWM" ]]; then
                    TARGET="$REMOTE:$RECONCILE_DIR/$DIR_PATH/$FNAME"
                else
                    TARGET="$R_ROOT/$FNAME"
                fi
                echo "rclone copyto --no-clobber \"$ESC_LOCAL\" \"$TARGET\"" >> "$RESTORE_SCRIPT"
            else
                # File exists -> Check for differences
                # Trap: Ignore size differences on Office files (xls, doc, ppt, etc)
                if [[ ! "$FNAME" =~ \.(xls|xlsx|doc|docx|ppt|pptx)$ ]]; then
                    RSIZE=$(echo "$REMOTE_ENTRY" | sed -E 's/.*"Size":([-0-9]+).*/\1/')
                    if [[ "$RSIZE" != "-1" && "$FSIZE" != "$RSIZE" ]]; then
                        echo "# Size mismatch: Local $FSIZE vs Remote $RSIZE" >> "$DIFFERENT_FILES"
                        echo "$FILE" >> "$DIFFERENT_FILES"
                    fi
                fi
            fi
        done < <(find "$FULL_LOCAL" -maxdepth 1 -type f -print0 2>/dev/null)
    fi

    rm -f "$REMOTE_DATA"
    # Update restart point
    echo "$DIR_PATH" > "$RESTART_FILE"

done < "$LOCAL_DIRS"

# Finalization
if [[ -s "$RESTORE_SCRIPT" ]]; then
    sort -u -o "$RESTORE_SCRIPT" "$RESTORE_SCRIPT"
fi
echo "DONE" > "$RESTART_FILE"
