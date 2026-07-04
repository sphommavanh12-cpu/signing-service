#!/bin/bash
# axm-seal-package.sh

set -e

python3 -c "import reportlab" 2>/dev/null || { echo "Error: reportlab not installed. Run: pip install reportlab" >&2; exit 1; }

if [ "$#" -ne 2 ]; then
    echo "Usage: axm-seal-package.sh <INPUT_PDF_PATH> <PROJECT_REF>" >&2
    exit 1
fi

INPUT_FILE="$1"
PROJECT_REF="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist." >&2
    exit 1
fi

BASENAME=$(basename "$INPUT_FILE")
EXTENSION="${BASENAME##*.}"
FILENAME_NO_EXT="${BASENAME%.*}"

if [ "$EXTENSION" != "pdf" ] && [ "$EXTENSION" != "PDF" ]; then
    echo "Error: Input file must be a PDF document." >&2
    exit 1
fi

if [[ ! "$BASENAME" =~ _v[0-9]+ ]]; then
    echo "Error: Input filename must contain a version marker (e.g., '_v1')." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRANSMITTAL_DIR="$HOME/axm-transmittals"
mkdir -p "$TRANSMITTAL_DIR"

TRANSMITTAL_PAGE="${TRANSMITTAL_DIR}/${FILENAME_NO_EXT}_transmittal.pdf"

trap 'if [ $? -ne 0 ]; then rm -f "$TRANSMITTAL_PAGE"; fi' EXIT

if ! "$SCRIPT_DIR/axm-seal-offline.sh" "$INPUT_FILE"; then
    echo "Error: axm-seal-offline.sh failed." >&2
    exit 1
fi

if ! EXTRACT_DATA=$("$SCRIPT_DIR/axm-seal-extract.sh"); then
    echo "Error: axm-seal-extract.sh failed." >&2
    exit 1
fi

SEAL_TIMESTAMP=$(echo "$EXTRACT_DATA" | grep 'SEAL_TIMESTAMP' | cut -d'"' -f2)
SEAL_HASH=$(echo "$EXTRACT_DATA" | grep 'SEAL_HASH' | cut -d'"' -f2)
SEAL_FILENAME=$(echo "$EXTRACT_DATA" | grep 'SEAL_FILENAME' | cut -d'"' -f2)

if [ "$SEAL_FILENAME" != "$BASENAME" ]; then
    echo "Error: Ledger filename '$SEAL_FILENAME' does not match input file '$BASENAME'." >&2
    exit 1
fi

if ! "$SCRIPT_DIR/axm-stamp-block.py" "$SEAL_HASH" "$SEAL_TIMESTAMP" "$SEAL_FILENAME" "$PROJECT_REF" "$TRANSMITTAL_PAGE"; then
    echo "Error: axm-stamp-block.py failed." >&2
    exit 1
fi

if [ ! -s "$TRANSMITTAL_PAGE" ]; then
    echo "Error: Transmittal PDF missing or empty." >&2
    exit 1
fi

echo "Success: Transmittal saved to: $TRANSMITTAL_PAGE"
echo "Outgoing document unchanged: $INPUT_FILE"
