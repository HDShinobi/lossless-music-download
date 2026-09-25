# spec-harden SUMMARY — Rust Engine Migration (SpotiFLAC v5.0.0)

- **Target spec:** `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md`
- **Rounds run:** 5 (cap 4, extended by one confirming round at the user's request)
- **Critic:** Codex `gpt-5.6-sol`, effort `medium`, depth `spec`. Rounds 1–4 draft-only;
  round 5 with read access to the repo + extracted upstream v5.0.0 tree (`--context`).

## Findings by severity

| Round | Blocker | Major | Minor | Nit |
|---|---|---|---|---|
| 1 | 0 | 5 | 1 | 0 |
| 2 | 0 | 2 | 2 | 0 |
| 3 | 0 | 3 | 1 | 0 |
| 4 | 0 | 2 | 0 | 0 |
| 5 | 0 | 2 | 0 | 0 |
| **Total** | **0** | **14** | **4** | **0** |

**Accepted vs rebutted:** 17 accepted in full; 1 partially accepted (r1 #4 — arithmetic/grouping
fixed, exhaustive per-method table rebutted as altitude and deferred to plan); 0 rebutted outright.

Main design changes: persisted-data upgrade/rollback contract (§3.5); process-scoped engine flag
with isolated `engine-rust/` data and one-way cutover (§3.4); LM-FORK survival + id-set guard +
retirement in the sync script (§6); exact 41-method grouping (§3.1); DLNA lifecycle state machine
(§4); init rules — immutable per process (§3.1); E2E gate moved to end of phase 4 and re-run on
the release candidate, deterministic A/B reset, required-coverage/evidence rules (§7, §8);
success criterion 5 covers the upstream-merged outcome (§10).

## Deferred to plan
- Readiness-gate timeout value and the list of manager-independent methods (§3.1).
- Exhaustive 41-method legacy→Rust table (args, success/error shape, state effects, cancellation) — phase-2 plan, from the grouping in §3.1.

## Finalization basis
**Finalization basis: author-judgment.** Round 5 re-raised two round-4 majors (init-argument
conflicts; criterion 5(b) vs LM-FORK retirement), tripping the circuit-breaker. The user
arbitrated: apply fixes and finalize. Both were fixed in round 5's adjudication
(init arguments made immutable per process; criterion 5(b) accepts an equivalent upstream test).
**Last fixes are critic-unverified** — no Codex round saw the round-5 fixes. No blockers were
raised in any round.

Converged = spec quality only, not implementation correctness — code still needs the project's real verification.
