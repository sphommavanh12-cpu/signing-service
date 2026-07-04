#!/bin/bash
# axm-seal-extract.sh

LEDGER_FILE="$HOME/axm-ledger.log"

if [ ! -r "$LEDGER_FILE" ] || [ ! -s "$LEDGER_FILE" ]; then
    echo "Error: Ledger file is missing, unreadable, or empty." >&2
    exit 1
fi

LAST_ENTRY=$(tail -n 1 "$LEDGER_FILE")

if [ -z "$LAST_ENTRY" ]; then
    echo "Error: Failed to read the last ledger entry." >&2
    exit 1
fi

SEAL_TIMESTAMP=$(echo "$LAST_ENTRY" | cut -d'|' -f1)
SEAL_FILENAME=$(echo "$LAST_ENTRY" | cut -d'|' -f2)
SEAL_HASH=$(echo "$LAST_ENTRY" | cut -d'|' -f3)
OPERATOR=$(echo "$LAST_ENTRY" | cut -d'|' -f4)

if [ -z "$SEAL_TIMESTAMP" ] || [ -z "$SEAL_FILENAME" ] || [ -z "$SEAL_HASH" ] || [ -z "$OPERATOR" ]; then
    echo "Error: Ledger entry format is invalid or corrupt." >&2
    exit 1
fi

export SEAL_TIMESTAMP
export SEAL_FILENAME
export SEAL_HASH
export OPERATOR

echo "SEAL_TIMESTAMP=\"$SEAL_TIMESTAMP\""
echo "SEAL_FILENAME=\"$SEAL_FILENAME\""
echo "SEAL_HASH=\"$SEAL_HASH\""
echo "OPERATOR=\"$OPERATOR\""
