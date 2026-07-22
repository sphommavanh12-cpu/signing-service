# PQC Migration — Phase 3: Hybrid Signing Architecture Proposal (v2)

**Status:** SONY LOCKED — approved to push as the approved architecture plan (2026-07-22)
**v1 → v2:** All six Gemini disagreement-pass findings accepted and
incorporated (see Section 7, Dual Review Record)
**Builds on:** Phase 1 inventory + Phase 2 risk classification (merged, PR #10)
**Scope:** Architecture only. No code in this document.

---

## 0. Resolved Decisions

Per Rule 2(b), every design decision must be named, not silently
resolved. All four decisions left open in v1 are now resolved below,
with reasoning, following the dual peer review.

### Decision A — verify.sh: Bundled, not prerequisite

**RESOLVED: A2 (Bundled).** v1 proposed fixing verify.sh's missing
Ed25519 check as a standalone prerequisite, then adding ML-DSA
separately. Gemini's disagreement pass correctly identified this as a
false decoupling: a bash state machine written for Ed25519-only
verification would need to be torn down and rebuilt anyway once
legacy/hybrid branching (Section 3) is added. verify.sh will be
rewritten once, as a single state machine handling both signature
checks and the legacy/hybrid branch logic together.

**Caveat added at gate pass:** bundling increases the size of a single
change, raising the chance of hitting Failure Mode (d) — The
Implementation Pivot — mid-build. The verify.sh rewrite should still be
treated as its own reviewable sub-component within this blueprint, not
folded silently into a single undifferentiated diff.

### Decision B — Key pinning: deferred to, and resolved by, Decision C

**RESOLVED: B1-equivalent, made concrete by Decision C.** v1 flagged a
genuine tension: designing a pinning schema for a key encoding
(PEM headers, OID structure, byte sizing) that wasn't yet chosen was
guessing. With Decision C now resolved (below), the ML-DSA key's exact
encoding format is known, so the pinning manifest can be designed
correctly in this same pass rather than deferred further.

**Chain manifest approach:** `githubpubkeyurl` continues to point to a
single URL/document (no schema field added), but that document now
holds both public keys — Ed25519 and ML-DSA — each labeled by algorithm
and encoded per circl's native marshaling format (see Decision C).

### Decision C — PQC library: `circl` (Cloudflare), not `liboqs-go`

**RESOLVED: Cloudflare's `circl` library** (`github.com/cloudflare/circl/sign/mldsa`).

**Why, per Gemini's disagreement pass:** `liboqs-go` depends on CGO
(C bindings), which breaks static cross-compilation, complicates CI/CD,
and introduces C-level memory-safety risk directly into the
cryptographic boundary of a currently pure-Go codebase. `circl` is a
pure-Go implementation with no CGO dependency, actively maintained by
Cloudflare, and includes ML-DSA (FIPS 204) support.

**Verified independently at gate pass (web search, not taken on
citation alone):** `circl`'s ML-DSA implementation is real, current,
and shipping — confirmed via Cloudflare's own repository, package
documentation, and release notes. As of this review it has a modest
but real and growing set of known importers.

**Important caveat not to lose:** `circl`'s ML-DSA support is recent
(this year's release cycle) — "mature" is relative. This resolves
Phase 1's original concern (Finding F-6: "no viable Go PQC dependency
exists") but only downgrades the risk from "no option" to "a real,
lower-risk, but still young dependency." This should be stated plainly
to Sony, not glossed over as a fully solved problem.

### Decision D — Key generation timing

**Left open, no resolution proposed in this pass.** Whether the ML-DSA
keypair is generated alongside the Ed25519 keypair (single event) or
independently (separate rotation schedule) was flagged in v1 and not
addressed by either drafting or gating pass. This remains a named open
question for Sony, not defaulted silently.

---

## 1. Signature Scheme

**Approach unchanged from v1:** Dual-signature, not replacement. Every
sealed artifact carries both an Ed25519 signature (classical, existing)
and an ML-DSA signature (post-quantum, new) over the same content hash.
Verification requires both to pass.

**Rationale unchanged:** matches the established hybrid pattern
(ML-KEM + X25519 for key exchange; dual-sign is the signature
equivalent) — a young PQC algorithm never becomes the sole line of
defense.

---

## 2. Schema Change (updated per gate pass items 4 & 5)

**Target:** `debriefs-schema.sql`, table `signingevents`

```sql
pqc_signature TEXT
  -- ML-DSA signature, nullable ONLY for artifacts sealed before the
  -- transition watermark (see below) — see CRITICAL FIX below for
  -- why this alone is unsafe
pqc_algorithm TEXT CHECK (pqc_algorithm IN ('ML-DSA-44', 'ML-DSA-65', 'ML-DSA-87'))
  -- constrained, not free text (gate pass item 5)
```

### CRITICAL FIX — Transition watermark (gate pass item 4, downgrade attack)

**This is a required change, not optional.** v1's original design —
"if `pqc_signature` is null, treat as historical, verify Ed25519 only"
— contains a serious vulnerability identified in dual review: an
attacker who has already compromised the Ed25519 key (the exact threat
hybrid signing exists to defend against) could simply null out
`pqc_signature` on a forged row and have the verifier silently accept
it as a legitimate legacy artifact.

**Required mitigation:** add a transition watermark — a locked
timestamp, monotonic sequence ID, or schema-version marker — recorded
once, at the moment hybrid signing goes live. Verification logic
becomes:

- If artifact's sequence/timestamp is **before** the watermark →
  Ed25519-only verification is valid; `pqc_signature` being null is
  expected and correct.
- If artifact's sequence/timestamp is **at or after** the watermark →
  `pqc_signature` MUST NOT be null. A null value here is a verification
  **failure**, not a pass — this is the exact bypass the watermark
  closes.

The watermark value itself (which timestamp, which sequence number)
must be established and locked at deployment time, appended to the
Master Review Ledger, and never made retroactively editable.

**Migration approach unchanged:** ADD COLUMN, no table rebuild, no
impact on historical rows below the watermark.

---

## 3. Verification Logic (architecture level only — no code)

Rewritten as a single unified state machine (per Decision A), not a
two-phase prerequisite-then-extension approach:

1. Recompute SHA-256 hash of artifact content; compare to stored hash.
   Fail immediately on mismatch (existing behavior, unchanged).
2. Verify Ed25519 signature against the pinned Ed25519 public key.
   Fail immediately if invalid — this closes the pre-existing gap
   (verify.sh currently skips this step entirely).
3. Determine artifact's position relative to the transition watermark
   (Section 2).
   - Before watermark: skip to step 5, logging "verified under legacy
     (Ed25519-only) scheme."
   - At or after watermark: `pqc_signature` must be present and
     non-null. If null, FAIL — do not treat as legacy.
4. If ML-DSA signature is present: verify against the pinned ML-DSA
   public key (encoded per `circl`'s native format). If this fails,
   the overall result is FAILED — a valid Ed25519 signature does not
   offset an invalid or missing required ML-DSA signature.
5. Only if all applicable checks pass: overall result is VERIFIED, with
   an explicit log entry stating which scheme(s) were checked (legacy
   Ed25519-only, or full hybrid).

---

## 4. Key Generation & Storage

Extends existing CP-4 design (AES-256-GCM at rest, Argon2 KDF, systemd
`LoadCredential`, `/vault/keys`) — same key-management architecture,
now holding a second keypair generated via `circl`'s ML-DSA key
generation functions.

**Decision D (timing) remains open** — flagged for Sony, not resolved
in this pass.

---

## 5. Capacity & Performance Impact (new section — gate pass item 6)

**Gap identified in v1:** the original draft treated `pqc_signature` as
"just another string column" without accounting for its actual size.

**Concrete numbers:**
- Ed25519 signature: 64 bytes
- ML-DSA-65 signature: approximately 3,309 bytes — roughly a 50x
  increase over the existing Ed25519 signature size

**Required before Sony lock on implementation (not required for this
architecture-level document, but flagged as a mandatory follow-up):**
- Estimated impact on `SignResponse` API payload size per request
- Estimated impact on `signingevents` table size at current and
  projected row-count scale, including bulk historical fetch
  performance
- Confirmation that `verify.sh`'s bash-level string/memory handling
  does not choke on a signature roughly 50x larger than what it
  currently processes

This is a capacity-planning exercise, not an architecture decision —
it does not block this blueprint's approval, but it must be completed
before implementation begins, and should be treated as a checklist item
in the eventual implementation PR.

---

## 6. Folder/File Structure Impact

- `internal/crypto/ed25519.go` — unchanged
- `internal/crypto/mldsa.go` — new file, using `circl/sign/mldsa`
- `internal/api/handlers.go` — `SignResponse` gains `pqc_signature`
  and `pqc_algorithm` fields
- `debriefs-schema.sql` — two constrained/nullable columns (Section 2)
  plus the transition watermark record
- `verify.sh` — full rewrite per Section 3 (single unified state
  machine, not prerequisite-then-extend)

---

## 7. Dual Review Record

**Drafting pass:** Claude, 2026-07-22. Produced v1 with four named
decisions (A, B, C left unresolved; D flagged open), a dual-signature
verification design, and schema additions.

**Disagreement pass:** Gemini, 2026-07-22. Raised six substantive
findings: (1) Decision A's "prerequisite" framing creates throwaway
work — recommend bundling; (2) Decision B's "hybrid-ready now" claim
defers rather than removes risk — recommend deferring to Decision C;
(3) Decision C's refusal to recommend was an abdication — recommended
`circl` over `liboqs-go` on CGO/memory-safety grounds; (4) **critical**
— identified a downgrade-attack vulnerability in the nullable
`pqc_signature` design; (5) unconstrained `pqc_algorithm` text field is
a known vulnerability class (JWT `alg: none` precedent); (6) signature
size impact (Ed25519 64 bytes vs. ML-DSA-65 ~3,309 bytes) was never
addressed in v1.

**Gating pass:** Claude, 2026-07-22. Accepted all six findings.
Independently verified the factual claim underlying Gemini's Decision C
recommendation (searched and confirmed `circl`'s ML-DSA support is real
and current, rather than accepting the citation at face value) before
adopting it. Added one caveat Gemini didn't raise: `circl`'s ML-DSA
support, while real, is recent — the dependency-maturity risk from
Phase 1 is downgraded, not eliminated.

**FM-3 requirement satisfied:** genuine, substantive disagreement was
raised (including one critical security finding) and resolved with
visible reasoning on both sides — not rubber-stamped.

**AMD-034 item 8 satisfied:** no self-assessment; no unmonitored
collusion; the gate pass independently verified a factual claim rather
than trusting the drafting pass's citation.

---

## 8. What Remains Open

- **Decision D** (key generation timing) — genuinely unresolved,
  flagged for Sony
- **Capacity/performance estimates** (Section 5) — required before
  implementation, not before this architecture is approved
- **Transition watermark's specific value** (what timestamp/sequence
  number) — a deployment-time decision, not an architecture decision,
  but must be locked and ledger-recorded when set

---

## 9. Sony Lock

**Sony Authorization:** Approved 2026-07-22 — "lock this architecture
and push it to the repo as the approved plan."

**Scope of this approval, stated explicitly per Rule 2(c):** This locks
the ARCHITECTURE as the approved plan for Phase 3. It does not, by
itself, authorize implementation to begin — Section 8 (What Remains
Open) lists items that must still be resolved (Decision D) or completed
(capacity/performance estimates) before implementation work starts. Per
Failure Mode (d), if implementation cannot proceed exactly as this
locked blueprint specifies, it halts and returns here for revision
rather than silently diverging.

---

*Requires Sony lock before any implementation, per the Architecture-
First Gate Rule. Once locked, implementation must not silently diverge
from this blueprint — per Failure Mode (d), any roadblock requiring a
structural change routes back to a revised blueprint, not a silent
in-flight fix.*
