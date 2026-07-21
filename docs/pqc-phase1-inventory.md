# PQC Migration — Phase 1 Inventory
**Scope:** Curve25519 / Ed25519 / X25519 exposure across signing-service  
**Date:** 2026-07-21  
**Status:** Read-only inventory — no changes made  
**Next gate:** Phase 2 risk classification (awaits explicit sign-off before any implementation)

---

## 1. ED25519 — Application Signing

### 1.1 Core crypto implementation

**`internal/crypto/ed25519.go`**

| Lines | What is here |
|-------|-------------|
| 4 | `import "crypto/ed25519"` — Go stdlib only, no third-party library |
| 10–11 | `SigningKey` struct holds `ed25519.PrivateKey` and `ed25519.PublicKey` |
| 14–19 | `NewSigningKeyFromSeed(seed []byte)` — 32-byte seed → keypair via `ed25519.NewKeyFromSeed` |
| 26–34 | `Sign(message []byte)` — calls `ed25519.Sign`, asserts 64-byte output |
| 45–53 | `Verify(publicKeyBytes, message, signature []byte)` — standalone verification |

**`internal/api/handlers.go`**

| Lines | What is here |
|-------|-------------|
| 15–24 | `SignRequest` / `SignResponse` wire types (`chain_head` in, `signature`+`key_version`+`timestamp`+`chain_head_sha256` out) |
| 75–77 | SHA-256 of `chain_head` computed; `signingKey.Sign([]byte(req.ChainHead))` called |
| 83–86 | Signature length asserted exactly 64 bytes before response |
| 91–95 | Signature returned as hex string in JSON |

**`cmd/main.go`**

| Lines | What is here |
|-------|-------------|
| 42–45 | **⚠ CP-3 test seed** — sequential bytes `{1, 2, …, 32}` hardcoded. Deterministic, publicly derivable keypair. Marked for CP-4 replacement. |
| 47 | `crypto.NewSigningKeyFromSeed(testSeed)` — keypair created at service startup |
| 53 | `signingKey.PublicKeyHex()` printed to stdout at startup |
| 17–24 | Comment documents CP-4 plan: AES-256-GCM at-rest, Argon2 KDF, `systemd LoadCredential` |

### 1.2 Seal artifacts

**`scripts/axm-seal.sh`**

- Computes `sha256sum` of input file → sends as `chain_head` to signing service → writes `.seal.json` artifact
- Artifact fields: `signature` (Ed25519, hex), `key_version`, `timestamp`, `chain_head_sha256`

**`scripts/axm-seal-offline.sh`**

- Offline/ledger path: appends `timestamp|filename|hash|operator` to `$HOME/axm-ledger.log` (append-only)
- No Ed25519 call in this path — SHA-256 hash only, no cryptographic signature

**`audit/cp7-test-artifact/2026-04-20T19-43-40Z.json`**

- Contains a real 64-byte Ed25519 test signature over a test hash
- Fields: `signature` (base64), `key_version` (SHA-256 hex fingerprint), `hash`, `signed_at`
- Produced by the CP-3 test seed keypair — not production material

**`verify.sh`**

- Strips `block_hash` field from artifact JSON, recomputes SHA-256, compares to expected value
- Does not independently verify the Ed25519 signature (verifies content hash only)

---

## 2. X25519 — Key Exchange

**No application-layer X25519 code anywhere in the repo.**

X25519 is present only implicitly inside Tailscale/WireGuard at the network transport layer. The signing service itself makes no DH or ECDH calls.

---

## 3. WireGuard

**No WireGuard config files committed to the repo** (no `wg0.conf`, `wgclt9.conf`, or similar).

References are documentation/comment-level only:

| File | Lines | Reference |
|------|-------|-----------|
| `README.md` | 4 | "Traffic runs over Tailscale (WireGuard-encrypted mesh); HTTP is used intentionally." |
| `scripts/axm-seal.sh` | 9–11 | Comment explaining WireGuard transport makes TLS redundant |

WireGuard key material (private/public/preshared keys) is not present in the repo. Key type is X25519 by WireGuard protocol — no negotiation, fixed.

---

## 4. TLS

**No TLS configured anywhere in this service — by design.**

- `cmd/main.go` HTTP servers configure timeouts only; no `TLSConfig`, no cipher suites
- No `ssl_ciphers`, `ECDHE`, or TLS-related strings anywhere in the repo
- Trust boundary is the Tailscale/WireGuard mesh (documented in multiple places)

---

## 5. SSH

**No SSH config files, key files, or SSH-related directives in the repo.**

- `scripts/desktop-scan.sh` line 195: comment notes port 22 is restricted to `tailscale0` interface — context only, no key config committed

---

## 6. Tailscale

Tailscale is the trust perimeter for all signing traffic. Relevant references:

| File | Lines | What is here |
|------|-------|-------------|
| `cmd/main.go` | 27 | Default bind address: `100.118.135.73` (Tailscale CGNAT IP) |
| `cmd/main.go` | 38–40 | Guard: `log.Fatal` if bind is `0.0.0.0` or `::` — Tailscale-only enforcement |
| `trustless-signing.service` | 3 | `After=tailscaled.service` — systemd dependency on Tailscale daemon |
| `scripts/axm-seal.sh` | 6, 41–45 | `SIGNING_IP="100.118.135.73"`; health check gate before signing |
| `scripts/desktop-scan.sh` | 154–187 | Gate: verifies Tailscale binary, daemon, `BackendState=Running`, CGNAT range |
| `scripts/desktop-scan.sh` | 420–451 | CHECK 4: ACL enforcement — `Self.Online`, exit node, unauthenticated peers, MagicDNS |

Tailscale's crypto is WireGuard (X25519) at transport layer. Application layer sees plain HTTP inside the mesh.

---

## 7. Dependencies

**No external cryptographic library dependencies.**

| File | Content |
|------|---------|
| `go.mod` | `module signing-service`, `go 1.19` — no `require` block |

Ed25519 is provided entirely by Go stdlib `crypto/ed25519`. No dalek, libsodium, nacl, tweetnacl, liboqs, or pqcrypto references anywhere.

`scripts/axm-stamp-block.py` uses `reportlab` (PDF generation) — not a cryptographic dependency.

---

## 8. Key Storage

| File | Lines | What is here |
|------|-------|-------------|
| `trustless-signing.service` | 16 | `ReadWritePaths=/vault/keys` — systemd sandbox grants write access (production key vault, not yet populated) |
| `trustless-signing.service` | 27 | `LoadCredential=signing_passphrase:/etc/signing-service/passphrase.key` — systemd credential API |
| `cmd/main.go` | 20–24 | CP-4 design comment: AES-256-GCM + Argon2 KDF + `LoadCredential` path planned |

**No `.pem`, `.key`, `.pub`, `.pfx`, `.p12`, or `id_ed25519` files committed anywhere in the repo.**

---

## 9. Data Schemas

**`debriefs-schema.sql`** (SQLite)

| Table | Crypto-relevant fields |
|-------|----------------------|
| `signingevents` | `signature TEXT NOT NULL`, `keyversion TEXT NOT NULL`, `signedat TEXT NOT NULL`, `githubcommitsha TEXT NOT NULL` |
| `chainmanifest` | `githubpubkeyurl TEXT NOT NULL` (public key published to GitHub for chain-of-trust), `chainhead TEXT NOT NULL`, `timestamprfc3339nano TEXT NOT NULL`, `manifestjson TEXT NOT NULL` |

The `signature` field in `signingevents` holds a single Ed25519 signature. **This is the field that would need a parallel column for a hybrid PQC signature** (e.g., `pqcsignature TEXT`) in a future Phase 3 schema change.

No second-signature field exists today. Schema version is implicit (no migration table).

---

## 10. Scripts — Full Map

| Script | Role | Crypto ops |
|--------|------|-----------|
| `scripts/axm-seal.sh` | Online sealing | SHA-256 → HTTP POST to signing service → writes `.seal.json` |
| `scripts/axm-seal-offline.sh` | Offline/ledger | SHA-256 append-only log only — **no Ed25519 call** |
| `scripts/axm-seal-extract.sh` | Ledger reader | Reads last ledger entry, exports env vars |
| `scripts/axm-seal-package.sh` | Orchestrator | Calls offline seal → extract → PDF stamper |
| `scripts/axm-stamp-block.py` | PDF stamper | Embeds hash + timestamp into transmittal PDF via reportlab |
| `scripts/axm-seal-purge.sh` | Retention | Removes `.seal.json` files older than `RETAIN_DAYS` (default 30) |
| `scripts/desktop-scan.sh` | Security scan | Tailscale gate; credential scan (Ed25519 seed pattern at line 286); Go dep audit; Tailscale ACL |
| `verify.sh` | Integrity | Strips `block_hash`, recomputes SHA-256 — does **not** verify Ed25519 sig |
| `scripts/crontab` | Scheduling | Weekly purge at `0 2 * * 0` |

---

## 11. Findings Requiring Follow-up (Phase 2 input)

| # | Finding | File | Notes for risk classification |
|---|---------|------|------------------------------|
| F-1 | CP-3 test seed hardcoded | `cmd/main.go:42–45` | Not production, but any artifact signed under this seed is trivially attributable to a known keypair. Track in CP-4 scope. |
| F-2 | `axm-seal-offline.sh` produces no Ed25519 signature | `scripts/axm-seal-offline.sh` | Offline ledger entries are hash-only; no signature to migrate, but also no integrity guarantee beyond hash |
| F-3 | `verify.sh` does not verify Ed25519 signature | `verify.sh` | Verifies SHA-256 hash only — signature in artifact is not independently checked by this script |
| F-4 | `githubpubkeyurl` field in schema, no implementation | `debriefs-schema.sql:24` | Gap between schema intent and current code — public key pinning via GitHub not yet active |
| F-5 | Single `signature` column in `signingevents` | `debriefs-schema.sql:11` | Would need a second column for hybrid PQC signature; no migration scaffolding exists |
| F-6 | No external crypto library dependency | `go.mod` | Good: Go stdlib only. Bad for PQC: stdlib has no ML-DSA/CRYSTALS-Dilithium; liboqs or a Go binding would be required |
| F-7 | WireGuard/Tailscale key material not in repo | — | WireGuard node keys live in host OS (`/etc/wireguard/`), not here. Out of scope for this repo but in scope for host-level PQC planning. |

---

## Scope Boundary

This inventory covers only the `signing-service` repository. Items **not** in scope here but noted for completeness:

- WireGuard node private keys on Vultr host and UDM (`/etc/wireguard/wg0.conf`, `wgclt9.conf`)
- Tailscale node identity keys (managed by Tailscale daemon, not accessible here)
- SSH host keys and authorized_keys on Vultr boxes
- Any TLS certificates managed outside this repo

---

*Phase 2 (risk classification by data lifetime) and Phase 3 (architecture proposal) require explicit sign-off before proceeding.*
