#!/bin/bash
# axm-seal-purge.sh — purge old AXM seal artifacts
set -euo pipefail

# Prevent concurrent cron runs
exec 9>/tmp/axm-seal-purge.lock
flock -n 9 || exit 0

# --- configuration -------------------------------------------------------
RETAIN_DAYS="${RETAIN_DAYS:-30}"

PURGE_DIRS=(
    "$HOME/axm-drive/03_PROTOCOL_LIBRARY"
    "$HOME/axm-drive/07_ACTIVE_PROJECTS"
    "$HOME/axm-drive/06_FORMATION_DOCUMENTS"
)

# --- OS-compatible cutoff date -------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
    CUTOFF=$(date -v-"${RETAIN_DAYS}"d +%s)
else
    CUTOFF=$(date -d "-${RETAIN_DAYS} days" +%s)
fi

# --- purge ---------------------------------------------------------------
PURGED=0

for DIR in "${PURGE_DIRS[@]}"; do
    [[ -d "$DIR" ]] || continue
    while IFS= read -r -d '' SEAL_FILE; do
        FILE_MTIME=$(stat -c '%Y' "$SEAL_FILE" 2>/dev/null \
            || stat -f '%m' "$SEAL_FILE" 2>/dev/null)
        if [[ "$FILE_MTIME" -lt "$CUTOFF" ]]; then
            rm -f "$SEAL_FILE"
            echo "Purged: $SEAL_FILE"
            (( PURGED++ )) || true
        fi
    done < <(find "$DIR" -maxdepth 1 -name '*.seal.json' -print0)
done

echo "axm-seal-purge: removed $PURGED artifact(s) older than ${RETAIN_DAYS} days"
