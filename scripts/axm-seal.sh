#!/bin/bash
# axm-seal.sh — AXM Contracting LLC document sealing
set -euo pipefail

# --- configuration -------------------------------------------------------
SIGNING_IP="100.118.135.73"
SIGNING_PORT="9999"

# HTTP is used intentionally. Traffic is carried over the Tailscale mesh, which
# provides WireGuard-encrypted transport at the network layer. TLS would be
# redundant and adds certificate management overhead with no security gain here.

# --- arguments -----------------------------------------------------------
DOC_TYPE="${1:-}"
FILE="${2:-}"

if [[ -z "$DOC_TYPE" || -z "$FILE" ]]; then
    echo "Usage: $0 <amd|bid|formation> <file>" >&2
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    echo "ERROR: file not found: $FILE" >&2
    exit 1
fi

# --- target directory (absolute paths) -----------------------------------
case "$DOC_TYPE" in
    amd)       TARGET_DIR="$HOME/axm-drive/03_PROTOCOL_LIBRARY"    ;;
    bid)       TARGET_DIR="$HOME/axm-drive/07_ACTIVE_PROJECTS"     ;;
    formation) TARGET_DIR="$HOME/axm-drive/06_FORMATION_DOCUMENTS" ;;
    *)
        echo "ERROR: unknown doc type '$DOC_TYPE'. Use amd, bid, or formation." >&2
        exit 1
        ;;
esac

mkdir -p "$TARGET_DIR"

# --- node check ----------------------------------------------------------
# Step 1: ping — catches NODE_DARK (Tailscale peer offline or route black-holed)
if ! ping -c 1 -W 2 "$SIGNING_IP" >/dev/null 2>&1; then
    echo "ERROR: NODE_DARK — $SIGNING_IP unreachable" >&2
    exit 2
fi

# Step 2: HTTP health check — catches SERVICE_DARK (node up, service not responding)
if ! curl -s --connect-timeout 2 "http://$SIGNING_IP:$SIGNING_PORT/health" >/dev/null 2>&1; then
    echo "ERROR: NODE_DARK|OFFLINE — signing service not responding (SERVICE_DARK)" >&2
    exit 2
fi

# --- seal ----------------------------------------------------------------
CHAIN_HEAD=$(sha256sum "$FILE" | awk '{print $1}')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
SAFE_NAME=$(basename "$FILE" | tr -cs 'a-zA-Z0-9._-' '_')
OUT_FILE="$TARGET_DIR/${SAFE_NAME}.${TIMESTAMP}.seal.json"

RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"chain_head\": \"$CHAIN_HEAD\"}" \
    "http://$SIGNING_IP:$SIGNING_PORT/sign")

if [[ -z "$RESPONSE" ]]; then
    echo "ERROR: empty response from signing service" >&2
    exit 3
fi

echo "$RESPONSE" > "$OUT_FILE"
echo "Sealed: $OUT_FILE"
