#!/usr/bin/env bash
set -u 

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
REMOTE="braam.io"

# ---------- dependency check ----------
for cmd in rclone awk grep sed find wc; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd not found"; exit 1; }
done

: > local-dirs.txt
: > missing-dirs.txt
: > shared-drive.txt

# ---------- shared drive mapping ----------
# Uses backend drives to get IDs for all Shared Drives
echo "Fetching Shared Drive mapping..."
rclone backend drives "$REMOTE:" | awk '
  /"id":/   { gsub(/.*"id": *"|".*/, "", $0); id=$0 }
  /"name":/ { gsub(/.*"name": *"|".*/, "", $0); name=$0 }
  id && name { print name "\t" id; id=""; name="" }
' > shared-drive.txt

# ---------- list local dirs (2 levels) ----------
# Scans local cache structure strictly
list_local() {
    local tag="$1" base="$2"
    [ -d "$base" ] || return 0
    for d in "$base"/*/; do
        [ -d "$d" ] || continue
        name="${d#$base/}"
        printf "%s\t%s\n" "$tag" "${name%/}"
        for sd in "$d"*/; do
            [ -d "$sd" ] || continue
            subname="${sd#$base/}"
            printf "%s\t%s\n" "$tag" "${subname%/}"
        done
    done
}

echo "Scanning local cache structure..."
{
    list_local "MD"  "Google Drive"
    list_local "SD"  "Google Drive - Shared drives"
    list_local "SWM" "Google Drive - Shared with me"
} | sort > local-dirs.txt

TOTAL_DIRS=$(wc -l < local-dirs.txt | xargs)
echo "Found $TOTAL_DIRS directories. Starting ID-based verification..."

# ---------- directory existence check ----------
tab=$'\t'
COUNT=0

while IFS="$tab" read -r TAG DIR_PATH || [[ -n "$DIR_PATH" ]]; do
    COUNT=$((COUNT + 1))
    printf "\r[%d/%d] Verifying %s: %-50s" "$COUNT" "$TOTAL_DIRS" "$TAG" "${DIR_PATH:0:50}"

    case "$TAG" in
        MD)
            # TRAP FIX: Instead of checking the path, we query the parent for the specific name.
            # This prevents the API from trying to calculate the contents of the target folder.
            parent="${DIR_PATH%/*}"
            name="${DIR_PATH##*/}"
            [[ "$parent" == "$name" ]] && parent="" # Root-level folder
            
            # Query only for the directory entry in the parent list
            if ! rclone lsf "$REMOTE:$parent" --max-depth 1 --include "/$name/" --no-traverse --contimeout 5s --timeout 10s 2>/dev/null | grep -q "$name"; then
                printf "\n[MISSING] %s\n" "$DIR_PATH"
                printf "%s\t%s\n" "$TAG" "$DIR_PATH" >> missing-dirs.txt
            fi
            ;;
        SD)
            drive_name="${DIR_PATH%%/*}"
            sub_path="${DIR_PATH#*/}"
            [[ "$sub_path" == "$DIR_PATH" ]] && sub_path=""
            
            drive_id=$(grep "^$drive_name$tab" shared-drive.txt | cut -f2 || true)

            if [[ -z "$drive_id" ]]; then
                printf "\n[UNKNOWN DRIVE] %s\n" "$drive_name"
                printf "%s\t%s\n" "$TAG" "$DIR_PATH" >> missing-dirs.txt
            else
                # For SDs, check if sub_path exists within that Drive ID
                # If sub_path is empty, we are checking the Drive root itself (already confirmed by mapping)
                if [[ -n "$sub_path" ]]; then
                    sd_parent="${sub_path%/*}"
                    sd_name="${sub_path##*/}"
                    [[ "$sd_parent" == "$sd_name" ]] && sd_parent=""
                    
                    if ! rclone lsf "$REMOTE:$sd_parent" --drive-team-drive "$drive_id" --max-depth 1 --include "/$sd_name/" --no-traverse --contimeout 5s --timeout 10s 2>/dev/null | grep -q "$sd_name"; then
                        printf "\n[MISSING SD] %s\n" "$DIR_PATH"
                        printf "%s\t%s\n" "$TAG" "$DIR_PATH" >> missing-dirs.txt
                    fi
                fi
            fi
            ;;
        SWM)
            # Informational only as per spec
            printf "%s\t%s\n" "$TAG" "$DIR_PATH" >> missing-dirs.txt
            ;;
    esac
done < local-dirs.txt

printf "\nDONE. Found $(wc -l < missing-dirs.txt 2>/dev/null || echo 0) directories requiring attention.\n"
