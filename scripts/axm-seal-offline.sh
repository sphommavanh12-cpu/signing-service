#!/bin/bash
set -euo pipefail

# --- input validation ----------------------------------------------------
if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <file>" >&2
    exit 1
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
    echo "ERROR: file not found: $FILE" >&2
    exit 1
fi

# --- compute -------------------------------------------------------------
HASH=$(sha256sum "$FILE" | awk '{print $1}')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OPERATOR="${USER:-$(id -un)}"
FILENAME=$(basename "$FILE")
LEDGER="$HOME/axm-ledger.log"

# --- ledger (append-only) ------------------------------------------------
printf '%s|%s|%s|%s\n' "$TIMESTAMP" "$FILENAME" "$HASH" "$OPERATOR" >> "$LEDGER"

# --- confirmation --------------------------------------------------------
echo "SEALED"
echo "  File:      $FILE"
echo "  SHA-256:   $HASH"
echo "  Timestamp: $TIMESTAMP"
echo "  Operator:  $OPERATOR"
echo "  Ledger:    $LEDGER"
