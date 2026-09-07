# Decision Log

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2**
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
**Date:** 2026-08-30 · **Status:** **Answered 2026-08-30 — build it. See D-072a for the
rules it was built to, and `PROJECT_STATUS.md` for the acceptance.** The text below is the
question as it was put, and is left unedited because this log is append-only.
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

**Answered 2026-08-30: build it.** The project lead directed that expense editing is part
of the approved V1 model and must be operational before Phase 3 can close. Built and
proven on both real clients — see the entry below for the rules he set with it, and the
three defects that only an edit could expose.

## D-072a — The rules the edit surface was built to
**Date:** 2026-08-30 · **Status:** Accepted (project-lead decision)

**A scoped share of a shared expense is read-only in V1.** A Crystal Canopy manager
holding `Your allocation ₹25,000` of a ₹58,000 invoice may not open it in an editable
form. They cannot reconcile a document whose total they are not entitled to see, and the
three things that would make it possible are all refused: nothing reconstructs the
withheld figure, nothing re-fetches the complete document because Edit was pressed, and
"edit my allocation only" is a separate collaborative workflow that V1 does not have. The
refusal lives in three places — the control is absent, `draftFor` returns
`EditRefusal.scopedProjection`, and `updateLocally` refuses at the write — and the server
refuses a forged attempt regardless, which is where the boundary actually is (D-037).

A document wholly inside one property the user holds is `complete` *for them*, and is
editable under the ordinary rules. "Complete" describes what this device was given, not
how many properties the invoice charges.

**One form, two modes.** `ExpenseEntryPage.editing` takes a draft loaded from an existing
document. The reconciliation rules, the period editor, the capability gates and the
allocation editor are the ones that already decide what a create may do. A second
implementation of the arithmetic behind company profit is the thing that must not exist.

**The version is captured once, at open, and never re-based.** `copyWith` cannot move it —
every keystroke rebuilds the draft, so offering it there is precisely how a background
sync would silently re-base somebody's edit. A stale intent therefore reaches the server
as `KM003`, becomes `Conflict`, and the user is shown what they entered beside what the
record now says, with one deliberate action: review the latest and apply the correction
again. Nothing is merged; the server's copy is never overwritten.

**Attachments are evidence, not form state.** An edit adds attachment rows and never
replaces or removes them. V1 offers no destructive attachment removal at all.

**Void stays a separate mutation**, unchanged: its own RPC, its own capability, a
mandatory reason, `base_row_version`, and immutability afterwards.

**Three defects the edit path exposed, none of which a create could have.**
1. `reconcileAcceptance` wrote every field of the server's answer. `expense_update`
   returns only `row_version`, so each edit erased the server-issued transaction number
   locally and left an accepted document reading *Pending Sync* for ever. A field the
   server did not state is now left alone.
2. The detail surface served a **stale cached projection across a user switch** — an
   Owner's complete ₹58,000 invoice shown to a scoped manager out of the Riverpod cache,
   while the local row had already been correctly re-pulled as scoped. That is the D-062
   leak arriving one layer above the read model. The expense read providers now depend on
   the principal.
3. Saving invalidated two of the three ledger surfaces, so a finance user on Windows
   recorded an expense and the ledger did not list it.

## D-073 — Attachment **upload** has no producer, and no object store
**Date:** 2026-08-30 · **Status:** **Answered 2026-08-31 — build it, do not defer it. See
D-073a for what was built and `ARCHITECTURE.md` §16 for how it works.** The text below is
the question as it was put, and is left unedited.
**Context:** Writing the attachment acceptance the project lead asked for (§19 of his
D-072 instruction) found the same shape of gap D-072 recorded for editing: a mechanism
that is implemented and tested, with nothing in the application that reaches it.

What exists, and works:

* `AttachmentStagingService` — copies a picked bill into app-private storage, re-encodes
  oversized images, computes the SHA-256 of what it staged, enforces the per-expense and
  per-document limits. Proven on both real clients (`attachment-staging`).
* `AttachmentUploadWorker` — the deferred upload: backoff, hash confirmation, terminal
  refusals, staging reclamation only after the server confirms *and* the hash matches.
  Eighteen host tests.
* The server half — the private `expense-attachments` bucket, the deterministic object
  path, and the Storage policy that gates an original on `is_complete`, so a scoped
  manager cannot download the whole bill (D-063). The live suite proves that refusal
  against `krishna-mis-dev`.

What does not exist, anywhere in `lib/`:

* any implementation of `AttachmentObjectStore` — the only one in the repository is
  `FakeObjectStore`, in `test/data/attachment_test.dart`;
* any construction of `AttachmentUploadWorker`;
* anything that schedules an upload, at start-up, after a save, or on reconnection.

So a bill attached on a real device is staged, hashed and recorded — and never leaves the
device. `expense_attachments.upload_state` stays `pending` for ever, and the Storage
bucket the migrations create is never written to by the application.

**What this blocks.** Four of the things §19 asks to be proven cannot be, because the
application does not do them: a successful upload, the hash confirmation that turns
`pending` into `uploaded`, a transient failure leaving the expense `Synced` while the
attachment retries, and the reconnect that retries only the attachment. The acceptance
that *can* run does, and says exactly where it stops: `attachment-staging` proves the
picker boundary, the copy into app-private storage, the hash of what was staged, that the
expense saves and syncs without waiting for any of it, and that the staged file survives a
restart.

**Why it is recorded rather than filled in.** Writing a Supabase Storage implementation of
`AttachmentObjectStore` is not the whole of it. It needs the upload to be scheduled
somewhere sensible (start-up, after save, on reconnection, on the same backoff clock as
the outbox), it needs to hold the D-063 predicate on the read side too, and it touches how
`expense_attachments` rows are synced back — none of which is a small unreviewed addition
to a financial system, and none of which the project lead scoped in the D-072 instruction.

**The decision required:** whether attachment upload is a Phase 3 slice to be built now —
in which case Phase 3 cannot close until it is — or whether V1 ships with attachments
staged locally and uploaded in a later phase, in which case `PROJECT_STATUS.md` and the
master spec's §15 must say so plainly, and the UI must stop implying a bill has been
filed anywhere but this device.

**Answered 2026-08-31: build it.** Attachment staging without upload is not enough for V1,
because the interface already presents an attachment lifecycle and the master spec treats
bills as durable supporting evidence. Built and proven on both real clients — see the
entry below for what it took, and for the security defect the acceptance found on the way.

## D-073a — What attachment upload is, as built
**Date:** 2026-08-31 · **Status:** Accepted (project-lead decision)

**Two writes, and an upload is not finished until both have happened.** Putting bytes in
the private bucket does not put a bill in the books. `SupabaseAttachmentStore` uploads the
object and then calls `attachment_register`, and only when the metadata row exists does
the worker call the attachment `uploaded`. Postgres remains the canonical record; the
Storage listing is not the ledger (spec §23).

**Order is a rule, not an optimisation.** An attachment is `waitingForExpense` until the
server has accepted the expense it belongs to, because the Storage write policy calls
`may_read_expense_attachments`, which requires the document to exist canonically. Upload
before that is refused for a reason that reads like a permission problem and is really an
ordering one. The financial record never waits for the bill in return: an expense that is
`Synced` stays `Synced` while its attachment says *Retry needed*.

**One durable state model** (local schema v10): `staged`, `waitingForExpense`,
`pendingUpload`, `uploading`, `uploaded`, `stagingReclaimed`, `retryNeeded`, `rejected`.
The four values it replaces could express neither "waiting for its expense" nor the
difference between a transient failure and a terminal refusal, and the worker needs both.
A `rejected` row carries no `next_attempt_at`, enforced by a check constraint, because a
null there once meant "due now" and retried a refusal for ever.

**Idempotent by construction.** The object path is derived from the expense and attachment
ids and written with `upsert`, and `attachment_register` replays on its mutation id and
refuses a second registration of the same id with different content. A retry after a lost
response leaves one object and one metadata row.

**Authorisation is the server's.** The signed-in user's own session, no service-role key,
a private bucket, and the same complete-document predicate (D-063) on the object, on the
metadata row, and in the RPC. Limits are enforced server-side as well as in the form.

**A real defect the acceptance found.** The `expense_attachments` **table** policy asked
"does a line of this document lie outside my scope?" — but `expense_allocations` RLS hides
exactly those rows from the caller, so the predicate was *vacuously true* for precisely the
users it existed to exclude. Storage refused a scoped manager the invoice image while the
metadata table handed them the row. Migration 0036 points the policy at the same
`security definer` predicate the Storage policies use, which is what its own comment had
claimed since 0031. A policy subquery runs with the caller's privileges — the same fact
that broke every table in D-045, arriving in a new place.

## D-074 — A retained document belongs to whoever queued it
**Date:** 2026-08-31 · **Status:** **Accepted — root cause found, fixed and proven on both
platforms.** Recorded first as an open defect under the title *"sign-out leaves synced
expenses browsable on a long-lived installation"*; the investigation below is left exactly
as it was written, including the hypothesis it disproved, because this log is append-only
and a wrong first guess that was checked is worth more to the next reader than a tidy one
that was not.

**Symptom.** On the Windows machine, whose local database persists across runs and had
accumulated a dozen synced expenses, `d068-switch` fails: after the Owner signs out and a
Crystal Canopy manager signs in, twelve Crystal Canopy documents are still browsable, and
none of them is stamped `scope_revoked_at`. Cached business units at that point are
`CCR` alone.

**Why it was not seen before.** The Android emulator reinstalls the application on every
`flutter test` run, so its database is nearly empty and the sign-out purge has almost
nothing to remove; the assertion passed for want of anything to fail on. The Windows
build keeps its database, which is exactly the shared back-office workstation D-054 added
the sign-out control for — the case the rule exists to protect.

**What is already ruled out.** The purge itself is correct in isolation: a host test that
seeds three accepted expenses and calls `purgeAllScopedCache` removes all three, reports
`3 documents removed`, and leaves the outbox intact. So the deletion logic is not the
defect.

**What the evidence points to.** `SessionController.signOut` calls
`purgeAllScopedCache()` unguarded, and then `store.clear()`. If the purge throws, neither
completes. The end state observed — units reduced to `CCR` while CCR documents survive —
is what would follow if the sign-out purge failed and the *next* user's ordinary authority
refresh then purged only the units they had lost (Hotel Krishna), leaving everything
Crystal Canopy behind. That is consistent but not yet proven; the throw itself has not
been captured.

**Why it is being recorded rather than guessed at.** Two candidate causes are visible and
neither should be picked without evidence: the staged-attachment reclaimer now wired into
the purge (file deletion on Windows can fail on a locked file), and the growth of the
`IN (...)` variable lists as the document count rises. Choosing one and "fixing" it would
be indistinguishable from choosing wrongly, because the symptom would disappear either way
on a freshly installed device.

**Severity.** Real but bounded. What survives is documents the *next* user is themselves
entitled to — every row observed was Crystal Canopy, and the manager signing in was the
Crystal Canopy manager. The Owner's shared ₹58,000 invoice is not among them in the
observed run. It is nonetheless a failure of the rule as written: D-053 and D-070 say the
previous user's scoped financial cache goes at sign-out, and on this installation it does
not.

**What it blocks.** Phase 3 closure. `d068-switch` on Windows is a failing acceptance
phase and is reported as failing, not skipped.

**Next step.** Capture the exception: wrap the sign-out purge so the failure is logged
rather than swallowed by whatever currently absorbs it, and re-run on the Windows
installation with its accumulated database. The fix follows from what it says.

---

**Resolved 2026-08-31. The hypothesis above was wrong, and checking it is what found the
real cause.**

**What the evidence actually said.** A diagnostic phase run inside the real
`krishna_mis.exe`, against the Windows installation with its accumulated database, called
the sign-out purge exactly as sign-out calls it and captured the result rather than the
symptom:

```
D074 purge OK: 2 units, 51 rows, 0 documents removed,
               12 retained for unsynced work, 69 outbox entries preserved
D074 expensesAfter: 12   stamped: 12   browsable: 0
D074 retainedActors: 71c18507-…, 749daa31-…
```

**The purge did not throw.** It completed, and it was right: all twelve documents carried
outstanding outbox intent, so D-070 retains them, and all twelve were correctly stamped
`scope_revoked_at` and unbrowsable. The end state at sign-out was exactly as specified.

The exposure happened one step later, and in the opposite direction from the one being
looked for. When the next user signed in, `ReferenceSync` refreshed authority, and
`ScopeCachePurge._restoreBrowsability` cleared `scope_revoked_at` on every retained
document whose business units were inside *the incoming user's* scope. Every document was
Crystal Canopy; the incoming user was the Crystal Canopy manager; so the restore un-hid
all twelve — and `retainedActors` shows they were queued by **two different people**.

**The rule that was missing.** D-070 says a retained document is kept because it is the
actor's own unsent work and exists nowhere else. That is a statement about *whose* it is,
and the restore tested only *where* it was. Scope is necessary and it is not sufficient:
holding a property does not make somebody the author of another person's queued intent.

**Decision.** Restoring browsability requires **both** conditions:

* every line of the document is inside the confirmed scope again — unchanged; and
* **this actor still has outstanding work on it**, established through
  `sync_outbox.actor_user_id`, which has recorded who queued each intent since D-050.

An org-wide grant covers every unit by construction (D-025) and is therefore *no* evidence
of authorship, so the ownership test applies to it identically — a wider grant restores
nothing that a narrower one would not.

A document whose intent has since completed stays stamped and is simply re-pulled from the
server on the next sync. That is the correct source for a canonical projection, and it is
the difference the whole retention policy turns on: the server can hand back a synced
document, and can never hand back an intent it never received.

**Fail closed at sign-out (the second half).** `SessionController.signOut` called
`purgeAllScopedCache()` unguarded. The hypothesis that it threw was wrong here, but the
shape of the risk was real — a cleanup failure must not leave the previous user's figures
readable. `signOut` now falls back to `quarantineAllDocuments()`, which stamps every
remaining document without deleting one: nothing browsable, nothing destroyed, which is
the safe half of both guarantees. The session ends and the authority store clears either
way, so a cleanup failure can never leave protected navigation usable, and the original
error still propagates rather than being swallowed.

**Positive control.** Four host tests pin the ownership rule — another user does not
inherit retained work, its own actor does, an org-wide holder does not, and a document
whose work has finished stays stamped — plus two on quarantine. Removing the ownership
predicate fails three of them, which is what makes them a control rather than a
description.

**Why the Android runs had been passing.** The emulator reinstalls the application on
every run, so its database was nearly empty and the restore had almost nothing to hand to
the wrong person. The Windows build keeps its database between runs — which is precisely
the shared back-office workstation D-054 added the sign-out control for, and the case the
rule exists to protect. **A test whose fixture is recreated every run cannot see a defect
that needs history to exist.**

**Verified:** `d068-switch` and `d068-revoke` pass on the Windows installation with its
accumulated database — the run that failed — and on Android.

One acceptance assertion changed with it, and the change is the fix working:
`d068-revoke` asserted `retained.single`, which assumed the device held exactly one
retained document. Since the restore stopped handing other people's work away, an
installation that has been used before legitimately holds several, so the assertion now
names the document it means.

## D-075 — A tap that misses is fatal, and an unexplained acceptance failure is diagnosed before it is re-run
**Date:** 2026-08-31 · **Status:** Accepted
**Context:** `expense-edit-offline` failed once in a batch and passed on its own
afterwards, and `PROJECT_STATUS.md` recorded it as an intermittent failure whose cause had
not been captured. The project lead's instruction was explicit: *do not normalise
unexplained flakiness at a financial synchronisation boundary.* Investigating it found
**three** distinct causes wearing one symptom, which is the reason the batch looked random.

**Cause 1 — a missed tap, reported thirty seconds later as a sync defect.** The failing
run's log carries the real evidence:

```
Warning: A call to tap() … derived an Offset (757.3, 642.4) that would not hit test
The hit test result at that offset is: … RenderAbsorbPointer … RenderOffstage …
```

The Save button was present and enabled, and the route was still animating in, so the
`ModalRoute`'s `AbsorbPointer` took the pointer. Flutter treats a missed tap as a
**warning**. The test therefore continued, waited thirty seconds for the outbox intent
that the un-pressed button never produced, and failed with *"no update intent was
queued"* — which reads exactly like a defect in the edit-to-outbox path, and is not one.

**A warning is the wrong severity for this.** A tap that lands on nothing invalidates
every assertion after it, and at this boundary it impersonates the class of defect the
suite exists to detect. Two changes: `WidgetController.hitTestWarningShouldBeFatal` is set
for the whole acceptance suite, so a miss fails where it happens; and taps go through
`tapWhenHittable`, which waits for `finder.hitTestable()` — a hit test at the widget's
centre actually reaching it — rather than for the weaker conditions *present* and
*enabled*, which a transition satisfies while swallowing the pointer.

**Cause 2 — the host's own network.** Three Android phases and one Windows phase failed
without reaching the application shell, and the Windows one named it outright:
`SocketException: The semaphore timeout period has expired (errno = 121)`, raised by the
harness's plain `package:http` admin client, which contains no application code at all.
Measured directly from the host, with `curl` and nothing else involved:

```
try1..try7   total≈0.13s   http=401
try8         connect=15.07s
try9, try10  connect failed, 20s timeout
```

The path to the project was dropping while those phases ran, and recovered afterwards.
**That is not a product defect, a harness race, or a startup budget**, and the only honest
handling is to name it, re-run the affected phases, and report the result of the run that
had a network.

**Cause 3 — a start-up budget that was genuinely tight.** Reaching the shell means a real
sign-in, `my_authority`, a full reference pull and the scope purge against a live project;
measured in isolation the phase completes in 24–34 seconds. The budget is raised, and the
reason it is safe to raise is written beside it: this is the *only* generous wait in the
suite, and no assertion about a financial outcome is given the same latitude — those wait
for a durable consequence and fail if it does not arrive.

**Consequences.** The three causes are distinguishable now, which they were not before: a
missed tap fails at the tap, a network failure names the socket, and a slow start-up has
room. Repeated runs of the phase pass in 24–34 seconds each.

**The general rule this is recorded for.** *An acceptance failure is diagnosed before it is
re-run.* Re-running first and reporting the green is how the missed tap would have survived
— it passed on the very next attempt, and the defect it was hiding was in the test's own
severity settings rather than in the product. The same instinct that made D-071's cleanup a
no-op and D-068's classification guard vacuous is at work here: **a check whose failure
mode is a warning is a check that will one day be ignored.**

## D-076 — An acceptance phase that can only pass once is not a regression test
**Date:** 2026-08-31 · **Status:** Accepted
**Context:** The two-device chain (`propagate-expense-a…e`) ran green when it was written
and failed on its **second** run, with:

```
duplicate key value violates unique constraint "expenses_pkey"
```

Five processes on two machines need a shared handle on one document, and the handle chosen
was a **hard-coded primary key**. Leg *a* voided any leftover before creating — the comment
even said "so the fixed id is free" — and that is precisely the mistake: a void does not
free a primary key. It is not supposed to. Financial history is corrected by void plus
audit and never by deleting rows (D-006), and no client role holds DELETE on a financial
table, correctly.

So the phase was structurally single-use. It reported *passing* the day it was written and
could never pass again, which is the worst of both: a green tick that decays into a
failure unrelated to the product.

**Decision.** The shared handle is the **marker in the document's notes**, which is
already how `expense-cleanup` finds what a run created (D-071) — the one identifier that
survives a process boundary without being written into the schema. Leg *a* voids any open
leftovers, then creates with a fresh UUID v7; legs *b*–*e* resolve the newest open
document carrying that marker. If none exists they fail with a message that says leg *a*
must run first, on Android, rather than with a foreign-key error about a row nobody was
looking at.

**Consequences.** The chain is repeatable against a database that never deletes a
financial row — which is every database this project will ever have. Old runs' documents
remain, voided, in the audit trail, exactly as D-066 says they should.

**Two further instances of the same mistake, found by fixing the first.** The
**attachment** id was fixed too, for the same reason and with the same consequence. And
the marker itself was matched with equality, while leg *b*'s whole job is to **correct**
the document — which rewrites its notes and destroyed the handle the remaining legs
depended on. The marker is now a prefix that every leg preserves, and leg *e*, which
exists to watch the document be voided, looks it up including voided ones.

That last one is worth naming separately: the handle was destroyed *by the operation
under test*. A test fixture identifier must survive everything the test does to the
fixture, and "everything the test does" is exactly what nobody checks when the first run
is green.

**The general rule.** *A fixture identifier must be unique per run unless the fixture can
actually be removed*, and in this project financial fixtures cannot be. The same
reasoning that makes the product correct — void, never delete — makes a fixed-key fixture
a defect. Two related findings in this phase have the same shape: D-071's cleanup that
never ran, and D-068's classification guard that compared a list against itself. Each was
a check that looked like it worked.

## D-077 — The attachment picker was never implemented, and every attachment test passed anyway
**Date:** 2026-08-31 · **Status:** Accepted — defect found by the project lead's manual
acceptance, on both platforms, after the automated suite reported the attachment pipeline
complete.

**Symptom.** On a real Samsung Galaxy A06 5G and inside the real `krishna_mis.exe`, the
expense form's attachment area said:

> Attaching a bill is not available on this device yet.

No picker opened, on either platform. Expense creation itself worked.

**Root cause, stated exactly.** `lib/` contained **one** implementation of
`AttachmentSource`: `UnavailableAttachmentSource`, whose `available` is the empty set and
whose `pick` returns null. `attachmentSourceProvider` defaulted to it, with a comment
saying *"Overridden in `main()` per target"* and *"the bootstrap installs a real one per
platform"*. **No such override was ever written.** `AttachmentStrip` renders the
unavailable message when `source.available.isEmpty`, so the message was the correct
rendering of a correctly-read provider — the defect was one layer below the UI, in wiring
that did not exist. There was also no picker plugin in `pubspec.yaml` at all: no
`image_picker`, no `file_selector`, no `file_picker`. Nothing was misconfigured. The
feature was absent.

**Why the automated acceptance did not catch it, which is the more important half.**
Every attachment test — 18 host tests and three acceptance phases on each platform —
overrode `attachmentSourceProvider` with `_SyntheticAttachmentSource`, injecting a file at
exactly the point a picker would return one. That injection is *correct*: the OS picker is
a separate activity the Flutter harness cannot drive, and D-058 established injecting at
the boundary as the honest technique. `ARCHITECTURE.md` §16.6 even says in as many words
that the picker itself is not proven and must be smoke-tested by a person.

What was missing is the assertion in between. **No test ever read what production
resolves.** Every test replaced the provider; none checked what it would have returned.
The suite proved the whole pipeline behind a boundary while the boundary had nothing
attached to it, and reported that as attachment upload working end to end.

This is the third instance of one pattern in Phase 3, and by now it deserves its name:
D-071's cleanup phase that ran `expect(true, isTrue)`, D-068's classification guard that
compared a list against itself, and now a provider whose production value nothing read.
**A test that supplies the thing it is testing proves the consumer, never the supplier.**

**Decision — the wiring resolves itself, and the resolution is asserted.**

1. `attachmentSourceFor(String operatingSystem)` returns `AndroidAttachmentSource` for
   `android` and `WindowsAttachmentSource` for `windows`. It is a plain function of a
   string rather than a read of `Platform` inside a widget, **so a host test can assert
   both production branches without either device** — which is precisely the test that
   was impossible to write before, and precisely the one that was missing.
2. `attachmentSourceProvider` calls it directly. There is no "bootstrap must remember to
   override" step, because that step is what was forgotten. A default that is wrong but
   harmless-looking is worse than no default.
3. `test/data/attachment_source_wiring_test.dart` asserts that neither shipped platform
   resolves to an empty `available` set, that each matches what `intakesFor` claims its
   shell offers, and that the provider needs no override. Reintroducing the defect fails
   five of its six tests — verified by doing exactly that.

**The platform adapters.**

* **Android** — `image_picker` for camera and gallery with
  `ImagePickerAndroid.useAndroidPhotoPicker = true`, which is **opt-in and defaults to
  false**; without it the plugin falls back to an intent that reads the media store, which
  is what drags a storage permission in behind it. Documents go through `file_selector`,
  which on Android is the Storage Access Framework. **No storage permission is declared or
  requested**, and none is needed by either path. `CAMERA` is deliberately *not* declared
  either: `ACTION_IMAGE_CAPTURE` needs no permission unless the app declares one, and
  declaring it would create an obligation to request it.
* **Windows** — `file_selector` over the native `IFileOpenDialog`. No custom browser, no
  elevation.

Both offer the one accepted-type list (`AttachmentTypes`) rather than a second copy of it,
so adding a supported type cannot be done in the policy and forgotten in the picker.

**What is unchanged.** Everything after selection is the D-073a pipeline exactly as built:
staging into app-private storage, hashing, `waitingForExpense`, `pendingUpload`, upload,
`attachment_register`, hash confirmation, `uploaded`. No second upload architecture, and
the picker returns a throwaway handle that nothing retains — the OS may revoke a content
URI at any time, and a receipt that vanished between capture and upload was never kept.

**Consequence for how this phase reports itself.** The manual picker tests were listed as
*pending* rather than assumed to pass, and they are the reason this was found before the
phase closed rather than after. That was the right call and it is worth keeping: a
boundary the harness cannot cross is a boundary a person has to.

---

**Manual acceptance, 2026-08-31 — both platforms PASS.**

* **Android**, real Samsung Galaxy A06 5G: the system Photo Picker opened and returned the
  selected image to Krishna Imperial MIS, shown **Attached**.
* **Windows**, real `krishna_mis.exe`: the native Windows file dialog opened and returned
  the selected file, shown **Attached**.

The failed first attempt above is not amended and not softened. It is the record of a
feature that reached two real devices, through a full green automated acceptance phase,
without existing — and of the one check that found it. **The manual gate stays in the
release checklist for every release**, and a green automated suite is not grounds for
skipping it: the suite was green the whole time.

---

# Phase 4 — Revenue Engine: approved planning baseline (2026-08-31)

The ten entries below are the **approved planning baseline for Phase 4**. None of them is
implemented. Phase 4 has not begun and is blocked on verified revenue tax and billing
configuration from the project lead. They are recorded now because the repository, not the
conversation, is the source of project state (`CLAUDE.md` §1).

## D-078 — Revenue is a document with components, because one day's revenue can carry more than one tax treatment
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Context.** The first Phase 4 proposal modelled revenue as a flat header: one entry, one
rate, one gross amount. The project lead rejected that shape and supplied the corrections
that break it — conditional tax resolution, room tax varying by accommodation value,
restaurant treatment depending on a premises or financial-year status, and banquet
potentially invoicing more than one kind of supply.

Every one of those corrections breaks the flat header in the **same way**: *one day's
revenue, in one category, can carry more than one tax treatment.* A single rate on the
header cannot represent that, and adding a second rate to the header would be exactly the
header-level classification mistake D-003 rejected for expenses.

**Decision — revenue takes the shape expenses already have.**

```
Revenue Entry  (document)
  └── Revenue Component  (1..n)
```

The header carries: `id` (client-generated UUID v7), `txn_number` (server-issued on
acceptance), `org_id`, `business_unit_id`, `revenue_category_id`, `business_date`,
`entry_kind`, `notes`, `created_by`, `row_version`, `voided_at` / `void_reason`, and the
usual sync metadata.

Each component carries **what was entered, and everything needed to explain what was
derived from it**:

```
entered_amount_minor, entered_basis
gross_amount_minor, tax_amount_minor, net_amount_minor   -- CHECK net = gross - tax
tax_rule_id, tax_rate_bp, tax_treatment                  -- the rule snapshot
value_band_min_minor, value_band_max_minor               -- the facts that
supply_subtype_id, premises_status_code                  -- selected that rule
```

`SUM(components) = header` is enforced by a deferred constraint trigger, exactly as
`SUM(allocations) = expense.amount` is. Money is integer paise throughout; no binary
floating point touches a stored or computed amount.

**Why this shape rather than a special case per category.** A simple Nandbhog day is
**one** component and is exactly as fast to enter as before. A room day spanning two tariff
bands is two. A banquet split between hall and catering is two. One model, one write path,
one reconciliation rule — rather than a per-category branch in the place where company
revenue is computed. It also reuses reasoning already proven in this repository instead of
inventing a second document shape.

**Alternatives rejected:** a second rate on the header (cannot represent three categories'
needs at once, and repeats the D-003 mistake); one entry per band with no grouping
(destroys "what was the day's room revenue?" as a first-class fact and invites double
counting); requiring room-by-room PMS data (out of V1 scope, spec §29, and unnecessary to
compute the tax).

**Consequence for the master spec.** Spec §8 describes a revenue *record* carrying gross,
tax and net directly. The component model refines that, and does not contradict §8.2, which
already permits multiple records per category per day. **The spec text will need amending
when Phase 4 is implemented** — that is a change to a binding governance document, so it is
recorded here as required and is deliberately **not** made now, while Phase 4 is unapproved
for implementation.

## D-079 — Conditional tax resolution: five bounded dimensions, deterministic, refusing ambiguity
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Context.** D-017 keyed a tax rule on `(revenue_category, effective_date)`. The project
lead's real business situation does not fit that: room tax may depend on accommodation
value per unit per day, restaurant treatment may depend on a premises or financial-year
status, and banquet may depend on which kind of supply was invoiced.

**Decision.** A rule is chosen by matching **facts** the entry supplies against
**conditions** the rule declares, over exactly five dimensions:

| Dimension | Where the fact comes from |
|---|---|
| revenue category | the entry |
| business date | the entry, under D-067 semantics |
| value band | the component's own amount |
| supply subtype | chosen on the component |
| premises tax status | configured per business unit, date-effective |

`revenue_tax_rules` gains nullable discriminator columns. **A null means the rule does not
depend on that dimension**, which means it matches **every** value of it.

**Resolution is zero-or-exactly-one, with no specificity ranking** (amended 2026-09-01,
D-094). For any fact set at a business date: zero rules match and entry is refused;
exactly one matches and resolves; more than one is a configuration defect and is refused.
A wildcard does not lose to a specific rule — it **collides** with it, because both match
the same facts. Configuration must be partitioned so one fact set cannot match two rules.

**Three properties are load-bearing, and each is a deliberate refusal of a more flexible
design.**

1. **A bounded set of dimensions, not an expression language.** A general rules engine in
   the path that computes company profit would be unauditable, untestable at its
   boundaries, and precisely the speculative module `CLAUDE.md` forbids. Adding a sixth
   dimension is a migration and a decision, made deliberately and once.
2. **Resolution is deterministic.** The same facts on the same date give the same answer,
   on the client and on the server, for ever. A report that changes its mind is worse than
   a report that refuses.
3. **Ambiguity is refused, never tiebroken.** Two rules that could both match the same
   facts on the same date are rejected by a database constraint at configuration time, and
   an ambiguous resolution at entry time refuses the save. Picking one arbitrarily would
   silently apply a rate nobody approved.

**No GST legislation is encoded in Dart, and none in a Flutter widget.** The dimensions are
a schema; the rates, bands, subtypes and statuses are configured data supplied from
verified business information. The resolver is one pure-Dart implementation in
`domain/`, used identically online and offline.

## D-080 — The entered amount has an explicit basis, and both what was typed and what was derived are stored
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Context.** The first proposal was incoherent, and the project lead caught it: it named
`gross_amount_minor` as the core stored field and had the Android form ask for "Gross",
while an exclusive tax treatment starts from the **pre-tax** amount. Those cannot all be
true at once.

**Decision.** The rule states the **input basis**, and the record stores what the operator
actually typed alongside the figures derived from it.

| Basis | The operator types | Derivation, in exact integer paise |
|---|---|---|
| `inclusive_total` | the customer total, tax included | `tax = round_half_up(entered × rate_bp ÷ (10000 + rate_bp))`; `net = entered − tax`; `gross = entered` |
| `pre_tax` | the amount before tax | `tax = round_half_up(entered × rate_bp ÷ 10000)`; `gross = entered + tax`; `net = entered` |
| `none` | the amount | `tax = 0`; `gross = net = entered` |

Rounding is half-up, applied **once, at the component**, and stored. Aggregates sum stored
paise and never re-apply a rate to a total (D-017).

**The field label follows the configured rule** — "Customer total (incl. GST)" or "Pre-tax
amount" — and is never universally labelled "Gross". A manager who has to guess which
number the form wants will eventually guess wrong, and the two answers differ by exactly
the tax.

Storing `entered_amount_minor` and `entered_basis` beside the derived trio is what makes a
figure explainable years later without consulting a rule table that may since have changed:
the record states what was typed, under which basis, against which rule, at what rate.

## D-081 — Room revenue is manual-first, in value-band components
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Decision.** The manager enters one figure per tariff band that had business that day. No
room-by-room data, and no PMS (spec §29).

```
Room Revenue · 15 June 2026
  Band: up to <configured boundary>    ₹42,000   -> rule A
  Band: above <configured boundary>    ₹23,000   -> rule B
  ------------------------------------------------
  Daily Room Revenue                   ₹65,000
```

**The form derives its own fields from the configured rules.** One rule in force for Room
on that date means one field, and entry is as fast as it ever was; two bands mean two
fields, labelled with the configured boundary. **No threshold is a constant in application
code** — the boundary is a property of the rule, so a change in the real treatment is a
configuration change rather than a release.

The band describes accommodation value *per room per day*, which is a fact about the tariff
rather than about the day's total. Recording it on the component preserves exactly the
information a differential treatment needs and nothing more: it does not reconstruct a PMS,
and it does not discard the distinction the tax depends on.

**A consequence the project lead should see before a manager does:** on days when two bands
apply, the daily room entry becomes two figures instead of one. That is a real, if small,
change to a daily routine, and it is flagged rather than presented as a surprise.

## D-082 — Premises tax status is configured business data, never inferred
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Decision.** A date-effective master, `business_unit_tax_status` —
`(business_unit_id, effective_from, status_code, note)` — records a premises or
financial-year tax status where the real treatment depends on one. Rules may name a
`premises_status_code`.

**The application never derives, infers or defaults this.** It is entered by the Owner from
what the accountant states, it is audited, and it is date-effective, so a change at the
start of a financial year cannot restate the previous year's Net Sales.

If a rule requires a premises status and none is configured for that unit on that business
date, the save is **refused** (D-084). Guessing it would be inventing a business fact,
which `CLAUDE.md` prohibits outright.

## D-083 — Banquet supply subtype: the extensibility point exists and ships empty
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Decision.** `revenue_supply_subtypes` — `(revenue_category_id, code, label,
archived_at)` — is created and **ships with no rows**.

* No subtypes configured for a category → no subtype field on the form, and rules with a
  null subtype match. Banquet behaves as an ordinary category.
* Subtypes configured → the component gains a subtype selector, and rules may differ per
  subtype.

The hinge therefore exists and is exercised by tests, and **no speculative subtype is
invented**. Hall-only, catering and composite packages are all plausible and are
deliberately *not* seeded: what Hotel Krishna Imperial actually invoices is a business fact
to be supplied from real invoices, not guessed from what hotels generally do.

## D-084 — An unresolvable or ambiguous tax rule refuses the save
**Date:** 2026-08-31 · **Status:** **Approved (project-lead decision). NOT implemented.**

**Decision.** If the resolver cannot produce **exactly one** applicable rule, the revenue
entry is refused — locally and on the server. Every failure mode is covered:

* no rule for the category on that business date;
* a component whose value band no rule covers;
* a required supply subtype not chosen;
* a required premises status not configured;
* **two or more rules that both match** — ambiguity, never a tiebreak.

The message is *"No tax rule configured for this revenue entry."*, naming which condition
could not be satisfied.

**"No rule configured" stays permanently distinct from a configured `0%` and from a
configured `none` / not-taxable.** The first is a gap in configuration; the other two are
decisions somebody made and can defend. Collapsing them is how Net Sales gets silently
overstated — and Net Sales feeds Operating Profit.

**Alternatives rejected:** treating absence as 0% (overstates profit, invisibly); recording
with an `unresolved` treatment and excluding it from reports (creates rows that exist but
cannot be reported, which is worse than not having them).

## D-085 — Revenue has its own number sequence
**Date:** 2026-08-31 · **Status:** **Approved (project-lead decision). NOT implemented.**

**Decision.** `KI-REV-26-27-000001` — organisation-wide, server-issued on canonical
acceptance, and **not shared with the expense sequence**. Offline entries carry their
client-generated UUID v7 identity until the server accepts them (D-008), exactly as
expenses do.

## D-086 — Offline revenue resolves tax from cached configuration, or refuses
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Decision.** `ReferenceSync` gains four things to cache: revenue tax rules, their
condition discriminators, the supply-subtype master, and the business-unit premises-status
timeline. Offline resolution uses **the same deterministic domain resolver** as online —
one implementation over cached data, so the two cannot drift.

If the required configuration is not cached, the local save is **refused and nothing is
queued**.

This is a deliberate departure from the expense engine, where a local save always succeeds,
and the reason is worth stating: an expense's correctness does not depend on configuration
the device might lack, and a revenue figure's does. A queued entry whose tax could not be
computed would be refused by the server anyway, and a rejected revenue entry sitting in
somebody's outbox is worse than being told, at the time, that it cannot yet be recorded.

The client never invents a rate, never defaults one, and never rounds a figure differently
from the way the server would.

## D-087 — The revenue reporting contribution shape is defined in Phase 4 and consumed in Phase 5
**Date:** 2026-08-31 · **Status:** **Approved as the planning baseline. NOT implemented.**

**Decision.** `revenue_period_contributions` — one row **per component**:

```
org_id, business_unit_id, revenue_category_id,
supply_subtype_id, value_band_min_minor, value_band_max_minor,
pnl_period_key,
gross_minor, tax_minor, net_minor
```

The mirror of `expense_period_contributions` (D-060), so the Phase 5 engines sum one shape
per side of the P&L. Keeping the component grain means **tax buckets survive into
reporting** rather than being flattened at the door, which is what makes "why did room tax
change this month?" an answerable question.

**Phase 4 defines and populates this interface. Phase 4 does not build the P&L or the
reporting engines** — that is Phase 5, with the parity suite D-020 requires.

## D-088 — The entered-amount basis is independent of how the source invoice presents tax
**Date:** 2026-09-01 · **Status:** **Accepted (project-lead correction to the D-080 plan).
Phase 4 still NOT implemented.**

**Context.** Real billing evidence arrived, and it immediately exposed an inference the
architecture would have made and would have got wrong.

The Crystal Canopy Rooftop restaurant bill dated 01/09/2026 presents tax the way almost
every POS does:

```
        items / subtotal
      + CGST 2.5%
      + SGST 2.5%
      ─────────────────
      = grand total
```

Read naively, a bill that *adds* tax to a subtotal looks like an `exclusive` treatment
whose input basis is `pre_tax`. That reading is wrong, and the project lead stated the
management meaning explicitly: when Restaurant Sales is recorded as ₹1,00,000 in this MIS,
**₹1,00,000 is the final amount including GST**. The system must derive the tax component
and Net Sales *out of* that figure, and must never add tax on top of it.

**Decision.** `entered_basis` describes **what the operator is typing into this
application**. It is not derived from, inferred from, or constrained by how the underlying
invoice or POS displays its arithmetic. The two are separate facts about separate things:

| | What it describes |
|---|---|
| **Invoice presentation** | how the source document lays out subtotal, tax and total for the customer |
| **`entered_basis`** | which of those numbers a manager types into the daily sales screen |

For Restaurant management entry, `entered_basis = inclusive_total` **even though the POS
invoice visibly computes subtotal + tax**. Both statements are true at once and there is no
contradiction to resolve: the invoice adds tax to reach a grand total, and the manager
records the grand total.

**Why this needed recording rather than just implementing.** The inference is natural,
would have been made silently, and would have been invisible in testing: entering
₹1,00,000 under a wrongly-inferred `pre_tax` basis produces a grand total of ₹1,05,000 and
a Net Sales of ₹1,00,000 — every figure internally consistent, every figure wrong, and
Operating Profit overstated by the whole tax component of revenue. Nothing in the software
would object, because nothing in the software would know.

`entered_basis` therefore comes from the **configured rule** (D-080), which is configured
from what the project lead states the management figure means — never from what a source
document looks like, and never from a heuristic over it.

**Consequence.** The input basis is a **management-accounting decision, per revenue
category**, and must be confirmed for each category separately. Restaurant is confirmed
(`inclusive_total`). Room, Banquet and Nandbhog are **not**, and are not to be assumed to
match Restaurant merely because they are billed by the same business — which is the same
discipline D-043 already applies to rates.

## D-089 — Nandbhog is restaurant revenue at 5%, and remains its own category
**Date:** 2026-09-01 · **Status:** **Verified business configuration (project-lead
confirmation). Phase 4 still NOT implemented; no rule row is written.**

**Confirmed by the project lead.** Nandbhog **is restaurant revenue**. It carries a **5%
total GST** treatment today, and its management sales figure is the **tax-inclusive**
customer total (`entered_basis = inclusive_total`, per D-090). Entering ₹1,00,000 for
Nandbhog means ₹1,00,000 *including* GST; the engine extracts the configured tax component
and derives Net Revenue, and never adds 5% on top.

**It remains a revenue category under Crystal Canopy Rooftop, not a business unit** —
D-024 is unchanged and this confirmation does not disturb it.

**The part that matters architecturally: "the same treatment" is not "the same rule."**
Restaurant and Nandbhog currently share a rate, a treatment and an input basis. They stay
**two independent categories with two independent rule rows**:

* they remain separately reportable, which is the whole reason Nandbhog is a category
  rather than a line inside Restaurant (spec §4);
* a future change to one **must not** alter the other. There is no inheritance, no
  fallback to a sibling category, and no shared rule row that two categories point at.
  Resolution is by `revenue_category_id` and always has been (D-079);
* a convenience that "copies Restaurant's rule to Nandbhog" is acceptable as a
  configuration *action* that creates a second, independent row. It is not acceptable as a
  *link* between them, because the link is exactly what would make one category's change
  propagate silently into another's Net Sales.

This is the same discipline D-043 has applied since Phase 2 — no category acquires a
treatment by proximity — applied now in the direction that is easy to get wrong: two
categories that agree today.

**Still pending for Nandbhog:** its **effective-from date**, like every other category.
Confirming today's rate does not establish when it started, and the software will not
choose one.

## D-090 — The management sales convention is tax-inclusive, and it is configuration rather than a constant
**Date:** 2026-09-01 · **Status:** **Verified business convention (project-lead
confirmation). Phase 4 still NOT implemented.**

**Confirmed.** For every V1 revenue category, the figure a manager records is the **final
customer-billed amount including GST, where GST applies**:

| Category | `entered_basis` |
|---|---|
| Restaurant | `inclusive_total` |
| Nandbhog | `inclusive_total` |
| Room | `inclusive_total` |
| Banquet | `inclusive_total` |

This resolves the question that had been blocking Room. It is a statement about **what the
management user means when they type a sales figure** — nothing more, and in particular it
is *not* a statement about how any source invoice presents its tax (D-088). The Crystal
Canopy POS bill still shows `subtotal + CGST + SGST = grand total`, and the management
figure is still the grand total. Both remain true.

**Three things this decision deliberately does not become.**

1. **Not a constant.** `inclusive_total` is recorded on each category's configured rule and
   snapshotted onto each component, exactly as the rate is (D-080). It is not a default in
   Dart, not a fallback when a rule is silent, and not an assumption the resolver makes.
   A category whose rule does not state a basis is unresolvable and refuses (D-084).
2. **Not permanent.** The rules are date-effective. If a category's convention ever changes,
   it changes from a date, and figures recorded before that date keep the basis they were
   recorded under — which is the entire reason the basis is snapshotted rather than looked
   up at read time.
3. **Not a reason to simplify the model.** All four categories agreeing today does not
   justify collapsing `entered_basis` to a single organisation-wide setting, nor removing
   `pre_tax` and `none` from the domain. The conditional architecture (D-079) and the three
   bases (D-080) stay as approved: Banquet's own treatment is still unresolved, and a model
   that fits only the cases known today is the model that has to be rewritten the first
   time a new one appears.

**Consequence for Banquet.** Its *basis* is confirmed — a banquet sales figure is the
customer total. Its **tax condition is not**: a real invoice shows ₹0 tax, and 5% is
applied in some circumstances. What determines which is the remaining business blocker, and
until it is answered Banquet revenue entry refuses (D-084). A confirmed basis is not a
confirmed rule.

## D-091 — Banquet carries no GST, and the earlier 5% observation is not a rule
**Date:** 2026-09-01 · **Status:** **Verified business configuration (project-lead
confirmation). Phase 4 still NOT implemented; no rule row is written.**

**Confirmed by the project lead.** The normal and current Banquet revenue treatment is
**without GST**.

| | |
|---|---|
| Revenue category | Banquet (Hotel Krishna Imperial) |
| Management input basis | `inclusive_total` |
| Tax treatment | `none` |
| Tax amount | ₹0 |
| Net revenue | equal to the entered amount |

```
        Banquet Sales   ₹40,343
          gross         ₹40,343
          GST                ₹0
          net           ₹40,343
```

which matches the supplied invoice of 30/08/2026 exactly: subtotal ₹40,343, taxes ₹0, net
payable ₹40,343.

**The earlier 5% observation is closed, and closed as an observation.** It was recorded
that GST of 5% is applied to a banquet in some circumstances. That is **not** encoded, and
specifically *"customer asks for GST → 5%"* is not becoming a rule, a dimension, or a
hidden second rule row. **Banquet has exactly one active rule in V1, and its treatment is
`none`.**

If a distinct GST-bearing banquet supply is required later it arrives as a **separately
approved** rule, profile or supply subtype, after its accounting treatment has been
verified — an explicit decision with its own entry in this log, not a dormant row somebody
finds already switched on. A second Banquet rule left active "just in case" would be worse
than absent: it would make resolution ambiguous, which D-084 refuses outright, and the
refusal would surface as a mysterious blocked save rather than as the configuration
question it really is.

**Why `inclusive_total` and not the `none` input basis.** With `tax_treatment = none` all
three input bases produce identical arithmetic — tax is zero, so gross, net and the entered
figure coincide, and the basis is arithmetically inert. Recording `inclusive_total` is
nonetheless the better statement of fact, for two reasons:

* it says what the number *is* — the final customer-billed amount — which stays true and
  stays informative whether or not tax applies to it;
* if a taxed banquet supply is ever introduced, the basis does not have to change. Only the
  treatment and rate do. A basis recorded as `none` would have to be revisited, and
  revisiting a snapshotted field is how historical figures get restated by accident.

This does leave `none` as an input-basis value with no current user, which is a small
redundancy in the domain rather than a defect: `entered_basis` answers *which number was
typed* and `tax_treatment` answers *what tax applies to it*, and they are genuinely
different questions even when one of them makes the other moot. Removing the value would be
its own decision, and there is no reason to take it now.

**Consequence.** The Banquet blocker is closed. All four V1 categories now have a verified
rate and a verified input basis, and the **only** remaining Phase 4 business blocker is the
set of **effective-from dates**.

---

# Phase 4 — Revenue Engine: implementation authorised (2026-09-01)

The project lead confirmed the last outstanding business fact — **effective from
2026-04-01 for all four verified treatments** — and authorised implementation.

**The verified configuration baseline, in full:**

| Business unit | Category | Treatment | Rate | Entered basis | Effective from |
|---|---|---|---|---|---|
| Crystal Canopy Rooftop | Restaurant | `inclusive` | 5% (CGST 2.5 + SGST 2.5) | `inclusive_total` | 2026-04-01 |
| Crystal Canopy Rooftop | Nandbhog | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Hotel Krishna Imperial | Room | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Hotel Krishna Imperial | Banquet | **`none`** | — (₹0) | `inclusive_total` | 2026-04-01 |

Four independent rule rows. No inheritance between Restaurant and Nandbhog (D-089); no
dormant 5% Banquet rule (D-091); Room's conditional architecture retained so a second value
band needs configuration rather than a redesign (D-081).

## D-092 — Master spec amended to v1.2 for the revenue model
**Date:** 2026-09-01 · **Status:** Accepted

**Context.** Governance requires that the binding specification move with the semantics,
and that the version, `CLAUDE.md` and this log change together (`CLAUDE.md`, D-028). Spec
§8 described a revenue *record* carrying one gross, one tax and one net. The approved and
now-authorised model is a document with components and conditional tax resolution
(D-078 … D-091). Leaving the binding document describing the old shape while building the
new one is exactly the code/documentation disagreement governance rule 3 exists to prevent.

**Decision.** The master spec is amended to **v1.2**, and the amendment is confined to the
revenue model:

* **§8.0 (new)** — a revenue entry is a document with one or more components; header totals
  reconcile exactly to component totals, enforced in the database;
* **§8.1 (extended)** — conditional resolution over five bounded dimensions, deterministic,
  zero-or-exactly-one, refusing ambiguity; categories that share a treatment do not share a
  rule; the entered basis is separated from the treatment and is explicitly not inferred
  from how a source invoice presents tax; a missing rule is never a zero rate;
* **§8.3 (new)** — room revenue entered manually by value band, with the boundary coming
  from configuration and never from a constant in code;
* **§8.4 (new)** — revenue's own financial-year-scoped number sequence.

**Nothing else is amended.** The accounting basis (§5), expense model (§6, §7),
business-date semantics (§9), permission model (§13), calculation architecture (§21),
offline model (§22) and V1 scope (§28, §29) are untouched. The change log entry in §30 says
so explicitly, because "amended the spec" is otherwise an unbounded claim.

**Consequence.** `CLAUDE.md`, all five canonical documents and the response footer now read
**v1.2**. The version bump is not cosmetic: it marks the point after which a reader must
not assume a revenue record carries a single rate.

## D-093 — The exclusion constraint that guarantees determinism today would forbid Room's value bands
**Date:** 2026-09-01 · **Status:** Accepted — **an architecture contradiction found in the
real code during the Phase 4 audit, before any Phase 4 code was written.**

**Context.** The Phase 4 audit read what actually exists rather than what was remembered.
`revenue_tax_rates` was shipped in Phase 2 and carries:

```sql
constraint revenue_tax_rates_no_overlap
  exclude using gist (
    revenue_category_id with =,
    daterange(effective_from, effective_to, '[)') with &&
  ) where (archived_at is null)
```

and the Dart mirror refuses a candidate with `TaxRuleRefusal.overlapsExistingPeriod`
whenever an active rule for the same category covers an overlapping date range.

**That constraint is correct for the model it was written for, and it makes D-081
impossible.** Room's two value bands are, by construction, two rules for the *same category*
over the *same dates*. The existing constraint would refuse the second one. The feature the
project lead approved cannot be configured against the schema as it stands.

This is worth stating plainly because the constraint is not a mistake to be deleted: it is
the thing that currently *guarantees* deterministic resolution, and D-079 requires that
guarantee. Removing it to make room for bands would trade a real protection for a feature
and leave ambiguity configurable — precisely what D-084 refuses.

**Decision.** The constraint is **replaced, not removed**, by one that is
discriminator-aware. Two active rules for one category conflict when their date ranges
overlap **and** their discriminators are not provably disjoint:

| Two rules, same category, overlapping dates | Outcome |
|---|---|
| disjoint value bands (`[0, 750000)` and `[750000, ∞)`) | **allowed** — this is Room |
| overlapping or equal value bands | **refused** |
| different supply subtypes | **allowed** |
| both with a null discriminator on every dimension | **refused** — the current behaviour, preserved |
| one null (matches anything) against one specific | **refused** — the null rule already covers the specific one's facts, so both would match |

The last row is the subtle one and is the reason this is a decision rather than a schema
tweak. A null discriminator means *"does not depend on this dimension"*, which means it
matches **every** value of it. A null-band rule and a `[750000, ∞)` rule therefore both
match a component carrying that band, and something would have to break the tie — which
the doctrine forbids. So a null and a specific rule on the same dimension and dates is a **conflict**,
refused at configuration time, and the administrator must state both bands explicitly.

**Consequence for the verified baseline.** All four categories are configured today with
**null discriminators** and one rule each, which is unambiguous and legal under both the
old constraint and the new one. Room's second band, if it ever exists, requires the
existing null-band Room rule to be **end-dated and replaced by two explicit banded rules**
from the same date — an auditable configuration change, not an in-place mutation. That is
the correct behaviour and is what keeps historical figures stable (§8.1).

**Where this lands in the plan.** The constraint replacement is part of **Slice 4**
(server schema), and the Dart `TaxRuleSet.refusalFor` change is part of **Slice 2**
(domain). Both must land with tests that assert the five rows of the table above — including
the two that must still be **refused**, because a constraint that has quietly stopped
refusing is indistinguishable from one that works (D-069, D-077).

## D-094 — Zero-or-exactly-one resolution, and a value band is selected rather than calculated
**Date:** 2026-09-01 · **Status:** Accepted (project-lead corrections) — **implemented in
Slice 2**, amends the wording of D-079 and D-093

Two corrections from the project lead, both taken before the resolver was written. The
second is the one that would have produced wrong money.

### 1 · There is no most-specific-match, anywhere

Earlier wording in D-079, D-093, `ARCHITECTURE.md`, `DATABASE_SCHEMA.md` and spec §8.1 said
resolution was *"most-specific-match"*. That phrasing implies a runtime ranking that can
resolve two otherwise-applicable rules, and **no such ranking exists or may exist**. The
canonical invariant is:

> For any revenue fact set at a business date, **zero or exactly one** rule may match.

* zero → no-rule refusal;
* exactly one → resolve it;
* more than one → ambiguous configuration → **refuse**.

Because `null` on a discriminator means *"does not care"*, a wildcard rule matches **every**
value of that dimension. A wildcard rule and a specific rule over overlapping dates
therefore both match the same entry: they represent **overlapping applicability** and must
be rejected. A wildcard does not lose to a specific — it collides with it. Configuration
must be partitioned so one fact set cannot match two rules.

All five documents now say the same thing, and the repository has one doctrine rather than
two phrasings of nearly the same idea.

### 2 · A value band is a configured identity, not a function of the amount

**This is the correction that mattered.** The earlier design compared a component's
`entered_amount` against a rule's `value_band_min/max`. That is wrong, and wrong in a way
that would have produced plausible-looking figures:

```
        Room Revenue · lower tariff band     ₹42,000
```

₹42,000 is the **day's aggregate revenue attributable to that band**. It is *not* the
per-room-per-night tariff that decides the treatment. Comparing an aggregate against a
tariff boundary is a category error — a hotel with forty ₹1,800 rooms and one with five
₹8,400 rooms can report the same daily total — and it would have silently selected a rate
by arithmetic that means nothing.

**Decision.** The operator states which configured band an amount is attributable to. The
band's own configuration carries the tariff boundary. The component snapshots the band
identity, its label and its bounds so the choice is explainable, and **the bounds are never
compared against a revenue figure**.

The guarantee is structural rather than documentary: **`RevenueTaxFacts` carries no
monetary field at all.** The resolver cannot see an amount, so no code path — present or
future — can resolve a band from one. A test asserts the fact set exposes nothing
money-shaped, because a comment saying "do not compare these" is the kind of rule that
D-068 and D-077 both showed nobody evaluates.

Room-by-room or PMS data remains out of V1 (spec §29). This design needs neither.

### Implemented in Slice 2

`lib/domain/revenue/revenue_tax_resolution.dart` — `RevenueTaxFacts` (no money),
`RevenueTaxRuleSet.resolve` returning a sealed result, and `conflictFor` implementing
collision detection where a wildcard collides rather than yields. 36 pure-domain tests,
including two positive controls: inverting the doctrine to most-specific-wins fails three
of them.

**A note on how those controls were arrived at, because it is the third time.** The first
control I wrote was a no-op — a rewrite of the predicate that was logically identical to
the original, which passed and proved nothing. It was caught by expecting the suite to go
red and finding it green. The same failure shape as D-074's first control and D-071's
cleanup phase: *a check is not a check until it has been seen to fail.*

## D-095 — One exclusion constraint cannot enforce the doctrine; Slice 4 needs more than that
**Date:** 2026-09-01 · **Status:** Accepted — **design recorded now, implemented in Slice 4.
The existing Phase 2 constraint is deliberately left in place until then.**

**Context.** D-093 said the Phase 2 exclusion constraint would be "replaced by a
discriminator-aware one". Writing the Dart resolver in Slice 2 made it clear that sentence
was optimistic, and the project lead flagged the same thing: **do not claim one PostgreSQL
exclusion constraint can enforce this unless it is proven.**

The rule Slice 4 must enforce is:

> Two active rules for one category conflict when their date ranges overlap **and**, on
> every discriminator, either is null or they are equal.

An `EXCLUDE USING gist` constraint compares operator-per-column. `daterange && daterange`
works. But the discriminator predicate is *"NULL matches anything, otherwise equal"*, which
is **not** `=` and is not `<>`: SQL equality on NULL yields NULL, not true, so a naive
`value_band_id WITH =` would treat two NULL-band rules as **non-conflicting** — the exact
opposite of what the doctrine requires, and it would let the ambiguous pair through
silently.

`IS NOT DISTINCT FROM` has the right semantics for *equality including nulls*, but that is
still not the predicate: it makes `null` equal only to `null`, whereas here `null` must
collide with **every** value. There is no built-in operator for "wildcard-aware overlap",
and inventing one via a custom operator class is a large, subtle piece of database
engineering to sit under company revenue.

**Decision — Slice 4 combines mechanisms, and proves each one:**

1. **Coerce where it is safe.** Map a null discriminator to a sentinel and use a range or
   enumerated domain, so the wildcard becomes a value that genuinely overlaps every other
   — *if* a representation can be found that gist can index without lying about the
   semantics. To be attempted and **proven with tests before being relied on**, not
   assumed.
2. **A validating trigger** implementing the predicate directly, in SQL, mirroring the Dart
   `conflictFor`. Straightforward and exact.
3. **Serialisation against the race the trigger cannot see.** A trigger validates against
   rows *visible to its transaction*. Two concurrent inserts, each individually valid, can
   commit an ambiguous pair — the classic write-skew that read-validate-write invites.
   Slice 4 therefore takes a **transaction-level advisory lock keyed on
   `(org_id, revenue_category_id)`** before validating, so rule changes for one category
   serialise. Rule configuration is a rare administrative act; serialising it costs
   nothing and removes the whole class.

**What must be true when Slice 4 is done, and asserted rather than argued:**

* the five conflict cases from D-093's table, tested against the real database, including
  the two that must still be **refused**;
* a concurrency test that attempts the ambiguous pair from two sessions and shows the
  second refused — because a constraint that only works single-threaded is a constraint
  that works until the day it matters;
* client-side `conflictFor` is **UX and offline resolution**, never the guarantee. The
  server's answer is final (D-037).

**Why the old constraint stays until then.** `revenue_tax_rates_no_overlap` is currently
the thing preventing ambiguous configuration. Removing it in Slice 2 — before its
replacement exists and is proven — would leave a window in which the database permits
exactly what the doctrine forbids. Slice 2 changes no schema at all.

## D-096 — The initial verified configuration ships as a committed migration
**Date:** 2026-09-01 · **Status:** **Accepted (project-lead decision). Implemented in
Slice 4, not Slice 2.**

**Decision.** The initial verified FY 2026–27 revenue tax configuration — the four rules,
effective 2026-04-01 — is created by a **committed migration**, so development, staging and
production start from the same reviewed baseline.

**Scope, deliberately narrow.** This covers the *initial verified baseline only*. Later
operational changes to tax rules continue to go through the audited authoritative RPC path
(`tax_rule_create` and its successors), unless a future governance decision says otherwise.
The migration is a starting point, not a new configuration channel.

**Why.** Three environments configured by hand diverge, and the divergence is invisible
until a figure differs between them. A committed migration makes the baseline a reviewed
diff with an author and a date, identical everywhere. A GST rate is not a secret, so §24
and §32 are not engaged: this is master configuration, not financial history and not a
credential.

**The four rules, and nothing else:**

| Category | Treatment | Rate | Basis | Effective from |
|---|---|---|---|---|
| Restaurant | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Nandbhog | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Room | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Banquet | `none` | — | `inclusive_total` | 2026-04-01 |

Four independent rows. **No value bands, no supply subtypes and no premises status values
are created**, because none has been verified: Room's single rule carries a null band, which
under D-094 is the correct representation of "the treatment does not depend on a band
today". Nandbhog's row is independent and references nothing of Restaurant's (D-089).
Banquet has exactly one row and no dormant 5% alternative (D-091).

**The stop condition, stated in advance.** If the Slice 4 schema turns out to require a
band identity, a subtype or a premises status that we do not have verified data for, the
work **stops and the contradiction is surfaced** rather than resolved by inventing a value.
On the current design it should not: every discriminator is nullable precisely so that a
category whose treatment does not depend on a dimension says so by leaving it null.

## D-097 — Entered basis and tax treatment are not coupled, and `EnteredBasis.none` is removed
**Date:** 2026-09-01 · **Status:** Accepted (project-lead verification of Slice 2) —
implemented as a Slice 2 corrective

**Context.** The project lead asked for the Banquet combination to be verified before
Slice 3, because it is the one the approved configuration depends on:

```
        Banquet     entered_basis = inclusive_total
                    tax_treatment = none
                    tax = 0, gross = net = entered
```

**It already worked.** `coherentWith` was written as `TaxTreatment.none => true`, so any
basis accompanies an untaxed rule and no one-to-one mapping was ever enforced. The check
found no defect in the semantics and it is proven rather than asserted: four
verified-configuration tests, one per category, resolve and compute; a positive control
that couples basis to treatment fails five of them.

**The doctrine, stated once.** The two answer different questions:

| | Answers |
|---|---|
| `entered_basis` | *what does the number the operator typed represent?* |
| `tax_treatment` | *how is tax treated?* |

so they are related and not coupled. `inclusive` extracts tax from a total, so the operator
must have typed the total; `exclusive` adds tax to a net figure, so they must have typed
the net figure; **`none` applies no tax and either basis is truthful**, because with tax at
zero the customer total and the pre-tax amount are the same number. `pre_tax` with an
untaxed rule is therefore **valid and deliberately allowed**: where a source figure
genuinely is a net amount, the basis says so, and discarding that truth to satisfy a
symmetry that does not exist would be the wrong trade.

The refused pairings are only the contradictory ones — `inclusive` with `pre_tax`, and
`exclusive` with `inclusive_total`.

**Two changes came out of the review.**

**1 · `EnteredBasis.none` is removed.** It had no distinct product meaning. Every revenue
figure a manager records is money billed to a customer; where no tax applies, that figure
is *simultaneously* the customer total and the pre-tax amount, so it is already fully
described by one of the other two values. A third label added no information, and its
presence invited recording Banquet as `none` — which D-091 had already argued against,
because `inclusive_total` states what the number *is* and stays true if tax is ever
introduced. It existed only because `TaxTreatment` has a value of the same name, which is
not a reason. Adding it back is one line plus a migration if a real meaning ever emerges.

**2 · The field label now takes the treatment, and this was a real defect.** `fieldLabel`
was a property of the basis alone, so Banquet — `inclusive_total`, treatment `none` —
would have been labelled **"Customer total (incl. GST)"**: a form telling an operator that
GST is inside a figure that carries none. Nothing in the domain would have objected, and it
would have reached Slice 8's entry screen looking correct.

`fieldLabelFor(treatment)` replaces it: an untaxed rule reads *"Amount billed to the
customer"*, a taxed inclusive rule *"Customer total (incl. GST)"*, an exclusive rule
*"Amount before GST"*, and none of them is ever "Gross" (D-080). Four tests pin it,
including one asserting that an untaxed label contains no mention of GST at all.

**Consequence.** The verified baseline is unchanged and remains configurable exactly as
approved. Spec §8.1, `ARCHITECTURE.md` §17.3 and `DATABASE_SCHEMA.md` §6.1 drop the third
basis value from their tables and state the non-coupling explicitly.

## D-098 — A value band needs its own master; rule identity cannot serve as band identity
**Date:** 2026-09-01 · **Status:** Accepted — **an architecture contradiction surfaced in
Slice 3**, as the project lead's §7 asked

**The question.** Slice 3 was asked to add only the reference caches the approved model
actually needs, and specifically: if the tax rule's own identity can serve as the stable
band the operator selects, do **not** invent another master table; if it cannot, say so
now rather than hiding the problem in persistence.

**It cannot, and the reason is dates.**

Rules are date-effective and superseded. When a rate changes on 1 April, the old rule is
end-dated and a **new row with a new id** takes over. A band is the opposite kind of
thing: *the lower tariff band* is one business concept that persists across every rate
change. If band identity were rule identity:

* the same band would have **different identities in different periods**, so
  `revenue_period_contributions` grouped by band (D-087) would fragment at every rate
  change — "why did lower-band room revenue drop to zero in April?" would have no answer
  except "it did not, the id changed";
* the entry form's band choices would be **rule rows**, so a band would disappear from the
  picker the moment its rule was end-dated, and reappear under a new name;
* a component's snapshotted band would point at a rule that may be archived, conflating
  *which band this was* with *which rule applied*, which are exactly the two facts the
  snapshot exists to keep apart.

**Decision.** `revenue_value_bands` is a master in its own right — `(id, org_id,
revenue_category_id, code, label, floor_minor, ceiling_minor, archived_at)` — with an
immutable `code` like every other master (D-035). Rules reference it through the nullable
`value_band_id` discriminator; components snapshot the identity, the label and the bounds.

**It ships empty.** No band exists until a real tariff boundary is verified (D-096), and
Room's single verified rule carries a **null** band, which under D-094 is the correct
representation of "the treatment does not depend on a band today".

**The bounds are carried and never compared.** `floor_minor` and `ceiling_minor` are for
display and historical explanation only. Nothing in the schema, and nothing in the
resolver, compares them against a revenue amount — a day's aggregate attributable to a band
is not a per-room-per-night tariff (D-094), and `RevenueTaxFacts` carries no money at all
so that the comparison is unavailable rather than merely discouraged.

## D-099 — The local unique tax-rate index is the D-093 contradiction, mirrored
**Date:** 2026-09-01 · **Status:** Accepted — found in Slice 3, fixed in the v11 migration

D-093 found that the Postgres exclusion constraint forbids Room's value bands. Slice 3
found **the same contradiction in the local schema**, shipped since v3:

```sql
CREATE UNIQUE INDEX ux_tax_rates_live_period
  ON revenue_tax_rates (revenue_category_id, effective_from)
  WHERE archived_at IS NULL
```

Two live rules for one category from the same date is precisely what two value bands are.
The local index would have **refused configuration the server had legitimately accepted**,
and it would have surfaced as a sync failure — a reference pull dying on a constraint —
rather than as anything a person could read or act on. Worse than the Postgres version, in
that respect: at least the server refuses at configuration time, in front of the
administrator making the change.

**Decision.** v11 drops it, and a fresh v11 database is never born with it. It is **not
replaced by a wider unique index**, because uniqueness cannot express the doctrine either:
a null discriminator matches every value, so a wildcard rule and a specific one are
distinct rows that a unique index would happily hold while D-094 calls them a conflict.

Ambiguity is decided where the facts are — by the resolver at read time, and
authoritatively by the server (D-095). **This is a cache; it stores what the server sent.**
A cache that second-guesses its source with a weaker rule than the source's own is a cache
that eventually rejects the truth.

## D-100 — A value band's boundaries are write-once
**Date:** 2026-09-01 · **Status:** Accepted — **a defect found by the Slice 4 audit of
Slice 3, corrected before it was mirrored into Postgres**

**Context.** The project lead required Slice 4 to inspect the local v11 band model *before*
reproducing it on the server, and specifically to determine whether it could safely
represent a future boundary change. It could not.

`revenue_value_bands.floor_minor` and `ceiling_minor` were plain mutable columns with a
`row_version`. Nothing stopped an administrator editing a ceiling from ₹7,500 to ₹9,000 in
place. Historical components would have kept their own snapshots and so would have stayed
correct — but the **configuration** would have become unexplainable, and worse:

> Every effective-dated rule referencing that band would have been retroactively
> redefined. A rule that applied to "the lower band" in June would suddenly apply to a
> different range of tariffs — **for dates already recorded** — and nothing anywhere would
> say it had changed.

That is a rule whose applicability was rewritten after the fact, which is the exact class
of harm the date-effective model exists to prevent.

**Decision — immutable bands, superseded rather than edited.** `floor_minor`,
`ceiling_minor`, `code` and `revenue_category_id` are **write-once**, enforced by a
trigger on both the SQLite mirror and Postgres. A boundary change creates a **new band**,
and the old one points at it through `superseded_by_band_id`, so the lineage says
"replaced by" rather than leaving an unrelated-looking row.

The `label` stays editable: a rename that preserves meaning is D-038's permitted case, and
fixing a spelling is not redefining a band.

A band must also describe *some* range — a row with neither floor nor ceiling is a label
pretending to be a discriminator, and is refused.

**Alternatives considered.** *Effective-dated band definitions* — band identity stable,
bounds versioned by date — are strictly more expressive and were rejected as premature:
they add a second date dimension to resolution, which the bounded-dimensions discipline
(D-079) says to add deliberately and only when a verified need exists. No band exists yet
and no boundary change is known. Immutability gives the same auditability with none of
that complexity, and the more expressive design remains reachable later.

**Consequence for collision detection.** Because a band's range is fixed for ever, two
rules can be compared by their bands' **tariff ranges** rather than merely by band id
(brief §5). `app.revenue_rules_overlap` does exactly that: two distinct band rows whose
ranges overlap are treated as overlapping applicability, so distinct ids cannot hide
overlapping financial applicability. That comparison would be unsound against mutable
bounds — which is another way of saying this decision is what makes the collision
algorithm trustworthy.

**How it was found.** By doing what the brief asked: reading the Slice 3 schema instead of
assuming the previous slice got it right. The same instruction found D-098 and D-099. It is
worth noting that three of Phase 4's five architecture findings came from auditing the
*previous* slice rather than from writing new code.

## D-101 — Slice 4 findings: the invariant catches what review does not
**Date:** 2026-09-01 · **Status:** Recorded

Two security-relevant defects reached a working, tested state in Slice 4 and were caught by
assertions rather than by reading.

**1 · Four `app` functions were left executable by client roles.** Postgres grants EXECUTE
to PUBLIC on every new function. The migration wrote explicit revokes for the helpers that
were front of mind — `resolve_revenue_rule`, `revenue_compute`, `next_revenue_number`,
`lock_revenue_category`, `revenue_financial_year`, `assert_revenue_rules_unambiguous` — and
therefore restricted **nothing** for `refuse_band_redefinition`,
`assert_revenue_has_components`, `guard_revenue_rule_write` and `revenue_rules_overlap`.

The API-surface invariant (D-044) refused to apply, naming all four. This is the *same
finding as D-044 itself*, one phase later, in a new place: a default privilege is not a
guard, it is a default. The list is now restated with the revokes beside it.

**2 · The read projection was unusable for every authorised user.** `revenue_document` was
first written `with (security_invoker = true)`, which runs the view with the **caller's**
privileges — and the caller deliberately holds no SELECT on `revenue_entries`. Every
authorised read failed with `permission denied for table revenue_entries`.

The correct pattern was already in the repository: `expense_document` is a
`security_barrier` view that runs as its owner and carries its **own** authorisation
predicate, which is what keeps the base tables ungranted while the projection stays the
only way in. Caught by the live security test on its first run, not by review of the SQL.

**The pattern worth naming.** Both defects were invisible to inspection and obvious to an
assertion. Neither would have been found by a more careful reading of the migration,
because in both cases the code says what its author meant — it is the *environment's
defaults* (PUBLIC EXECUTE, and what `security_invoker` implies about privileges) that
differ from the intent. That is the argument for keeping invariants that fail the deploy
rather than tests that describe the deploy.

---

# Phase 4 Slice 4 audit corrections and Slice 5 — offline resolution (2026-09-01)

## D-102 — A0 made mechanical: provenance is checked, not asserted
**Date:** 2026-09-01 · **Status:** Accepted — **completes A0**

**Context.** The Slice 4 report claimed "seven migrations, all committed" while the
repository held **two** files for **seven** ledger versions. The SQL was equivalent. The
provenance was not, and equivalence is not what an audit trail is for (D-056).

The first correction split the files and wrote `supabase/migrations/LEDGER.md`. That was
still a hand-maintained table, which is the same shape of thing as the reviewed API
surface — and the API surface list only stayed honest because a migration asserts it.

**Decision.** A host test reads the ledger and requires every applied version to be
accounted for by one of the two routes the ledger itself declares: a committed file whose
name ends `_<ledger name>.sql`, or an explicit row in the grouped Phase 2/3 table. Neither
route is "the SQL is equivalent". Every filename the ledger names must exist.

**Two things it caught immediately.**

1. **The A1 and A2 migrations had been applied and never committed** — the exact omission
   A0 exists to catch, caught by A0's own check one slice later. Both were recovered
   verbatim from the server's migration record, following D-056 rather than retyping them
   from memory, because a file that merely resembles what ran is not provenance.
2. **The parity migration's file was named for the version I intended, not the version
   Supabase assigned.** Renamed to match the ledger.

**Positive control:** removing the A1 file and its ledger row fails the test naming
`20260901142248 revenue_rule_completeness`, and only that.

## D-103 — A guard keyed on a naming convention stops working when the convention moves
**Date:** 2026-09-01 · **Status:** Accepted

**Context.** `migration_audit_test.dart` located the authoritative API-surface list by
filename — the latest migration ending `_api_surface_invariant.sql`. A0's new
one-file-per-version convention produced `..._api_surface_invariant_revenue.sql`, which
does not match that suffix, so the test silently read a **superseded** list and reported
four legitimately reviewed revenue RPCs as unnamed.

The failure was loud, which is the only reason this is a paragraph rather than an
incident. Had the naming drifted the other way — a new invariant file the test *did* match
but which no longer restated the full surface — it would have gone quiet.

**Decision.** The invariant file is identified by **what it does**: the migration
containing the `v_api text[] := array[...]` declaration, taking the last one. The test also
fails if no migration declares it at all, because "found nothing to check" must never read
as "nothing was wrong".

**The pattern, again.** D-059, D-068 and D-071 each record a rule that nothing evaluated.
This is the adjacent failure: a rule that evaluates *the wrong thing* because it keys on
an incidental property rather than a substantive one.

## D-104 — The stored form of a tax basis is pinned, not coincidental
**Date:** 2026-09-01 · **Status:** Accepted — **a production defect found by Slice 5**

**Context.** `EnteredBasis` was persisted and parsed through Dart's `.name`, which is
`inclusiveTotal`. Both schemas store `inclusive_total`, verified against the four live
rules in `krishna-mis-dev`. So `EnteredBasis.fromName` would have thrown on **every rule
carrying a basis** — which, since A1 made the column NOT NULL, is every rule that exists.

It survived Slices 2 to 4 because nothing had yet read a rule out of a database into the
domain model. The Slice 2 domain tests constructed `TaxRule` objects directly and were
checking Dart against itself.

**Decision.** `EnteredBasis.wireName` states the stored form explicitly, and `fromName`
parses that and nothing else — an unrecognised value throws rather than defaulting,
because there is no safe default for *"which amount is this"*. Choosing wrongly decides
whether a recorded figure includes tax.

Pinned in two places that cannot both be edited to agree with each other: a host test on
the exact strings, and a **live** test that reads `input_basis` out of the real column and
requires the client to parse it.

## D-105 — Revenue arithmetic parity: the vectors live in the migration
**Date:** 2026-09-01 · **Status:** Accepted

**Context.** D-020 requires one calculation specification with parity proven by tests. For
revenue there are now three executions of it: `TaxRule.compute` in Dart, the Drift-backed
repository that feeds it, and `app.revenue_compute` in Postgres.

The obvious shape — a Dart fixture list and a live test that calls the server — needed a
public RPC wrapper around `app.revenue_compute` purely so a test could reach it. That
expands the reviewed API surface (D-044) for no product reason, and a test-only endpoint
in a financial system is a thing that eventually gets called.

**Decision.** The vectors live **once**, in
`20260901144002_revenue_arithmetic_parity.sql`, which asserts them against
`app.revenue_compute` in a `do` block and **fails the deploy** rather than warning. That is
the pattern migration 0033 already established for the business-date rule (D-067, §14.2),
and `business_date_server_parity_test.dart` already established for reading it back.

**Nothing is created in the database.** The migration holds no DDL — two anonymous
`do $$ … $$` blocks — so the vectors are a `values (…)` literal evaluated at deploy time
and discarded. No table, view, function or type exists to grant, expose or mutate, and
`app.revenue_compute` is executable by neither `anon`, `authenticated` nor `PUBLIC`. The
Dart half parses the **repository file** under `test/`, which nothing in `lib/` references.
Ordinary revenue creation therefore has no runtime dependency on any of this.

`test/support/revenue_parity_vectors.dart` parses that same `values` list, so:

* add a vector to the migration, and Dart is checked against it automatically;
* change an expected figure, and Dart must change to match;
* change either implementation, and the other side's assertion catches it.

Thirteen vectors, chosen for where rounding actually decides something: one paisa, seven
paise, thirty-three paise (the smallest amount where half-up matters), an amount past
32-bit, a configured 0% beside a treatment of `none`, and both exclusive cases. **Exact
integer equality, no tolerance**, plus a separate reconciliation assertion — because a pair
of wrong figures can still add up.

The parser refuses to run on fewer than ten vectors. A parity suite that silently checks
nothing reports success, which is worse than having none.

**Positive control:** the same assertion with one expected figure moved by a single paisa
raises, verified against the live database.

**Result:** 13 of 13 agree exactly across all three engines, and all 13 reconcile.

## D-106 — `configurationUnavailable` is not `noApplicableRule`
**Date:** 2026-09-01 · **Status:** Accepted (project-lead requirement, Slice 5)

**Context.** An empty local rule query returns the same thing in two entirely different
situations: the configuration is synchronised and genuinely has no rule for these facts, or
this device has never received an authoritative snapshot. Both stop a revenue entry.

Collapsing them is how a device with an empty cache starts telling a manager that their
company's tax is not configured — a statement about the organisation, made on the strength
of a network condition.

**Decision.** `RevenueConfigurationUnavailable` is a first-class resolution outcome,
decided **before** the cache is queried rather than inferred from its emptiness. Its
evidence is an `app_meta` key written when reference configuration is pulled, not a row
count: a confirmed revocation legitimately empties the rule cache (D-070), and "no rows"
must never be promoted to "no rules exist".

It carries *why*: `neverSynchronised` or `revoked`. The first is a message about this
device; the second is a message about this user's access. Neither is a message about the
tax configuration, and the wording says so.

**Consequence.** A confirmed revocation therefore stops new offline revenue outright,
rather than letting stale configuration decide a rate. An already-recorded component is
unaffected: it carries its own rate, treatment and basis snapshot, consults no cache, and
stays explainable with no rule rows on the device at all — proven by deleting every rule
and reading the component back.

## D-107 — The live backend suite had been failing since Slice 4, and was carried forward
**Date:** 2026-09-01 · **Status:** Recorded

Three things must be reported plainly.

**1 · A stale assertion survived a checkpoint because the suite was not re-run.**
`phase-a` asserted `snapshot.taxRules, isEmpty` with the reason *"no tax rule is
configured, and none is invented (D-043)"*. That was true and correct through Phase 3.
Slice 4 installed the four verified rules (D-096), so it stopped being the truth — and the
suite was listed as *carried forward* rather than executed, which is exactly what the
project lead had instructed must not happen. It has been restated as the stronger claim it
should always have been: a Crystal Canopy manager receives their own property's rules and
none of Hotel Krishna's, decided by RLS.

**2 · The Slice 4 write-skew tests left 48 rows of scaffolding in the development
project.** Their teardown *archives* what they create, which is the strongest reversal the
real API offers — no client role holds DELETE on financial configuration (D-006), and that
is the correct trade rather than a gap to close by granting one. The consequence is that
archived rules accumulate across runs, so **no assertion may read `revenue_tax_rates`
without filtering `archived_at`**. One did, and failed for that reason rather than for a
defect. The accumulation was cleared administratively; nothing referenced it, no revenue
exists in the project, and the append-only audit rows recording its creation remain
(D-066).

**3 · Four phases of that suite are a sequenced protocol, not self-contained tests.**
`phase-a` to `phase-b` to `phase-c` to `multi-scope-a` to `multi-scope-b` share one
persistent local database and require an administrative grant change between each. Run out
of order or individually they fail by construction, which is not the same as failing. All
seven phases were run in the documented sequence, and the grant fixture was restored to
baseline afterwards.

---

# Phase 4 Slice 6 — Revenue ReferenceSync (2026-09-02)

## D-108 — Configuration completeness is per user, per unit, per dataset
**Date:** 2026-09-02 · **Status:** Accepted (project-lead requirement, pre-Slice-6 check A3)
— **corrects the marker Slice 5 shipped**

**Context.** Slice 5 recorded "this device has an authoritative snapshot" as a single
`app_meta` key, `revenue.configuration.synced_at`. Its presence claimed the whole
organisation's revenue configuration was authoritative. Put under audit before the
transport was built, it was too coarse in three separate ways, and each one is a way to
tell a manager something false about their own company:

* **Scope.** Synchronising Crystal Canopy would have made Hotel Krishna's configuration
  look authoritative. A Room entry would then resolve `noApplicableRule` — *"the Owner has
  not configured a rule"* — on a device that had never been told anything about Hotel
  Krishna. The statement is about the organisation; the evidence was about somewhere else.
* **User.** On the shared back-office workstation D-054 added a sign-out control for, one
  person's successful sync would have vouched for a scope the next person does not hold.
  Authority is per person (D-051 §9); so is any claim made on the strength of it.
* **Dataset.** Tax rules arriving proves nothing about value bands, supply subtypes or
  premises statuses, and the *same resolution* consults all four. A rule naming a band the
  device never received resolves to `missingFact`, which an operator reads as "choose a
  band" when there is no band to choose.

**Decision.** Completeness is recorded where it is actually true. Local schema **v12** adds
`revenue_config_snapshots`, keyed `(user_id, business_unit_id)`, carrying:

| | |
|---|---|
| `status` | `complete` or `revoked` |
| `datasets` | the dataset codes proven present, sorted and comma-joined |
| `generation` | the greatest `change_seq` in the snapshot, so two runs cannot be mistaken for one |
| `confirmed_at` | **server** time, from the confirmed authority — never the device clock |
| `updated_at` | device clock, diagnostics only, decides nothing |

**A complete revenue configuration snapshot, defined.** For one user and one business unit:
the revenue categories of that unit, every tax rule for those categories across *all*
effective dates including end-dated and archived ones, every value band including
superseded ones, every supply subtype, and every premises tax status for the unit. **All
four datasets or none.** Zero rows in a dataset is a perfectly good synchronised answer —
the verified baseline has no bands, no subtypes and no statuses — and *never having asked*
is not the same fact. That is exactly why the record stores a dataset list rather than
inferring completeness from row counts.

**A revocation downgrades rather than deletes.** Deleting the row would stop the device
claiming authority, which is the security-critical half and is not the whole of it: a
device with no row cannot distinguish a user who has lost a property from one who never
had it, and those are different sentences. `status = 'revoked'` with the datasets and
generation cleared is what makes D-106's two gaps reachable — and one of them, `revoked`,
was **unreachable in Slice 5**: both call sites hard-coded `neverSynchronised`, so the
distinction D-106 records existed in the type and never in the behaviour. A rule nothing
evaluates, in the shape of an enum arm nothing constructs.

**The unit is passed, never derived.** `resolve` requires `businessUnitId` rather than
looking it up from the category, because a confirmed revocation legitimately deletes the
category row (D-070) — so deriving the scope from the cache would turn a revocation back
into "never synchronised" and lose the distinction this path exists to preserve. Every
caller picks a property before a category, so the fact is already in hand.

**Consequences.** The old key is **removed** on upgrade rather than translated: it claimed
completeness for an organisation, and there is no honest way to decide retroactively which
user held which scope when it was written. A device that upgrades simply has no proven
snapshot and re-synchronises, which is the correct fail-closed answer and costs one pull.

## D-109 — A policy helper must be published, and this is the second time
**Date:** 2026-09-02 · **Status:** Accepted — a defect this slice introduced and caught

**Context.** Slice 6's read-boundary migration pointed the value-band and supply-subtype
policies at `app.revenue_category_unit`, a `security definer` helper resolving a category's
business unit. An RLS policy expression is evaluated with the **querying user's**
privileges, and `authenticated` deliberately holds no EXECUTE anywhere in `app`. Every
`select` against those two tables therefore failed with

```
permission denied for function revenue_category_unit
```

which took the entire reference pull down with it. No data was exposed; synchronisation
was simply impossible. Found by the live sync returning an empty local database, not by
reading the migration — the SQL says exactly what its author meant.

**This is D-045 again**, where every table returned 403 because the policies called
`app.current_org_id()`. The rule that came out of it then was recorded and did not
generalise into a check: the invariant added at the time asserts that no policy references
the `app` schema *by name*, and this migration passed it, because the reference was to a
function in `app`, not to the schema in a qualified expression the pattern matched.

**Decision.** The helper is published as `public.revenue_category_unit`, granted to
`authenticated` and revoked from `public` and `anon`, exactly as `current_org_id` and
`has_capability` already are. The `app` copy is dropped so there is one of it. The reviewed
API surface is restated to name it (D-044), because a function callable by a client is on
the surface whether or not anybody thinks of it as an API.

The migration now asserts **no policy anywhere references the `app` schema**, in the
general form rather than the one that happened to be checked before.

**What it costs.** An authenticated caller can map a revenue category id to a business unit
id, bypassing that table's RLS. Both are opaque UUIDs and neither is financial data; the
caller is still checked against `has_capability` for the unit, which is the decision that
matters. The same trade `has_capability` itself already makes.

## D-110 — Slice 4's revenue configuration read policies did not work
**Date:** 2026-09-02 · **Status:** Accepted — three defects found by auditing the boundary
before building transport across it

Auditing the read surface before synchronising through it found three policies that had
never been exercised, because the datasets they guard are empty in the verified baseline.

**1 · `business_unit_tax_statuses_read` could never be satisfied by anybody.** It required
the capability `revenue.view.all`, which **no role holds** — not manager, not accountant,
not data_entry, and not owner. The moment a premises status were configured it would be
unreachable by every client, and a rule requiring one would refuse for ever with no way to
fix it from the application. The same family as D-068, D-071 and D-073a — a rule nothing
can evaluate to true — arriving as *unsatisfiable* rather than as vacuously permissive,
which is the quieter half of the same failure.

**2 and 3 · The band and subtype policies were organisation-wide.** A Crystal Canopy
manager could read Hotel Krishna's band and subtype configuration. Not a financial amount,
but configuration about a property they deliberately cannot see — which is precisely what
`revenue_tax_rates_read` already refuses, and what D-107 restated the live `phase-a` to
assert.

**Decision.** All three now say what the tax-rule policy says: this organisation, and a
unit the caller may view. The migration asserts that the capability the new policies name
is actually held by somebody, so an unsatisfiable policy cannot be replaced by another one.

**Why this is worth its own entry.** Nothing was broken *in the application*, because no
band, subtype or premises status exists yet. The defects were latent, and would have
surfaced as "the app refuses every room entry and nobody can see why" on the day a second
tariff band was configured — a long way from the migration that caused it.

## D-111 — A confirmed pull is the current scope, and stale claims are withdrawn on it
**Date:** 2026-09-02 · **Status:** Accepted

**Context.** `ScopeCachePurge` computes what was revoked by diffing the confirmed authority
against the **previously stored** one. `AuthorityStore.loadFor` correctly returns nothing
when the stored authority belongs to somebody else (D-051 §9), so on a shared installation
the sequence *user A syncs, user B syncs, user A syncs with a narrower scope* produces no
diff and no revoked set — while A's completeness record still claimed a property A no
longer holds. A would have gone on resolving new revenue for it offline.

**Decision.** `pullAll` asks for everything and RLS decides what that means, so the units
in a **confirmed** snapshot *are* that user's current scope — including for an org-wide
holder, whose `scopedUnits` is empty by construction (D-025). Every successful pull
therefore withdraws this user's completeness claim for any unit the snapshot does not
contain. It needs no diff and no previous state, which is why it catches what the purge
cannot.

The complement is unchanged and is the thing that must not bend: a **failed** pull
withdraws nothing. An answer that did not arrive is not an answer that said no
(D-048 §1), and both halves are tested.

## D-112 — How old may revenue tax configuration be? — open question
**Date:** 2026-09-02 · **Status:** **Answered 2026-09-02 by the project lead: 24 hours.
See the second D-112 entry below for the decision and how it is implemented.** The text
that follows is the question as it was put, and is left unedited because this log is
append-only — the same treatment D-072 and D-073 received.

**Context.** Slice 6 caches revenue tax configuration and lets a device resolve against it
with no network. The brief asked, correctly, whether there is a limit — and told me not to
invent a TTL if the project has no such policy.

**It has none.** There is no TTL, maximum age or expiry anywhere in the authority or
reference architecture. The existing model is three-valued and says nothing about age:
`confirmed` (asked just now), `stale` (asked before, cannot ask now), `unknown` (never
asked). Cached *authority* already works offline indefinitely on that basis.

**What Slice 6 does today**, stated plainly rather than defaulted: a complete snapshot
permits offline revenue resolution for as long as it stands, with no expiry. That is the
existing policy applied unchanged to a new dataset, not a new decision.

**Why it is nonetheless worth the project lead's attention.** Permissions and tax rates
fail differently when they go stale. A stale permission is caught by the server the moment
a queued mutation is delivered — the client's opinion is never trusted (D-037). A stale
*rate* is not: the rules are date-effective, so a device holding a rule effective
2026-04-01 with no end date will keep applying 5% to business dates after a change it has
never received, and the figure it records will be internally consistent and wrong. The
server would accept it, because on that device's evidence it is correct.

**The question:** should a device refuse to create *new* revenue when its configuration
snapshot is older than some period, and if so what period?

This concerns **new financial creation only**. Revenue already recorded carries its own
rate, treatment, basis and rule snapshot, consults no cache, and is never re-rated — so
retained and historical entries are unaffected by any answer.

*"No limit; the risk is acceptable at this scale"* is a perfectly good answer and is what
the software does today. What must not happen is the software choosing a number nobody
approved, so no number has been chosen.

---

# Phase 4 Slice 7 — Revenue create workflow (2026-09-02)

## D-112 (answered) — Cached revenue tax configuration expires for NEW offline creation after 24 hours
**Date:** 2026-09-02 · **Status:** **Accepted (project-lead decision)** — answers the
question Slice 6 raised and deliberately did not default

**Context.** Slice 6 recorded that the project has no TTL anywhere, that none had been
invented, and why the question was worth asking: permissions and rates go stale
differently. A stale permission is caught server-side the moment a queued mutation is
delivered (D-037). A stale **rate** is not — rules are date-effective, so a device holding
an open-ended rule keeps applying it to business dates after a change it never received,
and the figure it records is internally consistent, wrong, and accepted by the server,
because on that device's evidence it is correct.

**Decision.** A complete, scope-specific revenue configuration snapshot may be used to
create **new** offline revenue for **24 hours** from its server-confirmed timestamp.
Beyond that, creation refuses until a successful authoritative synchronisation.

**What it is not.** Not a general `ReferenceSync` TTL for other masters, not a visibility
rule for existing revenue, not a period lock, and not an authority TTL. It governs one act.

**No override.** Not for the Owner, not for an Accountant. This is a tax-correctness gate,
not an RBAC privilege gate — there is no role whose permission makes a stale rate correct.

**Implementation.**

* The trust anchor is the **server-confirmed timestamp** persisted by Slice 6
  (`revenue_config_snapshots.confirmed_at`), taken from the authority answer. Never the
  moment a cache row happened to be written, which is a device-clock reading and forensic
  metadata only (spec §9).
* Scope is Slice 6's model unchanged: **per user, per business unit, all four datasets**.
  A fresh Crystal Canopy snapshot does not make Hotel Krishna fresh, and one person's
  freshness does not carry another's.
* **The boundary is inclusive.** At exactly 24 hours the snapshot is still usable. Stated
  because "24 hours" is ambiguous until somebody writes down which side the boundary falls
  on, and a rule nobody has stated is one two readers implement differently.
* **Clock skew fails closed.** If the device clock reads materially *earlier* than the
  server's own confirmation of the snapshot, the age cannot be measured and creation
  refuses with its own reason — because a backwards clock would otherwise make every
  snapshot look newly fresh, which is the one direction the error must not go. A five
  minute allowance absorbs ordinary disagreement between two machines. V1 builds no time
  attestation, deliberately.
* `clockUnreliable` is reported **separately** from `expired`, because *"your clock is
  wrong"* sends somebody to fix a different thing from *"your configuration is old"*.
* Where the network is available the caller may refresh before presenting the refusal;
  `RevenueRefusal.refreshMayResolve` says which refusals that could change.

**Expiry touches nothing that already exists.** It does not hide, delete, re-rate or
invalidate recorded revenue, does not destroy retained attempts, and does not alter
historical reporting. An attempt created at 10 hours' age and still pending at 30 hours is
submitted unchanged: it carries its own component snapshot, and the server decides whether
it remains acceptable. D-112 governs the *creation* of a new attempt and nothing else —
tested explicitly, because the tempting reading is the destructive one.

## D-113 — Revenue is checked before it is written, unlike an expense
**Date:** 2026-09-02 · **Status:** Accepted

**Context.** The expense engine always saves locally and lets the server refuse later. That
is right for an expense: its correctness does not depend on configuration the device might
lack, because an amount, a vendor and a category are facts the operator supplies.

A revenue figure is different. Its tax comes from configured rules, so a device that cannot
resolve them cannot produce a defensible number at all.

**Decision.** `RevenueRepository.evaluate` runs the whole contract **before** anything is
persisted — authenticated principal, unit authority, at least one component, a category
that belongs to that unit, an open period, a complete and fresh configuration snapshot,
exactly one resolvable rule per component, every required conditional fact, and exact
arithmetic. Only then does `createLocally` write.

Nothing half-created is left behind for somebody to deal with later, and the refusal is
**structured**: seventeen reasons, each naming a different thing to do about it. "Cannot
save" tells an operator nothing, and a raw exception tells them something they cannot act
on and should not see. A test asserts that no refusal message contains an exception name, a
SQL state, a table name or a refusal code.

**The write is one Drift transaction** — entry, components with their snapshots, and the
outbox intent — so there is no ordering in which a revenue document exists without the
intent to send it, or an intent points at a document that was never written. Proven by
forcing a mid-transaction failure and finding nothing at all.

**A recorded attempt is never re-rated.** The payload is captured at save time and sent
verbatim; a retry delivers the facts the operator approved, not a re-resolution against
configuration that has since arrived.

## D-114 — The client declares what it showed; the server refuses if it disagrees
**Date:** 2026-09-02 · **Status:** Accepted

**Context.** `revenue_create` resolves the rule and computes gross, tax and net itself and
ignores anything the caller says about them. That is correct and stays correct. But its
return payload carried the id, the number and the row version — and nothing about the
money, so a client had **no way to learn** that its own figures differed.

An entry prepared offline under a rule that had since changed would therefore be accepted,
and the operator who approved one GST figure would end up with a document stating another,
with nothing anywhere reporting that the two had ever disagreed. The financial values would
have been silently replaced while the acceptance claimed the approved draft went through.

**Decision.** A component may carry optional `declared_gross_minor`, `declared_tax_minor`
and `declared_net_minor`. They are **compared, never used** — the canonical figures remain
the server's. A mismatch is refused with its own code, `KM030`
(`tax_configuration_mismatch`), carrying both sets of figures and the rule that produced
the server's.

**It becomes a conflict, not a rejection.** Two defensible answers exist and a person
chooses between them — exactly the treatment a stale row version gets, and for the same
reason: financial state is never resolved by silent last-writer-wins (spec §22.1). The
local attempt keeps the figures the operator approved; nothing is repriced behind them.

Omitting the declared values keeps the previous behaviour exactly, which is what makes this
additive rather than a contract break. The canonical totals are also returned now, so a
replay reconciles to the same money and not merely to the same identity.

## D-115 — `revenue_create` had never successfully created a revenue entry
**Date:** 2026-09-02 · **Status:** Accepted — a Slice 4 defect found the first time
anything exercised the path

**Symptom.** Every delivery came back:

```
column reference "financial_year" is ambiguous
```

**Cause.** `app.next_revenue_number` was declared
`returns table(number text, financial_year text)`. Those are OUT parameters, and inside the
body `on conflict (org_id, financial_year)` names the same identifier as the table column
it targets. plpgsql substitutes the variable before the planner sees it, so the statement is
refused outright.

The failure happened *after* every validation passed and after the entry and its components
were inserted, at the point a number is issued. The transaction rolled back, so nothing was
written and nothing was corrupted. The RPC simply could not work.

**Why it survived Slice 4.** That slice proved the **boundary** — RLS, grants, the
projection, the reviewed API surface, the write-skew doctrine — and never created a revenue
entry through it. Thirteen live tests, none of which called the function whose whole job is
to record revenue. The same shape as D-104: two correct halves and no test crossing between
them.

**Fix.** A conflict target cannot be table-qualified, so the collision is removed by
renaming the output columns to `issued_number` / `issued_financial_year`, with the caller
updated in the same migration because those names are the contract between them. The
migration asserts the helper produces a well-formed number, that the counter advances
exactly once, and then **puts the sequence back** — an assertion must not consume a number
a real entry would otherwise have carried.

## D-116 — Three more rules naming a capability that no role holds
**Date:** 2026-09-02 · **Status:** Accepted — the same defect as D-110, in three more places

**Context.** With `revenue_create` finally working, the acceptance read the entries back
through `revenue_document` and got nothing. Not a scoping subtlety: **the projection has
never returned a row to anybody.**

`revenue_document`, `revenue_component_detail` and the `revenue_entries` read policy all
gate on `has_capability('revenue.view.all', …)`. No such capability exists. The catalogue
holds `revenue.view`; `revenue.view.all` is a name that was never granted to any role, so
the predicate is false for every caller including the Owner — and the only sanctioned way
to read revenue returned nothing at all.

D-110 recorded exactly this for `business_unit_tax_statuses_read`, which required the same
non-existent capability. It was fixed there and the pattern was not looked for elsewhere.

**Why it stayed invisible.** The datasets were empty until this slice, and *"the base
tables are not the client API"* passes trivially against a view that returns nothing to
anyone. A test asserting that a scoped user sees less than an Owner passes when both see
zero.

**Decision.** All three use `revenue.view`, which manager, accountant and owner hold.
Access stays per business unit and the base tables stay ungranted: the projection remains
the only way in.

**And the class is closed.** The migration asserts, generally, that **every capability
named by a revenue policy or projection is actually granted to some role**. It earned that
on its first run: it refused the migration and named `revenue.view.all` still present in
the `revenue_entries` policy, which the fix had missed.

*A rule that nothing evaluates is a comment* (D-068, D-071, D-077). This is its quieter
twin: **a rule that can never evaluate true refuses everything, silently, and looks like a
security boundary working.**

---

# Phase 4 Slice 8 — Android revenue entry (2026-09-04)

## D-117 — The D-112 clock-skew tolerance is five minutes, and it is not a general clock rule
**Date:** 2026-09-04 · **Status:** Accepted (project-lead decision) — makes explicit what
Slice 7 implemented

**Context.** D-112 requires the age of a revenue configuration snapshot to be measured from
the **server-confirmed** timestamp, and fails closed when the device clock reads earlier
than that timestamp — because a backwards clock would otherwise make every snapshot look
newly fresh, which is the one direction the error must not go.

"Earlier" needed a number. Slice 7 chose five minutes and the project lead has now approved
it explicitly, so it is a recorded decision rather than a constant somebody picked.

**Decision.** For V1: if the device clock reads **more than five minutes earlier** than the
server-confirmed timestamp of a scope's revenue configuration snapshot, that snapshot's
freshness is treated as **unmeasurable**, and creating new offline revenue is refused with
its own reason — `clockUnreliable`, never `expired`, because *"your clock is wrong"* sends
somebody to fix a different thing from *"your configuration is old"*.

**What it is not.** Not a universal application clock rule, not an authority check, not a
business-date rule, and not a tolerance applied anywhere else in the product. Business
dates are derived from the property's timezone and cut-off under D-067 and are unaffected;
server timestamps remain authoritative for everything they already govern.

**Why five minutes.** It absorbs ordinary disagreement between two machines — the sort a
phone that has not synchronised its time in a while produces — without absorbing a clock
that has been moved. V1 deliberately builds no time attestation: the point is to notice
that the measurement is meaningless, not to prove what the real time is.

**It does not change silently.** The value lives in one place, is named, and is asserted at
the boundary: two minutes' skew is tolerated, two hours is refused, and both are tested.

## D-118 — The Android revenue surface reads its shape from the configuration
**Date:** 2026-09-04 · **Status:** Accepted

**Context.** Slice 8 had to render a form for a category whose number of amount fields, and
whose field labels, are properties of configured tax rules rather than of the category.
Room has one generic rule today and may have two banded ones later (D-081); Banquet is
untaxed and must never be labelled as though GST were inside its figure (D-097).

**Decision.** The entry screen asks the resolved rule set what applies, and renders that.

* `RevenueTaxRuleSet.liveBandsFor` returns the distinct value bands configured for a
  category on a business date. **No band gives one plain amount field**, which is every
  verified category today; two bands give two labelled fields carrying the band identities
  the operator is stating. **No threshold is a constant in application code**, and nothing
  in the widget layer compares an amount against a band's bounds — a band is selected,
  never calculated (D-094).
* The amount field's label comes from `EnteredBasis.fieldLabelFor(treatment)`, so Banquet
  reads *"Amount billed to the customer"* and never *"Customer total (incl. GST)"*. Proven
  on the real Android client, not only in a widget test.
* Every figure in the live preview comes from `TaxRule.compute` — the same call the
  repository makes when it writes. The preview and the record cannot disagree because they
  are one function called twice, rather than two that agree today.

**Consequence.** A second configured Room band is a configuration change and a sync, not a
release. That is asserted rather than claimed: a test configures two bands and finds two
labelled fields.

## D-119 — Three defects the Android surface exposed, and one duplicated rule removed
**Date:** 2026-09-04 · **Status:** Recorded

None of these was visible in the domain, the repository or the server. All three needed a
screen.

**1 · An infinite rebuild.** `withComponentsFor` re-shapes the form from the configuration
and returned a **new** draft on every call, including when nothing had changed. The screen
applies the result with `setState`, so it rebuilt for ever. Found as a `pumpAndSettle`
timeout in the two-band widget test — never as anything a reader would spot, and on a real
phone it would have presented as heat and a flickering form rather than as an error.
Corrected by returning the same instance when the component set already matches.

**2 · A layout overflow on a phone.** The recent-sales row put the sync chip beside the
amounts. `Conflict / Attention Required` is long enough to overflow a 430pt screen by five
pixels — and only in the conflict state, which is the one an operator most needs to read.
The status now has its own line. Worth naming because the money still fitted: a screenshot
would have looked correct.

**3 · A screen that assumed it had been pushed.** Saving called `Navigator.pop`
unconditionally. That is true in production, where the page is always pushed from the quick
-add sheet, and it asserts if the page is ever the root of a route — which the widget suite
made it. It now pops only when there is somewhere to go back to, and otherwise clears to a
fresh form so a second sale can be recorded immediately.

**And one duplicated rule, removed rather than kept in step.** `RevenueRepository` mapped
outbox status to a user-visible sync state with its own `switch`. The project already has
exactly one such mapping — `OutboxStatus.userVisibleState` — and the copy had already
drifted: it called a `blocked` queue a failure, where the canonical mapping calls it
pending, because a queue paused on an authentication problem has not failed at anything.
The copy is gone. Two surfaces describing one entry differently is not a risk worth
carrying for a `switch` statement.

**Also recorded: the acceptance assertion that raced the product.** The first Android
acceptance asserted that a freshly saved sale carries no transaction number. On a fast
emulator the worker had already delivered and reconciled it before the line ran. That is
the product working, and the expense suite records the identical lesson at `expense-simple`:
the assertion is about the durable consequence — one queue entry, attributed — and the
"never fabricated locally" proof belongs in the offline phase, where no number can arrive
at all.

---

# Phase 4 Slice 9 — Windows revenue ledger (2026-09-04)

## D-120 — Sales sit beside Expenses under Transactions, not in a module of their own
**Date:** 2026-09-04 · **Status:** Accepted

**Context.** Slice 9 needed somewhere on the desktop to put a revenue ledger. The easy
option was a new top-level destination beside Transactions.

**Decision.** Both ledgers live under **Transactions**, chosen by a segmented control —
which is what spec §19 lays out (*Transactions → Expenses · Sales · Other Income*) and
what a finance user's day actually looks like. A separate destination would have split one
question about one property across two places.

The tab is held in the page rather than in a route, and both ledgers stay mounted in an
`IndexedStack`. That is not an optimisation: a dense ledger's filters, page and selected
row are worth a minute of somebody's assembly, and rebuilding them on every glance at the
other tab is how a finance user learns not to look.

## D-121 — The desktop ledger filters, orders and pages in SQL
**Date:** 2026-09-04 · **Status:** Accepted

`RevenueRepository.query` takes a `RevenueQuery` — an interface the presentation's
`RevenueFilter` implements, so the data layer never learns that a filter bar exists. Every
predicate is a SQL predicate, which is the shape the expense ledger already proved and the
difference between a screen that opens at a year of history and one that does not
(spec §27).

Three properties are load-bearing:

* **Ordering is `business_date desc, captured_at desc, id desc`.** The third term is not
  decoration. Two sales recorded in the same second on the same day have no defined order
  without it, and an undefined order across a page boundary is exactly how a row gets
  shown twice or skipped. Asserted directly.
* **Dates filter on the business date**, never `captured_at`. A sale rung up at 02:00
  belongs to the previous trading day (D-067), and filtering on the capture instant
  because it is convenient for SQL would put it in the wrong month of somebody's report.
* **Scope is applied in SQL, and it is not a filter.** `businessUnitIds` comes from
  confirmed authority; `businessUnitId` is a choice. Applying authority in Dart after
  paging would compute a window over rows the reader may not have, and `Clear filters`
  deliberately cannot drop it.

**Quarantined work is excluded by the first predicate in the builder**, before any filter
is considered, so no future branch can be written that forgets it. Tests assert that no
status filter, no search and no `include voided` toggle can surface a retained attempt —
and that `listRetainedAfterRevocation` still returns it to its own actor and to nobody
else (D-070, D-074).

## D-122 — The detail panel explains a sale from the sale, never from today's rules
**Date:** 2026-09-04 · **Status:** Accepted

Every rate, treatment, basis and band in the Windows detail panel comes from the
component's own snapshot. Nothing re-queries `revenue_tax_rates`.

That is the whole reason the snapshot exists (D-080): a sale recorded in June under a 5%
rule must still explain itself in December after the rule has been superseded, and a panel
that re-resolved would quietly restate history as though the new rate had always applied.
Proven by deleting every rule and finding the panel unchanged.

**The distinction the panel is most careful about is `none` versus a configured `0%`.**
Both produce ₹0 of tax and they are different statements: one is a treatment somebody
chose, the other a rate somebody set. Banquet reads **No GST**; a configured zero reads
**GST at 0%**. Showing the first for the second would describe a rule that does not exist,
and showing the second for the first would describe a rate nobody configured (D-091).

Multiple components are shown separately, each with its own band, rate and figures, and
the document totals appear underneath. Flattening two tariff bands into one rate would
state a rate that was never applied to anything.

## D-123 — Two layout defects, and the rule that catches them
**Date:** 2026-09-04 · **Status:** Recorded

Slice 8 recorded a status chip overflowing a phone by five pixels, visible only in the
conflict state, which a screenshot would have shown as correct because the money still
fitted. Slice 9 produced two more of the same family, both caught by rendering at
realistic sizes rather than by review.

**1 · A filter dropdown overflowed by 221 pixels.** `DropdownButtonFormField` lays its
selected item out at natural width unless told otherwise; a property named *Crystal Canopy
Rooftop* is wider than the field. `isExpanded: true` makes the ellipsis do its job.

**2 · The table's minimum width had drifted from the columns it was meant to cover.** It
was written down as `940` beside columns summing to `1204`, so the header overflowed by
211 pixels on an ordinary 1366pt laptop — a laptop, not an edge case. It is now **derived
from the column widths**, so the two cannot disagree again.

**The rule this yields.** A hand-picked layout constant beside the values it is supposed
to describe will drift from them, and the drift is invisible until something renders at
the size where it matters. The widget suite now renders the ledger at a laptop, a resized
window and a maximised screen, **in every sync state**, and asserts no exception — because
the states differ in width and the dangerous one is the one an operator most needs to
read.

---

# Phase 4 Slice 10 — Revenue correction and void (2026-09-04)

The guiding rule for the slice, as the project lead set it:

> Correct revenue through auditable mutation. Never silently rewrite financial history,
> never auto-merge a financial conflict, and never destructively delete a revenue
> document.

## D-124 — `revenue_update` differs from `expense_update` in three ways, each deliberate
**Date:** 2026-09-04 · **Status:** Accepted

The correction RPC was written by reading `expense_update` and asking, for each of its
decisions, whether it is right for revenue. Three answers came back different, and the
migration says so at the top of the file rather than leaving the next reader to compare
two hundred lines of SQL.

**1 · The server re-resolves the tax; the client's figures are compared and never used.**
An expense amount is a fact the operator supplies. A revenue figure's tax is not — it comes
from configured rules, so a correction must be re-rated against the entry's category and
its **new** business date. The client sends `declared_gross_minor` / `declared_tax_minor` /
`declared_net_minor` describing what it showed the operator, and a disagreement is refused
`KM030` (D-114) rather than silently replaced. Proven against the real server twice: sending
deliberately wrong figures under the ordinary keys changes nothing, and sending a wrong
figure as `declared_*` is refused with the document untouched.

**2 · Both the source and the target period are checked.** `expense_update` checks only the
period the document is moving *to*. Spec §13.4 says a closed period rejects every write
*affecting* it, and moving an entry **out** of a closed month affects that month's totals as
surely as moving one in. `revenue_update` therefore checks both.

*This is a gap in `expense_update`, surfaced rather than silently changed* — see D-127.

**3 · The business unit and the revenue category are not parameters.** Not refused:
absent. `revenue_update` takes no unit and no category, so a correction that moved revenue
between properties is unavailable rather than guarded, and there is no argument a later
change can forget to check. A live test sends `p_business_unit_id` anyway and PostgREST
refuses the call outright.

**Unchanged, because it was already right:** permission decided before existence is revealed
(D-046); ownership through `revenue.edit.all` or `revenue.edit` plus having recorded it;
`base_row_version` on every mutation; the edit window measured under the property's own
business date (D-067); idempotency by `mutation_id` (D-004); `write_audit` before the
answer is returned.

**The transaction number is not restated.** It belongs to the document's identity and
survives every correction — the defect D-072a records for expenses, where reconciliation
wrote every field back and erased the server-issued number on each edit.

## D-125 — A revenue document has at most one queued intent, and a correction rewrites it
**Date:** 2026-09-04 · **Status:** Accepted

**Context.** An expense edit queues a **new** update intent with a fresh mutation id every
time. That leaves two failure modes, both reachable and neither theoretical:

* **A correction to a sale the server has not accepted yet.** The create and the update sit
  in one batch. If the create fails transiently, the update still reaches the server, finds
  no such document, and is refused `KM015` — **terminal**. A legitimate correction becomes a
  rejection, and the operator is told their entry does not exist.
* **Two corrections before either syncs.** Both carry the same `base_row_version`, because
  both were based on the same local state. The first is applied and the second conflicts
  with a version its author never saw.

**Decision.** A revenue document has **at most one queued intent at a time**, and a
correction rewrites it in place:

```
        queued create  + edit  ->  the create's payload becomes the corrected one
        queued update  + edit  ->  the update's payload becomes the corrected one
        nothing queued + edit  ->  a new update intent, on the current row version
        anything queued + void ->  the void replaces it
```

A create stays a create — the server has never seen this document, and sending an update
for it would be asking to correct something that does not exist. A void replaces a queued
correction because voiding is the operator's later and more decisive intent, and sending
both would ask the server to correct a document and then throw the correction away.

**Nothing is deleted and no attribution is lost.** The queue entry keeps its own
`mutation_id`, its `actor_user_id` and its creation time, so idempotency (D-004), ownership
(D-050) and the retention rule (D-074) all still key on the same values. What changes is the
payload, which is the operator's current intent and is what they would expect to be sent.
A rewritten intent is also made due immediately: the operator has just acted, and making
them wait out a backoff earned by an earlier attempt would be punishing them for the
network.

**Voiding a sale whose create is still queued is refused**, with its own reason. There is
nothing on the server to void, and cancelling the create instead is a different decision —
one this layer does not get to take on somebody's behalf.

**Positive control:** with the coalescing removed — the lookup forced to find nothing, which
is exactly the expense shape — three of the twenty-one repository tests fail. Verified by
doing it.

## D-126 — Review latest replaces the local copy; the attempt survives in the intent
**Date:** 2026-09-04 · **Status:** Accepted

A conflict is two defensible answers with nobody entitled to overwrite the other. Both
refusals that produce one — a stale row version (`KM003`) and a tax mismatch (`KM030`) —
surface as `Conflict / Attention Required`, and the only forward action re-reads the record
first. **There is no merge and no "overwrite anyway".**

`RevenueRepository.applyServerDocument` is the one legitimately destructive act in the
slice: the local row currently holds the operator's refused attempt, and the whole point of
Review latest is to see what the sale actually says now. Two rules make that safe.

**It refuses while an intent may still be delivered.** A `pending`, `inFlight`, `failed` or
`blockedAuth` entry is work on its way to the server, and replacing the row underneath it
would show somebody the server's figures while their own are still about to be applied. A
`conflict` or `rejected` entry is different, and is the case this exists for: it will not be
retried on its own, and **the attempt is preserved in the intent's own payload**, so
overwriting the row destroys no evidence. The predicate is written as an exclusion so a
status added later lands on the refusing side by default.

**Nothing in the outbox is deleted.** The conflicted intent stays inspectable, which is what
D-048 §2 protects, and the sheet shows the operator's figures beside the server's before
anybody chooses. Reapplying reopens the form on the **current** record, so the correction is
re-entered against what the sale now says and carries the version it now holds — re-sending
the old draft with a refreshed version number would be exactly the silent overwrite the path
exists to prevent.

The server document is copied as it stands. Nothing about tax is recomputed on the way
through: that snapshot is the explanation of the server's own figures, and re-deriving it
locally would be this device deciding what the server meant.

## D-127 — Two things three documents claim that the code does not do
**Date:** 2026-09-04 · **Status:** Recorded — surfaced, not silently fixed

Slice 10's audit was asked to read the correction path before extending it. Two claims did
not survive that reading. Neither is fixed here, because both are about **expenses**, and
quietly changing the expense write path inside a revenue slice is how a scope becomes
unreviewable.

**1 · `expense_correct_business_date` does not exist.** `PROJECT_STATUS.md`,
`ARCHITECTURE.md` and `DATABASE_SCHEMA.md` all name it — the first as one of the reviewed
`SECURITY DEFINER` RPCs every financial write goes through. There is no such function in
`supabase/migrations/`, none in `lib/`, and none on `krishna-mis-dev`:

```
        public.expense_create      public.expense_update      public.expense_void
        public.revenue_create      public.revenue_update      public.revenue_void
```

The **capability** is not missing: `expense_update` takes a business date, and so does
`revenue_update`, and both re-check the period and the window when it moves. What does not
exist is the separately named endpoint the documents describe, and `ARCHITECTURE.md` §5.3's
table lists "Business-date correction" as its own row with its own concurrency semantics.
The same shape as D-072 — a surface documented as built, with nothing behind the name.

**2 · `transaction.correct.business_date` is a capability nothing evaluates.** It is in the
catalogue and granted to the accountant and owner bundles, and no policy, RPC or helper in
`public` or `app` mentions it. *A rule that nothing evaluates is a comment* (D-068, D-071,
D-077), arriving as a grant rather than as a check.

**What Slice 10 does about it:** records both, and takes neither. The business date of a
**revenue** entry is corrected through `revenue_update` under the ordinary edit rules, which
is stated plainly here so nothing implies a second endpoint. Whether the expense side gains
the named RPC, or the documents stop naming it, is the project lead's call.

## D-128 — `revenue.edit.all`, and the split revenue did not have
**Date:** 2026-09-04 · **Status:** Accepted

Revenue shipped with a single `revenue.edit`, where expenses have `expense.edit.own` and
`expense.edit.all`. Without the split there is no configured basis for the distinction spec
§13.2 draws between a **Manager**, who records their property's takings, and an
**Accountant**, who exists to correct them: either every manager could correct anybody's
sales, or nobody but the Owner could correct any.

`revenue.edit.all` is added beside it and granted to exactly the roles that hold
`expense.edit.all` — accountant and owner. `revenue.edit` keeps its meaning: correct entries
you recorded yourself. `revenue.void` is unchanged and is held by the accountant and the
Owner alone, because recording a sale does not entitle somebody to erase it from the books.

The catalogue row is written as a **literal**, not selected from `revenue.edit`'s category.
The catalogue is what the client's capability enum is checked against, and a reviewer — or
the parity assertion — has to be able to read the category here rather than infer it from
another row. The parity test caught the select form and refused it, which is the assertion
doing its job.

Both halves of the window rule are proven on the real server, and the second half is the
one that matters: a test asserting only the refusal cannot tell *"the window works"* from
*"the manager can never correct anything"*, and the second would pass just as green. So the
manager corrects their own entry from yesterday (permitted), their own entry from June
(refused `KM021`), and the Owner then corrects the same June entry, which is what
`transaction.correct.beyond_window` is for.

## D-129 — A void is stamped locally as intent, and a refusal is a sentence
**Date:** 2026-09-04 · **Status:** Accepted

Two corrections to what Slice 10 first built, both found by writing the tests.

**`voidLocally` threw where it should refuse.** A blank reason, an already-voided sale and a
sale whose create is still queued are all things a person can act on, and an exception
reaching a widget becomes either a crash or a message nobody can do anything about. All
three are now structured `RevenueRefusal` values with their own reasons, surfaced at the
button — the same discipline D-113 applied to creation. Only *"this sale is not in the local
ledger"* still throws, because it is a programming error rather than a decision.

**The local row is stamped as the actor's intent to void**, exactly as an expense is: the
local write always succeeds and the server decides, and a refusal makes the intent terminal
`Rejected` and keeps it for a person rather than quietly reversing it. Without the stamp the
operator pressed Void and nothing visibly changed, which is the interface saying nothing
happened when something did.

**The panel shows the reason and the server time, not the actor's id.** `revenue_document`
does not expose `voided_by`, and the locally stored value is a raw user id — a UUID rendered
at a manager is not an answer to "who". The server's audit holds the name, and the panel
says what it can support.

**One duplicated read removed.** The detail panel took its sync state from whichever ledger
query happened to have run, which on Android is none — so a phone would have reported
`Synced` for everything. It now comes from `RevenueRepository.syncStateOf`, derived from the
outbox, which is the one place that answer lives (D-119).

---

# Phase 4 Slice 10 — what the mandatory acceptance found (2026-09-05)

Slice 10's implementation was committed at `f7e00e1` with three acceptance phases recorded
as **NOT RUN**. Running them found two defects that every layer below them had reported as
working. Both are recorded here in full, because they are the argument for the phases
existing at all.

## D-130 — A re-applied correction carried the version it was refused on
**Date:** 2026-09-05 · **Status:** Accepted — **a defect found by the §44 two-client chain,
and reachable by nothing below it**

**Symptom.** Client A's stale correction is refused, exactly as designed. A reviews the
latest, sees both figures, and deliberately corrects the sale again against the version the
record now holds. That correction is refused as stale too — and would be, for ever. **A
conflict was unresolvable through the shipped path.**

**Cause.** `updateLocally` coalesces a correction into whatever intent is already queued
(D-125), and the first implementation rewrote the payload while **keeping the queued
entry's `base_row_version`**. The comment beside it explained why: *"an update stays an
update, on the base version it was first based on, because that is still the version the
server holds."*

That sentence is true only while the intent has not been refused. Once the server has
refused it and the operator has reviewed the latest, their new correction is based on the
**current** version, and re-sending the old one is a guaranteed second refusal.

**Fix.** A rewritten *update* intent carries the base version of the correction being
written. In the ordinary pending case the value is identical, because the row has not
moved; it differs only after a conflict has been reviewed, which is precisely the case that
was broken. A rewritten *create* still carries none, because a create establishes a new
identity and has nothing to be based on (D-021).

**This is not the silent rebase §4 forbids.** The value comes from the draft the form was
opened on, which `copyWith` cannot move. It is the version the operator actually looked at,
never one re-read at save time — which is the whole distinction, and the reason the fix is
one line rather than a re-derivation.

**Controls, both seen to fail.** Reverting the line fails the live A1 chain at the
re-applied correction, and fails the new host regression
(`a correction after a conflict carries the version it was made against`). A host test now
pins it, so the live suite is no longer the only thing that would notice.

**Why nothing below it saw this.** Every layer was individually right. The server was right
to refuse a stale version twice. The repository was right to coalesce. The widget was right
to offer Review latest. The defect lived in the *sequence*, and a sequence needs two clients
and a real server to exist at all. This is the same shape as D-104's "conversion nothing
exercised", one level up: **a path nothing traversed**.

## D-131 — The panel derived sync state one way and the ledger another
**Date:** 2026-09-05 · **Status:** Accepted — **a defect found by the §46 Windows
acceptance**

**Symptom.** On the real `krishna_mis.exe`, a correction is refused as a conflict — the
outbox entry says `conflict`, the local row holds the attempted figure, everything
underneath is correct — and the detail panel shows **Synced**, with no conflict banner and
no Review latest. The operator's one signal that their work needs attention was absent, on
the surface that exists to show it.

**Cause, and it is a duplication.** Two derivations of one fact:

```
        the ledger    LEFT JOIN sync_outbox ON entity_id = e.id
                                          AND entity_type = 'revenue_entry'
                                          AND status <> 'done'
        the panel     LEFT JOIN sync_outbox ON mutation_id = e.pending_mutation_id
```

`pending_mutation_id` is a denormalised pointer, and on the accumulated Windows database it
was null on a document whose correction had just been refused. The ledger, joining on the
document's id, knew better — so two surfaces in the same application described one sale
differently, which is the exact risk D-119 recorded when it deleted a duplicated status
mapping. It came back as a duplicated *query* instead of a duplicated `switch`.

**Fix, in two parts.**

1. **One derivation.** `watchSyncState` uses the ledger's join, and `syncStateOf` delegates
   to it, so the snapshot and the stream cannot disagree either. Nothing in the revenue
   read path consults `pending_mutation_id` any more.
2. **A stream, not a snapshot.** A conflict is delivered by the **sync worker**, which
   invalidates no provider and knows about no screen. A `FutureProvider` therefore kept
   whatever it read when the panel was first opened. `revenueSyncStateProvider` is now a
   `StreamProvider` over the outbox, and `revenueDetailProvider` watches it — so a
   transaction number arriving, a correction being refused, or a document being replaced by
   Review latest all reach the surface without anybody remembering to invalidate.

**Why the widget suite did not catch it.** Every widget test constructs its own state and
then renders once. Neither half of this needs a second render: the wrong join returns the
wrong answer immediately, and the staleness needs a *worker* to change something after the
first read. Only a real client, against a real server, with a real background worker, does
both.

## D-132 — Response loss is proven by losing a response, not by calling twice
**Date:** 2026-09-05 · **Status:** Accepted

The brief was explicit: *do not pretend a normal duplicate RPC call proves response-loss
recovery.* It does not. A duplicate call proves idempotency, and idempotency is not the
scenario — in a duplicate call the client was told the outcome the first time, and the state
that matters is the one where it was not.

`ControllableTransport` therefore gained a second mode beside its offline switch. With
`loseResponseOnceFor` set, the next matching request is **sent**, the server **answers**,
the response body is **drained**, and only then does the transport throw the platform's own
`SocketException`. The server has committed; the client knows nothing. Nothing above the
cable is simulated, which is the same honesty D-058 established for the offline case.

Both mutations are proven that way against `krishna-mis-dev`, through the real repository
and the real worker: an update (§E) and a void (§A3). In each the retry replays the **same**
mutation id — a fresh one would be a second financial record for one act, and nothing
afterwards could tell them apart — the document moves exactly one row version, the KI-REV
number is unchanged, no component is duplicated, and the audit holds one effect.

## D-133 — A mutation id may be reused across a reviewed conflict, and only there
**Date:** 2026-09-05 · **Status:** Accepted — recorded because the acceptance made me
reason it out rather than assume it

The A1 chain showed that a correction re-applied after Review latest is delivered under the
**same** mutation id the refused one carried, because it rewrote the queued entry rather
than starting a second piece of unsent work (D-125).

That is safe, and the argument is narrow enough to be worth writing down:

* a **refused** delivery consumes nothing — `processed_mutations` holds no result for it,
  so the id is still unused;
* the only statuses from which a new correction can reach an existing entry are `conflict`
  and `rejected`, and **both mean the server saw the intent and did not apply it**;
* `applyServerDocument` — Review latest — refuses to run while an intent is `pending`,
  `inFlight`, `failed` or `blockedAuth`, so the id can never be reused over a delivery whose
  outcome is unknown.

Take away the third rule and the reuse becomes unsafe: a lost response leaves an intent
whose outcome nobody knows, and reusing its id for a *different* correction would let the
server replay the old result and silently discard the new one. The guard that makes Review
latest safe is therefore also the guard that makes id reuse safe, which is why they are
stated together rather than in two places.

The acceptance asserts the consequence directly: the refusal left **no audit row at the
time it happened**, counted then rather than inferred afterwards, and exactly one financial
effect exists under that id at the end.

## D-134 — There are two composition roots, and they are now compared rather than trusted
**Date:** 2026-09-05 · **Status:** Accepted — a defect the §46 acceptance found in the
acceptance harness itself

**Symptom.** On the real `krishna_mis.exe` the conflict banner appeared correctly and
**Review latest did nothing**: it showed *"Connect to the internet to see what this sale
says now"* on a machine with a working connection.

**Cause.** `revenueGatewayProvider` defaults to null and is overridden in `main()`. The
acceptance harness builds the application itself, with its own override list, and that list
did not name the new provider — so the harness was driving an application in which the
conflict path had no way to re-read anything.

**This has now happened twice**, and the harness's own comment says so: the attachment
upload worker was missing from the same list, which left a bill `staged` for ever while the
shipped build moved it on. The comment beside it reads *"the acceptance must assemble the
application the same way `main()` does, or it is exercising a different application"* — and
that sentence was a comment rather than a check, which is the failure this project has
recorded under three different names (D-068, D-071, D-077).

**Decision.** The two lists are **compared**, not each trusted. A host test extracts every
`…Provider.overrideWith…` from `lib/main.dart` and from the acceptance harness and requires
the harness to cover everything `main()` overrides. Adding a provider to `main()` and
forgetting the harness is now a failing test rather than an acceptance phase that quietly
proves something about a different application.

**Positive control:** removing the override from the harness fails it, naming the reason.
Verified by doing exactly that.

**What it does not assert.** That the harness overrides *nothing extra* — it legitimately
does, because it injects a controllable transport and sometimes a synthetic attachment
source. The direction that matters is the one that was wrong.

## D-135 — A streamed read model needs a disposal the test body performs
**Date:** 2026-09-05 · **Status:** Accepted — a consequence of D-131, recorded because it
looks like a hang and is not one

Making the sync state a Drift stream gave the detail surface a **live query
subscription**. Drift schedules a zero-duration timer when one is cancelled, and Flutter
checks for pending timers at the end of the test **body** — before `addTearDown` runs. So
every widget test that rendered the panel and stopped failed with *"A Timer is still
pending even after the widget tree was disposed"*, which the runner reports as
`did not complete` and which reads, in a suite of thirty, exactly like a hang.

The disposal therefore has to happen inside the body, and a per-test call is a thing to
forget. `test/support/ui_test.dart` wraps `testWidgets` once: run the body, pump an empty
tree so the scope disposes and the subscription cancels, pump once more so the
cancellation timer fires. Both revenue widget suites use it.

Worth recording rather than fixing silently for two reasons. It is the **cost** of D-131 —
a streamed read model is more correct and is not free — and it is a failure whose message
points at the framework while the cause is the application's own subscription. The next
person to stream a read model will meet it.

---

# Phase 3 corrective — expense business-date correction (2026-09-05)

Approved by the project lead after the Slice 10 audit recorded it (D-127). **Option A**:
`expense_update` stays the one Expense correction contract, and the documents that
described a second endpoint are corrected rather than the second endpoint being built.

## D-136 — An expense could be lifted out of a closed month, and that is now refused
**Date:** 2026-09-05 · **Status:** Accepted (project-lead decision) — **a financial
integrity defect, proven against `krishna-mis-dev` before anything was changed**

**The defect, demonstrated rather than argued.** `app.validate_expense_allocations` only
ever sees the periods in the **incoming payload**. It can say where an amount is going and
never where it is being taken *from*, so `expense_update` protected the target period and
not the source. A probe against the shipped function:

```
        contributions BEFORE   {2026-03: 4500000}
        2026-03 closed for Crystal Canopy
        expense_update -> business_date 2026-04-10
        applied                {status: applied, row_version: 3}
        refused                null
        contributions AFTER    {2026-04: 4500000}
```

₹45,000 left a **closed** month. Its Total Expenses and Operating Profit changed, through
an ordinary edit, with nobody's permission and no reopen. Spec §13.4 rejects "every
create, edit, void and business-date correction **affecting** that period", and the
operative word is *affecting*: removing an amount from a closed month affects it as surely
as adding one. `expense_void` has always understood this and `revenue_update` applies it
(D-124); `expense_update` did not.

**Decision.** Before any mutation, the periods the expense **currently** contributes to are
each required open, read from `expense_period_allocations` — the one place an expense's
period attribution lives (D-060). The target periods keep being checked inside the
validator that create and update share, so an edit can never introduce a placement a
create would refuse.

Reading the source from the **contributions** rather than from `business_date` is what
makes a cross-period bill safe. A ₹60,000 invoice split May/June contributes to both
months; a guard keyed on the document's own date would have missed the other one entirely,
and that case is now a live test of its own. No P&L arithmetic is re-implemented for the
lock check — the rows a report will sum are the rows checked.

**Doctrine, unchanged by any role or capability:** closed source → refused; closed target →
refused; both open → the ordinary checks continue. The RBAC Owner holds every capability
there is and none of them is permission to change a closed month; reopening remains the
separate, reasoned, audited act it has always been. Proven both ways in the same test: the
Owner is refused, reopens deliberately, and the same correction is then accepted — which is
what makes the refusal a lock rather than a wall.

## D-137 — Moving a business date is a first-class act, not an edited field
**Date:** 2026-09-05 · **Status:** Accepted (project-lead decision)

Three further findings from the same audit, and the reason the fix is more than one
`require_period_open` call.

**The move is detected from canonical state.** `p_business_date is distinct from
e.business_date`, decided inside the transaction. No client boolean says "this is a
correction": a caller able to declare its own act would be choosing which rules apply to
it. The client computes the same thing to shape its form and sends it as nothing.

**It requires `transaction.correct.business_date`** — granted to the accountant and owner
bundles since Phase 2 and, until today, **named by 0 functions and 0 policies** on this
project. *A rule that nothing evaluates is a comment* (D-068, D-071, D-077); this one
arrived as a grant rather than as a check, which is the quieter shape of the same thing. It
is scoped per property the document charges, so scope still applies.

**It requires a reason**, and the reason lives in `audit_logs.reason` — append-only, the
same field `expense_void` already uses — rather than in a new column that would be a second
source of truth for one fact. Required only on the branch where the date actually moves, so
an ordinary correction gains no field and the fast path is untouched.

**A moved date says so.** `business_date_source = 'corrected'` (D-019), written on that
branch and only on it: every row on the development project read `derived`, including ones
the acceptance suite had moved. An ordinary later edit to an already-corrected row does not
restate it, because provenance that re-fires on every save stops being provenance.

**And it gets its own audit action**, `expense_business_date_corrected`, carrying both
dates, the reason and the actor — so "which dates were moved, by whom, and why" is one query
rather than a diff of every edited row.

**The capabilities compose; none replaces another.** `transaction.correct.business_date`
authorises the *kind* of act and grants no relief from the edit window, the period locks,
the unit scope or `base_row_version`. `transaction.correct.beyond_window` lifts the age rule
and authorises no date move. Both directions are proven live with the seeded bundles; the
one combination they cannot express — holding the date capability without the window one —
is asserted structurally in the migration instead, and that limit is stated rather than
glossed.

**One contract.** No `expense_correct_business_date` is created. Three canonical documents
named it and the server has never exposed it; the documents are corrected,
`ARCHITECTURE.md` §5.3's row is restated as *"inside `expense_update` / `revenue_update`"*,
and §24 states the contract in full. `MutationOp.correctBusinessDate` is **removed** from
the client for the same reason: nothing ever produced one, and an op no endpoint dispatches
is answered terminally by the router — so leaving it available would have turned the first
real correction into a permanent rejection.

**The surface.** The Expense edit form already had a business-date row, so this changes an
existing control rather than adding a screen. In edit mode it opens only for a holder of
the capability — the date is still shown, because it is part of the document — and a reason
field appears the moment the date differs from the one the form was loaded with. That
loaded date is captured once, at load, and `copyWith` cannot move it, exactly as
`baseRowVersion` cannot (D-072a): a field that moved on every keystroke would stop calling
an edit a correction halfway through typing it. Recording a *new* expense against a chosen
date is untouched — that is `manual`, not `corrected`. Hiding the control is not the
security boundary; the server refuses regardless.

## D-138 — `btrim(text)` strips spaces and not tabs, and a tab is not a reason
**Date:** 2026-09-05 · **Status:** Accepted — a defect **in the fix**, found by the live
case written to distinguish "empty" from "blank"

The first migration tested the reason with `length(btrim(coalesce(p_correction_reason,
''))) = 0`. One-argument `btrim` removes **spaces only**. So `'   <tab>  '` trimmed to a
single tab, measured 1, and was accepted: the rule that a correction always states why
would have been satisfiable by pressing one key, and the audit row would have carried a tab
where the reason belongs.

Corrected to `regexp_replace(…, '^\s+|\s+$', '', 'g')`, with the value table asserted at
deploy time in the pattern 0033 established — including the positive control that raises if
`btrim` ever starts stripping tabs, because the finding would then no longer reproduce and
the reasoning would need re-reading.

**Fixed in its own migration rather than by editing the applied one.** The committed file
for `20260905141738` is byte-identical to the statements the server ran, verified by hash
rather than by resemblance; rewriting it to look like something that never ran is the exact
substitution A0 and D-056 exist to prevent. Two ledger versions for one corrective is the
honest record of what happened.

**Recorded and deliberately not changed:** `expense_void` and `revenue_void` test their own
mandatory reasons with the same one-argument `btrim`, so a single tab satisfies both. Same
defect class, different reviewed scope (D-127). It is reported rather than fixed in passing.

## D-139 — A capability granted in production and evaluated nowhere fails the build
**Date:** 2026-09-05 · **Status:** Accepted

Two invariants, because one can be checked before a deploy and the other only against the
live catalogue.

A **deploy-time** assertion in the migration: every capability the catalogue grants to some
role must be named by a function body or a policy expression on the server. A **host**
assertion over the migrations, so the same question is answered before anything is applied.

Four capabilities are exempt, named individually rather than matched by a pattern:
`reports.view`, `reports.export`, `reports.print`, `settings.manage` — the surfaces they
govern are Phase 5 and Phase 7 and do not exist yet. That is a list a later phase deletes a
line from, not a rule that absorbs the next dead grant; a second assertion fails if a listed
capability ever *acquires* an evaluator, so the excuse cannot go stale.
`transaction.correct.business_date` is deliberately not on it: its surface shipped and ran
while the capability went unread, which is the whole finding.

**The host assertion earned its place by being wrong twice, in the same way, in one hour.**
Written first as "the capability appears somewhere in the migrations", it let a deliberate
sabotage pass — because the *comment explaining that nothing evaluates it* counted as its
evaluator. Narrowed to strip comments, it still passed: the deploy-time assertion asserting
that something evaluates the capability counted too. It now reads **function bodies and
policy expressions only**, which is what "evaluated" means, and the sabotage fails it.

That is the fourth time this project has had to find a control by expecting red and getting
green (D-071, D-074, D-094, and now this). The lesson does not seem to generalise on its
own, so it is written down again: **a check is not a check until it has been seen to fail.**

---

# Phase 4 corrective — revenue business-date correction governance (2026-09-05)

## D-140 — The revenue parity audit, and the three things it actually found
**Date:** 2026-09-05 · **Status:** Accepted (project-lead decision) — **not a mirror**

The brief was explicit: do not mirror the expense contract into `revenue_update` on the
strength of symmetry; prove the current behaviour first. Audited point by point against the
shipped function, four of the seven requirements were **already met** and are untouched:

| | |
|---|---|
| source **and** target period checked | already correct (D-124) |
| tax re-resolved against the **new** date | already correct (D-124) |
| `KI-REV` preserved across a correction | already correct |
| `base_row_version` concurrency | already correct |

Three were missing, and a probe proved it rather than a reading of the SQL. A **Manager** —
holding `revenue.edit` and not `transaction.correct.business_date` — recorded a sale and
then moved its business date from 2026-09-04 to 2026-09-03:

```
        update applied   {status: updated, row_version: 2}
        update refused   null
        audit actions    [{action: edited, reason: null}, {action: created, reason: null}]
```

No capability asked for, no reason collected, no distinct audit action. Spec §9 requires a
business-date correction to be "subject to permission" and "audited with before and after
values, actor, timestamp **and reason**", and spec §14 lists **business date corrected**
among the audited actions. Neither section is scoped to expenses, and a revenue entry
carries a business date like any other financial row. So this is a governance gap in the
revenue engine rather than an argument from symmetry, and it is a **Phase 4 corrective
defect found after Slice 10 closure** — a separate commit, with Slice 10's history left
exactly as it is.

**The detection compares dates, not period keys.** `revenue_update` already computed a
target period key, and a guard keyed on that would have seen no change at all when a sale
moved from 15 June to 20 June — which is what most real corrections look like. Tested
explicitly.

**No `business_date_source` is added to revenue.** The expense document has one (D-019);
`revenue_entries` never has, and spec §8.0 enumerates what a revenue entry carries without
including it, while spec §9 says the record notes how its date was arrived at. Those two
readings disagree, and settling a product question by copying the expense schema is exactly
what the brief forbade. **Raised for the project lead, not decided here** — see the open
question in `PROJECT_STATUS.md`.

**There is no revenue business-date control in the client**, and none is built here: the
Android and Windows revenue surfaces show the trading day and do not offer to change it.
The server boundary is corrected anyway, because `revenue_update` takes the parameter and
the boundary is where authority lives (D-037). The repository carries a correction reason
so the surface can supply one the day it exists, and so an authorised correction queued
offline delivers its reason with it.

## D-141 — Three acceptance assertions that could only pass on a fresh database
**Date:** 2026-09-05 · **Status:** Accepted — found by running the regression set, not by
reading it

The Phase 3 regression run surfaced three defects in the *suites*, all of the family D-074
records: **a test whose fixture is recreated every run cannot see a defect that needs
history.** The Windows machine's persistent database taught that lesson once; here it was
`build/live_test.sqlite`, which the phased live suite keeps between runs and across
identities.

1. **The expense fixture teardown voided at a hard-coded `base_row_version: 2`.** Every
   document the new correction tests create sits at v3, so the teardown would have silently
   failed to reverse exactly the fixtures this work added — reporting nothing. It now reads
   the version first. Verified: **zero** open expenses created during this session remain.
2. **A Slice 6 phase asserted that every revenue configuration snapshot is `complete`**,
   over *every user's* rows. Completeness is keyed (user, unit) since D-108, and a `revoked`
   snapshot belonging to a manager whose scope an earlier phase deliberately withdrew is the
   correct record of that withdrawal. It now asserts about the signed-in user, which is what
   the phase established.
3. **The offline-resolution phase resolved as `rows.first.userId`** — the Owner on a fresh
   database, and on an accumulated one a manager with a stale snapshot, so a device whose
   configuration had just arrived intact reported `configurationUnavailable`. It now picks
   the most recently confirmed complete snapshot **for the property being resolved**. And
   its sibling assertion, "no revenue was created doing it", was `isEmpty` — true only until
   the Slice 7 create phase wrote revenue into the same file — so it now counts across the
   phase, which is what the sentence actually claims (D-076).

All four phases were then run **twice in succession**, in the documented order, and passed
both times. A phase that can only pass once is not a regression test.

---

# Pre-Slice-11 corrective — two approved items (2026-09-05)

## D-142 — A mandatory financial reason rejects every whitespace-only value
**Date:** 2026-09-05 · **Status:** Accepted (project-lead decision) — closes the defect
D-138 recorded and deliberately left unfixed

**The defect, proven against the shipped functions before anything was changed.**
One-argument `btrim`/`trim` strips **spaces only**:

```
        expense_void(p_reason => E'\t')   applied, row_version 3
                                          audit reason: "\t"
        revenue_void(p_reason => E'\t')   applied, row_version 2
                                          revenue_entries.void_reason: "\t"
```

Two financial documents were permanently voided, and the only record of *why* is a tab.
Spec §14 requires the act to carry a reason; the rule that a void always states why was
satisfiable by pressing one key. Both engines, both boundaries.

**Decision.** One rule, in one place. `app.stated_reason` removes every leading and
trailing whitespace character and returns what is left; both voids call it, and so does
the business-date correction reason D-138 introduced. Neither boundary carries its own
regex to drift from the other — which was D-138's own finding, arriving a second time.

The helper is `immutable`, lives in `app`, is revoked from `public`, `anon` and
`authenticated`, and is **not** an addition to the reviewed API surface (D-044).

**What is stored is the normalised value**, which is the project's existing trimming
convention: `period_reopen` has always stored `btrim(…)` and the correction reason stores
its trimmed form. Storing `'  Duplicate  '` verbatim on a void while a correction stores
`'Duplicate'` would be the inconsistency this exists to remove. Internal spacing,
punctuation and case are the operator's and are untouched — asserted, because "trim" and
"squeeze" are one careless `regexp_replace` apart.

**The table backstops are tightened too, and are `NOT VALID` — for a good reason.** Both
`void_has_reason` CHECKs used the same spaces-only trim, so the backstop was weaker than
the boundary it backs. They now carry the strict expression, inlined rather than calling
the helper (a CHECK that calls a function is not re-validated when the function changes,
which would quietly make the constraint a comment) — and the migration asserts the two
forms agree value for value, so the duplication is checked rather than trusted.

They are `NOT VALID` because **the two probe fixtures cannot be repaired**.
`app.refuse_voided_mutation` refuses every update to a voided financial document,
including one issued as the table owner, and it was right to: history is corrected by void
and re-entry, never by rewriting a row (D-006). The choice was between rewriting voided
history to make a constraint validate, and enforcing the rule from here on. The second is
obviously correct, and it is a good sign rather than a bad one — two guarantees held at
once and the older one won.

**The positive control was seen to fail, in both engines.** The production helper was
temporarily replaced with the old `btrim` body — the one seam both boundaries now share —
and the tab-only case turned red on the expense void and on the revenue void. The
production body was then restored and both matrices re-run green.

That restore is worth recording, because the first attempt at it **silently did not
happen**: the `create or replace` was batched with a `do` block whose assertion had a
mis-escaped literal, the raise aborted the transaction, and the degraded helper stayed
installed. It was caught by reading the state back rather than by trusting the statement,
and the lesson is the ordinary one — *a restore is not restored until it has been read
back.*

**Recorded and deliberately not changed:** `public.period_reopen` normalises its own
mandatory reason with `btrim(coalesce(p_reason, ''))`, and `period_lock_events` carries
the same spaces-only CHECK. Same defect class, and **outside the two approved items** of
this corrective, which name the Expense and Revenue void boundaries. Reopening a period is
a different governance act with its own decision record (D-026), and widening a reviewed
scope because the fix would be small is how a scope stops being reviewable (D-127).
`app.stated_reason` is shaped so that closing it later is one call per site.

## D-143 — Revenue records how its current business date was established
**Date:** 2026-09-05 · **Status:** **Accepted (project-lead decision)** — an approved V1
requirement, settling the question D-140 raised and deliberately did not decide

**The question.** `expenses.business_date_source` has existed since Phase 3 (D-019);
`revenue_entries` had nothing. Spec §8.0 enumerates a revenue entry's fields without it;
spec §9 says the record notes how its date was arrived at. Those readings disagreed, and
D-140 refused to settle a product question by copying the expense schema.

**It was a three-way disagreement, and building it found the third.**
`DATABASE_SCHEMA.md` lists `business_date_source` on `revenue_entries` **twice** — in the
Phase 0 sketch and in §6.1's approved Phase 4 shape — and the Slice 4 implementation
shipped the table without it. Nobody noticed for six slices, because nothing read a column
that did not exist. So two of the three canonical documents already said yes, and what
looked like an open product question was partly an unrecorded implementation gap. The
decision below is still a decision — §8.0 had to be amended either way — but it is worth
knowing that the plan was right and the code was the thing that diverged.

**The decision: revenue carries provenance**, and §9 governs. The reason is reporting.
Revenue feeds Net Sales, which feeds Operating Profit, and the period a sale lands in is
decided by its business date. Whether that trading day was derived by the cut-off rule or
moved by a person afterwards is a durable financial fact about the row, and answering it
should not require reconstructing an audit sequence.

**Two values, not three.** `derived` and `corrected`. Expense also has `manual` — a date
chosen while *recording* — and revenue has no such path: no revenue surface offers a
trading day at entry, and `revenue_create` takes no provenance argument. A column
admitting a value nothing can produce would claim the system can do something it cannot.
A third value later is a migration and a decision.

**The enum is shared, and its wire names are now explicit.** `BusinessDateSource` is
reused rather than duplicated per engine: it is one concept and one stored vocabulary. Its
stored form is stated on the enum and pinned by a host test rather than being `.name` —
they agree today, and that is exactly the shape of D-104, where `EnteredBasis` was written
and read through `.name` while both schemas stored the snake-case form. *A wire name that
is a coincidence is a wire name waiting to break.* `fromWire` throws on anything else,
because there is no safe guess between "the cut-off derived this" and "somebody moved it".

**The server owns it.** `revenue_create` states `derived` itself and has no provenance
parameter; `revenue_update` writes `corrected` only on the branch where it has already
established, from canonical state, that the date moved. Every refusal — stale version,
closed period, missing capability, blank reason — happens before that write, so a refused
correction leaves the provenance exactly as it found it. **Once corrected it stays
corrected:** an ordinary later edit preserves the value, because the question is how this
trading day came to be and a subsequent amount correction does not change that answer.

**The client copies, and never derives.** Both write paths return the canonical value; the
acceptance carries it; the reconciler writes what it was told and, when the answer states
nothing — a replayed result from an older build — leaves the local value alone rather than
guessing (D-072a's rule about fields the server did not restate). The local update path
deliberately does **not** write provenance: a local correction is an attempt, and writing
it there would let a refused correction leave a device claiming a corrected trading day.

**Backfill is `derived`, and nothing cleverer.** Nothing infers a past correction from
`updated_at`, a row version, notes or a date comparison — none of those is evidence.
There *is* exact canonical evidence for two rows in `audit_logs`, and both belong to
voided development fixtures with no open corrected entry anywhere, so backfilling from the
audit trail would be machinery written to move two voided test rows. Deliberately not
written, and recorded as a decision rather than an oversight (all 307 existing rows are
`derived`, asserted at deploy).

**It does not replace the audit trail.** `business_date_corrected` still carries the old
date, the new date, the reason, the actor, the server timestamp and the mutation id — the
historical sequence, and it now carries the old and new provenance too. The column answers
one question about the row as it stands now. Phase 5 may read it and **must not let it
alter an amount**: aggregation stays keyed on the business date and the contribution
model.

**No UI is built for it.** It is provenance, not operator input, and no current surface
needs it; the domain and storage are correct and Slice 10's surfaces are untouched.

**Spec §8.0 is amended** to list the field, so the two readings no longer disagree.

## D-144 — A column added to a table created by a later migration needs a version floor
**Date:** 2026-09-05 · **Status:** Accepted — a real migration defect, caught by the one
fixture old enough to take the path

Local schema **v13** adds `revenue_entries.business_date_source`. Written first as
`if (from < 13)`, it failed on a device coming from **v9**:

```
        duplicate column name: business_date_source
```

`revenue_entries` is created at v11 **from the current table definition**, which now
includes the column — so a device upgrading from v10 or earlier already has it by the time
the v13 step is reached. The guard is therefore a range, `from >= 11 && from < 13`, and
the comment says why: every column added to a table that is itself created by a
later-than-v1 step needs one.

Found by the v9 attachment-migration fixture, which exists because D-073a's own migration
failed on a machine that had real v9 rows. The same fixture, catching the same class of
defect, two phases later — which is the argument for completing a fixture rather than
narrowing it.

Recorded beside it: two schema tests asserted `PRAGMA user_version` against a hard-coded
`12`. Their subject is "the database opens at the current version", not "at 12", so they
now read `db.schemaVersion` and do not need editing on every bump.

---

# Final pre-Slice-11 corrective (2026-09-05)

## D-145 — Reopening a closed period states why, and the rule is now project-wide
**Date:** 2026-09-05 · **Status:** Accepted (project-lead decision) — closes the last of the
five mandatory financial reasons, which D-142 recorded and deliberately left

**The defect, proven against the shipped function before anything was changed.**
`period_reopen` normalised its mandatory reason with `btrim(coalesce(p_reason, ''))`:

```
        period 2026-05 / Crystal Canopy · lock 6fce38ca-9a3d-4ec7-b2ce-e157199c38df
        closed legitimately                  state: closed, row_version 1
        period_reopen(p_reason => E'\t')     APPLIED, state: open, row_version 2
        refusal                              none
        period_lock_events                   {action: reopen, reason: "\t"}
        audit_logs                           {action: period_reopened, reason: "\t"}
        period_locks.reopen_reason           "\t"
        actor                                the Owner
```

A **closed financial period was reopened** — the most privileged financial act this system
has, the one spec §13.4 reserves to the Owner and D-026 requires to record "actor, timestamp
and a mandatory reason" — and the entire justification on record is a tab. Every downstream
protection worked exactly as designed; the thing that failed is the only one that was
supposed to make the act accountable.

**Decision.** `period_reopen` uses `app.stated_reason` (D-142). The restatement changes two
lines. Every other protection is asserted, by name, to have survived it: the capability
(unscoped for an organisation-wide reopen, per-unit otherwise), the reason checked *after*
the capability so a caller who may not reopen is not taught how to phrase a request they
cannot make, the period lookup, the not-closed refusal, `base_row_version`, the append-only
`period_lock_events` row, the audit row and `mutation_id` replay.

**The rule is now stated once, for all five.** Spec §14.1 records the requirement — void an
expense, void a revenue entry, correct either business date, reopen a period; a
whitespace-only reason is refused; internal spacing is content — and deliberately does *not*
record the mechanism, which is an implementation matter.

**And the invariant is a search, not a list.** Both the migration and a host test find every
function that can raise `reason_required` and require each to decide it by the canonical
rule — the helper, or the identical expression inlined. A list is something somebody has to
remember to extend, and the sixth mandatory reason is exactly the one that would arrive
without anybody remembering. Proven to have teeth by putting `btrim` back and watching it
fail.

**The caller audit, in full.** Five, and only five, functions can refuse for a missing
reason:

| | Rule |
|---|---|
| `expense_void` | helper (D-142) |
| `revenue_void` | helper (D-142) |
| `revenue_update` — business-date correction | helper (D-143) |
| `expense_update` — business-date correction | the identical expression, inlined |
| `period_reopen` | helper (this decision) |

`expense_update` predates the helper by one migration and carries the expression rather than
the call. Its semantics are identical, the invariant accepts either form and would fail on a
weaker one, and restating a large financial function for no behavioural change is the worse
trade. **Reported rather than refactored** — the brief's instruction not to turn this into a
generic text-validation exercise is the right one.

`expense_attachments_removal_has_reason` also trims spaces only and is **not** one of the
five: no function raises `reason_required` for it, and V1 ships no destructive attachment
removal at all (D-072a), so nothing can write the column. Tightening a constraint whose
writer does not exist would be changing a rule nothing evaluates — the very thing this
project keeps recording. Noted so whoever builds attachment removal starts from the rule.

## D-146 — A constraint validates where the data allows, and says why where it does not
**Date:** 2026-09-05 · **Status:** Accepted — corrects the architecture D-142 shipped

D-142 installed two tightened void-reason CHECKs `NOT VALID`, because two probe rows could
not be repaired: `app.refuse_voided_mutation` refuses every update to a voided document,
including one issued as the table owner, and it is right to (D-006).

That was correct for `krishna-mis-dev` and **wrong as a migration**. `NOT VALID` is written
into the migration, so a fresh replay — staging, production, a new developer's database —
would have inherited an unvalidated schema for a reason that exists only in one development
database's history. A constraint that has never been checked against any row is a weaker
guarantee than one that has, and nothing about staging deserved that.

**Decision: the migration validates by counting.** Each reason constraint is installed
`NOT VALID` and then a block counts the rows that would violate it. Zero → `VALIDATE
CONSTRAINT`. More than zero → left unvalidated, with a `raise notice` naming the constraint
and the count.

```
        clean environment    0 rows  →  validated
        krishna-mis-dev      1 row   →  NOT VALID, and it says which and why
```

No environment is named. No fixture id is hardcoded. Nothing is deleted, no DELETE is
granted, D-006 is untouched, and no "validated" state is fabricated. The block is
environment-adaptive because it asks the data, which is the only thing that can honestly
answer.

**Proven both ways.** On the development project all three constraints report exactly one
blocking row each — the expense void probe, the revenue void probe and the period reopen
probe, one per table. The clean branch was proven by replaying the identical constraints and
the identical block against a throwaway schema holding only legitimate rows: all three came
back `convalidated = true`, and an attempted insert of a tab-only reopen reason was refused.

**What is not proven, stated plainly.** A full migration-chain replay against a genuinely
fresh Postgres needs a provisioned database — a Supabase branch — which is a paid resource,
so it was not created unilaterally. What is proven is the property in question: the
constraints install, and they validate when no violating row exists. A branch replay is
worth doing once before the first staging deploy, and is recorded here as the thing a person
should run.

**The residue, named once so it is not mysterious later.** Three rows on `krishna-mis-dev`
hold a whitespace-only mandatory reason, each created deliberately to prove a defect, each
in an append-only or immutable-once-voided table:

| Table | Row |
|---|---|
| `expenses` | the void probe, `KI-EXP-26-27-000446` |
| `revenue_entries` | the void probe, `KI-REV-26-27-000306` |
| `period_lock_events` | the reopen probe, period 2026-05 |

They are evidence, not damage. Keeping them and leaving the constraint honest about them is
better than rewriting financial history to make a flag read `true`.

---

# Phase 4 Slice 11 — Revenue attachments (2026-09-06)

The governing rule for the slice, as the project lead set it:

> Revenue attachments are supporting evidence for a Revenue document. They are private,
> offline-capable, actor/scope-safe, retryable, and must never become an alternate
> financial source of truth.

## D-147 — The attachment lifecycle is shared, not copied; the smallest safe extraction
**Date:** 2026-09-06 · **Status:** Accepted

**Context.** The brief was explicit: reuse the proven Phase 3 architecture, do not build a
second attachment subsystem, and extract the *smallest safe* shared abstraction where the
expense code is unnecessarily expense-specific. The audit found the split cleanly:

| Already document-agnostic, reused untouched | Named for expenses, and only that |
|---|---|
| `AttachmentSource`, `AttachmentIntake`, `PickedFile`, `intakesFor`, `attachmentSourceFor`, both platform pickers | `ExpenseAttachment` — a file record with no expense in it |
| `ImageOptimizer`, `AttachmentTypes`, the hashing helpers | `AttachmentPolicy.maxPerExpense` / `maxTotalBytesPerExpense` — the product's limits, not a per-document rule |
| The eight-state lifecycle itself | `AttachmentStagingService.stage(expenseId:)` — a directory name |
| `AttachmentUploadWorker`'s backoff, ordering, recovery and reclamation | its typed Drift queries and its raw SQL |

**Decision.** `domain/attachments/document_attachment.dart` holds
`AttachmentUploadState`, `AttachmentPolicy` and `DocumentAttachment`, moved unchanged in
substance. `ExpenseAttachment` becomes a typedef of `DocumentAttachment`, so no expense
call site changes. `AttachmentOwnerKind { expense, sale }` carries the three strings that
genuinely differ — the noun a refusal uses, the storage path segment, and which
registration RPC to call.

`AttachmentUploadWorker` serves both tables through one internal descriptor rather than
gaining a sibling. **One backoff clock, one definition of `uploaded`, one recovery pass,
one reclamation policy.** Two workers would have been two of each, agreeing only until
somebody edited one — which is D-119 for a duplicated `switch` and D-131 for a duplicated
join, both of which had already drifted when they were found.

**The evidence that the refactor is neutral is the existing suite, not the argument.** All
73 expense attachment tests pass over the rewritten worker, the rewritten staging service
and the moved domain, unchanged except for parameter names.

**`waitingForExpense` keeps its name**, deliberately. It means *the parent financial
document has not been accepted yet*; it is named for the first document that needed it. It
is the value stored in `upload_state` on every device in the field and is named by two
SQLite check constraints, so renaming it is a data migration of live expense rows for no
behavioural gain. D-104's lesson is to **pin** a wire name, not to churn one.

**What was not done.** No broad attachment refactor for tidiness. The bucket keeps its id,
the enum keeps its values, `AttachmentRejection`'s cases keep their shape, and the pickers
were not touched at all.

## D-148 — A revenue entry is never partly visible, so its evidence predicate is not the expense one
**Date:** 2026-09-06 · **Status:** Accepted

**Context.** D-063 makes an expense attachment **complete-document-only**: a shared
invoice states the whole total on its face, so a manager entitled to a quarter of it does
not get the image, in a form no policy could redact. The obvious move was to copy
`may_read_expense_attachments`.

**That would have been cargo cult.** The expense rule exists because an expense *can* be
partly visible — it has allocation lines across properties, and a scoped projection that
withholds the header total. A revenue entry has neither: it names exactly one business
unit and one revenue category on its header (spec §8), and `revenue_tables.dart` already
declines to reproduce the expense visibility columns for exactly this reason.

**Decision.** `public.may_read_revenue_attachments(uuid)` asks what the revenue projection
already asks: this organisation, `attachment.view` held anywhere, and `revenue.view` for
the entry's own business unit. No allocation arithmetic, because there are no lines to be
outside anybody's scope. It is `security definer` for the reason every predicate in this
project is — a policy subquery runs with the **caller's** privileges, so reading
`revenue_entries` directly would answer from rows the caller can already see rather than
from the truth (D-045, and D-110 §1 where that reached a shipped policy).

One predicate, three consumers: the table policy, the Storage read policy and the Storage
write policy. The object and its metadata row therefore cannot disagree about who may have
them — which is the defect 0036 had to fix for expenses, where Storage refused a scoped
manager the image while the metadata table handed them the row.

**Proven, not asserted.** Against `krishna-mis-dev`: the property's own manager reads both
halves; a wrong-property manager enumerates neither and cannot register one either; an
anonymous caller gets nothing; and a **revoked** user — the grant genuinely withdrawn and
then restored, with the restoration read back — loses both.

## D-149 — One bucket, two path prefixes, two policies
**Date:** 2026-09-06 · **Status:** Accepted

**Decision.** Revenue evidence lives in the existing private bucket under
`org/{org}/revenue/{entry}/{attachment}.{ext}`, decided by its own three Storage policies.
The expense policies are untouched and keep deciding `org/{org}/expenses/…`.

**Why not a second bucket.** It would duplicate the file size limit, the MIME allow-list
and four policies, and all of them would then have to be kept in step by hand — which this
project has already learned is the failure mode, not the safeguard.

**Why the bucket id still reads `expense-attachments`.** A bucket id is where bytes
physically live. Renaming it would strand every bill already uploaded, for the sake of a
word. The Dart constant is renamed to `financialAttachmentBucket` and says so; the id is a
historical name and is documented as one.

**The separation is asserted rather than assumed.** `storage_revenue_id` returns null for
an expense path and `storage_expense_id` returns null for a revenue path, checked at
deploy time and again from a client. Neither prefix is reachable through the other's rule.

A `delete` policy remains absent for both. Nobody removes evidence through the object API.

## D-150 — Attaching is not editing
**Date:** 2026-09-06 · **Status:** Accepted

**Decision.** Adding evidence to a recorded sale is **not** a financial mutation and does
not behave like one. `RevenueRepository.attachLocally` takes no `base_row_version`, queues
no outbox intent, does not advance the entry's row version, and changes no amount, tax
figure, business date or transaction number. It is its own control on the detail surface
rather than a trip through the correction form.

The alternative — routing evidence through `revenue_update` — would have put a financial
mutation, a concurrency check and a re-resolution of tax behind an act that corrects
nothing. A person attaching last night's till report has not changed a figure, and making
the system re-rate the sale to accept a photograph would be inventing a reason for the
tax to move.

**The consequences are asserted directly.** A test captures a sale's gross, tax, net,
business date, transaction number, row version, component count and business-date
provenance before evidence is attached, and compares the whole set after attach, upload,
failure, retry, reclamation and restart. The same comparison runs against
`revenue_document` on the real server. The local schema is asserted to carry no
money-shaped column at all, so the mistake is unavailable rather than merely avoided —
the same move D-094 made when it removed every monetary field from `RevenueTaxFacts`.

**Ordering is still a rule.** Evidence cannot precede the document it supports: the
Storage write policy requires the sale to exist canonically, so a file waits in
`waitingForExpense` until the server issues a `KI-REV` number and the worker promotes it
(D-073 §2). A queued correction is unaffected either way, because **the attachment belongs
to the document's identity, not to any one mutation.**

## D-151 — V1 ships no attachment removal, and revenue does not add the concept
**Date:** 2026-09-06 · **Status:** Accepted

The brief asked for this to be determined rather than assumed, and the determination is:
**the binding V1 specification does not require attachment removal.** Spec §15 describes
capture, storage and access control; §28 lists attachments in scope and says nothing about
removing one; D-072a states plainly that V1 offers no destructive attachment removal at
all.

`expense_attachments` carries `removed_at`, `removed_by` and `remove_reason` from the
Phase 3 schema, and **no writer exists anywhere in the product** — which is why
`expense_attachments_removal_has_reason` was excluded from D-145's five mandatory reasons:
nothing can raise `reason_required` for it.

**Decision.** `revenue_attachments` carries no removal columns, and the migration asserts
their absence. Creating a second unwritable constraint because the sibling schema contains
the concept would be expanding V1 scope on the strength of a column name — and it is
precisely the shape of the three findings D-142, D-145 and D-146 had to reason about.

If removal is ever approved it arrives as its own decision, with a governance record for
removing financial evidence, and its mandatory reason uses `app.stated_reason` — the
canonical all-whitespace rule (D-142). The invariant that finds every
`reason_required` raiser will require it, so the defect cannot be repeated by omission.

The client half matches: the strip offers to take a file back out only while it is still
`staged` — that is a draft nobody has recorded, not a removal — and a recorded file has no
control beside it.

## D-152 — Two acceptance findings, both about what a real server does to an assertion
**Date:** 2026-09-06 · **Status:** Recorded

Neither is a product defect, and both are worth keeping because both were assertions that
looked correct and were about the wrong thing.

**1 · The online phase asserted that the product is slow.** It first checked that a freshly
saved sale's evidence had *not* yet uploaded, to demonstrate the D-073 §2 ordering rule.
Against `krishna-mis-dev` the whole chain — save, push, number, promote, upload — finishes
inside the same two-second pump, so the assertion failed on a run in which everything
worked. It is now about the durable consequence (one row, one object, matching hashes, no
financial change), and the ordering rule is proven in the **offline** phase, where no
number can arrive and the upload provably cannot start. Slice 8 records the identical
lesson for *"no number yet"* (D-119).

**2 · A widget test cannot await real file I/O without saying so.** Staging copies bytes
into app-private storage, which is genuine `dart:io`. A `testWidgets` body runs inside the
fake-async zone, where `pumpAndSettle` returns as soon as no frame is scheduled and an
await on real I/O in the body **never completes at all** — the first presents as an
assertion about a form that has not been told yet, the second as a hung suite rather than
a failed one. Both are handled with `tester.runAsync`, in a named helper, with the reason
written beside it. Recorded because the second failure mode reads like a product hang and
is not one; the next person to stage a file in a widget test will meet it.

**And the first fix for it was itself a wall-clock race.** The helper began as a fixed
twelve turns of pump-and-yield, which is 240 milliseconds of real time. It passed the file
alone and failed intermittently under the full suite — three tests one run, six the next,
none the third — because a dozen suites sharing a machine do not hand the real event loop
back on a schedule. A count of turns is not a wait; it is a bet on how busy the machine is,
and at a boundary that copies bytes it fails in exactly the way D-075 records: a timing
defect wearing the costume of a product one. The helper now waits for **the staged file to
appear**, up to a generous deadline, and says so if it does not. Three consecutive full
host runs, green.

The rule that generalises: **wait for the condition, never for a number of frames.** The
acceptance suite learned this as `pumpUntil`; the host widget suite needed the same lesson
the first time it touched real I/O.

## D-153 — A documentation invariant caught a line-ending rewrite
**Date:** 2026-09-06 · **Status:** Recorded

Appending the Slice 11 sections to the four canonical documents was done with a Python
rewrite. On Windows a text-mode write turns every newline into a carriage-return pair, so
all four files — which were LF — came back CRLF in **every** line rather than only in the
appended sections.

Nothing about the prose changed and no reader would have noticed. What noticed was
D-137's invariant, which asserts `ARCHITECTURE.md` states in as many words that there is
no `expense_correct_business_date` — it matches a two-line phrase, and a phrase spanning a
line ending stops matching when the line ending changes. The suite went from green to one
failure with a diff nobody would have read as "line endings", and it was right.

Two things are worth keeping from it.

**A whole-file rewrite is a whole-file change**, whatever the intent was. The fix is
`newline=''` on read *and* byte-mode on write, so the file's existing convention survives
an append. Applied, and the four files are back to LF, byte-identical to HEAD outside the
appended sections.

**The invariant earned its keep somewhere nobody designed it to.** It exists to stop a
documented endpoint being claimed again (D-127, D-137); it caught an encoding change
instead. A check written against the *substance* of a document rather than its presence is
worth more than one that merely counts sections — and this is the argument for phrasing
documentation invariants as sentences the document must contain.


---

# Phase 4 Slice 11 closure — the upload lifecycle after the bytes land (2026-09-06)

## D-154 — Storage write authority is not read authority, and the eight objects proved it
**Date:** 2026-09-06 · **Status:** Accepted — **a production lifecycle defect, latent in
the expense engine since D-073a and shipped again with revenue**

**The audit that was asked for, and what it overturned.** The Slice 11 report recorded 55
revenue objects against 47 metadata rows and attributed the eight orphans to *"KM009 for
the same id with different bytes, KM010 for a path belonging to another sale, and the
wrong-property and revoked attempts"*. Read against the actual rows rather than against the
test names, **three of those four attributions are wrong**:

* the **KM009** probe re-uploads to the *same* deterministic path, so it strands nothing —
  what it does instead is overwrite canonical evidence, which is a worse finding and is
  dealt with below;
* the **wrong-property** and **revoked** probes are refused by the Storage *write* policy,
  so no bytes are ever written and they strand nothing either.

The eight are **four pairs, one pair per suite run**. Four are KM010, which is a forged
path that production cannot produce. The other four are **KM020 — a voided parent** — which
the report did not name at all, and which is the one class no seam of any kind is involved
in. The expense side then showed exactly the same shape: 50 objects, 46 metadata rows, and
all four of its orphans with a voided parent.

**Why a legitimate client reaches it.** Both Storage write policies called the *read*
predicate, and a read predicate must not care whether a document is voided, because a void
keeps its evidence readable for ever (D-006, ARCHITECTURE §16.5). Both register RPCs refuse
`KM020` when it is. So the two halves of one upload disagreed about exactly one condition:

```
        1. a manager records a sale with a till photo; it syncs and is numbered
        2. the upload fails transiently; the row is `retryNeeded` on the backoff clock
        3. the accountant voids the sale — an ordinary, capability-gated act
        4. the backoff elapses; Storage ACCEPTS the bytes, because the sale is readable
        5. the register RPC refuses KM020
        6. the worker marks the row `rejected`, which is terminal and never retried
```

The object then sits in a private bucket for ever, named by no metadata row, invisible to
the ledger, counted against no limit, reachable through no product surface. **That is a
production lifecycle defect, not test residue**, and the four objects in the development
project are what the shipped path produced when the void arrived deliberately rather than
by chance.

**Decision.** `may_attach_to_expense` and `may_attach_to_revenue` are the read predicate
*plus* `attachment.upload` *plus* a parent that exists and is not voided. The INSERT and
UPDATE Storage policies decide on them. **The READ policies are untouched**, and a
deploy-time assertion refuses the migration if one of them ever acquires attach authority —
because a voided document keeping its evidence is the rule this must not break while fixing
the other one.

The register RPCs keep their own `KM020` guard. A boundary that relies on another boundary
having already said no is one deployment away from saying yes, so both are asserted.

**Registered evidence can no longer be overwritten either.** The UPDATE policies gained the
same not-already-evidence guard. Before it, a competing upload reached the canonical path
*before* the refusal, so the stored object no longer hashed to the value its own metadata
recorded — proven by a live test that turned red against the shipped server and green
afterwards. The retry that used to depend on overwriting is handled properly instead: the
worker asks whether the registration committed **before** it re-uploads, which is what a
lost response actually calls for, and only on a retry, because a first attempt cannot have
registered anything.

**Both document kinds, in a revenue slice, deliberately.** D-127's rule is not to change
the expense path quietly inside a revenue slice. This is neither quiet nor separable: Slice
11 made one worker and one store serve both (D-147), so the fix has no revenue-only form
that does not first fork them — and fixing one while leaving the other would recreate, on
purpose, the duplication D-147 exists to prevent.

**Proven red first.** Seven live tests were written against the shipped server and **four
failed**, including the evidence-overwrite one; all seven pass against the fixed one. The
host control is the retry pre-check: removing it turns two of the new repository tests red,
and the restore was read back rather than assumed (D-142).

## D-155 — An object no metadata row names is not evidence, and its uploader may take it back
**Date:** 2026-09-06 · **Status:** Accepted

D-154 closes the largest class by refusing the bytes. Two conditions remain in which bytes
legitimately land and registration still refuses terminally: the attachment limits
(`KM022`), reachable once a second device has filled a document's quota, and a path the
server derives differently from the client (`KM010`). Something has to answer for those, or
"the worker must not leave an indefinite inaccessible object" is a wish.

**Decision.** A narrow Storage `delete` policy per document kind, and the client that wrote
the bytes calls it at the one moment anything knows both that an object exists and that
nothing will ever name it — inside the store, immediately on a registration refusal.

Four conditions, each removing a way it could destroy something:

| | |
|---|---|
| `bucket_id` | nothing outside the financial bucket is in reach |
| the parent's **read** predicate | the caller must be entitled to the document — the read one rather than the write one, because an object needing cleanup may well belong to a sale that has since been voided, which is the very case that stranded it |
| `owner_id = auth.uid()` | only bytes this caller themselves wrote |
| `not attachment_object_is_registered(name)` | and only while no metadata row names the path |

**This is not a hole in D-063's "nobody removes evidence through the object API".** Postgres
is the record of what evidence exists (spec §23); an object no row names is, by that rule's
own definition, not evidence. The guard is a `not exists` the database evaluates at delete
time, so the guarantee is structural rather than conventional — and it is the same guard
that answers *"the response was lost"*: if the registration in fact committed, a row names
the path and the delete is refused rather than a bill being destroyed. Proven both ways
against the real server.

`attachment_object_is_registered` is `security definer` and not an inline subquery, because
a policy expression runs with the **caller's** privileges and both metadata tables carry
RLS — an inline `not exists` would answer *"nothing names this path"* for a row the caller
merely cannot see, and would then let them delete somebody else's evidence. That is D-045
and D-110 §1 in the one place where getting it wrong destroys a document rather than hiding
one.

**And the bucket now has to reconcile.** The Slice 11 run *reported* what it left; this one
reclaims it and then asserts there is nothing left — a different claim, and a standing
invariant over both prefixes rather than a tidy-up. It is written to reclaim first and
assert afterwards, so the residue of every earlier run cleared on its first execution: **16
stranded objects reclaimed, and the bucket now reconciles exactly — 79 revenue objects to
79 rows, 46 expense objects to 46 rows, 0 stranded.**

**Two adjacent findings, recorded rather than fixed in passing.**

*A guard keyed on an incidental convention, for the third time.* The migration audit's
function parser matched only a bare `$$` body tag. The three new predicates use `$fn$`, so
they were invisible to **every** assertion in that group at once — including the
`search_path` one, which is the direction that fails quietly. Widened to any dollar-quote
tag. This is D-103 exactly, and it is now the third instance (D-103, D-134, this).

*`ARCHITECTURE.md` §16.3 claims `attachment_register` "compares them against the stored
object and refuses on disagreement".* It does not: neither register RPC reads
`storage.objects` at all, and the byte size and hash are taken on trust from the caller.
The hash still means something — the *worker* verifies it against what the metadata row
reports before calling an upload confirmed — but the sentence describes a server-side check
that has never existed. Corrected in the document rather than built here: adding a
server-side object read is a change to a reviewed financial boundary and belongs in its own
scope (D-127).

## D-156 — The native picker gate is per document kind, and revenue's has not been run
**Date:** 2026-09-06 · **Status:** Open — **Android PENDING · Windows PENDING**

D-077 is the most expensive finding in this project: a full green automated attachment
acceptance ran on two real devices against a picker that did not exist, because every test
overrode `attachmentSourceProvider` and none read what production resolves.

Two halves of that gate, kept apart because they are different claims.

**The wiring half is closed, and is now closed for the revenue surfaces specifically.**
`attachment_source_wiring_test.dart` reads what production resolves per platform. Added
here: the revenue entry form and the sale detail panel are each rendered **without** the
injected source, and asserted not to show *"Attaching a file is not available on this
device yet."* — the exact sentence two real devices displayed for a whole phase. That is a
different claim from the provider test, because a surface that read some other provider, or
built its own strip, would satisfy the provider test and still fail a user.

**The native half is not closed and is not claimed.** The OS picker is a separate activity
no harness opens. It needs a person to open one **from a sale** on each platform, and it has
not been done: this session had no way to perform a human interaction on the project lead's
device, and driving an emulator's picker with input events would be a different test on a
different machine reported under the same name — which is the substitution D-077 exists to
forbid. It is recorded in `RELEASE_CHECKLIST.md` §L with the exact steps for each platform,
as **PENDING**, and **Phase 4 Slice 11 is therefore not formally closed** on that one line.

Running the expense gate does not discharge it. The strip is shared, but what the gate
proves is that a person can attach evidence to a *sale* on a real device, and no automated
result substitutes for it.


---

# Phase 4 Slice 12 — the revenue reporting interface (2026-09-06)

## D-157 — A revenue contribution is derived, because it carries no decision of its own
**Date:** 2026-09-06 · **Status:** Accepted

**The question the brief put:** does the binding schema require a *physical*
`revenue_period_contributions` table, and if a view would do, would deriving it reduce
drift?

**What the audit of the expense side found.** `expense_period_contributions` — the thing
`DATABASE_SCHEMA.md` calls the revenue projection *"the mirror of"* — **is a view**. The
physical table underneath it is `expense_period_allocations`, and it exists for a reason
that does not transfer:

> A cross-period split is a **decision a person made** (D-034, D-060). ₹60,000 apportioned
> ₹30,000 to May and ₹30,000 to June exists nowhere else — take the rows away and the
> information is gone.

A revenue contribution carries no such decision. Its period is the entry's own stored
`pnl_period_key`, under a server CHECK tying it to the business date; its money is the
component's own stored gross, tax and net; its rate, treatment, basis and band are the
component's snapshot. **Every field is already canonical somewhere.**

**Decision.** `revenue_period_contributions` is a `security_barrier` **view** in Postgres
and a view in SQLite, column for column, and the migration asserts that it is not a table.
The components remain the accepted financial facts; the contribution is reporting
attribution derived from them. Nothing may write a contribution amount, because there is
nothing to write.

**What that buys, stated as the four hazards it removes rather than as elegance.** Every
lifecycle question the brief raises is a question about *maintaining a second copy*:

| | With a stored table | Derived |
|---|---|---|
| a business-date correction moves a period | delete and rewrite, in the mutation's own transaction, on every path that can move a date | the entry moved |
| an edit replaces the figures | replace and never append — one forgotten `delete` doubles a month | the components were replaced |
| a void removes the effect | flag or delete, and every aggregate must agree which | the entry is voided |
| a replayed mutation | contribution idempotency, built and kept in step with mutation idempotency | there is nothing to insert twice |

None of those is a rule anybody has to remember, and this project's own record is that the
ones people have to remember are the ones that stop being applied (D-059, D-068, D-071,
D-077).

**Component grain is kept** (D-087). A two-band Room day is two contributions even though
the document totals aggregate them, so tax buckets survive into reporting instead of being
flattened at the door.

**And the grain protects the arithmetic.** Two Restaurant days of ₹76,450 and ₹81,200
contribute `364048 + 386667 = 750715` paise of tax. Re-applying 5/105 to the ₹1,57,650
total gives `750714`. The acceptance asserts both figures side by side so the difference is
stated rather than discovered — rounding happens once, at the component, and an aggregate
sums stored paise (spec §6.5, D-017).

**Alternatives rejected.** A stored table *plus* a maintaining trigger — the trigger would
have to fire on both parents, would run inside every financial mutation, and would be a
second definition of what a period means. And a stored table written by the RPCs, which is
what expenses do and is right there because there the rows are the only copy.

**Consequence for Phase 5.** It sums one shape per side of the P&L, both named
`*_period_contributions`, both views, both carrying `org_id`, `business_unit_id`, a
`pnl_period_key` in `YYYY-MM`, integer minor units and `voided_at`. No second financial-date
or period model is required, which is what B30 asked to be demonstrated rather than assumed.

## D-158 — A sale the server has not accepted is not revenue
**Date:** 2026-09-06 · **Status:** Accepted

Three exclusions are applied before any filter, in one shared predicate so they cannot be
present in one query and forgotten in the next: `voided_at IS NULL` (D-006),
`scope_revoked_at IS NULL` (D-070, D-074), and **`txn_number IS NOT NULL`**.

The third is the one that needed deciding. A locally recorded sale that has not yet been
accepted is the operator's **intent**; so is a correction sitting in a conflict, and so is
a rejected attempt. Counting any of them in an authoritative total would report money the
business does not yet have, and would make a figure move when nothing financial had
happened — a device coming back online would appear to change last month.

**Decision.** Canonical reporting contributions derive from canonical accepted revenue
only. A device's own unaccepted work is visible in the ledger, with its sync state, which is
where an operator's attempt belongs.

**And Slice 12 does not invent a provisional model.** A labelled *"local — including N
unsynced entries"* operational figure is a real product idea and is exactly what
`ARCHITECTURE.md` §6.4's freshness vocabulary is for — but it is a Phase 5 reporting
decision that has not been approved, and inventing one here would ship a second, softer
definition of revenue with nobody's name on it.

**Recorded with it, because Phase 5 will meet it first: there is no revenue pull.**
`RevenueGateway` reads one document back for reconciliation and nothing else, so the local
cache holds only what this device recorded. The local projection is therefore honest about
this device and is **not** a complete reporting cache; the server projection is the
authoritative one. That is the shipped state after Slice 11 rather than something this
slice changed, and it is stated here so Phase 5 plans for it instead of discovering that a
manager's dashboard is empty on a new installation.

## D-159 — Two fixtures completed, and a hard-coded schema version, all found by running
**Date:** 2026-09-06 · **Status:** Recorded

Three small things, all of a kind this log has recorded before, and all caught by the
existing suite rather than by review.

**A downgrade fixture that stopped being a downgrade.** `downgradeToV10` builds a v10
database by removing what v11 added. It dropped `revenue_entry_totals` and not the new v15
view, so a leftover view referenced tables the downgrade had just removed — and SQLite
validates every view when a table is renamed, which the fixture does. The v10→v11 test
failed with `no such table: main.revenue_components` in a test that has nothing to do with
reporting. **A fixture that claims to be an older schema has to actually be one**, and that
is the same lesson as the v9 attachment fixture two phases ago (D-144).

**A hard-coded schema version, again.** `expect(db.schemaVersion, 14)` in the Slice 11
migration test — written *after* D-144 recorded the identical correction for two other
tests. Its subject is "the current schema creates this table", not "the schema is 14", so it
now reads a lower bound. The lesson does not seem to generalise on its own, so it is written
down a second time.

**And the v15 step needs the D-144 range guard**, `from >= 11 && from < 15`, because
`revenue_entries` and `revenue_components` are created at v11: a device coming from v10 has
neither when the step is reached, and a view over tables that do not exist fails to create.
A fresh database gets the view from `onCreate` instead — and the reporting index had to be
added there too, which the fresh-database test caught by finding it absent.


## D-156 (closed) — the revenue native-picker gate, and what a manual gate can be asked to prove
**Date:** 2026-09-06 · **Status:** Closed — **Android PASS · Windows PASS**, reported by the
project lead. The entry above is left as it was written, because this log is append-only.

The project lead ran the gate on both platforms and reports both as passing. Slice 11 is
closed on that ratification, which is his to give: the OS picker is a separate activity no
harness opens, so the observation could only ever be a person's.

**Two halves, and only one of them leaves a trace.**

The picker itself — a real Android Photo Picker and a real Windows `IFileOpenDialog`
returning a file into a *revenue* surface — writes nothing to any server. There is nothing
for this repository to corroborate and nothing to doubt; that is what a manual gate is, and
D-077 exists because the automated suite was green throughout while the picker did not
exist.

The **save-and-sync leg** does leave a trace, and `krishna-mis-dev` has none. Checked four
ways rather than by looking once: all 96 revenue attachment rows are accounted for by
automated suites (89 `z-report.jpg` from the live suites, 7 `synthetic-receipt.jpg` from the
device-acceptance phases, which inject at the picker boundary and say so in the file name);
every registration in the **append-only** audit trail is the same actor in four hour buckets
matching those runs; the KI-REV sequence has 752 numbers and 752 rows, so nothing was
created and removed; and the newest revenue entry is the 07:50 automated one.

**This is recorded, not resolved, and it is not a challenge to the result.** The benign
explanations are the likely ones — a build with no backend configured runs the entire
surface against the local seed (D-052); a picker checked to the point where the file appears
on the form is the substance of the gate and needs no save; a device that never reconnected
keeps the sale local. What must not happen is a canonical document claiming a synchronised
artefact that the database says is absent, or a later reader mistaking the automated
`synthetic-receipt.jpg` rows for this line. One question is open for the project lead:
which build and environment the manual runs used.

**The rule this leaves behind.** A manual gate is a person's observation and is recorded as
one — attributed, dated, and never restated as though a suite had made it. Where the manual
act *should* leave a durable trace, the record says whether it did. Both halves of that are
the same discipline: say who verified what.


---

# Phase 4 Slice 13 — full Revenue Engine acceptance (2026-09-07)

## D-160 — The Windows ledger showed a stale sync state, and a weak assertion had been hiding it
**Date:** 2026-09-07 · **Status:** Accepted — **a product defect found by the Slice 13
acceptance, and a test defect that had concealed it since Slice 10**

**The symptom.** On the accumulated Windows database, `windows-revenue-edit` failed
deterministically — three runs out of three. A sale corrected through the shipped desktop
surface reached the server (`revenue_document` showed the corrected figures, one row
version, the same `KI-REV`), the outbox held nothing but `done`, and
`RevenueRepository.syncStateOf` returned `synced` — while the **ledger row went on
reporting `Syncing`**, indefinitely. Forty seconds of pumping did not move it.

**Two defects, and the order they have to be told in.**

**1 · The assertion was reading a different surface.** The line that failed was
`expect(visible('Synced'), isTrue)`. The Windows ledger renders its sync state
`compact` — an icon and a colour, and deliberately **no text**, because a dense financial
table with a word in every row is noise. So `find.text('Synced')` can never match the
ledger at all. It had been passing on text belonging to the detail panel, which happened
still to be mounted when the assertion ran. **It proved nothing about the ledger, and it
had proved nothing since Slice 10.**

That is the family this log keeps recording: D-071's cleanup phase that ran
`expect(true, isTrue)`, D-068's classification guard that compared a list against itself,
D-134's two composition roots. An assertion that passes for a reason other than the one it
states is worse than an absent one, because it occupies the space where a real check would
go.

**2 · Underneath it, the ledger was stale — D-131 exactly, one surface over.**
`filteredRevenueProvider` was a `FutureProvider`: a one-shot read, invalidated by the
*controller* when a person acts through the surface. **The sync worker is not the
controller.** When it delivers a queued correction and the reconciler marks the outbox
`done`, nothing invalidates anything, so the row keeps whatever state the query saw when it
last ran.

D-131 fixed precisely this for the *detail panel* and said so in as many words: *"a conflict
arrives from the sync worker, which invalidates no provider and knows about no screen, so a
cached snapshot went on being wrong indefinitely."* The ledger was left as a snapshot, and
the assertion that should have caught it was matching somebody else's text.

**Decision.** The ledger follows the outbox, as a stream.
`RevenueRepository.watchQuery` is the same statement as `query` — one builder, one row
mapper, so the two cannot drift — delivered through Drift with
`readsFrom: {revenueEntries, revenueComponents, syncOutbox}`. `filteredRevenueProvider`,
`revenueHasMoreProvider` and `recentRevenueProvider` are `StreamProvider`s over it. There is
one derivation of a row's sync state and it is pushed rather than polled.

The acceptance assertion now reads **the chip's own state** rather than a string the
compact form never renders, and waits for it to settle rather than sampling one frame —
which is D-152's rule (*wait for the condition, never for a number of frames*) and which
turned up `syncing` on the first attempt, exactly the value that would have been read as a
stuck queue.

**Controls, both seen to fail.** A repository regression listens to `watchQuery`, moves the
outbox entry to `done` **through Drift** rather than raw SQL — a `customStatement` changes
the rows and notifies nothing, which would have made it a test of the fixture — and
requires the stream to re-emit `synced`. Beside it sits the shape of the defect: a one-shot
`query` is correct at the instant it runs and stale for ever afterwards, which is why every
test that simply read again missed this.

**The cost, and it is D-135's.** A streamed read model holds a live query subscription, and
Drift schedules a zero-duration timer when one is cancelled; Flutter checks for pending
timers at the end of the test **body**. Converting these three providers made the Android
revenue UI suite hang — reported as `did not complete`, which reads like a product hang and
is not one. The remedy already existed: `uiTest`, which disposes inside the body. The suite
now uses it throughout. Recorded because the next person to stream a read model will meet
the same thing, and because it is the second time this cost has been paid.

## D-161 — What Slice 13 could not prove against the approved baseline, and how it was proved instead
**Date:** 2026-09-07 · **Status:** Recorded

Two acceptance requirements cannot be met against `krishna-mis-dev` without changing
configuration the project lead approved, and both are recorded rather than quietly
substituted.

**A second Room value band.** D-093 is explicit: two live bands for one category over the
same dates require the existing open-ended Room rule to be **end-dated and replaced**. That
is an auditable change to the verified FY 2026-27 baseline (D-096), and
`revenue_tax_rule_end_date` takes a `date` with no path back to null — so it is not a round
trip. The Slice 13 brief says so itself (*"Do NOT add production Room bands"*), so the
banded, multi-rate, multi-component path is proven **synthetically at host level**: two
bands at 5% and 12%, a two-component sale, exact paise per band, document reconciliation,
contribution rows keeping both rates apart, and an edit across both bands staying exact. On
the real server, multi-component grain is proven under the generic rule.

**A configuration change between preview and acceptance.** The same constraint applies:
legitimately changing the authoritative rule means end-dating a baseline one. The `KM030`
contract — server re-resolves, compares the client's declared figures, refuses, applies
nothing — is proven against the real server through declared values that disagree with the
configured rate, which exercises the identical server path with the baseline untouched.
What is *not* run live is the variant where the rule itself moved underneath the client.

**Neither is a gap in the product.** Both are proven; what differs is where. Stating that
plainly is the point, because a report that said "multi-band acceptance: PASS" without this
paragraph would be describing a live proof that did not happen.


## D-162 — There are four write privileges, and the revoke named three
**Date:** 2026-09-07 · **Status:** Accepted — a security defect found by the Phase 4
closure audit, in the Phase 3 boundary

**The finding.** Asking the live catalogue what a client may actually do — rather than
reading the migrations that were supposed to have closed it — returned 24 write grants:

```
        expenses, expense_allocations,                   TRUNCATE
        expense_period_allocations, expense_attachments  to authenticated

        expense_document, expense_period_contributions,  INSERT, UPDATE,
        revenue_document, revenue_component_detail,      DELETE, TRUNCATE
        revenue_period_contributions                     to authenticated
```

`20260829090300_expense_rls.sql` wrote `revoke insert, update, delete … from
authenticated`. **There are four write privileges.** Supabase grants ALL on public tables
to `authenticated` by template, so `TRUNCATE` survived the revoke on four tables holding
financial history — and **TRUNCATE does not consult row level security at all.**

**The revenue side was clean**, because Slice 11 used
`revoke all on table … from public, anon, authenticated`. The correct idiom was already in
the repository; Phase 3 used the enumerating form and lost a privilege inside it.

**And the guard enumerated the same three words.** The host invariant searched the
migrations for `grant (insert|update|delete)` and never asked what a client was left
*holding*. It could not have caught this. That is D-139 exactly — a check written against
the shape somebody expected the defect to take, rather than against the property that
matters.

**Reachability, stated honestly.** PostgREST issues SELECT, INSERT, UPDATE and DELETE; it
has no way to express TRUNCATE, and no client holds a SQL connection. So nothing shipped
could reach it. **That is not the standard this project uses** — D-044 refused exactly this
reasoning when nineteen RPCs were reachable by `anon` and every one happened to fail closed:
*happens to be unreachable* is a different claim from *cannot be granted*.

**Decision.** Everything is revoked from both client roles on the nine relations, and
exactly the reads the product performs are granted back. `public.expenses` gets nothing
back, because the header total on a shared bill is the other property's share and the
projection is the only way in (D-062). The invariant is restated over **all four
privileges** and over the whole `public` schema rather than over a list somebody must
remember to extend — at deploy time, and in the host suite.

A second deploy-time assertion checks that the eight projections are still readable and
that `public.expenses` still is not, so a migration that closes the boundary by breaking
the application fails instead of shipping. The live revenue and expense suites were re-run
afterwards: 81 and 50, green.

**The five projections** carried the whole default `GRANT ALL`. Those grants are inert — a
view over a join is not auto-updatable, and TRUNCATE on a view is meaningless — and they
are revoked anyway. A privilege nobody can use is still a privilege nobody reviewed.

**Recorded about the writing of it, because it is the same lesson one level up.** The first
attempt to append this entry was made through a shell heredoc, and every backticked span in
it was silently executed as a command substitution and replaced with nothing — a decision
record about an over-broad grant, written by a mechanism that quietly deleted a third of its
own evidence. Caught by reading the file back rather than trusting that the write succeeded,
which is D-142's rule: *a restore is not restored until it has been read back.*

---

# Phase 5 — P&L / MIS Reporting: the project lead's ratified decisions (2026-09-07)

The Phase 5 planning audit put eight product questions and two architecture corrections to
the project lead. All ten came back decided. They are recorded here **before** Slice 1
begins, so no later slice has to stop and ask again.

Recorded with them are the two findings the audit proved against `krishna-mis-dev` and the
shipped test suite — the `expense.view.own` predicate (E1) and the canonical-only asymmetry
between the two engines (E2) — because the decisions that close them are D-169 and D-168.

## D-163 — A P&L refuses rather than renders half
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D1)

**Context.** A P&L is Net Sales minus Expenses. Both sides are scoped independently:
revenue by `revenue.view`, expenses by `expense_visible_units()`. Nothing stopped the two
from disagreeing, and the audit found a principal for whom they do — a Data Entry user
holds expense visibility and **no** `revenue.view` at all.

Rendering that would produce Expenses against a revenue side of zero: **a large negative
Operating Profit that is not a restriction but a lie**, and one a manager has no way to
detect from the figure. The same hazard runs the other way for a principal with revenue and
no expenses, where the profit is overstated by the whole cost base.

**Decision.** A report **refuses**. It must never render Revenue without the complete
authorised Expense side, nor Expenses without the complete authorised Revenue side, and it
must never substitute an inaccessible side with zero. The refusal is **structured** — a
typed report-access refusal naming which side could not be established — in the shape
`RevenueRefusal` already uses (D-113), so the surface can say something a person can act on
rather than *"Cannot load report"*.

**Alternatives rejected:** rendering the accessible side alone with a caption (the figure is
still wrong, and a caption is not a guard); showing zero for the inaccessible side (the
failure mode this decision exists to forbid).

**Consequences.** The refusal is part of the report contract rather than a presentation
concern, so it belongs in the result type and is decided server-side as well as locally
(D-037). It shapes the reporting RPC's signature, which is why it had to be settled before
the boundary was written rather than after.

## D-164 — The capability intersection a P&L requires
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D2)

**Decision.** A **business-unit P&L** requires, for that unit, the intersection of:

```
        reports.view   AND   revenue.view   AND   expense.view.all
```

A **consolidated organisation P&L** requires the corresponding **unscoped** authority for
all three.

**`expense.view.own` does not qualify for a P&L**, and the reason is arithmetic rather than
policy: it cannot establish a complete expense denominator. A profit computed from the
subset of costs one person happened to enter is not that property's profit, and it would
look exactly like one.

**Role names appear nowhere in this.** Owner, Manager and Accountant behaviour is a
consequence of the capabilities their bundles hold, evaluated per business unit (D-025,
§13.1). Nothing in the reporting path may branch on a role code.

**Consequences.** `reports.view` finally acquires an evaluator, which removes it from
D-139's exemption list — deliberately, in the migration that owns the reporting boundary,
not as a side effect. `reports.export` and `reports.print` stay exempt until Phase 7.
Enforcement is server-side in the projection predicates and the reporting RPC; the client's
copy shapes the interface and is not the boundary.

## D-165 — The reporting week is Monday to Sunday, on the business date
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D3)

**Context.** Spec §10 names *This Week* and *Last Week* among the periods reporting must
derive. **No definition of a week existed anywhere in the repository** — not in the spec,
not in `BusinessDate`, not in any migration. The audit refused to guess one.

**Decision.** A reporting week runs **Monday through Sunday**, and its boundaries are
**canonical business dates** (D-019, D-067) — never UTC timestamps and never the device
calendar. A sale rung up at 01:00 on a Monday belongs to the previous week, because its
business date does.

**Consequences.** The week lives in the period vocabulary in `domain/finance` alongside the
month and the financial year, and is derived from `BusinessDate` rather than from
`DateTime.weekday` over an instant. Boundary tests at Sunday 23:59, Monday 00:01 and across
the 05:00 cut-off are mandatory, in the shape migration 0033 established for the edit
window.

## D-166 — Phase 5 includes read-only transaction drill-down
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D4)

**Decision.** Spec §11's traceability requirement is Phase 5 scope in full:

```
        P&L → category / hierarchy breakdown → underlying canonical transactions
            → the existing transaction detail surface
```

**Reports are read-only.** Drill-down navigates to the transaction surfaces that already
exist; it does not reimplement editing, correction or void inside reporting. A second write
path to a financial document is the cost this project has paid twice (D-072a, D-124), and
reporting is not going to be the third.

Charts, trends, period-over-period deltas and analytics navigation remain **Phase 6**.

**Consequences.** Slice 10 owns it. The document fetch reuses `ExpensePull.pullOne` and
`RevenueGateway.fetchComponents` on demand for the one document a manager opened, rather
than widening the reporting cache to carry document detail it does not need (D-171).

## D-167 — There is no provisional P&L in V1
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D5) — settles what
D-158 deferred

**Decision.** Canonical P&L contains **only server-accepted financial facts**. Pending,
rejected, conflicted and quarantined work stays visible in the transaction workflows, where
an operator can act on it, and contributes **zero** to management P&L.

**No second profit vocabulary is created.** D-158 recorded that a labelled *"local —
including N unsynced"* operational figure is a real idea and deliberately did not invent
one; the answer is that V1 does not have one. A softer definition of revenue with nobody's
name on it is worse than an honest refusal, and the freshness vocabulary (spec §21.4)
already tells a manager whether they are looking at everything.

## D-168 — Canonical P&L excludes pending expense attempts
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D6) — closes finding E2

**The defect, proven by the shipped suite rather than by reading it.** The two engines
disagreed about what counts as revenue and what counts as a cost:

```
        revenue_contribution_test    "a conflicted or rejected attempt contributes nothing"
        expense_repository_test:328  save(simpleExpense())  -> createLocally ONLY,
                                     never synced, txn_number NULL
                                     contributionTotal('2026-06') == Rs 200
```

`RevenueRepository._contributionPredicate` applies three exclusions — voided, scope-revoked
and **canonical-only** (`txn_number IS NOT NULL`). `ExpenseRepository.contributionTotal`
applies the first two and not the third.

**Combined into a P&L, that understates Operating Profit systematically and silently**: it
subtracts costs the server has never accepted while refusing to add the sales beside them.
Nothing would have failed; the figure would simply have been wrong in one direction.

**Decision.** The correction is approved even though it changes figures the shipped code
reports today. One canonical reporting semantic for both engines: an amount contributes only
if it is **server-accepted, not voided, authorised for reporting, and not locally
scope-revoked or quarantined.** Everything else contributes zero.

**Canonical acceptance is read from the authoritative document state**, never inferred from
sync UI text. `txn_number` is the marker on both engines: it is issued by the server on
acceptance and by nothing else, it is `NULL` on every locally created document (a check
constraint ties it to `financial_year`), and no client can invent one (D-008, D-085).

## D-169 — `expense.view.own` means the expenses that user created
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D7) — closes finding E1

**The defect, proven against `krishna-mis-dev`.** The capability is described in the
catalogue as *"View expenses this user created"*. `expense_visible_units()` returns the
units where the caller holds `expense.view.all` **or** `expense.view.own`, and **no read
path anywhere applies a `created_by` predicate** — verified by exhaustive search of every
policy, view and function in `public` and `app`.

Read as the one Data Entry identity on the development project, holding `expense.view.own`
on Crystal Canopy and nothing else:

```
        expense_document               787 rows visible,  724 created by other people
        expense_period_contributions   865 rows visible,  802 created by other people
        expense_allocations            787 rows visible,  724 created by other people
```

Including every expense the Owner and both managers had recorded. The capability that reads
*"expenses this user created"* was, in practice, *"every expense in your unit"*.

**Decision.** It means what it says: **expenses created by that user, within otherwise
authorised scope.** `expense.view.all` behaviour is unchanged, and the fix may only narrow —
no read that is refused today becomes permitted by it.

**The shape of the fix, and why the unit set could not simply be edited.** Ownership is a
property of a *document*; `expense_visible_units()` answers a question about *units*, and a
set of unit ids cannot express "mine". The two questions are therefore separated:

| | |
|---|---|
| `expense_visible_units()` | **unchanged** — whose *lines* may I see, per unit |
| `public.may_read_expense(id)` | **new** — may I see this *document* at all |

and the document predicate is `AND`-ed into every read path, because
`expense_allocations_read` is line-level and would otherwise still hand a `view.own` holder
another person's allocation rows.

**Every consumer was enumerated before the predicate moved**, as the brief required —
the two child-table policies, the `expenses` policy, four expressions inside
`expense_document`, `expense_period_contributions`, `expense_attachments_read`,
`may_read_expense_attachments` and, through it, `may_attach_to_expense` and the Storage
policies.

**One behavioural consequence, stated rather than discovered later:** a Data Entry user can
now attach evidence only to documents they created. Attaching to a manager's expense was
never a designed workflow, and it followed from the defect rather than from a decision.

**Recorded and deliberately not changed:** `public.expense_sees_whole_org()` is on the
reviewed API surface, granted to `authenticated`, and is **called by nothing** — no policy,
no view, no function, no client code. A fifth instance of the family D-068, D-071, D-077,
D-103 and D-116 record. It is outside this slice's four approved findings and removing it
changes the reviewed surface, so it is reported rather than removed in passing (D-127).

## D-170 — Reporting retention is the current and previous financial year, and "not
downloaded" is not zero
**Date:** 2026-09-07 · **Status:** Accepted (project-lead decision, D8)

**Decision.** The canonical offline reporting cache retains the **current financial year and
the previous one**, for the caller's authorised scope. Older ranges are fetched on demand.

**An older range that has never been downloaded, on a device that is offline, returns an
explicit unavailable state.** It does not return zero, and it does not present itself as a
current report. Those are three different answers and only one of them is true.

There is **no reporting TTL**. A report stays useful as *"As of 6 Sep, 7:15 pm"*; age is
disclosed, not enforced. D-112 is not reused — it governs new offline revenue *creation* and
is a tax-correctness gate, which is a different concept from whether a figure may be read.

**Consequences.** The retention window bounds the reporting delta pull and the local
database's ceiling (spec §9, §27). *Unavailable* joins the freshness vocabulary as a state
in its own right, distinct from spec §21.4's three, because those describe how current a
figure is and this one says there is no figure.

## D-171 — The reporting cache is its own authority class, not rows in the transaction tables
**Date:** 2026-09-07 · **Status:** Accepted (project-lead architecture correction A)

**Context.** The audit recommended pulling canonical contributions into the local read
model. The obvious implementation — inserting remote documents into the existing local
`expenses` / `revenue_entries` tables — is wrong, and the project lead stopped it before it
was built.

**Decision.** Server-owned accepted contribution facts live in a **dedicated canonical
reporting cache**, separate from the transactional tables.

**Why the tables cannot be shared.** They hold a different authority class. A local
transaction row can be pending, rejected, conflicted, quarantined or locally created and
never sent — states that belong to *this actor on this device* and that D-070, D-074 and
D-158 all reason about. A reporting row is a **server-owned canonical fact** with no actor
and no local state at all. Mixing them would mean every reporting query re-deriving which
rows are canonical, on tables where the answer varies per row and per user — which is
exactly the arrangement that produced E2.

The cache must support authority scope, the D-070 confirmed-revocation purge, D-074
user-switch isolation, restart, offline reads, correction **replacement**, void propagation
and bounded retention (D-170). It is classified explicitly under `CacheClassification` and
never lands in a generic bucket.

**It is not a second writable financial truth source.** Nothing but the reporting pull
writes it, no client edits it, and the canonical server contributions remain authoritative.

## D-172 — A delta watermark is proven, not assumed
**Date:** 2026-09-07 · **Status:** Accepted (project-lead architecture correction B) —
**the proof is owed by the reporting-sync slice, not by Slice 1**

**Context.** The audit proposed a document-grain delta keyed on `expenses.change_seq` and
`revenue_entries.change_seq`, reasoning that a correction or void bumps the parent. That
reasoning is plausible and was not tested.

**Decision.** It must be **proven behaviourally before the pull is implemented**, on both
engines. Take a canonical document whose reporting contribution can legitimately change
through an allocation or accounting-period mutation, and observe `change_seq` on the parent,
on `expense_allocations` and on `expense_period_allocations`, before and after.

* If every reporting-relevant child mutation reliably advances the parent, that invariant is
  documented **and permanently tested**, because an invariant nothing evaluates is a comment
  (D-068, D-071, D-077).
* If it does not, a parent-only watermark is **invalid** and must be replaced by an
  authoritative effective generation — the maximum relevant parent/child generation, or a
  server-side reporting-delta boundary that names every document whose contribution set
  changed.

**The required property, stated once so it can be tested:** every reporting-relevant
canonical mutation produces a generation a scoped delta pull can observe **exactly once, or
idempotently more than once, but never miss.**

Revenue receives the analogous proof even though its mutation model is believed to bump the
parent — "believed" is the word that makes the proof necessary. Note that
`revenue_components` carries no `change_seq`, `row_version` or `updated_at` at all, so the
revenue delta has no child generation available to fall back on.

## D-173 — The remote-reporting gap is both engines, not revenue alone
**Date:** 2026-09-07 · **Status:** Accepted — a Phase 5 planning correction to the Phase 4
handoff. **Phase 4 history is not rewritten.**

The Phase 4 closure's handoff contract records, correctly, that there is no revenue pull.
It records it as a revenue-only fact. It is not.

**Expenses have no reporting synchronisation either.** `ExpensePull.pullOne(expenseId)`
fetches one document by id and its only production caller is the Review-latest path in
`edit_launcher.dart`. That is a conflict-resolution mechanism, not a reporting one.

Proven exhaustively rather than inferred: the only writers of local `revenue_entries` are
`createLocally` and `applyServerDocument` (whose sole production caller is the revenue
conflict sheet, on a document this device already holds); no `RevenuePull` exists;
`RevenueGateway` exposes no list or range query; and `ReferenceSync` writes only master and
tax-configuration tables. The clinching evidence is in the suite itself — the live two-client
test must hand-`INSERT` an entry and its components into the second device's SQLite with raw
SQL before it can call `applyServerDocument`, because no shipped code path would ever put
them there.

**The server side is not the gap.** Both contribution projections are `SELECT`-granted to
`authenticated` and reachable over PostgREST, with the base tables ungranted. The authorised,
scoped reporting surface already exists; only the client never asks.

**Consequence for Phase 5:** the reporting-sync slice carries **two** pulls, and the
acceptance in that slice proves remote propagation for expenses as well as for revenue.

## D-174 — A `create or replace` is built from what the object is now, not from the migration that first created it
**Date:** 2026-09-07 · **Status:** Accepted — a regression **I introduced** in the D-169
migration and caught one probe later

**What happened.** `expense_view_own_means_own` had to restate `expense_attachments_read`,
because the D-169 document predicate is `AND`-ed into every expense read path. I rebuilt
that policy from `20260829090300_expense_rls.sql` — the migration that first *created* it —
rather than from `20260830130000_attachment_metadata_uses_definer_predicate.sql`, which is
the migration that last *replaced* it, in the D-073a corrective.

The older body inlines the question:

```sql
        exists (select 1 from public.expenses e
                 where e.id = expense_id and not exists (...))
```

An RLS policy expression is evaluated with the **querying user's** privileges, and no
client role holds `SELECT` on `public.expenses` — deliberately, since D-062. So the table
stopped being readable by anybody at all:

```
        select count(*) from public.expense_attachments
          -> 42501: permission denied for table expenses
```

Owner included. Fail-closed rather than a leak, and still a defect: D-063's read authority
became unavailable to exactly the users it exists to serve, and it would have presented as
"attachments have vanished" with nothing in the application able to explain it.

**How it was found, which is the part worth keeping.** Not by review — the SQL says what
its author meant, and I had read it twice. It was found by *widening the green probe*: the
E1 verification query was extended to count `expense_attachments` alongside the three
surfaces it was really about, and that extra column raised `42501`. A probe asserting only
what the change was supposed to affect would have reported success.

**Decision.** Two things, and the second is the durable one.

1. The policy is restored to the definer-predicate form, which now inherits the D-169
   correction through `may_read_expense_attachments` rather than restating it.
2. **A general invariant**: no RLS policy on a financial relation may read a financial base
   table inline. Every such question goes through a `security definer` predicate. Stated
   over the catalogue with a regex on the policy expressions, so it holds for policies
   nobody has written yet.

**Why this is its own decision rather than a line in D-169.** D-045 established the rule
when every table returned 403 because policies called `app.current_org_id()`. D-109
established it again when band and subtype reads called a helper in `app`. Each recorded the
lesson and neither turned it into a check that would catch the *next* shape of it — and the
next shape was not a predicate written against the wrong schema, but a **correct predicate
restored from a superseded version of itself.** That is a genuinely new route to the same
failure, and the rule it yields is narrower and more useful than "be careful with schemas":

> A `create or replace` has to be built from what the object **is**, not from the file that
> happens to define it first. The repository holds both, and only one of them is true.

**Consequences.** Three migrations for one corrective rather than two, and the applied files
are not rewritten to look like something that never ran (A0, D-056). The Owner reads 46
attachment rows again; a `view.own` holder reads only those on documents they recorded,
which is D-169 working through the restored predicate rather than around it.

## D-175 — The margin is an exact ratio, and its precision belongs to whoever prints it
**Date:** 2026-09-07 · **Status:** Accepted — Phase 5 Slice 2

**Context.** Spec §10 defines the margin as `Operating Profit ÷ Net Sales × 100`. That is
the only division in the entire financial model, and it forces two questions the spec does
not answer: what type carries it, and to how many decimal places.

**Decision, on the type.** It is carried as the **exact rational it is** — numerator and
denominator, both in paise, both untouched — and never as a `double`. A margin is a
presentation figure, and the argument for making it a float is that it is only ever
displayed. That argument fails the first time somebody adds two of them, or averages them
across properties: the result is then a financial figure that is wrong in the last place
with nothing in the audit trail to explain it. `MarginRatio` therefore holds
`operatingProfitPaise` and `netSalesPaise`, and nothing has been divided yet, so nothing
has been lost yet.

**Decision, on the precision.** It is **not chosen here**, because the binding spec does
not settle it and a calculation layer that quietly picks two decimal places has made a
presentation decision that every export then inherits.
`MarginRatio.percentageScaled(int scale)` defers it: the caller states the precision it is
about to print, and gets an exact integer at that scale. `scale: 2` on the worked Crystal
Canopy control gives `5653`, which is 56.53%.

**Rounding is half away from zero**, not half up. Half-up is the tax rule (D-017) and it is
right there, because a tax amount is a magnitude. A margin is **signed**, and half-up on a
signed value rounds −12.5 toward zero and +12.5 away from it, so a loss and a profit of the
same size would not be reported symmetrically. Stated and tested in both directions rather
than left to whichever way `~/` happens to truncate.

**Zero net sales is a separate case in the type, not a value.** `MarginNotApplicable` is a
variant of the sealed `OperatingMargin`, so a caller cannot print a number that does not
exist — spec §10 requires "not applicable" and forbids `0%`, `NaN` and `Infinity`. A
break-even month and a month with no trade are different facts and a report that showed
`0%` for both would be lying about one of them.

**Consequence.** A structural guard asserts that no file under `lib/domain/finance` names
`double`, calls `toDouble`, contains a floating-point literal, or uses `/` — which in Dart
returns a double even between two integers, and is therefore the accident this forbids.
Integer division is `~/`. The guard was proven to fail before it was trusted.

## D-176 — The finance domain consumes the engines' own totals, and a missing side is a
type, not a zero
**Date:** 2026-09-07 · **Status:** Accepted — Phase 5 Slice 2

Two shaping choices for `domain/finance`, both about what the calculator is allowed to be
handed.

**It reuses `RevenueTotals` and `ExpenseTotals` rather than defining its own input.** Those
are already the primitive summed-paise shapes the two repositories return — gross, tax, net
and a contribution count on one side; amount and a count on the other — and they are pure
domain with no storage in them. Inventing `PnlRevenueInput` beside them would have created
a second vocabulary for the same figures and a mapping layer whose only job is to be kept
in step. The contribution counts come along for free and are worth having: a total of zero
over no rows and a total of zero over forty rows are different facts, and a report that
cannot tell them apart will eventually present the first as the second.

**A side that could not be established is a different variant, not a nullable field.**
D-163 requires a P&L to refuse rather than substitute an inaccessible side with zero. A
nullable parameter defaulted to zero is exactly the shape that makes that mistake easy —
one forgotten null check and the report shows Expenses against a revenue side the reader
may not see, which is a large loss that never happened and looks precisely like a real one.

So `ReportingSide<T>` is sealed, with `SideAvailable<T>` carrying the facts and
`SideUnavailable<T>` carrying a reason. Both sides of `Pnl.compute` are **required and
non-nullable**: there is no argument a caller can omit, and the refusal is decided by an
exhaustive `switch` over both sides at once, so the compiler rather than a reviewer
guarantees every combination is answered. **An actual zero is `SideAvailable` carrying
zeroes and computes normally** — it is a real answer and stays one.

The reasons are an enum, not sentences: `notAuthorised` and `notDownloaded` (D-170). A
user-facing string compiled into the finance domain is one that cannot be reworded or given
the context the screen has, and this layer has no business owning the wording.

**What the calculator is deliberately not given.** No tax rate, so it *cannot* re-rate an
aggregate — the mistake that costs a paisa a day and cannot be found afterwards is
unavailable rather than discouraged, which is the move D-094 made for `RevenueTaxFacts`. No
sync state, because the canonical-only predicate belongs to the repository in SQL and a
second copy here would be a second place to forget it (D-168). No freshness, which is
Slice 6's and is composable rather than hardwired.
