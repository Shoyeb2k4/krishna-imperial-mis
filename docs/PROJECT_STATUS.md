# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Last updated: **2026-08-26**

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 0 — Discovery & Architecture: COMPLETE and approved by the owner.**
Owner decisions and three mandated architectural corrections are recorded; the master spec
is at **v1.1**.

**Phase 1 — Foundation: BLOCKED at step 14.1** on the application display name and Android
application ID. See *Blockers*.

## Completed

**Phase 0 — initial (spec v1.0)**
- Workspace inspected: `C:\Users\manoj\hotel krishna` was **empty** — nothing overwritten.
- Toolchain verified with `flutter doctor`: **no issues found**.
  Flutter 3.44.9 (stable) · Dart 3.12.2 · Android SDK 36.0.0 ·
  Visual Studio Build Tools 2026 18.7.3 · 3 devices available.
- Git repository initialised on branch `main`; `.gitignore` written before any code.
- Governance and design documents authored; fifteen decisions recorded (D-001 … D-015).

**Phase 0 — revision 1.1 (owner decisions and corrections)**
- **Owner decisions recorded** as given, not reinterpreted: management accrual basis
  (D-016); date-effective per-category tax configuration with no hard-coded rate (D-017);
  expenses at gross cost, no ITC (D-018); configurable per-unit business-day cut-off,
  default 05:00 (D-019); multi-entry revenue schema with a daily-summary UI (D-023);
  Nandbhog as a Crystal Canopy revenue category (D-024); mandatory business-unit scoping
  for non-Owner roles (D-025); 7-day edit window plus explicit period close/reopen (D-026);
  no production history, sanitised fixtures, separate import path (D-027).
- **Architectural corrections applied**: one calculation *specification* with
  parity-tested engines, superseding "one SQL engine" (D-020, supersedes D-007); explicit
  concurrency semantics for voids and every financial mutation (D-021, amends D-005);
  per-platform encryption key management, threat model and recovery behaviour (D-022,
  extends D-010).
- Master spec bumped to **v1.1** with a change log (D-028); `CLAUDE.md` hard constraints
  and response footer updated to match.
- Schema extended: accrual date columns and payment state; `revenue_tax_rates` with a
  non-overlap exclusion constraint; per-unit timezone and cut-off; `period_locks` and
  append-only `period_lock_events`; `roles.requires_unit_scope`; revenue uniqueness
  constraint deliberately removed.

## In progress

- Nothing. Phase 1 cannot start step 14.1 until the blocker below is answered.

## Verified

| Item | Status |
|---|---|
| Flutter/Dart/Android/Windows toolchain | **Verified** — `flutter doctor` clean |
| Governance documents exist, are readable and internally consistent | **Verified** — re-read after revision |
| Architecture / schema proposals | **Not verified** — design only, nothing built |
| Any application behaviour | **Not implemented** |

## Known issues

None — no code exists yet.

## Blockers

1. **Application identity — blocks Phase 1 step 14.1.** The repository contains no
   approved application display name or Android application ID, and inventing one is
   prohibited: the application ID is effectively permanent once an app is installed or
   published. **Owner input required** — see *Decisions requiring Shoyeb* below.
2. **Backend not provisioned.** No Supabase project exists. Deliberate — production
   infrastructure and credentials are not created during Phase 0/1 design. Blocks the
   authentication wiring portion of Phase 1 and all of Phase 2.

## Deferred (by design)

- Approval workflow — modelled in the schema, disabled in V1 (spec §26).
- Partial payments / payables ageing (spec §5.4).
- Proration of costs across accounting periods (spec §5.2, open question Q10).
- Input tax credit and any statutory GST support (spec §6.1).
- Snapshot-based sync pull cursor — `ARCHITECTURE.md` §5.2, limitation accepted for V1.
- Historical Excel/CSV import — separate controlled workflow (spec §32).
- Other Income module — only if the owner confirms it is needed.

## Next exact task

**Answer the application identity question (display name + Android application ID).**
On receipt, Phase 1 proceeds in this order:

1. `flutter create` for Android + Windows only, with the approved identifier and
   dev/staging/prod flavours (14.1, 14.2).
2. Module/folder architecture (14.3).
3. `Money` value object + Indian formatting tests (14.4).
4. `BusinessDate` value object + cut-off boundary tests at 04:59 / 05:00 / 23:59 / 00:01
   (14.5).
5. Drift/SQLite foundation, **and prove SQLCipher encrypted open plus platform-secure key
   handling on both Android and Windows** (14.6, spec §24.1).
6. Sync state model + outbox foundation against a fake remote, with restart-persistence,
   retry, idempotent mutation identity, failure and conflict tests (14.7).
7. Design token layer (14.8).
8. Android and Windows routing shells with placeholder destinations (14.9).
9. Run every Phase 1 verification gate (§15 of the owner's brief) and report honestly.

## Open questions for Shoyeb

**Q10 — Costs spanning two accounting months (new, non-blocking).** An electricity bill
covering 15 May – 14 June currently lands **entirely in June** (the month of
`accounting_period_end`). No proration is performed in V1. Confirm this is acceptable, or
tell me the split rule you want. This affects month-boundary profit figures only.

**Q11 — Application identity (blocking Phase 1).** Application display name, and the
Android application ID (reverse-domain, e.g. `com.<yourdomain>.<app>`). This is
effectively permanent once installed or published, so it is not invented.

*Resolved in revision 1.1:* Q1 accounting basis → D-016 · Q2 GST on revenue → D-017 ·
Q3 GST on expenses → D-018 · Q4 business-day cut-off → D-019 · Q5 revenue granularity →
D-023 · Q6 Nandbhog → D-024 · Q7 users and scoping → D-025 · Q8 period close and edit
window → D-026 · Q9 historical data → D-027.

## Owner actions required

1. Provide the application display name and Android application ID (Q11).
2. Nothing else. No infrastructure is to be created yet. **You will never be asked to paste
   a password, service-role key, database password, private key or signing password into
   chat.**

## Test totals

Unit 0 · Widget 0 · Integration 0 · Database 0 · Parity 0. No test suite exists.

## Build status

| Target | Status |
|---|---|
| Android (debug) | Not attempted — no application code |
| Android (release APK / AAB) | Not attempted |
| Windows (debug) | Not attempted — no application code |
| Windows (release + installer) | Not attempted |

## Database migration status

No migrations exist. `docs/DATABASE_SCHEMA.md` is a proposal awaiting review.

## Last important decision

**D-020 — one calculation *specification*, interchangeable engines, parity proven by
tests.** This replaces the incorrect "one SQL engine" formulation, keeps offline reporting
instant and unconditional, and makes engine divergence a build failure rather than a
silent reporting bug.

## Master Spec version

**1.1**
