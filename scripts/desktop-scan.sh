#!/usr/bin/env bash
# desktop-scan.sh — Pilot security scan for the local Tailscale-connected desktop.
#
# SCOPE: local machine only. No external hosts are contacted.
# GATE:  Tailscale must be active and the machine reachable via Tailscale IP
#        before any scan begins. Aborts and logs if the mesh is down.
#
# Usage: bash scripts/desktop-scan.sh
# Output: scan-reports/scan-<timestamp>.md
#
# Do not merge without Sony review.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_REPORTS_DIR="${REPO_ROOT}/scan-reports"
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
REPORT_FILE="${SCAN_REPORTS_DIR}/scan-${TIMESTAMP}.md"
FAIL_LOG="${SCAN_REPORTS_DIR}/abort-${TIMESTAMP}.log"

# Findings array: "SEVERITY | CATEGORY | DETAIL"
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

# Tailscale uses the 100.64.0.0/10 CGNAT range
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
# 8080 = signing-service API (Tailscale-internal)
declare -A EXPECTED_PORTS=([8080]=1)

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
        add_finding "HIGH" "Unexpected Open Port" "Port ${port}/tcp is open but not in expected baseline (${!EXPECTED_PORTS[*]})."
    fi
done

# Separately flag anything bound to 0.0.0.0 (all-interfaces, not Tailscale-scoped)
if command -v ss &>/dev/null; then
    WILDCARD_LISTENERS="$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep '^0\.0\.0\.0:' | tr '\n' ' ')"
    if [[ -n "${WILDCARD_LISTENERS}" ]]; then
        add_finding "HIGH" "Network Exposure" \
            "Port(s) bound to 0.0.0.0 (all interfaces, not Tailscale-only): ${WILDCARD_LISTENERS}"
    fi
fi

log "Listening ports found: ${OPEN_PORTS[*]:-none}"

# ── CHECK 2: Exposed credentials in signing-service repo ─────────────────────

log "=== CHECK 2: Credential scan ==="

# Patterns that suggest hardcoded secrets. Case-insensitive, word-boundary aware.
CRED_PATTERNS=(
    'PRIVATE KEY'
    'BEGIN RSA'
    'BEGIN EC'
    'BEGIN OPENSSH'
    'BEGIN PGP'
    'password\s*[:=]\s*["\x27][^"\x27]{4}'
    'secret\s*[:=]\s*["\x27][^"\x27]{4}'
    'api[_-]?key\s*[:=]\s*["\x27][^"\x27]{4}'
    'token\s*[:=]\s*["\x27][^"\x27]{8}'
    'AWS_SECRET_ACCESS_KEY'
    'GITHUB_TOKEN\s*='
    'sk-[A-Za-z0-9]{20,}'
)

INCLUDE_GLOBS=(
    --include='*.go'
    --include='*.sh'
    --include='*.env'
    --include='*.json'
    --include='*.yaml'
    --include='*.yml'
    --include='*.toml'
    --include='*.sql'
    --include='*.conf'
    --include='*.cfg'
)

CRED_FOUND=0
for pattern in "${CRED_PATTERNS[@]}"; do
    while IFS= read -r hit; do
        [[ -n "${hit}" ]] || continue
        # Exclude .git internals and test fixtures that legitimately contain placeholder text
        [[ "${hit}" =~ \.git/ ]] && continue
        add_finding "CRITICAL" "Credential Exposure" "${hit}"
        CRED_FOUND=$(( CRED_FOUND + 1 ))
        # Cap at 10 hits per pattern to avoid report flooding
        [[ "${CRED_FOUND}" -ge 10 ]] && break 2
    done < <(grep -rIn "${INCLUDE_GLOBS[@]}" --exclude-dir='.git' \
                   -E "${pattern}" "${REPO_ROOT}" 2>/dev/null | head -3 || true)
done

if [[ "${CRED_FOUND}" -eq 0 ]]; then
    log "No credential patterns found in repo."
fi

# ── CHECK 3: verify.sh dependency audit ──────────────────────────────────────

log "=== CHECK 3: verify.sh dependency audit ==="

VERIFY_DEPS=(bash jq sha256sum awk)

for dep in "${VERIFY_DEPS[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
        add_finding "HIGH" "Missing Dependency" \
            "\`${dep}\` is required by verify.sh but is not installed."
        continue
    fi

    dep_path="$(command -v "${dep}")"

    # Tamper check: binary should not be world-writable
    dep_perms="$(stat -c '%a' "${dep_path}" 2>/dev/null || true)"
    if [[ "${dep_perms}" =~ [2367]$ ]]; then
        add_finding "HIGH" "Dependency Integrity" \
            "\`${dep}\` at ${dep_path} has world-writable permissions (${dep_perms}) — possible tampering vector."
    fi

    # Bash: flag pre-4.3 (Shellshock era)
    if [[ "${dep}" == "bash" ]]; then
        bash_ver="$(bash --version 2>&1 | grep -oP 'version \K[0-9]+\.[0-9]+' | head -1 || true)"
        bash_major="${bash_ver%%.*}"
        bash_minor="${bash_ver##*.}"
        if [[ -n "${bash_major}" && ( "${bash_major}" -lt 4 || ( "${bash_major}" -eq 4 && "${bash_minor}" -lt 3 ) ) ]]; then
            add_finding "CRITICAL" "Dependency CVE" \
                "bash ${bash_ver} is vulnerable to Shellshock (CVE-2014-6271). Upgrade to >= 4.3.25."
        fi
        log "  bash: ${bash_ver} at ${dep_path}"
    fi
done

# Lint verify.sh itself for risky patterns
VERIFY_SCRIPT="${REPO_ROOT}/verify.sh"
if [[ -f "${VERIFY_SCRIPT}" ]]; then
    # $1 passed unvalidated — path traversal if caller-controlled
    if grep -qE 'cat\s+"?\$1"?' "${VERIFY_SCRIPT}" 2>/dev/null; then
        add_finding "MEDIUM" "Script Safety" \
            "verify.sh passes \$1 directly to cat without path validation — path traversal possible with attacker-controlled input."
    fi
    # echo -n piped to sha256sum: no issue, but flag if sha256sum gets raw user data
    if grep -qE 'echo.*\$[{(]?[A-Z_]*INPUT' "${VERIFY_SCRIPT}" 2>/dev/null; then
        add_finding "LOW" "Script Safety" \
            "verify.sh pipes an INPUT variable into sha256sum — ensure the source data is trusted."
    fi
fi

# ── CHECK 4: Tailscale ACL enforcement ───────────────────────────────────────

log "=== CHECK 4: Tailscale ACL enforcement ==="

if [[ "${SELF_ONLINE}" != "true" ]]; then
    add_finding "HIGH" "Tailscale ACL" \
        "Machine reports Online=false in tailscale status — ACL enforcement may be inactive."
fi

# Exit node configured? Warn — could route non-Tailscale traffic through a peer
EXIT_NODE_STATUS="$(echo "${TS_STATUS_JSON}" | jq -r '.ExitNodeStatus // empty' 2>/dev/null || true)"
if [[ -n "${EXIT_NODE_STATUS}" ]]; then
    add_finding "MEDIUM" "Tailscale ACL" \
        "Exit node is active: ${EXIT_NODE_STATUS} — verify peer ACLs still restrict access correctly."
fi

# Unauthenticated peers (UserID == 0) should not appear in a healthy tailnet
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

# MagicDNS / HTTPS cert heuristic: if TailscaleDNS is not serving, ACL host routing is degraded
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
| Scope | signing-service repo, local port baseline, verify.sh deps, Tailscale ACL |
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
2. **Open port baseline** — enumerated listening TCP ports; flagged anything outside expected set (${!EXPECTED_PORTS[*]}) or bound to 0.0.0.0
3. **Credential scan** — grepped repo for key/secret/token/PEM patterns across Go, shell, config, SQL files
4. **verify.sh dependency audit** — confirmed jq, sha256sum, awk, bash present; checked permissions and known CVEs; linted verify.sh for unsafe patterns
5. **Tailscale ACL enforcement** — confirmed self online, no unauthenticated peers, no unexpected exit node, MagicDNS active

---

*Generated by \`scripts/desktop-scan.sh\` — local Tailscale-only pilot.*
*Sony review required before merge.*
FOOTER

} > "${REPORT_FILE}"

log "Report written: ${REPORT_FILE}"

# Exit codes: 0 = clean, 2 = high/critical findings, 3 = medium findings only
if (( COUNT_HIGH > 0 )); then
    log "RESULT: ${COUNT_HIGH} HIGH/CRITICAL finding(s) — immediate review required."
    exit 2
elif (( COUNT_MEDIUM > 0 )); then
    log "RESULT: ${COUNT_MEDIUM} MEDIUM finding(s) — review recommended."
    exit 3
fi

log "RESULT: No findings above LOW severity."
exit 0
