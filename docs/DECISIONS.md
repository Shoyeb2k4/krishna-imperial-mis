# Decision Log

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)

Material architecture and product decisions. Append new entries; do not rewrite history.
Settled decisions are not reopened without new evidence — record the evidence if they are.

Format: **Decision · Date · Context · Reason · Alternatives · Consequences.**

---

## D-001 — Flutter + Dart for Android and Windows
**Date:** 2026-08-26 · **Status:** Accepted (directed by owner, confirmed viable)
**Context:** The product must ship as a genuine installable Android app and a genuine
compiled Windows desktop app, sharing business logic.
**Reason:** Flutter is the only mainstream stack that produces a native Android package
*and* a compiled Windows executable from one Dart domain layer, with a mature offline
database story. Verified on this machine: Flutter 3.44.9, Dart 3.12.2, Android SDK 36.0.0,
Visual Studio Build Tools 2026 — `flutter doctor` reports no issues, so both target
toolchains are ready today.
**Alternatives:** .NET MAUI (weaker Android ecosystem for this team); React Native
(no first-class Windows desktop target for this shape); Electron + web (explicitly
prohibited by the spec).
**Consequences:** One codebase, two presentation layers. Windows desktop plugin support is
thinner than Android's, so every third-party package must be checked for Windows support
before adoption.

## D-002 — Money stored as integer minor units (paise)
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** Financial correctness is non-negotiable.
**Reason:** Binary floating point cannot represent decimal currency exactly; errors
accumulate through aggregation and allocation splits. `BIGINT` paise in Postgres and
64-bit `int` in Dart are exact, fast, and index well. `BIGINT` paise covers ~₹92,00,00,00,00,00,00,000 — never a practical ceiling here.
**Alternatives:** Postgres `numeric` (exact but maps to `double`/string awkwardly in Dart
and invites accidental float arithmetic); `Decimal` package everywhere (slower, more
ceremony, and still needs a storage decision).
**Consequences:** A `Money` value object wraps all arithmetic. Division happens only at the
presentation boundary. Any `double` touching currency is a defect. Percentage splits use
largest-remainder distribution so totals reconcile exactly.

## D-003 — Classification lives on expense allocation lines, not on the header
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** A single electricity bill is shared between Crystal Canopy and Hotel Krishna
Imperial. If the header carried the business unit and category, shared costs would be
either duplicated or unattributable.
**Reason:** Modelling the expense as a document (date, vendor, payment, total, attachment)
plus one-or-more allocation lines (business unit, department, section, category, amount)
handles the simple case and the shared case with one uniform model. All reporting
aggregates lines, so no expense ever falls outside the hierarchy.
**Alternatives:** Header-level classification with a separate "shared cost" mechanism (two
code paths, two report paths, guaranteed divergence); entering the bill twice, once per
unit (destroys the link to the real document and its attachment).
**Consequences:** Every expense — even a ₹200 grocery bill — has one allocation line.
`SUM(lines) = header.amount` is enforced by a deferred constraint trigger. Unit-scoped
permissions become naturally enforceable at line level.

## D-004 — Outbox queue plus a server-side mutation ledger for sync
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** The spec forbids duplicate transactions from retries and rejects
"just retry the API request".
**Reason:** Each user intent gets one `mutation_id` generated once and reused for every
retry. The server records processed mutation ids and replays the stored result on a
duplicate. Duplicate delivery, a crash after send, and a timeout-then-retry all collapse
to exactly one financial record. The outbox lives in SQLite, so the queue survives an app
kill.
**Alternatives:** Deduplicating on a natural key (fragile — two genuine ₹500 cash expenses
to the same vendor on the same day are legitimate); "last write wins" sync frameworks
(unacceptable for financial data).
**Consequences:** All financial writes go through a `sync_push` RPC rather than direct
PostgREST table writes. `processed_mutations` is retained 90 days.

## D-005 — Optimistic concurrency with an explicit conflict state
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** Two devices may edit the same expense while one is offline.
**Reason:** Each row carries `row_version`; an update states the version it was based on.
A mismatch is **rejected**, and the record is surfaced as *Conflict / Attention Required*
for a human to resolve. Silently overwriting someone's financial edit is unacceptable.
**Alternatives:** Last-writer-wins (silent data loss); field-level CRDT merge (large
complexity for a case that will occur rarely, and merged money is meaningless).
**Consequences:** A conflict resolution UI is required in Phase 3. Creates remain
conflict-free by construction.
**Amended 2026-08-26 by D-021.** The original text also claimed voids were conflict-free.
That was wrong and is corrected: a void is a financial state change and can be issued from
a stale view, so it carries `base_row_version` like any update.

## D-006 — Void, never delete, for financial records
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** Financial history must be auditable.
**Reason:** Corrections are made by voiding with a reason and re-entering, leaving a
complete trail. Reports exclude voided documents; audit views retain them. Masters are
archived rather than deleted, and `ON DELETE RESTRICT` makes orphaning impossible.
**Alternatives:** Hard delete (destroys audit); delete + audit copy (two sources of truth).
**Consequences:** No client role holds DELETE on financial tables. "Delete" never appears
in the UI for a financial record — the action is "Void".

## D-007 — Local SQLite is the single canonical aggregation engine in V1
**Date:** 2026-08-26 · **Status:** **Superseded by D-020 (2026-08-26).** Retained for the
record. The offline-first requirement makes a second execution environment unavoidable;
"one engine" was the wrong formulation and is replaced by "one specification, parity-tested
engines". The local-first default and the escalation trigger below survive intact.
**Context:** The spec demands exactly one calculation layer feeding dashboard, screen
reports, Excel and PDF — while also demanding full offline reporting.
**Reason:** The client already holds transactional data for offline operation. Aggregating
locally means one SQL implementation, not a Dart copy and a Postgres copy that silently
diverge. At this data volume (order of 10⁵ rows per year) local aggregation is
comfortably fast.
**Alternatives:** Server-side aggregation only (breaks offline reporting); both, from day
one (two implementations — precisely the divergence the spec prohibits).
**Consequences:** Escalation trigger recorded in `ARCHITECTURE.md` §9: if a one-month P&L
exceeds 400 ms on the reference Android device, or the local DB exceeds 500 MB, add
server-side RPCs — and ship a parity suite proving both engines agree exactly.

## D-008 — UUID v7 client-generated primary keys
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** Offline creation needs globally unique ids assigned before the server ever
sees the row. v7 is time-ordered, so it keeps B-tree insert locality (unlike v4) and sorts
usefully by creation time.
**Alternatives:** Server-assigned sequences (impossible offline); UUID v4 (index
fragmentation); ULID (equivalent, but v7 is the standardised form with better Postgres
`uuid` type support).
**Consequences:** A separate human-readable `txn_number` is generated for user reference,
unique per organisation.

## D-009 — Riverpod (code-generated) + go_router
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** Riverpod gives compile-time-checked, testable, disposal-safe state with no
`BuildContext` dependency, which suits a shared domain layer across two very different
UIs. `go_router` handles declarative routes and an auth redirect guard on both platforms.
**Alternatives:** Bloc (more ceremony per feature); provider/GetX (weaker guarantees).
**Consequences:** `build_runner` is part of the workflow; generated files are committed to
keep CI reproducible.

## D-010 — Encrypted local database (SQLCipher)
**Date:** 2026-08-26 · **Status:** Accepted, residual risk noted.
**Extended 2026-08-26 by D-022** with per-platform key management, a threat model,
logout/key-loss behaviour, and a Phase 1 obligation to prove it on both platforms.
**Reason:** Both platforms store complete company financial history on disk. A lost phone
or a shared office PC should not expose it in a readable SQLite file. The key is generated
per install and held in Android Keystore / Windows DPAPI-backed secure storage.
**Alternatives:** Plaintext SQLite (unacceptable); full-disk encryption reliance (not
guaranteed on every Windows machine in use).
**Consequences:** Slight write overhead. **Residual risk:** Windows DPAPI protection is
tied to the user account rather than hardware, so it is weaker than Android Keystore.
Accepted for V1; mitigated by requiring Windows account passwords and short session
lifetimes. Recorded here so it is a known risk, not a surprise.

## D-011 — Single Flutter package, layered by folder
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** One app, one team. Package splits (melos) would add build friction without
solving a real problem. Layer boundaries are enforced by lint rules in CI instead.
**Consequences:** Revisit if a second application (e.g. a staff-facing app) is added.

## D-012 — Material 3 as substrate, custom token layer as identity
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** M3 supplies accessibility, focus handling, input behaviour and platform
conventions for free. The spec forbids looking like a default M3 / generic dashboard app,
so all colour, type, spacing and component styling come from project design tokens.
**Consequences:** No screen may hard-code a colour or font size. A component is added to
the design system before it is used twice.

## D-013 — Supabase (Postgres) as backend, Mumbai region
**Date:** 2026-08-26 · **Status:** Proposed — awaiting owner confirmation
**Reason:** Postgres with RLS, Auth, Storage and SQL functions covers every backend
requirement without operating servers. `ap-south-1` (Mumbai) keeps latency and data
residency appropriate for an Indian business.
**Pending:** the owner must confirm the vendor, the paid tier (RLS and daily backups
matter more here than free-tier limits), and the region. Blocks Phase 1.

## D-014 — Financial year 1 April – 31 March; Asia/Kolkata business dates
**Date:** 2026-08-26 · **Status:** Provisional — assumed, needs confirmation
**Reason:** Standard Indian financial year. Business dates are stored as plain `DATE`
captured in Asia/Kolkata so a late-night rooftop sale at 01:00 does not silently land on
the wrong day.
**Pending:** whether a hospitality "business day" ends at midnight or at a defined cut-off
(e.g. 05:00) — this materially changes which day late-night revenue belongs to, and is an
open question for the owner.

## D-015 — Git repository initialised on branch `main`, nothing committed yet
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** Phase 0 requires repository initialisation. `.gitignore` covering secrets,
signing material, build output and generated files exists before any code lands, so a
credential can never be committed by accident.
**Consequences:** No commit has been made; the owner decides when and whether to publish
to a remote. If a remote is added it must be **private**.

---

# Revision 1.1 — owner decisions and mandated architectural corrections (2026-08-26)

Phase 0 was approved with the decisions and corrections below. D-016 … D-019 and
D-023 … D-027 are **owner decisions**, recorded as given and not reinterpreted.
D-020 … D-022 are **owner-mandated architectural corrections** to Phase 0 design.

## D-016 — Management accrual basis for profitability
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Context:** June salary paid on 5 July must appear in the June operating P&L. Cash-date
attribution would make monthly profit meaningless for a business whose payroll, rent and
utility bills settle after the period they belong to.
**Decision:** The P&L uses the date on which the cost was economically incurred. Four
concepts are stored separately on every expense: `business_date` (operational date),
`accounting_period_start/end` (optional service period), `pnl_date` / `pnl_period_key`
(derived attribution, stored), and `payment_status` / `payment_date` /
`payment_method_id`. Attribution rule: `pnl_date = COALESCE(accounting_period_end,
business_date)`, computed once server-side and persisted, including on allocation lines.
**Explicitly not:** double-entry accounting, a payables sub-ledger, journals, or a trial
balance. This remains a management MIS.
**Alternatives:** Pure cash basis (rejected by the owner — misstates monthly profit);
full accrual accounting with an AP ledger (out of scope, spec §29).
**Consequences:** Profitability reports use `pnl_date`; ledger and edit-window rules use
`business_date`; cash/outflow reporting uses `payment_date`. Every report states its
basis on screen and in exports. Partial payment is not modelled in V1. Costs spanning two
months are **not prorated** — they land in the month of `accounting_period_end`; this is a
stated simplification raised to the owner as Q10, not an assumption made silently.

## D-017 — Tax configuration is date-effective and per revenue category
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Context:** The supplied June management report behaves arithmetically like a 5%
tax-inclusive calculation, but Restaurant, Nandbhog, Room and Banquet must not be assumed
to share a treatment permanently, and rates change over time.
**Decision:** A `revenue_tax_rates` table keyed by `(revenue_category_id,
effective_from, effective_to)` carries `rate_bp` and `treatment ∈
{inclusive, exclusive, none}`, with a database-level guarantee that active periods for one
category never overlap. The resolved rate, treatment and source row id are **snapshotted
onto each revenue record**. Sales are normally recorded tax-inclusive. **No rate is
hard-coded anywhere.** A 5% inclusive value appears only in sanitised test fixtures.
**Alternatives:** A single application constant (explicitly prohibited); a rate column on
`revenue_categories` (cannot express rate changes over time without restating history).
**Consequences:** Inclusive extraction is exact integer arithmetic,
`tax = round_half_up(gross × rate_bp ÷ (10000 + rate_bp))`, rounded once at the record.
Aggregates sum stored paise and never re-apply a rate to a total, so a rate change next
year cannot alter last year's Net Sales. No statutory GST filing engine is built.

## D-018 — Expenses are recorded at gross cost including GST; no input tax credit
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Decision:** The operating expense is the gross amount actually incurred or paid to the
supplier, GST included. V1 builds no ITC accounting and no GST ledger, and claims no
statutory accounting support. An optional `tax_amount_minor` column exists as
**informational metadata only** — never used in any calculation, never reducing an expense,
never implying recoverability, and never a required field in the entry workflow.
**Consequences:** The primary expense workflow stays fast. If recoverable tax is ever
introduced it will be a deliberate, separately specified feature, not an emergent
reinterpretation of this column.

## D-019 — Business date is derived under a configurable per-unit cut-off, default 05:00
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Context:** A rooftop bill rung up at 01:00 on 16 June belongs to the 15 June trading day.
**Decision:** Each business unit carries its own IANA timezone and `business_day_cutoff`
(default `05:00`). Business date is derived as
`local.time < cutoff ? local.date − 1 : local.date`, **persisted**, never recomputed at
read time. The capture instant is stored separately and is never authoritative. Server
timestamps govern `created_at` / `updated_at` and ordering; the device clock is forensic
metadata only. A user may enter a date explicitly, and a privileged user may correct one;
`business_date_source ∈ {derived, manual, corrected}` records which, and every correction
is audited with before/after, actor, timestamp and reason.
**Alternatives:** Midnight boundary (wrong for late-night hospitality trade); recomputing
business date at read time (a cut-off change would silently restate closed history).
**Consequences:** Cut-off changes affect future derivations only. Timezone handling uses
the IANA database so the architecture is DST-safe even though Asia/Kolkata has no DST.
Boundary tests at 04:59, 05:00, 23:59 and 00:01 are mandatory.

## D-020 — One calculation *specification*, interchangeable engines, parity proven by tests
**Date:** 2026-08-26 · **Status:** Accepted — **supersedes D-007** (owner-mandated correction)
**Context:** D-007 claimed "one aggregation engine in SQL". That is incompatible with an
offline-first product: an Android device must show updated financial information the
instant an offline entry is saved, so local execution can never be optional, and a
server-side engine will exist for ranges outside local retention. Two execution
environments are a fact; denying it is exactly how two implementations silently diverge.
**Decision:** The canonical *specification* — measures, filters, period math, tax
extraction, Net Sales, Operating Profit, margin, deltas — lives once, in pure Dart in
`domain/finance/`, with no Drift, Supabase or Flutter dependency. Engines
(`LocalReportingEngine` over Drift/SQLite, `RemoteReportingEngine` over Postgres RPC)
return **primitive summed paise only** and perform no business arithmetic. A parity suite
runs identical sanitised fixtures through every engine and both export paths and asserts
**exact equality in integer paise**; divergence fails the build.
**Alternatives:** Local-only aggregation (breaks large historical ranges and any future
server scale); two independent full implementations (the divergence the spec forbids);
Dart-side folding of all rows (does not scale and abandons SQL's aggregation).
**Consequences:** The divergence surface shrinks from "the whole P&L" to "select and sum
the right rows". Exports contain no formulas — they render the same result objects the
screen rendered. Local is the default source for every screen and never waits on the
network. Until Postgres is provisioned, parity is asserted against a deliberately naive
pure-Dart reference implementation, so the suite has teeth from Phase 1. Every report
carries an explicit freshness state (`Local — current, N unsynced` · `Synced as of …` ·
`Local — server has newer changes`) shown in the UI and printed in export headers.

## D-021 — Every state-changing financial mutation has explicit concurrency semantics
**Date:** 2026-08-26 · **Status:** Accepted — **amends D-005** (owner-mandated correction)
**Context:** D-005 claimed a void "cannot conflict". Wrong. Device A loads Expense v3;
Device B edits it to v4; Device A then voids "v3". Voiding v4 on that stale intent would
destroy an edit nobody reviewed.
**Decision:** Idempotency and concurrency are separate mechanisms and are never conflated.
`mutation_id` + `processed_mutations` answers "have I already applied *this exact
intent*?"; `base_row_version` vs `row_version` answers "is this intent still based on
current state?". **Update, void, business-date correction and master archive all require
`base_row_version`** and are rejected as `Conflict / Attention Required` on mismatch. Only
create is conflict-free, by construction. Period close/reopen validates the period's
current state instead.
**Consequences:** Re-delivering the *same* void twice is idempotent and succeeds
identically; a *new* void based on a stale version is refused. Defined and tested edge
cases: void-already-voided with the same mutation id (replay), with a fresh matching
version (no-op success, audited once), with a stale version (conflict); update of a voided
record (rejected — voided documents are immutable, correct by new document); any mutation
into a closed period (rejected with a `period_closed` error distinct from a conflict, so
the UI states the real reason). Attachment upload-state is advisory metadata and is
explicitly exempt.

## D-022 — Local encryption key management documented and proven per platform
**Date:** 2026-08-26 · **Status:** Accepted — **extends D-010** (owner-mandated correction)
**Decision:** The SQLCipher key is a 256-bit CSPRNG value generated per installation. It is
never hard-coded, never in plaintext configuration, never committed, never logged, never
included in diagnostics or crash reports — the last two enforced by a CI grep and a logger
redaction rule rather than by discipline. **Android:** `flutter_secure_storage` →
EncryptedSharedPreferences with the master key in Android Keystore, `allowBackup=false` and
data-extraction rules excluding the database. **Windows:** `flutter_secure_storage` →
DPAPI-protected store scoped to the Windows user.
**Threat model and residual risk:** Android binds to the OS/hardware keystore. Windows
binds to the *user account*, not hardware — malware running as the same user can unwrap the
key. That residual risk is **accepted for V1** and mitigated by requiring a Windows account
password, short session lifetimes, re-authentication after idle, and no automatic sign-in.
**Logout and recovery:** sign-out clears the session only and never deletes the local
database, because that would destroy queued offline mutations that exist nowhere else.
"Sign out and erase local data" is a separate destructive action that refuses while the
outbox is non-empty. If the key becomes unavailable the database is unrecoverable by
design; the app says so plainly and offers to reset and re-download, and unsynced
mutations are lost — mitigated by aggressive sync, not by false reassurance. Key rotation
is not a V1 feature.
**Phase 1 obligation:** encrypted open, persistence and platform-secure key handling must
be **proven on both Android and Windows during Phase 1**. If the trade-off proves
unacceptable on either platform it becomes a recorded Phase 1 finding with options for the
owner to decide — never a silent drop and never a late-release surprise.

## D-023 — Revenue schema permits multiple entries per category per day; UI stays a daily summary
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Decision:** No uniqueness constraint on `(business_unit, revenue_category,
business_date)`. Each record carries `entry_kind ∈ {daily_summary, shift, import,
correction}` and an optional source reference, so shift summaries, POS imports and
corrections are all representable later without a migration. Reporting sums all `active`
rows deterministically. The routine V1 UI remains a simple Daily Sales Summary and does not
force shift-level entry.
**Consequences:** Because duplicates are now *possible*, the entry screen must actively
prevent *accidental* ones: on finding an existing active record for that unit/category/date
it asks explicitly whether to edit the existing entry or add another. It never silently
creates a duplicate. A partial index supports that lookup.

## D-024 — Nandbhog is a revenue category under Crystal Canopy Rooftop in V1
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Decision:** Nandbhog is a revenue stream within Crystal Canopy Rooftop, not a separate
business unit, and receives no independent P&L hierarchy in V1.
**Consequences:** Because revenue records reference business unit and revenue category as
separate columns, and expense allocation lines carry their own business unit, promoting
Nandbhog to a business unit later is a controlled data migration plus an owner decision on
whether history is restated or split from a cut-over date — not a schema rewrite. Recorded
as a reserved future migration in spec §31.

## D-025 — Business-unit scope is mandatory for every non-Owner role
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Context:** "A Manager must not automatically gain access to both properties."
**Decision:** `roles.requires_unit_scope` is true for Manager, Accountant and Data Entry;
only Owner may hold an unscoped, all-units grant. A database trigger rejects a scoped role
granted with a null business unit, so the safe default is enforced rather than remembered.
Authorisation is always evaluated as `(capability, business_unit_id)` via
`has_capability(cap, bu)`; role names never appear in application conditionals on either
side. Scoping is enforced at **allocation-line** level, so a unit-scoped manager sees only
their property's share of a shared electricity bill.
**Consequences:** A manager covering both properties holds two explicit, separately
revocable grants. No production user accounts are created during design phases.

## D-026 — Period close, explicit reopen, and a configurable edit window
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Decision:** While a period is open: Manager and Data Entry may edit their permitted
transactions for up to **7 calendar days** after the business date (`edit_window_days`,
configuration not a constant); Accountant and Owner may correct permitted transactions for
as long as the period stays open; beyond the window requires the distinct capability
`transaction.correct.beyond_window`. Once a period is **closed**, every create, edit, void
and business-date correction touching it is rejected server-side. Only the Owner may
reopen, via a deliberate action recording actor, timestamp and a **mandatory reason**,
written to `period_lock_events` and the audit trail.
**Consequences:** **No silent or automatic reopening exists anywhere.** Enforcement lives
in the same server-side write path as every other financial mutation — not in the UI — and
returns a `period_closed` error distinct from a version conflict so the user is told the
truth. The full closing console may arrive in a later phase; the enforcement model is built
into the write path from the start. Every correction is audited.

## D-027 — No production history yet; sanitised fixtures only; import is a separate path
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Decision:** No production financial history is imported, and **no real financial data is
ever committed to source control**. Development and tests use sanitised, anonymised
fixtures. A future Excel/CSV import is a separate controlled workflow with its own staging,
validation, reconciliation report and audit trail; it writes through the same integrity
rules as normal entry (allocation sums, period locks, capability checks) but is a distinct
path marked `entry_kind = 'import'`, permanently distinguishable in the audit trail.
**Consequences:** The normal transaction-entry path can never be contaminated or bypassed
by a bulk load, and imported figures remain identifiable years later.

## D-028 — Master Spec bumped to v1.1
**Date:** 2026-08-26 · **Status:** Accepted
**Reason:** D-016 … D-027 change financial semantics (accounting basis, tax resolution,
business-date derivation, revenue cardinality) and correct three architectural statements.
Governance requires the version to move with the semantics, so `CLAUDE.md`,
`SHOYEB_MASTER_SPEC.md` and the response footer all read **v1.1**, with the change recorded
in spec §30.
**Consequences:** Documents written against v1.0 semantics — in particular D-005's
void claim and D-007's single-engine claim — are superseded, not deleted. History stays
readable.

---

# Phase 1 — Foundation decisions (2026-08-26)

## D-029 — Application identity: "Krishna Imperial MIS" / `in.krishnaimperial.mis`
**Date:** 2026-08-26 · **Status:** Accepted (owner decision)
**Context:** The Android application id is effectively permanent. Changing it after
installation or publication forces an uninstall/reinstall and destroys local data,
including any unsynced offline entries. Phase 1 initialisation was deliberately blocked
until the owner decided, rather than inventing an identifier and continuing.
**Decision:** Display name **Krishna Imperial MIS**; application id
**`in.krishnaimperial.mis`**. Flavours append suffixes so all three coexist on one
device: `in.krishnaimperial.mis.dev`, `.staging`, and the bare id for production, with
per-flavour launcher labels.
**Consequences:** The Dart package remains `krishna_mis` for readability; the Android
`namespace` and `applicationId` are set explicitly rather than being derived from it.
Windows carries the same product identity in its executable metadata and window title.

## D-030 — Encryption via package:sqlite3 build hooks and the SQLite3MultipleCiphers build
**Date:** 2026-08-26 · **Status:** Accepted — **supersedes the `sqlcipher_flutter_libs`
mechanism named in D-010/D-022**; the encryption requirement itself is unchanged.
**Context:** `sqlcipher_flutter_libs` is **end-of-life**: version 0.7.0+eol contains no
code at all. `package:sqlite3` 3.x now selects its native SQLite build through Dart build
hooks, offering upstream SQLite, SQLCipher, or SQLite3MultipleCiphers.
**Decision:** `pubspec.yaml` declares `hooks.user_defines.sqlite3.source: sqlite3mc`.
The database is opened with `PRAGMA key = "x'<64 hex>'"`, passing the raw 256-bit key
rather than a passphrase to be derived.
**Reason:** SQLite3MultipleCiphers provides AES-256 (including a SQLCipher-compatible
cipher) uniformly on Android and Windows, and — unlike the SQLCipher build — does not
link OpenSSL on either platform, which removes a substantial build dependency from a
product that must compile for two targets for years. The SQLCipher build also lags the
current SQLite version.
**Alternatives:** `source: sqlcipher` (OpenSSL linkage, older SQLite); staying on
`sqlcipher_flutter_libs` (dead package); plaintext local storage (unacceptable).
**Consequences:** The encryption is **proven, not assumed**. A test asserts that
`PRAGMA key` genuinely encrypts — so a silent fallback to the plain SQLite build fails
the build rather than shipping a readable database. Verified on the Windows host and on
an Android device: the file does not start with `SQLite format 3`, vendor names and
amounts do not appear in the raw bytes, and a wrong key raises rather than returning an
empty database. Native binaries are fetched at build time from the package's releases;
`url_pattern` allows an internal mirror if that ever becomes a requirement.

## D-031 — `flutter_secure_storage` pinned to 9.2.4; Windows needs the Visual Studio ATL component
**Date:** 2026-08-26 · **Status:** Accepted, with a recorded toolchain blocker
**Context:** Two findings, both from actually building rather than from reading docs —
which is exactly what `ARCHITECTURE.md` §8.3 required of Phase 1.
1. `flutter_secure_storage` 11.x requires `compileSdk 37`. This machine has Android SDK
   36, and the AAR metadata check fails the Android build outright.
2. **Every** version of `flutter_secure_storage_windows` (3.1.2 and 4.2.2 both checked)
   includes `<atlstr.h>`, so the Windows build requires the **C++ ATL** component of
   Visual Studio. This installation of Build Tools 2026 does not have it, and the
   Windows build fails with `C1083: Cannot open include file: 'atlstr.h'`.
**Decision:** Pin to `flutter_secure_storage: 9.2.4`, which builds against SDK 36, and
request `AndroidOptions(encryptedSharedPreferences: true)` explicitly so the key is held
in EncryptedSharedPreferences with its master key in the Android Keystore. Record the
ATL requirement as a one-time build-machine prerequisite for Windows.
**Alternatives considered:** Installing Android SDK 37 (possible, but pulls the whole
toolchain forward for one package); replacing the package with a hand-written Windows
DPAPI FFI store (would not help — merely *depending* on the package builds its Windows
plugin, so avoiding ATL means dropping it on Android too and hand-writing Keystore
access, which is far more security-sensitive code than this problem warrants); patching
the dependency to remove the ATL include (forking a security package — rejected).
**Consequences:** Android builds and runs today. **The Windows build is blocked** until
the ATL component is installed — one action in the Visual Studio Installer, recorded in
`PROJECT_STATUS.md` under owner actions and in `README.md` as a prerequisite. Nothing
about the design changes; this is a build-machine gap, found in Phase 1 exactly as
intended rather than near release.

## D-032 — Riverpod 3 without code generation
**Date:** 2026-08-26 · **Status:** Accepted — **amends D-009**
**Context:** D-009 chose "Riverpod 2 + riverpod_generator". In practice
`riverpod_generator` and `drift_dev` cannot currently be resolved together: they require
incompatible `analyzer` majors, and `riverpod_lint`/`custom_lint` drag in an `analyzer`
old enough to demand an SDK-provided `macros` package that no longer exists.
**Decision:** Use **Riverpod 3.4.2 with hand-written providers**. `drift_dev` keeps its
code generation, because Drift's table classes genuinely need it.
**Reason:** Drift codegen is load-bearing; Riverpod codegen is convenience. Given a
forced choice, the convenience goes. Hand-written providers are perfectly maintainable
and remove `build_runner` from the edit loop for most feature work.
**Consequences:** Providers are declared explicitly. `riverpod_lint` is deferred until
the analyzer conflict clears upstream; revisit at Phase 2.

## D-033 — Local timestamps stored as ISO-8601 UTC text
**Date:** 2026-08-26 · **Status:** Accepted
**Context:** Drift's default stores `DateTime` as unix seconds and hands the value back
in the **device's local zone**. A test caught this immediately: a timestamp written as
`09:00Z` came back as `14:30` with no zone attached.
**Decision:** `DriftDatabaseOptions(storeDateTimeAsText: true)`, so instants are stored
as ISO-8601 UTC text and always read back as UTC.
**Reason:** In a financial system a timestamp that changes meaning with the reader's
timezone is a defect waiting to happen — the same row would read differently on a laptop
set to another zone, and a value written as UTC would come back wearing a local label.
Business *dates* are a separate concept entirely and carry no time at all
(see `BusinessDate`).
**Consequences:** Applied before any data exists, so no migration is required. Server
timestamps remain authoritative; the device clock is forensic metadata only.

## D-034 — Cross-period expense allocation is optional, explicit, and exact
**Date:** 2026-08-27 · **Status:** Accepted (owner decision, answering Q10)
**Context:** The Phase 0 simplification — a cost spanning two months lands wholly in the
month of `accounting_period_end` — was put to the owner as Q10 and **rejected**. A
universal closing-month rule would misstate any bill that genuinely spans a boundary.
**Decision:** Two behaviours, one model.

*Default (the fast, normal path).* Every expense has a canonical business date and
optional accounting period. With no period allocation supplied, the **full** amount
belongs to that one accounting period. ₹12,000 dated 18 June is ₹12,000 in June. Nothing
about ordinary entry changes, and no extra field appears in the fast path.

*Optional cross-period allocation.* An authorised user may deliberately spread an expense
across more than one accounting period where economically appropriate — electricity
spanning two months, annual subscriptions, insurance, maintenance contracts, rent, AMC,
prepaid operating costs. A ₹60,000 invoice for 15 May – 14 June may be allocated
₹30,000 / ₹30,000, or by any other deliberate split.

**Invariants:**
- Period allocations attach to an **expense allocation line**, so cross-period and
  cross-business-unit splitting compose without either mechanism knowing about the other.
- `SUM(period allocations) = the allocation line's amount` is enforced by a deferred
  constraint trigger. **No paise may disappear or be duplicated.**
- Gated by its own capability (`expense.allocate_periods`), held by finance and owner
  roles only — not by Manager or Data Entry.
- Every period allocation and every change to one is audited.
- Each target period is checked against period locks and the edit window individually: a
  split touching a closed month is refused like any other write into it.

**Reporting rule:** where period allocations exist, reports use them; otherwise they use
the expense's own accounting period. Uniform, with no special case in the query — see
`DATABASE_SCHEMA.md` §5.1 and `ARCHITECTURE.md` §6.2.

**Explicitly not in V1 (spec §29):** no general ledger, no automatic journal entries, no
prepaid or accrual accounts, no accrual reversals, no statutory accounting. This is a
management attribution mechanism, not double-entry.

**Day-count proration:** if added later it must be an **explicit helper that proposes a
split for the user to accept or edit**, shown before it is applied and revisable
afterwards — never a hidden or irreversible assumption. The suggestion uses
largest-remainder distribution so a proposed split already reconciles exactly.

**Consequences:** `ARCHITECTURE.md` §12 limitation 2 is withdrawn — the closing-month
approximation no longer exists. `expense_period_allocations` is added to the schema. The
capability catalogue gains `expense.allocate_periods`. Ordinary expenses stay exactly as
simple as they were.

## D-035 — Historical integrity: stable id, immutable code, label snapshot
**Date:** 2026-08-27 · **Status:** Accepted
**Context:** Master spec §12 requires that renaming a master must not silently corrupt the
interpretation of history — while still allowing a genuine typo to be fixed. Those two
pull in opposite directions, and picking only one of them is wrong either way.
**Decision:** Three mechanisms together.
1. **Stable `id`** — every aggregation groups on it, so no display change can move a
   total by a single paisa.
2. **Immutable `code`** — assigned at creation, never editable. The repository offers no
   method that changes it. History, capability grants and joins all key on it.
3. **Label snapshot** — each transaction stores the master's name as it read on the day
   it was recorded.

Reports show the **current** name by default, because that is what a manager expects when
a spelling is corrected. The transaction detail and the audit trail can always show what
was actually on screen when the entry was made, and `wasRenamedSince` flags the difference
rather than hiding it.
**Alternatives:** Snapshot only (a corrected typo never propagates and old reports look
wrong forever); current name only (renaming "Water" to "Diesel" silently rewrites what
history appears to say); forbidding renames outright (unusable — typos happen).
**Consequences:** Re-purposing a master remains prohibited by policy, and no schema can
detect intent. The system makes it *survivable* instead: every rename is audited, the code
cannot move, and the snapshot keeps history readable even if someone does it anyway.
Archived masters stay valid for existing entries and are refused only for new ones, so
archiving a category can never retroactively invalidate the amounts already booked
against it.

## D-036 — Verified Windows key protection: user-scope DPAPI, not Credential Manager
**Date:** 2026-08-27 · **Status:** Accepted — **corrects D-010 and D-022**
**Context:** D-010/D-022 described the Windows key store as "DPAPI / Credential Manager"
from the architecture proposal. The owner required this be *verified* rather than
assumed. It was, by reading the code path that actually executes and then inspecting the
artefact the running Windows application produced.
**What is actually used.** `flutter_secure_storage_windows` 3.1.2 ships **two**
implementations. The C++ plugin (`CredWriteW`, `CRED_TYPE_GENERIC`,
`CRED_PERSIST_LOCAL_MACHINE`, AES-128-GCM, per-key `.secure` files) is **not** the path
taken. The **Dart FFI implementation** is, and it calls
**`CryptProtectData` / `CryptUnprotectData` — Windows DPAPI**, storing the entire
key/value store as one protected blob:

```
%APPDATA%\Krishna Imperial\Krishna Imperial MIS\flutter_secure_storage.dat
```

**Verified empirically on this machine**, not inferred:
- The file carries the DPAPI blob signature `01 00 00 00 d0 8c 9d df 01 15 d1 11 8c 7a 00 c0`.
- `ProtectedData.Unprotect(..., CurrentUser)` decrypts it; the plaintext is a plain
  `{key: value}` map containing `krishna_mis.db_key.v1`.
- No Windows Credential Manager entry exists for the application (`cmdkey /list` is
  empty of it), confirming the C++/Credential-Manager path is unused.
- `CryptProtectData` is called with `dwFlags = 0` — **no `CRYPTPROTECT_LOCAL_MACHINE`**,
  so the blob is **user-scoped** — and with **no optional entropy**.

**Consequences for the threat model.** The database key's protection is exactly
"DPAPI, current Windows user, this machine". Practically:
- Another Windows user on the same machine cannot read it.
- Copying the `.dat` file to another machine or user profile makes it useless — which is
  also why a roaming profile would carry an undecryptable blob, since the file lives
  under Roaming AppData while the DPAPI key does not roam.
- **Any process running as the same Windows user can call `CryptUnprotectData` and
  recover the key.** No application-supplied entropy is used, so there is no second
  factor. This is the residual risk already accepted for V1, now stated precisely rather
  than approximately. Mitigations remain: require a Windows account password, short
  session lifetimes, re-authentication after idle, no automatic sign-in.
- If that residual risk is ever judged unacceptable, the fix is to supply application
  entropy to `CryptProtectData` or to move the key behind a user-supplied passphrase.
  Both are deliberate changes, not silent ones.
**Note:** Android is unaffected — it uses EncryptedSharedPreferences with the master key
in the Android Keystore, as documented.

## D-037 — The backend is the authority; the client Authorizer is UX and testability
**Date:** 2026-08-27 · **Status:** Accepted (owner requirement, made explicit)
**Context:** Phase 2 has produced a complete client-side capability, scope, hierarchy,
period-lock and edit-window engine. It would be easy to mistake that for security.
**Decision:** It is not. The pure-Dart `Authorizer` exists to give **immediate, offline,
testable UX** — a disabled control, an honest error message, a form that cannot be
submitted. **A modified Android or Windows client must not be able to bypass any rule.**
When the Supabase portion of Phase 2 lands, every one of the following is re-decided
server-side and the server's answer is final:
capabilities · business-unit scope · hierarchy validation · archived-master restrictions ·
period locks · edit-window rules · close/reopen authorisation · financial mutation
authorisation.
**Mechanisms:** RLS on every table for visibility and unit scope; database constraints
and triggers for hierarchy and allocation-sum integrity; `SECURITY DEFINER` RPCs inside
a transaction wherever multi-row integrity is at stake (`sync_push`, period close/reopen,
expense + allocation + period-allocation writes). Direct client table writes are not
granted on financial tables.
**Consequences:** The same rules exist twice by design — once in Dart for the interface
and once in Postgres for the guarantee. That duplication is deliberate and must be kept
in step: the RLS/RPC test suite asserts **allow and deny** for each rule, and a policy
without a passing deny-test is not done (`ARCHITECTURE.md` §8). The client's opinion is
never trusted, never sent as an authorisation claim, and never used to skip a server
check.

## D-038 — Cosmetic rename versus semantic change (amends D-035)
**Date:** 2026-08-27 · **Status:** Accepted (owner clarification)
**Context:** D-035 established stable id, immutable code and label snapshot. It did not
say plainly *when* a rename is legitimate. This makes the rule explicit.

### Cosmetic rename — permitted
A master's label may be renamed when its **business meaning is unchanged**. Fixing a
spelling or spacing is exactly this:

```
VEGITABLE & FRUITS   →   VEGETABLES & FRUITS
Frontoffice          →   Front Office
```

Reports display the corrected current label. The audit trail and the transaction detail
retain the transaction-time label snapshot, so it stays possible to see what was on
screen when each entry was made.

### Semantic change — prohibited as a rename
A rename must **never** be used to change the accounting or operational meaning of
historical data:

```
Kirana & Pulses      →   Building Maintenance      ← PROHIBITED
```

That would make months of grocery spending appear under a materially different concept,
silently restating history. When the meaning changes, the procedure is:

1. **archive** the existing master;
2. **create a new master with a new, stable, immutable code**;
3. use the new master for **new transactions only**;
4. **preserve every historical reference** to the old master.

### How the application enforces it
No semantic detection is attempted — that judgement is the owner's, and an AI guess about
whether two labels "mean the same thing" would be exactly the kind of invented business
fact this project forbids.

Instead the application makes the distinction **visible and deliberate**:
- Renaming a master that **has historical usage** shows a warning stating the rule, the
  number of transactions affected, and the period they span.
- The Owner/admin must **explicitly acknowledge** the warning before the rename applies.
- A master with no history renames without ceremony.
- The immutable `code` and the historical references remain authoritative regardless of
  what the label says, so even a misjudged rename cannot corrupt aggregation, joins or
  capability grants.
- Every rename is audited with before/after values and the acknowledging actor.

The Masters UI is designed around this distinction rather than presenting rename as an
ordinary inline edit.
**Consequences:** The Masters UI needs a usage count per master (transactions referencing
it, with their date range) before the rename dialog can state the impact. That query is a
Phase 2 deliverable and is listed in `PROJECT_STATUS.md`.

## D-039 — Archiving a parent refuses while it has live children
**Date:** 2026-08-27 · **Status:** Accepted — **owner may revise; options stated below**
**Context:** Owner requirement §7 asked for a deliberate, tested rule for what happens to
active children when a parent master is archived, and for the options to be reported
before any irreversible semantics were built.
**Decision:** Archiving refuses while the record has **live children**, naming how many.
The user archives bottom-up: category, then section, then department. Nothing cascades and
nothing is reassigned.
**Why this one:** It is the only option with no destructive or surprising outcome. The
alternatives were:

| Option | Why not the default |
|---|---|
| **Refuse while children are live** *(chosen)* | Slightly tedious for a large subtree, but nothing happens that the user did not ask for, and every step is individually reversible. |
| Cascade-archive the whole subtree | One click could archive dozens of categories. Reversing it means finding and restoring each one, and a mis-click is expensive. Viable **with an explicit confirmation listing what will be archived** — say the word and it becomes an additional action beside the current one, not a replacement. |
| Archive the parent and leave children live | Orphans them: a live category hanging off an archived section, still offered in pickers, inside a structure that no longer exists. Rejected outright. |
| Reassign children to the grandparent | Silently changes the meaning of the hierarchy and therefore of every future report grouped by it. Rejected — this is the reporting-integrity equivalent of a semantic rename (D-038). |

**Nothing about archiving touches history.** An archived master keeps every existing
reference, stays valid for entries already recorded, is excluded from pickers for new
ones, and leaves past reports unchanged. Archiving is permitted regardless of how much
history a record carries — that is precisely what it is for — and only live *children*
block it. Restore is always available.
**Consequences:** Implemented in `ArchivePolicy`, enforced by `MasterRepository`, surfaced
as *"Archive the N records underneath this one first"*, and covered by tests at both the
domain and UI level.

---

# Phase 2 — Backend, authorisation and session decisions (2026-08-27 … 2026-08-28)

D-040 … D-043 were recorded while the migrations were being written. D-044 … D-047 were
forced by applying them to the real development project. D-048 … D-051 are the owner's
decisions on cache revocation, vendor semantics, outbox ownership and the session model.
D-052 … D-056 were forced by the Phase 2 device acceptance — every one of them is a defect
the acceptance found in code that had already passed review and a green host suite.

All of them were held in `docs/DECISIONS_PHASE2_BACKEND.md` while unverified. That file no
longer exists: this is the single authoritative record.

## D-040 — The hierarchy is pinned by a composite foreign-key ladder
**Date:** 2026-08-27 · **Status:** Accepted — applied and verified against `krishna-mis-dev`, 2026-08-28
**Context:** Owner requirement §4: the database must reject impossible structures even if
the client is modified — a section belonging under a Hotel Krishna department must not be
attachable to a Crystal Canopy hierarchy. The owner also warned specifically against
"duplicated denormalized parent IDs unless they materially strengthen validation and
remain transactionally consistent."

A plain parent foreign key does not achieve the requirement. `sections.department_id →
departments(id)` guarantees the department exists and says nothing about which property it
belongs to. Nothing in that constraint stops a section being re-pointed across properties.

**Decision:** Each level carries its ancestors and references its parent by the whole
tuple:

```
departments        (org_id, business_unit_id)                → business_units(org_id, id)
sections           (org_id, business_unit_id, department_id) → departments(org_id, business_unit_id, id)
expense_categories (org_id, business_unit_id, department_id, section_id)
                                                            → sections(org_id, business_unit_id, department_id, id)
```

**Why this is not the duplication the owner warned about.** The ancestor columns are not
free-floating copies kept in step by application code or by a trigger. Each is *pinned by
the same foreign key that pins the parent link*, checked at the same instant, in the same
statement. For a section to claim the wrong business unit it would have to name a
`(business_unit_id, department_id)` pair that does not exist in `departments`, and the key
refuses it. Consistency is not maintained; it is structurally unavailable to break.

**Alternatives:** a validation trigger per level (correct until someone writes a path that
skips it, and it must re-read the parents on every write); application-only validation
(explicitly insufficient — a modified client bypasses it); no ancestor columns and a
recursive check at use time (turns every Phase 3 allocation-line write into a three-join
verification).

**Consequences:**
- Re-parenting a department across properties fails while it has sections, because their
  tuples would stop resolving. A `refuse_reparent_across_units` trigger refuses the move
  outright as well, so the failure names the real problem instead of surfacing as a
  foreign-key error on a row nobody was looking at.
- A Phase 3 expense allocation line validates its entire classification with **one**
  composite foreign key against
  `expense_categories(id, section_id, department_id, business_unit_id)` — no trigger, no
  application check, no possible drift.
- Slightly wider indexes and four extra uuid columns across four tables. Accepted.

## D-041 — Master usage is a maintained counter, never a `count(*)`
**Date:** 2026-08-27 · **Status:** Accepted — applied and verified against `krishna-mis-dev`, 2026-08-28
**Context:** Owner requirement §11: an authoritative server usage figure for masters, and
explicitly *"do not design an expensive `COUNT(*)` pattern that will become pathological
once financial history is large."* D-038 needs that figure before a rename dialog can
state its real impact.
**Decision:** `master_usage_counters` holds one row per master — count, earliest and latest
business date — maintained incrementally by `app.record_master_usage`, which the Phase 3
financial write path calls. `public.master_usage()` reads it by primary key, in O(1), and
labels the result `source: 'server'`.
**Alternatives:** `count(*)` over allocation lines (a full scan of financial history every
time an administrator opens a dialog that must feel instant); a materialised view (refresh
latency, and a stale count is exactly the thing that must not be relied on for an archive
decision); an approximate count (unacceptable for a decision the owner is told is safe).
**Consequences:**
- While no financial tables exist, a count of zero is **genuinely authoritative** — there
  are no transactions in the organisation at all, so nothing is approximated. That is
  different in kind from a local cache reporting zero because it has not synced, which the
  client must never promote to authoritative. `MasterUsage` already carries its source and
  keeps the two apart.
- The counter trigger wiring lands with the Phase 3 financial tables. Until then
  `record_master_usage` has no callers, which is deliberate and stated rather than
  discovered later.

## D-042 — Period locks are keyed by `period_key`, not by a start/end date pair
**Date:** 2026-08-27 · **Status:** Accepted — applied and verified against `krishna-mis-dev`, 2026-08-28
**Context:** `docs/DATABASE_SCHEMA.md` §7 sketched `period_locks` with `period_start` and
`period_end` date columns. The implemented client — `BusinessDate.periodKey`, the local
SQLite `period_locks` table and `PeriodRegistry` — settled on a `'YYYY-MM'` key.
**Decision:** Postgres uses `period_key text` with a format check, matching the client and
the local mirror.
**Reason:** Two representations of the same concept must be converted at every boundary,
and a conversion is a place to be wrong. The key is also what the authoriser actually asks
for, so keying on it removes a translation step from the hot path of every financial write.
A month is the only period granularity V1 closes.
**Consequences:** `docs/DATABASE_SCHEMA.md` §7 is superseded on this point and is corrected
when Phase 2 completes. If a non-monthly close is ever needed, the change is a new column
plus a migration, not a redesign — the lock is still one row per (org, unit, period).

## D-043 — No tax rate is seeded, and none is assumed
**Date:** 2026-08-27 · **Status:** **Accepted (owner decision, 2026-08-27)**
**Context:** `docs/DATABASE_SCHEMA.md` §12 lists "initial tax configuration rows" among the
seeded data. Spec §8.1 and `CLAUDE.md` forbid a hard-coded rate anywhere, and permit a 5%
inclusive value only in **sanitised test fixtures**. Put to the owner, who confirmed it and
made the terms explicit.
**Decision (owner's words):** No GST or tax rate is seeded yet. The tax treatment for
Restaurant, Nandbhog, Room and Banquet will be supplied later, after the actual business
tax treatment has been verified. Specifically:

* no default tax rate;
* no assumed 5%;
* no assumed 18%;
* no implicit inheritance from another category, another property or another period;
* no fake production tax rule in seed data.

The Tax Rules feature carries an explicit **"No rule configured"** state. This does not
block Phase 2.

The seed therefore creates no `revenue_tax_rates` rows at all, and the timeline for each
revenue category starts empty.
**Reason:** A rate committed to a migration is a rate in source control that nobody chose,
and it would silently produce Net Sales figures the owner never approved. The domain
already treats a missing rule as a visible configuration gap rather than a silent "no tax"
that overstates Net Sales, so an empty timeline is both honest and already handled.
**Consequences:** The owner supplies the first rule per revenue category — Restaurant,
Nandbhog, Room, Banquet — through the Tax screen or `tax_rule_create`, each with its rate,
its treatment and the date it takes effect, once the real treatment is verified. Until
then:

* `TaxRuleSet.ruleFor` returns null rather than a zero-rate default, so a missing rule is a
  visible configuration gap and never a silent "no tax" that would overstate Net Sales;
* the Tax screen states *"No tax rule configured. Revenue recorded for this category will
  have no tax extracted until one is set."* in the caution colour, and shows *"No rule in
  force today"* against the category — already implemented and covered by a widget test;
* Phase 4 revenue entry must refuse, or record explicitly untaxed, rather than assume — it
  must not invent a rate from any source.

No entry in the seed, the migrations, the fixtures or the code carries a rate.

---

### Forced by applying the schema to a real database (2026-08-27)

D-044 … D-047 were not designed; they were discovered by executing the migrations against
`krishna-mis-dev` and watching what actually happened. Each is verified against that
project.

## D-044 — `EXECUTE` on a new function is revoked, and the revocation is asserted
**Context:** Postgres grants `EXECUTE` on every new function to `PUBLIC`. Writing
`grant execute … to authenticated` therefore restricted nothing — it restated an access
`anon` already had. All 19 RPCs were reachable by an unauthenticated caller holding only
the publishable key. Each refused, because they call `app.require_actor()` first, but
"happens to fail closed" is a different claim from "cannot be called".
**Decision:** `PUBLIC` and `anon` lose `EXECUTE` on everything in `public` and `app`;
`authenticated` is re-granted exactly one reviewed list; `alter default privileges` keeps
the next function closed; and a migration **asserts** the result, failing if anything is
reachable that should not be — or if a reviewed function has quietly stopped being
callable. The API surface is declared in one place and restated in full whenever it grows.
**Consequences:** Proven over HTTPS: an anonymous `rpc/master_create` now returns
`permission denied for function master_create` rather than reaching the function at all.

## D-045 — RLS policies call a published helper, never the internal schema
**Context:** Every policy called `app.current_org_id()`. A policy expression is evaluated
with the **querying user's** privileges, and `authenticated` has no `USAGE` on `app` — the
schema is locked down precisely so it cannot be reached. Every table returned `403` for
every signed-in user. No data was exposed; the application was simply unusable, and no
static review had shown it.
**Decision:** `public.current_org_id()` is published and granted to `authenticated`;
policies use it. `app.current_org_id()` stays for use inside `SECURITY DEFINER` functions,
which run as the owner. A migration asserts that **no policy references `app.`**.
**Alternatives:** granting `authenticated` `USAGE` on `app` would have worked and would
have eroded the boundary the schema exists to draw, and broken the D-044 invariant.
**Consequences:** The lesson is recorded in the invariant itself, which now fails in both
directions — over-exposure *and* silent under-exposure.

## D-046 — Permission is decided before existence is revealed
**Context:** Every mutation RPC loaded the target row first and refused `unknown_entity`
when it was missing, only then checking capability. Normally a weak oracle, because ids
are random — but seeded master ids are UUID v5 values derived from public code paths
(D-040), so anyone can compute them and probe.
**Decision:** The cheap organisation-wide capability check runs **before** the row is
loaded. The precise unit-scoped check still runs afterwards, because it needs to know
which property the row belongs to; an administrator can therefore still distinguish
existence, which is appropriate.
**Consequences:** The server now refuses in the same order the Dart `Authorizer` always
has — permission, then ownership, then state. The two layers give the same answer for the
same reason.

## D-047 — Onboarding a user is a first-class administrative action
**Context:** `user_role_grant` requires a profile, and nothing created one except the
owner bootstrap. Preparing the authorisation tests would have meant inserting profiles
behind the authorisation model — exactly what must not happen.
**Decision:** `public.user_provision(email, full_name)` brings an **existing**
authentication account into the organisation, gated on an organisation-wide
`users.manage`. It never creates accounts and never sets passwords: sign-up and
credentials stay entirely inside Supabase Auth. `public.user_deactivate` is its
counterpart and deletes nothing.
**Consequences:** Every development identity used in the authorisation suite was created
through the ordinary signup path and enrolled through this RPC, so the tests exercise the
real administrative mechanism rather than a shortcut around it.

## D-048 — Revoked-scope cache policy: purge server-owned reference data, on confirmed authority only
**Date:** 2026-08-28 · **Status:** **Accepted (owner decision — Option A)**
**Context:** When the server confirms a user has lost a business unit, what happens to the
reference data already cached in the device's encrypted SQLite database? Three options
were put to the owner; **A — purge on the next successful authoritative refresh** was
chosen. Encryption at rest is not a reason to retain newly unauthorised data.

**Decision.** On a **successful** authority refresh that positively establishes the user's
current scopes, locally cached *server-owned* reference data belonging exclusively to a
revoked business unit is deleted: departments, sections, expense categories, revenue
categories, unit-scoped tax rules and period locks, and the business unit itself.

**`unknown ≠ revoked`.** Nothing is purged because the network failed, a refresh timed
out, a token could not be renewed or authority is simply unknown. This is enforced by the
type system rather than by discipline: `ScopeCachePurge.applyTo` takes an
`AuthorityRefresh`, which is a sealed type whose only purging branch is
`AuthorityConfirmed`. There is no signature that lets a caller purge on a timeout.

**The outbox is never touched.** Queued, failed, rejected, conflicted and attention-
required work is the user's, not the server's. The purge deletes only from a fixed list of
server-owned tables and *asserts* the outbox count is unchanged before returning, throwing
rather than continuing if it ever is not. A mutation queued while authorised and refused
on delivery becomes `OutboxStatus.rejected` — a new, terminal state distinct from
`conflict`, never auto-retried, never marked synced, and still inspectable with the
server's own reason attached.

**Transactional and bottom-up.** One transaction, children before parents, so there is no
moment at which a section hangs off a department that is already gone and no partially
purged hierarchy if anything fails. Verified with `PRAGMA foreign_key_check`.

**One deviation from the literal instruction, and why.** D-048 lists "scoped Vendors"
among the data to purge. Vendors are classified here as **organisation-global and
retained**, because:

* server-side, `vendors_read` is organisation-level — a manager who loses Crystal Canopy
  but keeps Hotel Krishna is still returned every vendor, so purging one locally would
  delete a row the very next pull restores. That is churn, not security;
* a vendor is a supplier of the **company**, not of a property. `default_business_unit_id`
  is a pre-selection for the entry form, and treating a UI convenience as a tenancy
  boundary is how a company-wide supplier list quietly fragments;
* D-048 §4 asks for the classification to be fixed rather than for exceptions to be added
  to the purge, so it is fixed in the classification.

What *is* done: a vendor's stale `default_business_unit_id` pointing at the revoked unit is
cleared, so the picker cannot offer a property the user can no longer reach. **If vendors
should genuinely become unit-scoped, that is a change to `vendors_read` and to the vendor
model on both sides — not a client-only deletion rule — and it needs the owner's decision.**

**Re-grant.** Restoring a scope re-downloads canonical server state. Because seeded ids are
derived (D-040), the same records return under the same ids and nothing duplicates. A
previously rejected mutation is **not** resurrected: authority returning does not re-assert
an intent the server already refused.

**Consequences:** `CacheClassification` names every local table and its owner, and throws
on an unclassified one — so a new table forces a decision about what an authority change
does to it, rather than defaulting into whichever behaviour is convenient.

## D-049 — A vendor is an organisation-global master; its default business unit is a convenience
**Date:** 2026-08-28 · **Status:** **Accepted (owner decision)**
**Context:** D-048 listed "scoped Vendors" among the data to purge on scope revocation.
Raised as a deviation, and the owner settled it: vendors are organisation-global.

**Decision.** A vendor may serve Crystal Canopy, Hotel Krishna Imperial, or both, without
duplicate master records — grocery, vegetable and water suppliers, electricians,
maintenance and stationery vendors all commonly serve both properties. `vendors_read`
stays organisation-level and is **not** redesigned as unit-scoped merely because a vendor
carries a default business unit.

`default_business_unit_id` is an optional operational pre-selection. It determines
**none** of: ownership, visibility, authorisation, accounting scope. A vendor stays
visible even when its configured default is outside the current user's scope.

**The refinement that matters (§2).** Losing access to a vendor's default unit must not
mutate the canonical vendor. No NULL is written, no row version moves, no audit event is
raised, and the default is not removed because one user lost scope — the vendor has not
changed. An earlier draft cleared the cached default during the purge; that was wrong on
two counts: it made the local row disagree with the server, and the very next pull would
restore it, producing an endless pull/clear/pull/clear cycle.

Instead the constraint is **derived per user** at the point of use:

```dart
String? effectiveDefaultBusinessUnitId(Set<String>? scopedUnits)
```

inside scope → the configured default; outside scope → null for that user's picker;
scope restored → the configured default becomes usable again on its own, with nothing
written to make it so. `null` scopedUnits means an org-wide holder — no restriction.
`hasUnreachableDefault` lets the detail panel say so quietly, rather than showing an
absent default that looks like a data fault.

**Consequence — a local schema correction (v5).** `vendors.default_business_unit_id` and
`vendors.default_category_id` were modelled as foreign keys with `ON DELETE RESTRICT`.
That made the revoked-scope purge impossible: deleting the business unit failed while any
vendor named it, so the only ways forward were to rewrite canonical vendor data (forbidden
by §2) or to leave the unit cached (defeating D-048).

A foreign key asserts "the target exists in this database". On a **per-user cache** that
is simply false — a manager scoped to one property legitimately holds vendors whose usual
property is the other one. Both columns are therefore **soft pointers**, resolved at the
point of use. A dangling value is expected and harmless. The server keeps its real foreign
keys, because there the assertion is true.

## D-050 — The outbox records who queued each intent
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** A shared Windows workstation in a back office sees several people sign in and
out of one installation. The outbox was anonymous, so nothing distinguished one person's
queued work from another's.
**Decision:** `sync_outbox.actor_user_id` (local schema v6). Sync sends only entries
belonging to the signed-in user; one person's queued work is never retried by, attributed
to, or shown as another's. Rows written before the column existed are unattributed and are
never sent by anyone — surfaced for a human rather than guessed at or discarded.
**Consequences:** Signing out and switching users never deletes queued work (D-048 §2),
and now it cannot be misattributed either.

## D-051 — Authentication, session lifecycle and fail-closed authority
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** `principalProvider` returned a hard-coded Owner holding every capability —
correct while no backend existed, a security defect the moment one did.
**Decision.** One `SessionState` machine drives the whole application: unauthenticated ·
authenticating · verifying · **unverified** · ready(confirmed|stale) · expired. Only
`SessionReady` yields real grants; every other state yields `Principal.anonymous`, which
holds nothing.

* **Fail closed (§8).** A user who authenticates on a device that has never received an
  authoritative snapshot gets *no* operational access — not a reduced menu, not a
  read-only view. Their permissions must never depend on whether their phone had signal.
* **Cached authority (§9).** A previously verified user works offline against permitted
  cached data, visibly stale, with privileged mutations pending rather than final. Cached
  authority is keyed by user id and `loadFor` returns nothing for anybody else, so the
  mistake cannot be made by forgetting a check.
* **Deactivation (§14).** The server declining to treat somebody as an actor is a
  *statement*, not a connectivity problem, so it never falls back to cache: the session
  becomes expired and the stored authority is cleared.
* **User switch (§16).** When a different user signs in on the same installation, the
  previous user's scoped cache is purged and their cached authority cleared **before**
  navigation opens. The outbox is untouched.
* **Session tokens** live in the platform-secure store — Android Keystore, Windows
  DPAPI — not shared preferences, because a refresh token is a bearer credential for
  company financial data (D-022).

**Enforcement:** `test/app/no_hardcoded_authority_test.dart` asserts over `lib/` that no
shipped file builds a `Principal`, references `RoleTemplates.owner`, or carries a
development identity. Test fixtures may do as they like; they are not in `lib/` and cannot
enter a build.

### Forced by the Phase 2 device acceptance (2026-08-28)

Five defects reached a green host suite, a clean `flutter analyze` and a review, and were
caught only by running the real signed application on a real device and a real desktop
against the real development project. They are recorded as decisions because each changes
a rule, not just a line of code.

## D-052 — The shipped seed does not run when a backend is configured
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** Start-up applied `seedMasterData` unconditionally, with a comment saying it
was safe "until the backend becomes the source of master data". The backend arrived and
the call did not change. The seed contains **both** properties, so every fresh
installation held a complete, browsable Hotel Krishna Imperial hierarchy before anybody
had signed in — and a Crystal Canopy-scoped Manager signing in afterwards inherited it.
Their own pull was correctly scoped by RLS; the seed was sitting underneath it.

This was invisible to the host suite, which seeds deliberately, and to the user-switch
tests, which happened to purge the seed on the way past. It appeared the moment a
scoped Manager was the *first* user on a clean install.
**Decision:** The seed runs only when `!config.hasBackend`. With a server, the server is
the source of master data and RLS decides what a user may cache. With no server, nothing
can authenticate anyway, so the seeded masters are development scaffolding rather than
somebody else's property.
**Alternatives:** purging the seed on first sign-in (fixes the symptom, leaves a window in
which it is browsable); marking seeded rows and filtering them (two kinds of master row,
and every query has to remember which it is looking at).
**Consequences:** The offline-with-no-backend build is unchanged. A build *with* a backend
shows nothing until authority is confirmed, which is exactly the fail-closed behaviour
D-051 requires. `test/app/no_hardcoded_authority_test.dart` asserts the guard is present
and that nothing else in `lib/` applies the seed.

## D-053 — Signing out takes the downloaded scope cache with it
**Date:** 2026-08-28 · **Status:** Accepted — amends D-051 §16
**Context:** D-051 purges the previous user's scoped cache when a *different* user signs
in, by comparing the cached authority's owner against the new user. But `signOut()`
clears the authority store. So after an ordinary sign-out there was no recorded owner, the
comparison found nothing to compare, and the purge never ran. On a real Android device:
the Owner signed out, a Crystal Canopy-only Manager signed in, and Hotel Krishna Imperial
was still in the local database.

The isolation rule was correct and its trigger was unreachable — the only sequence that
could fire it (switching users *without* signing out) is one the interface cannot produce.
**Decision:** `signOut()` purges the scoped cache **before** clearing the authority store,
while the device still knows whose cache it is. The sign-in-time check stays as
defence in depth.
**Reason:** Nothing is lost. The same user signing back in online re-pulls what they are
entitled to; offline they would have no cached authority to work under in any case,
because sign-out clears that too.
**Consequences:** The outbox is still never touched — queued work survives sign-out,
sign-in as somebody else, and back again, attributed throughout (D-050). Covered by two
host tests that fail without the fix.

## D-054 — Both shells state who is signed in, and offer a way out
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** Phase 2's first integration shipped with **no sign-out control anywhere**.
`signOut()` existed and was reachable only from the "access not verified" screen. A
signed-in user could not leave. On a shared back-office workstation that is not a missing
convenience — it is how the next person's takings get entered under somebody else's
account — and it made every user-switch rule in D-050 and D-053 unreachable in practice.
**Decision:** One `AccountControl`, in the Windows sidebar footer and on the Android
"More" screen (master spec §18): the signed-in email, the scope in the permission model's
own language ("All business units" / "1 business unit"), the staleness chip when access is
not fresh, and Sign out behind a confirmation that says how many queued entries are being
kept rather than sent.
**Reason:** The identity belongs in permanent chrome, not behind a menu. Somebody has to
be able to see whose session is open *before* they type a figure into it.
**Consequences:** The confirmation names the pending count and states plainly that nothing
queued is deleted. Never a role name — the scope line is derived from grants, per D-025.

## D-055 — `user_reactivate` is the counterpart of `user_deactivate`
**Date:** 2026-08-28 · **Status:** Accepted — extends D-047
**Context:** D-047 gave the Owner `user_deactivate` and no way back. Suspending somebody —
a manager on leave, or a mis-click — was a one-way door through the API, and the only
remaining route was direct table access, which no client holds and which writes no audit
row.
**Decision:** `public.user_reactivate(user_id, mutation_id)`, deliberately symmetric with
its counterpart: the same unscoped `users.manage` guard, the same idempotency key, the
same audit shape. It restores nothing else — role grants are separate records and any that
were revoked stay revoked.
**Consequences:** The API surface invariant (D-044) is restated to 24 functions. The
migration audit refused the addition until the reviewed list named it, which is the
invariant working.

## D-056 — Every migration the server has applied must exist in the repository
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** `my_authority()` — the single call the whole authorisation model depends on,
and the only thing permitted to trigger a destructive local purge (D-048) — had been
applied to the development project and **never committed**. For a day the repository could
not have produced a working staging or production environment, and nothing would have
said so until a deploy failed.

Governance already states that the repository is the source of project state
(`CLAUDE.md` §1). What was missing was anything that checked.
**Decision:** The function is recovered into `supabase/migrations/` verbatim from the
server's own migration record, and the live suite asserts that every RPC the server
exposes is created by a committed migration. A `--history` secret scan already covered
what must not be in the repository; this covers what must.
**Consequences:** Applying a migration through any route other than a committed file is
now a failing test rather than an invisible divergence. The API surface invariant is
restated to include `my_authority`, which the earlier restatement had silently dropped.

---

# Phase 2 acceptance addendum and governance correction (2026-08-28)

## D-057 — Project lead, business, project and domain, stated precisely
**Date:** 2026-08-28 · **Status:** Accepted (project-lead instruction)
**Context:** The governance header of every canonical document read `Owner: Shoyeb
Akhtar`. That is wrong in a way that matters: it reads as a statement about who owns
Hotel Krishna Imperial, which this repository has no business asserting. It also collided
with `Owner`, the unscoped RBAC grant in spec §13.2, so one word carried two unrelated
meanings across a body of security-sensitive documentation.
**Decision:** The canonical facts are:

| | |
|---|---|
| Project Lead / Product Decision-Maker | Shoyeb Akhtar |
| Business | Hotel Krishna Imperial |
| Project | Krishna Imperial MIS |
| Domain | hotelkrishnaimperial.in |

No document states or implies that the project lead is the proprietor of the business.
The **application role named `Owner`** — capitalised, the unscoped grant only that role
may hold (D-025) — is untouched: it is a permission level in the software and says nothing
about anyone's relationship to the business. The `owner` role code, `RoleTemplates.owner`,
`app.bootstrap_owner` and every capability grant keep their names.

The application id **`in.krishnaimperial.mis`** is unchanged (D-029), and the product
remains native Android and Windows (spec §2). A domain is not a deployment target: nothing
about `hotelkrishnaimperial.in` implies a web build, and none is produced.
**Consequences:** Forward-looking prose — `CLAUDE.md`, the master spec, `PROJECT_STATUS`,
`ARCHITECTURE`, `DATABASE_SCHEMA`, `RELEASE_CHECKLIST`, `README` — now says "the project
lead". Historical decision entries in this log are **not** rewritten, because this log is
append-only by governance; where an older entry says "the owner" in lower case it means
the project lead, and `CLAUDE.md` says so explicitly. Three lower-case uses of "owner"
survive on purpose and mean something else entirely: the role code in a schema comment,
the Postgres object owner a `SECURITY DEFINER` function runs as, and the user a cached
authority snapshot belongs to.

## D-058 — Offline behaviour is proven by injecting the transport, not by changing the machine
**Date:** 2026-08-28 · **Status:** Accepted — closes the one gap the Phase 2 report left open
**Context:** The Phase 2 completion report recorded Windows offline acceptance as **Not
tested**, honestly and deliberately: on Android the emulator's radios can be switched off
from the host, and on Windows the equivalent is either removing the build machine's own
network — which severs the tooling driving the run — or adding a firewall rule, which is a
machine security setting this project will not change unattended.
**Decision:** `bootstrap({http.Client? transport})`. The acceptance suite passes an
`http.Client` that throws the platform's own `SocketException` from inside `send`; nothing
else in the repository ever passes one.

**Why this is an injection point and not a backdoor.** It is a *parameter*. There is no
environment variable, no `bool.fromEnvironment`, no global registry, no debug menu and no
runtime switch: the only way to reach it is to call `bootstrap` with an argument, and the
only caller that does lives in `integration_test/`, which is not compiled into the
application. `main()` calls `bootstrap()` with none. Three tests in
`test/app/no_hardcoded_authority_test.dart` hold that closed — nothing in `lib/` passes a
transport, `main()` passes no arguments at all, and `lib/` contains no acceptance flag or
offline switch of its own.

**Why it is honest.** Nothing is faked above the cable. The real Supabase client builds the
real request, the throw is the same exception an unreachable host produces, and every
decision after it is made by the shipped code for the shipped reason: the real
classification in `SupabaseGateway`, the real `AuthorityRefresh.unavailable`, the real
"unknown ≠ revoked" branch in `ScopeCachePurge`, the real backoff, the real refusal
mapping. The alternative — asserting Windows offline behaviour from Android and shared
code — would have been an argument, not a test.
**Consequences:** The addendum runs on both platforms and proves the same fourteen points
on each. `ARCHITECTURE.md` §12 limitation 7 is withdrawn.

## D-059 — The outbox has a real transport, and it sends only its owner's work
**Date:** 2026-08-28 · **Status:** Accepted — completes D-050
**Context:** Two gaps surfaced while building the addendum, both invisible while every
master mutation was made online by a person watching the result.

First, `SyncEngine` had **no real `RemoteMutationEndpoint`** — only a fake used by tests.
Nothing joined the durable outbox to the gateways, so work queued offline would have sat
there forever. That is survivable in an online-only workflow and indefensible in an
offline-first one.

Second, D-050's actor filter existed on `OutboxRepository.dueEntries` and the engine never
passed it. The rule was written down and not enforced: whoever happened to be signed in
when connectivity returned would have pushed somebody else's queued financial intent under
their own session, and the server would have attributed it to them.
**Decision:** `MasterMutationEndpoint` dispatches one queued intent to the RPC that
corresponds to it, passing the intent's own `mutation_id` (so a redelivery replays rather
than applying twice) and its `base_row_version` (so a stale intent is a conflict rather
than an overwrite). It performs no business arithmetic and invents no retry. Its whole
substance is one translation table, and the security-relevant row is the last one: an
**unreachable** transport is a transient failure, never a refusal, because "we could not
tell" must never look like the server saying no (D-048 §1).

`SyncEngine.actorUserId` is now supplied from the session, and `syncEngineProvider` rebuilds
whenever the session changes, so a second person signing in on the same installation gets a
worker that can see only their own queued work.
**Consequences:** A queued mutation now genuinely reaches the server, and the addendum
proves the whole round trip on both platforms: refused while offline as transient, retried
after its real backoff elapses, applied once when permitted, and recorded as terminal
`Rejected` — never `Conflict` — when the server declines the act itself.

---

# Phase 3 — Expense Engine decisions (2026-08-29)

## D-060 — Period contributions are the only reporting source
**Date:** 2026-08-29 · **Status:** Accepted (project-lead correction)
**Context:** The Phase 0 design stored `pnl_date` on the document and, separately,
allowed optional cross-period allocations (D-034). Read literally that is two reporting
sources for one amount: a ₹60,000 line split ₹30,000 May / ₹30,000 June would contribute
₹30,000 to each period *and* ₹60,000 against its document date, and any report that
touched both would count ₹120,000. The project lead required that double counting be
prevented **by construction** rather than by every query being careful.
**Decision:** Every allocation line carries at least one period contribution, always.

* No deliberate split → the server generates **one** contribution for the whole amount,
  covering the document's own accounting period (or its business date), marked
  `is_derived = true`. The user never sees it and never needs the
  `expense.allocate_periods` capability for it.
* A deliberate split → one contribution per period, `is_derived = false`, gated by that
  capability and audited.

**Reporting reads `expense_period_allocations` and nothing else.** There is no
document-level `pnl_date` column on the expense at all, and `ExpenseDocument` exposes no
such property — so no caller can sum a line amount against one date and its contributions
against theirs. `SUM(contributions) = line amount` is a deferred constraint trigger, so a
transaction that would unbalance it cannot commit.
**Alternatives:** keeping `pnl_date` on the document and excluding split lines in every
query (one forgotten `WHERE` is a wrong P&L, and nothing would fail loudly); a view that
unions the two shapes (same risk, hidden one layer down).
**Consequences:** The default case costs one extra row per line, which is the price of
there being exactly one place the money lives. `public.expense_period_contributions` is
the named projection reports will consume, so "what do I sum?" has one answer.

## D-061 — Cross-unit allocation is its own capability
**Date:** 2026-08-29 · **Status:** Accepted
**Context:** Spec §7 allows one expense to charge both properties. Holding scope on both
was the obvious gate, and it is not enough: a manager covering both properties
operationally would silently acquire the ability to decide how a shared cost is
apportioned between two businesses, which moves both of their operating profits.
**Decision:** `expense.allocate_cross_unit`, granted to Accountant and the Owner role and
deliberately not to Manager or Data Entry — the same line `expense.allocate_periods`
already draws, for the same reason. Scope on every unit named remains necessary; this is
what makes it sufficient.
**Consequences:** A Crystal Canopy-only manager is not offered Hotel Krishna as a split
target and is refused `KM002` if a modified client tries; a manager holding both scopes is
offered the split flow only if they also hold the capability, and is refused `KM001`
otherwise. Both proven against the real server.

## D-062 — The local read model is a sibling of the server schema, not a copy
**Date:** 2026-08-29 · **Status:** Accepted (project-lead requirement)
**Context:** The server projection already withholds the header total from a unit-scoped
user, because on a two-property bill `total − own share` is the other share. A local
cache that stored the total anyway would undo that protection, and "the widget does not
display it" is not protection at all — a raw SQLite file is readable with a text editor.
**Decision:** The local expense header carries `visibility ∈ {complete, scoped}`, a
nullable `document_total_minor` and a non-null `visible_amount_minor`, with a **SQLite
check constraint**: a `scoped` row carrying a document total is refused by the database.
Withheld allocation lines and contributions are absent rather than filtered — the server
never sends them, so they cannot be on the device.
**Documented divergences from Postgres, each deliberate:**

| Local | Server | Why |
|---|---|---|
| no `SUM(lines) = total` constraint | deferred trigger | a scoped record deliberately does not sum to the document |
| `pending_mutation_id` | — | sync state is *derived* from the outbox, never duplicated into a column that could disagree |
| `category_id` is a soft pointer | real foreign key | a scope purge (D-048) legitimately removes masters while synced history remains (same reasoning as D-049) |
| attachment staging columns | — | staging is a client concern by definition |

**Consequences:** Proven by syncing one ₹58,000 shared bill into three separate local
databases and reading the **bytes** of each: the Crystal Canopy device holds 2,500,000 and
neither 3,300,000 nor 5,800,000; the Hotel Krishna device the converse; the Owner the whole
document. A future writer cannot reintroduce the leak by forgetting a null.

## D-063 — Original attachments are complete-document-only
**Date:** 2026-08-29 · **Status:** Accepted (project-lead requirement)
**Context:** An attachment is the whole bill. The shared electricity invoice says ₹58,000
on its face, so handing the image to a manager entitled to ₹25,000 gives away exactly what
the projection withholds — in a form no database policy can redact.
**Decision:** A user who receives a **scoped** projection of an expense does not receive
its attachments. Not "receives them with the button hidden": the Storage policy returns
nothing, and the `expense_attachments` table policy returns no row. The predicate is
literally the same one the header projection uses for `is_complete`, so an attachment can
never be readable by somebody the document itself is only partly visible to.

The bucket is private. The object path is derived and predictable
(`org/{org}/expenses/{expense}/{attachment}.{ext}`) and that is fine — path secrecy is not
authorisation, and a client has to be able to name what it just wrote. No client role holds
DELETE on the bucket.
**Consequences:** A redacted or per-unit attachment feature is a *feature*, with its own
decision, not something to be approximated by trimming an image. Verified by attempting a
direct Storage download as a scoped manager and being refused.

## D-064 — Usage means two different things, and both are kept
**Date:** 2026-08-29 · **Status:** Accepted (project-lead correction)
**Context:** The first implementation decremented `master_usage_counters.transaction_count`
on void, which would have quietly erased the evidence the D-038 rename warning is built on:
a category used four hundred times and voided once would report three hundred and
ninety-nine, and a category whose only entries were later voided would report zero — as
though it had never been used.
**Decision:** Two figures.

* `transaction_count` is **historical**: how many accepted lines have ever referenced this
  master. It never decreases. A voided expense still happened.
* `active_count` is **current**: how many live, unvoided lines reference it now. A void and
  an edit that drops a line both decrement it.

D-038's rename warning reads the historical figure. A "can I stop using this?" question
reads the active one.
**Consequences:** `app.record_master_usage` takes both deltas; a void passes `(0, -1)`. The
superseded five-argument signature had to be dropped, because with a defaulted sixth
parameter every existing five-argument call became ambiguous — caught by the live suite.

## D-065 — The edit window is inclusive of its last day
**Date:** 2026-08-29 · **Status:** Accepted — closes the gap the Phase 3 checkpoint recorded
**Context:** "Seven days" is ambiguous until it is written down and tested. The Phase 3
checkpoint recorded the boundary as untested and said so rather than implying otherwise.
**Decision:** `elapsed = current_date − business_date`, in whole calendar days.

```
elapsed <= edit_window_days   permitted
elapsed >  edit_window_days   refused KM021
```

So a business date of D is editable on **D+7** and refused on **D+8**.
`transaction.correct.beyond_window` lifts the *age* rule and nothing else: the period lock
is checked afterwards and is **never** bypassed. `edit_window_days` remains configuration
(`org_settings`), not a constant.
**Consequences:** All four cases proven against `krishna-mis-dev`: seven days permitted,
eight refused `KM021`, thirty days permitted for a holder of the capability, and a closed
period refusing `KM004` even for that holder. Building the test found a real defect —
`expense_update`'s non-enumerating pre-check asked for `expense.edit.own` specifically, so
an Accountant, who holds `expense.edit.all` and not `expense.edit.own`, was refused before
the document was loaded. The pre-check now accepts either form.

## D-066 — Development acceptance leaves audit evidence, and it is not erased
**Date:** 2026-08-29 · **Status:** Accepted (project-lead requirement)
**Context:** Device acceptance creates real documents in `krishna-mis-dev` and therefore
real audit rows. `audit_logs` is append-only by trigger and correctly refuses deletion.
**Decision:** The audit trail is never edited to make the development database look tidy.
Acceptance-generated events are recognised, without weakening audit integrity, by what is
already recorded on them:

* the **actor** — every development identity is an `@example.com` address, or the single
  named development Owner, and no such account exists outside the development project;
* the **environment** — the rows live in `krishna-mis-dev`, which is a separate Supabase
  project from staging and production and shares no data with either (spec §3);
* the **reason text** on every reversal a test performs, which names the acceptance run.

No mutable `is_test` flag is added to audit history. The fixtures a run creates — the
expense documents themselves — *are* removed afterwards, because they are development
scaffolding rather than history; the audit rows recording that they existed remain, which
is exactly the asymmetry the append-only guard is for.
**Consequences:** A run ends with the development project's financial tables at baseline
and its audit trail longer. That is the correct outcome and is documented here so it is
not mistaken for contamination.

---

# Phase 3 — decisions forced by the device acceptance (2026-08-30)

Each of the three below is a defect the acceptance found in code that had already passed
review, a clean `flutter analyze` and a green host suite. They are recorded as decisions
because each changes a rule, not merely a line.

## D-067 — The edit window is measured under the property's business date
**Date:** 2026-08-30 · **Status:** Accepted — **amends D-065**
**Context:** D-065 fixed the *boundary* of the seven-day window — D+7 permitted, D+8
refused — and wrote the rule as `elapsed = current_date − business_date`. It did not ask
what `current_date` means. It means the **database session's** calendar date, and this
database's session timezone is UTC:

```
select current_setting('TimeZone')   →  UTC
```

The properties are `Asia/Kolkata` (UTC+05:30) with an 05:00 cut-off, so the UTC calendar
date lags the property's own business date for part of every night. Measured against the
real configuration, the two disagreed for **thirty minutes a day, 05:00–05:29 IST**, and
inside that window an entry that was D+8 old counted as D+7 and was **wrongly accepted for
edit**.

**Thirty minutes is not the point.** The window is that narrow only because the +05:30
offset and the 05:00 cut-off happen to cancel out, and both are configuration (spec §9). A
unit with a midnight cut-off is misjudged for **five and a half hours a day**; a unit in a
zone west of UTC is misjudged the other way, refusing edits that are still inside the
window. Correctness cannot rest on a coincidence between two independently editable
settings.

**Decision:** "Today", for the edit window, is the **property's current business date**,
derived exactly as spec §9 derives it for a new entry — `now()` in the unit's IANA
timezone, stepped back one calendar day when the local time is before that unit's cut-off.
`app.business_date_at(instant, timezone, cutoff)` is the server half of
`BusinessDate.fromInstant`, and takes the instant as a parameter so the rule is testable at
04:59, 05:00, 23:59 and 00:01 without waiting for those times to arrive. Migration 0033
asserts all four, plus the 05:15 case this decision exists for.

Deriving it through the cut-off — rather than simply using the property's calendar date —
is what makes the two layers consistent: an expense recorded this second has `elapsed = 0`
instead of having already spent a day of its window.

A shared bill charges more than one property and each property's books are protected
separately, so the window must be open for **every** unit the document touches. The
comparison uses the greatest business date among them: the strictest reading, never the
most permissive.

**Alternatives:** setting the database session timezone to `Asia/Kolkata` (moves the
coincidence rather than removing it, and silently changes every other date expression in
the schema); comparing against the property's plain calendar date (disagrees with the
cut-off, so a just-recorded entry starts a day into its window).

**Consequences:** `current_date` no longer appears anywhere in the schema. Both helpers
live in `app`, which `authenticated` cannot reach, so the reviewed API surface (D-044) is
unchanged — and the migration asserts that, in both directions.

The migration was **refused on its first application** by its own assertion: Postgres had
granted `PUBLIC EXECUTE` on both new helpers. `alter default privileges … in schema app`
was set by 0024 and did not cover them, because `ALTER DEFAULT PRIVILEGES` applies only to
objects created by the role that ran it, and these arrived over a different connection. The
revoke is now explicit and lives in the same file that creates the functions, so it cannot
depend on who holds the connection. **A default privilege is not a guard; it is a default.**

## D-068 — Financial documents are scoped, and retained; their unit pointer is soft
**Date:** 2026-08-30 · **Status:** Accepted — completes D-048's classification
**Context:** Signing out on a device that had synced an expense **threw**:

```
DELETE FROM business_units WHERE id IN (?, ?)  →  FOREIGN KEY constraint failed
```

`expense_allocations.business_unit_id` was a real foreign key with `ON DELETE RESTRICT`,
while `category_id` — the column immediately below it, in the same classification, for the
same reason — was deliberately a soft pointer (D-062). The scope purge deletes the units a
user no longer holds, and at sign-out all of them (D-053), so the restrict fired. On a
shared back-office workstation that is the ordinary sequence, and it is precisely the one
D-054 added the sign-out control for.

Underneath it was a second, quieter defect. D-048 promised that `CacheClassification`
"names every local table and its owner, and throws on an unclassified one — so a new table
forces a decision about what an authority change does to it". The test that was supposed to
hold that promise iterated `CacheClassification.tables` and asserted each entry was in
`CacheClassification.tables`. It is true by construction and proved nothing. Phase 3 added
four expense tables, none of them was classified, and the suite went on passing.

**Decision, in three parts.**

1. **`business_unit_id` on an allocation line is a soft pointer**, like its neighbour. A
   foreign key asserts "the target exists in this database"; on a per-user cache that is
   simply false, and a retained line may legitimately outlive the cached unit it names.
   The server keeps the real key, where the assertion is true. Local schema **v8**.
2. **The four expense tables are classified `scopedFinancialHistory` and are retained.**
   Not `businessUnitScoped`, because that value means *purged*; not `organizationGlobal`,
   because that would be untrue and would mislead the next reader. The purge is limited to
   server-owned **reference** data, which the server hands straight back when authority
   returns — "nothing a person typed is ever in scope" was already the stated limit, and an
   expense is something a person typed.
3. **The completeness guard now runs against the real schema**, comparing the classified
   set with `AppDatabase.allTables` in both directions. A promise nothing evaluates is a
   comment.

**A question left open for the project lead.** *(Answered 2026-08-30 by D-070, which
reverses the retention below: synced financial data for a revoked unit is now purged at
the confirmed authority refresh, and only the actor's own unsent work is kept. This
paragraph is left as written, because this log is append-only.)* This retains a revoked
manager's cached expense amounts for the property they have lost. It follows from D-048 as written, and the
alternative — purging scoped financial history too — is defensible on the same security
reasoning that chose Option A. It is a retention decision about financial data, so it is
his to make, not one to be settled by an implementer reading between two documents. If he
wants it purged, it is one line in `CacheClassification` plus a delete step, and part 1
above is required either way.

**Consequences:** Sign-out works on a device holding expenses. The atomicity test that used
the dropped foreign key to force a mid-transaction failure now forces one with a duplicate
allocation primary key: the rollback path under test is unchanged, only the way the test
reaches it.

## D-069 — The secret scan proves its own controls on every run
**Date:** 2026-08-30 · **Status:** Accepted
**Context:** The first Windows **Release** build of Phase 3 produced an AOT snapshot, and
the scan reported a Postgres connection string with a password inside `app.so`. It was a
297-character false positive: `AppConfig`'s classifier contains the literal `postgres://`
precisely so it can *refuse* a connection string, and in an AOT string table that literal
is interned beside unrelated symbols. The pattern's trailing `[^\s@]+` ran across the
separator bytes and reached the `@` in `_timeZoneOffsetInSeconds@0150898`, assembling a
"password" out of `Error_trySetStackTrace`, `StreamTransformerBase` and `HctSolver`.

This is the same class of defect the Phase 2 acceptance recorded and fixed for
`sb_secret_`. The fix then was a `verify` hook; the Postgres pattern never got one.

**Decision:** The pattern gains a verifier — a real connection string is short and
contiguous, and every character between the scheme and the `@` is legal in a URI userinfo,
so one byte outside that set means the match has left the string it started in.

And because every `verify` hook makes the scan **narrower**, the tool now runs a
**self-test on every invocation**, not behind a flag: five control credentials it must
still catch, and two look-alikes it must not. If any control fails it exits 2 and reports
which, because *a scan that has quietly stopped matching reports "clean" just as
confidently as a scan that is working*. Verified by deliberately over-narrowing the
verifier and watching the run refuse itself.

**Consequences:** Narrowing a pattern to silence a false positive can no longer narrow it
past the real thing without saying so. Acceptance builds carry the development identity
passwords in `kernel_blob.bin` and are still proven non-distributable by the same tool;
the distributable artefacts are rebuilt without the identity defines and scanned clean.

---

# Phase 3 — the project lead's retention decision, and what closing it found (2026-08-30)

## D-070 — Financial cache retention: synced financial data is purged on revocation
**Date:** 2026-08-30 · **Status:** Accepted (project-lead decision) — **answers the open
question D-068 left for him, and reverses what the Phase 3 checkpoint shipped**
**Context:** D-068 classified synced expense documents as retained through a confirmed
scope revocation, on the reading that the purge covered server-owned *reference* data and
that "nothing a person typed is ever in scope" (D-048). It said plainly that the opposite
reading was defensible on the same security grounds, that it was a retention decision
about company financial data, and that it was therefore the project lead's to make rather
than an implementer's.

**He decided the other way.**

**Decision.** After a **confirmed** authoritative scope revocation, server-owned synced
financial data for the revoked business unit no longer remains in that user's normal
browsable local cache. This happens at the authority refresh — **not** deferred to
sign-out. The sequence is unchanged in shape and stricter in effect:

```
authority refresh confirmed
  -> determine revoked scopes
  -> purge the unauthorised canonical financial cache
  -> render only what is currently authorised
```

In scope: synced expense headers, allocation rows, period-contribution rows, attachment
metadata, the locally cached attachment **files** the user may no longer retrieve, and any
future server-owned financial read model. `unknown != revoked` is unchanged and remains
enforced by the type system: `applyTo` takes an `AuthorityRefresh`, whose only purging
branch is `AuthorityConfirmed`, so a timeout still deletes nothing.

**What is preserved, and why it is a different kind of thing.** Pending, rejected and
conflicted mutations — and the locally authored document rows needed to inspect and
reconcile them — are **not** destroyed because access changed. They are user-owned
attempt state, not canonical server-owned read data: the server hands a synced expense
straight back when authority returns, and it can never hand back an intent it never
received. Such a document is:

* retained **whole**, because a half-deleted document cannot be inspected or reconciled,
  which is the only reason it was kept;
* stamped `expenses.scope_revoked_at` (local schema **v9**);
* removed from **every** canonical financial read — the ledger, the filtered query, the
  contribution totals — so it is never browsable as though it were still authorised;
* still tied to its original `actor_user_id`, so another user signing in on the same
  installation can neither see it in their ledger nor push it (D-050);
* reachable only through `listRetainedAfterRevocation`, the dedicated
  pending / rejected / conflict workflow.

A mutation refused after its permission was withdrawn still becomes terminal `Rejected`
and is still not deleted. Restoring the scope clears the stamp and the document becomes
browsable again; a shared document becomes browsable only when **every** property it
charges is reachable, which is the strict reading.

**The partially revoked shared bill.** A manager losing Crystal Canopy while keeping Hotel
Krishna keeps the Hotel Krishna share and loses everything else — and the header is
**downgraded from `complete` to `scoped` with its document total nulled**. This is not
tidiness. A complete header of ₹58,000 beside a single surviving line of ₹33,000 publishes
₹25,000, which is precisely the share just revoked and precisely the arithmetic the local
read model exists to make impossible (D-062). Attachments go with the downgrade, on the
predicate they already had: complete-document-only (D-063).

**Alternatives:** purging at sign-out only (leaves the revoked property's figures
browsable for as long as the session lasts — the thing the decision rejects); deleting the
unsent work too (destroys the only copy of something a person did, and D-048 §2 has never
allowed it); filtering at query time instead of stamping (every future query must
remember, and one that forgets is a silent leak).

**Consequences.**
* `CacheOwnership.scopedFinancialHistory` now means *purged, sparing unsynced work*. It
  keeps its own name rather than folding into `businessUnitScoped`, because the exception
  is the whole policy.
* Local schema **v9** adds `expenses.scope_revoked_at`.
* `PRAGMA secure_delete = ON` is now set on the local database. Without it the purge was
  **weaker than the projection it protects**: the deleted rows stayed legible in freed
  pages, and D-062's argument was explicitly about what a raw database file reveals. Found
  by writing the byte-level test, and confirmed by breaking the pragma and watching the
  revoked ₹25,000 reappear in the file.
* Staged attachment bytes are reclaimed **after** the transaction commits, because a
  rollback cannot put a deleted file back.
* Proven on both real clients against `krishna-mis-dev`: the Owner's complete ₹58,000
  invoice does not survive into a scoped manager's session, and a manager holding both
  properties who loses one keeps ₹33,000, loses the ₹25,000 and the ₹58,000, keeps their
  own unsent intent, and sees no foreign-key failure on the way through.

## D-071 — Acceptance fixtures are reversed, and the phase proves it
**Date:** 2026-08-30 · **Status:** Accepted
**Context:** D-066 and `PROJECT_STATUS.md` both stated that the expense documents an
acceptance run creates "are removed afterwards". They were not. The `expense-cleanup`
phase signed in and ran `expect(true, isTrue)`; the list it was meant to consume,
`_createdExpenses`, is populated per process, and **each phase is its own process
launch**, so by the time cleanup started that list was always empty. The documentation
described an intention that nothing carried out — the same shape of finding as D-059 and
D-068's classification guard: *a rule that nothing evaluates is a comment*.
**Decision:** Every document an acceptance run creates carries a marker in its notes, and
the cleanup phase finds them by that marker — the one identifier that survives a process
boundary — and **voids** them, then asserts none remain open. Void rather than delete,
because financial history is corrected by void plus audit and never by deleting rows
(spec §14, D-006); the reason text names the run, which is exactly the identification
D-066 specifies. A document a closed period refuses is reported by id and reason rather
than swallowed or failed on.
**Consequences:** The phase reads through `expense_document`, never `expenses` — no client
role holds SELECT on the base table, and the first version of this fix was refused
`42501`, which is the D-062 boundary working. The append-only audit rows remain, and that
asymmetry is the point of the guard. The entry form's notes and reference fields gained
keys so the marker can be typed through the real field rather than injected behind it.
Verified: a run ends with `reversed N of N`, and the assertion that none remain open is
what would fail if it ever stopped working.

## D-072 — The expense **edit** surface does not exist, and that is a Phase 3 gap
**Date:** 2026-08-30 · **Status:** **Open — requires the project lead's decision**
**Context:** `PROJECT_STATUS.md` records Phase 3 slices 8–13 as "the Android entry
surface, the Windows ledger and detail, **edit/void**, cross-business and cross-period
allocation, and the audit presentation … built and committed (`3871b9f`)". Writing the
Windows edit/void acceptance found that the edit half is not built.

What exists: `public.expense_update` on the server, fully implemented and proven — the
live suite exercises the D+7 / D+8 boundary, the beyond-window capability and the closed
period against `krishna-mis-dev`, and migration 0033 pins its date basis (D-067).
`ExpenseGateway.update` exists. `ExpenseMutationEndpoint` can dispatch a
`MutationOp.update` intent.

What does not exist, anywhere in `lib/`: any way to *produce* that intent.
`ExpenseRepository` has `createLocally`, `voidLocally`, `load`, `list`, `query`,
`listRetainedAfterRevocation` and `contributionTotal` — and no update. The detail panel's
`_Actions` renders **Void alone**, under a comment that says "Edit and Void". No route, no
control, no draft-loading path, no `base_row_version` plumbing from a client.
`ExpenseGateway.update` is called only from the live suite and one acceptance assertion.

So a user cannot edit an expense on either platform, and the seven-day edit window — the
subject of D-026, D-065 and D-067 — governs a client operation that has never been built.

**Why this is recorded rather than fixed in passing.** An expense edit is not a missing
button. It needs a draft loaded from a possibly-scoped projection, allocation and
period-contribution editing under the same reconciliation rules as entry,
`base_row_version` carried from load to submission, conflict presentation when it is
stale, period-lock and edit-window prediction, an outbox intent, and reconciliation of the
server's answer — in a financial system, under D-021's concurrency semantics. Building
that unreviewed, inside a task the project lead scoped as *verification of an existing
surface*, would be a large unilateral change to how company financial records are
corrected.

**What is blocked by it:** the edit half of the Windows edit/void acceptance, and the
"Windows updates it / Android submits a stale mutation" steps of the two-device acceptance
**as specified through the UI**. The server-side equivalents of all of these are already
proven; what cannot be proven is a client path that does not exist.

**The decision required:** whether to build the expense edit surface as the Phase 3 slice
it was recorded as, or to descope it explicitly — in which case `PROJECT_STATUS.md` must
stop claiming it, and the edit window's client-side rules should say plainly that they
predict a server operation the client cannot yet issue.
