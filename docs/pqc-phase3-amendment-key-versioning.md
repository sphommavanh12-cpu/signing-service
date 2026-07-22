# PQC Migration — Phase 3 Amendment (v3): Key Versioning for Independent Rotation

**Status:** SONY LOCKED (2026-07-22) — dual peer review complete,
Decision D and rotation interval resolved through direct back-and-forth
before lock — ready to push to repo
**v2 → v3:** Decision D resolved (independent key generation). Rotation
interval (Trigger 1) resolved (1 year, not 2 — see Section 0 for the
reasoning, including drawbacks considered on both sides before landing
here).
**v1 → v2:** All five Gemini disagreement-pass findings resolved (see
Section 8, Dual Review Record). Two items (E, temporal validity) fully
accepted; one (manifest retention) rejected with cited evidence; two
(rotation governance, key pinning) accepted with modification.
**Amends:** docs/pqc-phase3-hybrid-signing-architecture.md (v2, Sony
locked, merged as PR #12)

---

## 0. Resolved Decisions

### Decision E — RESOLVED: E1 (sequential version string)

v1 leaned toward E2 (key fingerprint/hash). Gemini's disagreement pass
correctly identified a canonicalization-dependency risk: if the
underlying library's encoding or hashing method ever changes, identical
keys could produce different fingerprints, causing valid signatures to
fail verification years later for reasons unrelated to the actual
cryptography. For a system meant to verify documents a decade after
signing, a "dumb" sequential identifier (`v1`, `v2`, `v3`...) is safer
precisely because there is no computation to get wrong.

### Decision F — RESOLVED: F1 confirmed, archiving proposal rejected

Gemini raised a DoS concern about unbounded manifest growth requiring a
hot/cold archiving split. **Verified independently (web search, not
accepted on assertion):** an ML-DSA-65 public key is 1,952 bytes. Even
at an aggressive one-rotation-per-year cadence sustained for 50 years,
the manifest would total roughly 100KB — trivial for a bash script to
parse, and not a realistic DoS vector for a single-operator signing
service. **F1 stands as originally recommended: retain every historical
key indefinitely, no archiving/pagination needed.** This note exists so
a future reviewer doesn't re-raise the concern without also checking
the actual key size.

### Rotation Governance Trigger — RESOLVED: OR-logic retained, Trigger 2 tightened

Gemini objected to OR-logic (proposing M-of-N consensus instead) on the
grounds that a permanent cryptographic action shouldn't share governance
mechanics with a low-stakes session-close toggle. The underlying concern
is valid; the proposed fix is not — M-of-N consensus requires multiple
authorized parties, which is architecturally incompatible with AXM's
locked doctrine of Sole Execution Authority with no delegation ever
built (Rules 380/381).

**Resolved fix:** OR-logic structure retained (Trigger 1 — scheduled
interval; Trigger 2 — suspected compromise), but **Trigger 2 now
requires Sony's own direct confirmation of a credible compromise signal
before it counts** — not an automated system or third-party signal
acting alone. This closes the flooding/DoS concern Gemini identified
without inventing a multi-party governance structure that exists
nowhere else in AXIOM.

### Key Pinning — RESOLVED: Ed25519 becomes the static root of trust

Gemini identified the most significant structural gap in this
amendment: Phase 3 v2's locked pinning design assumed a static, two-key
manifest. Once the manifest becomes a growing list (Section 3, below),
static pinning — by hash or by URL — breaks on the first rotation.

**Resolved fix:** the Ed25519 key, which never rotates under this
system, becomes the permanent root of trust. Ed25519 signs the ML-DSA
manifest itself. verify.sh checks that signature first, confirming the
manifest hasn't been tampered with, before trusting any ML-DSA public
key listed inside it.

**Tradeoff, stated explicitly rather than left implicit:** this means
the hybrid signing scheme's trust anchor is still classical, not
post-quantum. If a future quantum computer capable of breaking Ed25519
exists, an attacker with that capability could forge the manifest's
signature and inject a fraudulent ML-DSA key into the trusted set —
even though ML-DSA itself remains unbroken. This amendment closes the
near-term pinning bug; it does not close the long-term quantum threat
to the trust chain's root. A fully post-quantum root of trust is a
larger undertaking, arguably premature given current PQC tooling
maturity (Phase 1's own caveat about `circl` still applies) — this is
an acceptable, known tradeoff for an incremental migration, not a
defect to be silently absorbed.

---

### Decision D — RESOLVED: Independent key generation

Originally raised as an open question in Phase 3 v2. Resolved here now
that this amendment's schema/manifest changes fully support independent
rotation regardless of how the first key is generated.

**Reasoning trail:** Initial lean was paired generation (simpler, one
combined key-generation ceremony). Revised to independent generation
once this amendment removed the schema blocker — pairing was only
attractive as the lower-effort path when independent rotation wasn't
yet structurally supported; once it is, there's no remaining benefit to
coupling the two keys' lifecycles even at the first generation event.

**Drawback considered and accepted as acceptable:** since the Ed25519
key already exists and never rotates under this system, "paired vs.
independent" in practice only affects the single, one-time ML-DSA key
generation event — there's no future Ed25519 generation event to
actually decouple from. This makes the distinction smaller in practice
than initially framed. The remaining real cost is two separate
key-generation ceremonies (each requiring its own dry-run/audit trail
per MANUAL CODE PUSH DISCIPLINE) rather than one combined event — a
minor process overhead, accepted in exchange for keeping the two keys'
security postures fully independent from day one.

**Practical implication:** the ML-DSA key is generated as its own
event, tagged `v1` under Decision E's sequential format, at whatever
point Phase 3 implementation actually begins — not bundled into any
other infrastructure ceremony.

### Rotation Interval (Trigger 1) — RESOLVED: 1 year

**Reasoning trail:** Initial lean was 2 years, on operational-risk
grounds (each rotation is a manual, error-prone event per MANUAL CODE
PUSH DISCIPLINE; fewer rotations means fewer chances to introduce a
mistake). Revised to 1 year after weighing three factors that outweigh
that concern:

1. **Silent-compromise exposure window.** Trigger 2 (Sony-confirmed
   compromise) only helps if a compromise signal actually surfaces. If
   a compromise is silent, the fixed interval alone bounds how long a
   compromised key stays trusted — 2 years of undetected exposure is a
   materially worse worst-case than 1 year.
2. **Legal/evidentiary optics.** This sealing system's stated purpose
   is attorney-defensible documentation. A 1-year rotation cadence is
   simpler to defend as diligent practice in a dispute than a 2-year
   cadence, even if 2 years is technically defensible on the
   cryptographic merits alone.
3. **`circl`'s youth.** The library's ML-DSA support is recent (Phase 1
   caveat). A shorter interval during this early period allows
   confidence in the library to build through several rotation cycles
   with real-world usage, rather than locking in a longer interval
   before that track record exists.

**Operational-risk drawback acknowledged, not dismissed:** more
frequent rotation does mean more manual ceremonies and more
opportunities for human error during each one. This is a real,
accepted tradeoff — mitigated by the fact that each rotation still
goes through the same dry-run/sanity-gate/backup discipline as any
other consequential AXM action, which is the actual control against
rotation-induced error, not a longer interval.

**Revisit trigger (not yet formally scheduled, flagged for future
consideration):** once `circl`'s ML-DSA implementation has several
years of real-world track record, the interval could reasonably be
reconsidered — but that reconsideration is a future decision, not
something this amendment presumes to schedule now.



## 1. Schema Addition (unchanged from v1)

**Target:** `debriefs-schema.sql`, table `signingevents`

```sql
pqc_key_version TEXT     -- sequential identifier (v1, v2, v3...) per
                            Decision E. Identifies WHICH ML-DSA key
                            signed this row, not just which algorithm.
                            Nullable ONLY for artifacts sealed before
                            the transition watermark — same nullability
                            rule and downgrade-attack protection as
                            pqc_signature (Section 2, below).
```

---

## 2. Downgrade-Attack Protection, Extended (unchanged from v1)

At or after the transition watermark, `pqc_key_version` must be
non-null AND must resolve to a key present in the manifest. A null or
unresolvable key version on a post-watermark row is a verification
**failure**, not a skip.

---

## 3. Chain Manifest Restructuring (updated per gate pass)

The manifest becomes a list of ML-DSA keys, each entry containing:
- `key_version` (sequential string, per Decision E)
- the public key, encoded per `circl`'s native format
- date the key became active
- date the key was superseded (blank if current)

**Retention: indefinite (Decision F, confirmed).** No archiving or
pruning mechanism — the size math doesn't warrant one.

**Trust anchor (per resolved Key Pinning decision):** the entire
manifest document is signed by the Ed25519 key. That signature, not a
static hash or URL pin, is what verify.sh checks first.

The Ed25519 entry itself remains a single, unversioned key — it does
not rotate under this system.

---

## 4. verify.sh Logic (updated — two additions per gate pass)

Phase 3 Section 3's unified state machine gains the following, in
order, before the existing ML-DSA verification step:

1. **Manifest integrity check (new):** verify the manifest document's
   own signature against the pinned Ed25519 public key. If this fails,
   the entire verification halts — the manifest cannot be trusted, so
   nothing inside it can be either.
2. **Key lookup:** read `pqc_key_version` from the row; look up the
   corresponding public key in the (now-trusted) manifest.
3. **Temporal validity check (new, closes the gap Gemini identified):**
   confirm the row's signing timestamp falls between that key's
   `active` date and `superseded` date (or is after `active` with no
   `superseded` date, if the key is still current). If the timestamp
   falls outside that window — e.g., a forger uses a since-superseded
   key's old private key material to sign something dated after that
   key was rotated out — **FAIL**. Key presence in the manifest alone
   is not sufficient; the key must have been the *valid, active* key
   at the claimed time of signing.
4. **Signature verification:** proceed with ML-DSA verification against
   that specific key, only if steps 1–3 all passed.

This remains part of the single bundled verify.sh rewrite (Decision A,
unchanged from the original Phase 3 lock) — not a new prerequisite.

---

## 5. Rotation Governance Trigger (updated per gate pass)

**Two independent triggers, either sufficient:**

- **Trigger 1 — Scheduled.** Rotate on a fixed calendar interval of
  **1 year** (resolved — see Section 0 for full reasoning trail,
  including the drawback considered and accepted).
- **Trigger 2 — Suspected compromise, Sony-confirmed.** Rotate on any
  signal suggesting the current ML-DSA private key material may be
  exposed — but **only once Sony has directly confirmed the signal is
  credible.** No automated system or third-party signal triggers
  rotation unilaterally. This closes the flooding/resource-exhaustion
  concern Gemini raised without requiring a multi-party consensus
  mechanism this system doesn't otherwise have.

**Mechanical effect of rotation** (unchanged from v1): new key
generated → new sequential `key_version` assigned → new manifest entry
added, manifest re-signed by Ed25519, old entry's supersede-date filled
in but never removed → newly sealed artifacts carry the new
`pqc_key_version`; historical artifacts remain verifiable against their
original key and its recorded validity window.

---

## 6. Effect on Decision D (key generation timing) — RESOLVED

This amendment removes the schema blocker that would have made
independent ML-DSA rotation structurally impossible. Decision D is now
resolved (Section 0): the ML-DSA key generates independently, as its
own event, not paired with any Ed25519 activity.

---

## 7. What Remains Open After This Amendment

- All original Phase 3 open items: capacity/performance estimates
  (now also covering manifest signature-verification overhead in
  verify.sh), watermark's specific deployment value
- The classical-root-of-trust tradeoff (Section 0, Key Pinning) is a
  known, accepted limitation — not an open item requiring resolution,
  but worth revisiting if/when a mature post-quantum signature root
  becomes practical to adopt
- The 1-year rotation interval's own revisit trigger (Section 0) — not
  scheduled, flagged as a future reconsideration once `circl` has a
  multi-year track record

Decision D and the rotation interval, both previously open, are now
resolved (Section 0) — this amendment has no remaining named design
decisions pending Sony's call.

---

## 8. Dual Review Record

**Drafting pass:** Claude, 2026-07-22. Produced v1 with two named
decisions (E, F) and a deferred rotation-governance section, following
from Decision D investigation surfacing the schema gap.

**Disagreement pass:** Gemini, 2026-07-22. Raised five substantive
findings: (1) E2's canonicalization-dependency risk — recommend E1;
(2) a temporal-validity gap allowing a compromised superseded key to
forge current documents; (3) unbounded-manifest DoS concern — recommend
hot/cold archiving; (4) OR-logic governance mismatch for a permanent
action — recommend M-of-N consensus; (5) the manifest restructuring
breaks Phase 3 v2's locked static key-pinning design — recommend
Ed25519 as root of trust signing the manifest.

**Gating pass:** Claude, 2026-07-22. Accepted findings 1, 2, and 5 in
full. Rejected finding 3 after independently verifying ML-DSA-65's
actual public key size (1,952 bytes) showed the DoS concern was not
supported at any realistic scale for this system. Accepted finding 4's
underlying concern but rejected its specific fix (M-of-N consensus) as
incompatible with AXM's locked Sole Execution Authority doctrine;
substituted a tightened Trigger 2 requiring Sony's direct confirmation
instead.

**FM-3 requirement satisfied:** genuine, substantive disagreement was
raised (including one structural break — finding 5 — and one critical
security gap — finding 2) and resolved with visible reasoning on both
sides, including one rejection backed by independently verified data
rather than accepted on assertion.

**AMD-034 item 8 satisfied:** no self-assessment; no unmonitored
collusion; gate pass verified a factual claim (finding 3's size math)
before ruling on it rather than trusting either the drafting pass or
the disagreement pass at face value.

---

## 9. Sony Lock

**Sony Authorization:** Approved 2026-07-22 — "v3 is ready for lock.
Please proceed with the Claude Code handoff."

**Status:** Dual peer review complete (Section 8). Decision D and the
rotation interval resolved through direct back-and-forth with Sony,
including drawbacks weighed on both sides before landing on final
values (Section 0) — not a single-pass recommendation accepted without
scrutiny.

**Scope of lock, stated explicitly per the Architecture-First Gate
Rule:** locking this amendment approves the ARCHITECTURE — the schema
addition, the manifest restructuring, the verify.sh logic changes, the
rotation governance model, and the two resolved decisions (D and
Trigger 1's interval). It does not authorize implementation to begin.
Per Section 7, capacity/performance estimates and the watermark's
specific deployment value remain outstanding prerequisites to
implementation, same as the base Phase 3 document.

---

*Requires Sony lock before this amends the locked Phase 3 document, and
before any implementation, per the Architecture-First Gate Rule. This
amendment does not authorize implementation on its own.*
