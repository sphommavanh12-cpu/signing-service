════════════════════════════════════════════════════════════
AMD-[TBD] — ARCHITECTURE-FIRST GATE RULE
════════════════════════════════════════════════════════════
AXM Contracting LLC — AXIOM Governance System
Status: SONY LOCKED — signature confirmed (Section 9)
Date staged: 2026-07-13 (original) — dual review completed 2026-07-21 —
             Sony signed 2026-07-21
AMD number: UNCONFIRMED — assign at next node session against
            Master Review Ledger v5; do not adopt a number without
            ledger verification (see Section 8, item 1)

════════════════════════════════════════════════════════════
1. PURPOSE
════════════════════════════════════════════════════════════
To require that any new technical build, spec, or system modification
under AXIOM/AXM produces architecture documentation — schemas, folder
structures, data flow, and named design decisions — BEFORE any
implementation code is written, and to require Sony's explicit,
unambiguous approval of that blueprint before implementation begins.

This closes a recurring gap: technical work has repeatedly moved from
concept directly to code, with architectural decisions made implicitly
during implementation rather than reviewed explicitly beforehand.

════════════════════════════════════════════════════════════
2. RULE
════════════════════════════════════════════════════════════
For any new build or significant modification to existing AXIOM/AXM
technical infrastructure:

  a. Claude (or any drafting agent) must produce, BEFORE writing
     implementation code:
       - A technical architecture document describing the approach
       - Data schemas (if applicable)
       - Folder/file structure (if applicable)
       - Explicit identification of design decisions that involve
         trade-offs

  b. A blueprint is INVALID for approval if it contains an unflagged
     design decision — defined as any point where more than one
     reasonable implementation path exists and the blueprint silently
     picked one without naming the alternatives considered. The
     blueprint does not need exhaustive schema detail on points where
     only one reasonable approach exists — the requirement is that
     real decisions are named as decisions, not that every detail is
     pre-specified.

  c. No implementation code is written until Sony gives explicit,
     unambiguous approval referencing the blueprint by name or number
     (e.g., "Approved, proceed" or "[blueprint name] approved"). Casual
     acknowledgment ("looks good," "ok," "sure") or silence/topic change
     does NOT constitute approval. If approval intent is unclear, the
     gating layer must directly ask "Is this blueprint approved to
     proceed to implementation?" rather than infer from tone or context.

  d. Neither Claude nor Gemini may offer, suggest, or hint at the
     availability of a waiver (see Section 3). Waivers originate from
     Sony only, unprompted.

  e. If implementation cannot proceed exactly as an approved blueprint
     specifies — a technical roadblock, missing dependency, or
     unexpected failure requiring a structural change — the
     implementation agent must HALT and return to the drafting layer to
     revise the blueprint. Silent mid-build architecture changes are not
     permitted, regardless of how minor they seem in the moment. (See
     Failure Mode d, Section 5.)

════════════════════════════════════════════════════════════
3. SCOPE
════════════════════════════════════════════════════════════
Applies to all AXIOM/AXM technical builds — signing-service code,
seal/stamp pipeline changes, Drive automation, homelab infrastructure
scripts, and any other system Claude or Gemini touches on Sony's behalf.

WAIVER: Sony may waive this rule for a specific task. Waivers must be
zero-prompt originations from Sony — neither drafting nor gating layer
may propose, suggest, or create pressure toward a waiver, even
implicitly (e.g., "this is simple, want me to just build it?" is a
prohibited framing).

EXCLUSION — read-only inventory/analysis and gap-analysis/red-team
review are excluded from this gate, WITH ONE CONDITION: any
analysis/audit output that names a specific implementation mechanism
(a named function, library, locking primitive, or concrete code
pattern — not just "X is broken" but "fix X by doing Y using Z") is
automatically tagged DRAFT BLUEPRINT — CANDIDATE at the moment of
output, and must pass through the same peer-review + Sony-lock gate as
any other blueprint before implementation proceeds. Pure findings that
identify a gap without prescribing a mechanism remain ungated.

════════════════════════════════════════════════════════════
4. RELATED PRECEDENT (why this rule exists)
════════════════════════════════════════════════════════════
  1. LES-021 (locked 2026-07-10) — partial stack analysis presented as
     complete; structural proposals made before full context (the
     ledger) was reviewed. Same root cause as this rule targets:
     proceeding before the full picture is confirmed and reviewed.

  2. PM-LEDGER-REBUILD-001 — a design decision (Drive API binary
     upload) was attempted without first confirming tool support,
     failed at execution, and was worked around in the moment rather
     than escalated back to review. This is the exact scenario
     Failure Mode (d) / Rule 2(e) now formally closes.

  3. 2026-07-21 verify.sh/axm-seal-extract.sh gap analysis — fix
     recommendations surfaced multiple valid implementation mechanisms
     (flock vs. atomic rename; Go micro-binary vs. openssl call) inside
     what was framed as a read-only finding. Under dual review, this
     was identified as already crossing the analysis-to-design boundary
     this rule now formally defines (Section 3 exclusion condition).

════════════════════════════════════════════════════════════
5. FAILURE MODES
════════════════════════════════════════════════════════════
  a. Blueprint approval inferred from casual acknowledgment or
     conversational tone rather than confirmed explicitly.
     MITIGATION: Rule 2(c) — gating layer must directly confirm
     ambiguous signals rather than infer; approval must reference the
     blueprint by name.

  b. A drafting agent omits a real design decision because it wasn't
     recognized as a decision point.
     MITIGATION: peer review (Gemini draft + Claude gate) explicitly
     checks for unflagged design decisions per Rule 2(b) before Sony
     sees the blueprint.

  c. The waiver clause is used as a social-engineering vector —
     an agent frames a task as "simple enough to skip review."
     MITIGATION: Rule 2(d) and Section 3 — waivers are zero-prompt Sony
     originations only; drafting/gating layers are explicitly
     prohibited from suggesting them.

  d. THE IMPLEMENTATION PIVOT (added via dual review, 2026-07-21) — a
     blueprint is approved; implementation hits a technical roadblock;
     the implementation agent silently restructures the approach to
     make it work, invalidating the approved blueprint without
     returning to review.
     MITIGATION: Rule 2(e) — halt and return to drafting layer; no
     silent mid-build architecture changes, regardless of how minor.

════════════════════════════════════════════════════════════
6. DUAL PEER REVIEW RECORD
════════════════════════════════════════════════════════════
Drafting pass: Gemini, 2026-07-21. Raised six substantive contentions
  (AMD numbering unconfirmed; granularity loophole; waiver clause
  exploitability; analysis-to-design bleed; ambiguity in "explicit"
  approval; missing implementation-pivot failure mode).

Gating pass: Claude, 2026-07-21. Accepted all six contentions; modified
  four of them where Gemini's proposed fix risked new friction or
  procedural ambiguity (granularity fix scoped to "unflagged decisions"
  rather than mandatory exhaustive schemas; analysis-bleed fix given a
  concrete auto-tagging trigger; approval-language fix softened from a
  rigid string requirement to a confirm-if-ambiguous rule; waiver fix
  adopted as-is).

FM-3 requirement satisfied: genuine, substantive disagreement was
  raised and resolved with visible reasoning on both sides, not
  rubber-stamped. AMD-034 item 8 satisfied: no self-assessment, no
  unmonitored collusion — both passes are on record above.

════════════════════════════════════════════════════════════
7. PREREQUISITES BEFORE ACTIVATION
════════════════════════════════════════════════════════════
  ☑ Dual peer review: Gemini draft pass + Claude gate pass — COMPLETE
  ☑ FM-3 mandatory-disagreement record — COMPLETE (Section 6)
  ☑ AMD-034 item 8 compliance check — COMPLETE (Section 6)
  ☐ AMD number formally assigned against Master Review Ledger v5 —
    OUTSTANDING, do at next node session
  ☑ Sony lock — COMPLETE (Section 9 signed 2026-07-21)
  ☐ Push to signing-service repo — handed to Claude Code session
    2026-07-21, branch claude/amd-architecture-first-gate-rule,
    draft PR pending — awaiting PR URL confirmation

════════════════════════════════════════════════════════════
8. GATE RULING
════════════════════════════════════════════════════════════
Status: Dual peer review COMPLETE. Sony lock COMPLETE (Section 9).
Two administrative items remain before this is fully sealed into the
ledger:
  1. Confirm the next open AMD number at the next node session
     (do not guess; check against Master Review Ledger v5 directly)
  2. Confirm push/PR to signing-service repo completed (handed to
     Claude Code session 2026-07-21; PR URL pending confirmation)

════════════════════════════════════════════════════════════
9. SONY EXECUTION AUTHORIZATION
════════════════════════════════════════════════════════════
Sony Authorization: Sony Phommavanh          Date: 2026-07-21

Gate Ruling: SONY LOCKED — signature confirmed. Pending only AMD
number assignment and repo push confirmation before final seal.

────────────────────────────────────────────────────────────
AXM Contracting LLC — AXIOM Governance System — AMD-[TBD] v1.0
CONFIDENTIAL
────────────────────────────────────────────────────────────
