# PQC Migration — Phase 2 Risk Classification

**Scope:** Risk classification by data lifetime, built on Phase 1 inventory
(PR #10, `docs/pqc-phase1-inventory.md`)
**Date:** 2026-07-22
**Status:** Classification only — no implementation mechanisms specified
**Gate note:** Per the Architecture-First Gate Rule (merged PR #11), this
document intentionally stops at classification. It does not name specific
libraries, functions, or code patterns for remediation — doing so would
auto-tag this as DRAFT BLUEPRINT — CANDIDATE and require the full
peer-review + Sony-lock gate before proceeding. Phase 3 (architecture
proposal) is the appropriate place for that, once this classification is
reviewed.

---

## Classification Method

Each item from the Phase 1 inventory is scored on two independent axes:

1. **Data lifetime** — how long the artifact needs to remain trustworthy.
   Long-lived data is exposed to harvest-now-decrypt-later risk; ephemeral
   data is not (by the time a quantum computer could break the key,
   the session is long over and irrelevant).

2. **Current verification status** — whether the item's integrity/
   authenticity claim is even being checked today, independent of PQC.
   (This axis surfaces the verify.sh gap as a confound: some "PQC risk"
   items are actually unverified today for reasons that have nothing to
   do with quantum computers.)

---

## Classification Table

| Item | Data Lifetime | PQC Risk | Current Verification Status | Priority |
|---|---|---|---|---|
| Ed25519 seal signatures (`signingevents.signature`) | **Long-lived** — sealed artifacts are meant to be verifiable years later (ledger, doctrine, contracts) | **High** — classic harvest-now-decrypt-later profile | **Partially broken today** — verify.sh does not check the signature (see standalone finding, pre-dates PQC) | **P1** — but the non-PQC gap must close first; hybrid signing on top of an unverified baseline doesn't help |
| `chainmanifest` / `githubpubkeyurl` (public key pinning) | **Long-lived** — chain-of-trust anchor, meant to be durable | **High** — if this key is ever compromised retroactively via quantum break, the whole chain-of-trust is invalidated | **Not implemented yet** (schema field exists, no code) | **P1** — but this is a "build the missing piece" item, not a "upgrade the existing piece" item |
| CP-3 test seed artifacts (`audit/cp7-test-artifact/*.json`) | **N/A** — explicitly test material, not production | **None** — not real signed data | Known-non-production, but attribution risk exists (F-1) | **Not applicable to PQC** — this is a hygiene issue (test-key discipline), unrelated to quantum timeline |
| `axm-seal-offline.sh` ledger entries | **Long-lived** — offline/ledger path, same durability expectation as online seals | **N/A currently** — no Ed25519 signature exists in this path at all (hash-only) | **No signature to migrate** — there's nothing here for PQC to upgrade; the gap is that this path was never signed in the first place | **Separate track** — this needs a decision (should this path be signed at all?) before it can be classified for PQC purposes |
| WireGuard/Tailscale transport (X25519) | **Ephemeral** — session keys, rotate per-connection/per-session | **Low** — even successful decryption of a captured WireGuard session years from now exposes only that session's traffic, not durable data | Functioning as designed; out of scope for this repo (Phase 1, Section "Scope Boundary") | **P3** — lowest priority; the data protected by this layer is not the kind that benefits from long-term confidentiality |
| SSH host keys (Vultr boxes) | **Ephemeral-ish** — protects session access, not data-at-rest | **Low-Medium** — a compromised SSH session could expose whatever was accessed during that session, but the key itself isn't protecting durable signed artifacts | Out of scope for this repo | **P3** — same reasoning as WireGuard; host-level planning item, not signing-service scope |
| Go stdlib dependency (no external crypto libs) | N/A — infrastructure fact, not a data classification | **Structural** — no ML-DSA/Dilithium available in stdlib; any hybrid signing requires a new external dependency | N/A | **Flagged for Phase 3** — this is the single biggest structural decision facing Phase 3 architecture, not a data-lifetime question |

---

## What This Classification Shows

**The two highest-priority items by data lifetime (Ed25519 seal signatures and public key pinning) both have a confound: neither is fully functioning as a *classical* (non-quantum) integrity/authenticity system today.** This changes the practical order of operations:

- It would be architecturally premature to design a hybrid Ed25519+ML-DSA signing scheme on top of a verification path (`verify.sh`) that doesn't check signatures at all today. Phase 3 hybrid-signing architecture should assume the standalone verify.sh fix (already scoped separately) is either done first or explicitly built into the same Phase 3 blueprint as a prerequisite step — not treated as a parallel, unrelated fix.
- Public key pinning (`githubpubkeyurl`) is a "build it" item regardless of PQC — it doesn't exist yet in any form. Phase 3 should decide once whether to build classical-only pinning now (faster, but redone later) or design pinning with hybrid keys in mind from the start (slower now, avoids rework).

**Everything network-transport-layer (WireGuard, Tailscale, SSH) is genuinely low priority for this repo's PQC planning** — not because the underlying math isn't vulnerable, but because the data these layers protect is short-lived by nature. This is a defensible, evidence-based deprioritization, not a gap.

**The CP-3 test seed and the offline-ledger no-signature gap are not PQC risk-classification items at all** — they got pulled into the Phase 1 inventory as findings, but they don't belong in a *quantum-readiness* priority order. They're either hygiene issues or design-scope questions that should be resolved on their own track.

---

## Recommended Sequencing Into Phase 3

Not a blueprint — a sequencing recommendation for what Phase 3 should scope, in order:

1. Confirm the verify.sh signature-check fix status (separate track, already scoped) — Phase 3 hybrid-signing architecture should treat this as a dependency, not a parallel unrelated task.
2. Decide the public-key-pinning mechanism (classical-only now vs. hybrid-ready from the start) — this is a real architectural fork requiring Sony's input, not something to resolve silently.
3. Address the Go-stdlib / external-dependency gap as its own decision point — what library, how mature, how it's vetted — before any hybrid signature code is written.
4. Explicitly defer WireGuard/Tailscale/SSH-layer PQC planning — not neglect, but a documented, reasoned "not now" based on the ephemeral-data classification above.
5. Resolve the offline-ledger (`axm-seal-offline.sh`) no-signature gap as a standalone design question — does this path need a signature at all, independent of PQC.

---

*This document is a classification, not a blueprint. Phase 3 (architecture proposal) requires its own dual peer review and Sony lock before any implementation, per the Architecture-First Gate Rule (merged, docs/AMD-036-architecture-first-gate-rule.md).*
