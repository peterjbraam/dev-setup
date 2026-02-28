#!/bin/bash

# Enforce exactly 2 arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <target_directory_prefix> <list_file>"
    echo "Example: $0 '/absolute/path/to/A/' raw_duplicates.txt"
    exit 1
fi

TARGET_PREFIX="$1"
LIST_FILE="$2"

# Ensure the list file actually exists
if [ ! -f "$LIST_FILE" ]; then
    echo "Error: File '$LIST_FILE' not found."
    exit 1
fi

# The surgical strike pipeline
# Note: Added -f to rm so it doesn't throw an error if grep finds 0 matches
grep "^${TARGET_PREFIX}" "${LIST_FILE}" | tr '\n' '\0' | xargs -0 rm -f

echo "Done. Removed duplicates residing in: $TARGET_PREFIX"
