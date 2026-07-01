#!/bin/bash
set -e
# Usage: ./verify.sh <json_file> <expected_sha256_hash>

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "ERROR: Missing arguments. Usage: ./verify.sh <json_file> <expected_sha256_hash>" >&2
    exit 2
fi

if [ ! -f "$1" ]; then
    echo "ERROR: File not found: $1" >&2
    exit 2
fi

INPUT_DATA=$(jq -c 'del(.block_hash)' "$1")
CALCULATED_HASH=$(echo -n "$INPUT_DATA" | sha256sum | awk '{print $1}')

if [ "$CALCULATED_HASH" = "$2" ]; then
    echo "SUCCESS: Integrity Verified."
    exit 0
else
    echo "CRITICAL: Mismatch detected. Do not commit."
    exit 1
fi
