#!/bin/bash
# Usage: ./verify.sh [json_file] [provided_hash]
INPUT_DATA=$(cat "$1" | jq -c 'del(.block_hash)')
CALCULATED_HASH=$(echo -n "$INPUT_DATA" | sha256sum | awk '{print $1}')

if [ "$CALCULATED_HASH" == "$2" ]; then
    echo "SUCCESS: Integrity Verified."
else
    echo "CRITICAL: Mismatch detected. Do not commit."
fi
