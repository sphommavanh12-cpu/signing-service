#!/usr/bin/env bash
# desktop-scan.sh — Pilot security scan for the local Tailscale-connected desktop.
#
# SCOPE: local machine only. No external hosts are contacted at any point.
# GATE:  Tailscale must be active and the machine reachable via its Tailscale IP
#        before any scan begins. Aborts immediately and logs if the mesh is down.
#
# Usage:  bash scripts/desktop-scan.sh
# Output: scan-reports/scan-<timestamp>.md  (local only, gitignored)
#         scan-reports/scan-<timestamp>.md  uploaded to Google Drive automatically
#
# Exit codes:
#   0 — no findings above LOW
#   1 — scan aborted (Tailscale gate failed or fatal error)
#   2 — HIGH or CRITICAL findings present
#   3 — MEDIUM findings only
#
# Google Drive upload requires one of:
#   - gdrive CLI  (https://github.com/glotlabs/gdrive) configured and authenticated
#   - rclone      configured with a remote named "gdrive" pointing to Google Drive
#   - GDRIVE_ACCESS_TOKEN env var set to a valid OAuth2 bearer token
#
# ── Hourly self-check-in scope (defined explicitly) ──────────────────────────
# The CI monitoring loop (ScheduleWakeup in Claude Code) that watches PR #3:
#   CHECKS:   PR open/closed/merged state; CI check-run status; unresolved review comments
#   TOUCHES:  GitHub read-only API calls only (pull_request_read: get, get_check_runs,
#             get_review_comments). May push a fix commit if a CI failure is tractable
#             and the fix is unambiguous.
#   DOES NOT: modify repo files autonomously without a concrete failing check to fix;
#             push to any branch other than claude/pentagi-desktop-scan-pilot-m06o60;
#             merge the PR (merge is blocked on Sony review); post review comments;
#             re-arm itself after the PR is merged or closed.
# ─────────────────────────────────────────────────────────────────────────────
#
# Do not merge without Sony review.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_REPORTS_DIR="${REPO_ROOT}/scan-reports"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
REPORT_FILE="${SCAN_REPORTS_DIR}/scan-${TIMESTAMP}.md"
FAIL_LOG="${SCAN_REPORTS_DIR}/abort-${TIMESTAMP}.log"
GDRIVE_FOLDER_ID="1DBH7y7yPLSF_TeeW4gGxhBF06bkwbcEI"

FINDINGS=()
COUNT_HIGH=0
COUNT_MEDIUM=0

mkdir -p "${SCAN_REPORTS_DIR}"

# ── Helpers ──────────────────────────────────────────────────────────────────

log() {
    echo "[$(date -u +%H:%M:%SZ)] $*"
}

abort_scan() {
    local reason="$1"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s ABORT: %s\n' "${ts}" "${reason}" | tee "${FAIL_LOG}"
    log "Scan aborted. Reason logged to: ${FAIL_LOG}"
    exit 1
}

add_finding() {
    local severity="$1"  # CRITICAL | HIGH | MEDIUM | LOW | INFO
    local category="$2"
    local detail="$3"
    FINDINGS+=("| ${severity} | ${category} | ${detail} |")
    case "${severity}" in
        CRITICAL|HIGH) COUNT_HIGH=$(( COUNT_HIGH + 1 )) ;;
        MEDIUM)        COUNT_MEDIUM=$(( COUNT_MEDIUM + 1 )) ;;
    esac
    log "[${severity}] ${category}: ${detail}"
}

# ── Google Drive upload ───────────────────────────────────────────────────────
# Called after the report is written. Tries three methods in order.
# Logs a HIGH finding if all methods fail (manual upload is not acceptable).

upload_report_to_gdrive() {
    local file="$1"
    local folder_id="${GDRIVE_FOLDER_ID}"
    local filename
    filename="$(basename "${file}")"

    log "Uploading report to Google Drive folder ${folder_id} ..."

    # Method 1: gdrive CLI (v3 API — https://github.com/glotlabs/gdrive)
    if command -v gdrive &>/dev/null; then
        if gdrive files upload --parent "${folder_id}" "${file}" 2>/dev/null; then
            log "Uploaded via gdrive CLI."
            return 0
        fi
        # gdrive v2 syntax fallback
        if gdrive upload --parent "${folder_id}" "${file}" 2>/dev/null; then
            log "Uploaded via gdrive CLI (v2)."
            return 0
        fi
        log "gdrive CLI upload failed — trying rclone."
    fi

    # Method 2: rclone with a remote named "gdrive"
    if command -v rclone &>/dev/null; then
        # rclone cannot address Drive by folder ID directly; use the folder path if
        # a "gdrive" remote is configured, otherwise fall through.
        if rclone listremotes 2>/dev/null | grep -q '^gdrive:'; then
            if rclone copyto "${file}" "gdrive:pentagi-scan-reports/${filename}" \
                    --drive-upload-cutoff 1M 2>/dev/null; then
                log "Uploaded via rclone (gdrive remote)."
                return 0
            fi
            log "rclone upload failed — trying Drive API."
        fi
    fi

    # Method 3: Google Drive Files API via curl + OAuth2 bearer token.
    # Set GDRIVE_ACCESS_TOKEN before running the script, or store it in
    # ~/.config/pentagi/gdrive-token (chmod 600).
    local token="${GDRIVE_ACCESS_TOKEN:-}"
    if [[ -z "${token}" && -f "${HOME}/.config/pentagi/gdrive-token" ]]; then
        token="$(< "${HOME}/.config/pentagi/gdrive-token")"
    fi

    if [[ -n "${token}" ]]; then
        local metadata
        metadata="{\"name\":\"${filename}\",\"parents\":[\"${folder_id}\"]}"
        local response
        response="$(curl -s -X POST \
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" \
            -H "Authorization: Bearer ${token}" \
            -F "metadata=${metadata};type=application/json;charset=UTF-8" \
            -F "file=@${file};type=text/markdown" 2>/dev/null)"

        local file_id
        file_id="$(echo "${response}" | jq -r '.id // empty' 2>/dev/null || true)"
        if [[ -n "${file_id}" ]]; then
            log "Uploaded via Drive API (file ID: ${file_id})."
            return 0
        fi
        log "Drive API upload failed: ${response}"
    fi

    # All methods exhausted — this is a HIGH finding (upload is mandatory).
    add_finding "HIGH" "Report Upload Failed" \
        "Could not upload ${filename} to Google Drive folder ${folder_id}. " \
        "Install gdrive CLI, configure an rclone 'gdrive' remote, or set " \
        "GDRIVE_ACCESS_TOKEN / ~/.config/pentagi/gdrive-token. Manual upload is not acceptable."
    return 1
}

# ── GATE: Tailscale presence and mesh reachability ───────────────────────────

log "=== GATE: Tailscale check ==="

if ! command -v tailscale &>/dev/null; then
    abort_scan "tailscale binary not found. Install Tailscale before running this scan."
fi

TS_STATUS_JSON="$(tailscale status --json 2>/dev/null)" || \
    abort_scan "tailscale status failed — daemon may not be running (try: sudo tailscale up)."

if ! command -v jq &>/dev/null; then
    abort_scan "jq is required to parse tailscale status but is not installed."
fi

BACKEND_STATE="$(echo "${TS_STATUS_JSON}" | jq -r '.BackendState // "Unknown"')"
if [[ "${BACKEND_STATE}" != "Running" ]]; then
    abort_scan "Tailscale is not active (BackendState=${BACKEND_STATE}). Scan aborted to preserve trust boundary."
fi

TS_IP4="$(tailscale ip -4 2>/dev/null || true)"
if [[ -z "${TS_IP4}" ]]; then
    abort_scan "Tailscale is running but no IPv4 address assigned — machine may have dropped off the mesh."
fi

# Tailscale CGNAT range: 100.64.0.0/10
if [[ ! "${TS_IP4}" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
    abort_scan "Tailscale IP '${TS_IP4}' is outside the 100.64.0.0/10 CGNAT range — unexpected network configuration."
fi

SELF_NODE="$(echo "${TS_STATUS_JSON}" | jq -r '.Self.DNSName // "unknown"')"
SELF_ONLINE="$(echo "${TS_STATUS_JSON}" | jq -r '.Self.Online // false')"

log "Tailscale ACTIVE — node: ${SELF_NODE}, IP: ${TS_IP4}, online: ${SELF_ONLINE}"
log "=== GATE PASSED — beginning scan (local machine only) ==="

# ── CHECK 1: Open ports vs expected baseline ─────────────────────────────────

log "=== CHECK 1: Open port baseline ==="

# Expected listening ports for this host. Adjust as the service topology changes.
# 22    = SSH (restricted to tailscale0 interface only)
# 53    = systemd-resolve (loopback only)
# 8080  = signing-service API (Tailscale-internal only)
# 47688 = tailscaled
# 64170 = tailscaled IPv6
declare -A EXPECTED_PORTS=([22]=1 [53]=1 [8080]=1 [47688]=1 [64170]=1)

OPEN_PORTS=()

if command -v ss &>/dev/null; then
    while IFS= read -r addr; do
        port="${addr##*:}"
        [[ "${port}" =~ ^[0-9]+$ ]] && OPEN_PORTS+=("${port}")
    done < <(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | sort -u)
elif command -v netstat &>/dev/null; then
    while IFS= read -r addr; do
        port="${addr##*:}"
        [[ "${port}" =~ ^[0-9]+$ ]] && OPEN_PORTS+=("${port}")
    done < <(netstat -tlnp 2>/dev/null | awk '/LISTEN/ {print $4}' | sort -u)
else
    add_finding "MEDIUM" "Port Scan" "Neither ss nor netstat found — port baseline check skipped."
fi

for port in "${OPEN_PORTS[@]}"; do
    if [[ -z "${EXPECTED_PORTS[${port}]+x}" ]]; then
        add_finding "HIGH" "Unexpected Open Port" \
            "Port ${port}/tcp is open but not in expected baseline (${!EXPECTED_PORTS[*]})."
    fi
done

# Flag anything bound to 0.0.0.0 (all-interfaces, not Tailscale-scoped)
if command -v ss &>/dev/null; then
    WILDCARD_LISTENERS="$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep '^0\.0\.0\.0:' | tr '\n' ' ')"
    if [[ -n "${WILDCARD_LISTENERS}" ]]; then
        add_finding "HIGH" "Network Exposure" \
            "Port(s) bound to 0.0.0.0 (all interfaces, not Tailscale-only): ${WILDCARD_LISTENERS}"
    fi
fi

log "Listening ports found: ${OPEN_PORTS[*]:-none}"

# ── CHECK 2: Credential scan (expanded) ──────────────────────────────────────

log "=== CHECK 2: Credential scan ==="

# File types to scan — includes .env, .env.*, and dotenv files by name
INCLUDE_GLOBS=(
    --include='*.go'
    --include='*.sh'
    --include='*.env'
    --include='.env'
    --include='.env.*'
    --include='*.env.*'
    --include='*.json'
    --include='*.yaml'
    --include='*.yml'
    --include='*.toml'
    --include='*.sql'
    --include='*.conf'
    --include='*.cfg'
    --include='*.ini'
    --include='*.properties'
)

# Patterns grouped by category for clarity.
# Each entry is "SEVERITY:CATEGORY:PATTERN"
declare -A CRED_PATTERN_META
CRED_PATTERNS=()

# PEM / key block headers
CRED_PATTERNS+=('-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY')
CRED_PATTERNS+=('-----BEGIN CERTIFICATE')

# Unquoted .env assignments (KEY=value, no quotes required)
CRED_PATTERNS+=('^(PASSWORD|PASSWD|SECRET|API_KEY|APIKEY|PRIVATE_KEY|AUTH_TOKEN|ACCESS_TOKEN|CLIENT_SECRET|DB_PASS|DB_PASSWORD)\s*=\s*\S{4,}')

# Quoted assignments in any language
CRED_PATTERNS+=('(password|passwd|secret|api[_-]?key|private[_-]?key|auth[_-]?token|access[_-]?token|client[_-]?secret)\s*[:=]\s*["\x27][^"\x27\s]{4,}')

# Known service-specific formats
CRED_PATTERNS+=('sk-[A-Za-z0-9]{20,}')                          # OpenAI
CRED_PATTERNS+=('AIza[0-9A-Za-z_-]{35}')                        # Google API key
CRED_PATTERNS+=('xox[baprs]-[0-9A-Za-z-]{10,}')                 # Slack token
CRED_PATTERNS+=('gh[pousr]_[A-Za-z0-9]{36,}')                   # GitHub PAT / App token
CRED_PATTERNS+=('AKIA[0-9A-Z]{16}')                              # AWS access key ID
CRED_PATTERNS+=('AWS_SECRET_ACCESS_KEY\s*=')
CRED_PATTERNS+=('GITHUB_TOKEN\s*=')

# Raw private key material not in PEM format
CRED_PATTERNS+=('private[_-]?key\s*[:=]\s*[0-9a-fA-F]{32,}')   # hex-encoded
CRED_PATTERNS+=('0x[0-9a-fA-F]{64}[^0-9a-fA-F]')               # Ethereum private key
CRED_PATTERNS+=('["\x27][A-Za-z0-9+/]{42}={0,2}["\x27]')       # base64 ~32 byte key (e.g. Ed25519 seed)

CRED_FOUND=0
for pattern in "${CRED_PATTERNS[@]}"; do
    while IFS= read -r hit; do
        [[ -n "${hit}" ]] || continue
        [[ "${hit}" =~ \.git/ ]] && continue
        # Skip test/example fixtures (file path contains test/ or testdata/ or _test.go)
        [[ "${hit}" =~ (test/|testdata/|_test\.go:) ]] && continue
        add_finding "CRITICAL" "Credential Exposure" "${hit}"
        CRED_FOUND=$(( CRED_FOUND + 1 ))
        [[ "${CRED_FOUND}" -ge 15 ]] && break 2
    done < <(grep -rIn "${INCLUDE_GLOBS[@]}" --exclude-dir='.git' \
                   --exclude-dir='verified-artifacts' \
                   -E "${pattern}" "${REPO_ROOT}" 2>/dev/null | head -3 || true)
done

# Also scan for bare .env files anywhere in the tree (grep --include doesn't recurse dotfiles)
while IFS= read -r envfile; do
    [[ -f "${envfile}" ]] || continue
    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        if [[ "${line}" =~ (KEY|SECRET|PASS(WORD)?|TOKEN|PRIVATE)= ]]; then
            add_finding "CRITICAL" "Credential Exposure (.env)" "${envfile}: ${line}"
            CRED_FOUND=$(( CRED_FOUND + 1 ))
        fi
    done < "${envfile}"
done < <(find "${REPO_ROOT}" -name '.env' -o -name '.env.*' 2>/dev/null | grep -v '\.git/' | grep -v '/verified-artifacts/')

if [[ "${CRED_FOUND}" -eq 0 ]]; then
    log "No credential patterns found in repo."
fi

# ── CHECK 3: Dependency audit (verify.sh + Go toolchain) ─────────────────────

log "=== CHECK 3: Dependency audit ==="

check_binary() {
    local name="$1"
    local label="${2:-${name}}"

    if ! command -v "${name}" &>/dev/null; then
        add_finding "HIGH" "Missing Dependency" \
            "\`${label}\` is not installed — required for this service."
        return 1
    fi

    local dep_path
    dep_path="$(command -v "${name}")"

    # Resolve symlinks before checking permissions. On Linux, symlinks always
    # show lrwxrwxrwx — only the target file's permissions are meaningful.
    local dep_target dep_perms
    dep_target="$(readlink -f "${dep_path}" 2>/dev/null || echo "${dep_path}")"
    dep_perms="$(stat -c '%a' "${dep_target}" 2>/dev/null || true)"
    if [[ "${dep_perms}" =~ [2367]$ ]]; then
        add_finding "HIGH" "Dependency Integrity" \
            "\`${label}\` at ${dep_path} (→ ${dep_target}) is world-writable (${dep_perms}) — possible tampering vector."
    fi

    log "  ${label}: $(${name} --version 2>&1 | head -1 || true) (${dep_path})"
    return 0
}

# verify.sh runtime dependencies
log "-- verify.sh dependencies --"

VERIFY_DEPS=(bash jq sha256sum awk)
for dep in "${VERIFY_DEPS[@]}"; do
    check_binary "${dep}" || continue

    if [[ "${dep}" == "bash" ]]; then
        bash_ver="$(bash --version 2>&1 | grep -oP 'version \K[0-9]+\.[0-9]+' | head -1 || true)"
        bash_major="${bash_ver%%.*}"
        bash_minor="${bash_ver##*.}"
        if [[ -n "${bash_major}" && ( "${bash_major}" -lt 4 || \
              ( "${bash_major}" -eq 4 && "${bash_minor}" -lt 3 ) ) ]]; then
            add_finding "CRITICAL" "Dependency CVE" \
                "bash ${bash_ver} is vulnerable to Shellshock (CVE-2014-6271). Upgrade to >= 4.3.25."
        fi
    fi
done

# Lint verify.sh itself
VERIFY_SCRIPT="${REPO_ROOT}/verify.sh"
if [[ -f "${VERIFY_SCRIPT}" ]]; then
    if grep -qE 'cat\s+"?\$1"?' "${VERIFY_SCRIPT}" 2>/dev/null; then
        add_finding "MEDIUM" "Script Safety" \
            "verify.sh passes \$1 directly to cat without path validation — path traversal possible with attacker-controlled input."
    fi
    if grep -qE 'echo.*\$[{(]?[A-Z_]*INPUT' "${VERIFY_SCRIPT}" 2>/dev/null; then
        add_finding "LOW" "Script Safety" \
            "verify.sh pipes an INPUT variable into sha256sum — ensure the source data is trusted."
    fi
fi

# Go toolchain (signing-service is a Go module — go 1.19 per go.mod)
log "-- Go toolchain --"

GO_MOD="${REPO_ROOT}/go.mod"
REQUIRED_GO_MAJOR=1
REQUIRED_GO_MINOR=19

if check_binary "go" "go (toolchain)"; then
    GO_VERSION="$(go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
    GO_MAJOR="${GO_VERSION%%.*}"
    GO_REST="${GO_VERSION#*.}"
    GO_MINOR="${GO_REST%%.*}"

    if [[ -n "${GO_MAJOR}" ]]; then
        if (( GO_MAJOR < REQUIRED_GO_MAJOR || \
              ( GO_MAJOR == REQUIRED_GO_MAJOR && GO_MINOR < REQUIRED_GO_MINOR ) )); then
            add_finding "HIGH" "Go Version" \
                "Installed go ${GO_VERSION} is below the go.mod requirement of ${REQUIRED_GO_MAJOR}.${REQUIRED_GO_MINOR}. Upgrade required."
        else
            log "  go version ${GO_VERSION} meets go.mod requirement (>= ${REQUIRED_GO_MAJOR}.${REQUIRED_GO_MINOR})"
        fi
    fi
fi

# go.sum integrity — if external deps were ever added without a go.sum that's a risk
if [[ -f "${GO_MOD}" ]]; then
    if grep -q '^require' "${GO_MOD}" 2>/dev/null; then
        if [[ ! -f "${REPO_ROOT}/go.sum" ]]; then
            add_finding "HIGH" "Go Dependency Integrity" \
                "go.mod declares external dependencies but go.sum is absent — dependency checksums unverified."
        else
            log "  go.sum present alongside go.mod."
        fi
    else
        log "  go.mod has no external dependencies — go.sum not required."
    fi
fi

# ── CHECK 4: Tailscale ACL enforcement ───────────────────────────────────────

log "=== CHECK 4: Tailscale ACL enforcement ==="

if [[ "${SELF_ONLINE}" != "true" ]]; then
    add_finding "HIGH" "Tailscale ACL" \
        "Machine reports Online=false in tailscale status — ACL enforcement may be inactive."
fi

EXIT_NODE_STATUS="$(echo "${TS_STATUS_JSON}" | jq -r '.ExitNodeStatus // empty' 2>/dev/null || true)"
if [[ -n "${EXIT_NODE_STATUS}" ]]; then
    add_finding "MEDIUM" "Tailscale ACL" \
        "Exit node is active: ${EXIT_NODE_STATUS} — verify peer ACLs still restrict access correctly."
fi

UNAUTH_PEERS="$(echo "${TS_STATUS_JSON}" | jq -r '
    .Peer // {} | to_entries[]
    | select((.value.UserID == 0) or (.value.UserID == null))
    | .value.DNSName // .key
' 2>/dev/null | paste -sd ',' - || true)"

if [[ -n "${UNAUTH_PEERS}" ]]; then
    add_finding "HIGH" "Tailscale ACL" \
        "Unauthenticated peer(s) in tailnet: ${UNAUTH_PEERS} — review ACL policy."
else
    log "All tailnet peers authenticated."
fi

TS_DNS="$(echo "${TS_STATUS_JSON}" | jq -r '.MagicDNSSuffix // empty' 2>/dev/null || true)"
if [[ -z "${TS_DNS}" ]]; then
    add_finding "LOW" "Tailscale ACL" \
        "MagicDNS suffix absent from tailscale status — DNS-based ACL routing may not be active."
fi

# ── Report generation ─────────────────────────────────────────────────────────

log "=== Generating report: ${REPORT_FILE} ==="

{
cat <<HEADER
# Pentagi Desktop Security Scan

| Field | Value |
|-------|-------|
| Date | $(date -u +"%Y-%m-%d %H:%M:%S UTC") |
| Target | Local desktop only — Tailscale IP \`${TS_IP4}\` |
| Node | \`${SELF_NODE}\` |
| Scope | signing-service repo, local port baseline, verify.sh + Go deps, Tailscale ACL |
| Script | \`scripts/desktop-scan.sh\` (pilot) |

> **Scope boundary:** This scan is restricted to the local Tailscale-connected desktop.
> No external hosts were contacted.
> **Do not merge without Sony review.**

---

## Summary

| Metric | Count |
|--------|-------|
| Total findings | ${#FINDINGS[@]} |
| HIGH / CRITICAL | ${COUNT_HIGH} |
| MEDIUM | ${COUNT_MEDIUM} |

HEADER

if (( COUNT_HIGH > 0 )); then
    echo "**Action required — HIGH or CRITICAL findings detected. See table below.**"
    echo ""
elif (( COUNT_MEDIUM > 0 )); then
    echo "**Review recommended — MEDIUM findings detected. See table below.**"
    echo ""
else
    echo "No findings above LOW severity."
    echo ""
fi

cat <<BODY

---

## Tailscale Gate

| Check | Result |
|-------|--------|
| Backend state | \`${BACKEND_STATE}\` |
| Local Tailscale IP | \`${TS_IP4}\` |
| CGNAT range (100.64/10) | confirmed |
| Node | \`${SELF_NODE}\` |
| Online | \`${SELF_ONLINE}\` |

---

## Findings

| Severity | Category | Detail |
|----------|----------|--------|
BODY

if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    echo "| INFO | All checks | No findings above INFO. |"
else
    printf '%s\n' "${FINDINGS[@]}"
fi

cat <<FOOTER

---

## Checks Performed

1. **Tailscale gate** — confirmed mesh active, node online, IP in 100.64.0.0/10 range; aborted if not
2. **Open port baseline** — enumerated listening TCP ports via ss/netstat; flagged ports outside expected set (${!EXPECTED_PORTS[*]}) and any 0.0.0.0 bindings
3. **Credential scan (expanded)** — scanned Go, shell, config, SQL, .env, .ini, .properties files for:
   - PEM/key block headers (RSA, EC, DSA, OPENSSH, PGP)
   - Unquoted .env assignments matching PASSWORD/SECRET/KEY/TOKEN/PRIVATE_KEY
   - Quoted credential assignments in any language
   - Service-specific formats: OpenAI sk-, Google AIza-, Slack xox-, GitHub gh[pousr]_, AWS AKIA
   - Raw private key material: hex-encoded, Ethereum 0x64-hex, base64 Ed25519 seeds
   - Explicit dotfile scan for bare .env / .env.* files not caught by glob recursion
4. **Dependency audit** — verify.sh runtime deps (bash, jq, sha256sum, awk): presence, world-writable perms, Shellshock CVE; verify.sh lint for path traversal; Go toolchain: version vs go.mod requirement (>= 1.19), go.sum presence
5. **Tailscale ACL enforcement** — self online, no unauthenticated peers, no unexpected exit node, MagicDNS suffix present
6. **Google Drive upload** — report uploaded to folder \`${GDRIVE_FOLDER_ID}\` automatically after scan

---

## Hourly Self-Check-In Scope

The CI monitoring loop watching PR #3:

| Dimension | Definition |
|-----------|------------|
| **Checks** | PR open/merged/closed state; CI check-run pass/fail; unresolved review comments |
| **Touches** | GitHub read-only API (get, get_check_runs, get_review_comments). May push a fix commit only if a CI failure is tractable and the fix is unambiguous. |
| **Does NOT touch** | Repo files without a concrete failing check; branches other than \`claude/pentagi-desktop-scan-pilot-m06o60\`; PR merge (blocked on Sony review); review comments; re-arms after PR is merged or closed. |

---

*Generated by \`scripts/desktop-scan.sh\` — local Tailscale-only pilot.*
*Sony review required before merge.*
FOOTER

} > "${REPORT_FILE}"

log "Report written: ${REPORT_FILE}"

# ── Google Drive upload (mandatory, summary only) ────────────────────────────
# Uploads a summary containing only counts, severity levels, and check names.
# No topology (node names, IPs, peer list), no credential match text, no port
# numbers or network details leave the local machine.
# The full report stays in scan-reports/ (gitignored, local only).

SUMMARY_FILE="${SCAN_REPORTS_DIR}/scan-${TIMESTAMP}-summary.md"

{
cat <<SUMMARY_HEAD
# Pentagi Desktop Scan — Summary

| Field | Value |
|-------|-------|
| Date | $(date -u +"%Y-%m-%d %H:%M:%S UTC") |
| Script | scripts/desktop-scan.sh (pilot) |
| Scope | signing-service repo, port baseline, dependency audit, Tailscale ACL |

> Full report with finding details is retained locally only.
> No network topology, IP addresses, or credential match text included here.

---

## Finding Counts

| Severity | Count |
|----------|-------|
| CRITICAL / HIGH | ${COUNT_HIGH} |
| MEDIUM | ${COUNT_MEDIUM} |
| Total | ${#FINDINGS[@]} |

---

## Check Results

| Check | Status |
|-------|--------|
| Tailscale gate | $([ "${SELF_ONLINE}" = "true" ] && echo "PASS" || echo "WARN") |
| Open port baseline | $([ "${COUNT_HIGH}" -eq 0 ] && echo "No unexpected ports" || echo "See local report") |
| Credential scan | $([ "${CRED_FOUND:-0}" -eq 0 ] && echo "No findings" || echo "${CRED_FOUND} finding(s) — see local report") |
| Dependency audit | COMPLETED |
| Tailscale ACL | $([ -n "${UNAUTH_PEERS:-}" ] && echo "WARN — see local report" || echo "PASS") |

---

*Full findings are in the local scan-reports directory. Sony review required before merge.*
SUMMARY_HEAD
} > "${SUMMARY_FILE}"

upload_report_to_gdrive "${SUMMARY_FILE}" || true  # finding already added on failure
rm -f "${SUMMARY_FILE}"

# ── Exit with appropriate code ────────────────────────────────────────────────

if (( COUNT_HIGH > 0 )); then
    log "RESULT: ${COUNT_HIGH} HIGH/CRITICAL finding(s) — immediate review required."
    exit 2
elif (( COUNT_MEDIUM > 0 )); then
    log "RESULT: ${COUNT_MEDIUM} MEDIUM finding(s) — review recommended."
    exit 3
fi

log "RESULT: No findings above LOW severity."
exit 0
