# CLAUDE.md — Project Directive

Project Lead / Product Decision-Maker: Shoyeb Akhtar
Business: Hotel Krishna Imperial
Project: Krishna Imperial MIS
Domain: hotelkrishnaimperial.in
Directive ID: SHOYEB-HOSPITALITY-MIS
Master Spec Version: 1.2

These values are governance metadata. Do not silently change them. If the Master Spec
version changes, update it here and in `docs/SHOYEB_MASTER_SPEC.md` in the same change,
and record the reason in `docs/DECISIONS.md`.

**Two distinct meanings of "owner", kept apart deliberately (D-057).**

* **Shoyeb Akhtar is the project lead and the product decision-maker.** He directs this
  work and every product decision recorded in `docs/DECISIONS.md` is his. Nothing in this
  repository states or implies that he owns Hotel Krishna Imperial, and nothing should.
* **`Owner` with a capital O is an application role**, the unscoped RBAC grant defined in
  §13.2. It is a permission level inside the software and says nothing about anybody's
  relationship to the business. It is unchanged.

Where earlier records say "the owner" in lower case, they mean the project lead.

---

## What this project is

A production management-MIS and profitability application for **Crystal Canopy Rooftop**
and **Hotel Krishna Imperial**. Managers record income and expenses at operational
detail; the system derives daily / weekly / monthly / custom-range reporting,
department, section and category analysis, business-unit and consolidated
profitability, and P&L.

It is a **management MIS**, not a statutory accounting or ERP replacement.

## Authoritative documents

The full product specification is imported here and is binding:

@docs/SHOYEB_MASTER_SPEC.md

Consult these when relevant to the task at hand:

@docs/PROJECT_STATUS.md
@docs/ARCHITECTURE.md
@docs/DECISIONS.md

Also available, read on demand (not auto-imported):

- `docs/DATABASE_SCHEMA.md` — entities, relationships, constraints, RLS
- `docs/RELEASE_CHECKLIST.md` — build, sign, verify, distribute
- `docs/PRODUCTION_RUNBOOK.md` — production operations and the secrets register (Phase 9;
  where secrets live, never their values)

## Governance rules

1. **The repository is the source of project state. Chat history is supplemental.**
   Before substantial work in a new or resumed session: read `CLAUDE.md`, the master
   spec, `PROJECT_STATUS.md`, the relevant architecture/decision docs, then read the
   actual code before making any claim about it.
2. Never assume prior chat context is newer than the repository.
3. If code and documentation disagree, investigate and resolve the discrepancy.
   Do not blindly trust either one.
4. Update `docs/PROJECT_STATUS.md` at meaningful checkpoints and **always** before
   crossing a phase boundary.
5. Record material architecture or product decisions in `docs/DECISIONS.md`.
6. Do not reopen settled decisions without new evidence.

## Hard constraints (violating any of these is a defect)

- **Platform:** Flutter + Dart, targeting **Android** (installable signed APK, AAB-ready)
  and **Windows** (compiled desktop executable + installer). Not a web app. Not a PWA.
  Not Electron. Not a browser shell.
- **Money:** stored and computed as **integer minor units (paise)**. Binary floating
  point must never touch a stored or computed currency amount.
- **Currency display:** Indian digit grouping. `₹12,36,420` — never `₹1,236,420`.
- **Offline-first:** every transactional write succeeds locally with no network, is
  queued, and syncs idempotently. Retries must never create duplicate financial records.
- **One calculation specification, parity-tested engines:** all derived financial
  arithmetic lives once, in `domain/finance/`. Reporting engines (local SQLite, remote
  Postgres) return summed paise only and perform no business arithmetic. Dashboard,
  screen, Excel and PDF consume the same result objects. A parity suite asserts exact
  equality in paise and fails the build on divergence. Never re-implement a financial
  formula inside a view, an export, a widget, or a query.
- **Offline reporting is never gated on the network.** Local is the default engine on
  every screen, and every figure carries an explicit freshness state.
- **Accrual attribution:** profitability uses `pnl_date`
  (`COALESCE(accounting_period_end, business_date)`), the ledger and edit window use
  `business_date`, cash reporting uses `payment_date`. Never mix bases in one report.
- **Business date is derived and persisted** under the unit's timezone and cut-off
  (default 05:00) — never the raw device clock, never recomputed at read time.
- **No hard-coded tax rate anywhere.** Tax is resolved from date-effective per-category
  configuration and snapshotted onto the record.
- **Explicit concurrency on every financial mutation.** Update, void, business-date
  correction and master archive all require `base_row_version`. Idempotency
  (`mutation_id`) and concurrency (`row_version`) are separate mechanisms; never conflate
  them. Only create is conflict-free.
- **Period locks and unit scope are server-enforced.** A closed period rejects every
  write; only the Owner reopens, with a mandatory reason and an audit record. Non-Owner
  roles always carry an explicit business-unit scope.
- **Encryption keys never touch code, config, git, logs or diagnostics.**
- **Server-authoritative authorization:** Postgres RLS plus server-side validation.
  Hiding a button is not security. No service-role key ever ships in a client binary.
- **No destructive financial history:** correct by void/reversal plus audit, not by
  deleting rows. Masters archive; they do not delete when referenced.
- **Deterministic finance:** no AI in the calculation path. AI may explain verified
  numbers; it may never produce them.
- **No invented business facts.** If a business rule is unknown, ask Shoyeb or record
  it as an open question. Do not guess tax rates, categories, or accounting treatment.

## Scope discipline

V1 scope and V1 non-goals are defined in the master spec (§28, §29). Do not implement
double-entry accounting, a payables sub-ledger or partial payments, input tax credit,
GST filing, payroll processing, inventory, POS, PMS, integrations, or predictive
analytics without explicit approval from Shoyeb. Historical import is a separate,
controlled workflow (§32) — never part of the normal entry path, and no real financial
data is ever committed to source control.

## Quality bar

Before declaring any phase complete, run and report: `dart format`, `flutter analyze`,
unit tests, widget tests, relevant integration tests, migration checks, and the
platform builds that the phase touches. Report status honestly using exactly these
labels: **Implemented / Tested / Partially tested / Not tested / Blocked**.
Never claim something works that has not been verified.

## Communication with the project lead

Shoyeb is the product decision-maker, not a code reviewer. Lead with the plain-language
outcome, then technical evidence. State what changed, what was tested, what is blocked,
and the next recommended action. Never bury a failure. Never ask him to paste a
password, service-role key, private key, client secret, database password, or signing
password into chat.

## Required response footer

End every substantive response in this repository with:

`Directive: SHOYEB-HOSPITALITY-MIS • SPEC v1.2 • Phase: <current phase>`

If these governance files cannot actually be read in the current environment, say
`PROJECT DIRECTIVE NOT VERIFIED` instead of guessing. Never claim to have read a file
that was not available.
