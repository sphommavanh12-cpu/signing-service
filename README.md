# AXM Signing Service

Trustless Ed25519 document-sealing service for AXM Contracting LLC.
Traffic runs over Tailscale (WireGuard-encrypted mesh); HTTP is used intentionally.

## axm-seal.sh

Seals a document by hashing it, submitting the hash to the signing service, and
writing the signed artifact to the appropriate drive folder.

**Usage**

```
axm-seal.sh <amd|bid|formation> <file>
```

**Doc types → target directories**

| Type | Directory |
|------|-----------|
| `amd` | `$HOME/axm-drive/03_PROTOCOL_LIBRARY` |
| `bid` | `$HOME/axm-drive/07_ACTIVE_PROJECTS` |
| `formation` | `$HOME/axm-drive/06_FORMATION_DOCUMENTS` |

**Exit codes**

| Code | Meaning |
|------|---------|
| 0 | Sealed successfully |
| 1 | Bad arguments or file not found |
| 2 | Node unreachable (NODE_DARK) or service not responding (SERVICE_DARK) |
| 3 | Empty response from signing service |

**Example seal artifact**

```json
{
  "signature": "9a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b",
  "key_version": "3a1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b",
  "timestamp": "2026-07-04T02:00:00.000000000Z",
  "chain_head_sha256": "4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c"
}
```

## axm-seal-purge.sh

Purges seal artifacts older than `RETAIN_DAYS` (default: 30) from all target directories.
Uses `flock` to prevent concurrent cron runs. macOS and Linux compatible.

**Usage**

```
axm-seal-purge.sh
RETAIN_DAYS=60 axm-seal-purge.sh
```

**Install crontab**

```
crontab $HOME/scripts/crontab
```

Weekly run, Sunday at 02:00. Sony to confirm deploy location before activating.

## Signing service endpoints

| Endpoint | Port | Method | Purpose |
|----------|------|--------|---------|
| `/sign` | 9999 | POST | Submit `{"chain_head":"<sha256>"}`, returns signed artifact |
| `/status` | 9998 | GET | Service health and uptime |

## Verification

```
./verify.sh <artifact.json> <expected_sha256>
```

Returns exit 0 on integrity match, 1 on mismatch, 2 on bad invocation.
