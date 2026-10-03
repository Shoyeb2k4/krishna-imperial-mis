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

## D-177 — A revenue row's reporting generation never moved, and the effective document generation is now defined
**Date:** 2026-09-07 · **Status:** Accepted — the D-172 proof, and the corrective it forced.
**A production defect**, latent since Phase 4.

D-172 required the delta watermark to be **proven before the reporting pull was written**,
on both engines, rather than assumed. It was, and the two engines gave opposite answers.

### Revenue — case B. The parent generation is frozen after INSERT.

`change_seq` is the project's one observable mutation generation: a single sequence,
`app.global_change_seq`, stamped onto every synced row so a client can ask *"what changed
since?"* (`ARCHITECTURE.md` §5.2). Seventeen tables in `public` carry the column and stamp
it on UPDATE through `app.touch_row`. **Two carried it and stamped nothing** —
`revenue_entries` and `revenue_attachments`, both added in Phase 4.

The column's `default nextval(...)` fires on INSERT, so the value was present, plausible,
and never moved again. Proven through the real RPCs, one transaction each:

```
        after create           change_seq 12945   row_version 1   2026-06-15   voided false
        after amount edit      change_seq 12945   row_version 2   2026-06-15   voided false
        after date correction  change_seq 12945   row_version 3   2026-07-10   voided false
        after void             change_seq 12945   row_version 4   2026-07-10   voided TRUE
```

An edit, a correction that moved the entry **from June to July**, and a void: all four
mutations invisible to any `change_seq > watermark` delta. A device synchronising reports
that way would have taken the sale once and then never heard about it again — keeping a
June figure that had moved to July, and keeping a voided sale on the books for ever.

**`row_version` advanced throughout, and that is what hid it.** `revenue_update` and
`revenue_void` bump the concurrency token by hand, so every conflict test, every stale-write
refusal and the whole Slice 10 acceptance behaved correctly. The one property nobody
exercised was the one a reporting pull needs.

### Expense — case A. Sound, and audited the same way.

```
        step                     parent   allocations   period allocations   row_version
        create                    13003         13000                13002             2
        amount correction         13004         13006                13008             3
        accrual move              13009         13011                13013             4
        void                      13014         13011                13013             5
```

Every reporting-relevant mutation advances `expenses.change_seq` — including the accrual
movement, where **no header field changed** and only the contribution's period moved
(13004 → 13009), and the void (13009 → 13014). `expense_update` always writes the header,
and `app.touch_row` is attached to all three tables.

**But a child can carry a higher generation than its own parent** (13004 < 13006 < 13008),
because the header is written before the lines are replaced. So the parent's `change_seq`
*understates* when the document last changed.

### The effective document generation, defined

```
        Revenue:  revenue_entries.change_seq
                  — components carry no generation at all, and only `revenue_create` and
                    `revenue_update` write them, both of which write the entry. Valid only
                    with the corrective below.

        Expense:  greatest(expenses.change_seq,
                           max(expense_allocations.change_seq),
                           max(expense_period_allocations.change_seq))
```

Taking the parent alone on the expense side would still *detect* every change — it always
advances — but it would report a generation lower than the document's true one. Using the
maximum keeps the watermark honest, and under-advancing is safe in the other direction
because document replacement is idempotent.

**No component `change_seq` was added to revenue.** It would have been symmetrical and
unnecessary: components change only inside a parent mutation, which now stamps the parent.
Adding a column because the other engine has one is how a schema grows fields nobody reads.

### The corrective, and why not `app.touch_row`

`app.stamp_change_seq()` advances the generation and touches nothing else — no
`row_version`, no `updated_at`, no behaviour any client can observe. `touch_row` was
rejected because it *also* does `row_version := old.row_version + 1`, which the revenue RPCs
already do: attaching it would double-increment the concurrency token, and every client
holding a version would be refused `KM003` on its next correction. The narrowest fix that
makes the delta observable is the one that changes nothing else.

`revenue_attachments` is fixed in the same migration. It is outside the reporting path today
(attaching is not editing — D-150), and a column whose value is meaningless is a trap for
whoever first tries to synchronise them.

**Green, through the same RPC sequence:** `13017 → 13018 → 13019 → 13020`, one generation
per mutation, with `row_version` still `1 → 2 → 3 → 4`.

### The invariant is a search, not a list

Every table in `public` carrying `change_seq` must advance it on UPDATE, asserted over the
catalogue with **no exemption list**, at deploy time and again in the host suite. A check
naming the two tables that happened to be wrong would pass for ever and catch nothing — and
the next table to carry the column would arrive exactly as these two did (D-068, D-071,
D-077). The host regression turns red on three tests when the corrective is removed.

---

# Phase 5 Slice 4 — the canonical reporting cache and its delta (2026-09-07)

D-171, D-172 and D-173 set this slice up: a dedicated reporting authority class, a
generation that had to be proven before a delta could be designed, and a gap that turned
out to be on **both** engines rather than revenue's alone. These four record what building
it decided.

## D-178 — The delta unit is a document, and the delta carries no period filter
**Date:** 2026-09-07 · **Status:** Accepted

**The design that looks obvious and is wrong.** *"Fetch the contributions that changed
inside the year I am refreshing."* It is the query anybody writes first, it is efficient,
and it silently keeps a wrong figure for ever:

```
        a sale is corrected from 30 June to 1 July

        a June-filtered delta   returns NOTHING for it — there is no June row any more
        the cache               keeps its June figure
        the figure              is wrong, stable, and reconciles against itself
```

The same shape covers a re-apportioned shared bill (a property loses a line entirely) and
a void (the document contributes nothing anywhere). In each case the correct new state is
*absence*, and a filtered query cannot deliver an absence.

**Decision.** The delta asks for **every** contribution the caller may see whose document
generation is above the watermark, in **any** period, and the **document** is the unit of
replacement. For each retained financial year, a changed document has its cached rows for
that year deleted and its current ones inserted. June loses the rows, July gains them, and
nothing in the client has to know that a correction happened.

**Replacement is bounded by the financial year**, so refreshing one year cannot delete
another year's rows for a document that contributes to both — which a cross-period
allocation legitimately does (D-034). That bound is also what makes retention safe:
refreshing FY2026 never touches FY2027.

**Cost, stated rather than glossed.** An initial pull fetches every contribution the reader
may see, and a later one fetches every changed document rather than every changed row in a
period. At this write volume — a handful of operators, a few thousand contributions a year
— that is a few thousand rows once and a handful thereafter. If it ever stops being, the
answer is a server-side delta RPC that returns absences explicitly, not a period filter.

**Controls, each seen to fail.** Disabling document replacement turns four tests red;
removing the year bound from the delete turns one red (the two-year document); storing
voided rows turns one red. Each was restored and read back (D-142).

## D-179 — A void is visible to the delta only because the projection carries it
**Date:** 2026-09-07 · **Status:** Accepted — recorded because the two rules turn out to be
the same rule

Both contribution projections **carry** `voided_at` rather than filtering it, so that a
voided document stays inspectable while every aggregate excludes it (D-006, D-158). That
was decided for audit.

It is also the only reason a reporting delta can learn about a void at all. A projection
that filtered voided rows would make a voided document simply **disappear** from every
delta, and its cached contributions would stay on a device's books permanently — the one
hazard document-grain replacement cannot cover on its own, because there would be no row
naming the document to replace.

**Decision.** The synchroniser drops voided rows **on the way in**, after counting their
document. The cache therefore holds the active reporting effect and nothing else, which is
what makes the canonical-only predicate unnecessary here rather than merely remembered —
the rule Slice 1 found applied on one engine and forgotten on the other (D-168).

Asserted against the real server, not inferred from the migration: a voided sale's rows
come back from `revenue_period_contributions` carrying `voided_at`, and the cached figure
falls by exactly the sale.

## D-180 — The watermark is the lowest scope's, never the highest
**Date:** 2026-09-07 · **Status:** Accepted

A run covers several properties and, at a year boundary, two financial years. Each has its
own marker, so the delta needs one number from many.

**Decision.** `since = min(marker.generation)` across every requested (unit, year), taking
**zero** for any scope that has no marker, and then less the safety overlap, clamped at
zero.

**Why the minimum is not a preference.** Taking the highest would ask the server for
changes since a point a newly granted property never reached. Every document written below
it would be missed — and missed **permanently**, because the run would then certify that
property complete to the higher generation, so no later delta would ever ask for the
documents it skipped. A gap that writes its own alibi.

The scenario is ordinary: a manager gains Hotel Krishna after months of holding only
Crystal Canopy. Hotel Krishna's existing sales carry generations far below Crystal Canopy's
watermark.

**And the overlap hides it.** With the two generations a few hundred apart the safety
overlap covers the gap and a maximum-watermark implementation passes. The regression
therefore places them **5,000** apart and models RLS in the fake gateway, so the first sync
provably cannot have cached Hotel Krishna by accident. Written that way after the first
version of the control passed against the deliberate defect — the fifth time this project
has had to find a control by expecting red and getting green (D-071, D-074, D-094, D-139).

**The complement.** Every unit in a run is certified to the **same** generation, including
one that had no changed document. One run is one authoritative boundary; a quiet property
certified lower than a busy one would drift permanently behind and re-read the same delta
for ever.

## D-181 — Two adapters behind one port, and production's choice is asserted
**Date:** 2026-09-07 · **Status:** Accepted

`LocalReportingSource` now has two implementations, and they answer different questions:

| | |
|---|---|
| `CachedReportingSource` | the synchronised cache — what the server says the hotel earned and spent |
| `DriftReportingSource` | this device's own contribution projections — what *this installation* recorded |

**Wiring the wrong one produces no error and no empty state.** It produces a correct sum of
the wrong set of rows, on a manager's second phone, indefinitely. That is a worse failure
mode than D-077's, where two real devices at least *said* attaching was unavailable.

**Decision.** Production resolves the cache, and the wiring is asserted rather than
intended: `bootstrap` builds the gateway beside every other one, `main()` overrides the
provider, the acceptance harness covers it, and a host test reads what
`localReportingSourceProvider` actually returns. D-134's guard refused the change until the
harness matched `main()`, which is that guard earning its place a second time.

The source takes its owner as a **constructor field** rather than a call argument, the
shape `SyncEngine.actorUserId` already has: there is no signature by which a caller reads
somebody else's figures by forgetting to say whose they are (D-050, D-074). Before sign-in
it names the anonymous principal, who owns no cache rows by construction — so a screen that
forgets to check the session gets nothing rather than the previous user's P&L.

**Recorded and not fixed here:** coverage is one value per property, so a scope missing only
its expense side refuses as `bothSidesUnavailable` rather than naming the absent half. The
rule D-163 states is satisfied — it refuses — and the finer message belongs to Slice 5,
which owns what a manager is actually told.

## D-182 — Three files were in the wrong place, and the guard said so
**Date:** 2026-09-07 · **Status:** Recorded

Slice 3's assertion that *no management formula lives in an engine* (spec §21.2) refused
three new files in `lib/data/reporting/`. Each refusal was correct, and each was fixed by
**moving the file** rather than widening the check — which is the D-103 anti-pattern this
project has now recorded three times:

| File | What the guard saw | Where it belongs |
|---|---|---|
| the reporting cache | `Money.fromPaise(` | it sums in SQL and wraps the result, which is what a repository does — `lib/data/repositories/` |
| the synchroniser | `rate_bp` | it copies a rate across the wire without computing with it, which is transport — `lib/data/sync/` |
| `financialYearsCovering` | `FinancialYear(` | period math, so `domain/finance` (spec §21.1), where the engine, the coverage oracle and retention read one answer |

The third is the one worth keeping. *"Which financial years does this range touch"* had been
written in the data-layer adapter that needed it first; a range spanning 20 March to 10
April is **two** years, and coverage, retention and the delta must not be able to disagree
about that. A guard written against a property rather than a naming convention found a real
design error while looking for arithmetic.

`lib/data/reporting/` now holds the engine and its two sources, and nothing in it touches
paise, a rate or a date derivation.

---

# Phase 5 Slice 5 — the server reporting boundary and D-020 parity (2026-09-08)

## D-183 — Coverage is per side, because the two sides are established separately
**Date:** 2026-09-08 · **Status:** Accepted — corrects what Slice 4 shipped

**The defect, and it was in the seam rather than in either half.** Slice 4 stored coverage
markers per **dataset**: `(owner, business unit, dataset, financial year)`, revenue and
expense certified independently, exactly as they are synchronised independently (D-108).
`UnitReportingFacts` then carried **one** `ReportingCoverage` per property, and the engine
handed that single value to both sides of `Pnl.compute`.

So a scope whose expenses were fully synchronised and whose revenue had never arrived
refused as `bothSidesUnavailable` — naming neither the side that was missing nor the side
that was fine. The refusal was correct (D-163 requires it) and the *reason* was wrong, and a
wrong reason on a refusal is not cosmetic: it sends somebody to look for a problem that is
not there and away from the one that is.

**Decision.** Coverage is established, carried and reported **per side**:

```
        markers            per dataset          (unchanged, since D-108)
        oracle             coverageFor(unit, range, side)
        UnitReportingFacts revenueCoverage, expenseCoverage
        engine             each side mapped independently into Pnl.compute
        envelope           revenueCoverage, expenseCoverage
```

Revenue missing alone → `revenueUnavailable`. Expenses missing alone →
`expensesUnavailable`. Both → `bothSidesUnavailable`. Both complete over a range with no
trade → a real ₹0 report, because zero is a figure and unavailable is not (D-176).

`ReportEnvelope.coverage` survives as a **lossy** single badge for a caller that shows one
indicator, and is documented as never consulted to decide a refusal — the refusal is already
in the outcome, per side.

**`ReportingCoverage` gains a third value, and that is not a reversal.** Slice 3 wrote the
enum with two and said in as many words why: an `unavailable` beside `notDownloaded` had no
producer, and a value no code constructs is the gap D-108 had to reopen. Slice 5 gives it
one. The remote source reads a server that always holds the canonical facts, so it can never
answer `notDownloaded`; what it *can* answer is that this caller holds no authority over a
side. **"Synchronise this" and "ask somebody for a grant" are different instructions**, so
`notDownloaded` and `notAuthorised` stay different values and travel into
`ReportingSideUnavailable` unchanged.

**Positive control, seen to fail.** With the engine reverted to handing
`facts.weakestCoverage` to both sides — the Slice 4 behaviour — **five** tests turn red: the
three D-183 refusal cases, and the two remote-authority cases including the Data Entry one.
Restored and read back (D-142).

## D-184 — The server reporting boundary is `security invoker` and adds no data access
**Date:** 2026-09-08 · **Status:** Accepted

**The problem this had to solve.** Slice 5 needs an authoritative server calculation to
measure the offline cache against, and Slice 7 — not Slice 5 — owns `reports.view` and the
complete reporting capability matrix (D-164). Shipping a client-callable P&L endpoint that
skipped the authorization work would be exactly the temporarily under-authorized surface the
brief forbids. Shipping the aggregation core with **no** client `EXECUTE` — the preferred
option — would have left the parity harness unable to call it: the live suites authenticate
as real development identities holding the anon key, nothing in `app` is reachable by a
client role by design (D-044, D-045), and no service-role path exists or should.

**Decision.** `public.reporting_primitives(uuid[], date, date, boolean)`, and the whole of
its safety is that it is **`security invoker`**.

It runs with the **caller's own privileges**, over the two `security_barrier` contribution
projections and nothing else. Every predicate that already governs a reporting read governs
it: `current_org_id()`, `has_capability('revenue.view', unit)` on one side,
`expense_visible_units()` plus `may_read_expense()` on the other. **Anything it can return,
the caller could already have selected row by row and added up.** It therefore grants no new
data access at all, which is what makes it safe to expose before Slice 7 rather than in
spite of Slice 7.

A `security definer` version would have run as the owner against tables the caller
deliberately cannot read, and handed one property's figures to the other property's manager.
Two invariants assert `prosecdef = false` — one in the boundary migration, one in the API
surface restatement, where a reviewer looking for it will find it.

**It enforces D-164's data half now.** `revenue.view` gates the revenue side and
`expense.view.all` gates the expense side, per property, and **`expense.view.own` never
qualifies** — a subset of one author's costs is not a property's cost base. An unauthorised
side comes back **null, never zero**, so the shape §34 names is unavailable: a Data Entry
holder cannot receive a plausible P&L assembled from their own costs against a revenue side
of nothing. Proven live from the payload as well as from the refusal.

**What it does not check is `reports.view`**, which today has an evaluator nowhere and sits
on D-139's exemption list. That stays Slice 7's, deliberately. Its absence creates no
exposure for the reason above; it is a third gate on top of a boundary that already holds,
not the boundary itself. **No STOP was required**, because a secure client-callable engine
demonstrably exists without moving that boundary forward.

**One statement, therefore one snapshot.** Revenue and expenses are read in a single SQL
statement, so under Postgres MVCC both sides come from one snapshot. The dangerous shape —
read revenue, let a transaction commit, read expenses, and call the pair one P&L — is
excluded **structurally**: the function is `language sql` and an invariant refuses a body
containing more than one statement or a `plpgsql` rewrite, where two statements under READ
COMMITTED would take two snapshots. The scope-wide read exists for the same reason, so a
consolidated total is never assembled from two properties read at two moments.

**And the hazard is demonstrated rather than argued.** The live control drives the
interleaving itself — read revenue, void both documents, read expenses — with no sleep and
no race, and produces `(R, 0)`: a pair that was never true of the hotel at any instant. The
RPC, asked at any moment, returns one of the three states that were.

**It derives nothing.** No tax rule, no rate, no business date, no accounting period, no Net
Sales, no Operating Profit, no margin. It returns summed integer paise and the counts behind
them, and the derived P&L is `domain/finance`'s on both engines (spec §21.1, §21.2, D-020).
It therefore needs no tax configuration to answer a historical P&L. Every sum is cast to
`bigint` rather than left as the `numeric` that `sum()` returns, and an invariant refuses a
body naming `float`, `real` or `double precision`, or reaching for a rate.

**Scope cannot widen by omission.** `unnest(coalesce(p_business_unit_ids, '{}'))` over a null
or empty array yields no units, so there is no branch in which an omitted id means the whole
organisation; the client then refuses `noPermittedBusinessUnit`. Asserted at deploy and
proven live with a null argument.

## D-185 — Two engines, one orchestration; the parity that matters is between the sources
**Date:** 2026-09-08 · **Status:** Accepted

Spec §21.2 says an engine's whole contract is *"select and sum the right rows"* and that it
*"performs no business arithmetic"*. Taken seriously that leaves an engine with nothing to
differ about **except its source** — so `LocalReportingEngine` and `RemoteReportingEngine`
are one `ReportingEngine` over two adapters behind one port, and the D-020 suite compares
two *sources*: does the synchronised offline cache mean the same thing as the authoritative
backend?

Writing the orchestration twice so the parity suite had two copies to compare would be
testing a duplication this design exists to avoid — and it would compare them on the one
axis that cannot go wrong while leaving the axis that can, the rows, untested. A structural
guard asserts both engines `extends ReportingEngine` and that neither has acquired its own
`Pnl.compute(`.

**The comparison is exact and has teeth.** Range, scope, Gross Sales, GST, Net Sales,
Expenses, Operating Profit, **contribution counts**, per-unit totals, consolidated totals,
the revenue category breakdown **including its treatment**, and the expense hierarchy
breakdown. No tolerance, integers only. The counts are in it because two engines can agree
on every figure while one of them summed the wrong set of rows to get there — a control adds
a zero-valued ghost row and the comparison fails on the count alone. A second control
degrades the server model to re-rate an aggregate, producing `750714` where the truth is
`750715`, and the suite fails on that one paisa.

**One asymmetry is designed and is stated rather than skipped.** The remote engine can answer
a range the device has never downloaded; the local engine answers `notDownloaded`, correctly
(D-170). That is the two engines disagreeing about *coverage*, not about money, so parity is
asserted only where local coverage is complete and
`expectLocalUncoveredWhileRemoteAnswers` asserts the other case explicitly — a harness that
silently skipped disagreements would skip real ones too.

**The remote engine writes nothing.** It fills no cache, moves no coverage marker and holds
no database; a guard forbids the words that would let it. A remote read that synchronised on
the way past would make the two sources agree because one had just overwritten the other,
which is the opposite of a parity proof. Retry is therefore free — the query is read-only
and `stable` — and the local engine holds no reference to the remote one, so reporting stays
ungated on connectivity (spec §21.4).

## D-186 — The reporting boundary reads each side once
**Date:** 2026-09-08 · **Status:** Accepted — a measured change

`EXPLAIN (ANALYZE, BUFFERS)` as the development Owner, over the whole of FY 2026-27:

```
        revenue aggregate     0.3 ms   Index Scan using revenue_entries_reporting_idx
        expense aggregate   368.7 ms   Index Scan on expense_period_allocations,
                                       Filter: may_read_expense(expense_id)
                                       1,094 rows, 11,240 buffer hits in that one node
        reporting_primitives(both units, whole FY, breakdown)   774 ms
```

The expense projection carries a per-row `security definer` predicate (D-169), so every
candidate row costs a function call — and the first version of the boundary scanned that
projection **twice** whenever a breakdown was asked for, paying that cost again for an answer
it already had.

**Decision.** Each side is grouped once, at its finest grain, and the headline figure rolls
up from those subtotals. Integer addition is associative and rounding happened once at the
component and was stored (spec §6.5, D-017), so the rolled-up total is the same integer as
the direct sum — to the paisa, with nothing to reorder. `p_breakdown` now governs only what
is **returned**, not what is read, and an invariant asserts each projection is named exactly
once in a `from`.

Warm, after: FY consolidated with breakdown **398.6 ms**, without breakdown **368.7 ms** —
the breakdown now costs about thirty milliseconds rather than doubling the query. One month
for one property is **39 ms** server-side and 98–185 ms end to end including the round trip
to Mumbai, well inside the 400 ms escalation trigger `ARCHITECTURE.md` §9 records. The full
Slice 5 live parity suite was re-run against the replacement and is green.

**Recorded and deliberately not changed:** `may_read_expense` evaluated once per candidate
row is the whole of the remaining cost. Making it cheaper is a change to how an expense's
visibility is decided — a reviewed authority predicate — and belongs with the reporting
capability model (Slice 7) or performance hardening (Slice 8), not inside a parity slice
(D-127). **No materialised view and no aggregate table**: nothing has been measured that
needs one.

---

# Phase 5 Slice 5 corrective — the reporting boundary enforces `reports.view` (2026-09-08)

## D-187 — `SECURITY INVOKER` answers a question about data access, not the reporting authorization contract
**Date:** 2026-09-08 · **Status:** Accepted (project-lead ruling) — **corrects D-184**

**What D-184 concluded, and why it was too narrow.** Slice 5 shipped
`public.reporting_primitives` enforcing two of D-164's three capabilities — `revenue.view`
for the revenue side, `expense.view.all` for the expense side — and not `reports.view`. The
reasoning recorded in D-184, and repeated in `ARCHITECTURE.md` §31.2, `DATABASE_SCHEMA.md`
§11 and the ledger, was that `security invoker` prevents the function returning any row the
caller could not already have selected row by row and added up, so the missing check
*"creates no exposure"* and *"no STOP was required"*.

The first clause is true and remains true. The conclusion drawn from it is not, and the
project lead has ruled:

> `SECURITY INVOKER` correctly prevents the RPC from exposing underlying financial rows the
> caller could not otherwise access, but that is **not** sufficient for the approved
> reporting authorization contract.

D-164 is a statement about **who may read a report**, not merely about which rows a query
may touch. It names three capabilities and it names them for a reason: reporting is its own
privilege in this product's permission model, and a client-callable P&L endpoint that
enforces two of the three is under-authorized against the approved contract however little
it can expose. *"Nothing leaks"* is a claim about confidentiality; *"this principal may run
a report"* is a claim about authority, and the second was never established.

**Proven red before it was closed**, with a capability-based fixture rather than a role
name — so the proof does not depend on today's role templates, and would still be the proof
if the templates changed tomorrow. A purpose-built principal holding exactly `revenue.view`
and `expense.view.all` for Crystal Canopy, and no `reports.view`:

```
        reports.view      false
        revenue.view      true
        expense.view.all  true

        reporting_primitives(CCR, FY 2026-27)
          expense.amount_minor  22808602   over 63 contributions
          revenue_authorised    true
          expense_authorised    true
```

₹2,28,086.02 of a property's cost base, returned to a principal the approved contract does
not permit to read a report at all. No existing development identity could have shown this —
every principal holding the two data capabilities also holds `reports.view` — which is
exactly why a fixture had to be built rather than an existing login reused.

**The corrected rule, enforced in `20260908050614`:**

```
        reporting_ok(unit) = has_capability('reports.view', unit)
                             AND (one property requested OR unscoped reporting authority)

        revenue_authorised = reporting_ok AND has_capability('revenue.view', unit)
        expense_authorised = reporting_ok AND has_capability('expense.view.all', unit)
```

`expense.view.own` is named nowhere in the body and cannot qualify. Nothing branches on a
role code, and a deploy-time invariant refuses a body that names one.

**Missing authority is never zero, and it cannot produce half a P&L.** An unauthorised side
comes back `null`, exactly as before; what is new is that a missing `reports.view` removes
**both** sides together, so there is no combination of absent capabilities that yields
Revenue against Expenses of nothing, or the reverse. The client refuses
`bothSidesUnavailable` and renders no figure (D-163). The same green probe now returns
`revenue: null, expense: null`.

**The client needed no change at all, and that is the design working rather than luck.**
`RemoteReportingSource` already maps a null side to `ReportingCoverage.notAuthorised`, and
`ReportingEngine` already maps that to a `SideUnavailable` refusal. No authorization logic
was added to `Pnl.compute`, which stays a pure calculator that is handed two sides and never
asks who is looking (D-176). Authorization belongs outside the finance domain, and it stayed
outside it.

**The consolidated rule (D-164), which is the half that is easy to get wrong.** A request
naming **more than one** property is the organisation report, and requires the **unscoped**
form of all three capabilities. Two scoped grants do not silently add up to an
organisation-wide privilege — their holder keeps every per-property report their authority
supports and does not get the consolidated view.

Proven in both directions, because a test that only showed the refusal could not tell *"the
unscoped rule binds"* from *"consolidated never works"*:

| | |
|---|---|
| a principal scoped to CCR **and** HKI, each alone | authorised |
| the same principal, both together | **refused**, both units `notAuthorised`, both sides null |
| the unscoped Owner, both together | authorised |

The scoped fixture for the first two rows was made and withdrawn through the real
administrative RPCs inside the live suite, with the withdrawal read back (D-142); the
capability-only probe that proved the original gap was built and removed the same way, and
the removal was read back too.

**Positive control, seen to fail.** With the consolidated condition removed from the body,
the live regression turns **red** on exactly the assertion it exists for — the scoped
holder receives the organisation report. Restored, and the restore read back before anything
else was claimed.

**D-139's exemption list is updated in the same corrective**, which is the only honest place
for it. `reports.view` was exempt because *"the surface it governs does not exist yet"*, and
that sentence stopped being true the moment Slice 5 granted a client-callable P&L endpoint
to `authenticated`. Its line goes; `reports.export`, `reports.print` and `settings.manage`
stay, because those surfaces are Phase 7 and genuinely do not exist. A third assertion
states the requirement positively — `reports.view` must be granted to some role **and**
named by the boundary — because the two existing assertions would both pass if it were
simply granted to nobody, which is the D-139 defect in reverse.

**Two host-side guards had to be corrected before they could see any of this**, and both are
the family this log keeps recording:

* the exemption list was read with `firstMatch` over every migration, so a later
  restatement was invisible and the test would have gone on checking a list two migrations
  out of date while reporting success. It reads the **last** declaration now;
* the evaluator extraction matched only a bare `$$` function body. `reporting_primitives` —
  the evaluator the list now depends on — is quoted `$fn$`, so with the exemption removed
  the test would have reported `reports.view` as dead. The body tag is captured now. That is
  D-155's finding in a new file, and the third instance of D-103.

Both were found by expecting the corrected test to pass and watching it fail for the wrong
reason, which is the same discipline as expecting red and getting green.

**What this corrective deliberately does not do.** It does not remove
`public.expense_sees_whole_org()`, redesign the reporting role templates, build any Slice 7
reporting-security UI or provider work, or add an export or print evaluator. It moves the
capability boundary forward by exactly one evaluator at exactly one boundary. Slice 7 still
owns the comprehensive reporting capability audit, the accumulated-state security
acceptance, the dead-API review and the remaining reporting-security surface.

**And the closure record is corrected rather than quietly reissued.** The Slice 5 report
claimed a complete authorization story and did not have one. D-184 stays as written —
this log is append-only — and every canonical document that repeated its conclusion now
says what was actually true: the original enforced the **data** half of D-164, the reporting
half was missing, and Slice 5 is closed on the corrective rather than on the first report.

---

# Phase 5 Slice 6 corrective — one report is one snapshot (2026-09-08)

## D-188 — Local as-of coherence: a report's facts must belong to one authoritative snapshot
**Date:** 2026-09-08 · **Status:** Accepted (project-lead ruling) — **an as-of correctness
defect in the Slice 4 synchroniser, found by the audit Slice 6 opens with and corrected
before any freshness work began**

Slice 6 was told to prove, before implementing anything, that the reporting cache can
honestly say *"as of T"*. It could not, and the reason is not a bug in a line of code — it
is that nothing in the design ever established what "as of" meant.

### What was actually shipped, read from the tree rather than from the closure record

Three facts, each verified against the code and against `krishna-mis-dev`:

* **`generation` is data-derived, not a boundary.** `ReportingSync` set a year's generation
  to `max(change_seq)` **over the rows that happened to come back**. It is the largest
  document generation the delta returned, and it says nothing about what the server held
  when it answered. Measured live: revenue max 19981, expense max 19658, head 19981 — the
  expense side's "generation" was 323 behind the revenue side's, from one run, with nothing
  wrong.
* **Two datasets were two HTTP calls, therefore two snapshots.** The revenue delta and the
  expense delta were separate PostgREST requests. Under READ COMMITTED each took its own
  MVCC snapshot, and anything committing between them lands in one and not the other.
* **`server_confirmed_at` was never written by any call site.** The marker column existed
  from Slice 4 and every reporting caller left it null. There was no server-confirmed time
  in the reporting cache at all.

### The interleaving, constructed rather than imagined

```
        t0   revenue delta answers; revenue certified to 19981
        t1   a sale is accepted                     change_seq 19990
        t2   an expense is accepted                 change_seq 19991
        t3   expense delta answers; expense certified to 19991
```

The cache now holds revenue as at t0 and expenses as at t3. **There is no generation G for
which this cache equals the server's state**, and a report drawn from it is a P&L of a
moment that never existed. Both halves are canonical; the pair is not a snapshot of
anything. Under D-163 the two sides are subtracted from one another, so the error lands
directly in Operating Profit — and it is invisible, because every figure reconciles.

### The corrective, in one sentence

**A successful reporting synchronisation establishes ONE coherent authoritative PostgreSQL
snapshot for every dataset it certifies, and a report may claim currentness only when every
required segment provably belongs to one such snapshot.**

### Transport — one statement, one snapshot, one server time

`public.reporting_snapshot(uuid[], bigint, bigint) returns jsonb` (`20260908122910`) returns
**in a single SQL statement**, under one MVCC snapshot: `pg_current_snapshot()` as an opaque
identity, `now()` as the server's own transaction time, the per-unit authority answer, and
both datasets' contribution rows.

* **Not `plpgsql`, and not two calls.** `language sql`, and a deploy invariant refuses a
  body containing more than one statement — the same structural argument
  `reporting_primitives` already carries (D-184). A revenue query followed by an expense
  query is precisely the defect and cannot be written here.
* **The server time comes from the same statement.** Not a second `select now()`, which
  would date one moment with another's clock, and never `DateTime.now()`, which is a device
  reading and is not evidence about a server (spec §9).
* **`now()` rather than `clock_timestamp()`**, deliberately: `now()` is the transaction
  timestamp, which is the moment the snapshot belongs to, and PostgREST gives each RPC its
  own transaction.
* **It is not the Slice 5 aggregation RPC.** It returns canonical facts and nothing derived
  — no P&L arithmetic, no tax re-rating, no UI strings — and `reporting_primitives` is
  untouched apart from stating its own `server_time` from its own statement
  (`20260908124127`).

**Authority is preserved and is stated explicitly per unit**: `reports.view` ∩
`revenue.view` ∩ `expense.view.all` (D-164, D-187), `security invoker`, no base table
exposed, no role name, non-enumeration kept, and `reports.export` / `reports.print`
deliberately **not** required — a snapshot for reading a report is not an export.

### Snapshot identity and the delta cursor are separate, and stay separate

They answer different questions and one cannot stand in for the other:

| | |
|---|---|
| **snapshot identity + server time** | *which authoritative moment these facts jointly are* |
| **`change_seq` cursor** | *where the next delta resumes* |

A sequence value is allocated when a row is written and becomes visible when its
transaction commits, so `change_seq` orders work and **dates nothing** (`ARCHITECTURE.md`
§5.2). *Complete through generation G* therefore does **not** mean *every canonical
transaction with `change_seq <= G` was in this snapshot*, and the safety-overlap doctrine
(D-180) remains required exactly as it was.

**`min(generation)` is explicitly prohibited as a coherence rule**, and the prohibition is
installed rather than written down: a behavioural regression certifies two properties to
the *identical* generation from two runs and requires the report to refuse the freshness
claim, and a structural guard fails if any file in `lib/data/reporting` so much as names a
generation. Both were seen to fail before they were trusted.

### Local schema v18 — the smallest change that can express membership

`reporting_coverage_markers` gains **`snapshot_id`**, beside the `server_confirmed_at` the
table already had and nothing wrote. A marker therefore answers *which authoritative
snapshot these facts jointly represent*, and **nullable is the honest type**: a marker
written before this corrective cannot prove membership of anything, and null is refused
rather than treated as coherent by default.

Chosen over a separate snapshot table because coherence then needs no join, the aggregate is
one comparison, and the duplication is bounded by units × datasets × years. The v18 step
carries the D-144 range guard.

**The commit order inside the one local transaction is part of the rule:** receive the whole
snapshot → begin → revenue replacements → expense replacements → coverage markers →
**shared snapshot evidence last** → commit. A run that fails anywhere leaves no evidence and
no half-certified side, which is what makes *"one snapshot or none"* true rather than
intended.

### What is refused, and what is never refused

A report whose required segments — every property, **both** datasets, every financial year
the range touches — do not all carry the **same** evidence produces **no freshness claim**.
It still produces the report: the figures are canonical, availability is unchanged, and
nothing about money moves. Withholding the stronger claim is the whole of the remedy.

Null is **not** a third freshness state and must never be rendered as one.

### Consequences

* Slice 4's `f9711ae` … `f20a37f` are not rewritten. This is a corrective on top of them,
  with its own commit, and the defect is recorded rather than tidied away.
* The delta, the safety overlap, the document-grain replacement (D-178), the void handling
  (D-179) and the lowest-watermark rule (D-180) are all unchanged.
* The local consolidated-unscoped reporting rule is still unenforced on the device and is
  still Slice 7's.

---

# Phase 5 OA-1 — Owner Accounts Foundation: the project lead's ratified decisions (2026-09-09)

Owner Accounts is a **newly discovered real business requirement**, audited before it was
built and approved with eleven binding decisions, **OA-D1 … OA-D11**. They are recorded
here as **D-189 … D-199**, in the order they were given, so a later reader needs the
decision log rather than a brief.

**What OA-1 builds, and what it deliberately does not.** OA-1 is the *foundation*: owners,
ownership shares, family members, the owner ledger and its movements, the capability
namespace, the server boundary and the local schema. It builds **no settlement
calculation, no statement, no owner reporting surface and no client screen** — those are
OA-2 and OA-3. Where a decision below governs something OA-1 does not build, it says so
in as many words, in the shape D-078 … D-087 used for the Phase 4 planning baseline.

**And it corrects nothing that was accepted.** The P&L, Revenue, Expense and reporting
semantics closed in Phases 3 to 5 are untouched: `Pnl.compute` is not edited, no
contribution projection changes, and a host test compares the expense and revenue
contribution totals before and after owner movements are recorded and requires them equal.

## D-189 — The profit share is 50:50, in integer basis points (OA-D1)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** Two owners, **5000 basis points each, totalling exactly 10000**. Held as
`ownership_shares` rows carrying `share_basis_points integer`, date-effective, never a
percentage and never a `double` — the same representation `rate_bp` has carried since
D-017, for the same reason: 50% of an odd number of paise has to reconcile exactly.
**No share is seeded.** The ratio is a business fact and the real owner identities and the
inception date are bootstrap data nobody has supplied; a migration writing `5000` against
a real owner would be a financial claim the project lead never made (D-043's rule, applied
to a second kind of configuration). The live suite asserts that **no ownership share exists
for any owner outside its own two synthetic fixtures.**
**A ratio change takes effect at the start of a month**, refused otherwise with a sentence,
because a mid-period change would split a settlement period into two ratios and OA-1 builds
no apportionment for that. See D-190 for what a share is *not* allowed to do.

## D-190 — The owner account is a carry-forward current account, and its balance is derived (OA-D2)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** An owner's position is a **current account** that carries forward between
periods, and **the closing balance is derived from the movements — never stored.**
**Why derived.** A stored balance is a second copy of a figure the movements already
determine, and every hazard of one is the hazard of maintaining it: a correction that
forgets to adjust it, a void that leaves it, a replay that applies twice, and a device that
recomputes it differently from the server. That is D-157's argument for the revenue
contribution projection, in the one place where getting it wrong is invisible — a wrong
balance reconciles against itself perfectly.
**Consequence for OA-1:** `owner_ledger_entries` holds movements and nothing aggregated.
A structural guard asserts the owner layer computes **no** balance and **no** entitlement,
because that is OA-3's and a balance computed in two places is a balance that will differ.

## D-191 — An opening balance is an explicit movement, not a column (OA-D3)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** Where an owner's account starts from a position that predates the system, it
is recorded as an `opening_balance` **movement** carrying its own direction, date, actor
and audit row — not as a field on the owner master.
**Why.** A column would be a figure with no date, no reason and no author, sitting outside
the ledger that every other figure lives in, and it would have to be excluded by hand from
every aggregate. As a movement it is dated, audited, correctable by the ordinary path,
voidable with a stated reason, and included by the same rule as everything else.
**It is the one movement type that may be either a credit or a debit**, because an owner's
opening position can be either, and the direction is therefore stated rather than implied
by the type. **No opening balance is seeded**, for D-189's reason.

## D-192 — `settlement_paid` is a V1 movement type (OA-D4)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** Paying an owner their settled share is a first-class movement type in V1,
alongside withdrawal, NC consumption, opening balance and manual adjustment.
**Why it is not "just a withdrawal".** A withdrawal is money an owner took during a period;
a settlement payment is the discharge of a computed entitlement. Collapsing them would make
*"how much has been settled against last year?"* unanswerable from the ledger, and the
question is the whole point of a settlement statement.
**OA-1 records the type and computes no entitlement.** What a settlement *is* — the
calculation, the statement, its states — is OA-3, and OA-1 deliberately builds none of it.

## D-193 — A settlement statement is Draft or Finalized, and "needs recalculation" is derived (OA-D5)
**Date:** 2026-09-09 · **Status:** **Accepted (project-lead decision). NOT implemented in
OA-1.**
**Decision:** A settlement statement carries two stored states — **Draft** and
**Finalized** — and a third condition, **Needs Recalculation**, which is **derived** by
comparing the statement against the facts it was computed from rather than stored as a flag.
**Why derived.** A stored "stale" flag has to be set by every path that could invalidate a
statement, and the path that forgets is the one that matters. Derived, a correction to a
movement inside a finalized period makes the statement *say* it needs recalculating without
anything having to remember — which is D-157's argument again, and D-188's.
**Recorded now, built in OA-3.** OA-1 creates no statement table, no state machine and no
recalculation. It is recorded here so OA-3 does not have to re-ask.

## D-194 — Non-chargeable consumption is valued at the full printed bill (OA-D6)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** When an owner or a linked family member consumes without paying, the movement
is recorded at the **full printed / menu bill value** — what a paying guest would have been
charged — and not at cost, not at a discount, and not at a negotiated internal rate.
**Why.** The figure is a distribution to an owner, and its size is what the business gave
up. Cost would understate it by the margin, which is exactly the amount the other owner is
entitled to see; and a rate nobody has defined would be a business fact the software
invented (`CLAUDE.md`'s rule).
**It is a debit against the owner's account and is not revenue.** It never enters
`revenue_period_contributions`, and it cannot: the Owner Ledger writes to
`owner_ledger_entries` and to nothing else, there is no path from one to the other, and a
host test compares the revenue and expense contribution totals before and after.
**Statutory GST treatment of a non-chargeable supply is NOT settled by this feature** and
is not claimed to be.

## D-195 — Family consumption is attributed to the linked owner, and the server derives the link (OA-D7)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** A family member is linked to exactly one owner, with effective dates. Their
non-chargeable consumption is attributed to that owner. **Family members receive no profit
share** — they are consumers, not owners — and a family member may be recorded as the
person who *collected* a withdrawal while the debit stays with the owner.
**The server derives the owner from the link and refuses a client that disagrees.** A
caller may declare an owner; the declaration is **compared, never used**, and a mismatch is
refused rather than silently re-attributed. That is D-114's contract applied to attribution
instead of to tax, and for the same reason: two defensible answers exist and neither may
overwrite the other silently.
**The link is immutable.** Re-pointing a family member at a different owner would restate
every movement already attributed through them, so the row is the identity: ending a link
and creating a new one is the supported act, and a trigger refuses the reassignment. Each
movement also snapshots the owner the server resolved, so history explains itself without
consulting a mapping that may since have changed (D-080's discipline).

## D-196 — Both owners see both owners' settlement data in full (OA-D8)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision)
**Decision:** Owner visibility is **symmetric and complete**: each owner sees the other's
withdrawals, non-chargeable consumption, opening balance, adjustments and settlement
position, in full.
**Why it is stated rather than assumed.** The opposite arrangement is the one software
usually implements — each principal sees their own — and it would be wrong here. Two
partners settling a shared profit have to be able to check the same figures; a per-owner
view would make the arithmetic unauditable by the person it most affects.
**It is therefore all-or-nothing, and never sliced by property.** An owner's current
account spans both business units, so a per-property slice is not a narrower view but a
misleading one — it shows part of a position with nothing saying so. The read policies are
asserted to carry no `business_unit_id` predicate at all (see D-200 for the defect that
assertion found).
**Staff see none of it.** Manager and Data Entry hold no owner-account capability in V1, so
an operator who records a bill learns nothing about an owner's finances.

## D-197 — The settlement report requires `reports.view` **and** `owner_settlement.view` (OA-D9)
**Date:** 2026-09-09 · **Status:** **Accepted (project-lead decision). NOT implemented in
OA-1** — no settlement report exists yet.
**Decision:** Reading an Owner Profit & Settlement Statement requires the intersection of
`reports.view` and `owner_settlement.view`. Holding the reporting capability is not enough,
because owner settlement is a category of information a finance reader may legitimately be
excluded from; and holding the owner capability is not enough, because the statement is a
report and reporting authority is its own privilege (D-164).
**OA-1 introduces neither capability and no evaluator for them.** `owner_settlement.view`
does not exist in the catalogue, deliberately: a capability granted and evaluated by nothing
is the family D-068, D-071, D-077, D-116 and D-139 record, and OA-3 creates it together
with the boundary that reads it.

## D-198 — The report is called the Owner Profit & Settlement Statement (OA-D10)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision) — naming only
**Decision:** The canonical name is **"Owner Profit & Settlement Statement"**. Not "Owner
P&L": the management P&L is a defined artefact with a defined meaning (spec §10), and a
second document sharing its name would make *"what does the P&L say?"* ambiguous in exactly
the conversation where it must not be. Owner settlement consumes `PnlResult`; it is not a
second P&L.

## D-199 — Owner-account capabilities use underscored first segments (OA-D11)
**Date:** 2026-09-09 · **Status:** Accepted (project-lead decision) — and it prevents a
deploy failure that would have read like a security finding
**Decision:** The namespaces are **`owner_masters.*`** and **`owner_ledger.*`**. **No
capability literal may begin with a bare `owner.`**
**Why, and it is mechanical rather than aesthetic.** Three shipped reporting migrations
assert that no boundary body matches `\mowner\M` — a guard against a **role-name** branch,
because `owner` is an RBAC role code (D-057) and financial logic must never test one
(spec §13.1). Postgres word characters do not include `_`, so `owner_ledger.view` does not
match while `owner.ledger.view` would. A capability named the natural way would therefore
have failed a deploy-time invariant with a message about role-name branching, three
migrations away from the file being edited.
Eight capabilities are created: `owner_masters.view`, `owner_masters.manage`,
`owner_ledger.view`, `owner_ledger.create.nc`, `owner_ledger.create.withdrawal`,
`owner_ledger.edit.all`, `owner_ledger.void`, `owner_ledger.adjust`. The Accountant bundle
receives six — not `owner_masters.manage`, which is master administration, and not
`owner_ledger.adjust`, because a manual adjustment moves an owner's position without a
business event behind it. A host guard asserts the rule over the capability enum, so the
next capability added to this domain is covered by it.

---

# Phase 5 OA-1 — what building it found

## D-200 — A capability granted scoped can never satisfy an unscoped gate
**Date:** 2026-09-09 · **Status:** Accepted — **the third instance of D-110 and D-116**

**The defect.** The two sensitive reads — `ownership_shares` and `owner_ledger_entries` —
were gated on `public.has_unscoped_capability('owner_ledger.view')`, reasoning that an
owner's current account spans both properties and a per-property slice is misleading rather
than narrower (D-196). **The reasoning is right and the mechanism was wrong.** D-025 forces
every non-Owner grant to name a business unit, and a database trigger enforces it, so an
unscoped requirement is satisfiable by the Owner and by nobody else, for ever.

Measured on this project: `owner` unscoped ×1, `accountant` scoped ×1, `manager` scoped ×4,
`data_entry` scoped ×1. So the Accountant — granted `owner_ledger.view` deliberately, and
able to record, correct and void a movement — read **nothing**. The live authorization
matrix caught it: a withdrawal recorded as the Accountant came back to an empty ledger.

**D-110 found a policy requiring a capability no role held; D-116 found three read rules
gated on `revenue.view.all`, which does not exist, so the only sanctioned way to read
revenue returned nothing to anybody including the Owner. This is the same shape a third
time**, and it is invisible to a test that only checks a scoped user sees *less* than the
Owner, because both see zero.

**The fix is `has_capability_anywhere`, and the principle survives intact.** The rule was
never *"the reader holds an organisation-wide grant"* — it was *"either the whole ledger is
visible or none of it is"*. The capability is not used to filter rows, so a holder sees
every movement of every owner or no row at all. What changes is that the business unit named
on the grant does not narrow this one capability, which is **stated in the migration** rather
than left to be discovered from a helper name.

**The class is closed by assertion rather than by care**, in both places it can appear: no
owner-account *policy* may require an unscoped capability no holder can satisfy, and — added
with D-201's corrective — no owner-account *RPC* may either. Both are searches over the
catalogue, so the next policy or function added to this domain is covered.

## D-201 — An ownership timeline moves forward only, and a refusal is a sentence
**Date:** 2026-09-10 · **Status:** Accepted — **found by the live suite's second run**

`owner_share_set` closed an open share that started *earlier* and inserted the new one, and
that was the whole of what it did about the timeline. Asked to configure a share at a date
at or before one already configured, it fell through to the exclusion constraint and handed
the caller `23P01`, a table name, a constraint name and a raw daterange — which spec §13.1
has forbidden in a refusal since Phase 2, and which the same function already avoids for the
mid-period rule by refusing with a sentence "rather than only by the CHECK".

**It was invisible to a suite that runs once.** The first run configured 5000 + 5000 from
2026-04-01 and moved Owner A to 6000 from 2026-07-01, green throughout. The second met its
own residue — permanent residue, because no client role holds DELETE on `ownership_shares`
(D-006) and OA-1 deliberately builds no share-removal RPC, since withdrawing an ownership
ratio is a governance act nobody has specified.

**That is D-076 exactly**, in a new shape: a fixture *date* must survive everything the test
does to the fixture, and in this project financial fixtures cannot be removed. The live
group now computes its base month from where the timeline currently stands and walks it
forward, and it was run **three times in succession, green each time**, because a phase that
can only pass once is not a regression test.

**The rule the refusal states** is §37's, which the suite already asserted from the other
side: *a later change does not restate a historical ratio.* Rewriting a historical ownership
ratio would silently restate every settlement computed under it. It is refused as `KM031`
under its own detail code, `ownership_change_backdated`, and the sentence names the next
month that would work.

**On `KM031` carrying two detail codes**, because it looks like a collision and is not: the
**errcode is the class and the detail code is the reason**. `KM001` has carried
`missing_capability` and `not_permitted` since Phase 2, `KM002` carries three names, `KM015`
carries three, and `ServerRefusal._kinds` maps on the **detail code**, never on the errcode.
Checked against the live catalogue rather than assumed, which is what stopped a "corrective"
that would have been a change to a working convention.

**And the guard for it had to be narrowed before it was trusted.** Its first version
asserted the migration body contains `ownership_change_backdated` — which the migration's
own deploy-time assertion satisfies, so a body whose refusal had been renamed still passed.
It now requires the **refusal site**, `app.refuse('KM031', 'ownership_change_backdated'`.
That is D-139's failure for the third time in this project's own machinery (D-139, D-187,
this), found the way the others were: by expecting red and getting green.

## D-202 — SQLite `trim()` strips spaces only, and a tab is not a reason
**Date:** 2026-09-09 · **Status:** Accepted — **the local mirror of D-138 and D-142**

The local `owner_ledger_entries` CHECK requiring a manual adjustment to state a reason was
written `length(trim(coalesce(reason, ''))) > 0`. **SQLite's one-argument `trim()` removes
spaces and nothing else**, so a single tab satisfied it — the identical defect D-138 found
in `btrim(text)` on the server and D-142 closed across all five mandatory financial reasons.

Fixed here with the explicit whitespace set, `trim(x, char(32,9,10,13))`, on the adjustment
reason and on the void reason, and caught by a test written for the case rather than by
review.

**Recorded and deliberately not fixed: the shipped local revenue and expense void CHECKs
carry the same weakness.** They are outside OA-1's reviewed scope, and widening a scope
because the fix would be small is how a scope stops being reviewable (D-127). The server
boundary refuses a whitespace reason before either constraint is reached, so the exposure is
a local CHECK that is weaker than the rule it backs rather than a reachable path.

## D-203 — What "byte-for-byte" has actually meant, stated once
**Date:** 2026-09-10 · **Status:** Accepted — a correction to this repository's own ledger
wording

`LEDGER.md` has said since Phase 3 that each migration is *"verified byte-for-byte against
`supabase_migrations.schema_migrations.statements`"*. Measured rather than repeated, that has
**never been literally true of any migration in this repository**:

* Supabase stores the submitted text **without its trailing newline**, so every committed
  file is one byte longer than the statement accounting for it;
* an OA-1 file's header names its own ledger version, and the version is assigned by the
  server *at apply time* — so a file naming it cannot be the text that was submitted. Those
  headers were corrected after the versions came back, and one file was additionally renamed
  when the assigned version turned out not to be the predicted one (`20260909120000` →
  `20260909112045`), which is D-102's finding happening again.

**What is true is checked mechanically and is the property that matters**: for all eight OA-1
versions, the committed file and the applied statement are identical in **every executable
line**. Comparing both with blank lines and `--` comment lines removed and each remaining
line trimmed gives an exact match — line count and digest — for each of the eight. The
divergences are confined to comments, blank lines, indentation and that header line.

Two files diverged by more than the header and were checked line by line before this was
written: one by a reworded sentence, one by four expanded comment paragraphs. **No
executable SQL differs anywhere**, which is what D-056 and A0 exist to guarantee.

The wording in earlier ledger sections is not rewritten — this log and that ledger are
append-only records of what was claimed when — and `LEDGER.md` now carries the accurate
statement beside the OA-1 entries.

## D-204 — V1 ownership is fixed at exactly two owners, 5000 basis points each (OA-D12)
**Date:** 2026-09-10 · **Status:** Accepted (project-lead ruling) — **amends D-189**

**The ruling.** For Krishna Imperial MIS V1, ownership is fixed at **50:50 between exactly
two owners**. General variable ownership settlement logic is **not** designed for V1. The
authoritative configured ownership vector for any settlement period must resolve to
exactly `[5000, 5000]`, and the settlement engine must not accept or infer 60/40, 70/30, a
three-owner allocation, unequal active ownership, a partial total, or a total above 100%.
Future 60/40 transition workflows are **not** to be built in OA-1 or OA-2 unless separately
authorised.

**The date-effective schema stays.** The ruling says so explicitly, and it is the right
call: `ownership_shares` keeps its effective dates, its `between 1 and 10000` CHECK and its
exclusion constraint, so every historical row remains exactly as recorded and an authorised
future ratio is a change to a business rule rather than a migration of history. **The
migration asserts the CHECK was *not* narrowed**, because encoding a business rule on a
column is the thing that would make lifting it expensive.

### Proven red first, and the red was not subtle

The shipped resolver accepted every shape the ruling forbids, and each one **totals exactly
10000** — so a total-only check could never have seen them:

```
        [6000, 4000]        -> OwnershipResolved(2 owners)
        [7000, 3000]        -> OwnershipResolved(2 owners)
        [4000, 3000, 3000]  -> OwnershipResolved(3 owners)
        [10000]             -> OwnershipResolved(1 owners)
```

That is why `shareIsNotHalf` is a **separate refusal** from
`sharesDoNotTotalOneHundredPercent`. A refusal that said "the shares do not add up" for a
60/40 configuration would be unhelpful *and false*.

### Enforced twice, deliberately, and the two are pinned to each other

| | |
|---|---|
| **must not infer** | `OwnershipShareSet.resolveV1For` — the call a settlement makes. Refuses everything the general rule refuses, then a vector that is not exactly two owners, then any share that is not 5000 bp, then a share belonging to an owner the caller says is inactive |
| **must not accept** | `owner_share_set` — refuses `KM033 ownership_share_must_be_half` and `KM033 ownership_exceeds_two_owners`, with sentences rather than a constraint name |

The domain rule alone would leave a database able to hold a configuration every settlement
refuses, with the refusal arriving long after the act that caused it. The boundary rule
alone would not stop an administrative write or a legacy row from being *inferred* into a
ratio nobody approved. Both, and a host guard pins the two numbers to each other so one
cannot be edited into disagreement with the other — the discipline D-104 established after
a wire name was written and read through two different spellings.

**`resolveFor` is untouched and composes rather than being replaced.** It stays the general
date-effective rule, because that is what keeps historical records readable, and history
legitimately contains ratios V1 no longer configures. `resolveV1For` calls it and adds the
ruling on top, in one place, so lifting the ruling later is one deliberate change rather
than an audit of every caller. A guard asserts both methods exist and that the second calls
the first.

### The eight properties, and where each is proven

| | Property | Proof |
|---|---|---|
| 1 | exactly two active shares resolve for a settlement date | domain + **live**, through the same resolver a settlement will use |
| 2 | both equal 5000 bp | domain + live |
| 3 | total equals 10000 bp | domain + live |
| 4 | one missing owner refuses | domain — both arms: a lone 5000 fails the total, a lone 10000 fails the count, and only the second needs this decision to exist |
| 5 | any non-5000 share refuses | domain (five splits, including 5001/4999) + **live** (five values, refused `KM033`) |
| 6 | more than two active shares refuses | domain (4000/3000/3000, which totals 10000) + **live** (a third owner refused at the boundary) |
| 7 | historical records remain readable | domain (a 60/40 period still resolves under the general rule and refuses under V1) + live (closed rows unchanged) |
| 8 | no P&L / Revenue / Expense semantics change | the existing structural guards and the live non-interference comparison, re-run |

**Positive control, seen to fail:** with the two V1 conditions disabled, four domain tests
turn red. With the boundary's literal changed to 6000, the pinning guard turns red.
Restored and read back in both cases (D-142).

### Two consequences worth stating

**The live acceptance no longer configures a non-5000 share.** Its supersession test
proved closing-without-overlap by moving Owner A to 6000; it now re-sets 5000 from a later
month, which proves the same property without leaving the development database holding a
vector no settlement could resolve. The suite was run **three times in succession**
afterwards.

**A third synthetic owner exists on `krishna-mis-dev`, holding no share.**
`OA1_TEST_OWNER_C_REFUSAL_FIXTURE` exists so the third-owner refusal is proven against the
real boundary rather than only in Dart — a rule nothing evaluates being the family this log
keeps recording. The test asserts afterwards that it holds no ownership share, because a
refusal test that left one would have broken the invariant it exists to protect.

**Still required before real settlement data is entered: the effective-from date of the
50:50 ownership.** Not guessed, not defaulted to the financial year, and not inferred from
the tax configuration's 2026-04-01 — the same discipline D-043 applied to tax rates.

## D-205 — A refusal must name a remedy that exists
**Date:** 2026-09-10 · **Status:** Accepted — a defect in D-204's own new code, found by
asking whether the action it recommended was available

D-201 established that a refusal "ends in an action rather than in a complaint". The
third-owner refusal D-204 deployed took that literally and got it wrong:

>  "This version allocates profit between exactly two owners, and two are already
>   configured. **End an existing owner's share** before configuring another."

**Nothing can end an owner's share.** OA-1 exposes `owner_share_set` and nothing else — it
closes the *same* owner's previous share as a side effect of setting a new one — and no
`owner_share_end` exists in any migration or anywhere in `lib/`. Substituting one owner for
another is an ownership-transition workflow, which D-204 explicitly defers.

So the sentence sent an administrator looking for a control that is deliberately absent.
**A refusal naming an unavailable remedy is worse than one naming none**: it reads like a
missing button rather than like a decision somebody took, and the person spends their time
hunting instead of asking for the decision to be revisited.

Reworded to state the decision — *changing who the owners are is not part of this version*
— which is both true and the actionable thing, because the action available is to ask for a
different ownership model to be approved.

**Two guards, and the second is the general one.** The deploy asserts the old phrase is
gone; it also asserts that **no owner-share-end boundary exists**, so if one is ever added
the deploy fails and whoever adds it decides what the refusal should then say. The rule
this leaves behind: *the remedy a refusal names is part of the refusal, and it has to be
checked like any other claim.*

**And the host guard for it had to be narrowed twice**, which is now routine enough to be
worth stating as a pattern rather than as an incident. A text search for the old phrase
matched the migration's own deploy-time assertion — the assertion that exists to refuse it —
so the guard read the check as the defect. It now extracts the refusal's **message** and
tests that. Three times in this file, and the same shape every time (D-139, D-187, D-201):
**a guard must look at the thing that acts, never at the text that mentions it.**

Recorded beside it: writing that guard reintroduced **literal backspace bytes inside a
regex** — `` mangled by the shell into `0x08` — which is D-159's finding exactly, and was
caught the same way, by reading the file back rather than trusting the write.

---

# Phase 5 OA-2 — Owner Settlement Engine (2026-09-10)

## D-206 — A device held no canonical owner data at all, and the settlement is built on the fix
**Date:** 2026-09-10 · **Status:** Accepted — **the OA-2 §18/§20 audit, run before any
settlement arithmetic was written**

OA-2 required proving what canonical owner data another device can obtain **before**
building a settlement engine, because an engine over partial local history reconciles
against itself perfectly and is wrong by exactly the movements it never saw. Run against
`krishna-mis-dev` with a fresh device, it found **two** gaps rather than the one OA-1
reported.

**One · no owner ledger reaches a second device.** Device A recorded a withdrawal, the
server accepted it and issued a `KI-OWN` number. Device B — authorised, online, the same
person, asking the most generous question its canonical ledger offers — saw **nothing**.

**Two · no ownership masters reach any device.** `OwnerLedgerRepository.ownershipShares()`
and `familyMapping()` read local tables that **nothing in production writes**. The
gateway's `fetchOwners`, `fetchOwnershipShares` and `fetchFamilyMembers` are called by
nothing anywhere in `lib/` — the D-077 shape. So on every real device the V1 vector
resolves to *no share configured* and an NC bill has no mapping to attribute by. OA-1 did
not report this half, and it is the more severe one.

**The gap was entirely client-side**, which decided the shape of the fix: the same session
that could not see the movement locally was handed it, and all three masters, by the
server. A caller was missing, not a boundary — exactly what D-173 recorded for reporting.

The audit is committed as a permanent test rather than described, and it still asserts the
unsynchronised state; a later group in the same file runs the synchroniser and asks the
same questions again.

## D-207 — The canonical owner pull is a full replace, not a delta
**Date:** 2026-09-10 · **Status:** Accepted — OA-2 §19's decision, documented

Three options were named. **A — a full canonical Owner Ledger pull — was chosen.**

| | |
|---|---|
| **A · full pull** | **chosen.** The ledger is small: a handful of movements a month |
| B · a settlement projection/cache | rejected — an aggregated position is a **second financial truth**, which §19 and §26 forbid, and it would need its own correction and void propagation |
| C · a server settlement query | rejected — a client-callable settlement RPC needs the capability OA-3 reserves, and §44 says to stop rather than ship it under-authorized |

**What a full replace buys is the absence of machinery.** A correction arrives corrected, a
void arrives carrying `voided_at`, and a movement the server no longer returns simply ceases
to exist here — because nothing is preserved across a run. That removes the watermark, the
safety overlap, the document-grain replacement and the lowest-watermark rule the reporting
delta needs (D-178, D-180), one of which took two attempts to control. §19 asks for the
simplest correct option and says not to copy the reporting cache mechanically; this is that.

**It is not written into `owner_ledger_entries`.** That table is this actor's own attempt
state, with an outbox pointer and a D-070 retention stamp. A pulled movement is a
server-owned fact that may belong to **another actor entirely**, and writing one there would
put somebody else's movement under this person's retention rules and make every settlement
query re-derive which rows count — the arrangement that produced the E2 defect (D-168,
D-171). Kept apart, the settlement query has nothing to filter.

**One statement, one snapshot.** `public.owner_ledger_snapshot()` returns movements, owners
and shares together with `pg_current_snapshot()` and `now()` from that same statement. Four
separate reads are four MVCC snapshots, and a settlement assembled from them would be a
position of a moment that never existed — the defect D-188 corrected for reporting, and
repeating it knowingly would be worse than the first time. It calculates nothing, is
`security invoker`, and needs no new capability.

**The commit order is the rule:** one local transaction, coverage evidence **last**, so a
run that fails anywhere leaves no claim and no half-replaced history.

## D-208 — A profit ratio is not organisation-global reference data
**Date:** 2026-09-10 · **Status:** Accepted — **a latent exposure the §20 audit surfaced**

OA-1 classified `owners`, `ownership_shares` and `owner_family_members` as
`organizationGlobal` — the treatment business units, departments and vendors get, which
means they **survive a user switch**.

That was safe only because **nothing ever wrote them**, which is precisely what the OA-2
audit established. The moment a synchroniser fills them, a shared back-office workstation
where the Owner synchronised first leaves the ownership ratio and the owner names readable
by the Manager who signs in next — and OA-1 §31 is explicit that operational recording
authority must not carry profit-share visibility.

**So the settlement reads an owner-keyed copy instead.** `canonical_ownership_shares` and
`canonical_owners` join `canonical_owner_movements` in the OA-2 cache: every row carries the
**signed-in person**, every one is purged on a confirmed revocation, and User B inheriting
User A's ownership data is structurally unavailable rather than something a query has to
remember (D-074).

**Recorded and deliberately not changed:** the three OA-1 master tables remain classified
`organizationGlobal` and remain **empty**, so the exposure is latent rather than live. The
consequence is that OA-1's client-side NC pre-check still cannot run on a real device — it
reads those empty tables — and that is stated rather than fixed here, because filling them
under their present classification is the exposure above, and reclassifying them is a
schema change outside OA-2's reviewed scope (D-127). **OA-3 owns the choice**: fill the
owner-keyed cache and read it from the ledger path too, or reclassify and add an owner key.

## D-209 — The owner settlement position is derived, and the P&L is consumed
**Date:** 2026-09-10 · **Status:** Accepted — the OA-2 engine, as built

**Sign convention (§2), binding:** a positive position means the business owes the owner; a
negative one means the owner has drawn more than their entitlement. Not to be reversed in
storage or in a surface.

```
        closing = opening
                + profit entitlement for the period    (signed; a loss reduces it)
                - withdrawals - NC consumption - settlement paid
                + adjustment credits - adjustment debits
```

written as one statement, because every movement already knows its own direction: the
position is the cumulative entitlement plus the signed effect of every canonical movement to
the cutoff. A movement type added later therefore cannot be forgotten by an arm of a
`switch`.

**Nothing is stored.** No balance column, no settlement table, no statement row. The opening
position for a month is **derived from history before it** (§23), which is why a correction
(§27) and a void (§28) need no propagation machinery at all — they recompute everything
downstream on their own. Guards assert no such column exists locally or on the server.

**Operating Profit is consumed, never recreated (§33).** `Net Sales − Expenses` lives once,
in `domain/finance` (D-020). The settlement domain takes two cumulative figures and cannot
derive either; a structural guard fails the build if the directory names `netSales`,
`grossSales`, `RevenueTotals` or `Pnl.compute`, and a positive control confirms it turns red.

**A settlement is not cash (§15).** There is no treasury model, and a positive position
claims nothing about a bank balance. Calculating a position writes nothing; paying it is a
separate `settlement_paid` movement through OA-1 (§41).

## D-210 — Cumulative entitlement, and the paisa that belongs to neither owner
**Date:** 2026-09-10 · **Status:** Accepted — OA-2 §8, §9, §37, §38

**Halving each month's profit strands a paisa every odd month**, permanently, in a place
nobody would ever look. So entitlement is cumulative from inception and a period's figure is
the **difference of two cumulative splits**:

```
        month 1 profit = 1 paisa    cumulative 1  ->  each 0, remainder 1
        month 2 profit = 1 paisa    cumulative 2  ->  each 1, remainder 0

        allocated: 0 then 1, each = 2 paise exactly
        the naive floor(profit / 2) each month allocates 0 and 0, and loses both
```

Both figures are asserted side by side, so the difference is a stated fact rather than a
discovery.

**The remainder is never given to anybody.** It is an organisation-level figure that resolves
by itself the moment cumulative profit becomes divisible, and it is **never persisted as a
ledger movement** (§9). §9's invariant — `A + B + remainder = cumulative Operating Profit`,
exactly — is a property on the type and is checked across a 2,001-value sweep.

**No owner bias, in either direction.** The split truncates toward zero, so a positive
remainder follows a profit and a negative one follows a loss, and neither owner is ever the
one who happens to receive it. Verified empirically before it was relied on, because getting
it wrong silently favours one person by a paisa.

**A loss is shared (§7)** and never clamped: −₹1,00,000 gives each owner −₹50,000, and
overpayment produces a negative position rather than a floor at zero (§42).

## D-211 — Two guards were wrong on first writing, and both are the same lesson
**Date:** 2026-09-10 · **Status:** Recorded

The oracle guard forbade the production type names in `test/support/owner_settlement_reference.dart`
— and matched the oracle's **own doc comment**, which says it calls none of them. That is
D-139's failure, committed in a guard written while quoting D-139. Fixed by stripping
comments first, using the helper already in the file for exactly that.

The no-mutable-state guard forbade a local accumulator inside a fold — a rule about style
wearing the costume of a rule about money. Narrowed to what actually matters: no static
**field** and no mutable top-level variable, distinguished from a static method by refusing
to cross a parenthesis.

**And the mechanical hazard recurred three times in one session.** Backslash escapes passed
through a shell heredoc into a file arrived as literal backspace bytes inside a regex
(D-159), as an empty raw string, and as a mangled path separator. Each was caught the same
way — by reading the file back rather than trusting the write — which is the only reason
none of them shipped. It is recorded again because it is now clearly a property of the
tooling rather than an accident.

---

# Phase 5 OA-3 — Owner Settlement UI / Security Surface (2026-09-11)

## D-212 — The project lead's OA-3 rulings (Q1 … Q4)
**Date:** 2026-09-11 · **Status:** Accepted (project-lead decision)

OA-3 began with a verification pass and stopped on four questions the repository could not
answer. The project lead answered all four; they are recorded as given.

**Q1 · one date, not two.** There is **no separate settlement inception date** in V1. One
authoritative server date means *"50:50 ownership and owner settlement begin from this
date"*, and it is **not guessed**: until it is configured the settlement surface says
**"Settlement start date not configured"**, the calculator refuses, and nothing defaults.
It lives behind the existing owner-account configuration boundary — gated by
`owner_masters.manage`, never by the Owner role name — and every change is audited.

Built as `public.owner_settlement_settings` (one row per organisation, first-of-month
CHECK, no default, **ships empty**) written only by `public.owner_settlement_start_set`,
which requires unscoped `owner_masters.manage`, refuses a missing or mid-month date
`KM031` with a sentence, enforces `base_row_version` (`KM003`), replays on `mutation_id`,
and audits `ownership_start_set` with before and after values. The row is readable by
holders of `owner_settlement.view` or `owner_masters.manage` — *anywhere*, not unscoped,
because D-200 records what an unsatisfiable unscoped read gate costs.

**The production date is still outstanding.** No migration, fixture or line of code
supplies it.

**Q2 · Owner only.** `owner_settlement.view` is created and granted to the Owner bundle
alone; the Accountant, Manager and Data Entry bundles receive nothing. Enforcement is by
capability, and because a settlement is organisation-wide there is **no partial settlement
for a scoped reader** — a reader without unscoped P&L authority is refused
(`reportingNotAuthorised`), never handed a settlement over the properties they can see.

**Q3 · preview only.** No Finalize, Reopen, Lock, approval or statement versioning exists in
OA-3. The result is labelled a **live, derived preview** on screen. D-193's Draft/Finalized
model is recorded and not built, and nothing in OA-3 invents its rules.

**Q4 · a separate screen.** "Owner Settlement" is its own destination — a Windows sidebar
entry and an Android entry under More → Owner Accounts — shown only with
`owner_settlement.view`, and **not** a tab inside Reports or the P&L. One shared domain
contract, a monthly picker, no charts.

**Consequences.** D-197's intersection (`reports.view` ∩ `owner_settlement.view`) is
satisfied and extended: the server transport requires `owner_settlement.view`,
`owner_ledger.view` and `reports.view` (D-213), and the client preview additionally requires
unscoped `reports.view`, `revenue.view` and `expense.view.all` (D-164, D-187) before it asks
for a figure.

## D-213 — Seeing the ledger is not seeing the settlement, and the server says so
**Date:** 2026-09-11 · **Status:** Accepted — **proven red first**

**The gap.** OA-2's `owner_ledger_snapshot()` was `security invoker` over tables the
Accountant may read, so it handed the Accountant everything a settlement is made of. As the
development Accountant, before the change:

```
        owner_ledger_snapshot()   159 movements · 3 owners · 34 ownership shares · 2 family links
```

That is exactly the private information Q2 reserves to the Owner, and nothing about it
was a leak by OA-2's rules — the Accountant *records* owner movements and legitimately reads
the ledger. Q2 draws a line those rules did not have: **recording authority is not
settlement visibility.**

**Decision.** The snapshot computes `settlement_authorised = owner_settlement.view AND
owner_ledger.view AND reports.view` in one CTE and returns every owner dataset — movements,
owners, shares, family links and the start date — **only** when it is true. Otherwise each
is **null, never an empty list**: an empty list is a claim that the owners hold nothing, and
the client must be able to tell *withheld* from *none* (D-163). The client requires the flag
as a boolean; a payload without it is refused rather than guessed at.

**RLS on `owner_ledger_entries` is deliberately unchanged**, so the Accountant still reads
the ledger it records into. Both halves are asserted live: the same Accountant gets
`settlement_authorised: false` with every dataset null, and still reads ledger rows through
RLS. The Owner is still authorised.

**On the client**, a `false` answer is its own result, `OwnerSettlementSyncNotAuthorised`,
and it **withdraws** this user's canonical owner cache — coverage first — in one
transaction. A reader who loses the settlement does not keep last week's copy of it.

## D-214 — A confirmed capability loss purges the owner-sensitive cache (corrects D-070's trigger)
**Date:** 2026-09-11 · **Status:** Accepted (project-lead decision)

D-070 purges on a confirmed **scope** revocation: losing a business unit. The canonical
owner cache is not scoped by business unit at all (D-196), so a person who kept both
properties and lost `owner_settlement.view` would have lost nothing from their device — the
owners' private position would have stayed readable on a shared workstation by the person
whose permission had just been withdrawn.

**Decision.** `ScopeCachePurge.applyTo` now checks the **confirmed principal's current
capabilities**, not a diff against a previous snapshot. If the confirmed principal lacks
`owner_settlement.view`, `owner_ledger.view` or `reports.view`, this user's canonical owner
cache is purged — coverage first — **even when their business-unit access is unchanged**. If
they lack `owner_ledger.view`, the OA-1 ledger cache is purged for every unit present.

State-based rather than diff-based, for the reason D-111 records: the stored previous
snapshot is per user, so a diff on a shared installation can miss a loss entirely.

**What it never does** — both from D-048 and asserted: nothing is purged on a network
failure, a stale refresh or an unreachable server, because `unknown ≠ revoked`; and
actor-owned unsent work is retained and stamped exactly as D-070 and D-074 retain it.

**Positive controls, each seen RED and restored byte-identical:** the capability purge
disabled (6 red); the restore-authorship predicate removed (1 red, the D-074 case).

## D-215 — `owner_ledger_entries` was classified as purged and was never purged
**Date:** 2026-09-11 · **Status:** Accepted — an OA-1 defect found by the D-214 audit

OA-1 classified `owner_ledger_entries` `scopedFinancialHistory` — *purged on a confirmed
revocation, sparing actor-owned unsent work* (D-070). **`ScopeCachePurge` contained no code
that touched it.** A user switch or a revoked property therefore left synced owner movements
readable on the device: the classification said one thing and the purge did another, and
nothing compared them.

The same family as D-068's vacuous classification guard: the guard proves every table is
*classified*; nothing proved the classification is *implemented*.

**Decision.** `_purgeOwnerLedger` mirrors revenue exactly — synced movements for a revoked
unit are deleted; movements carrying this actor's outstanding intent are retained and
stamped `scope_revoked_at`; restoring scope restores only the actor's own (D-074).
`quarantineAllDocuments` includes the table, `purgeAllScopedCache` covers it, and the
canonical owner cache is purged at sign-out **even when no business unit is cached**, which
the earlier early-return skipped.

## D-216 — D-208 resolved by option B: the OA-1 masters stay unwritten, permanently guarded
**Date:** 2026-09-11 · **Status:** Accepted — the choice D-208 left to OA-3

D-208 left OA-3 two options: **(A)** move OA-1's client-side NC pre-check onto the
owner-keyed canonical cache, or **(B)** keep the organisation-global OA-1 master tables
unwritten, with a permanent guard that nothing writes them.

**Option A is not narrow, and that decided it.** The NC pre-check runs for whoever records
the bill — the Accountant bundle holds `owner_ledger.create.nc` — and after D-213 the
canonical cache is filled only for holders of `owner_settlement.view`. Moving the pre-check
there would either give the recorder settlement visibility (the thing Q2 forbids) or leave
the pre-check reading an empty cache for exactly the people who use it. The server already
derives attribution from the link and refuses a disagreeing declaration (D-195), so the
client pre-check is UX, not the boundary.

**Decision: B.** `owners`, `ownership_shares` and `owner_family_members` stay classified
`organizationGlobal` and stay **empty**. `owner_master_isolation_guard_test.dart` fails if
any file in `lib/` names a Drift writer for them, and carries a self-test proving its
pattern finds a planted writer. The settlement surface reads names only from the owner-keyed
`canonical_owners`. User A's owner identities, ratio and family links are therefore never
readable by User B, by construction.

**The consequence stays stated:** OA-1's client-side NC pre-check cannot run on a real
device, and the server remains the only thing that attributes an NC bill.

## D-217 — Live suites that share one ledger run serially, and a count is not idempotence
**Date:** 2026-09-11 · **Status:** Recorded — two findings from running the owner live
suites together

**1 · A count compared across two live reads is not a property.** OA-2's audit test
*"a second pull is idempotent"* compared the cached movement count before and after a second
pull. Run beside the OA-1 suite, which records movements, the count legitimately changed
between the pulls and the test failed while the property held. It now asserts the property:
after the second pull **every movement id is held exactly once**, and the audit's own
movement once. D-152's rule again — assert the durable consequence, not a number that
another writer can move.

**2 · The OA-3 delta assertions cannot share the ledger with another writer.** The OA-3
end-to-end group asserts that *this* sale moved Operating Profit by exactly its Net Sales and
*this* withdrawal moved Owner A's withdrawals by exactly its amount. Beside the OA-1 suite
the second read saw OA-1's own Owner A withdrawals and the delta was ₹-1,45,000 rather than
₹12,345. Every preview was correct for the ledger it read. **Weakening the assertion to
tolerate another writer would stop it proving "exactly once"**, so the owner live suites run
with `--concurrency=1`, and the suite says so in its header.

**3 · The development start date is a fixture.** The OA-3 live suite sets
**2026-05-01** on `krishna-mis-dev` because no settlement can be exercised without one. It
is **not** the production 50:50 date. It is chosen to look unlike a real answer (not the
FY start, not the tax configuration's 2026-04-01) and to fall inside the development
ownership history's 50:50 window. No client API unsets a configured date, by design; the
administrative removal to restore "not configured" was **not performed** in this session
(the action was declined by the session's permission gate), so the development project
holds that fixture until somebody removes it deliberately. Its two audit rows are
append-only evidence and stay regardless (D-066).

## D-218 — Recorded and deliberately not changed in OA-3
**Date:** 2026-09-11 · **Status:** Recorded

**The OA-1 owner-ledger outbox transport is not wired in `bootstrap`.**
`RoutingMutationEndpoint` is composed with masters, expenses and revenue;
`OwnerLedgerMutationEndpoint` and `OwnerLedgerReconciler` exist and are not passed. A queued
owner movement would therefore be answered terminally by the router and kept for a person
to see (the D-059 behaviour) rather than delivered. **Latent**: no client surface creates an
owner movement — OA-1 built none, and OA-3 is a read-only preview. The D-077 shape, in the
owner domain; it belongs with the slice that builds an owner-movement entry surface, not
inside a read-only preview (D-127).

**No administrative UI sets the start date.** `owner_settlement_start_set` is the reviewed
boundary and is proven live; the screen that calls it is not built. Until it is, the date
is set through the RPC by an Owner session.

**No per-person family breakdown.** The canonical cache does not carry family links, so the
preview shows each owner's non-chargeable consumption as the OA-2 total, not per family
member. Adding it means adding links to the owner-keyed cache, which D-216 deliberately did
not widen.

**`OwnerSettlementRefreshReport.reportingSucceeded` is true for an empty report list.**
Unreachable — a non-empty range always needs at least one financial year — and harmless,
because the preview decides from the coverage on disk, never from the report. Noted so it
is not rediscovered as a defect.

## D-219 — PowerShell text cmdlets corrupt UTF-8 source, and a control restore must be byte-identical
**Date:** 2026-09-11 · **Status:** Recorded — the tooling hazard D-159 and D-211 record,
in a fourth shape

Restoring a positive control with PowerShell `Get-Content -Raw` / `WriteAllText` re-encoded
`owner_settlement_sync.dart` through the ANSI code page and turned every non-ASCII
character — `₹`, `—`, `§` — into mojibake. The file compiled; it was wrong. It was caught by
the diff, repaired by reversing the mis-decode (UTF-8 bytes read as Windows-1252, re-encoded,
decoded as UTF-8), and the repair verified as insertions only.

**Rule, applied for the rest of OA-3:** every positive control is restored with a byte copy
(`cp` of a saved original, then `cmp` to prove identity), and every scripted edit uses Python
with explicit UTF-8 and `newline=''`. A restore is not restored until it has been read back
(D-142) — and "read back" means compared as bytes, not eyeballed.

## D-220 — Canonical cache ownership is not reporting authority
**Date:** 2026-09-13 · **Status:** Implemented / Tested — Phase 5 Slice 7

The offline reporting adapter and direct owner-settlement repository could read retained
canonical cache without checking the current capabilities. Capability-loss purge also
missed reporting data when unit access stayed unchanged, and sign-out missed reporting-only
units without master rows. Each was demonstrated RED, then corrected at its owning layer.
Adapters receive the session principal and derive the cache-owner identity from it. D2 and
unscoped consolidated authority apply locally too; absent authority never becomes a zero
side. D-070 removes affected owner/unit reporting cache with coverage first; D-074 discovers
all reporting unit IDs. Unavailable refreshes and actor-owned pending work keep the existing
doctrine. This is not a new financial or role policy. See `SLICE7_SECURITY_AUDIT.md`.

## D-221 — Retire dead executable API surface, and control the audit itself
**Date:** 2026-09-13 · **Status:** Implemented / Tested

Live function/policy inspection and client search found no caller of
`expense_sees_whole_org()`. Migration `20260912100000` removes it without CASCADE and
restates the reviewed API at 57 functions. Live rollback rehearsal, atomic application/
ledger recording and full SQL identity were verified. Historical migrations are unchanged.
The host active-function scanner now honours drops and recreations. A synthetic granted
capability made the actual D-139 guard fail despite an older exemption and comment/DO
mentions; adding a `$fn$` evaluator made it pass. Controls were removed, never deployed.
Export, print and settings-management exemptions stay deferred, not silently implemented.

## D-222 — The development start date is an acceptance fixture, not a baseline
**Date:** 2026-09-13 · **Status:** Implemented / Tested — project-lead-authorised cleanup

No persistent fixture requires development to retain `2026-05-01`. The exact dev settings
row was removed through the administrator boundary before and after the final serial
owner/reporting run. All 101 live tests passed, including the not-configured case. Final
settings count is zero; no production date was chosen and no financial/audit history was
deleted. The SQL teardown asset lives outside migrations. Acceptance owns setup plus
administrative cleanup, including failures; do not give the client a privileged reset RPC.
The production 50:50 start date remains an unanswered business decision.

---

# Phase 5 Slice 8 — Windows P&L Surface (2026-09-13)

## D-223 — Slice numbering confirmed; "Slice 8 owns performance hardening" meant Phase 8
**Date:** 2026-09-13 · **Status:** Accepted (project-lead ruling)

Phase 5 remains: Slice 8 Windows P&L Surface, 9 Android P&L Surface, 10 Breakdown +
read-only drill-down, 11 Full acceptance, 12 Closure. The Owner Accounts addendum's
renumbered §26 plan was a non-binding proposal, superseded by OA-1…OA-3 and Slice 7.

Historical statements that "Slice 8 owns performance hardening" (`PROJECT_STATUS.md` Slice 3
and Slice 5 notes, `ARCHITECTURE.md` §29 and §31.5, D-186, and the comment in applied
migration `20260907204444`) are incorrect references to **Phase 8 — Production
Hardening**. They are clarified here and in `ARCHITECTURE.md` §37 rather than rewritten, and
the applied migration is not edited. Two items are carried to Phase 8 and were **not**
optimised in Slice 8: server expense authorization / per-row `may_read_expense` reporting
cost, and the local expense reporting index that leads with `org_id`.

## D-224 — Operating Margin is displayed to two decimal places, or N/A
**Date:** 2026-09-13 · **Status:** Implemented / Tested — settles what D-175 deferred

`OperatingMargin.displayTwoDecimals` renders `12.34%` / `-4.27%` from the exact
`MarginRatio.percentageScaled(2)`: half away from zero, symmetric for profit and loss, the
sign taken from the rounded value (so −0.004% reads `0.00%` and −0.05% keeps its sign), and
`N/A` — never `0.00%` — when Net Sales are zero. It lives beside the exact ratio in
`domain/finance` so no surface divides, formats a percentage itself, touches a `double` or
derives a margin from rounded rupees. A sabotaged sign turned five display tests red.

## D-225 — Relative presets resolve under each property's own business date
**Date:** 2026-09-13 · **Status:** Implemented / Tested (project-lead ruling)

Today, Yesterday, This Week, Last Week, This Month, Last Month and Financial Year are
resolved independently for every included property from one instant, through that
property's stored timezone and cut-off (`BusinessDayRule`, read per business unit). A single
property uses its own date. Consolidated reporting may use a preset only when every property
resolves to the identical inclusive range; otherwise the preset is disabled and refused with
a direction to Custom. No property is the master calendar; no device, UTC or database
calendar date decides it. A property whose stored rules are unreadable refuses the preset
rather than being defaulted to `Asia/Kolkata`/05:00. Custom uses explicit P&L dates.

## D-226 — A P&L scope qualifies only with the full D2 intersection
**Date:** 2026-09-13 · **Status:** Implemented / Tested (project-lead refinement)

`PnlAuthority` states once what the surface offers: a property only when the principal holds
`reports.view`, `revenue.view` and `expense.view.all` for it; consolidated only with all
three unscoped. Membership, `expense.view.own` and two scoped grants never qualify, and no
role name is evaluated. The view provider decides again against the principal before
opening the cache, so a directly selected scope is `PnlNotAuthorised` without a read; the
cache adapter and server refuse independently (Slice 7). Real-executable acceptance proved
this for a principal asserted by capability, not by role name.

Category lines use the canonical category primitives and are shown only when
`PnlResult.breakdownReconciles` confirms gross, GST, net and expenses reconcile exactly; the
totals under them are the headline figures, never a widget sum. Department, section, vendor
and transaction navigation remain Slice 10.

## D-227 — The P&L surface serialises its cache reads with its synchronisation
**Date:** 2026-09-13 · **Status:** Implemented / Tested

A report is several cache queries and a synchronisation is one transaction writing that
cache, so a sync landing between two queries could pair revenue from one snapshot with
expenses from another (D-188). Every P&L report read — including loading coverage markers —
and every P&L sync takes one `ReportingCacheLock`; the reporting source is invalidated inside
the lock so the next read loads the markers the run wrote. A no-op lock turned the
interleaving regression red.

Refresh brings retained years current, keeps already-downloaded older years current, and
never starts a download. "Download required data" fetches every missing financial year of
the range on demand through the existing `ReportingSync`; no second cache exists. A head
check before syncing marks a report "server has newer" only on a confirmed answer; an
unreachable server changes nothing, and a complete cached report stays readable offline.

**Recorded, not changed:** the OA-3 owner-settlement refresher does not take this lock, so a
settlement refresh and a P&L read on another tab could in principle interleave. Not
demonstrated, outside Slice 8's surface, and left for the slice that next touches that
refresher rather than changed in passing (D-127).

---

# Phase 5 Slice 9 — Android P&L Surface (2026-09-13)

## D-228 — The Android Reports tab opens directly to Profit & Loss
**Date:** 2026-09-13 · **Status:** Implemented / Tested (project-lead decision)

V1 has one standard reporting surface, so the phone's Reports tab opens straight to Profit &
Loss (`MobileProfitAndLossPage`) with no intermediate reports menu. Owner Settlement stays on
its own private owner surface and is not reachable from Reports. When later phases add enough
distinct reporting surfaces, the tab may become a reporting hub, under a separately approved
slice. The tab is a convenience, not a gate: the page and its providers decide P&L authority
themselves, exactly as on Windows (D-226).

## D-229 — Android Custom dates are chosen on a calendar picker only
**Date:** 2026-09-13 · **Status:** Implemented / Tested (project-lead decision) — **one
wording point raised for the project lead**

Android offers no typed date entry. Custom opens the Material date-range picker in
`DatePickerEntryMode.calendarOnly`, so there is no text field and no switch to typed input.
The tapped calendar days are the explicit P&L dates: `pnlCustomDatesFrom` reads year, month
and day only, and nothing is converted through a timezone, UTC or the device clock. A dismissed
picker leaves the selection exactly as it was. A range ending before it starts is never swapped:
it is passed on and refused by the existing resolver (`PnlInvalidRange`). The picker opens on the
custom range already chosen, otherwise on the period being reported, so opening it reads no clock
either. Windows keeps its existing typed Custom entry.

**What "native" means here, stated rather than assumed.** The picker is Flutter's Material
`showDateRangePicker`, the Android Material Design date-range picker as Flutter renders it. It is
**not** the Android OS `MaterialDatePicker` dialog reached through a platform channel: the project
has no such plugin, and adding a new dependency was outside Slice 9's approved scope. If the
decision meant the OS dialog literally, that is a separate change and needs its own approval.

## D-230 — Slice 9 is emulator acceptance; a physical-device pass remains before Phase 5 closes
**Date:** 2026-09-13 · **Status:** Accepted (project-lead decision)

Slice 9's real-app acceptance ran on the local `Pixel_8` Android emulator (`emulator-5554`,
Android 17 / API 37). It is recorded as **emulator acceptance** and is never reported as
physical-device acceptance. Phase 5 final acceptance must still include a real physical Android
device pass (the Galaxy A06 or another approved target) before Phase 5 closes. That line is in
`RELEASE_CHECKLIST.md` §O as **PENDING**.

## D-231 — A P&L on screen belongs to the person it was computed for
**Date:** 2026-09-13 · **Status:** Implemented / Tested — **a D-074-class isolation defect in
the Slice 8 provider layer, proven RED before it was fixed**

**The defect.** `pnlViewProvider` and `pnlScopeOptionsProvider` watch the session, so a new person
triggers a re-read, and a Riverpod re-read keeps the previous value while it loads. That is right
when a synchronisation lands: the report stays on screen instead of flashing to a spinner. It is
wrong when the person changes, and both surfaces rendered `view.value`. The next person's first
read queues behind `ReportingCacheLock`, so a synchronisation still running at the switch kept the
previous person's figures on screen for its whole duration.

**Proven red on the shipped Slice 8 code.** An Owner reading the consolidated P&L starts a refresh.
While it holds the lock, the session moves to a Crystal Canopy-only principal. The Windows page
went on showing the Owner's consolidated gross, ₹11,040.00, to that principal
(`test/features/pnl_session_switch_test.dart`).

**Decision.** `PnlReportView` and `PnlScopeOptions` carry `viewerUserId`. Both surfaces show a view
only through `pnlViewShownTo`, and offer scopes only through `pnlScopeOptionsShownTo`: a report or
an option set computed for somebody else is treated as not yet loaded. Views that carry no figure
are shown as they are. `PnlSyncController` also stops a run started for one person from writing its
outcome into the next person's status. A structural guard refuses a page that reads either
provider's value directly.

**Controls, each seen to fail.** With the display rule disabled, the regression turns RED on both
Windows and Android. Restored byte-identical, it is green again.

**Recorded, not changed.** `reportingSyncProvider` binds a `ReportingSync` to the owner id of the
session that built it. A synchronisation that is still running when that person signs out keeps
running with their id, so it could write that person's rows into the canonical cache after the
sign-out purge removed them. Those rows are owner-keyed and unreadable by the next person, since
the cache adapter refuses anyone without authority (D-220). This has **not been demonstrated**, and
the Slice 9 switch acceptance lets the Owner's run settle before signing out. It is recorded for
Slice 11's accumulated-state acceptance, and is not fixed inside a presentation slice (D-127).

## D-232 — One wording for both P&L surfaces, and a Slice 8 guard that could not fail
**Date:** 2026-09-13 · **Status:** Implemented / Tested

**One wording.** Android and Windows lay a P&L out differently and must not describe one
differently. Every refusal, not-downloaded, downloading, failed, unavailable-side, sync-notice and
freshness sentence now lives once in `pnl_presentation.dart`, along with range and instant
formatting and category ordering. Both pages only arrange them, with every Slice 8 key and sentence
unchanged, and the Slice 8 Windows suite passes unmodified over the rewired page. The file computes
no figure, decides no authority and derives no business date; the existing calculation and boundary
guards scan it along with the rest of the feature.

**A vacuous guard.** Slice 8's "Android keeps its Reports placeholder" test sliced the router source
from the first `_mobileRouter(`, which is the call inside `create()`, not the method. Its "mobile
router" was one line, so `isNot(contains('ProfitAndLossPage'))` could never fail. It is replaced by
an assertion anchored on the method declarations, which requires each anchor to be found before
asserting anything between them. It is proven RED by pointing Reports back at a placeholder. This is
the family D-139, D-187 and D-201 record: a guard is not a guard until it has been seen to fail.

**New guards, each with planted positive controls and a real sabotage seen RED:** no typed date
entry or date conversion on the phone page, and the picker is calendar-only; no direct read of the
view or scope-options value on either page; the scope sheet and the picker open over the root
navigator, so nothing sits behind the bottom bar or the docked [ + ]; and Android Reports is the
phone P&L while Windows keeps it under Analytics. Missed taps are fatal in the new phone widget
suite (D-075).

**One acceptance-harness defect, found on the emulator and reproduced on the host.** The first
`android-pnl` run failed while choosing a Custom range, before any P&L figure was compared. The
helper scrolled the date-range picker by "the first vertical `Scrollable` inside the dialog". That is
one month's own grid, which has `NeverScrollableScrollPhysics`, so 400 drags moved nothing and the
target day never appeared. The phone widget test had not caught it because its dates were in the
month the picker opened on. Two host tests now choose dates six months forward and eighteen months
backward. They failed in exactly the emulator's way until the helper bound to the nearest ancestor
`Scrollable` that can actually scroll, captured once as an element. The product was not involved.
The failed run's fixtures were voided by its own `finally` sweep, verified on the server as 0 open
of 3.

**A second acceptance-harness defect, found on the next emulator run.** With the picker fixed,
`android-pnl` reached the P&L, matched the server, and then timed out on "the control to exist"
when it went to refresh. The step before had scrolled the page to the bottom to prove the last line
clears the [ + ] action. The phone page is a lazy list, so the header holding the refresh control was
no longer built, and a helper that waits for a control before scrolling to it could never see it.
The helper now walks the page towards the top, then the bottom, until the control is built, and only
then centres it. The product was not involved: on a phone, refresh lives at the top, alongside
pull-to-refresh. That run's fixtures were voided by its `finally` sweep (0 open of 6 on the server).

---

# Phase 5 Slice 10 — Reporting Breakdown + Read-Only Transaction Drill-Down (2026-09-14)

## D-233 — Report detail is fetched on demand and held in memory; this reconciles D-166 with D-171
**Date:** 2026-09-14 · **Status:** Implemented / Tested (project-lead decision Q1)

**The contradiction.** D-166 said drill-down would reuse `ExpensePull.pullOne` and
`RevenueGateway.fetchComponents` for the document a manager opens. Both reuse paths persist
what they fetch:

* `pullOne` writes the document into the local `expenses` tables.
* `RevenueRepository.applyServerDocument` does the same for revenue.

That is correct on the Review-latest path, where the document is already this actor's. From
a report, it would put another actor's canonical document into this actor's attempt-state
tables, under D-070 and D-074 retention. D-171 forbids mixing those two authority classes.

**Decision.** `ReportDocumentReader` calls only the gateways' `fetch*` reads. It maps each
answer to an immutable domain value, `RevenueEntry` or `ExpenseDocumentDetail`, and the
provider holds that value in memory. It writes nothing:

* no transaction row
* no outbox item
* no reporting cache row
* no coverage marker

**Guards.**

* The reader names no database and no RPC, and calls only `fetch*`.
* Neither the reader nor the drill-down source contains `pullOne`, `expense_pull` or
  `applyServerDocument`.
* The cache document queries are `SELECT`-only, owner-keyed, and filter on `pnl_date`.

**Proven.** Live, on a device that recorded nothing, the row counts of eleven tables are
identical before and after opening a sale and a shared bill. The tables are the seven
transaction tables, the outbox, and the three reporting cache tables.

**Offline (Q3).** No full detail is shown from local transaction tables. Showing it would
need proof that the local copy is the same document version the report counted, and no
existing provenance can prove that without a schema change. No enhancement is proposed.
Offline detail says **"Detail not downloaded — connect to open this document."**

## D-234 — Document bodies are immutable values, and only the ledgers compose actions
**Date:** 2026-09-14 · **Status:** Implemented / Tested (project-lead decision Q2)

**Decision.** `RevenueDocumentBody(entry)` and `ExpenseDocumentBody(detail)` render a
document from a value. They own none of these:

* Edit, Void, Correction or Review latest
* attachment mutation
* sync state, outbox or approval
* reopen, create or delete

The ledger detail panels compose a body with their existing actions, unchanged. The P&L
drill-down composes the body alone.

**Guards.**

* A mutation scan covers every P&L presentation file and both bodies. It forbids action
  imports, action widgets and calls, write providers, action keys and database writes.
* Planted controls prove the scan works. `RevenueActions` planted in the drill-down view
  and `SyncStateChip` planted in the revenue body each turned it red.
* A widget test renders drill-down detail for a principal who holds edit, void and attach
  capabilities, and finds no action surface.

## D-235 — The drill-down hierarchy, and a document row is that document's contribution
**Date:** 2026-09-14 · **Status:** Implemented / Tested (project-lead decisions Q4, Q5, Q6)

**Paths.**

```
        Expenses   P&L → Expenses → Department → Section → Category → Documents → Detail
        Revenue    P&L → Revenue → Revenue Category → Documents → Detail
```

**Rules.**

* An expense category line on the P&L is a shortcut to the exact
  Department + Section + Category bucket.
* Revenue has no entry-kind, value-band or supply-subtype level. Components are shown
  inside the detail.
* Every level uses canonical IDs from the cache. Document rows are that bucket's
  contributions grouped by document, for the viewer, the scope and the `pnl_date` range.

**A document row is the document's contribution to the bucket, not the document's total.**
A ₹58,000 bill shared with Hotel Krishna appears under Crystal Canopy's Kirana bucket as
₹25,000. Both the row note and the detail's contribution card say so.

**Anchor.** Drill state is anchored to viewer, scope and range, and changing any of them
resets it.

**Platforms.** Windows shows a breadcrumb with detail on the right. Android pushes one page
per level, uses native back, and returns to the report when the session or selection
changes.

## D-236 — Children reconcile exactly, and a fetched document must explain its row
**Date:** 2026-09-14 · **Status:** Implemented / Tested

**Reconciliation.** Before any child row is shown, the children must equal the displayed
parent:

* amounts in integer paise, with no tolerance, and the row count must match;
* revenue proves gross, GST and net separately;
* expenses prove amount;
* there is no Other, Unallocated or rounding bucket.

On failure no child is shown, and the surface says **"Transactions not shown — amounts do
not add up exactly. Refresh."**

**Fetched document versus cached row.** A fetched document is shown only if it explains its
cached row:

* Revenue: accepted, not voided, same unit, category and business date, inside the range,
  and component sums and count equal to the row.
* Expense: its contributions filtered to the bucket and range equal the row in amount,
  count and first and last P&L date.

**Otherwise.**

* A mismatch says **"This transaction changed since the report was synchronised. Refresh
  the report to open current detail."** Refresh goes through the existing synchroniser
  under `ReportingCacheLock`. The displayed report is never altered in place.
* A document the server withholds, or does not return, says **"Not available to you."**

**What may be fetched.** Only a line contained in the currently authorised bucket, checked
with `documents.contains(line)` inside the provider. No path fetches a free-form document
id.

**Authorization.** Each property needs `reports.view`, `revenue.view` and
`expense.view.all`. Consolidated needs all three unscoped. `expense.view.own` never
qualifies, and no role name is read (D-164, D-226).

**Positive controls, each seen red and restored byte-identical:**

1. expense reconciliation forced true
2. revenue reconciliation forced true
3. the reader's cross-check removed
4. the bucket-containment check disabled
5. drill state not reset on a scope change
6. the level anchor check removed
7. the source's authority check removed
8. `RevenueActions` planted in the view
9. `SyncStateChip` planted in the body
10. `pullOne` planted in the reader

## D-237 — The Slice 8 P&L boundary guard is narrowed, deliberately
**Date:** 2026-09-14 · **Status:** Implemented / Tested (project-lead ruling)

Slice 8's guard forbade department, section and vendor detail and all navigation in the P&L
feature. Slice 10 needs exactly those, so the guard is narrowed rather than bypassed.

**Still forbidden:**

* router navigation (`context.go`, `context.push`, `GoRouter`, `AppRoutes`)
* export, print and charts
* owner settlement
* arithmetic in the UI
* any mutation
* importing a transaction page or ledger

**New:** `MaterialPageRoute` builders are limited to `MobilePnlDrillPage` and
`MobilePnlDocumentPage`.

Each rule has a planted-snippet positive control. The five Slice 8 boundary tests that
failed when drill-down was first added were rewritten to state the narrowed boundary.

## D-238 — A live authority probe asked the consolidated question by mistake
**Date:** 2026-09-14 · **Status:** Recorded; the fix is in the test

The first live run of the Slice 10 suite failed on a Crystal Canopy manager: *"the server
grants Crystal Canopy"* came back false.

**Cause.** The helper asked `reporting_primitives` about both properties in one call. A
request naming two properties is the consolidated report, and a scoped reader is refused
both (D-164, D-187). The server answered correctly; the test asked the wrong question.

**Fix.** The helper now asks one property per call.

**State checked on the catalogue.** The manager's Crystal Canopy grant is active. Their
Hotel Krishna grant was revoked on 2026-09-13 by the D-187 regression fixture. The per-unit
answers are therefore Crystal Canopy authorised and Hotel Krishna refused, which is what
the test asserts.

This is D-187's rule catching a test that forgot it. No product code changed.

## D-239 — Opening a document always fetches it again
**Date:** 2026-09-14 · **Status:** Implemented / Tested — **a defect found by the Windows
real-app phase, proven red on the host before it was fixed**

**Symptom.** In `windows-pnl-drill`, every online step passed: the sale and the shared bill
both opened read-only, and the device's row counts were unchanged. The offline step then
failed. After closing the shared bill and cutting the connection, re-opening the same row
never said "Detail not downloaded".

**Evidence, not a guess.** Two theories were checked and ruled out first:

* the wording differing from the test's expectation — the rendered sentence is the constant;
* PostgREST's automatic GET retries delaying the answer past the wait — they add about
  7 seconds, and the wait is 60 seconds of wall-clock time.

A diagnostic then printed what was on screen at the timeout. It showed:

* the already-fetched expense body, with no spinner;
* **no request attempted while offline**.

**Cause.** `pnlDocumentDetailProvider` is keyed by the request. Re-opening the identical row
while the copy fetched a moment earlier was still held reused that copy, and never asked the
server. That breaks D-233's rule that detail comes from the server on demand. Offline, it
showed a document as if it had just been opened. Online, it could show a copy that no longer
matched the server.

**Why the host tests missed it.** Host pumping finishes disposing the provider before the
next tap, so a host re-open always fetched. The two new host regressions therefore hold the
fetched copy alive across the re-open, as the real executable did. On the unfixed code both
failed the way the real run did: reads stayed at 1.

**Fix.** Every open of a document row discards any held copy first:

* Windows: `PnlDrillController.select` invalidates `pnlDocumentDetailProvider(request)`.
* Android: the drill page's `onSelect` does the same before pushing the document page.

Offline, a re-open now says "Detail not downloaded". Online, it shows the current document.

**Kept.** The on-screen diagnostic stays in the acceptance offline step, so a future timeout
there reports what the page showed instead of only that it timed out (D-075).

---

# Phase 5 Slice 11 — Full Reporting / Owner Accounts Acceptance (2026-09-15)

## D-240 — A synchronisation superseded by a session or authority change writes nothing
**Date:** 2026-09-15 · **Status:** Implemented / Tested — **closes D-231, proven RED first**

**The defect.** A reporting or owner-settlement synchronisation holds the signed-in person's id
from the moment it starts. If that person signs out, or a confirmed refresh withdraws a
capability, the purge removes the cache — and the synchronisation's answer, still on the wire,
was then written back under the old id.

**Proven red** with a real file-backed database, the real cache, synchronisers, purge and
session controller, and a server whose answer was held until released
(`test/data/stale_sync_after_transition_test.dart`). **6 of 7 cases re-applied data**:
reporting rows and coverage markers after sign-out, after the loss of each of `reports.view`,
`revenue.view` and `expense.view.all`, and the owner history after sign-out and after the loss
of `owner_settlement.view`. The network-failure control stayed green.

**Why the existing authority record could not enforce it.** `AuthorityStore` is saved and
cleared outside the purge's transaction, so a write can land after the purge commits and before
the stored authority changes.

**Decision.** A cache authority generation in `app_meta` (no schema change), advanced **inside
the purge's own transaction** on sign-out, a user switch, the fail-closed quarantine, and a
confirmed authority whose reporting or owner-settlement capabilities differ from the last one
recorded. Both synchronisers read it before asking the server and re-check it **inside the
transaction that writes**. A stale run rolls back, writes nothing, and reports
`DatasetAbandoned` / `OwnerSettlementSyncAbandoned`. Surfaces show an abandoned run as neither a
failure nor a success.

**Control.** With the in-transaction check disabled, 6 of 7 turn RED; restored byte-identical,
7 of 7 pass. Commit `405d985`.

## D-241 — The P&L and Owner Settlement share one canonical-cache boundary
**Date:** 2026-09-15 · **Status:** Implemented / Tested — **closes D-227, proven RED first**

**The defect.** Slice 8's lock lived in the P&L feature. The settlement preview reads the P&L
several separate times, and the settlement refresh writes the reporting cache; neither took
the lock.

**Proven red** against hand-worked coherent references
(`test/data/canonical_cache_coherence_test.dart`):

| Interleaving | Result | Coherent before | Coherent after |
|---|---|---|---|
| preview paused after its first P&L read, refresh committed | June 26,000.00 · cumulative 26,000.00 · per-property 23,000.00 | 6,000.00 · 26,000.00 | 23,000.00 · 23,000.00 |
| consolidated P&L read paused between properties, refresh committed | 3,000.00 | 6,000.00 | 23,000.00 |

**Decision.** `CanonicalCacheLock` in the data layer, one app-wide instance
(`canonicalCacheLockProvider`). P&L reads, drill-down reads and the P&L sync take it as before;
the settlement refresh and the settlement preview each run as one span under it, and the
refresh invalidates the reporting sources while still holding it. Owner Settlement depends on
no P&L provider.

**Control.** Private locks instead of the shared one turn both cases RED; restored
byte-identical, 3 of 3 pass. Commit `df7946f`.

## D-242 — A confirmed P&L capability loss closes the open drill-down for the same person
**Date:** 2026-09-15 · **Status:** Implemented / Tested

**The defect.** The Windows drill state and the Android drill and document pages reset when the
**user id** changed. The same person losing `reports.view`, `revenue.view`,
`expense.view.all` or unscoped authority kept them open. Proven RED: 7 of 8 in
`test/features/pnl_capability_revocation_test.dart` (the network-failure control green).

**Decision.** Both reset on `pnlReadAuthorityKey` — the user id plus the person's scoped P&L
read grants. Regressions for `owner_settlement.view` loss were added beside it: the preview
refuses, the owner cache is purged, a direct read refuses, the navigation entry disappears on
both shells, and a network failure purges nothing.

**Control.** Keying on the user id again turns the suite RED; restored byte-identical, it
passes. Commit `02639be`.

## D-243 — How Slice 11 proves a live capability loss on the development project
**Date:** 2026-09-15 · **Status:** Accepted (project-lead Decisions 2 and 4)

There is no spare development identity (`unassigned@example.com` has no profile), and a scoped
role cannot lose one capability without changing that role. Live revocation is therefore run on
`krishna-mis-dev` only by **temporarily removing one capability from the `manager` or `owner`
role** through the administrator path, while the real Windows executable waits, and restoring it
exactly — checked against the role-capability hash captured before any mutation. The phase and
the host coordinate through a handshake file (`S11_HANDSHAKE`), the pattern the Phase 2
`revoked` phase already uses. The phase observes the loss through a real authority refresh and
never asserts on a role name. Temporary grants the phase creates are revoked by the phase and
their rows removed by the host, so `user_roles` returns to its captured fingerprint.

## D-244 — The persisted session is handed back whole, so a restart restores it
**Date:** 2026-09-15 · **Status:** Implemented / Tested — **a Phase 2 defect found by Slice 11**

**Symptom.** Every Windows acceptance log began with two `supabase_flutter` warnings —
`Error while setting initial session` and `Error while recovering session`, each a
`FormatException` at character 1 — followed by the first 75 characters of a JWT header.

**Cause, confirmed in the package source rather than assumed.** `supabase_flutter` 2.17.2 passes
whatever `LocalStorage.accessToken()` returns straight to `auth.setInitialSession(...)` and
`auth.recoverSession(...)`, both of which parse the **persisted session JSON**; its own shipped
storage returns the stored string unchanged. `SecureSessionStorage.accessToken()` decoded that
string and returned only its `access_token` field. Recovery could never parse it, so no session
was ever restored and every launch fell back to the sign-in screen.

**Why nothing noticed.** It failed closed — nobody saw anybody else's data — and the `restart`
phase the acceptance header has listed since Phase 2 ("no sign-in at all — the session must come
back on its own") **never existed**: git history holds no commit that ever added it. A documented
check that nothing implemented, the family D-071 and D-077 record.

**Proven RED twice.** The host contract test (`test/data/session_storage_contract_test.dart`)
failed 2 of 3. In the real Windows executable, `slice11-restart-a` signed in and exited without
signing out, and `slice11-restart-b` then timed out waiting for the session to come back.

**Decision.** `accessToken()` returns the stored session string unchanged. The key, the platform
secure store (Android Keystore, Windows DPAPI — D-022, D-036) and sign-out removal are unchanged.

**GREEN.** The contract test passes 3 of 3. On Windows, `slice11-restart-b` restores the same
person's session with no sign-in, reads the cached report offline, and refreshes on reconnect,
with no session-recovery warning in the log.

**Control.** The shipped adapter from `HEAD` turns the contract test RED (2 of 3); the fix,
restored byte-identical, passes 3 of 3. Commit `1eb6a25`.

**Exposure, measured rather than assumed.** The logged fragment was a JWT **header** only —
algorithm and key id, truncated at 75 characters, no payload and no signature — and it was
written to local acceptance logs outside the repository, never committed. With the fix the
warning, and so the fragment, no longer appears.

**On Android** the emulator reinstalls the application on every launch, so restart persistence
there is a manual physical-device check (§Q.2 items 6 and 7) rather than an automated phase.

## D-245 — A same-person session refresh keeps the reader's choices
**Date:** 2026-09-15 · **Status:** Implemented / Tested — **a Slice 8/OA-3 defect found by the Slice 11 revocation phase, proven RED on the host before it was fixed**

**Symptom.** In the real Windows executable, `slice11-revocation` refreshed authority for the
same person with nothing changed, first offline and then online. Each refresh reset the P&L
back to This Month on the default property and closed the open drill-down.

**Cause.** `PnlSelectionController`, `SettlementMonthController` and both sync controllers
watched the **whole** `sessionProvider`. A stale or unchanged authority refresh emits a new
session state for the same person, and a Riverpod `build` that watches it runs again. That
discarded the chosen property, period and month, and let a running refresh's status fall back
to idle.

**Decision.**
* The P&L selection and drill-down are keyed on `PnlAuthority.readKey`: the person plus exactly
  the P&L read grants they hold. They reset when the person changes, and when a P&L capability
  is gained or lost (D-226, D-231). A session refresh with nothing changed leaves them alone.
* The settlement month is keyed on the person. A lost capability already makes the preview
  refuse (D-213), so the month does not need to reset for it.
* Both sync controllers are keyed on the person, so a session refresh cannot drop a run that
  is still going (D-074 unchanged: a new person, a new status).

**RED first.** The P&L case (`pnl_capability_revocation_test.dart`, "the same person, the same
authority, a new session state") failed 2 of 2. It compares `(scope, period)`, because
`PnlSelection` has no `==` and an identity comparison would have been an invalid RED. The
settlement case (`owner_settlement_ui_test.dart`) failed 2 of 2: the month went back from
2026-05 to 2026-06.

**GREEN.** Both pass. The P&L, drill-down, session-switch, revocation and settlement suites pass
together, 206 tests.

**Control.** With the settlement month watching the whole session again, the regression turns
RED, 2 of 2. The fix, restored byte-identical (`cmp`), passes.

## D-246 — On Windows the session lives in its own protected file, apart from the database key
**Date:** 2026-09-16 · **Status:** Implemented / Tested (project-lead decision: "split the
stores") — **a Phase 1 storage hazard found by the Slice 11 revocation phase, proven RED
first**

**Symptom.** `slice11-revocation` run 4 failed before it started:
`EncryptedDatabaseUnreadable … (sqlite 26)`. Run 3's log held the cause:
`Failed to decrypt data … Failure on CryptUnprotectData() … Delete corrupt file:
…flutter_secure_storage.dat`.

**Cause, read from the locked plugin source.** `flutter_secure_storage_windows` **3.1.2**
(the version in `pubspec.lock`; earlier notes that said 4.2.2 were wrong):

* keeps every key in one DPAPI blob;
* rewrites the whole blob on every change, with a non-atomic write;
* does not serialise readers against writers;
* **deletes the whole blob** when a read cannot decrypt it, then rethrows.

The session is rewritten on every sign-in and token refresh. The database key
(`krishna_mis.db_key.v1`) is written once per installation. They shared the blob. One
failed session read deleted the key, a new key was generated, and the existing encrypted
database could no longer be opened (D-022, D-036).

**Proven RED on the host.** With a fake plugin that behaves the same way (clears
everything and throws on a failed read), a failed session read changed the database key
(`test/data/session_key_isolation_test.dart`).

**Decision.**

* **Windows:** the session lives in its own file, `krishna_mis.session.dpapi`, in the
  application support folder. `ProtectedFileSessionStore`:
  * protects it with DPAPI, current user, no entropy — the same protection the plugin
    gives its blob, no weaker and no stronger (D-036);
  * writes through a temporary file and renames it over the old one;
  * runs reads and writes one at a time within the process;
  * **never deletes the file because a read failed.** An unreadable session counts as no
    session; the person signs in again and the next write replaces it.
* **The database key stays in the plugin store**, unchanged.
* **Android is unchanged:** the session stays in the Keystore-backed plugin store (D-022).
* **Upgrade:** a session left in the plugin store by an earlier build is moved once, and
  only while the new file has never existed. An unreadable new file is never a reason to
  read the old store, because that read is the one that deletes the key.
* `sessionSecretStoreFor(os)` is a plain function of the platform name, so a host test
  asserts both production branches (D-077).

**The acceptance run gets its own data folder.** `bootstrap` gains
`Directory? appDataDirectory`, the same kind of parameter as D-058's transport. Only the
acceptance harness passes it, on Windows only
(`%TEMP%\krishna_mis_acceptance`). With a folder given, the session is never moved out of
the plugin store. `main()` passes nothing, and a guard asserts `lib/main.dart` does not
name it.

**Why the acceptance could reach the project lead's store at all.** Processes started from
the Claude desktop app run inside its MSIX package, whose file writes to Roaming are
redirected to
`…\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming`. Acceptance runs therefore wrote an
overlay copy, while reads could still see the real Roaming folder. The real
`%APPDATA%\Krishna Imperial\Krishna Imperial MIS\krishna_mis.db` (196,608 bytes,
31 Aug) was not touched. Whether a real `flutter_secure_storage.dat` exists beside it
could not be checked from this session and is **with the project lead to check**. The
broken overlay database and store were moved aside, not deleted, into
`s11-evidence-20260915`.

**Tests.** 9 host tests: both platform branches; a failed session read leaves the key and
the file; the next sign-in replaces an unreadable session with no temporary file left;
sign-out removes the session only; an acceptance folder never takes the shared-store
session; the one-time move; the unreadable-new-file case never reads the old store; a
failing old store is no session; and a real DPAPI round trip on this host (not plaintext
on disk, a damaged file kept, delete works).

**Control.** With the Windows branch pointed back at the plugin store, 4 tests turn RED.
Restored byte-identical (`cmp`), all pass.

**Dependencies.** `win32` and `ffi` become direct dependencies at the versions already
locked (5.15.0, 2.2.0). The lockfile changed only their classification.

## D-247 — The real Windows installation has a database and no key store
**Date:** 2026-09-16 · **Status:** Recorded — forensic evidence only; answers the question
D-246 left with the project lead

**What was checked, and by whom.** The project lead inspected
`%APPDATA%\Krishna Imperial\Krishna Imperial MIS\` on the real Windows account, outside
any packaged process. It holds `krishna_mis.db`. **It holds no `flutter_secure_storage.dat`.**
Nothing was renamed, moved, deleted or modified.

**What that means.** On Windows the database key lives in that file (D-036, D-246). With
the file absent, that installation's database cannot currently be opened by the app. On its
next launch the app would find no key, and would not be able to read the existing file.

**What it does not establish.** Why the file is missing. Three explanations fit the evidence,
and none is proven:

* it was never written at that location;
* the plugin deleted it after a failed read (the D-246 hazard);
* a process removed it before D-246 kept acceptance runs out of the shared store.

The record does not choose between them.

**Rules that follow.**

* `krishna_mis.db` on the real installation is **not** deleted, modified, opened or
  "recovered" by any step of this project. Recovering it is not a goal.
* It is **not** an acceptance fixture. Acceptance uses its own data folder on Windows
  (D-246), independent of whether that database can ever be read again.
* D-246's isolation is judged on its own tests, never on the state of that folder.
* It held development data from the Phase 3 clean-build check (31 Aug). No production
  financial data exists anywhere yet, so nothing of the business is lost.

## D-248 — A pull-to-refresh that did not refresh, once, on a real phone
**Date:** 2026-09-17 · **Status:** Recorded — **not explained, and not called flaky**

The first physical-device run of `android-pnl` on the Galaxy A06 reached the P&L, rendered
the category rows, and then timed out in `pullToRefreshPnl` after ninety seconds:
*"timed out waiting for: pull-to-refresh to run the synchronisation"*. The same phase had
passed on the emulator throughout Slices 9 and 10.

**Why it could not simply be re-run.** D-075 is explicit, and this failure is the shape that
rule exists for. `PnlSyncController._run` returns **without touching its status** when the
selection resolves to nothing to fetch, and the helper waits for that status to change — so
from outside the test, *"the gesture never arrived"*, *"the run returned early"* and *"an
awaited provider never completed"* are one symptom. Re-running and reporting the green would
have buried whichever of the three it was.

**What was ruled out first, from the evidence in the log rather than by theory.** The custom
range had been applied: `choosePhoneCustom` asserts `pnlSelectionProvider.period` equals the
tapped days and it passed. The gesture landed inside the right scrollable: the printed
finders at the drag point are the phone P&L's own list. And the run before it had failed for
a different and fully explained reason — the phone had no SIM and its Wi-Fi had dropped with
the screen off, so every request failed DNS (`errno = 7`) and nothing reached the backend.

**What was built instead of a guess.** The helper now reports, on timeout: the sync phase and
whether it is running, whether the status is still the identical object, the selected period,
and whether the scope-options, business-day-rules and view providers hold a value, an error or
are still loading — and then tries the **header refresh control**. That last step is the
discriminator: if the header refreshes, the gesture is what did not arrive; if it does not,
the run itself cannot resolve anything to fetch. It is the D-239 pattern, where the offline
drill-down step prints what was on screen rather than only that it timed out.

**And then it did not happen again.** Six physical-device phases ran with the diagnostic
armed — `android-pnl`, `-scope`, `-switch`, `-drill`, `android-owner-settlement`,
`slice11-shared-device`, `slice11-lifecycle` — and it printed nothing in any of them.

**So the record says the honest thing: one timeout, cause unknown.** The diagnostic stays in
the harness rather than being removed once the suite went green, because the next occurrence
is the one that can be explained, and a diagnostic deleted for tidiness is one nobody has
when it matters. If it recurs, its first line answers the question this entry could not.

## D-249 — An acceptance run holds its own database key, selected by the boundary that already exists
**Date:** 2026-09-17 · **Status:** Accepted (project-lead ruling) — **proven RED first**

**What D-246 left open, found by the Slice 12 audit.** D-246 gave the acceptance suite its own
data folder, so a run opens its own database file and its own session file. The **key** stayed
shared: `DatabaseKeyManager` read, wrote and deleted one entry — `krishna_mis.db_key.v1` — in
the plugin store belonging to the person using the machine. An acceptance run could therefore
create that entry, read it, and delete it through "erase local data". Measured on this
machine before the change, the store held exactly one entry, `krishna_mis.db_key.v1`, written
by earlier acceptance runs.

The project lead ruled: isolate it, keep the plugin, make the identifier injectable through
the existing acceptance boundary, change no schema, and do not move the key into the session
file.

**The identifier is selected by the data folder, not passed as a string.**

```
        databaseKeyNameFor(appDataDirectory: null)   -> krishna_mis.db_key.v1
        databaseKeyNameFor(appDataDirectory: dir)    -> krishna_mis.acceptance.db_key.v1
```

`main()` passes no folder, so a shipped binary has no reachable path to the acceptance entry;
a run given a folder has none to the production entry. Both invariants are structural rather
than remembered, which is the distinction this project keeps paying for (D-068, D-077).
`DatabaseKeyManager` gained a `keyName` field so a test can inject either, and every read,
write and delete names it — so one installation's cleanup cannot reach another's key.

**Android is untouched**, as the ruling requires: the harness passes a folder on Windows only
(`Platform.isWindows`), so an Android acceptance run keeps the production identifier and the
Keystore-backed store (D-022). No schema, no migration, no financial semantics.

**RED first, then GREEN, then a control.** Ten tests written against the intended API failed
to compile against the shipped code — the identifier, the selector and the field did not
exist. After the change, 10 of 10 pass. The control points the selector at the production
identifier: **2 of 10 turn red** — the acceptance-selection test and *"an acceptance run can
never land on the production identifier"* — and the file was restored with a byte copy and
`cmp` (D-219).

**And it is proven on the real machine, not only in Dart.** The secure store was read before
and after two real Windows acceptance process launches, printing **key names only** and a
hash of the production value rather than the value:

```
        before   entries: krishna_mis.db_key.v1
                 production value SHA-256(16): 40687EF4DB29C7A1

        after    entries: krishna_mis.db_key.v1, krishna_mis.acceptance.db_key.v1
                 production value SHA-256(16): 40687EF4DB29C7A1   <- untouched
                 acceptance value: 64 hex characters, different
```

`slice11-restart-a` created the acceptance database under the acceptance key and
`slice11-restart-b`, a second process launch, **reopened it** — which is the "an acceptance
restart reopens its own database using its own key" invariant, proven end to end rather than
argued.

**One operational consequence, stated because it will recur.** The acceptance database that
existed before this change was encrypted with the production key, so it is unreadable under
the new identifier. It was deleted before the first run — it is disposable by design, which is
the whole point of the separate folder — and the run recreated it. A future key change to that
folder has the same consequence and the same remedy.

**A property worth keeping, found by inspecting the build.** The Windows **release** payload
contains `krishna_mis.db_key.v1` and **not** `krishna_mis.acceptance.db_key.v1`: with `main()`
the only caller and no folder in its hand, the acceptance branch is compiled out of the
shipped binary altogether. The Android **debug** payload contains both strings, because a
debug kernel is not tree-shaken — and the acceptance identifier stays unreachable there for
the reason above, not because the string is absent. Both are stated rather than one being
quietly presented as the general rule.

## D-250 — The Android date-range picker is Flutter's Material picker, and that is what was meant
**Date:** 2026-09-17 · **Status:** Accepted (project-lead clarification) — closes the question
D-229 raised

D-229 recorded that Android's Custom range uses Flutter's Material `showDateRangePicker` in
calendar-only mode, and flagged that *"native picker"* might have meant the Android OS dialog
reached through a platform channel — a different thing, needing a new dependency and its own
approval.

**The project lead has clarified: the Flutter Material date-range picker is approved for
Android V1.** The term meant a mobile calendar interaction rather than typed desktop date
entry, and did not require an OS/platform-channel picker.

**No rework, no new dependency, no behaviour change.** What ships is what was approved:
calendar-only, no typed entry, the tapped days read as year, month and day with no timezone,
UTC or clock conversion, and a reversed range refused rather than swapped. The D-229 wording
point is closed.

---

# Phase 6 — Dashboard & Analytics (2026-09-17)

Phase 6 was scoped by an audit of the shipped code, and the project lead ruled on the eight
questions it raised. D-251 … D-260 record those rulings as given; D-256 is a rule this
implementation had to add and is flagged for confirmation; D-261 records the approved plan.

**The principle every entry below serves:** Phase 6 creates no second financial calculation
model. Every dashboard figure is a field of a `PnlResult` the Phase 5 engines produced, or a
comparison of two of them computed once in `domain/finance`.

## D-251 — A dashboard compares period to date with the same stretch last time
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 1) — implemented in Slice 2

```
  Today so far            today                 vs  the previous business date
  Week to date            Monday .. today       vs  last Monday .. same weekday
  Month to date           1st .. today          vs  last month's 1st .. same ordinal day,
                                                    capped at that month's end
  Financial year to date  1 April .. today      vs  last 1 April .. same date a year earlier
  Custom                  from .. to (n days)   vs  the n P&L dates immediately before
```

Never the current partial period against the whole previous one. Every range is a P&L date
range derived from a business date; no UTC instant or transaction timestamp is read.

**Calendar edges, stated because they are the part that is easy to get wrong:**

* **A shorter previous month caps the comparator.** 31 March compares with 1–28 February, and
  the pair carries `comparisonCapped` and both day counts so the surface can say so.
* **29 February has no counterpart**, so Financial year to date on 29 February 2028 compares
  with 1 April 2026 – 28 February 2027, capped.
* **A leap day inside a stretch is not a cap.** On 1 March 2028 the current stretch holds
  29 February and is 336 days against 335; on 1 March 2029 the comparator holds it and is the
  longer side. The equivalent date existed both times, so nothing is capped — the day counts
  say it.

`DashboardPeriods` in `lib/domain/finance/dashboard_periods.dart`. Every day of 2026–2029 is
swept by a test.

## D-252 — On the dashboard, an in-progress period ends today; the P&L screen is unchanged
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 2, and the labels rule)

On the dashboard and in Phase 6 analytics, *Financial Year* means **financial year to date**,
and an in-progress week, month or financial year ends at the property's current business
date. A future-dated accrual appears when its P&L date enters the period, and not before.

**The Phase 5 P&L screen keeps its approved semantics** — This Month is the whole calendar
month and Financial Year the whole year (D-225). The two are separate types:
`DashboardPeriodKind` beside `RelativePreset`, and nothing in the P&L path was edited.

**Labels never make an unfinished period look finished:** *Today so far*, *Week to date*,
*Month to date*, *Financial year to date*.

## D-253 — Comparison display rules
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 3) — implemented in Slice 2

* **Either side unavailable** — not authorised, not downloaded, one side of the P&L missing, or
  anything else — **no numerical comparison at all.** Nothing is substituted with zero. The
  refusal behind each side is carried.
* **Previous figure zero:** percentage N/A; the rupee change is still shown.
* **Operating Profit with a negative side:** no percentage. A sign change reads *Moved from loss
  to profit* or *Moved from profit to loss*, beside the exact rupee movement. Break-even is
  neither a profit nor a loss, so a move to or from zero is not a sign change.
* **Operating Margin moves in percentage points**, exactly: 12.30% → 14.10% is **+1.80 pp**,
  never "14.63% growth".

All of it lives once in `lib/domain/finance/pnl_comparison.dart`, as exact rationals over
paise, rounded once, half away from zero. The margin movement multiplies two paise figures,
which passes 2^63 at crore scale, so it is computed in `BigInt`.

**One consequence of "exact", recorded so it is not rediscovered as a defect.** The movement is
taken from the two exact margins, not from their rounded displays. For 1/3 against 1/6 it is
**+16.67 pp**, while the two displayed margins, 33.33% and 16.67%, differ by 16.66. A surface
showing both margins beside the movement can therefore show a 0.01 pp visible gap. This is the
ruling applied literally; if the project lead prefers the movement to match the two printed
margins, that is a one-line change and a new decision.

## D-254 — A consolidated comparison needs both sides to agree across properties
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 4) — implemented in Slice 2

D-225 is applied **independently to both sides.** Every included property must resolve to the
identical current range **and** the identical comparison range; otherwise the consolidated
comparison is refused (`currentRangesDiffer` / `comparisonRangesDiffer`) and the reader is
sent to Custom. No property is the master calendar, and a property whose business-day rules are
unknown refuses rather than being defaulted.

For every relative kind the comparator is a function of the current range's end, so agreeing
current ranges imply agreeing comparators. The comparison check runs regardless, and is proven
with an injected pairing that breaks the implication, so a future rule cannot rely on it
silently.

## D-255 — Trend grain, and what a day may be ranked on
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 5) — one point left open

* **Daily and weekly trend points carry Net Sales only.** Accrual placement makes a single day's
  expenses and profit misleading.
* **Expenses and Operating Profit are trended monthly**, and a financial year to date is
  trended monthly.
* **Best and worst day rank daily Net Sales only**, never profit. A tie is reported in full,
  never broken; one unavailable day refuses the whole ranking.

The permission is a property of the grain and is checked when trend buckets are built, so a
chart cannot ask for a daily profit series by accident. A clipped first or last week or month is
marked `partial`.

Grains offered per period: Today — none; Week to date — daily; Month to date — daily and
weekly; Financial year to date — monthly.

**Open: the grain for a Custom range.** A custom range can be three days or three years, and no
rule was given, so `DashboardTrends.grainsFor(custom)` offers none. This is raised for the
project lead rather than chosen.

## D-256 — An ordinary figure with a negative previous value gets no percentage
**Date:** 2026-09-17 · **Status:** **Implemented, pending project-lead confirmation**

D-253 rules on a negative side for Operating Profit only. Net Sales, Expenses, Gross Sales and
GST are normally non-negative, but a correction can in principle leave a period negative, and a
percentage of a negative base reads backwards (−₹100 → +₹100 would print "−200%"). The
comparison therefore gives **N/A (`previousNegative`)** for an ordinary figure whose previous
value is negative, keeping the rupee change. This is the conservative reading of the profit rule,
added so the software did not have to guess, and it is flagged rather than presented as a
ruling.

## D-257 — Charts use `fl_chart`, behind an internal presentation layer
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 6) — dependency added in Slice 5

`fl_chart` is the one chart package. Before it is added (Slice 5): verify compatibility with
Flutter 3.44.9 / Dart 3.12.x on Android and Windows, pin the exact version, and record it here.
It sits behind a small internal chart layer that receives **already-computed presentation
values**. Chart code computes no P&L, GST, money total, category total, comparison percentage,
margin, percentage-point movement, reconciliation, authority or period range, and a structural
guard will assert it. No other chart package.

## D-258 — Top N + Others is presentation grouping over a set that already reconciles
**Date:** 2026-09-17 · **Status:** Accepted (project-lead rule) — implemented in Slice 2

The complete category set must add up exactly to its headline figure — expenses to Expenses,
revenue categories to Net Sales — **before** anything is grouped. If it does not, no Top-N chart
is drawn (`doesNotReconcile`). **Others is the exact sum of every line not in the top**, and it
can hide nothing missing, unreconciled or unauthorised, because such a set is refused first.

Ranking is by amount, largest first; equal amounts are ordered by the line's full identity so
the chart never changes between two readings of the same data. Categories of different
properties stay separate lines — nothing decides that two categories are "the same". Revenue mix
ranks by Net Sales.

`TopN` in `lib/domain/finance/dashboard_analytics.dart`.

## D-259 — People without P&L authority see a neutral landing surface
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 7) — Slices 4, 6, 7

Overview (Windows) and Home (Android) remain for everyone. A principal without the P&L
authority `PnlAuthority` defines (D-164, D-226) sees **no** financial figure, chart or
comparison, and no property name inferred from a default or another person's scope. They may
see permitted navigation, existing non-financial quick actions their capabilities allow, and
neutral account and session information. Where nothing useful remains: *"Management analytics
are not available for your access."* No separate operational dashboard is built in Phase 6.

## D-260 — Android gets the management dashboard; Windows owns the analytics workspace
**Date:** 2026-09-17 · **Status:** Accepted (project-lead decision 8)

**Android Home:** scope, period, freshness, Net Sales, Expenses, Operating Profit or Loss,
Operating Margin, comparison indicators, the Net Sales trend, top expense categories, property
comparison when consolidated authority exists, and *See full P&L* to Reports.

**Windows Analytics:** Profit & Loss, Revenue Analysis, Expense & Department Analysis, Business
Comparison. Not reproduced on Android in Phase 6.

Both platforms use the same domain rules, providers and wording.

## D-261 — The Phase 6 plan, and the performance gate
**Date:** 2026-09-17 · **Status:** Accepted (project-lead approval)

Eleven slices: (1) governance, (2) exact comparison domain rules, (3) dashboard engine and
measurement, (4) authority and providers, (5) chart foundation, (6) Windows Overview,
(7) Android Home, (8) Windows Analytics sections, (9) drill-down integration, (10) full
acceptance, (11) closure.

**Performance gate, before Slice 3 closes:** trend series built from ordinary repeated reports
are measured on representative financial-year-sized data. If fast enough, the architecture is
kept. If not, **stop and report** — no server analytics RPC, materialised aggregate, index or
second analytics cache is added without a separate decision.

**Out of Phase 6:** Owner Settlement analytics, finalized owner statements, export, PDF,
printing, vendor analysis, value-band analysis, forecasting, targets, AI analysis, editing from
dashboards, new server-side dashboard functions, and performance hardening not shown to be
necessary. The production 50:50 start date is still outstanding and does not block Phase 6.

## D-256 (closed) — An ordinary figure shows a percentage only against a positive base
**Date:** 2026-09-20 · **Status:** **Accepted (project-lead ruling)** — the final form of the
rule Slice 2 implemented and flagged. The earlier entry stands as written, because this log is
append-only.

Slice 2 recorded D-256 as *implemented, pending confirmation*: it suppressed the percentage for
an ordinary figure whose **previous** value was negative, on the conservative reading of the
Operating Profit rule, and said plainly that the ruling had covered profit only. The project
lead has now settled it, and the settled rule is wider than the one that was guessed.

**For Gross Sales, GST, Net Sales and Operating Expenses**, a percentage change is shown only
when:

```
        previous > 0   AND   current >= 0
```

| | |
|---|---|
| `previous == 0` | percentage **N/A**; the exact rupee movement is still shown |
| `previous < 0` | no percentage |
| `current < 0` | no percentage — **this is the half Slice 2 did not have** |

Whenever either side is negative the exact rupee movement is shown, a surface may word the
direction, and no conventional growth percentage appears. −₹100 improving to +₹100 would
otherwise print "−200%" for an improvement, and a current figure crossing below zero produces a
percentage that is arithmetically defined and reads as nonsense.

**Operating Profit is unchanged** and keeps its stricter rules (D-253): a loss on either side
gives no percentage, and a sign change is stated in words. It is the one figure whose negatives
are ordinary.

**How it is enforced.** One `PercentNotApplicableReason` per condition, tested in the order
above, so a comparison whose two sides are both negative names the **base** — the condition a
reader can act on. `currentNegative` joins `previousZero` and `previousNegative`. The rupee
movement is on `MoneyComparisonAvailable.change` and is never gated on any of them, and
`eitherSideNegative` is derived here so a surface's wording cannot be written against a
different test from the one that suppressed the percentage.

**Control, seen to fail:** with the current-negative branch removed, two comparison tests turn
RED. Restored by byte copy and `cmp` (D-219).

## D-263 — A custom range's trend grain comes from its own span, and a missing bucket is a gap
**Date:** 2026-09-20 · **Status:** Accepted (project-lead ruling) — closes the point D-255 left
open

D-255 set the trend grain for every relative period and deliberately left Custom open, because
a custom range can be three days or three years and choosing a rule would have been deciding
one. The project lead has decided it.

**Net Sales, by inclusive P&L-date span:**

```
        1 … 31 days      daily
        32 … 180 days    weekly
        181+ days        monthly
```

**Expenses and Operating Profit stay monthly only**, at every span — D-255's reason is
unchanged, and a longer custom range does not make a daily cost point any less distorted by
accrual placement.

**Where a monthly cost trend is too short, nothing is shown.** The threshold is that a trend
needs **more than one bucket**: one point shows no direction and no movement, so drawing it as
a trend would be the chart making a claim its data cannot support. A range lying inside one
calendar month — including a whole calendar month on its own — therefore offers no Expenses or
Operating Profit trend at all, while its Net Sales trend is unaffected. Partial first and last
buckets **count** toward the two: they are real figures for real, shorter periods, and
requiring a complete month instead would be inventing a completeness rule nobody has set. If a
stricter meaningfulness rule is ever wanted, it is one line and a new decision.

**Buckets.** Weeks are Monday–Sunday (D-165) and months are calendar months. A custom range
routinely clips its first and last bucket; each is marked `partial` and is **never
extrapolated** to a notional whole week or month. The buckets tile the range exactly — no gap,
no overlap, and their day counts sum to the range's.

**A bucket with no figure is a gap, and that is now a type rather than a rule to remember.**
`TrendSeries` is built from buckets and their outcomes: a computed bucket becomes a
`TrendValue` carrying the measure read from its own field, and a **refused** bucket becomes a
`TrendGap` carrying the refusal. There is no path by which a missing bucket becomes zero,
because there is no arm that constructs one — the same move D-176 made for an unavailable side
of the P&L, and the same reason: a flat segment drawn across missing data is indistinguishable
from a real trading lull and the reader has no way to tell. A **real** zero stays a
`TrendValue` and stays distinct from a gap.

Filing a P&L under a bucket that is not its own range, supplying a different number of outcomes
from buckets, or mixing two scopes each throws. Plotting a real figure in the wrong place is
the failure mode worth refusing outright.

**Choosing a grain never moves the period.** Buckets are derived from a range that is already
fixed, so neither the selected custom period nor its comparator is touched by which grain a
chart happens to plot. Asserted rather than argued, because it is the kind of coupling that
would be introduced by a convenience later.

**Controls, each seen to fail and each restored byte-identical:** the daily threshold moved
from 31 to 30 (1 RED); the too-short guard removed so a one-bucket cost trend is offered
anyway (1 RED); a refused bucket turned into a zero `TrendValue` (2 RED).

## D-264 — A displayed margin movement reconciles with the two displayed margins
**Date:** 2026-09-20 · **Status:** Accepted (project-lead ruling) — closes the point D-253
raised

Slice 2 recorded a consequence of "exact" and flagged it: the margin movement is taken from the
two **exact** ratios, so 1/3 against 1/6 moves +16.67 pp while the two *printed* margins,
33.33% and 16.67%, differ by 16.66. A surface showing all three leaves a visible 0.01 pp a
reader cannot account for.

**The ruling.** The exact rational margins and the exact movement stay canonical in
`domain/finance`. **What is displayed** at the configured precision is:

```
        displayed movement  =  displayed current  −  displayed previous
```

so the three figures on screen add up. `MarginMovement.pointsScaled` remains the exact figure
and is not replaced; `displayedPointsScaled` is the displayed one, and it is what
`displayTwoDecimals` prints, because that string is the one that sits beside the two printed
margins. `exactDisplayTwoDecimals` formats the canonical figure for a diagnostic or an export
that states the unrounded movement.

**This is presentation reconciliation only.** Nothing downstream computes from the rounded
value, and no canonical figure is replaced by one.

**Proven, not asserted.** A sweep of **60,500** margin pairs — including negative net sales,
negative profit, halfway cases and 32-bit-crossing figures — at precisions 0 to 4 asserts
`displayed == round(current) − round(previous)` exactly, with no exception. A second test reads
the actual strings a surface prints, parses them back and adds them up. A third bounds the two
answers against each other: each of the three roundings moves its figure by at most half a
unit, so displayed and exact can never differ by more than **one** unit at the display
precision — stated as a bound because a wider gap would mean one of the roundings is not what
it claims to be.

**Control, seen to fail:** with `displayTwoDecimals` pointed back at the exact movement, two
tests turn RED, including the string-level one. Restored by byte copy and `cmp`.

## D-265 — One plan, one span, one claim: how a dashboard reads
**Date:** 2026-09-20 · **Status:** Accepted — Phase 6 Slice 3

A dashboard is not one report. It is the P&L of the period so far, the same P&L for the
stretch it is compared with, one report per trend bucket, and — where a best and worst day
is asked for — one report per day of the period. The engine's whole substance is how those
reads are planned, held together and described, because every figure they produce is
already decided by `domain/finance`.

**It derives nothing.** No comparison arithmetic, no bucket boundaries, no ranking, no
grouping: `PnlComparison.compare`, `DashboardTrends.buckets`, `DashboardTrends.series`,
`DailyNetSalesRanking.rank` and `TopN` are called, never reproduced. The directory guard
already forbids money arithmetic here; a dedicated guard adds the complement — the
delegation must be **present**, and constructing any of thirteen domain result types is
refused. A guard that only forbids would pass just as happily over a file that did nothing
at all, which is D-139's defect in reverse.

**Every distinct range is read once.** A month-to-date dashboard wants a daily Net Sales
trend *and* a best and worst day, and both are the same thirty days of single-day reports.
The plan is therefore a **set** of ranges and the view is assembled from one map of
results. Reading them twice would double the cost of the busiest dashboard there is for no
second answer — measured at 37 reads rather than 67.

**A refused headline refuses the view, and stops reading.** Every bucket lies inside the
current period and is read under the same authority, so a period that cannot be
established would refuse thirty more times at thirty times the cost. That is also the
D-163 reading: a trend drawn under a refused headline is the half-report a dashboard must
not show. The **comparator is still read**, so a refused current period beside an
available previous one is still described honestly rather than blanked.

**One lock span, therefore one moment.** The whole view runs inside a single
`CanonicalCacheLock` span (D-241). A dashboard is an order of magnitude more reads than a
P&L screen and is correspondingly more exposed to a synchronisation landing in the middle
of it — and a trend whose first half is one snapshot and whose second half is another
reconciles perfectly and is a picture of no moment that existed (D-188). Proven
behaviourally: a synchronisation queued on the same lock after the view's first read does
not commit until the view is finished, and the trend is entirely the state before it.

**One freshness claim, or none.** The view claims a snapshot only when **every** read
carried snapshot evidence and all of it was the same evidence. Deliberately not the
headline's evidence alone: a trend bucket in an older financial year may have been
certified by a different run, and a badge taken from the headline would date the chart
beside it to a moment that chart does not belong to. A part that could not be established
has no evidence and therefore withholds the claim for the whole view — *synchronised as of
T* printed above a chart with a hole in it claims a completeness the view does not have.
The figures are canonical either way. Coverage is combined the same way: the weakest of
each side across every read, not the headline's.

**Controls, each seen to fail and each restored byte-identical (`cmp`):** the range set
degraded to a list (2 RED); the reads moved out of the lock span (1 RED — and the count
guard passed, which is recorded in the guard itself rather than glossed); the
refused-headline short-circuit removed (1 RED); the freshness badge taken from the
headline alone (1 RED); a read placed before the span opens (1 RED).

## D-266 — The Phase 6 performance gate: the existing foundation is sufficient
**Date:** 2026-09-20 · **Status:** Accepted — the gate D-261 required, discharged

D-261 set the gate: measure representative financial-year dashboard workloads on the
existing Phase 5 reporting foundation, and **stop and report** rather than change the
architecture if the measurement is unsuitable. It named five things not to add without a
separate decision — a dashboard RPC, a second reporting cache, a materialised aggregate, a
new index, a new server reporting function.

**None was added.** The measurement does not support adding one.

### What was measured

Two financial years of trade for two properties — **4,380 revenue contributions and 2,920
expense contributions**, a 2.5 MB database — written into the real canonical reporting
cache, read through the real `MarkerCoverage`, `CachedReportingSource`,
`LocalReportingEngine`, `Pnl.compute` and `DashboardEngine` under the real
`CanonicalCacheLock`. Seven workloads, every one a dashboard the rulings actually permit,
all consolidated across both properties, which is the heavier scope.

The on-device runs use the **real SQLCipher-encrypted database** in the application's own
storage directory, and assert it is genuinely encrypted before measuring — a measurement
against a plaintext file would be a measurement of something the product does not do.

### Windows, real encrypted database, two samples

| Workload | reports | points | cold | warm |
|---|---|---|---|---|
| financial year to date, whole year, monthly ×3, top 5 | 14 | 36 | 119 / 134 ms | 86 / 95 ms |
| financial year to date, mid-year, monthly ×3, top 5 | 8 | 18 | 49 / 49 ms | 45 / 42 ms |
| **month to date, daily + weekly, ranked, top 5** | **37** | **35** | **170 / 181 ms** | **168 / 151 ms** |
| week to date, daily, ranked | 6 | 4 | 32 / 30 ms | 25 / 31 ms |
| custom 365 days, monthly ×3 | 14 | 36 | 74 / 71 ms | 74 / 71 ms |
| custom 180 days, weekly | 28 | 26 | 120 / 123 ms | 122 / 125 ms |
| custom 31 days, daily, ranked | 33 | 31 | 153 / 157 ms | 146 / 155 ms |
| headline + comparator alone | 2 | — | 10 / 8 ms | — |

### Android emulator, real encrypted database, three samples

`sdk gphone16k x86_64`, Android 17 / API 37, **debug** build.

| Workload | run 1 cold | run 2 cold | run 3 cold | warm (runs 2–3) |
|---|---|---|---|---|
| financial year to date, whole year | 319 ms | 60 ms | 67 ms | 23–24 ms |
| financial year to date, mid-year | 53 ms | 13 ms | 14 ms | 10–12 ms |
| **month to date, daily + weekly, ranked** | **685 ms** | **41 ms** | **38 ms** | **31–41 ms** |
| week to date, daily, ranked | 88 ms | 6 ms | 5 ms | 5 ms |
| custom 365 days, monthly ×3 | 69 ms | 18 ms | 19 ms | 19–21 ms |
| custom 180 days, weekly | 29 ms | 28 ms | 29 ms | 25 ms |
| custom 31 days, daily, ranked | 215 ms | 24 ms | 27 ms | 24 ms |

**Run 1 is discarded as warm-up, and the evidence for that is in run 1 itself rather than
in an assertion about it:** a 28-report workload cost 29 ms cold while a 14-report one
cost 319 ms, and the heaviest cost 685 ms cold against 31 ms warm in the same run. Cost
that does not follow the work is not the work. Runs 2 and 3 were taken on a settled
emulator and agree closely with each other.

### What the numbers say

**The worst measured steady-state dashboard is 168 ms, on Windows, for 37 reports.** The
escalation trigger this project set in `ARCHITECTURE.md` §9 is 400 ms for a one-month P&L
on the reference Android device; the heaviest dashboard on either platform is inside it,
and the Android figures are several times better than the Windows ones.

**Cost is linear in reports and the per-report cost is the Phase 5 engine's**, which is
what makes the figures predictable rather than a black box: two reports cost 8–10 ms on
Windows, and 37 cost 151–181. Nothing about a dashboard is superlinear, because nothing
about it is a new query shape — it is *n* of the P&L query already measured in Phase 5
Slice 5.

**The rulings bound the work themselves.** D-263's span thresholds are why a year-long
custom range is 14 reports rather than 367: a 365-day Net Sales trend is monthly, not
daily. D-255 is why a financial year to date is 12 buckets shared by three series rather
than three sets. The grain rules turn out to be the performance design.

### Remote and download cost

**Not applicable to the dashboard engine**, and that is a statement rather than an
omission: it issues no remote call. It reads the canonical cache, and the download that
fills that cache is the unchanged Phase 5 `ReportingSync`, whose live cost against
`krishna-mis-dev` is already recorded (Slice 5: one month 39 ms server-side and 98–185 ms
end to end to Mumbai; a consolidated financial year 368–398 ms). Slice 3 adds no server
function, no RPC and no new request.

What Slice 3 *did* measure of that path is the **local half of a first full
synchronisation** — applying 7,300 contributions across two financial years in one
transaction: **527–2,718 ms on Windows, 824–6,711 ms on the emulator**, both with wide
spread. That is a one-off cost on a fresh installation, not a per-dashboard cost, it is
Phase 5 machinery, and it is recorded here because it is the largest single number in the
whole measurement and somebody will otherwise find it and wonder.

### One thing deliberately not optimised

Each report currently reads **four** aggregates per property — revenue totals, expense
totals, revenue by category and expenses by category — and a trend bucket needs only the
first two. Suppressing the breakdown on bucket reads would roughly halve the query count
of the heaviest dashboard. It is not done, because the gate's instruction was to change
nothing the measurement does not require, and at 168 ms the measurement does not require
it. It is recorded here so that the option is known rather than rediscovered, and so that
a future measurement on slower hardware has somewhere obvious to start.

### The limits of this evidence, stated

The Android figures are from the **emulator**, not from the project lead's Galaxy A06
(D-230), and from a **debug** build, which is slower than a release build for Dart code
and identical for SQLite. A physical-device dashboard pass belongs with the Phase 6
acceptance slice, exactly as D-230 placed the P&L one. The fixture is two properties and
two financial years, which is the local retention ceiling (D-170); a device does not hold
more than that without asking for it.

## D-267 — The dashboard's authority is the P&L's, and authority identity is part of dashboard identity
**Date:** 2026-09-21 · **Status:** Accepted — Phase 6 Slice 4, written test-first

Slice 4 connects the Slice 3 engine to the session. It builds no chart and no screen, and
— the point of the slice — it introduces **no second financial authorization model**.

**The scopes are not merely decided the same way; they are the same provider.** A dashboard
reads `pnlScopeOptionsProvider`, so it cannot offer a property the P&L would refuse, and a
later change to what qualifies cannot move one surface and leave the other behind. The rule
is [D-164 as corrected by D-187] unchanged: `reports.view` ∩ `revenue.view` ∩
`expense.view.all` for a property, all three **unscoped** for consolidated. A structural
guard asserts the provider names no `Capability.` at all, so it has no way to decide the
question for itself, and no role name appears anywhere in the feature.

Four ways a property might have been offered and is not: because another person selected it
(the options carry a viewer and the selection is keyed on the authority), because it is in
the cache (the units come from the master graph and are filtered by the rule), because a
role implies it (no role is read), or because some **other** capability names it — a
principal holding `masters.view` on Crystal Canopy plus every Owner Accounts capability is
offered nothing, which is tested.

### Authority identity, not merely the person

Every `DashboardState` carries the [PnlAuthority.readKey] of the authority it was assembled
under, and `dashboardShownTo` refuses to show it to any other. The comparison is the **key**
rather than the user id, and that is the whole of the difference from the P&L's own guard:
the same person whose qualifying capabilities have moved is a different authority, and their
previous dashboard must stop being visible at once rather than when the next read happens to
finish.

That matters because a provider re-reading **keeps its previous value while it loads** —
right when a synchronisation lands, and wrong the moment authority changes. D-231 recorded
exactly this defect on the P&L, where a consolidated report stayed on screen for a
Crystal-Canopy-only principal for as long as a synchronisation held the lock. The key is
captured **before** anything is read, so an assembly that spans a change is stamped with the
authority that started it and can never become the visible dashboard.

The selection is keyed the same way: a different person, or the same person whose qualifying
capabilities have changed, starts from a clean selection; a session state change that leaves
the authority identical keeps the reader's chosen property and period (D-245). A selected
property whose authority is withdrawn therefore resolves to a still-permitted scope, or —
when there is none — to an explicit refusal. It never keeps showing the revoked property.

**The sync controller is keyed on the authority too**, which is a deliberate divergence from
`PnlSyncController`'s person key: a status describing a scope this authority cannot read is
not this authority's status, and keying on the person would leave a capability change with a
run stuck at *synchronising* and the next run refusing to start behind it. The data layer is
the real guarantee either way — D-240's cache authority generation abandons a run whose
reporting capabilities have moved — and this is the surface saying the same thing.

### Five states, and not one of them is a zero

| | |
|---|---|
| loading | including the moment after an authority change, when the previous dashboard is deliberately not visible |
| available | a complete dashboard, **and separately** whether the last refresh failed |
| not authorised | no qualifying scope, or a scope this authority may not read |
| period unavailable | the properties disagree about a range (D-254), a calendar could not be read (D-225), or a custom range ends before it starts |
| required data unavailable | the engine could not stand behind the figures |

`dashboardPresentation` is a pure function of those, so a surface cannot arrive at a
different answer from the one that is tested. **Where a complete dashboard exists and a
refresh fails, the dashboard is retained and the failure is reported beside it** — a failed
run writes nothing (D-048), so the figures are still the last complete canonical snapshot.
Where none exists, the answer is unavailable, never fabricated figures (D-163).

### What is delegated, and asserted to be

Periods are the Slice 2 planner's (`DashboardPeriods.forUnits` / `forCustom`), with both the
current range and the comparator required to agree across the properties in scope (D-254);
the guard forbids every shape of date arithmetic in the provider. Which series a period may
carry is `DashboardTrends.grainsFor`'s answer (D-255, D-263), so the provider cannot ask for
a trend the rulings do not permit. Figures come from **one** `DashboardEngine.build`; the
guard forbids a second reporting path and forbids the provider reassembling any part of the
view itself. Freshness is the engine's combined claim passed through — when the engine can
name no one snapshot the provider names none either, and constructing a claim here is
forbidden.

### Written test-first, and the controls that make it mean something

The test file was written and run before the providers existed, and failed to compile
against the API it describes. Three deliberate breaks were then made and each was seen RED
before being restored byte-identical (`cmp`):

| Control | Result |
|---|---|
| authority identity reduced to the person alone | **3 RED** — capability revocation, in-flight isolation, and the guard |
| `expense.view.own` made to qualify, in `PnlAuthority` itself | **1 RED** — which is also the proof that the dashboard genuinely depends on that rule rather than restating it |
| stale publication allowed after a switch or revocation | **4 RED** — user switch, capability revocation, in-flight isolation, and the guard |

### Recorded, and deliberately not changed

`PnlSyncController` keys its status on the **person**, so a capability change mid-run is not
detected at the surface. It is not a defect: `ReportingSync` abandons the run under D-240,
the controller reports it as neither success nor failure, and the P&L re-reads under the new
authority. It is noted because the dashboard's key is stricter and the difference should be
read as deliberate rather than as drift, and because if the P&L surface is ever touched
again the same key is the simpler thing to have (D-127).

## D-268 — A chart states a figure it was given, never one it read off a position
**Date:** 2026-09-21 · **Status:** Implemented / Tested — Phase 6 Slice 5

Charts are presentation. The rule that makes that true rather than intended is about the
**direction** of one conversion:

```
        exact Money  ──derive──▶  double coordinate      allowed, one way
        double coordinate  ──▶  Money                    does not exist in the layer
```

`ChartAmount` carries the exact figure **and** the string the application's own formatter
produced from it; the plotted coordinate is a getter over the figure, and there is no
constructor taking a `double`. So a tooltip, an axis tick and a readout are not numbers a
renderer handed back — they are the figure `domain/finance` computed, printed the way every
other surface prints it. This is the move D-094 made for `RevenueTaxFacts` and D-150 for the
revenue attachment schema: make the mistake unavailable rather than discouraged.

**A tooltip is a lookup.** fl_chart reports *which* mark was touched, so the exact figure is
found by index in the points the domain supplied. Exactly one place in the layer converts a
coordinate to anything, and it converts to a **category index** that carries no money —
`ChartSelection.indexAt`, named so a reviewer sees it rather than finding it. A guard asserts
that it is the only one.

**What the layer may not do**, each asserted over the directory rather than per file: reach a
report, a database or a server; decide authority, coverage or freshness; resolve tax; call
`Pnl.compute`, `PnlComparison.compare`, `DashboardTrends.*`, `DailyNetSalesRanking`, `TopN.*`
or `Money.sum`; sort anything; or derive or format a date. A position's name arrives as a
label from the surface that owns the application's date wording, so the layer cannot grow a
second date format.

**A gap is a gap, and a zero is a zero.** A `TrendGap` becomes a `ChartAbsent` carrying **no
amount at all**: the line breaks at `FlSpot.nullSpot`, and the bar chart draws **no rod**. A
break-even month draws a rod *at* zero. A zero-height rod is exactly what break-even looks
like, so a month nobody could establish must not render as one (D-263).

**The value axis is anchored at zero.** A truncated axis exaggerates variation, and this is a
management report rather than a pitch (spec §20). It is also what gives an Operating Profit
chart a baseline to draw a loss beneath. The baseline is an **explicit reference line**, not
whichever grid line happens to land there — a generated grid does not promise to include zero
at all, which is a real finding rather than a precaution: the first implementation coloured a
grid line at zero, and once the tick step was chosen so that axis labels resolve, zero stopped
being generated for a range whose minimum is not a multiple of the step.

**Never colour alone** (spec §20): a series carries a marker shape and a dash pattern beside
its colour and is named in the legend; profit and loss are stated by the side of the baseline,
by the sign on the figure, by the word in the readout and by the word in the description.
Break-even is its own word, because it is neither.

**A refused domain result draws no financial data.** A `TopNRefused` — a category set that did
not reconcile — and a trend of nothing but gaps both render a stated reason in place of a
plot, never an empty plot area, which a reader cannot tell apart from a flat zero (D-163).

**One interaction model for both platforms.** fl_chart reports a Windows hover and an Android
touch through the same callback, and arrow keys move the same selection, so there is no second
interaction model to keep in step — the discipline D-232 settled for the P&L wording. Animation
is off: a financial chart gains nothing from motion, and a running animation makes an assertion
read a figure that is on its way somewhere (D-152).

**Controls, each seen RED and restored byte-identical (`cmp`):** a `TrendGap` converted to a
zero point; a tooltip built by formatting the plotted `double`; the ranked adapter re-ranking
and re-summing the domain's lines; and `ChartAmount` reduced to its coordinate.

## D-269 — fl_chart 1.2.0, pinned, and what was verified before it was added
**Date:** 2026-09-21 · **Status:** Accepted — the dependency decision D-257 required

**Verified before adding**, against this repository's toolchain (Flutter 3.44.9, Dart 3.12.2)
rather than from the package's description:

| Required behaviour | Mechanism, read in the package source |
|---|---|
| a gap that breaks a line | `FlSpot.nullSpot`, and the renderer breaks at it |
| bars above and below zero | `BarChartRodData(fromY:, toY:)`, with a negative `toY` |
| a tooltip that states an exact figure | `GetBarTooltipItem` gives `groupIndex`; `TouchLineBarSpot` gives `spotIndex` — **both hand back an index**, which is what lets a tooltip read the prepared figure rather than the coordinate |
| accessibility | fl_chart publishes none, so the layer wraps every chart in one `Semantics` node carrying the whole description |

fl_chart 1.2.0 itself requires Flutter >= 3.27.4 and Dart >= 3.6.2. It brings `equatable`
transitively and nothing else. **No STOP condition was reached**: every approved behaviour is
representable, including horizontal bars (`rotationQuarterTurns`).

**Pinned exactly — `fl_chart: 1.2.0`, not a caret.** A chart package's rendering is what
several assertions read, so an unreviewed minor bump is a silent change to what a manager
sees. A guard asserts the pin, the lockfile, the recorded toolchain, that no second charting
package exists in `pubspec.yaml` or `pubspec.lock`, and that **nothing outside the chart layer
imports `package:fl_chart`** — so replacing the package is never a change to a screen.

**One implementation choice inside an approved family, stated rather than buried.** The three
ranked horizontal families — revenue mix, top expense categories, department spending — are
composed from the design system's own text and a proportional fill rather than plotted on a
rotated axis. A ranked bar chart is a **list with a bar**, and two requirements decide it: a
category reads *Crystal Canopy Rooftop · Kirana & Pulses*, which as an axis tick at 360dp
either truncates the name or takes a third of the plot from the bars; and **money must never
be truncated or wrapped**, because a truncated amount is a wrong amount (the rule `MoneyText`
has carried since Phase 1). So the name sits on its own line above the figure at phone width,
and in its own slot beside it at desktop width, and a test asserts the two never share a line
at 360dp.

This is **not** a second charting library and not a rejection of the package — fl_chart draws
the other three families and could draw these. It is the right primitive for a ranked list,
it lives in the same layer under the same models, formatters, selection and description, and
it is reversible in one file. **Flagged for the project lead** rather than presented as
settled.

## D-269 (final) — The three ranked families keep their composed implementation
**Date:** 2026-09-22 · **Status:** **Accepted (project-lead ruling)** — resolves the point
Slice 5 flagged. The earlier entry stands as written, because this log is append-only.

Slice 5 built revenue mix, top expense categories and department spending from the design
system's own text and a proportional fill rather than on a rotated `fl_chart` axis, and
flagged the choice for confirmation rather than presenting it as settled.

**The ruling: keep it. These three are not to be replaced with rotated `fl_chart` axes in
V1.**

They are **ranked financial lists with proportional magnitude**, and the presentation
ranks, in this order:

```
        the complete category or department name
        the exact INR value
        the rank
        the proportional magnitude
        accessibility
```

above maintaining a conventional chart axis. **A long hospitality category name is not
truncated to create axis space, and money is never truncated** — a truncated amount is a
wrong amount, which is the rule `MoneyText` has carried since Phase 1.

The proportional fill stays **presentation-only** and consumes already-prepared values: it
ranks nothing, sums nothing and reconciles nothing, because `TopN` did all three before the
adapter saw the lines (D-258, D-268).

**Reversible in the presentation layer, and it alters no semantics.** The domain results,
the dashboard engine, the ranking, the grouping and the figures are untouched by it; the
three families sit in the same chart layer under the same models, formatters, selection and
description as the cartesian ones. `fl_chart` remains the one chart package (D-257) and
draws the other three families.


---

# Phase 6 Slice 6 — Windows Overview Dashboard (2026-09-22)

## D-270 — A per-property figure is a domain split, not a widget sum
**Date:** 2026-09-22 · **Status:** Accepted

The approved Overview shows Net Sales, Expenses and Operating Profit **per property**
beside each other, and nothing in the Slice 2–5 foundation produced them: a consolidated
[PnlResult] carries its category lines but no per-property totals.

Two ways to get them, and only one is this project's:

* **group in the widget** — the surface sums `revenueByCategory` and `expenseByHierarchy`
  by business unit. Rejected. That is arithmetic over money in the thing that draws it,
  and it would be a second answer to *what did Crystal Canopy earn* (D-020, spec §21.1);
* **group in `domain/finance`** — which is where every other exact grouping in this
  product already lives, one level down, as `PnlDrilldown.departments`.

**Decision: `PropertyComparison.of(result)` in `lib/domain/finance/`.**

**Each property's figures come from `Pnl.compute`.** The per-property primitives are handed
to the one canonical calculator rather than having `netSales − expenses` and the exact
margin ratio written out a second time — the duplication D-119 and D-131 each record, found
after it had already drifted.

**It refuses rather than showing a split it cannot stand behind**, on three conditions:
a report covering one property has nothing to compare and is not drawn as a chart of one
bar; a breakdown that does not reconcile exactly is refused, because a property missing a
line would simply appear smaller than it is (D-236's rule applied to the dimension a reader
is least able to check); and the grouped parts are checked to add **back** to the headline
on every primitive, so the grouping is proven rather than assumed. The order is
business-unit id, never figure order, and no property is labelled a winner.

**The engine carries it, and the department ranking, at no cost.** `DashboardView` gains
`propertyComparison` and `departmentSpending`; both are pure functions of the headline
result the engine already holds, so **neither adds a read** and the D-266 performance gate
is untouched. Putting them there rather than in the page is what keeps the Slice 4 rule —
*there is one dashboard path, through the engine* — true of the surface as well as of the
providers.

## D-271 — One place turns a reporting date into words
**Date:** 2026-09-22 · **Status:** Accepted

Money has had one such place since Phase 1. Dates did not: `pnl_presentation.dart` held a
private month table, and the dashboard needed the same wording plus a compact form for a
chart position. A second table would have been a second answer to *what is this day
called*, which is the drift D-232 settled for the P&L wording.

`lib/core/formatting/report_dates.dart` now holds it. `pnlDateLabel`, `pnlRangeLabel` and
`pnlInstantLabel` keep their names and delegate, so every Phase 5 call site and assertion is
untouched and the P&L's wording is byte-identical. The dashboard uses the same helper, plus
`reportDayLabel`, `reportMonthLabel` and `reportShortRangeLabel` for a bucket's name.

**And `MoneyFormatter` gains one variant.** A period-over-period movement needs an explicit
`+`, and an unsigned rise reads as a total. `MoneySignStyle.explicit` gives `+₹1,200.00`,
`-₹1,200.00` and — because a zero movement has no direction — `₹0.00`. It is added to the
one place money becomes text rather than by a surface prefixing a character to a formatted
string.

## D-272 — Two guards narrowed for Slice 6, and two defects found in doing it
**Date:** 2026-09-22 · **Status:** Accepted

Slice 4's guard asserted the dashboard feature builds **no screen**. Slice 5's asserted the
chart layer is **wired into no screen**, and said in as many words that it was the
assertion Slice 6 would have to change. Both are narrowed rather than bypassed, which is
the move D-237 made when Slice 10 needed the breakdowns the Slice 8 P&L guard forbade.

| | Now |
|---|---|
| the providers | still no widget, no chart, no `Widget build(` |
| the surface | may draw; may not calculate, navigate, mutate, export, print, name an Owner Accounts value, or reach storage |
| the charts | may be drawn **only** from `lib/features/dashboard/`, and a complement asserts the dashboard actually draws them — so the rule cannot be satisfied by there being no charts at all (D-139) |

**Two defects in the guard itself, both found by running it.**

*A token that matched a local variable.* `customSelect` matched `customSelected`, the
period bar's own flag, and reported the page as reaching a database. It is
`customSelect(` now — the false positive D-069 records, in a new file.

*A phrase assertion that the formatter broke.* `dart format` reflowed
`if (view.propertyComparison case final PropertyComparisonReady split)` across two lines
and the guard went red for a line break. Phrase assertions are matched against source with
runs of whitespace collapsed, which is D-153's finding — an invariant phrased as a sentence
the source must contain has to survive the source being re-wrapped.

## D-273 — What rendering the Overview found, and what it could not reach
**Date:** 2026-09-22 · **Status:** Recorded

**A layout defect at a real Windows size.** Four headline metrics across a 1366-wide window
leave a column about 245 logical pixels wide, and *Gross ₹13,23,420.00 · GST ₹6,302.00* is
85 pixels too long for it. Money is never ellipsised, so the pair is a `Wrap` and flows onto
a second line. Found by rendering at 1366×768, not by review — the D-123 family, met again
at a width nobody had rendered at.

**One of my own assertions was vacuous, and a control found it.** The Overview's
authority-switch test asserted that no dashboard body is on screen after the authority
changes. With the display guard deliberately removed it **stayed green**: at that moment
the provider holds no previous value at all, so the test was measuring Riverpod's reload
rather than the rule. It now exercises the rule directly — the Owner's assembled dashboard
offered to the next authority must not be shown — and goes red under the control. The
fourth or fifth time this project has found a check by expecting red and getting green
(D-071, D-074, D-094, D-139, D-180, D-232).

**A trend gap is not reachable end to end today, and that is stated rather than staged.**
Reporting coverage is recorded per financial year, so every bucket inside a period shares
its coverage with the headline: a year that is not downloaded refuses the headline too, and
there is no arrangement in which one bucket of a computed report is missing. The gap
behaviour is therefore proven through `dashboardTrendChartData` — the one adapter the
surface itself uses — from a series carrying a refused bucket, and it is proven again in the
chart layer's own suite. If a later slice makes coverage finer than a financial year, a
gap becomes reachable and the acceptance for it belongs there.

---

# Phase 6 Slice 7 — Android Home Dashboard (2026-09-23)

## D-274 — The phone's Home is the same dashboard, arranged for a thumb
**Date:** 2026-09-23 · **Status:** Accepted

D-260 gives Android the management dashboard and keeps the analytics workspace on
Windows. Slice 7 builds it, and the whole of the design is what it **reuses**.

**It is a second arrangement, not a second dashboard.** `MobileHomePage` reads the same
Slice 4 providers, the same `PnlAuthority`, the same `DashboardEngine`, the same
`CanonicalCacheLock` span, the same coverage and the same freshness claim as the
Overview. It computes no figure, decides no authority, derives no date and resolves no
tax; the Slice 6 surface guard — now run over both surfaces (D-275) — asserts all of
that over the file rather than over a reviewer's attention.

**Every sentence is the shared one.** Wording, range and instant formatting and category
ordering live in `dashboard_presentation.dart`, which both surfaces arrange and neither
writes. Slice 7 found one sentence that had escaped it — *Both properties
(consolidated)*, written as a literal in the Overview's chip and twice more on the phone
— and moved it to `dashboardConsolidatedScopeLabel`. Three copies of one sentence is the
drift D-119 and D-131 each record, caught before it drifted rather than after.

**Content, and what is deliberately absent.** Scope, period, freshness; Net Sales with
Gross Sales and GST secondary to it, Operating Expenses, Operating Profit or Loss and
Operating Margin, each with its comparison; the Net Sales trend; property comparison when
the reader holds consolidated authority; top expense categories; and *See full P&L*.
**Revenue mix, department spending and the monthly profit trend are not on the phone**
(D-260) — the engine still carries them, and the surface does not show them, which a test
asserts from both sides.

**The one navigation is named, never numbered.** *See full P&L* switches the shell to
`AppRouter.mobileReportsBranch`, a constant declared beside the branch list it indexes.
It is **not** drill-down: opening a figure's transactions from a dashboard is Slice 9's,
and nothing here duplicates the P&L's own breakdown.

**The phone's own controls, and the rules they inherit.** The property is chosen in a
bottom sheet and the period in a horizontal chip strip, both presented on the **root**
navigator so no choice sits behind the bottom bar or the docked [ + ]; a consolidated
period the properties disagree about is offered disabled and refused (D-254); Custom is
the Material calendar with typed entry off (D-229, D-250), and dismissing it changes
nothing. A reader without qualifying authority sees the approved neutral line, **no
property name, no scope selector and no period strip** (D-259), and the page carries no
`MoneyText` at all.

## D-275 — A rule about a surface runs over every surface
**Date:** 2026-09-23 · **Status:** Accepted — **a gap in the Slice 6 guard, closed before
the second surface was written**

Slice 6's `dashboard_surface_guard_test.dart` bound most of its rules to a single `page`
variable holding `overview_page.dart`. That was correct while the feature had one screen
and silently wrong the moment it had two: every calculation, mutation, Owner Accounts,
export, clock, trend-gap and ranked-family rule would have stopped short of
`mobile_home_page.dart`, and nothing would have said so.

**Decision.** The guard holds `_surfaces = [_overview, _home]` and iterates it. A rule
about a dashboard screen is written once and evaluated on both, so the next surface is
covered by construction rather than by somebody remembering to add it — the same move
D-162 made when it replaced an enumerated privilege list with a question about the
catalogue.

Two rules are deliberately **per surface**, because the two screens differ: the Overview
draws four chart families and the phone three, and the phone shows `topExpenseCategories`
while neither `topRevenueCategories` nor `departmentSpending` may appear on it (D-260).

**And navigation is now narrowed rather than forbidden.** Slice 6 asserted the feature
contains no `goBranch(`. The phone has exactly one, so the rule became: the Overview has
none, the phone has **exactly one**, and it names `AppRouter.mobileReportsBranch`. A
further guard parses `app_router.dart`, slices the mobile router from its own declaration
to the desktop one, extracts the branch order and asserts the declared constant is the
index Reports actually occupies — so the two cannot drift into a button that opens the
wrong tab.

**One mechanical finding, recorded because it is the third of its shape.** The phrase
assertions collapse whitespace runs to one space (D-153), which is not enough for a
phrase `dart format` may wrap **inside** a call: the wrap introduces a space that was
never written. `_dense` strips whitespace entirely for those. A guard that fails on a line
break is a guard somebody eventually deletes.

## D-276 — What rendering the phone found
**Date:** 2026-09-23 · **Status:** Recorded

**A real layout defect, at a size and a font scale nobody had rendered at.** At 360dp with
the system font scale at 1.6, the Gross Sales / GST pair under Net Sales overflowed its
card by **56 pixels**. `_Secondary` was already a `Wrap` and its comment already said the
pair *"flows onto a second line instead"* of money being ellipsised — but each pair was a
`Row` inside that `Wrap`, and a `Row` cannot flow. `RenderWrap` gives its children a
**bounded** main-axis constraint, so a pair wider than the card overflowed rather than
wrapping.

The pair is now a `Wrap` of its own, so the label goes on one line and the figure on the
next, whole. **The figure is the half that may never be shortened** (D-269), so the layout
gives way rather than the money. This is the D-123 and D-273 family a third time, and the
lesson is the same each time: a layout is correct at the sizes something has actually
rendered at, and nowhere else.

**A smoke assertion that outlived what it described.** `routing_smoke_test.dart` proved
Home was still underneath the quick-add sheet by finding the text *"Phase 6 — Dashboard &
Analytics"* — the **placeholder's** caption. With the real dashboard on that branch the
caption is gone, so the test failed for the right reason and the assertion now names the
page. A test that identifies a screen by a caption is a test that breaks when the screen
becomes real.

**Five positive controls, each seen RED and restored byte-identically** (`cp` then `cmp`,
D-219): the secondary pair back to a `Row` (the raised-font-scale test); *See full P&L*
pointed at branch 0 (the navigation test **and** the guard); the freshness line replaced
by a fixed sentence (the server-newer test); a movement worded by the page instead of by
`dashboardMoneyMovement` (the comparison test); and `departmentSpending` rendered on the
phone (the D-260 guard).

---

# Phase 6 Slice 8 — Windows Analytics Sections (2026-09-23)

## D-277 — The Analytics workspace: the P&L embedded, three sections over one prepared view
**Date:** 2026-09-23 · **Status:** Accepted — **one point flagged for the project lead**

Spec §19 puts four sections under Analytics: Profit & Loss, Revenue Analysis, Expense &
Department Analysis and Business Comparison. The desktop Analytics branch is now
`AnalyticsPage`, which puts them behind one segmented selector — the pattern Transactions
already uses for Expenses and Sales (D-120).

**The Profit & Loss is not rebuilt.** It is `ProfitAndLossPage`, embedded exactly once and
unchanged, with its own presets, selection, drill-down and synchronisation. A guard asserts it
appears once, that no analytics file names the P&L's calculator or state, and that the router's
Analytics branch is the workspace rather than the bare page.

**Two period models, stated in the navigation state.** `AnalyticsSection.periodModel` is
`pnlPresets` for the P&L — whole months and whole financial years (D-225) — and
`dashboardToDate` for the three analysis sections (D-251, D-252). The workspace says so in a
caption above its controls, so the two calendars are never confused and neither is quietly
changed to match the other.

**The three analysis sections share the dashboard's selection and its one prepared view.** They
read `dashboardViewProvider`, go through `dashboardPresentation` once, and are handed the ready
view; moving between them reads nothing again, which a test asserts by object identity and by the
transport's request count. Authority is Slice 4's, unchanged: the state is stamped with the
authority that assembled it (D-267), so a different person, or the same person with a moved
capability, never sees the previous analysis.

**Flagged:** sharing the dashboard's selection means the Overview and the three analysis sections
move together — choosing *Financial year to date* in Revenue Analysis also sets the Overview to
it. That is what "no second read of a result that is still valid" costs, and it treats the
dashboard period as one choice across the Phase 6 surfaces. If the project lead would rather the
workspace keep its own period, that is a provider family and a second synchronisation target, and
a decision.

**Two further mechanics.** The section choice is keyed on the authority, so a new authority opens
on the Profit & Loss rather than wherever the previous one left off; and the analysis workspace is
built the first time an analysis section is opened, so a reader who only looks at the P&L starts no
dashboard synchronisation. Both halves stay mounted in an `IndexedStack` after that, so a P&L the
reader was drilling into is still there when they come back.

**Drill-down stays Slice 9's.** What Slice 8 fixes is what a row *means*: `AnalyticsDrillIntent`
values built from the prepared lines in the domain's order, with the exact Others remainder mapping
to none. Nothing navigates, no detail screen is invented, and no drill-down query is duplicated.

## D-278 — What each analysis section shows, and what it deliberately does not
**Date:** 2026-09-23 · **Status:** Accepted — **two omissions flagged for the project lead**

**Revenue Analysis.** A ruled summary — Gross Sales, less GST, Net Sales, each against the
comparable stretch — the Net Sales trend at the planner's grain (D-255, D-263), and the revenue mix
by category as D-269's composed ranked rows. The three sums are the canonical result's own, so
Gross = GST + Net by construction; GST is never derived from Gross on screen. Where the planner
offers no trend (Today so far), the section says why instead of drawing an empty plot.

**Expense & Department Analysis.** Operating Expenses against the comparable stretch, the
**monthly** expense trend where the period offers one, the top expense categories (Top 5 + Others)
and department spending. A daily or weekly expense series is never requested — accrual dating makes
it describe when a bill was dated rather than what was spent — and where a period has fewer than two
months the section states that there is one monthly point and no trend.

**Business Comparison.** A ruled table — Net Sales, Operating Expenses, Operating Profit / Loss and
Operating Margin — for each property and for both together, every cell a field of the per-property
`PnlResult` `PropertyComparison` computed through `Pnl.compute` (D-270). Properties are in the
domain's id order and a note says so; every figure is in neutral ink, and an operating result
carries the word *Profit*, *Loss* or *Break-even* beside it (spec §20). The grouped chart is
secondary: the exact figures are visible in the table without hovering anything. It is shown only
for a consolidated scope. A reader without consolidated authority gets an explicit unavailable
state that names no property; a reader who has chosen one property is offered *Compare both
properties*.

**Not built, and why — flagged rather than decided.**

* **No percentage share.** No prepared share exists, and a share computed and rounded per line
  would not add up to 100.00% on screen — the problem D-264 settled for margins, met again. The
  ranked rows state each category's exact contribution and show its proportion as geometry. A share
  figure is a new domain rule and a decision.
* **No per-category period comparison.** `PnlComparison` compares headline figures; nothing
  compares one category with itself across two periods. Building it is new domain arithmetic, not
  presentation.

Out of scope, as the brief directed: value-band, supply-subtype, vendor, occupancy, forecast,
target and budget analysis. A guard asserts no section names them.

## D-279 — One set of Windows building blocks, and one set of guard rules
**Date:** 2026-09-23 · **Status:** Accepted

The Overview's scope bar, period bar, refresh control, headline metrics, panels, grid and state
messages were private to `overview_page.dart`. The Analytics workspace needs the same controls over
the same providers, so they moved into `dashboard_widgets.dart` rather than being copied — the drift
D-119, D-131 and D-232 each record. Every key is the one Slice 6 shipped, and the Overview's widget
suite passes unchanged over the moved code.

**One dashboard guard rule narrowed, deliberately.** Slice 6 asserted that the Overview file itself
reads `pnlScopeOptionsShownTo(`. The scope bar now lives in the shared file, so the rule is: the
shared file reads the options, the Overview uses the shared bar and reads no options itself, and the
Android Home still reads its own. The calculation and navigation rules are extended to the shared
file. D-237's move — narrowed, not bypassed.

**The guard token lists are shared too.** The dashboard guard's lists — calculation, navigation,
mutation, Owner Accounts, export, storage — moved into `test/support/surface_guard_tokens.dart`, and
the new analytics guard enforces those same lists rather than a copy that could drift.

**And the chart-layer guard is narrowed a second time.** Slice 6 permitted charts only under
`lib/features/dashboard/`. The three analytics section files — and only those, not the workspace
page or its state — are now permitted too, and the complement asserts each of them really draws
one. Planting a chart import in the workspace page turns the rule red.

## D-280 — A fixture that described a row the database cannot hold
**Date:** 2026-09-23 · **Status:** Recorded

The Overview suite books a *Water* cost to a *kitchen* department — but Water lives under the
ordinary section, not the kitchen. The server's composite hierarchy keys make that row impossible
(D-040), so the reporting cache can never receive it. The Overview never noticed, because it keys
nothing on the hierarchy. The Analytics workspace mounts the Phase 5 P&L beside it, and the P&L keys
its category rows on the guarantee D-040 provides: the impossible row gave two rows one key, and
Flutter reported *Duplicate keys found*.

The product is right and the fixture was wrong. The analytics suite gives the kitchen its own
section and four categories that really live under it. The Overview suite is left as it is: it is
harmless there, and changing an accepted slice's fixture to satisfy a different slice's surface
would be the wrong way round (D-127). Recorded because the symptom looks like a P&L defect and is
not one.

Found with it: the first version of the "exact Others" test passed while asserting nothing, because
the corrected fixture's costs had merged into one category and there was no Others to check. The
assertion was conditional (`if (others != null)`). It is now unconditional, over a fixture with six
lines, and it names the figure it expects. A test that can pass by finding nothing to check is the
family D-071 and D-273 record.

---

# Phase 6 Slice 9 — Drill-down Integration (2026-09-23)

## D-280 (closed) — The Overview fixture now describes rows the server can hold
**Date:** 2026-09-23 · **Status:** Implemented / Tested (project-lead instruction) — the entry
above stands as written, because this log is append-only.

The project lead ruled that the impossible fixture must not stay in the canonical Overview
harness. `test/features/dashboard_overview_test.dart` now uses the analytics fixture's valid
composite hierarchy:

* the kitchen department has its own section, `$ccr-kitchen-section`;
* four categories live under that section: Cylinder & Coal, Milk & Dahi, Paneer / Dairy and
  Vegetables & Fruits;
* `_cost` takes the section, so every kitchen cost names the kitchen's own section and category.

**Test data only.** No production or domain code changed.

**Totals are preserved.** Test 18 keeps the same four costs, on the same dates, for the same
₹10,000.00 in total. They are now spread over four kitchen categories instead of piled onto one
invalid Water row. Test 19's ₹7,500.00 moves from kitchen/Water to kitchen/Cylinder & Coal.

**Test 18 is now unconditional.** Its comment said "five ranked lines plus a remainder", but its
four costs had merged into one line. It now asserts five lines and a non-null Others. That is
D-280's own weak-assertion finding, closed where it started.

The Overview and dashboard-guard suites were re-run green (72).

## D-281 — The project lead's Slice 9 rulings on the Slice 8 flags
**Date:** 2026-09-23 · **Status:** Accepted (project-lead decision)

1. **Shared Phase 6 period: approved.** Four surfaces share one period selection
   (`dashboardSelectionProvider`): the Windows Overview, Revenue Analysis, Expense & Department
   Analysis and Business Comparison. The selection is keyed on the authority (D-267), so it
   never crosses principals and never survives a revoked scope.
   **The Profit & Loss stays independent.** It keeps its whole-month, whole-financial-year and
   Custom semantics (D-225, D-252).
2. **No displayed percentage share per category in Phase 6 V1.** Each category keeps its exact
   INR value, exact label and proportional fill (D-278).
3. **No per-category previous-period comparison in Phase 6.** It would be a future analytics
   extension needing explicit domain scope, and is never to be built in widgets or navigation
   code.

## D-282 — A dashboard figure opens the Phase 5 drill-down through a second anchor origin
**Date:** 2026-09-23 · **Status:** Implemented / Tested — Phase 6 Slice 9

**The coupling found in the real code.** The Slice 10 drill-down belongs to the report on the P&L
screen: `pnlDrillLevelProvider` refuses any anchor that is not
`PnlDrillAnchor.of(pnlViewProvider)`. A dashboard figure over Month to date, or over one trend
bucket, is not that report. Reusing the engine unchanged would have meant writing the
dashboard's range into the P&L's selection before every drill-down. That is a P&L state rewrite,
which the brief said to stop before.

**Decision.** `PnlDrillAnchor` gains an `origin`:

* `pnl` is the default, so every Phase 5 call site is unchanged;
* `dashboard` anchors carry their own viewer, scope and resolved range.

For a dashboard anchor, the level provider works in this order:

1. It refuses a different person (`reportChanged`, D-074).
2. It decides the D2 intersection again for the person signed in now, including unscoped
   consolidation. This happens **before any read**.
3. Only then does it read the report through `pnlDashboardDrillReportProvider`. That provider
   makes the P&L screen's own engine call (`reportForUnit` / `report` over a
   `CustomRangePeriod`) inside one canonical-cache span.

From there, every level, reconciliation, document row, document fetch and refusal is the
unchanged Phase 5 code.

**Why the destination reads rather than reusing the dashboard's figures.** `DashboardView` keeps
no per-bucket results. The brief also forbids treating prepared totals as query truth. The intent
therefore carries ids and a range, never a figure, and the destination is authoritative for what
a level holds.

**One level is added, for this origin only.** On the P&L, the revenue categories are the
statement's own lines. A dashboard's Net Sales has no such lines beneath it, so a dashboard opens
`PnlRevenueCategoriesAt` as its revenue level.

* Its parent is `PnlDrilldown.revenueOf(result)`.
* It reconciles gross, GST and net exactly, using the existing `revenueChildrenReconcile`.
* For dashboard anchors only, `PnlRevenueDocumentsAt.parent` and the Revenue crumb point at this
  level.
* On the P&L, both behave exactly as before.

**The shared view gains labels, not logic.** The breadcrumb, level list, document detail and
mobile pages take two new parameters:

* a `reportLabel`, naming where Back returns to (for example, "Back to Revenue Analysis");
* an `onRefresh`, so a refresh runs the dashboard's own synchronisation rather than the P&L's.

The defaults reproduce Phase 5 exactly. The mobile pages still return to the P&L when its
selection changes, but only for P&L-origin drill-downs; a dashboard drill-down carries its own
range.

## D-283 — A hand-off to the P&L is an explicit Custom period, through the P&L's own contract
**Date:** 2026-09-23 · **Status:** Implemented / Tested — **one consequence flagged**

Some figures have no transactions of their own:

* Operating Profit
* Operating Margin
* Gross Sales and GST
* a profit trend point
* a property

These open the existing P&L:

1. `selectScope(scope)` and `selectCustom(from, to)` are called with the exact resolved range.
2. The Analytics section switches to Profit & Loss.
3. On Windows, a hand-off from the Overview goes to `/analytics`. On Android, the shell switches
   to the Reports branch.

No P&L preset, resolver or provider changed, and there is no second P&L state model. The P&L
does not follow the dashboard afterwards, and This Month is still the whole calendar month
(proof 33).

**Flagged:** a hand-off replaces whatever the P&L was last showing with the Custom range it was
opened for. That is what "open the P&L for this period" means under the existing contract. If
the project lead would rather the P&L keep its previous selection and show the hand-off range
only temporarily, that needs a second, transient P&L selection, which is a decision for them.

## D-284 — Opening a chart point is a separate act from selecting it
**Date:** 2026-09-23 · **Status:** Implemented / Tested

The chart layer only reported selection, and selection follows the pointer: a ranked row selects
on hover. Navigating on selection would send a reader somewhere because the mouse crossed a row.
Each chart therefore gains `onActivated`:

* **Ranked rows** open on tap. Hover still only selects.
* **Trend, profit and comparison charts** open on any of:
  * a tap on a mark;
  * Enter or Space;
  * the explicit, keyed **Open ⟨label⟩** action under the plot (`ChartOpenAction`,
    `ChartFrame.openKey`). It sits outside the plot's excluded semantics, so screen readers
    announce it.
* **A gap has no Open action and opens nothing** (D-263).

The chart layer still resolves only an index. What that index means is decided by the surface's
shared adapter.

## D-285 — Findings while building Slice 9
**Date:** 2026-09-23 · **Status:** Recorded

**A guard word met a variable name.** The analytics guard forbids the substring `target`,
meaning targets and budgets. The first wiring named a local variable `targets`, and the guard
refused it. The variables were renamed (`opens`, `destination`) and the guard was left alone:
the rule is right, and the name was incidental.

**Control C found two layers, not one.** Removing the destination's viewer and authority checks
turned proofs 12 and 22 red. Proofs 21 and 23 (capability revocation) stayed green. That is not
luck: the Slice 7 cache adapter (D-220) independently refuses a reader who lacks authority, so
the report beneath the drill-down still came back `notAuthorised`. The destination check is the
first gate, not the only one, and both gates stay.

**The dashboard sync invalidates the drill-down source** (Slice 4 code). The new "no drill-down
reads" rule therefore forbids *reading or watching* that source, not naming it.

---

# Phase 6 Slice 10 — Full Acceptance (2026-09-23)

## D-283 (final) — The P&L hand-off replaces the P&L's period, and that is approved
**Date:** 2026-09-23 · **Status:** **Accepted (project-lead decision)** — closes the point
D-283 flagged. The earlier entry stands as written, because this log is append-only.

When a Phase 6 dashboard or analytics figure navigates to the existing P&L, the P&L is set
to that figure's exact resolved canonical date range as a **Custom** period. This may
replace whatever period the P&L was showing before.

**Not created, by ruling:** a temporary P&L selection, a second P&L provider, hidden
return-state financial semantics, or another P&L screen. The existing P&L remains the single
source of truth, and its presets are unchanged.

**Back** returns the reader to the originating dashboard or analytics surface where the
platform flow already supports it:

* **Windows, from an Analytics section:** the workspace switches to its Profit & Loss
  section. Choosing the originating section again shows it unchanged; its state stays
  mounted.
* **Windows, from the Overview:** the shell goes to Analytics. The Overview destination
  shows the Overview with its period and scope as they were.
* **Android, from Home:** the shell switches to the Reports tab. The Home tab shows the
  dashboard as it was left.

None of these returns carries financial state. Each is the platform's own branch or section
navigation.

## D-286 — Money never shrinks to fit; the layout gives way, and a figure breaks only between digit groups
**Date:** 2026-09-24 · **Status:** Implemented / Tested (project-lead rule and ruling) —
**corrects the Slice 10 layout fix and the shrink-to-fit it inherited from Slices 5–9**

**The rule, as the project lead set it.** Money and every exact financial value must not
silently shrink to fit: no `FittedBox` scaling, no `Transform.scale`, no smaller font chosen
because a line is tight, no ellipsis, no clipping. At a large Android text scale the layout
gives way: side-by-side content reflows vertically, the figure takes its own line, a
proportional bar moves below it, the row grows taller, and the reader's own text scale is
kept. Names are not truncated either.

**What Slice 10 had done, and why it was wrong.** The first large-text fix wrapped the
Gross/GST pair, the ranked amounts and the chart readout in `FittedBox(scaleDown)`. That
repeated a mechanism already in five shipped places — the phone Home headline (D-276), the
Windows analysis summary and Business Comparison table, the Android P&L lines and the
Android drill-down rows — each commented as "scaled down rather than truncated". A figure
drawn at a third of its size is not truncated, and it is not the size the reader chose.

**Proven RED on the code as it stood**, by checks that read what was painted rather than
what the source intended:

* the structural guard found the shrink mechanism in **8 files**;
* the phone Home headline "₹1,66,383.00" was drawn at **0.238×** at 320 dp and 2.0× text,
  and at **0.693×** even at 430 dp and 1.0×.

**The first scale check was itself vacuous**, and a control found it. It used a 4×4
transform's largest axis scale, which includes z; a 2-D shrink leaves z at 1, so the check
passed over a figure drawn at a quarter size. It now measures x and y.

**Decision — one reflow primitive, every site.** `FigureReflow`, in
`core/design/components/`, lays a lead (label, title or bar) beside a figure while the
figure's whole one-line width fits. It measures that width as the figure's own text at the
reader's scale. When the figure does not fit, it puts the figure on a full-width line at full
size and grows taller. It replaces all eight shrink sites:

* phone Home headline metrics and Gross/GST;
* ranked rows, where the bar goes below the figure;
* the chart header, where the readout goes below the title;
* the Windows analysis summary and Business Comparison;
* the Android P&L lines and drill-down rows.

Ranked names are no longer ellipsised (D-269 final). `lib/` now contains no `FittedBox`,
`BoxFit.scaleDown`, `Transform.scale` or text-scale clamp, and a guard keeps it that way.

**The one case the rule did not settle, and the project lead's ruling.** Measured with the
real Android font, the 26 px headline "₹1,66,383.00" at 2.0× needs 303 px. It has 254 px on
a 320 dp phone and 294 px on a 360 dp phone, even on a line of its own. No reflow can fit
it. **Ruled: break at digit groups.** Only when a figure is wider than a full line of its
own, it breaks after a comma between digit groups ("₹1,66," then "383.00"). It stays at full
size, every digit is visible, and the card grows. `MoneyText` places invisible break
opportunities after commas only, and a word joiner after a sign, so a line can never start
inside a group or between a sign and "₹". The approved headline size is unchanged.

**Tests measure real glyphs.** The test framework's default face draws every glyph 1 em
wide, about 1.8× a phone's digits. At that width no headline fits even at 1.0× on 360 dp, so
a large-text check against it proves nothing about a phone. The layout suites load Roboto
from the Flutter SDK's own material fonts. Nothing is downloaded, and nothing is added to the
app.

**What is checked, at 320, 360 and 411 dp × 1.0, 1.6 and 2.0 on the phone Home, the Android
P&L and the drill-down pages, and at 1366, a narrower window and 1920 on the Windows
Overview and analysis sections:**

* every paragraph showing ₹ is drawn at scale 1, at the system text scale, and not cut short;
* a pure figure is on one line at its full width, or — only when wider than a full line of
  its own — broken after a comma with every glyph inside its line;
* no figure runs off the screen;
* the last content clears the docked [ + ].

**Controls, each seen RED and restored byte-identical (`cmp`):**

* the break removed: the 320/360 dp × 2.0 headlines break inside a group;
* `FigureReflow` forced side by side: 16 tests turn red.

## D-287 — Recorded in Slice 10, and not called flaky
**Date:** 2026-09-24 · **Status:** Recorded

* **Android authority run 1 stalled for more than 20 minutes with no captured cause.** The
  cold-boot rerun passed. It is recorded as unexplained, not flaky. The phase now logs
  numbered steps, so a recurrence names the step it stalled on.
* **The emulator's DNS failed** ("unknown host", Wi-Fi "!"), and sign-in could not reach the
  server. It was fixed by cold-booting with explicit DNS servers. This was a device and
  network cause, not a product one.
* **The on-device layout loop passed at 320 × 1.6** while the host check failed. The device
  check most likely did not apply the size and scale it claimed. The host suites (D-286) are
  the layout evidence.
* **Before a refresh, the financial year to date comparator is withheld**, because the
  previous financial year has not been downloaded. This is correct (D-253, D-170).

## D-288 — The physical phone is addressed by its USB serial, over USB only
**Date:** 2026-09-25 · **Status:** Accepted (project-lead instruction) — acceptance
infrastructure only; no product or runtime configuration changes

The first physical Phase 6 attempts never reached the phone. Each one stopped at device
lookup or install with `device 'R9ZY50M3GVX' not found`, while Windows went on listing
the phone's USB interfaces as healthy. No test executed, so none is recorded as a result.

**The cause, from evidence rather than theory.** After one failed install, `adb devices -l`
listed the phone only as `adb-R9ZY50M3GVX-L4e2UQ._adb-tls-connect._tcp`, at a
`192.168.x.x` address. Wireless debugging was on, and adb's automatic mDNS connection had
taken the phone over under its Wi-Fi identity. The USB serial the run was addressed to
then no longer existed. The climbing transport numbers (1, 6, 10) had recorded the same
swapping.

**Decision.** Physical acceptance uses USB ADB only, addressed by the USB serial:
* wireless debugging off on the phone, USB debugging on;
* the adb server restarted with `ADB_MDNS_AUTO_CONNECT=0` for the session;
* a preflight asserting exactly one target, `R9ZY50M3GVX device`, with no
  `_adb-tls-connect`, `192.168…`, emulator, unauthorised or offline entry;
* a 90-second watch of that serial before launch;
* the device identity recorded immediately before and after every run.

If the identity changes during a run, the run stops and the failure is classified as
acceptance infrastructure or device configuration, never as a product failure.

**Two further transport findings, recorded and not over-explained.**
* With wireless debugging off, one watch lost the USB serial about 40 seconds after
  authorisation, while Windows still listed the ADB interface. The cause was not captured.
  The phone's screen locking fits the timing, but it was not proven.
* Windows later reported the phone as **Code 10** (`0xC0000001`) on a USB 3 root hub. A
  replug cleared it.

**Recorded, not changed.** The phone reported `stay_on_while_plugged_in=0` although Stay
awake had been set, and `screen_off_timeout=1800000`. The monitor's screen-state column
failed on a script error, so screen state during the passing watch is not evidenced; only
ADB state is.

With the preflight in place, `p6-android-dashboard` and `p6-android-authority` both passed
on the Galaxy A06, with the USB identity unchanged before and after each.

## D-286 (clarified) — An exact amount stays on one line whenever an empty line holds it
**Date:** 2026-09-25 · **Status:** Accepted (project-lead clarification)

An exact money value stays on one line whenever the complete amount fits on an otherwise
empty line at the selected system text scale. Only when the complete amount cannot fit on
an empty available line may it wrap, and then only at an Indian digit-group separator.

Digits are never removed. Money is never ellipsised, clipped, or shrunk, and the system
text scale is never reduced.

**The product already behaves this way.** `FigureReflow` gives a stacked figure the full
width of its line. `MoneyText` offers break opportunities only after commas, and the text
engine uses one only when the whole figure is wider than its line.

**One test looseness, recorded rather than changed during acceptance.** The last-resort
check in `test/support/money_layout.dart` accepts a broken figure if it was wider than its
slot and the slot was at least 60% of the screen width. That is a proxy for "an otherwise
empty line", not a measure of it. It passes because the product is correct. It would not
catch a figure broken inside a slot narrower than its line but wider than 60% of the
screen. Tightening it to the enclosing line's width is a test change for the project lead
to schedule.

## D-286 (test tightened) — The layout check measures the real empty line
**Date:** 2026-09-25 · **Status:** Implemented / Tested (project-lead instruction) — closes the
looseness recorded in *D-286 (clarified)*

`test/support/money_layout.dart` no longer approximates "an otherwise empty line" as 60% of
the screen. A figure that wraps is accepted only when all of these hold:
- it lies in the **figure** child of a `RenderFigureReflow`;
- that reflow has stacked it onto a line of its own;
- the paragraph was given the reflow's full measured width;
- its complete one-line width exceeds that width.

Two focused tests pin the boundary at the real width. A line exactly as wide as the figure
keeps it on one line. A line 2 px narrower lets it break, after a comma only.

**Proven RED first.** With `FigureReflow`'s stacked line deliberately narrowed:
- to 70%, the new check failed 16 tests and the old one 14. At phone widths the proxy
  happened to trip, so this level did not separate them;
- to 90%, the new check failed **8**. The old check let **all eight screen suites pass** and
  caught only an isolated unit test.

Restored byte-identically, the suites are green: 314 tests. The stricter check found no
product defect, and no product code changed. Commit `310a2d0`.

---

# Phase 6 — Dashboard & Analytics: closure (2026-09-25)

## D-289 — Phase 6 is closed, and this is what each of its decisions finally says
**Date:** 2026-09-25 · **Status:** Accepted (project-lead approval of the Slice 11 audit)

Phase 6 closes at Slice 11. **Slice 11 is documentation and closure gates only**: no
product code, no schema, no migration and no server change. This entry records the final
disposition of every Phase 6 decision, so a reader need not reconcile the flags,
corrections and closures across fifty entries. **No earlier entry is rewritten or
renumbered.**

### Final dispositions

| Decision | Final state |
|---|---|
| D-251 … D-255, D-257 … D-261 | Accepted and implemented (governance, periods, comparisons, trend grain, fl_chart, Top N, the neutral landing surface, the platform split, the plan and the gate) |
| **D-253** flagged point | Closed by **D-264** |
| **D-255** open point (the Custom trend grain) | Closed by **D-263** |
| **D-256** "pending confirmation" | Superseded by **D-256 (closed)**. An ordinary figure shows a percentage only when `previous > 0 && current ≥ 0`, and the rupee movement is always shown. Operating Profit keeps D-253's stricter loss and sign-change rules |
| **D-262** | **Never allocated.** No entry, reference, code comment or test names it. It is a numbering gap, recorded here and **not** filled retroactively; the numbers are not renumbered |
| **D-263** | Final. Net Sales is daily to 31 days, weekly to 180 and monthly beyond. Expenses and profit are monthly only, and withheld below two buckets. A missing bucket is a gap, never zero or interpolated |
| **D-264** | Final. The displayed margin movement is the difference of the two displayed margins; the exact movement stays canonical |
| **D-265 / D-266** | Final. One plan, one lock span, one freshness claim or none. The performance gate was discharged with nothing added. Re-measured at closure (below) |
| **D-267 / D-268** | Final. The authority key is the dashboard identity; charts derive coordinates from money and never money from coordinates |
| **D-269 / D-269 (final)** | Final. fl_chart **1.2.0**, pinned. The three ranked families stay as composed rows |
| **D-270 … D-275** | Final |
| **D-276** | Its fix stands (the Gross/GST pair wraps). The "scaled rather than truncated" wording of that era is **superseded by D-286** |
| **D-277** flag (the shared period) and **D-278** flags (no share percentage, no per-category comparison) | Resolved by **D-281** |
| **D-280** | Superseded by **D-280 (closed)**: the Overview fixture describes rows the server can hold |
| **D-282 / D-284** | Final |
| **D-283** flag | Closed by **D-283 (final)**. A hand-off replaces the P&L's period with an explicit Custom range |
| **D-285** | Recorded. The drill-down's authority check is two gates: the destination, and the Slice 7 cache adapter. Not a defect |
| **D-286 → (clarified) → (test tightened)** | **Final.** The layout gives way before money does. An exact amount stays on one line whenever an empty line holds it, and breaks only after a digit-group comma when it cannot. Nothing shrinks, clips or ellipsises, and the text scale is never reduced. The layout check measures the real empty line |
| **D-287** | **Acceptance-infrastructure observations**, not product defects: the emulator authority stall, the emulator DNS fault and the on-device layout loop |
| **D-288** | **Acceptance-infrastructure observations**, not product defects. The wireless-ADB takeover was proven and fixed by running USB-only with mDNS off. One USB drop remains unexplained, one Code 10 cleared on replug, and the phone reports Stay awake off |

### Evidence at closure

- **Host:** 2,648.
- **Live:** 106, run serially.
- **Windows real-executable acceptance:** `p6-windows-dashboard` and `p6-windows-authority`
  both pass.
- **Emulator acceptance:** `p6-android-dashboard` and `p6-android-authority` both pass.
- **Galaxy A06 automated acceptance:** both phases pass. SM-A066B, Android 16 / API 36,
  USB serial `R9ZY50M3GVX`.
- **Galaxy A06 manual checklist (§S.3):** **20/20 PASS**, reported by the project lead on
  2026-09-25.

**Performance, re-measured on the current `DashboardEngine`.** Slice 3's Android figures
predated the Slice 6 engine change, so Android was measured again at closure. Same fixture
throughout: 4,380 revenue and 2,920 expense contributions, two financial years, two
properties, on the real SQLCipher database. Two launches on the `Pixel_8` emulator
(`sdk_gphone16k_x86_64`, Android 17 / API 37, debug build):

| Workload | Reports / points | Warm now (runs 1 / 2) | D-266 warm |
|---|---|---|---|
| Financial year to date, whole year | 14 / 36 | 32 / 37 ms | 23–24 ms |
| Financial year to date, mid-year | 8 / 18 | 18 / 14 ms | 10–12 ms |
| **Month to date, daily + weekly, ranked** | **37 / 35** | **47 / 37 ms** | **31–41 ms** |
| Week to date, daily, ranked | 6 / 4 | 6 / 6 ms | 5 ms |
| Custom 365 days | 14 / 36 | 26 / 24 ms | 19–21 ms |
| Custom 180 days, weekly | 28 / 26 | 32 / 26 ms | 25 ms |
| Custom 31 days, daily, ranked | 33 / 31 | 30 / 25 ms | 24 ms |

- **Report and point counts are identical to D-266 for every workload**, which confirms the
  Slice 6 engine change added no reads (D-270).
- The worst warm figure is **47 ms**, about ten milliseconds above Slice 3 and roughly
  one-ninth of the 400 ms intervention threshold (`ARCHITECTURE.md` §9). That is not a
  material regression.
- Windows was re-measured at Slice 10 on the same engine: worst steady state **163 ms**,
  against D-266's 168 ms.
- No optimisation, RPC, aggregate or index was added.

**Schema and server.** Drift **v21** and the migration ledger at **101**, unchanged since
the Phase 5 closure. Phase 6 added no relation, column, index, RPC or migration.

### Carry-forwards

| Class | Items |
|---|---|
| **A. Phase 7** | Excel export; PDF; Windows printing; the `reports.export` and `reports.print` evaluators, still exempt under D-139; the Windows *Reports* destination. Exports render `PnlResult` and `DashboardView` and compute nothing (`ARCHITECTURE.md` §50) |
| **B. Phase 8** | `may_read_expense` per-row cost (D-186); the `org_id`-leading local expense index (D-223); any materialisation that a measurement justifies; broader stress and recovery work; making a missed tap fatal across the whole host suite (known issue #5) |
| **C. Phase 9** | Production Supabase configuration; the D-146 fresh-branch migration replay; Android release signing; AAB; Play Internal Testing; Windows installer; production distribution and go-live |
| **D. Product / business** | **The production 50:50 ownership effective-from date**; disposal of the D-247 forensic database; the stale Windows *Administration* placeholder copy ("arrives in Phase 2"), left unchanged at the project lead's instruction for the future Administration work |
| **E. Future analytics** | Category percentage shares; per-category previous-period comparison (both D-281); vendor analytics; value-band and supply-subtype analysis; forecasting; targets and budgets; further analytical dimensions |
| **F. Owner Accounts extension** | Finalized Owner Statements (D-193); owner-ledger outbox wiring (D-218); a per-family-member non-chargeable breakdown; the OA-1 client NC pre-check (D-208, D-216) |

**Open defects at closure: none.** Phase 7 may be scoped on the contract in
`ARCHITECTURE.md` §50.

---

# Phase 7 — Export, PDF & Printing: the project lead's rulings (2026-09-25)

The Phase 7 scoping audit is recorded in the conversation that started the phase. Its
findings are restated where they matter below, so this log does not depend on that
conversation. The project lead accepted the audit and ruled on its eight questions
(D1 … D8). D-290 … D-297 record those rulings as given. D-298 … D-300 record the dependency
decision, the export contract and a documentation correction.

**The principle every entry below serves:** Phase 7 **renders results the app has already
approved**. It is not another reporting or accounting engine.
- Every exported or printed figure is a field of a `PnlResult` or `DashboardView` the
  Phase 5 and Phase 6 engines produced, or a label taken from the cached masters.
- No export computes a P&L, GST, category total, margin, comparison or reconciliation.
- No export queries a financial table or reads through a second cache.
- No export decides authority by role name (spec §16, §21.3, `ARCHITECTURE.md` §50).

## D-290 — V1 export scope: four Windows reports as PDF and Excel; the P&L as PDF on Android
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D1)

**Windows** exports **PDF and Excel** for:

1. **Profit & Loss** — the canonical management P&L, in the shape of spec §10. For a
   consolidated scope: revenue lines by category → Gross Sales → less GST → Net Sales →
   expense lines by category → Total Expenses → Operating Profit or Loss → Operating Margin,
   for each property and for the consolidated total.
2. **Revenue Analysis**
3. **Expense & Department Analysis**
4. **Business Comparison** — offered only when consolidated authority qualifies (D-278).

**Not exported:** the Overview dashboard as its own document, chart images, screenshots, or
anything that exists on screen only as decoration. An export shows the underlying
management figures as professional tables.

**Evidence the audit relied on:** spec §16 (Excel, PDF, Windows printing), §21.3 (Excel and
PDF are in the parity rule), §28 (Excel and PDF export are V1 scope; revenue, expense,
department and business analyses are V1 reports) and §33 ("export P&L").

## D-291 — `reports.export` and `reports.print` are client-enforced product-action controls
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D2)

```
    export   =  qualifying view authority for the exact scope  AND  reports.export for that scope
    print    =  qualifying view authority for the exact scope  AND  reports.print  for that scope
```

**What counts as qualifying view authority.** It is the report's own rule:
- `PnlAuthority` for the P&L and the three analysis sections — per property, or unscoped for
  consolidated (D-164, D-187, D-226);
- consolidated authority for Business Comparison.

**Consolidated scope needs the action capability for every property it includes.** A
consolidated export needs `reports.export` (or `reports.print`) either **unscoped** or held
for **every** included property.

**A capability alone grants nothing.** Holding `reports.export` or `reports.print` without
view authority reveals no figure. No role name is read.

**The status of these two capabilities, stated so nobody claims more than is true:**
- They are **product-action controls**. They are **not** the confidentiality boundary for
  financial data.
- That boundary is the server's reporting authorization. `reporting_primitives` and
  `reporting_snapshot` enforce D-164 in Postgres, and RLS enforces the projections behind
  them. That authorization decides which figures can reach a device at all.
- An export only lays out figures the device was already authorised to hold and display.
- **No server component evaluates `reports.export` or `reports.print`, and V1 adds none.**
  There is no export-audit RPC, no migration and no server change for this decision.
- A modified client could therefore skip the action check. What it could never do is obtain
  a figure the server did not authorise.

**Offline export of a complete, already-authorised canonical report is permitted.** Export
does not require a network round trip.

**D-139's exemption stays, and its reason changes.** Both capabilities remain on the
exemption list in the latest restating migration (`20260911131228`).
- The migration's comments still read "Phase 7 · no export path exists" and "no print path
  exists". That was true when they were written. The migration has been applied and is **not** rewritten (A0,
  D-056).
- **From Phase 7 the reason is D-291:** these capabilities are evaluated on the client by
  design, so "no server evaluator" is the intended final state, not a gap.
- The exemption still covers only these two capabilities (and `settings.manage`, whose
  surface still does not exist). It is not a general rule for client-only capabilities. Any
  new client-evaluated capability needs its own decision.

## D-292 — Role bundles are unchanged; a Manager does not gain export or print
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D3)

The seeded bundles stand exactly as shipped:
- **Owner** holds every capability.
- **Accountant** holds `reports.export` and `reports.print`, scoped to their properties.
- **Manager** holds `reports.view` but **not** the two action capabilities.
- **Data Entry** holds none of the three.

**Consequence:** a Manager can read the P&L and the analysis sections but is **not offered**
Export or Print. This is the intended V1 behaviour, not a defect.

If a particular Manager needs to export or print, the capability is granted through normal
capability administration. There is no role-name exception and no special case in code.

## D-293 — Android V1: the P&L as a PDF, handed to the system share sheet
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D4)

**Android offers one thing:** generating the P&L PDF and handing it to the system share
sheet.
- **Not on Android:** Excel, direct printing, and exports of the Windows analysis sections
  (Android has no screen for those).
- **Files:** the PDF is written to app-private cache storage, shared through the share
  intent, and the temporary file is removed afterwards.
- **No new permissions.** No `WRITE_EXTERNAL_STORAGE`, no broad filesystem access, no
  Downloads folder.
- **Why share and not save:** the installed `file_selector_android` (0.5.2+10) cannot show a
  save dialog. It offers `openFile`, `openFiles` and `getDirectoryPath` only. So the share
  sheet is the Android way to "save" (Files, Drive, email).

**The PDF renderer is shared across platforms.** The Android P&L PDF is built from the same
document model, by the same renderer, as the Windows P&L PDF.

## D-294 — Excel money cells are numeric, written from integer paise
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D5)

**Money cells are numeric cells**, so they stay sortable, filterable and usable in Excel.
They are never turned into text to get perfect Indian digit grouping.

**How a money value becomes a cell:**
- Each value is written from the exact integer paise, as a decimal literal built by
  **integer formatting**: rupees, a point, then two digits of paise.
- **No Dart `double` touches a money value** on its way into the workbook.
- Excel itself holds every number as a double. That is a property of the file format, not a
  calculation in this project. The workbook contains no formula that could turn that into
  arithmetic.

**Contents rules:**
- **No finance formulas.** No cell recalculates a total, GST, Net Sales, a profit or a
  margin. Every figure is a value copied from the canonical result.
- **No raw-paise column** in a management workbook.
- **The margin** is a numeric percentage written from the exact scaled integer (D-224), or
  the text **N/A** when Net Sales is zero. It is never `0.00%`.

**Number format.** Excel's custom number format language accepts at most two conditional
sections. Lakh/crore grouping cannot therefore be expressed correctly for every positive
**and** negative value, and a loss is exactly the negative case a P&L must get right.
- If a lakh/crore format cannot be proven correct for every value the workbook can contain,
  the workbook uses a **conventional, reliable numeric currency format**. Wrong grouping is
  not acceptable.
- Parity (spec §21.3) is about the **numerical value**. Digit grouping is presentation.
- The screen and the PDF keep exact Indian-style formatting (₹12,36,420).

## D-295 — The PDF font is Noto Sans, bundled locally, never fetched
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D6)

**Why a font must be bundled.** The PDF standard fonts cannot draw ₹. `printing` 5.15.1
ships a Google Fonts helper that **downloads fonts over the network** at runtime, which
would make PDF output depend on connectivity. It must not be used.

**Decision:**
- **Noto Sans** is bundled as an application asset, in only the weights the report design
  actually uses. The expected set is Regular and Bold; it is confirmed in the PDF slice.
- The SIL Open Font License text and attribution are committed beside the font files.
- The renderer is proven to work with the network absent.
- Before Noto Sans is adopted, the PDF slice must verify that it draws ₹ and all ordinary
  report text.

## D-296 — Transaction-list export is deferred
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D7)

**Why:** the canonical reporting cache (`reporting_tables.dart`) holds no transaction
number, notes or vendor name. A drill-down list exported from it could not show the
KI-EXP / KI-REV reference a reader would expect. Adding one would need one of three things,
all ruled out for Phase 7 V1:
- a reporting-cache schema change (Drift v22);
- an online fetch of every document just to export it;
- an online-only drill-down export.

**Decision:** transaction-list and drill-down export are **out of Phase 7**. The existing
drill-down is unchanged. If transaction-list export is required later, it is scoped
separately, with its data requirements stated.

## D-297 — The Windows Reports destination becomes the Export Centre
**Date:** 2026-09-25 · **Status:** Accepted (project-lead decision D8)

The Windows Reports placeholder (`app_router.dart`, the `AppRoutes.reports` desktop branch)
becomes an **Export Centre**.
- **What it offers:** access to, and export/print actions for, the four canonical outputs
  of D-290.
- **What it reuses:** the existing canonical report, scope and period selections, and the
  shared export and print pipeline.
- **What it does not do:** duplicate Analytics or the P&L. It is not a second P&L screen,
  not a second analytics workspace, and has no report state of its own. Figures stay on the
  surfaces that already show them.

## D-298 — Dependencies: `pdf` and `printing` pinned; an internal XLSX writer on `archive`
**Date:** 2026-09-25 · **Status:** Accepted (project-lead approval)

**Approved, pinned exactly** (checked against pub.dev on 2026-09-25):

| Package | Version | Why | Notes |
|---|---|---|---|
| `pdf` | **3.13.1** | the PDF document model and layout, pure Dart | Apache-2.0. Compatible with the locked `archive` and `image`; brings `xml` 7 in transitively |
| `printing` | **5.15.1** | native print dialog on Windows; Android share (it ships its own FileProvider) | Apache-2.0. Flutter ≥3.41, Android minSdk 21 |
| `archive` | promoted to a **direct** dependency, at the 4.x version pub already resolves (4.2.0 today) | ZIP container for the XLSX writer | already present transitively, through `image` |

**Rejected:**
- **`excel` 4.0.6** needs `archive ^3.6.1`, which conflicts with the locked `archive` 4.x.
  Its last release was August 2024.
- **`share_plus` 13.3.0** needs `win32 ^6.0.1`, which conflicts with the `win32 ^5.15.0` pin
  D-246 depends on. `printing` covers PDF sharing on Android.

**Pinning happens in the slice that first uses each package**, not in governance. That
keeps each dependency change next to the code and tests that justify it.

**Recorded risk — the Windows build downloads PDFium.** `printing`'s Windows
`CMakeLists.txt` downloads a PDFium binary at **build** time, `PDFIUM_VERSION 5200`, from
`github.com/bblanchon/pdfium-binaries`.
- A Windows build machine therefore needs that host reachable, or a local copy supplied
  through the `PDFIUM_URL` / `PDFIUM_VERSION` cache variables.
- This is a build-time fact only. Nothing is fetched when the app runs.
- It belongs to Phase 9's reproducible-build work, and is noted here so it is not a
  surprise.

**The internal XLSX writer.** It is a small OpenXML writer on top of `archive`, and its
responsibilities stop at packaging:
- workbook and package structure, worksheets, cells, styles;
- number and date formats, frozen panes, auto-filters;
- relationships, content types, and ZIP serialisation.

It **does not** calculate a P&L, GST, a category total or a margin, does not create a
finance formula, and does not query reporting data. It receives immutable canonical export
models and writes them out. A structural guard in the XLSX slice enforces this, the way
D-268 guards the chart layer.

## D-299 — The export contract: one document model, rendered two ways, printed as the PDF it is
**Date:** 2026-09-25 · **Status:** Accepted — the contract Slices 2 to 9 build against

**The pipeline, one direction only:**

```
    canonical result (PnlResult / DashboardView) + cached master names
          │   read under the same authority, scope, period and lock the screen uses
          ▼
    export document model      immutable; exact Money; no arithmetic; freshness carried
          ├──► PDF renderer  ──► save (Windows) · share (Android) · print (Windows)
          └──► XLSX writer   ──► save (Windows)
```

**One model per report.** Each of the four outputs has one immutable document model. It is
built **only** from:
- the canonical result the corresponding screen already reads;
- labels from the cached master graph, which show the current name (D-035);
- the resolved scope and period, and the freshness evidence.

The model copies figures. It does not derive any. A structural guard enforces this with the
same token lists as the dashboard and analytics guards (D-279).

**Printing is the PDF.** Windows printing sends the **same bytes** the PDF renderer
produced for that model to the native Windows print dialog (`Printing.layoutPdf`). There is
no print-specific layout, no print-specific report logic, and no direct printer protocol.
The P&L must print directly; other outputs may use the same pipeline where that costs
nothing.

**Authority comes first.** The pipeline checks D-291 for the exact scope **before** the
model is built. A refused scope never produces a model, a file or a print job.

**Offline behaviour.** Export works when all three hold:
- the canonical report is complete locally;
- the current principal is still authorised;
- the required action capability is held.

**Export never triggers a sync or a fetch.** An unavailable report stays unavailable: the
export is refused with the reason the screen already gives. Missing data never becomes ₹0.

**Freshness, three separate statements, never merged:**
1. **Synchronised as of T** — the server-confirmed time, only when canonical snapshot
   evidence exists (D-188);
2. **Server has newer changes** — only when a head check actually confirmed it;
3. **Generated on this device at …** — the device clock, labelled as the device clock.

When the report carries no freshness evidence, the document states none, rather than
inventing one or passing off the generation time as the synchronisation time.

**Every document also states:**
- the date basis (P&L date, spec §5.3);
- what the expenses include;
- the scope, and the exact period.

**Parity (spec §21.3).** The parity suite is extended to the document models, the XLSX
cells and the PDF text. The screen, the workbook and the PDF must agree on every figure,
exactly, in integer paise.

**Never in an exported file:**
- identifiers: Supabase or database ids, auth user ids, snapshot identities, change
  sequences, row versions;
- internal names: capability codes, cache or coverage metadata, local file paths;
- test material: acceptance or test markers;
- credentials of any kind.

A guard inspects the generated bytes, like the secret scanner does.

**Owner Accounts are out of Phase 7.** No Owner Accounts export, no settlement statement and
no printed settlement preview. The preview is not a statement (D-212 Q3). Finalized Owner
Statements remain carry-forward F (D-289).

**What does not change.**
- **Schema and server:** Drift stays v21, the ledger stays 101. No migration, no reporting
  RPC, no reporting cache, and no server write or API change. If an approved Phase 7
  requirement turns out to need any of these, the work **stops and is reported first**.
- **Performance:** export rendering is measured separately. The reporting engine and cache
  are not optimised in Phase 7; that stays Phase 8's work.

## D-300 — The schema document's capability catalogue now matches the shipped codes
**Date:** 2026-09-25 · **Status:** Implemented (documentation only)

**The finding.** The Phase 7 scoping audit found that `DATABASE_SCHEMA.md` §2's
"initial" capability catalogue named `report.view / report.export / report.print`. Those
codes never existed. The shipped codes, in `public.capabilities` and
`lib/domain/auth/capability.dart`, are `reports.*`. The same Phase 0 block also wrote
`master.*`, `user.manage` and `role.manage`, where the shipped codes are `masters.*`,
`users.manage` and `roles.manage`. It also omitted every capability added after Phase 0.

**The fix.** The block now restates the shipped catalogue in full, cites the two
authoritative lists, and records the correction in place. No code, seed, migration or
capability changed. This is the documentation disagreeing with the code, resolved in favour
of the code, which is where the truth lies (governance rule 3).

## D-301 — The host suite is portable to a Linux cloud/CI host
**Date:** 2026-09-25 · **Status:** Implemented / Tested. This is **cloud/CI portability
infrastructure, not a Phase 7 feature**. It changes test code only; no product behaviour
changes.

**The finding.** Phase 7 Slice 1 ran the host suite in a Linux cloud container. It got
**2,405 passed, 1 skipped, 9 failed**, and the untouched Phase 6 closure commit gave the
identical result there. Windows, where every earlier phase ran, passes 2,648 of 2,648.
Two assumptions in the tests had only ever held on the project lead's machine:

1. **`test/support/money_layout.dart` opened `material_fonts/roboto-regular.ttf`.** The SDK
   ships `Roboto-Regular.ttf`. Windows' case-insensitive filesystem hid the difference.
   On Linux, six layout suites failed in `setUpAll`, so **233 tests never ran**.
2. **Three D-077 wiring tests read the production provider on the host** and required a
   real picker. That held only because the host was Windows.

**Proven red first**, with the eight affected files run together: **18 passed, 9 failed**.

**The corrections, all test-only:**
- **Font lookup.** The helper matches the three faces by name case-insensitively and
  requires exactly one match for each. A missing directory now says to run `flutter
  precache`, instead of failing with an unexplained path.
- **The provider wiring test** is split into two host-independent claims:
  - **(a) Structural.** The body of `attachmentSourceProvider` is exactly
    `attachmentSourceFor(Platform.operatingSystem)`, with nothing in front of it.
  - **(b) Runtime.** Reading the provider with no override gives what this OS resolves
    to. On an Android or Windows host it must also be a real picker.
  - Together with the existing function tests, which prove that Android and Windows
    resolve real pickers, this keeps the whole D-077 guarantee on any host.
- **The two revenue-surface tests** now ask production's own
  `attachmentSourceFor('android' | 'windows')`, named explicitly, instead of whatever OS
  the host is. The detail surface is tested for both shipped platforms and the entry form
  for Android, so one test became two.

**Green afterwards.** The same eight files: **262 passed, 0 failed.** The full host
suite on Linux: **2,649 passed, 1 skipped, 0 failed**. The skip is the real Windows DPAPI
round trip (`session_key_isolation_test`), which is designed to skip anywhere except
Windows. That makes the suite **2,650** tests: the 2,648 of the Phase 6 closure, plus one
test each from the wiring split and the per-platform revenue test.

**Positive controls**, each seen red, then restored by byte copy and checked with `cmp`
(D-219):

| Control | Result |
|---|---|
| provider body replaced with `const UnavailableAttachmentSource()` | the structural wiring test goes red. On Linux the runtime half passes, which is exactly why the structural half exists |
| `attachmentSourceFor('android')` degraded to "unavailable" | both Android revenue-surface tests go red |

**Windows behaviour is unchanged.** The same font files are found, and on a Windows host
the runtime wiring test still requires a real picker directly.

**`tool/cloud/install_flutter.sh`** installs the pinned Flutter 3.44.9 on a Linux host. It
is idempotent, never changes the version, and precaches the material fonts. A cloud
environment's setup script can call it, so each session does not reinstall the toolchain
by hand. The project's Flutter version is unchanged.

## D-302 — The export document models, as built
**Date:** 2026-09-25 · **Status:** Implemented / Tested (Phase 7 Slice 3). This builds the
contract in D-299 and `ARCHITECTURE.md` §51.4. Five design choices are recorded here,
because each one decides what a document may say.

**1 · An analysis export shows what its screen section shows.**
- The Revenue Analysis and Expense & Department Analysis documents carry exactly the
  section's content:
  - the compared figures;
  - the trend at the planner's grain (monthly only for expenses, D-255);
  - the domain's Top N rankings, **with the exact Others** (D-258).
- They do not show a longer list the screen does not. The complete category list belongs
  to the P&L export, which is its canonical home.
- Adding a longer list here would mean an export stating a table the screen never showed.
  That would be a product decision nobody took.

**2 · A consolidated P&L export has the spec §10 shape.**
- It carries one statement per property, in business-unit id order, then the consolidated
  total.
- The per-property statements are `PropertyComparison.of(result)`. That is the canonical
  split (D-270) the Business Comparison screen already shows. Nothing reimplements it, and
  the model guard allows that one call and no other calculation.
- If the domain refuses the split, because the breakdown does not reconcile, the document
  carries the total alone and says so (`propertySplitShown`).
- When the breakdown does not reconcile, a statement's line lists are **absent**, exactly as
  the screen withholds them.

**3 · `ExportPermitted` is now a proof object.**
- It carries the action, report and scope it permits. Its constructor is library-private,
  so only `ExportAuthority.decide` can make one.
- Every builder requires one, and refuses a permit issued for:
  - a different report;
  - a different property;
  - a one-property scope against a consolidated result, or the other way round;
  - a consolidated scope that does not contain every property in the figures.
- So "authority first, before any model exists" (§51.3) is structural, not a convention.

**4 · One line order, in `domain/finance`.**
- `PnlLineOrder` holds the P&L category order: property, then category, by id. It moved
  from `pnl_presentation.dart`, whose two functions now delegate to it.
- The Windows and Android P&L screens and every export therefore read one rule. The
  screen's behaviour is unchanged; the full suite ran green over the move.

**5 · Labels come in through an interface; ids go no further.**
- `ExportLabels` resolves names for properties, categories, departments and sections, and
  the consolidated-scope wording. The surfaces implement it from the cached master graph,
  with the screen's own fallback sentences.
- A model stores **no** id. Business-unit ids are used only to look up labels and to check
  a permit.
- Freshness is copied as three separate fields: server-confirmed time or null; a
  confirmed server-has-newer flag; the device's generation time. The snapshot identity is
  deliberately **not** copied.
- A test walks every string in every document and proves that no id, snapshot id or
  capability code is present (§51.8).

## D-303 — The XLSX foundation, as built
**Date:** 2026-09-25 · **Status:** Implemented / Tested — Phase 7 Slice 4

**1 · The writer is packaging and nothing else.** `lib/core/export/xlsx/xlsx_writer.dart`
writes the parts a workbook needs — content types, relationships, a title-only core
properties part, the workbook, the styles and one part per sheet — and ZIPs them with
`archive` 4.2.0.
- It imports **no project code**, so it cannot know what a P&L, or even money, is.
- There are four cell types: text, number, date and blank. **There is no formula cell
  type**, so a workbook it writes is values only. A guard checks both facts.
- A number cell takes an exact decimal literal, validates it, and stores the text as it
  was given. It never parses the literal into a `double`.
- Output is deterministic: fixed ZIP timestamps and a fixed part order. The same model
  always gives the same bytes.
- The core properties part carries a title and **no author, device or creation time**
  (§51.8).

**2 · Money reaches a cell through one formatter.**
- `MoneyFormatter.decimalLiteral` turns exact paise into `-1234.05` by integer formatting.
  It sits beside the other money-to-text rules (D-271's "one place" rule).
- `MarginRatio.displayedFractionLiteral` rewrites the screen's rounded margin
  (`percentageScaled(2)`) as a fraction: 56.53% becomes `0.5653`. The workbook therefore
  cannot show a different margin from the screen.
- A margin that is not applicable is the text "N/A", never `0%`.

**3 · The number format is conventional, as D-294 allowed.** Money cells use
`"₹"#,##0.00;-"₹"#,##0.00`. Lakh/crore grouping in an Excel number format can only be
approximated with thresholds. It could not be shown to be correct for every negative value
the workbook can hold, so it was not used. The stored value is exact either way.

**4 · The P&L workbook.** `lib/core/export/workbook/pnl_workbook.dart` lays out a
`PnlExportDocument` as three sheets:
- **Summary:** the header block (scope, period, From/To as date cells, basis, inclusions,
  and the three freshness statements on separate rows), then one column per statement.
  Rows: Gross Sales, Less GST, Net Sales, Less Expenses, Operating Profit or Loss, the
  **result in words**, and the margin.
- **Revenue** and **Expenses:** the scope statement's category lines, with a frozen
  heading and an auto-filter.
- The **Total** row is the headline figure the domain computed. It is never a sum of the
  rows above it.
- A breakdown that does not reconcile is not shown, and the sheet says why.

**5 · One wording for both file formats.** `lib/core/export/export_wording.dart` holds the
report titles, the basis and inclusion sentences, the three freshness statements, the
screen's figure labels, the result words and the file names
(`KrishnaImperialMIS_<Report>_<Scope>_<from>_<to>.<ext>`). The PDF renderer (Slice 5)
reads the same file.

**6 · The layouts contain no arithmetic at all.** A guard over `lib/core/export` checks:
- no sum, paise read, parsing, clock, sort, storage, network, platform or feature import;
- no formula element;
- no binary arithmetic outside the writer, which may count columns;
- every numeric cell in a layout is built from one of the two literals above.

String text is removed before the check, so "Operating Profit / Loss" does not count as
arithmetic, but code inside an interpolation still does.

**7 · The three approved packages were pinned together.** `pdf: 3.13.1`,
`printing: 5.15.1` and `archive: 4.2.0` went into `pubspec.yaml` in this slice, and
`flutter pub get` ran once, under the cloud-efficiency instruction to pin once. `pdf` and
`printing` are not imported until Slices 5 and 7.
- The lockfile gained their transitive packages: barcode, bidi, path_parsing,
  pdf_widget_wrapper, petitparser, qr and xml.
- Flutter regenerated the Windows plugin registrant to include `printing`.
- The chart guard confirms that `fl_chart` is still the only charting package.

## D-304 — The PDF foundation, as built
**Date:** 2026-09-25 · **Status:** Implemented / Tested — Phase 7 Slice 5

**1 · The fonts are bundled, checked, and handed in.**
- Noto Sans **Regular** and **Bold**, the static TrueType files from the Noto project, ship
  under `assets/fonts/noto_sans/` with their **SIL Open Font License 1.1** (`OFL.txt`).
  These are the only two weights (D-295).
- `pubspec.yaml` declares exactly those three assets. A test holds the list.
- The renderer is **handed** the font bytes through `ExportPdfFonts`. It never loads an
  asset, opens a file or fetches anything. The delivery layer reads the bundle (Slices 6
  and 8).
- `ExportPdfFonts` refuses a font that cannot draw **₹** (U+20B9), so a figure can never
  print with a missing symbol. Both bundled fonts pass.

**2 · The P&L PDF.** `lib/core/export/pdf/pnl_pdf.dart` lays out a `PnlExportDocument` on
A4 portrait pages:
- An opening block: title, scope, period and range, basis, inclusions, and the three
  freshness statements on separate lines.
- One statement per `PnlExportStatement`: the screen's labels, the figure printed by
  `MoneyFormatter.standard` with Indian grouping, the result in words, and the D-224
  margin string or N/A.
- The revenue and expense category tables of the scope statement. A **Total** row carries
  the headline figure, never a sum of the rows.
- **Every page** has a header (product, report, scope, range, basis) and a footer (the
  synchronisation statement, the generation time, and page *n* of *N*). A table's heading
  row repeats on every page the table continues onto.
- A breakdown that does not reconcile, or a consolidated result the domain could not
  split, is withheld and the page says why, as the screen does.

**3 · Money is never shrunk or cut (D-286, on paper).**
- Amount columns take their natural width (`IntrinsicColumnWidth`); the text columns flex
  and wrap.
- There is no `FittedBox` and no scale-down. A guard refuses both in `lib/core/export`.
- A test prints a fifteen-digit amount and finds it whole, on the line with its label. A
  second test finds no text set smaller than the 7.5-point footer size.

**4 · No document-information dictionary.** The PDF carries no title, author, creator,
producer or creation date.
- The package fills the creation date from the device clock, and the renderer may not read
  the clock (§51.1).
- A document says nothing about who or which device made it beyond what its visible header
  states (§51.8). This matches the workbook (D-303).
- The package still stamps its own random file identifier (`/ID`). That identifier carries
  no information about the user, device or report.

**5 · Tests read the PDF the way a viewer does.** `test/support/pdf_text.dart` is a small
reader for the renderer's uncompressed output:
- it decodes each glyph code through the font's own `/ToUnicode` map;
- it places each word through the page's transformation matrices;
- it groups the words into lines.

Tests therefore compare the **printed text** with `MoneyFormatter`'s rendering of the
canonical `PnlResult`, which is the same string the screen shows. The reader refuses a
compressed PDF rather than silently finding nothing.

**6 · The guard over `lib/core/export` covers the PDF.**
- The PDF layer contains no arithmetic.
- It prints money only through `MoneyFormatter.standard.format`.
- It passes no metadata to `pw.Document`.
- It does not import `printing` or `file_selector`: delivery belongs to the feature layer.
- Only `pdf/` may import `package:pdf`, and only `xlsx/` may import `archive`.

Found while writing the guard: a `File(` token matched `ArchiveFile(`, the false-positive
shape D-069 records. It was dropped, because `File` needs `dart:io`, which is already
refused.

**Deliberately not in Slice 5:** saving, printing and sharing (Slices 6 to 8); the
analysis-report PDFs (Slice 9); a landscape layout, which only the Business Comparison
table may need (Slice 9).


## D-305 — The Export Centre and Save As, as built
**Date:** 2026-09-25 · **Status:** Implemented / Tested — Phase 7 Slice 6

**1 · An export is made from the report the screen holds.** The Export Centre reads the
P&L view and the shared dashboard exactly as their screens do, including the identity
check that keeps one person's report from another (D-231, D-267). It holds no report state,
shows no figure, and never starts a synchronisation. Changing the scope or period happens on
the report's own screen.

**2 · Authority is decided three times.** Before an action is offered, before the document
is built, and after the Save As dialog closes. The last check also compares the person and
their reading authority, so a capability lost while the dialog is open means nothing is
written.

**3 · No silent overwrite.** The person chooses the folder and name in the native dialog,
which asks before returning an existing file's name (the Windows save dialog's default
overwrite prompt, which `file_selector_windows` leaves in place). The only name that does not
pass through that question is one this code changes by adding a missing extension; if that
name is taken, the save is refused and the existing file is left untouched. The bytes are
written to a hidden file beside the target and renamed over it, so a failed write never
leaves a partial file under the report's name.

**4 · Save failures are stated in the person's terms:** the dialog could not open; the name
is taken; Windows refused the folder; the file is open in another program; any other write
failure. Cancelling is not an error.

**5 · `UTC` is resolved, not looked up.** The screens' fallback display zone is `UTC`,
which the bundled IANA data names `Etc/UTC`. `reportInstantLabel` now maps it to `tz.UTC`.
This fixes a latent throw on screen and a certain failure in export, and changes no other
zone.

## D-306 — Android sharing, as built: private cache, no permission, cleanup before the next share
**Date:** 2026-09-25 · **Status:** Implemented / Tested — Phase 7 Slice 8

**1 · One PDF.** The phone P&L shares the bytes the shared renderer makes for the P&L
document — the same bytes Windows saves and prints. There is no Android layout.

**2 · Authority.** Sharing is an export: view authority **and** `reports.export` for the
exact scope, decided before the icon appears, before the document is built, and again before
the sheet opens.

**3 · No storage permission.** `Printing.sharePdf` writes `<app cache>/share/<name>` and
grants the chosen app read access through its own FileProvider
(`${applicationId}.flutter.printing`). The manifest declares no storage or media permission.

**4 · Cleanup is ours, and happens before the next share.** `printing` marks the file only
`deleteOnExit`, which almost never runs on Android. It cannot be deleted when the sheet
opens, because the receiving app has not read it yet. So this app removes its own earlier
exports (`KrishnaImperialMIS_*.pdf`) from `<cache>/share/` before each share and when the
phone P&L opens. A file therefore stays in private cache until the next share or the next
visit to the P&L, or until Android clears the cache. `ARCHITECTURE.md` §51.7 said "removed
afterwards"; it is amended to say this.

**5 · What the share sheet can tell us.** Android returns nothing about what the person did
in the sheet, and `printing` returns `true` whenever it launched the chooser. A closed sheet
cannot be told from a completed share, so the app says only that the sheet opened. A sheet
that could not open is reported as that.

## D-307 — The analysis exports, as built
**Date:** 2026-09-25 · **Status:** Implemented / Tested — Phase 7 Slice 9

**1 · Laid out from the Slice 3 document models, and nothing else.** Revenue Analysis,
Expense & Department Analysis and Business Comparison each render their
`*ExportDocument`, which carries the canonical `DashboardView` figures. The layouts compute
nothing:
- a movement is the domain's own `MoneyComparisonAvailable.change`;
- a percentage is the domain's own rounded `displayTwoDecimals`, or "N/A" with its reason;
- a total is the headline figure the ranking reconciled to, never a sum of rows;
- Business Comparison keeps the domain's fixed property order.

The core export guard checks every layout file for arithmetic, sorting, parsing and
clocks.

**2 · Never zero for missing.**
- An unavailable comparison prints "Not available" in the previous, change and percentage
  columns, with the screen's sentence saying why.
- A trend point that could not be established is "Not available" with a note that it is not
  zero.
- A ranking that did not reconcile prints no line, only why.
- A genuine ₹0 stays a figure.

**3 · Portrait, not landscape.** §51.5 allowed landscape where a comparison table needs the
width. None does: the widest table has four amount columns at their natural width beside a
wrapping label, which fits A4 portrait. All four PDFs stay portrait, which also keeps
printing to one page format.

**4 · In Excel, a percentage change is the screen's text.** Money, previous figures and
movements are numeric cells. The percentage is written as the rounded text the screen shows
("+8.42%", or "N/A"). Writing it as a number would need a new exact-fraction literal on
`PercentChangeRatio`, which is a domain change this slice does not make. Margins stay
numeric percentages, as in the P&L.

**5 · One page furniture for every PDF.** The P&L PDF's header, footer, opening block and
table style moved into `lib/core/export/pdf/pdf_page.dart`, and all four PDFs use it. There
is now exactly one `pw.Document`, with no information dictionary. The P&L PDF tests pass
unchanged over the refactor.

**6 · The analysis wording is held to the screens by a test.** `lib/core/export` may not
import a feature file, so the analysis sentences live in `export_wording.dart` as well as in
the dashboard and Analytics presentation files. `export_wording_parity_test.dart` asserts
they are the same words.

**7 · Every report prints.** `exportPrintable` is true for all four reports on Windows, from
the same PDF bytes Save PDF writes. `reports.print` still decides.

## D-308 — The Windows runner holds a second apartment reference, so a print cannot freeze the next Save As
**Date:** 2026-09-28 · **Status:** Implemented / Tested (project-lead approval) — **a product defect
found by the Phase 7 Slice 10 acceptance, proven RED first**

**Symptom.** In the real `krishna_mis.exe`, opening the Windows print dialog once — printing or
cancelling — and then choosing Save PDF or Save Excel froze the application. The Save As dialog never
appeared and the window stopped responding. Saving without printing first always worked.

**Diagnosis, from the frozen process rather than from theory** (WinDbg, with the project lead's
agreement to diagnose before changing anything):
- the main thread was blocked in `file_selector`'s `IFileSaveDialog::Show`, inside
  `combase!MTAThreadWaitForCall`. The thread was in the multithreaded apartment, although the runner
  starts it single-threaded (`windows/runner/main.cpp`);
- a trace of every `CoInitializeEx` / `CoUninitialize` on that thread showed the Windows print stack
  (`WINSPOOL!GetCurrentNetworkId`) calling `CoUninitialize` without a matching initialize during the
  first print dialog. The next `CoInitializeEx(COINIT_MULTITHREADED)` on the thread, by the printer
  driver's `PrintConfig`, then **succeeded**, which is only possible once the thread's single
  apartment reference has gone;
- with no apartment of its own, the thread falls into the process's implicit multithreaded
  apartment. The file dialog is single-threaded only, so it is marshalled back to the same thread,
  which is waiting for it: a deadlock.

The defect is in Windows components the app does not own; neither `printing` nor `file_selector`
misuses COM.

**Decision.** The runner takes **one extra** single-threaded apartment reference at startup, with the
reason written beside it. The stray release drops the count from two to one, and the thread stays
single-threaded. No Dart change, no plugin fork, no export or finance change.

**Proven both ways in the real executable** (`p7-windows-repro`):

| Runner | Scenario | Result |
|---|---|---|
| committed (one reference) | print dialog, cancel, then Save As | **frozen** — reproduced four times |
| two references | print dialog ×1, ×2, ×3 (cancelled), then Save As | saved |
| two references | print to PDF ×1, ×2, ×3, then Save As | saved |

The stray release happens once, not once per print: three print dialogs in a row leave the thread
single-threaded.

**Guard.** `test/app/windows_runner_apartment_test.dart` asserts the runner takes exactly two
single-threaded references before the engine starts, never joins the multithreaded apartment, and
names D-308. It fails on the committed runner. The behaviour itself is proven only in the real
executable, by the repro phase above.

**Not balanced at exit, deliberately.** The process ends after its message loop; the existing single
`CoUninitialize` is unchanged.

## D-309 — Print decides authority again when Print is pressed
**Date:** 2026-09-28 · **Status:** Implemented / Tested (project-lead ruling on the residue) —
**a product defect found by the Phase 7 Slice 10 acceptance, proven RED first**

**Symptom.** In the real `krishna_mis.exe`, the accountant opened the print dialog for the P&L. While
the dialog was open, `reports.print` was withdrawn from the role. The person then pressed Print, and
the report printed. The result was `ExportActionHandedOver` and the printed file held the document.
Save already re-checked authority after its dialog closes (Slice 6). Print handed the bytes over with
no re-check.

**Why the check belongs inside `onLayout`.** `printing` asks for the document only after the person
presses Print: `Printing.layoutPdf` calls `onLayout` from the native print job. That is the last
moment the application can decline, so the check sits there. Two ways to decline were read in the
plugin source (`printing` 5.15.1, `windows/printing.cpp`, `print_job.cpp`):

| `onLayout` | What the plugin does | Chosen? |
|---|---|---|
| throws | deletes the job and never completes the Dart future; Print would stay "running" for ever | no |
| returns no bytes | starts the document, fails to load it, `AbortDoc`, reports a failed completion | **yes** |

**Decision.**
- `ExportPrinter` gains `layout`, and the dialog is given `layout()`, not the bytes directly.
- `exportPrintLayout(bytes, stillPermitted)` returns the renderer's bytes unchanged while the action
  is still permitted, and no bytes once it is not.
- The controller reports `ExportActionAbandoned` whenever authority has gone by the time the dialog
  returns, whatever the plugin says.

**The residue, accepted by the project lead.** With the virtual printer *Microsoft Print to PDF*, the
driver asks where to save and creates that file at `StartDoc`, which runs before the document can be
checked. When the job is then aborted the file is left **empty (0 bytes)**. It holds no report
content. A physical printer prints nothing. Removing the prompt and the empty file would need a fork
of the plugin's Windows code, a dependency change the project lead did not ask for. The acceptance
rule is therefore **no report content reaches any file**: the file is absent or empty.

**Proven.**
- Host: a fake dialog that loses the capability before asking for the document gets no bytes, and
  the outcome reads "Your access changed". With the controller's layout ignoring authority, that
  test turns **red**. A second test keeps the document flowing when the capability is kept.
- Real executable (`p7-windows-authority`): `ExportActionAbandoned`, and `lost-during-print.pdf` is
  0 bytes. Before the fix it was `ExportActionHandedOver` with the report inside.

**Guard.** `export_feature_guard_test.dart` now requires `onLayout` to return `layout()`, the layout
to be `stillPermitted() ? bytes : Uint8List(0)`, and the controller to pass
`exportPrintLayout(rendered.bytes, stillPermitted)`. The renderer's bytes are still the only
document the dialog can receive.

## D-310 — A shared PDF goes when its person signs out or another person signs in
**Date:** 2026-09-28 · **Status:** Implemented / Tested (project-lead decision) — security and
privacy hygiene, not a new feature

**Context.** The Slice 10 acceptance found that the P&L PDF shared from the phone stays in the app's
private cache. It survives leaving and reopening Reports, because the phone shell keeps that tab
alive and the cleanup in D-306 runs when the share control is first built. It also survives
sign-out. The file is derived management financial data.

**Decision (project lead).**
- The cleanup before each new share stays.
- The shared PDF is **also** removed when the person signs out, or when the authenticated person
  changes (a user switch, or a session ending).
- Leaving the Reports tab, a tab kept alive, or a widget that does not rebuild does **not** need
  to trigger cleanup.

**How.** `sharedExportCleanupProvider` watches only who is signed in (`sessionProvider` → `userId`).
When the person changes it runs `removeEarlierShares` on the private cache, and the application
root keeps it alive.
- It runs after the change and never inside `signOut`, so a cache that cannot be reached never
  blocks signing out.
- It touches only this app's `KrishnaImperialMIS_*.pdf` files in `<cache>/share/`.
- It uses no new permission, no public storage, and no report or reporting-cache data.
- A refresh for the same person removes nothing. A change from nobody to somebody (sign-in or
  session restore) also runs, which is harmless and closes the case of a restart between two
  people.

**Found while building it.** `exportShareCacheRootProvider` was retried by Riverpod 3's default
backoff when its future failed, so anything awaiting it, including a share, would wait instead of
failing. It is now not retried.

**Proven.** Six host tests:
- sign-out removes the file;
- a user switch removes the previous person's file;
- the same person keeps it;
- unrelated cache content, including a `KrishnaImperialMIS_` text file and a PDF outside `share/`,
  is untouched;
- an unreachable cache does not block sign-out;
- the next-share cleanup still works.

With the listener disabled, the sign-out and switch tests turn **red**.

---

# Phase 7 — Export, PDF & Printing: closure (2026-09-28)

## D-311 — Phase 7 is closed, and this is what each of its decisions finally says
**Date:** 2026-09-28 · **Status:** Accepted (project-lead approval: Slice 10 accepted, U.4 manual
review PASS)

Phase 7 closes at Slice 11. Slice 11 is documentation and closure gates only: no product code, no
dependency, no schema, no migration and no server change. This entry gives the final disposition of
every Phase 7 decision. **No earlier entry is rewritten or renumbered.**

### Final dispositions

| Decision | Final state |
|---|---|
| D-290 | Final. Windows exports four reports as PDF and Excel; Android shares the P&L PDF. No Overview export, chart image or screenshot |
| D-291 | Final. Export = view authority ∩ `reports.export`; print = view authority ∩ `reports.print`, for the exact scope, decided on the client by design. The server's reporting authorization remains the confidentiality boundary. `reports.export` / `reports.print` stay on D-139's exemption list |
| D-292 | Final. Role bundles unchanged; the Manager is offered no export or print, proven in the real app |
| D-293 | Final. Android: the P&L PDF through the system share sheet, from the private cache, with no new permission. No Android Excel, no Android direct printing, no Android analysis export |
| D-294 | Final. Money cells numeric, from integer paise, no formulas, no raw-paise column; conventional currency format (Excel may show lakh grouping by locale) |
| D-295 | Final. Noto Sans Regular and Bold bundled with `OFL.txt`; nothing fetched at run time |
| D-296 | Final. Transaction-list and drill-down export deferred; not built |
| D-297 | Final. The Windows Reports destination is the Export Centre and holds no report state |
| D-298 | Final. `pdf` 3.13.1, `printing` 5.15.1, `archive` 4.2.0 pinned; `excel` and `share_plus` rejected. PDFium is downloaded at Windows **build** time (Phase 9 reproducibility item) |
| D-299 | Final. One document model, two renderers; printing sends the same PDF bytes; freshness is three separate statements |
| D-300 | Final. The schema document's capability catalogue matches the shipped codes |
| D-301 | Final. The host suite runs on a Linux cloud host as well as on Windows |
| D-302 … D-307 | Final: the models, XLSX writer, PDF renderer, Export Centre, Android share and analysis exports as built |
| **D-308** | Final. The Windows runner holds a second COM apartment reference so a print can never freeze a later Save As |
| **D-309** | Final. Print decides authority again when Print is pressed. With Microsoft Print to PDF, an aborted job may leave an empty 0-byte file; the project lead accepted that (no report content reaches any file) |
| **D-310** | Final. A shared PDF is removed at sign-out and when another person signs in; leaving the Reports tab is not a trigger |

### What Phase 7 did not add, verified at closure against `b35611a` (Phase 6 closure)

- No change under `supabase/` (no migration, no RPC).
- No change under `lib/data/local` (Drift **v21**), and none in the reporting data layer or reporting
  cache.
- No Owner Accounts export, no transaction-list export, no Android Excel and no Android direct
  printing. The phone P&L imports only the share action.

### Carry-forwards

| Class | Items |
|---|---|
| **Phase 8** | Export rendering performance, measured separately from reporting (§51.9, not measured in Phase 7). `may_read_expense` per-row cost (D-186). The `org_id`-leading local expense index (D-223). A review of other `FutureProvider`s for Riverpod 3's default retry-on-error (found in D-310). Making a missed tap fatal across the host suite. The D-248 diagnostic |
| **Phase 9** | Production Supabase configuration; the D-146 fresh-branch migration replay; Android release signing, AAB, Play; Windows installer; a reproducible Windows build without the PDFium download (D-298); launching the release executable once D-247's installation is resolved; a physical printer on the target machine |
| **Product lead** | The production 50:50 ownership effective-from date; disposal of the D-247 forensic database; the stale Administration placeholder copy; whether a transaction-list export is wanted (D-296); optionally, removing the Print-to-PDF empty-file residue, which needs a `printing` plugin fork (D-309) |
| **Future analytics / Owner Accounts** | Unchanged from D-289 (category shares, per-category comparison, finalized Owner Statements, …) |

**Open defects at closure: none.**

---

# Phase 8 — Performance, Hardening & Recovery (2026-09-29)

Phase 7 closed at `ba1aed7`. Phase 8 was scoped by a read-only audit of the shipped code and
of `krishna-mis-dev`. The project lead accepted the audit and ruled on its six questions and
two further items (D1 … D8). D-312 records those rulings as given. D-313 … D-316 record what
Slice 1 established on the strength of them.

**The principle every entry below serves:** Phase 8 improves robustness and performance
**without changing an approved financial semantic, an authority rule or a V1 feature**.
Nothing is optimised because it looks faster; it is optimised because a measurement against
an approved threshold says so.

## D-312 — The project lead's Phase 8 rulings (D1 … D8)
**Date:** 2026-09-29 · **Status:** Accepted (project-lead decisions)

**D1 · Scale envelope.** Neither historical estimate (D-007's "order of 10⁵ rows per year",
D-178's "a few thousand contributions a year") is a business forecast. Phase 8 validates
against three engineering volumes:

| Class | Volume |
|---|---|
| **CURRENT** | the actual development dataset at the time of measurement |
| **SCALE** | 100,000 financial contribution rows per year |
| **STRESS** | 500,000 financial contribution rows, about five years at the scale envelope |

These are validation volumes, not a forecast of hotel activity. Every benchmark names its
dataset, and numbers from different hardware are never compared as if equivalent.

**D2 · Thresholds.** The binding intervention threshold stays `ARCHITECTURE.md` §9: a
one-month canonical P&L above **400 ms on the reference Android device**. Exports of a
normal, realistic report: **Windows < 1 s, Galaxy A06 < 2 s**, measured per stage
(canonical result already available · document-model creation · XLSX rendering · PDF
rendering · file write) and excluding every dialog and human wait. A deliberately large
stress export is reported separately and is not automatically a defect.

**D3 · Where D-186 is measured.** `krishna-mis-dev` for current real data and planner
evidence; a **local PostgreSQL** for synthetic SCALE and STRESS data. The shared dev project
is **not** populated with hundreds of thousands of synthetic rows. The local harness matches
production PostgreSQL semantics, extensions and configuration as closely as practical, and a
local timing is never presented as a Supabase production timing. D-186 is measured with
`EXPLAIN (ANALYZE, BUFFERS)`, representative authority principals, one month, one financial
year and both properties with breakdown, five warm runs, median and spread, and
function-call evidence where PostgreSQL supports it. `may_read_expense` changes only if a
measurement justifies it, and any authorisation rewrite needs the complete allow/deny matrix
before acceptance.

**D4 · Damaged local database recovery is built in Phase 8.** `ARCHITECTURE.md` §8.2 promises
it and the shipped application stops on a dead-end screen (D-316). Binding rules:

* never reset automatically, and never silently discard local data;
* state plainly that unsynced local work may be unrecoverable;
* require explicit destructive confirmation, **typed** for the final reset;
* prefer quarantining or renaming the damaged database to deleting its bytes, preserved for
  forensic or manual recovery where practical;
* create a fresh local database only after confirmation;
* re-download only what the current authenticated principal is authorised to receive, never
  another user's cached data, respecting D-070 and D-074;
* a failure during recovery is itself recoverable and retryable;
* the D-247 forensic database is not touched unless separately scoped and approved;
* choices are plain language — *Try again*, and where the condition qualifies *Reset local
  data and download again* — and raw SQLite or Drift text is never the primary message;
* the exact behaviour for pending, unsynced, rejected and conflicted work is recorded;
* if quarantine conflicts with encryption or key handling, the limitation is reported rather
  than security weakened.

**D5 · Paging.** Keyset paging is **not** implemented to make old documentation true. Slice 1
corrects the documentation to the implementation — LIMIT/OFFSET (D-314). Slice 4 fixes the
expense ledger's ordering independently: `business_date`, `captured_at`, then a stable id, in
the current list's direction. That ordering fix is a correctness requirement and needs no
threshold breach. Keyset paging itself is built only if profiling at the approved scale shows
OFFSET is materially problematic.

**D6 · The D-223 index stays.** No index is added because D-223 existed, the existing unused
index is not dropped, and Drift v22 is not created to remove it. The record states that the
original candidate path is no longer the production reporting path (D-315). Removal is
reconsidered only if measurement proves a meaningful write or storage cost.

**D7 · Retry and hang hardening.** Riverpod retries are **not** disabled globally. Each
provider is classified by its semantics, and a user-triggered one-shot action must not appear
to hang because a provider it awaits is backing off before the controller marks the action
as started. High-priority candidates: `pnlScopeOptionsProvider`, `businessDayRulesProvider`,
`exportPdfFontsProvider`, and `masterGraphProvider` where a user action awaits it. For each:
the current retry behaviour is established from the Riverpod package source, the failure is
reproduced, the right behaviour is defined, regression evidence is added, and the smallest
semantic correction is made. A P&L or dashboard sync must not look like "nothing started"
while its prerequisites are awaited. **This is not claimed to fix D-248**, which stays a
hypothesis, and the D-248 diagnostic stays in place throughout Phase 8.

**D8 · Missed taps.** No global switch is flipped blindly. First the full-suite baseline; then
fatal missed taps enabled experimentally; then every newly failing test listed and classified
as a real missed interaction or a harness artefact; then a deliberate migration. The final
state is global fatal missed taps, with an opt-out only where it is semantically justified and
documented.

**The plan, approved:** nine slices — (1) governance and baseline harnesses, (2) D-186 server
profiling, (3) retry and hang hardening, (4) local expense-ledger profiling and deterministic
ordering, (5) global missed-tap hardening, (6) export performance, (7) stress and recovery,
including damaged-database recovery, (8) Windows, emulator and Galaxy A06 acceptance and
regression, (9) closure. D-223 is disposed of in Slice 1 and Slice 4 without a schema change
unless later measurement overturns the audit.

## D-313 — How Phase 8 measures: environments, datasets, report format, thresholds
**Date:** 2026-09-29 · **Status:** Accepted — the measurement contract every Phase 8 slice
reports against (`ARCHITECTURE.md` §52)

**Environments.** A result is valid only in the environment it names.

| Id | Environment | Timing claims allowed |
|---|---|---|
| **E-DEV** | `krishna-mis-dev` (`loratzmactetjbqolwri`), Supabase, Mumbai. PostgreSQL 17.6; `jit` off; `shared_buffers` 224 MB; `work_mem` 2184 kB; `track_functions` none; extensions btree_gist 1.7, pg_stat_statements 1.11, pgcrypto 1.3, supabase_vault 0.3.1, uuid-ossp 1.1 (read 2026-09-28) | server-side plan timings for CURRENT only |
| **E-LOCALPG** | a disposable PostgreSQL 17 cluster the harness initialises in a scratch directory, on its own port, loopback-only, holding only synthetic data | server-side plan timings for SCALE and STRESS, labelled local |
| **E-WIN** | this Windows 11 workstation, real `krishna_mis.exe` or the Windows integration harness, real encrypted database | Windows timings |
| **E-A06** | Galaxy A06 SM-A066B, Android 16 / API 36, over USB only (D-288) — the **reference Android device** for §9 | the binding Android timings |
| **E-EMU** | `Pixel_8` emulator, x86_64 | indicative only; never used to pass or fail §9 |
| **E-HOST** | `flutter test` on the host | counts, plans and correctness; **no timing is a verdict** |

**E-LOCALPG never touches the machine's existing PostgreSQL service** (`postgresql-x64-17`,
17.11, already running) or any database in it: it initialises its own cluster, so no
credential for that service is needed or requested. Supabase-specific behaviour the harness
cannot reproduce exactly — the `auth.uid()` claim path, the Supabase role set, the PostgREST
transaction wrapper — is emulated by a documented minimal shim, and each deviation is listed
beside the result.

**Dataset classes.** A *financial contribution row* is one row of
`revenue_period_contributions` (one revenue component) or `expense_period_contributions`
(one expense period allocation) — the grain every report sums (D-060, D-157).

| Class | Definition | Where it may live |
|---|---|---|
| **CURRENT** | the dev dataset as it stands; each report records the exact row counts it measured against, and how many of them are voided | E-DEV, and copies of its shape on devices |
| **SCALE** | 100,000 contribution rows in one financial year | E-LOCALPG; device caches |
| **STRESS** | 500,000 contribution rows over five financial years | E-LOCALPG; on a device only as a stated worst case, since local retention is the current and previous financial year (D-170) |

CURRENT at the time of this record (2026-09-28, E-DEV): 2,150 expenses, 2,365 expense
allocations, 2,475 expense period allocations, 2,601 revenue entries and 2,613 revenue
components — most of them voided acceptance fixtures.

Synthetic data is generated by a deterministic, seeded generator whose parameters are part of
the result: the revenue/expense split (default 50/50), the number of properties (two), the
share of voided documents, and the share of cross-period and cross-property splits. It carries
no real name, amount or business fact (§32), is marked as synthetic, and never reaches
`krishna-mis-dev`.

**Measurement rules.**
* Measure first. No change is proposed without a before figure, a threshold and a workload.
* Warm figures are at least five runs after one discarded warm-up; the warm-up is reported,
  never averaged in. Report median, minimum and maximum, and p90 when there are ten or more
  runs.
* Cold figures are reported separately and say what "cold" means in that environment.
* Build mode is stated (debug, profile, release). A debug-build Dart timing is labelled as one.
* Host tests assert **counts, plans and results**, never wall-clock budgets, because a timing
  assertion on a shared machine fails for reasons unrelated to the code (D-152, D-075).
* Human and dialog time is never part of a renderer's figure (D2).

**Report format.** Every Phase 8 measurement is recorded as:

```
        Id · date · commit · environment · build mode
        dataset class + exact row counts (and voided share)
        principal (by capability set, never by role name)
        workload · runs (warm-up discarded) · median · min · max · p90
        threshold · verdict: inside / outside / no threshold
        plan or stage breakdown where one exists · artefact location
```

Raw plans and timings stay out of the repository unless sanitised; the verdict and summary go
in `PROJECT_STATUS.md`.

**Thresholds.**

| Id | Threshold | Source |
|---|---|---|
| **T1** | one-month canonical P&L ≤ **400 ms** on E-A06; local database ≤ **500 MB** | §9, D2 |
| **T2** | normal export, total of model + render + write: E-WIN **< 1 s**, E-A06 **< 2 s** | D2 |
| **T3** | a stress export is reported, not automatically a defect | D2 |

**No other threshold is approved.** Where a slice measures a path T1–T3 do not cover — the
server execution of `reporting_primitives` and `reporting_snapshot` (D-186), a ledger page at
a deep offset (D5), the reporting sync — it uses 400 ms as a **reporting line**, records the
result, and acts only on a finding the project lead has ruled on. A figure outside a reporting
line is a question, not a licence to optimise.

**Existing baselines**, restated so later slices compare like with like: see *Phase 8 Slice 1*
in `PROJECT_STATUS.md`. None of them was measured at SCALE or STRESS.

## D-314 — Every ledger pages with LIMIT/OFFSET, and the documents now say so
**Date:** 2026-09-29 · **Status:** Implemented (documentation and code comments only)

**The disagreement.** `ARCHITECTURE.md` §9 said ledgers use keyset pagination and "never
OFFSET"; `PROJECT_STATUS.md` twice recorded the Windows ledger's "keyset paging" as built and
tested; `RELEASE_CHECKLIST.md` §B asked for "keyset pagination"; and three code comments
repeated it. **No keyset paging exists anywhere.** The expense, revenue and owner ledgers all
use `LIMIT … OFFSET`, which the `windows-ledger` phase proves through the repository with
`limit: 2, offset: 0` and `offset: 2`.

**Decision (D5).** The documents and comments are corrected to LIMIT/OFFSET. Nothing else
changes in Slice 1. The applied history is not rewritten: the earlier `PROJECT_STATUS.md`
paragraphs keep their text with a correction beside them.

**`ARCHITECTURE.md` §9 carried a second inaccuracy, corrected with it.** It said the
`org_id`-led reporting indexes exist "both locally and in Postgres". On the server they do. On
a device they cannot help: a device holds one organisation, so no local query constrains
`org_id` (D-223, D-315), and the local reporting cache is indexed by owner, property and
period instead.

**Two findings for Slice 4, recorded and not fixed here.**

1. **The expense ledger's order is not total.** `ExpenseRepository.query` orders by
   `business_date DESC, captured_at DESC` with no id tie-break. Two documents captured in the
   same instant have no defined order, so a page boundary can show one twice and skip another
   — the hazard D-121 closed for revenue. Slice 4 adds the stable id (D5).
2. **The Windows expense ledger shows one page.** `filteredExpensesProvider` calls
   `query(filter)` with the default `limit: 100, offset: 0` and nothing asks for a second
   page, so a filter matching more than 100 documents shows the newest 100 and says nothing
   about the rest. The sync-state filter is then applied to those 100 rows in Dart, so it can
   show fewer. The revenue ledger pages (`revenuePageSize = 50`, `revenueHasMoreProvider`).
   Whether Slice 4 adds a next-page control on the revenue pattern is a change to what the
   ledger shows, so it is **raised for the project lead** rather than decided here.

## D-315 — D-223 is disposed of: the index is on a path production no longer takes
**Date:** 2026-09-29 · **Status:** Accepted (D6) — no schema change

**What D-223 described.** `ix_expense_contributions_reporting` on
`expense_period_allocations (org_id, pnl_period_key, business_unit_id)` leads with `org_id`,
which no local query constrains, so the local reporting query scanned instead (Phase 5
Slice 3, measured at 0.07 ms on a two-year fixture).

**What the audit found.** That index serves only `ExpenseRepository.contributions`,
`contributionTotals` and `contributionTotalsByCategory`, which are called only by
`DriftReportingSource`. **Production does not use `DriftReportingSource`**:
`localReportingSourceProvider` builds `CachedReportingSource` over the canonical reporting
cache (Phase 5 Slice 4, D-181), whose indexes all lead with the owner, the property and the
period. The production P&L therefore never reads the path D-223 was about.

**Decision.** Leave the index in place, add none, and create no Drift v22 for it (D6). If a
Slice 4 or Slice 7 measurement shows a meaningful write or storage cost on
`expense_period_allocations`, removal is reconsidered then. The real local question — the
expense ledger's indexes, hydration and ordering — is Slice 4's and is measured there.

## D-316 — The damaged-database recovery flow is promised and not built
**Date:** 2026-09-29 · **Status:** Recorded — built in Slice 7 under D4

**The promise.** `ARCHITECTURE.md` §8.2: when the key is unavailable the database cannot be
opened, and "the app detects the failure, explains it in plain language, and offers to reset
the local store and re-download from the server".

**What ships.** `bootstrap()` opens the encrypted database and throws
`EncryptedDatabaseUnreadable` when the key will not open it. `main()` catches **any** start-up
error and shows `_StartupFailureApp`: a fixed sentence and then the raw exception as
`SelectableText('$error')`. There is no *Try again*, no reset, no quarantine, and no test that
drives the path (`EncryptedDatabaseUnreadable` is named in no test). The raw text can include
a local file path.

This is the D-072 and D-077 shape: a documented behaviour with nothing behind it, found by
reading the code rather than the plan. §8.2 now says so beside the promise.

**Open design points for Slice 7, stated now so they are decided rather than discovered:**
* **What "damaged" means.** A missing key, a key that does not open the file, a file that
  opens but fails its integrity or migration step, and a failure that is not the database at
  all (for example a refused configuration) are different conditions. Only some of them
  qualify for *Reset local data and download again*; a configuration refusal never does.
* **Quarantine and the key.** A quarantined file is still ciphertext. If the key is lost, the
  bytes are kept but cannot be read by this application. If the key still exists, keeping the
  file useful for recovery means keeping its key too, under an identifier no normal start-up
  reads — or accepting that quarantine preserves bytes only. Which is achievable without
  weakening key handling (D-022, D-036, D-246, D-249) is a Slice 7 finding.
* **Unsent work.** Every pending, failed, rejected or conflicted outbox entry lives in the
  damaged database. The flow must count what it can and say plainly what will be lost, and
  cannot count what it cannot open.

## D-317 — The Expense ledger pages, and every filter runs before the page is cut
**Date:** 2026-09-29 · **Status:** Accepted (project-lead ruling) — **binding on Phase 8
Slice 4; not implemented in Slice 2**

**What was found (D-314).** The Windows Expense ledger asks for the newest 100 documents
and nothing more: there is no next page and no *load more*, nothing tells the reader that
older matching documents exist, and the sync-state filter is applied in Dart to those 100
rows — so it can show far fewer than 100 while older matching documents are never asked
for at all.

**The ruling.** This is not acceptable for V1 hardening, and Slice 4 corrects it:

1. The Expense ledger gains explicit pagination — a *load more* in the Revenue ledger's
   pattern (`revenuePageSize`, `revenueHasMoreProvider`) wherever that fits the Expense
   ledger's architecture.
2. **Raising the hard-coded limit is not a fix** and is not acceptable.
3. **Every active filter is applied in the database before the page is cut**: date range,
   property and scope, category and the other supported filters, search, and sync state.
4. The order is total and deterministic: `business_date`, then `captured_at`, then a stable
   id, in the direction that keeps today's newest-first reading.
5. Paging starts as LIMIT/OFFSET.
6. Keyset paging is built **only if** Slice 4's profiling at the approved dataset envelope
   (D-312 D1, D-313) shows OFFSET is materially problematic.
7. The ledger says clearly when more documents are available.
8. Changing a filter, the search or the scope resets the paging.
9. Loading another page never duplicates a row, skips a row, or reorders rows already on
   screen.

**Scope.** This is ledger correctness and usability hardening. It is not evidence that
Phase 8 should widen into general feature work, and it adds no new filter, column or
screen. It supersedes the "raised for the project lead" note in D-314 finding 2.

## D-318 — D-186 measured: the per-row expense predicate breaks the reporting sync at SCALE
**Date:** 2026-09-29 · **Status:** Measured (Phase 8 Slice 2). **Intervention warranted —
nothing changed.** Work stopped before any authorisation change, as D-312 (D3) requires; the
redesign below **awaits the project lead's approval**.

**What was measured.** `public.may_read_expense(uuid)` — the D-169 document predicate — on
every reporting path that evaluates it: `expense_period_contributions`, `reporting_primitives`,
`reporting_snapshot`, the `expense_period_allocations` RLS policy and `expense_document`.
Principals by capability set: Owner (unscoped), Crystal Canopy Manager, Crystal Canopy
Accountant; locally also the `expense.view.own` principal. EXPLAIN (ANALYZE, BUFFERS), one
discarded warm-up, five measured runs unless stated, and the exact number of calls each
workload made to each function (`pg_stat_xact_user_functions`, per transaction). Tooling and
harness: D-319.

### The finding

Cost is **linear in the rows the predicate is evaluated on — about 0.335 ms per expense row on
krishna-mis-dev** — and the predicate is evaluated on far more rows than any report needs:

| Rows it is evaluated on | Evidence |
|---|---|
| **every voided and unnumbered row in range** — `voided_at`/`txn_number` live on `expenses`, so they are applied after the security-barrier view's own qual has run at the scan | dev, Jan 2027, Crystal Canopy: **434 calls for 0 live rows** |
| **the other property's rows** in `reporting_primitives` — the requested property is applied by joining the `authority` CTE, not as a scan predicate | dev: a Crystal-Canopy-only month makes **664** calls; the view filtered by property needs 434 |
| **a refused request, in full** — a scoped reader's consolidated request is refused per property, but the expense scan still runs | dev, CCR Manager, consolidated FY: refused, **2,247 calls, 780 ms** |
| **the whole history on a delta pull** — `reporting_snapshot`'s `change_seq` bound is applied after the predicate, and there is no date bound | dev: a 28-row delta makes **2,475** calls (895 ms) against 1,044 ms for the full pull |

Without the authorisation layer the same reads take **0.18–0.66 ms on dev**: the predicate is
over 99.9% of the cost. Per call on dev: `has_capability` ≈ 0.23 ms, `current_org_id` ≈
0.14 ms, `may_read_expense`'s own body ≈ 0.11 ms — three nested SECURITY DEFINER SQL functions,
each with `SET search_path`, none of them inlinable. The revenue projection has the same shape
with one level (`has_capability` per component, ≈ 0.08 ms).

### Dev, CURRENT (2,150 expenses · 2,475 expense period rows, 97% voided · 2,613 revenue components)

Median ms (min–max), five warm runs. Workloads: `epc` = the view directly, one property or
both with breakdown; `rp` = `reporting_primitives`; `rs` = `reporting_snapshot`; month =
Jan 2027 (the busiest, 664 rows); FY = 2026-27.

| Workload | Owner | CCR Manager | Accountant | `may_read_expense` calls |
|---|---|---|---|---|
| epc, month, one property | 145.0 (144.8–149.0) | 151.2 (148.5–151.5) | 148.6 (146.0–149.8) | 434 |
| epc, FY, one property | 579.0 (576.8–583.3) | 593.2 (589.5–598.2) | 589.1 (586.1–591.8) | 1,730 |
| epc, FY, both, breakdown | 758.8 (755.0–759.8) | 786.6 (773.4–793.8) | 763.6 (759.7–784.8) | 2,247 |
| rp, month, one property | 232.7 (229.3–239.2) | 229.8 (228.0–232.5) | 229.2 (227.9–232.4) | 664 |
| rp, FY, one property | 769.7 (768.6–795.9) | 778.5 (776.4–789.0) | 771.5 (766.4–772.3) | 2,247 |
| rp, month, both, breakdown | 234.6 (231.4–236.1) | 230.0 (228.9–264.1) *refused* | — | 664 |
| rp, FY, both, breakdown | 782.5 (770.7–813.3) | 780.2 (769.1–822.2) *refused* | 770.2 (766.5–778.0) *refused* | 2,247 |
| rs, full | 1,044.1 (1,039.8–1,113.9) | 1,034.1 (1,031.1–1,043.8) | 1,025.1 (1,008.6–1,031.3) | 2,475 |
| rs, delta (200 generations) | 895.2 (890.2–904.9) | 917.5 (913.8–928.3) | 894.8 (893.8–896.7) | 2,475 |
| RLS read, month | 246.7 (223.3–351.2) | 150.0 (148.6–152.3) | 148.3 (147.6–150.5) | 664 / 434 / 434 |
| `expense_document`, month | 238.5 (233.0–255.1) | 230.0 (228.8–230.9) | 229.2 (228.2–232.6) | 656 |
| *no authorisation, session role* | month 0.18 · FY one property 0.61 · FY both 0.66 | | | 0 |

Shared buffers all hits, no reads (e.g. `rs` full 31,250). **Nothing at CURRENT crosses 8 s**;
the largest is the full sync at ~1.04 s.

### Local SCALE and STRESS (E-LOCALPG — indicative timings, exact call counts)

SCALE = 99,869 contribution rows in FY 2026-27 (49,869 expense, 50,000 revenue, 10% voided).
STRESS = 499,975 over FY 2022-23 … 2026-27. The local per-call cost ranged from 0.29 ms (a
quiet run — dev is 0.335 ms) to ~0.9 ms under host load, so timings for identical call counts
vary up to ~3× between runs. The **call counts** are the portable evidence, and the
**projection** multiplies them by dev's measured per-call costs (0.335 ms per expense row,
0.082 ms per revenue component).

| Workload | SCALE calls | SCALE local, CCR Mgr / Acct | STRESS calls | STRESS local, CCR Mgr | Projected on dev-class hardware, SCALE and STRESS |
|---|---|---|---|---|---|
| rp, month, one property | 4,205 | 2,560 / 2,883 ms | 4,205 | 1,414 ms | ~1.7 s (both) |
| rp, FY, one property | 49,514 | 35.4 / 38.8 s | 49,514 | 15.6 s | **~20.5 s (both) — over 8 s** |
| rs, delta | 49,869 | 36.4 / 28.0 s | 249,975 | **136.9 s** | **~20.8 s / ~104 s — over 8 s** |
| rs, full | 49,869 | 31.5 / 31.4 s | 249,975 | **fails** (below) | ~20.8 s / fails |
| epc, month, one property | 2,829 | 1.8 / 1.4 s | 2,829 | 0.92 s | ~0.95 s |

Owner at SCALE: same call counts, timings recorded but noisy (the run overlapped two host test
runs). Owner at STRESS, a quiet run: `rp` one-property month **1,348 ms** (1,283–1,679), `rp` FY
**15,959 ms** (one run), `epc` FY both with breakdown **16,023 ms** (one run) — the same call
counts as the Manager.

**Two failures, demonstrated, not projected:**

1. **The 8-second timeout.** krishna-mis-dev gives `authenticated` `statement_timeout = 8s`.
   At SCALE, as the CCR Manager with that timeout: a one-month report returns; the
   **financial-year report and a 200-generation delta `reporting_snapshot` are cancelled**
   (`canceling statement due to statement timeout` in `has_capability` ← `may_read_expense`).
   The device's reporting cache is filled only by `reporting_snapshot`, so a device on a
   dataset of this size **cannot synchronise its P&L** and reports "not downloaded".
2. **The 256 MB JSON ceiling.** At STRESS, the Owner's first full `reporting_snapshot` fails
   before any timeout: `total size of jsonb object elements exceeds the maximum of 268435455
   bytes`. The transport has no date bound, so a fresh install asks for the entire history in
   one JSON document.

**Against the thresholds.** T1 (one-month P&L ≤ 400 ms on the Galaxy A06) is measured on the
device's local engine and is not the server path. D-186 threatens the reporting budget
**functionally, not by latency**: the transport that fills the local cache stops working. At the
dev-class per-call cost (≈0.42 ms per expense-and-revenue pair) the full or delta sync crosses
8 s at about **38,000 contribution rows of history**, voided rows included, and a remote
financial-year report at about **38,000 contribution rows in that year**. CURRENT holds 5,088.
At the D-312 envelope of 100,000 rows a year, that is **under five months of trading**.

### Proposed redesign — for approval, not implemented

1. **Slow queries.** `reporting_snapshot(units, since, since)` (every sync, full or delta) and
   `reporting_primitives(units, FY-from, FY-to, …)`; underneath, the qual
   `may_read_expense(p.expense_id)` in `expense_period_contributions`.
2. **Principal.** All. The cost does not depend on who asks; a scoped reader pays for rows it
   will never see.
3. **Dataset.** Breaks at SCALE (99,869 rows); fails outright at STRESS (499,975).
4. **Plan.** Index Scan on `expense_period_allocations_category_period_idx`
   (org, property, `pnl_date`) with `Filter: may_read_expense(expense_id)` per row; the hash join
   to `expenses` that applies `voided_at`/`txn_number` comes after; `reporting_snapshot` has no
   date bound, so the scan is the whole table.
5. **Timings.** Above.
6. **Function calls.** One `may_read_expense` (plus one `current_org_id` and one or more
   `has_capability`) per expense period row scanned; one `has_capability` per revenue component.
7. **Bottleneck.** A per-row SECURITY DEFINER predicate, three nested non-inlinable functions
   deep, evaluated before every cheaper filter.
8. **Candidate redesign.**
   * **R1 — set-based authority in the read paths.** Resolve the caller's authority once per
     statement (organisation, user id, the properties where they hold `expense.view.all`, the
     properties where they hold `expense.view.own`), and express the D-169 document test as
     plain indexed SQL inside the security-barrier view and the three expense RLS policies:
     *a line in a view-all property, or the caller recorded it and a line is in a view-own
     property* — exactly `may_read_expense`'s rule. `may_read_expense` stays for the
     single-document checks (attachments, RPCs). The same move for the revenue projection's
     per-row `has_capability`.
   * **R2 — `reporting_primitives` scans only authorised, requested properties.** Apply the
     requested and authorised property set as a scan predicate, and skip the expense scan when
     nothing is authorised. Narrowing only; worth ~30% at a 70/30 split and all of a refused
     request. **R2 alone does not remove the timeout.**
   * **R3 — the transport stops asking for all history at once.** Bound `reporting_snapshot` to
     the requested financial years and page it, so a first sync is never one unbounded JSON
     document. This is a transport contract change (client and server) and needs its own
     approval; R1 does not fix the 256 MB ceiling.
9. **Expected benefit.** The same aggregates without the predicate take 0.2–0.7 ms on dev
   (90–240 ms locally at SCALE and STRESS). R1 should take a financial-year report and a full
   SCALE sync from ~20 s projected to well under a second; this must be measured in the harness
   on the same matrix before anything is deployed.
10. **Authorisation and security risk.** High if wrong: a divergence exposes another property's
    or another author's costs (D-169), or reopens the covert channel D-062 closes. It is an
    authorisation implementation change with the same semantics, so it must be **proven
    equivalent**, not argued.
11. **Migration and server impact.** One migration: replace `expense_period_contributions`,
    `expense_document`, and the `expenses`, `expense_allocations` and
    `expense_period_allocations` read policies; add at most one authority helper (API-surface
    invariant restated). No table, column or data change; no Drift change; no client change for
    R1 and R2. Rollback: restore the previous definitions. R3 changes the client transport.
12. **Allow/deny matrix required before acceptance.**
    * **Differential equivalence, in the harness**: for every principal below and every
      expense at SCALE, the set of document ids, line ids and period-row ids visible through
      each surface is identical before and after — plus the rolled-back positive control.
    * **Principals**: Owner unscoped; Manager CCR; Manager HKI; Accountant CCR; Data Entry CCR
      (`view.own`); a principal holding `view.own` on one property and `view.all` on the other;
      a revoked grant; a deactivated profile; no claims; a user of another organisation; a
      principal holding only `reports.view`.
    * **Documents**: single-property CCR by others; CCR by the `view.own` principal; HKI; a
      shared CCR+HKI document by the Owner; a shared document recorded by the `view.own`
      principal; voided; unnumbered; another organisation's.
    * **Surfaces**: `expense_document` (including the withheld total on a partial view,
      D-062), `expense_period_contributions`, the three tables under RLS,
      `expense_attachments` and Storage (`may_read_expense_attachments`,
      `may_attach_to_expense`), `reporting_primitives` (per property and consolidated, D-164,
      D-187), `reporting_snapshot`, and the expense RPCs.
    * **Live**: the existing live reporting, parity, expense and D-169 suites on
      krishna-mis-dev, unchanged and green.

## D-319 — The D-186 harness, and what building it found
**Date:** 2026-09-29 · **Status:** Implemented / Tested (Phase 8 Slice 2) — benchmark tooling
only; no product code, schema, migration, RPC or authorisation change

**The tooling, `tool/perf/`.**

| File | Does |
|---|---|
| `d186_probe.sql` | `pg_temp.d186_probe`, a **temporary** function: emulates a principal the way PostgREST does (`SET LOCAL ROLE authenticated` + `request.jwt.claims`), one discarded warm-up, N × EXPLAIN (ANALYZE, BUFFERS), the flattened plan, one timed plain run, and the exact per-function call counts from `pg_stat_xact_user_functions` |
| `d186.py` | builds the workload matrix; `emit` prints one batch (a single transaction ending in ROLLBACK); `run-local` runs it against the harness socket only; `summarize` prints the D-313 table |
| `localpg.sh` | a throwaway PostgreSQL 17 cluster in `%TEMP%\krishna_mis_perf_pg`, settings mirroring krishna-mis-dev, **no TCP listener** — one Unix-domain socket in its own directory |
| `supabase_shim.sql` | the minimum Supabase surface the migrations reference, every deviation listed |
| `bootstrap_identities.sql` | five synthetic principals at `.invalid` addresses, provisioned through the real admin RPCs |
| `synth.sh`, `synth.sql` | deterministic SCALE and STRESS datasets through every constraint and trigger; refuses to run outside the harness |
| `selftest.sql` | authorisation allow/deny against ground truth for every principal, plus a rolled-back positive control |

`test/tool/perf_harness_guard_test.dart` holds the safety properties as host tests: no TCP
listener, refusal guards present, no hosted project or credential named, one transaction ending
in ROLLBACK, `.invalid` identities, the positive control present. Planting a TCP listener turns
it red.

**Fidelity, checked rather than assumed.** After replay, 36 object definitions were fingerprinted
on both sides — the seven authority and reporting functions, the three reporting views, the
three expense RLS policies, 21 indexes and both property ids. **34 are byte-identical**; the two
RPCs differ **only in comments** (D-203's pattern) and are identical after comments and
whitespace are removed. The self-test passed 8/8 at SCALE; with `may_read_expense` replaced by
`true` inside a rolled-back transaction, the `expense.view.own` principal saw 32,961 rows instead
of their own 2,922, and the restored definition hashed exactly as krishna-mis-dev's.

**Findings.**

1. **The committed migrations do not replay in filename order** — relevant to D-146's
   fresh-branch replay before the first staging deploy (Phase 9).
   `20260829090500_api_surface_invariant.sql` is the ledger's `api_surface_invariant_v5`
   (20260829133240), applied **after** `20260829100000_usage_and_attachment_storage.sql`,
   because it names two functions that file creates. Filename order fails there. With that one
   file moved after its anchor, all 94 migrations replay. And
   `20260901132225_revenue_verified_baseline_fy2627` refuses to install without an owner
   profile, which on the server was bootstrapped by hand in Phase 2: a staging replay has to
   bootstrap its owner before that file. Neither was known before.
2. **Function call tracking is available per transaction on krishna-mis-dev.** `pg_settings`
   lists `track_functions` as superuser-only and `has_parameter_privilege` says `postgres` may
   not set it, yet `SET LOCAL track_functions = 'all'` inside a transaction is accepted and
   `pg_stat_xact_user_functions` then counts exactly. Only ever used `LOCAL`, inside a
   transaction that rolls back; no server-wide setting was changed.
3. **This session could not open a TCP listener** (`could not bind IPv4 address "127.0.0.1":
   Permission denied`, not a reserved port range), so the harness uses a Unix-domain socket
   only — which is stricter isolation than a loopback port and is kept.
4. **Local timings are indicative.** For identical call counts they varied up to ~3× with host
   load; the quietest run's per-call cost (0.29 ms) matched krishna-mis-dev's (0.335 ms). The
   Owner's SCALE run overlapped two host test runs and is recorded as noisy; the Owner's clean
   figures come from STRESS, whose month and year workloads are the same size because they are
   date-bounded. At STRESS the heavy workloads used one or two measured runs, recorded in each
   result.
5. **Supabase-specific behaviour not reproduced**, and why it does not matter here: the
   PostgREST wrapper (emulated), supautils, Storage's API, and PostgreSQL 17.11 against 17.6.
   `postgres` is a superuser locally and a BYPASSRLS non-superuser on Supabase; both bypass RLS
   inside the SECURITY DEFINER bodies and neither is the measured principal.

**Nothing synthetic touched krishna-mis-dev.** Every dev batch was a single transaction ending in
ROLLBACK that created only a temporary function.

## D-320 — The D-318 redesign as approved: set-based authority, scoped scans, a paged transport
**Date:** 2026-09-29 · **Status:** Accepted (project-lead approval of D-318 with one
modification) — implemented in migrations `reporting_authority_evaluated_once` and
`reporting_snapshot_paged`; results in D-321

**The approval.** R1, R2 and R3 were approved with one modification: **no global historical
retention cutoff**. The transport pages; it does not forget. A first synchronisation still
delivers every authorised document the caller asks about, in bounded pages, until there are
none left. Everything else in the approval is binding on this entry: the row set must be
identical for every principal (R1 is an optimisation only), a single-property report must
not authorise another property's rows (R2), and no role name enters any of it.

**R1 · authority resolved once per statement.** `expense_period_contributions` and
`revenue_period_contributions` no longer call a SECURITY DEFINER predicate per row. The
properties where the caller holds `expense.view.all`, `expense.view.own` and
`revenue.view` are each computed once, by `has_capability` itself over every
`business_units` row, as a scalar InitPlan; the D-169 document rule is stated in set form:

```
        a line in a view-all property
     ∨ (the caller recorded the document ∧ a line in a view-own property)
```

It is exact because every allocation's and every revenue entry's unit is a
`business_units` row (the D-040 composite key ladder), so `unit = any(set)` is true exactly
when `has_capability(cap, unit)` is. `may_read_expense` is unchanged and still guards every
single-document path — the three expense RLS policies, attachments, Storage and the RPCs.

**R2 · a report scans only what it asked for and may see.** `reporting_primitives` applies
the requested **and** authorised units as a scan predicate on each projection. A
Crystal-Canopy-only report no longer reads Hotel Krishna's rows; a refused request scans
nothing. The authority join stays, so the predicate can only narrow.

**R3 · the paged transport.** `reporting_snapshot` is dropped and replaced by
`reporting_snapshot_page(units, financial_years, revenue_since, expense_since,
revenue_after_seq, revenue_after_id, expense_after_seq, expense_after_id, page_documents)`:

| | |
|---|---|
| unit of paging | a **document** — a page never splits one (the unit of replacement already, D-178) |
| order | (document generation, document id): `expenses.change_seq`, `revenue_entries.change_seq` |
| page size | up to `page_documents` documents per dataset (client default 1,000; server clamps 1–2,000) |
| a page returns | the documents (id, generation), their rows inside the requested financial years, `has_more`, the snapshot identity and server time |
| first sync (`since = 0`) | lists documents with a row in the requested years; the client replaces the requested segment whole |
| delta (`since > 0`) | lists **every** changed document, including one whose rows all left the requested years, so the client can clear it |
| authority | decided per unit on every page, D-164 ∩ D-187, SECURITY INVOKER |

**The delta cursor moves from row grain to document grain.** The old transport keyed a delta
on each row's `greatest(header, allocation, period)` generation; the new one keys on the
document's own generation. That is complete only because **no server path changes a
document's reporting rows without stamping its header in the same transaction** —
`expense_create`, `expense_update` and `expense_void` all write `public.expenses`, and the
revenue RPCs write `revenue_entries` (D-177). A host guard now holds that over the latest
definition of every function (`document_generation_invariant_test.dart`), with a planted
headerless writer as its self-check.

**D-188 is amended, not relaxed.** A multi-page run's coherence claim is carried by the page
whose datasets **both** report `has_more = false`: its snapshot identity and server time
become the markers' evidence. Because the pass is ordered by generation, a document changed
after an earlier page was delivered appears again, later in the same pass, at its newer
version — so the published cache equals the final page's snapshot, with only the late-commit
hazard the safety overlap already mitigates (D-180, ARCHITECTURE §5.2). A single-page run is
exactly the D-188 case.

**The client (not a new architecture).** Same cache tables, same markers, same evidence,
same lock:

* intermediate pages are **staged** under the owner key `<owner>#reporting-staging`, never
  under the reader's own key, so nothing half-run is ever readable;
* the final page and every staged page are **published in one transaction** — staged
  documents replace published ones per financial year, a first sync clears the requested
  segment first, and the markers and evidence are written last (D-108);
* an interrupted run **resumes** from its cursor only when its scope is identical — user,
  units, years, on-demand flag, both `since` values, page size and the D-240 authority
  generation; otherwise the staged pages are discarded;
* a change in the authorised set between pages, a session or authority transition (D-240),
  or a refusal **discards** the staged pages and abandons the run;
* the purge (D-070, D-074) removes staged pages and the resume state with the reader's own.

**Residual behaviours, recorded rather than hidden.**

1. A scoped reader keeps a stale row if a shared expense is re-apportioned **wholly** to a
   property the reader cannot see: the delta lists the document only where the reader is
   authorised, and after the move there is no authorised row to list. This is the pre-existing
   D-062 boundary, unchanged by paging.
2. In a multi-page **first** synchronisation, a document moved entirely out of the requested
   years mid-run is removed at the next delta, not in the same run.
3. The head-check (`reporting_newer_than`) and the markers' generation are now document
   generations. An older marker's row-grain generation is at least as high as any document
   generation it covered, so the first delta after upgrade misses nothing.
4. Installed clients built before this change call the dropped `reporting_snapshot` and fail
   their reporting sync on `krishna-mis-dev` until rebuilt. There are no production users;
   the dev APK and the Windows build are rebuilt in Slice 8.

## D-321 — The D-318 redesign measured, and the page cost the acceptance found
**Date:** 2026-09-30 · **Status:** Implemented / Tested (Phase 8 Slice 3a — the approved
D-318 follow-on). Measured on krishna-mis-dev (CURRENT) and the local harness (SCALE,
STRESS) to the D-313 contract. **D-318 is closed** on this evidence.

### 1 · Row identity, proven exactly (the equivalence gate)

`tool/perf/equivalence.sql`, run on a freshly replayed SCALE harness against the
pre-redesign definitions captured in `perf_old`, compares **row ids**, never counts.

| | |
|---|---|
| Checks | **238 of 238 identical**, 0 different, **1,833,274 rows compared** |
| Principals | Owner (unscoped), CCR Manager, HKI Manager, Accountant, Data Entry (`view.own`), a mixed `view.own` + `view.all` principal, no authority, revoked, `reports.view` only, two scoped grants, a second Owner |
| Scopes | CCR, HKI, consolidated, invalid consolidated (two scoped grants) |
| Surfaces | `expense_period_contributions`, `revenue_period_contributions`, `expense_document`, the expense RLS tables, `reporting_primitives` (per property and consolidated), the paged transport walked to completion (first and delta), `reporting_newer_than` |
| Documents | own and other authors', single- and multi-allocation, both properties, cross-period, voided, unnumbered, permitted and denied |
| Transitions | capability revocation, property-scope loss, consolidated loss, user switch, and a stale in-flight publication |

**The delta changed grain on purpose (D-320).** The old transport keyed a delta on each
row's own generation; the new one on the document's. The gate therefore compares a delta
against the old rows **of documents whose generation is above `since`**, and reports what
it set aside: synthetic child rows carry generations far above their headers, which no
production writer produces (every writer stamps the header — D-177, guarded by
`document_generation_invariant_test.dart`). On krishna-mis-dev only 27 of 2,150 documents
have a child generation above the header, the largest gap 4, inside the safety overlap.

**Three positive controls, each required to go red** (asserted, not eyeballed):

| Control | Result |
|---|---|
| C1 — the Data Entry set widened to `view.all` in the new projection | old 3,256 rows, widened 32,961: **29,705 extra rows** — red |
| C2 — `reporting_primitives` with the HKI manager's refusal removed | old 24,951, widened 50,000: **25,049 extra rows** — red |
| C3 — the paged transport with the reporting-authority check removed, as the mixed principal on CCR | **53 expense rows** where the real function returns 0 — red |

### 2 · What the acceptance found: pages bounded in size, not in cost

The first measurement of `reporting_snapshot_page` at STRESS showed every page sorting the
caller's **whole history**. The projections are security-barrier views, so PostgreSQL plans
them as subqueries and cannot push `ORDER BY … LIMIT` into them. Evidence:

| STRESS, first body | |
|---|---|
| one page, warm | 3.1 s (Owner), 3.8 s (CCR Manager) |
| one page, **cold**, under the 8 s `authenticated` timeout | **cancelled** at 8.05 s (CCR Manager) |
| Owner, 2-year first sync, 1,000-document pages | 265 s end to end |
| Owner, 5-year first sync | **1,161 s** |

A size-bounded page whose cost grows with history makes a first sync quadratic. That fails
R3's intent, so it was corrected before acceptance rather than reported as a risk.

**The correction — `reporting_snapshot_page_windowed`, same contract, same answer.** A
comparison on the generation (bigint, leakproof) *is* pushed into the view and served by
`*_org_change_seq_idx`. Each page now reads a generation window starting at its cursor
(or `since + 1`, or — on a first page — the lowest generation in the requested years) that
grows fourfold until it holds the page's 4n + 1 candidates. Rows outside the window all
have higher generations, so the candidates, documents, rows and `has_more` are exactly the
old body's. Four further findings made it fast rather than merely correct:

* fetching a page's rows with `document id IN (…)` cannot cross the barrier either and
  scanned the whole history; the rows are now bounded by their documents' own generation
  range (every row of a document carries its generation);
* the planner estimated the page's document list at one row and re-scanned the window once
  per document (1.9 s a page at SCALE); the membership test is now an array comparison.
* a scope with no authorised property searched every window for nothing (1.1 s); it now
  searches none (12.6 ms).
* on krishna-mis-dev, where fewer than 4n + 1 rows exist at all, the window then grew
  about two dozen times to the top of the generation range, re-counting everything each
  step: a first page went from 119 ms to 597 ms. A second migration stops growing once a
  step finds nothing new, and ends a full window at the highest generation it actually
  holds (597 → 210 ms on dev, and less sorting at scale).

Both corrections are their own migrations — `reporting_snapshot_page_windowed`
(20260930125903) and `reporting_snapshot_page_window_stops` (20260930132722) — because an
applied migration is never edited. On STRESS, each corrected body was compared page by page
with the original paged body on 19 sampled pages across seven walks (Owner and CCR
Manager; first, second, third and final pages; 2-year and 5-year first syncs; deltas):
**0 mismatches**, both times. The SCALE gate in §1 was run from a fresh replay on the
final body.

### 3 · Before and after — krishna-mis-dev (CURRENT)

Rows: before 2,150 expenses · 2,475 expense period rows · 2,601 revenue entries · 2,613
components (2026-09-29); after 2,276 (2,215 voided) · 2,610 · 2,792 (2,789 voided) · 2,805
(2026-09-30 — the live suites' voided fixtures since). Median ms of five warm runs, EXPLAIN
ANALYZE, every batch rolled back; `r` = refused.

| Workload | Owner before → after | CCR Manager before → after | Accountant before → after |
|---|---|---|---|
| expense projection, month, one property | 145.0 → 1.9 | 151.2 → 1.5 | 148.6 → 1.4 |
| expense projection, FY, one property | 579.0 → 2.5 | 593.2 → 2.4 | 589.1 → 2.4 |
| expense projection, FY, both, breakdown | 758.8 → 2.5 | 786.6 → 2.7 | 763.6 → 2.8 |
| `reporting_primitives`, month | 232.7 → 5.7 | 229.8 → 6.3 | 229.2 → 6.3 |
| `reporting_primitives`, FY | 769.7 → 9.4 | 778.5 → 9.8 | 771.5 → 10.0 |
| `reporting_primitives`, both, FY | 782.5 → 13.0 | 780.2 r → 4.3 r | 770.2 r → 4.5 r |
| full sync (old one call → new first page) | 1,044.1 → 209.7 | 1,034.1 → 191.9 | 1,025.1 → 193.0 |
| delta sync, 200 generations | 895.2 → 23.0 | 917.5 → 23.5 | 894.8 → 23.8 |
| whole first sync, paged (Owner, 3 pages, 5,063 documents) | — → 418.6 | | |
| `may_read_expense` calls, FY report | 2,247 → **0** | 2,247 → **0** | 2,247 → **0** |

Unchanged by design and still per row (§6): the expense RLS read, 253 / 171 / 167 ms, and
`expense_document`, 264 / 263 / 262 ms, for one month.

### 4 · Before and after — SCALE (local harness, 99,869 contribution rows in one year)

Same data, same harness; before = the pre-redesign definitions kept in `perf_old`. Median
(five runs; three for FY and whole-sync workloads). Timings on this workstation vary with
host load (D-319) — the call counts and the order of magnitude are the evidence, not the
last digit.

| Workload | Owner before → after | CCR Manager before → after | Accountant after |
|---|---|---|---|
| expense projection, month | 426.6 → 16.4 | 420.8 → 14.0 | 15.6 |
| expense projection, FY | 4,895 → 146.4 | 4,713 → 148.7 | 136.1 |
| `reporting_primitives`, FY | 8,127 → 240.1 | 7,608 → 227.1 | 235.0 |
| `reporting_primitives`, both, FY | 7,599 → 362.9 | 7,779 r → 3.5 r | 3.2 r |
| delta sync | 7,459 → 16.5 | 8,221 → 13.7 | 13.6 |
| first page | (old full sync: > 8 s, cancelled) → 489.8 | → 368.6 | 327.1 |
| whole first sync, paged | → 4,902 (50 pages) | → 3,712 (31 pages) | 3,740 |

**Under the 8 s `authenticated` statement timeout** (single cold statements): the old full
sync, old delta and old financial-year report were each cancelled at 8.0 s for both the
Owner and the Manager; the new first page took 438 / 318 ms, a delta page 17 / 14 ms, the
FY report 351 / 215 ms, and the largest page of a whole first sync 459 / 299 ms.

### 5 · Before and after — STRESS (local harness, 499,975 rows over five years)

| Workload | Owner before → after | CCR Manager before → after | Accountant after |
|---|---|---|---|
| expense projection, month | 910.0 → 19.4 | 1,414 (D-318) → 18.7 | 20.5 |
| `reporting_primitives`, FY | 17,579 → 320.9 | 15,600–16,000 (D-318) → 305.7 | 321.7 |
| delta sync | 85,755 → 21.6 | 136,900 (D-318) → 14.3 | 14.1 |
| old full sync | **fails** — jsonb > 256 MB (D-318) | | |
| first page (first paged body → final) | 3,080 → 1,057 | 3,786 → 738 | 774 |
| whole 2-year first sync (first paged body → final) | 265 s → **11.9 s** (100 pages) | 213 s → **10.4 s** (61 pages) | 9.7 s |
| whole 5-year first sync (first paged body → final) | 1,161 s → **30.8 s** (250 pages) | 1,923 s → **26.5 s** (151 pages) | — |

The CCR Manager's pre-redesign STRESS figures in this run were taken under visible host
load (every workload about 3.5× the Owner's), so the table uses D-318's quiet-run figures
for them; the Accountant's first-paged-body run was likewise loaded and is not quoted.

**Under the 8 s timeout at STRESS** (cold, single statements, final body): first page
827 ms (Manager) and 1,095 ms (Owner); delta page 15 / 18 ms; FY report 299 / 506 ms. The
largest page of any whole first sync: 762 ms (Manager, 2 years), 1,840 ms (Manager, 5
years), 1,234 ms (Owner, 2 years), 3,103 ms (Owner, 5 years) — the first page, which finds
the lowest generation across every requested year. **No page came near the timeout**;
before the correction a cold first page was cancelled.

### 6 · What is still per row, deliberately

R1 changed the two reporting projections only. The three expense RLS policies and
`expense_document` still call `may_read_expense` per row, as D-320 left them: one month
costs 500–740 ms at SCALE and STRESS (2,829–4,205 calls). Those surfaces serve single
documents and the ledger's own reads, not reporting; they are recorded for Slice 4, which
owns the expense ledger (D-317), and no reporting path depends on them.

### 7 · The transport, as delivered

| | |
|---|---|
| page size | client 1,000 documents per dataset; server clamps 1–2,000 |
| pages, first sync | dev 3 · SCALE 31–50 · STRESS 61–100 (2 years), 151–250 (5 years) |
| largest page | 2,000 documents / 2,783 rows (SCALE gate, 2,000-document pages) |
| delta | lists every changed document, tombstones included; 13–24 ms a page at every volume |
| coherence | the final page's snapshot certifies the run (D-188 as amended by D-320) |
| authority | re-decided per unit on every page; a refused scope searches nothing (1.6–12.6 ms) |

### 8 · Closure

D-318's three failures are gone and measured gone: no reporting path evaluates a per-row
predicate, a single-property report reads only its property, no synchronisation is one
unbounded document, and at the approved STRESS envelope no page exceeds 3.1 s against an
8 s timeout. Row identity is proven exactly for every principal, scope, surface and
transition the directive named, with every control red. **D-318 is closed.** The residuals
recorded in D-320 stand, and §6 is carried to Slice 4.

---

# Phase 8 Slice 3 — Retry and hang hardening (2026-10-01)

## D-322 — A one-shot act never waits on a provider's retries
**Date:** 2026-10-01 · **Status:** Implemented / Tested (Phase 8 Slice 3, under D-312 D7)

**What the Riverpod 3.4.2 source says** (read, not recalled; pinned by
`test/features/retry_hang_test.dart`): a failed provider is retried up to ten times, 200 ms
doubling to 6.4 s — 38.2 s. An `Error` and a `ProviderException` are not retried. While it
retries, a `.future` already handed out stays pending. The retry timer rebuilds the provider
**only while something watches it**, so a `.future` read once from an unwatched provider never
settles. No retry override existed on the container; one provider
(`exportShareCacheRootProvider`) already answered once.

**What that did here, reproduced before any change** (fake clock, 100 ms steps):

| Act | Before | After |
|---|---|---|
| P&L refresh, master hierarchy unreadable, nothing watching | status never changed; `refresh()` never settled | running at once; `failed` (local) within 100 ms |
| the same, P&L screen watching | status never changed; `refresh()` threw after 75.8 s (11 hierarchy reads) | the same as above |
| P&L refresh, business-day rules unreadable, screen watching | status never changed; threw after 37.6 s | the same as above |
| Dashboard refresh, hierarchy unreadable | as the P&L: never, or 75.8 s | the same as above |
| Owner settlement refresh, hierarchy unreadable | "synchronising" **for ever** (threw at 37.6 s with a screen, never without) | `failed` (local) within 100 ms |
| P&L refresh, a local failure after it started (coverage table missing) | threw; left **running for ever**; every later refresh ignored | `failed` (local); the next refresh runs |
| P&L view, report source unreadable | canonical cache lock held **76 s** | released within 100 ms |
| Export fonts failing with an `Exception` | never settled unwatched (export "making the file" for ever); 38.2 s watched | answered within 100 ms; next press tries afresh |

**Decision.**

1. **One-shot acts read their inputs once, themselves.** The three refreshes read the master
   hierarchy and the business-day rules from the repository (`readReportSyncInputs`), not
   through a provider's `.future`.
2. **Visible first.** A refresh is running before it awaits anything; a second tap meanwhile is
   ignored instead of starting a second run.
3. **Every failure lands in a status.** A failure on this device is `failed` with
   `localFailure`, worded in plain terms and offering retry; nothing is written and the figures
   on screen stay. The person- and authority-change guards (D-074, D-231) and D-240's
   abandonment are unchanged; a run whose person or authority changed publishes nothing.
4. **Answer once where retry cannot help** (`noAutomaticRetry`): derived providers
   (`pnlScopeOptionsProvider`, `localReportingEngineProvider`, `dashboardEngineProvider`),
   providers awaited under the canonical cache lock (`localReportingSourceProvider`,
   `reportingDrilldownSourceProvider`), `businessDayRulesProvider`, and `exportPdfFontsProvider`.
5. **Explicit retry reaches the failed input.** Try again, and every refresh a person starts,
   invalidate whichever report input holds an error (`retryFailedReportInputs`); inputs never
   read are left unread.
6. **`masterGraphProvider` keeps its retry**, deliberately: the entry forms and Masters screens
   recover from a passing failure on their own, and nothing one-shot awaits it now.
7. **Not disabled globally**, as D7 required.

**Classification of the audited providers.** A retry appropriate · B retry wrong for a one-shot
path · C already bounded · D needs explicit retry · E background retry acceptable.

| Provider | Class | Change |
|---|---|---|
| `pnlScopeOptionsProvider` | B (derived) | answers once |
| `businessDayRulesProvider` | B, D | answers once; reached by Try again |
| `exportPdfFontsProvider` | B, D (real failures are `Error`s, so C in practice) | answers once; a failed export clears it |
| `masterGraphProvider` | E | none; actions no longer await it |
| `localReportingSourceProvider` | B (under the lock) | answers once |
| `localReportingEngineProvider` | B (derived, under the lock) | answers once |
| `reportingDrilldownSourceProvider` | B (under the lock) | answers once |
| `dashboardEngineProvider` | B (derived) | answers once |
| `pnlDocumentDetailProvider` | E (every open re-fetches, D-239; network failures are typed results) | none |
| `pnlViewProvider`, `dashboardViewProvider`, presets, settlement preview, drill levels | E (top level; an error shows Try again at once) | Try again reaches failed inputs |
| `exportShareCacheRootProvider` | C (already answered once) | none |
| `sessionProvider`, `reportingSyncProvider`, `ownerSettlementRefresherProvider` | C (synchronous; nothing to retry) | none |

**D-248, disposition.** The old symptom — a pull-to-refresh whose status never changed — was
not reproduced on a device in this slice. A plausible contributing cause is now removed: a
refresh awaiting a retrying, or unwatched, provider left the status untouched for 38–76 s or
for ever, which is exactly what the diagnostic could not tell apart from "the gesture never
arrived". D-248 itself **remains unconfirmed**, and the diagnostic stays. One change in what it
will see: a failure while preparing now publishes `failed`, so the diagnostic's wait ends and
its next assertion names the phase; a refresh with nothing to fetch still leaves the status
object identical, as before.

**Guards.** `test/app/one_shot_read_guard_test.dart` refuses `ref.read(p.future)` in `lib/` on
a provider that does not answer once. Positive controls, each seen red and restored
byte-identically (`cmp`): the fonts' retry restored; the source's retry restored; the refresh
awaiting the providers again; the running state moved after the inputs; the failure swallowed;
a stale failure published after a person change (P&L, owner settlement) and after a capability
change (dashboard); a stale run reaching the server; Try again reaching nothing; the guard
against the fonts' retry restored.

**Recorded, not changed.** The Android and Windows expense entry forms show the raw error text
when the master hierarchy cannot be read (`'Nothing has been saved. $error'`). That is a
presentation defect outside this slice's retry scope (D-127); it belongs with the slice that
next touches expense entry.

---

# Phase 8 Slice 4 — Expense ledger profiling, pagination and read-path hardening (2026-10-01)

## D-323 — The Expense ledger reaches every matching document, and its read path is indexed
**Date:** 2026-10-01 · **Status:** Implemented / Tested (Phase 8 Slice 4, under D-312 D5 and
D-317)

### What the ledger did, measured before anything changed

Read from the code, then measured with `test/support/expense_ledger_workload.dart` — a
deterministic synthetic fixture with shared bills, cross-period splits, voided rows,
attachments, every outbox state, and documents captured in the same instant.

* **The path.** Both shells read `filteredExpensesProvider`, a one-shot `FutureProvider`
  calling `ExpenseRepository.query(filter)` with its defaults, `limit: 100, offset: 0`. That
  default is the hidden 100-row ceiling: nothing ever asked for a second page.
* **Filters.** Dates, payment, vendor, search, voided and the four hierarchy filters were SQL
  predicates. **Sync state was applied in Dart after the 100 rows were cut**, so it searched the
  newest window only.
* **Order.** `business_date desc, captured_at desc` — no id tie-break.
* **Hydration.** Per row: allocations, contributions, attachments and an outbox lookup — **153–155
  statements for a 50-row page**, every child read a full `SCAN` of its table, because none of the
  three child tables had an index on `expense_id`.
* **Hierarchy filters.** A correlated `EXISTS` that scanned `expense_allocations` once per
  document: quadratic.

| Baseline (old code) | CURRENT (2,276 docs) | SCALE (45,000) | STRESS (225,000) |
|---|---|---|---|
| E-HOST, ordinary page | 22–40 ms | 443–551 ms | — |
| E-HOST, property / category filter | 131–132 ms | **~112 s** | not run: quadratic |
| E-HOST, conflict filter: rows found | **1 of 46** | **1 of 900** | — |
| E-WIN encrypted, ordinary page | 40–59 ms | **3.5–3.9 s** | **17.0 s** |
| E-WIN encrypted, conflict filter: rows found | 1 of 46 | 1 of 900 | 1 of 4,500 |

### Before and after, on the real encrypted database (E-WIN)

`integration_test/expense_ledger_performance_test.dart`, Windows 11, Debug build, SQLCipher
file in the application's support directory, one discarded warm-up then five runs (two at
SCALE/STRESS before, one for the STRESS-before retry). "Before" is commit `41f58c5` run from a
git worktree with the same workload file.

| Median ms | CURRENT before → after | SCALE before → after | STRESS before → after |
|---|---|---|---|
| first page | 55.2 → 4.6 | 3,479 → 3.1 | 17,034 → 2.3 |
| second page | 58.5 → 3.6 | 3,631 → 2.5 | — → 2.5 |
| middle page (OFFSET) | 53.5 → 3.7 | 3,584 → 27.8 | — → 123.1 |
| deep page (OFFSET) | 46.4 → 3.7 | 3,906 → 50.3 | — → 240.7 |
| property / category filter | 156.7 / 153.2 → 3.7 / 3.3 | not run (quadratic) → 2.7 / 2.5 | not run → 2.5 / 2.6 |
| one-month range | 40.6 → 3.0 | 3,777 → 2.4 | — → 2.5 |
| unmatched category (worst case) | 154.4 → 1.6 | not run → 102.1 | not run → 540.0 |
| search | 1.4 → 2.0 | 104.4 → 51.1 | — → 244.1 |
| conflict filter | 42.0 (1 row) → 3.0 (46) | 7,004 (1) → 2.7 (50) | 17,145 (1) → 2.8 (50) |
| include voided | 43.1 → 2.6 | 7,827 → 2.3 | — → 2.2 |
| statements per page | 151–156 → 4 | 153–155 → 4 | 153 → 4 |
| file | 2.4 → 2.8 MB | 39.1 → 46.4 MB | 194.6 → 231.1 MB |

The first STRESS "before" run ended after about 90 s with "did not complete" from the test
runner and no captured cause; a reduced retry (first page and conflict filter, one run)
completed and is what the table reports. Not called flaky (D-075): it is an unexplained
abort of the old code's measurement, not of anything shipped.

### What was decided and built

1. **Every filter is decided in the statement that cuts the page.** Sync state included: the
   user-visible state is derived in SQL by `ExpenseRepository.ledgerSyncStateSql`, **generated**
   from `OutboxStatus.userVisibleState` — the project's one mapping (D-119) — so the SQL and the
   Dart rule cannot drift; a host test asserts they agree for every outbox status. A status this
   build cannot name is shown as pending, never as synced.
2. **A total order:** `business_date desc, captured_at desc, id desc` (D-121's rule, applied to
   expenses).
3. **Load more, one window.** `filteredExpensesProvider` is now a stream of an
   `ExpenseLedgerWindow`: the first `pages × 50` matching documents, read as **one** ordered
   statement with one extra row to learn whether more exist. Appending OFFSET pages was rejected:
   a page cut later is cut against a table that may have changed, and a document synced between
   two presses would shift every later page by one — shown twice or never. Re-reading the window
   cannot duplicate, skip or reorder.
4. **Paging resets** on any change to the filter, the search or the reader's authority (the
   person plus every grant). A session refresh that changes nothing keeps the reader's place
   (D-245).
5. **A window is shown only to the question it answers** — stamped with the authority key and
   the exact filter, refused otherwise (D-074, D-231).
6. **A stream (D-160).** The sync worker invalidates no provider; the ledger now follows the
   outbox.
7. **Batched hydration:** one `IN` list per child table — **4 statements a page however long it
   is**, measured.
8. **Local schema v22 — four indexes, no table or column change.** `expense_id` on
   `expense_allocations`, `expense_period_allocations` and `expense_attachments` (the server has
   had the same three since Phase 3), and `ix_expenses_ledger` on
   `expenses (business_date desc, captured_at desc, id desc) WHERE scope_revoked_at IS NULL`. The
   hierarchy filters are a correlated `EXISTS` answered through the allocation index. The case
   for the migration, as D-312 requires:

| | Without v22 (new code) | With v22 |
|---|---|---|
| Page statement plan | `SCAN e … USE TEMP B-TREE FOR ORDER BY` | `SCAN e USING INDEX ix_expenses_ledger` |
| Child read plan | `SCAN expense_allocations` | `SEARCH … USING INDEX ix_expense_allocations_expense` |
| E-HOST STRESS, first / middle / deep page | 429 / 606 / 548 ms | 7.5 / 39 / 68 ms |
| E-HOST STRESS, hydration share | 68–153 ms | 3–7 ms |
| E-HOST STRESS, property / category filter | 423 / 389 ms (uncorrelated `IN`) | 9.0 / 6.2 ms (`EXISTS`) |
| Write cost: seeding STRESS | 15.1 s | 15.9 s (+5%) |
| Storage: STRESS file | 193.9 MB | 230.2 MB (+19%) |

   SQLite also enforces the `ON DELETE CASCADE` from `expenses` by looking each child table up
   on `expense_id`, so the scope purge benefits too. **Rollback:** dropping the four indexes
   loses no data; the v22 step is `CREATE INDEX IF NOT EXISTS` only. The v16 reasoning applies:
   the tables arrive at v7 and `scope_revoked_at` at v9, so no version floor is needed (D-144).
9. **LIMIT/OFFSET kept; keyset not needed.** On the encrypted Windows database at STRESS a page
   ~2,000 deep costs 123 ms and ~4,000 deep 241 ms, against 2.2–2.8 ms for the pages a person
   reaches by "Load more". The ledger itself reads offset 0; OFFSET depth is a repository-level
   profile (D-314).
10. **Plain errors** (D-322's recorded defect): the entry form, the ledger and the detail panel
    say what failed in words, offer Try again, and send the exception to the developer log
    (`dart:developer`), never to the screen.

### Recorded, not changed

* **Two worst cases at STRESS.** A filter matching nothing walks the whole ledger index — 540 ms
  on E-WIN — and search is `LIKE '%…%'` over the whole table — 244 ms. Both fall to tens of
  milliseconds at SCALE. Five years at the SCALE envelope is the stated worst case for a device
  (D-170 bounds reporting, not the ledger), and fixing either needs a second index or a search
  structure nobody has measured a need for on the reference device.
* **The Revenue ledger has the same post-cut sync-state filter** (`RevenueRepository._mapLedger`).
  Same defect class, outside this expense slice (D-127); it belongs with the slice that next
  touches revenue.
* **Raw `$error` text** remains on the Masters, Vendors and Revenue ledger surfaces and the
  start-up failure screen (D-316). Outside this slice; the start-up screen is Slice 7's.
* **`recentExpensesProvider` has no reader** in `lib/` — only invalidations. Left in place.

### Positive controls, each seen red and restored byte-identically

| Control | Red |
|---|---|
| C1 sync filter applied after the cut | the before-the-cut test |
| C2 no id tie-break | the tie test — **only after it was strengthened**: with the v22 index present the tie order comes back as `id desc` from the index itself, so the first version passed without the tie-break. It now inserts out of id order and is asserted again with the ledger index dropped |
| C3 pages survive a filter change | the reset test |
| C4 a window shown to another person | the switch test |
| C5 the raw error on the ledger | the plain-error test |
| C6 SQL sync state disagrees with Dart | the parity test |
| C7 hydration one document at a time | the statement-count test |
| C8 no `expense_id` index | the plan test and both v22 schema tests |

## D-324 — The server expense-read residual is not on any production path; no server change
**Date:** 2026-10-01 · **Status:** Measured (Phase 8 Slice 4). No migration, no RLS or
authorisation change.

D-321 left a residual: the three expense RLS policies and `expense_document` still evaluate
`may_read_expense` per row, about 500–740 ms for a month at SCALE. Slice 4 asked whether that is
worth changing.

**Every production read of those surfaces names one document.** `ExpenseGateway.fetchDocument`
(`expense_document` by id), `fetchAllocations`, `fetchPeriodContributions` and
`fetchAttachments` (by `expense_id`), and the attachment worker's `hashOf` (by `storage_path`).
No client issues the month shape D-321 measured.

Measured with `tool/perf/d186.py --single`, one discarded warm-up and five EXPLAIN (ANALYZE,
BUFFERS) runs, every dev batch rolled back (the result returned by a raised exception, so nothing
could commit):

| Read (median ms · `may_read_expense` calls) | Owner | CCR Manager | Accountant | Data Entry |
|---|---|---|---|---|
| E-DEV CURRENT · `expense_document` by id | 2.5 · 1 | 4.0 · 1 | 3.6 · 1 | 0.8 · 1 (0 rows: refused) |
| E-DEV · `expense_allocations` by document | 1.3 · 1 | 1.8 · 1 | 1.7 · 1 | 1.7 · 1 (0 rows) |
| E-DEV · `expense_period_contributions` by document | 2.4 · 0 | 2.8 · 0 | 2.6 · 0 | 0.6 · 0 (0 rows) |
| E-DEV · `expense_attachments` by document / by path | 2.4 / 2.4 · 1 | 3.8 / 3.5 · 1 | 3.3 / 3.3 · 1 | 0.6 · 0 (0 rows) |
| E-LOCALPG STRESS · document / allocations / contributions | 1.3 / 0.7 / 0.6 | 2.1 / 1.0 / 0.9 | 2.1 / 1.0 / 0.9 | 0.5 / 1.1 / 0.9 |
| *E-DEV · month benchmark: epa RLS / `expense_document`* | *272 · 791 / 372 · 781* | *183 · 518 / 281 · 781* | *177 · 518 / 274 · 781* | *180 · 518 / 268 · 781* |
| *E-LOCALPG STRESS · the same month benchmarks* | *660 · 4,205 / 1,249 · 3,520* | *399 · 2,829 / 1,246 · 3,520* | *406 · 2,829 / 1,261 · 3,520* | *469 · 2,829 / 1,327 · 3,520* |

Answers to the slice's questions:

* **Per-row functions:** `may_read_expense`, with `has_capability`, `current_org_id` and
  `expense_visible_units` beneath it; `may_read_expense_attachments` for attachments.
* **Unrelated properties are not evaluated per row** by the RLS policy: its unit-set predicate
  runs first, so a CCR-scoped reader's month makes 2,829 calls where the Owner's makes 4,205.
* **Voided rows are evaluated** by `expense_document`, deliberately: it returns voided documents,
  which the ledger shows with *include voided* (D-006).
* **The D-318 set-based pattern could be reused** on these surfaces, but a single-document read
  already makes exactly one predicate call and costs 0.5–4 ms at both CURRENT and STRESS: the
  per-row cost scales with rows a read touches, and production reads touch one document. A
  rewrite of reviewed RLS would carry the full D-318 equivalence burden for no measured benefit.
  **Declined.** If a future surface lists expenses from the server, this measurement is where it
  starts.
* **`expense_attachments` by document** used a sequential scan on dev (46 rows); the harness at
  STRESS has `expense_attachments_expense_idx` and uses it. No change needed.

---

# Phase 8 Slice 5 — Global missed-tap test hardening (2026-10-01)

## D-325 — A missed tap fails the test, across the whole host suite
**Date:** 2026-10-01 · **Status:** Implemented / Tested (Phase 8 Slice 5, under D-312 D8).
Test infrastructure only; no product code changed.

**Baseline, before any change** (HEAD `0e0e30b`): full host suite **3,053 passed, 0 failed,
0 skipped**. The log held **no** missed-tap warning at all — checked by planting a miss and
confirming the reporter does print one. Five files (`dashboard_drill`, `dashboard_mobile_home`,
`pnl_capability_revocation`, `pnl_drilldown_ui`, `pnl_mobile_ui`) set the flag fatal in
`setUpAll` and back to false in `tearDownAll`; seventeen other tapping files had no setting;
`revenue_ui_test` carried the one `warnIfMissed: false`.

**Mechanism.** `test/flutter_test_config.dart`, the one config `flutter test` wraps around every
file under `test/` (the nearest config wins; there is no other). It sets
`WidgetController.hitTestWarningShouldBeFatal = true`, sets it again in a root `setUp` before
every test, and a root `tearDown` fails any test that leaves it false — restoring it first, so
one leak cannot weaken the tests after it. No file assigns the flag any more. A tap that is
meant to miss opts out **at its own call** with `warnIfMissed: false` beside a
`// missed-tap opt-out:` comment giving the reason; there is no file- or test-wide switch.
`integration_test/` is outside the config: the device acceptance suite keeps its own D-075
setting.

**First enablement: 0 newly failing tests** (3,053 still passed), so the classification
A … G is zero in every category. The suite had been free of misses since D-075.

**Migration.** The five per-file toggles removed (13 lines). The `revenue_ui_test` opt-out was
re-evaluated rather than kept, and was **dead code**: the test tapped Save, pumped once, and
tapped again only if the button was still there — but in the host harness the first save
finishes inside that pump and the form resets, so the second tap was never reached (an
instrumented run printed nothing). The test asserted one sale after one press. It now presses
twice before any frame — which exposes D-326 — and is skipped, visibly, against D-326. **No
opt-out is retained anywhere in `test/`.**

**Guard** (`test/app/missed_tap_policy_test.dart`, 12 tests): the config exists, is the only
one, and does all three things before `testMain`; nothing else under `test/` assigns the flag;
every code-level `warnIfMissed: false` carries the reason marker (comments are prose, not
calls); the acceptance suite keeps D-075's setting; and, behaviourally, a tap on a covered
widget throws, and a per-call opt-out covers its own call and nothing after it.

**Positive controls,** each restored byte-identically (`cmp`):

| Control | Result |
|---|---|
| C1 a tap on the page under the open "Sign out?" dialog (`account_control_test`, never fatal before) | both shell variants **red**; with the config removed the same miss **passed** with 3 warnings |
| C2 a planted test that leaves the flag false | that test **red** by name; the next test in the file still fatal |
| C3 the per-test re-assert removed from the config | a file-wide `setUpAll` switch survives — **red** |
| C4 a real planted file-wide switch | the guard **red**, naming the file |
| C5 the leak check removed from the config | the leak passes silently, and the structural guard goes **red** |

**Reliability.** Full suite **3,064 passed, 1 skipped**; with
`--test-randomize-ordering-seed=20261001` the same; three shards **1,024 + 1,017 + 1,023 =
3,064**, 1 skipped. Each file runs in its own isolate and the flag is re-asserted per test, so
order, sharding and concurrency cannot change the policy.

## D-326 — A double press before the next frame reaches the revenue save twice
**Date:** 2026-10-01 · **Status:** **Open — reported, not fixed. Awaits the project lead.**
Found by D-325's re-evaluation of the revenue opt-out.

| | |
|---|---|
| Screen | Revenue entry (`RevenueEntryPage`), both shells |
| Control | Save (`revenue-save`) |
| Expected | a second press while the first save runs does nothing — the code's own comment says "a second press cannot start a second save" |
| Actual | two presses before the next frame (what a janking phone delivers) both reach `_save`, because the button is disabled only after a rebuild and `_save` does not check `_saving` on entry. The draft carries one id, so the database refuses the second insert (`UNIQUE constraint failed: revenue_entries.id`): **still one sale**, but the refusal escapes as an unhandled `SqliteException` |
| Platform | both; reproduced in the host harness |
| Proposed fix | one line at the top of `_save`: `if (_saving) return;`. Verified: applied temporarily, the skipped test passes unchanged; reverted (`cmp`), not committed |
| Same shape | `ExpenseEntryPage` disables Save through `_saving` the same way — by reading, not exercised |

Not a hit-target defect, and not fixed inside a test-infrastructure slice. The test
`a double tap records one sale, not two` stays skipped until the fix is approved.

## D-326 (fixed) — Save runs once per act, on Revenue and Expense entry
**Date:** 2026-10-01 · **Status:** Implemented / Tested (project-lead approval) — the entry
above stands as written, because this log is append-only.

**The fix.** Both `_save` methods now begin `if (_saving) return;`, and the next statement
sets `_saving = true` synchronously, before the first await. A second press that lands
before the button rebuilds returns there: it reads nothing, calls no controller, writes
nothing, shows nothing, and does not touch the first save.

**The flag cannot latch.**
- Expense already released `_saving` in its failure path; unchanged.
- Revenue released it on a refusal, but an exception from the controller escaped with
  `_saving` still true, so Save stayed disabled for good. That path now logs the detail to
  the developer log (`krishna_mis.revenue`, D-323) and says *"This sale could not be saved.
  Check Recent sales before trying again."* in the existing refusal banner. The sentence does
  not claim nothing was recorded, because evidence is attached after the sale commits.
- Every `setState` after an await stays behind the existing `mounted` checks.

**Tests.** The skipped revenue test is re-enabled and now counts saves at the controller,
so the database is not what stops the duplicate. New: an equivalent Expense test, and a
failure-then-retry test on each form.

| Control (restored byte-identically, `cmp`) | Result |
|---|---|
| Revenue guard removed | double-tap **red**: 2 controller saves |
| Revenue failure path no longer releases `_saving` | retry **red** |
| Expense guard removed | double-tap **red**: 2 controller saves |
| Expense failure path no longer releases `_saving` | retry **red** |

Full host suite **3,068 passed, 0 skipped**. No schema, server, outbox, validation, button
design or navigation change.

---

# Phase 8 Slice 6 — Export performance (2026-10-01)

## D-327 — Exports are well inside T2 on Windows; no change is justified
**Date:** 2026-10-01 · **Status:** Measured (Phase 8 Slice 6, under D-312 D2 and D-313).
No product code changed.

**What was measured.** Each of the four reports, as PDF and Excel, in three stages:
1. the document model (`ExportDocuments.*`);
2. the render (`pnlPdf` / `pnlWorkbook` and their analysis counterparts);
3. the file write (`writeAtomically`).

These are the same functions `ExportPipeline.render` and the Save As path call. The stage
D2 calls "canonical result already available" is the starting point: workloads are built
from `Pnl.compute`, `PnlComparison`, `DashboardTrends`, `TopN` and `PropertyComparison`,
with no database underneath (`test/support/export_workload.dart`). Dialogs and human waits
are excluded. The one-off font load is reported on its own line.

| Size | Contents |
|---|---|
| **normal** | both properties for a month: the four revenue categories and the 23 expense concepts of spec §4, a 30-day daily Net Sales trend, and a 12-month expense trend |
| **stress** (T3) | 40 revenue lines, 600 expense lines and a 60-month expense trend — deliberately far past a real hotel |

### E-WIN — the real `krishna_mis.exe`, debug build, fonts from the app bundle

One warm-up discarded, then five runs. Each cell is the median TOTAL (model + render +
write) in ms, with the range in brackets; the first-export warm-up comes after the dot.

| | normal PDF | normal XLSX | stress PDF | stress XLSX |
|---|---|---|---|---|
| P&L | 19.9 (18.6–45.7) · warm-up 137.5 | 4.3 · 19.4 | 205.3 (196.1–218.4) · 235.5 | 8.4 · 9.1 |
| Revenue Analysis | 15.6 · 27.7 | 4.1 · 5.9 | 11.8 · 13.1 | 4.0 · 5.5 |
| Expense Analysis | 12.9 · 13.1 | 3.6 · 5.6 | 15.7 · 16.9 | 5.9 · 5.9 |
| Business Comparison | 9.5 · 9.7 | 2.8 · 5.9 | 9.7 · 8.9 | 3.3 · 3.7 |

- **Font load and check:** 19.2 ms, once per session.
- **Stage split:** the model takes 0.1–1.7 ms, the write 1.5–2.4 ms, and the render is the
  rest.
- **Sizes:** the normal PDFs are 1–2 pages and 17–23 KB. The stress P&L PDF is 17 pages and
  84 KB.

**Verdict, T2 (E-WIN < 1 s): inside.** The worst normal export is the session's first P&L
PDF: 19.2 + 137.5 ≈ **157 ms**. This was a debug build, the slow case for Dart, so release
can only be faster. **T3:** the stress P&L PDF takes 205 ms and is reported, not a verdict.

**E-A06: Not tested.** No Android device was attached. The same harness runs there
unchanged:

```
flutter test integration_test/export_performance_test.dart -d <device>
```

This belongs with Slice 8's device runs. Until then, T2's Android verdict is open.

**What was therefore not done.** Nothing was optimised: no isolate, no caching, no
change to any renderer.

### Findings, recorded and not changed

1. **A P&L PDF has a ceiling of about 840 category lines.** `pw.MultiPage` keeps the `pdf`
   package's default limit of 20 pages:

   | Lines | Pages |
   |---|---|
   | 760 | 20 |
   | 840 | 21 |
   | 900 | fails with `PdfTooBigPageException` |

   The export controller catches it and reports `ExportActionError`: no file is made, and
   nothing hangs or crashes. A real hotel has tens of lines, so this is far outside use.
   - **Proposed fix:** one argument on `exportPdfDocument`'s `MultiPage`, `maxPages`.
   - **Not applied.** It is a product choice, and no threshold requires it.
2. **PDF rendering runs on the UI isolate.** The stress P&L blocks about 200 ms of frames
   on Windows. The normal exports block 10–20 ms once warm. This breaches no threshold, and
   the A06 figure decides whether it matters on the phone.

**Guards.** `test/core/export/export_performance_test.dart` (8 tests) asserts that every
workload renders, and that every P&L line reaches both the workbook and the PDF text. It
also asserts that the atomic writer leaves no `.part` file behind. Two positive controls
went red and were restored byte-identically (`cmp`): the PDF dropping expense lines past
100, and the workbook doing the same.

## D-327 (A06) — The realistic export is inside T2 on the Galaxy A06; Slice 6 closes
**Date:** 2026-10-01 · **Status:** Measured / Tested (Phase 8 Slice 6 device acceptance). The
entry above stands as written, because this log is append-only.

**Threshold.** T2 is **< 2 s** on the Galaxy A06 and < 1 s on Windows.

**Device.** Galaxy A06, SM-A066B, Android 16 (API 36), USB serial `R9ZY50M3GVX`, USB only
(D-288). The build was dev flavour, `config/dev.json`, HEAD `71118c1`. `flutter test` runs a
**debug** build, the slow case for Dart.

**The benchmark.** `integration_test/export_performance_test.dart` uses the same workloads as
the Windows run, 10 warm runs each. It now also reads back the P&L PDF it wrote and checks it
on the device:
- every revenue and expense line, and every amount, printed whole;
- ₹, scope, period and freshness present;
- the file is under the app-private cache, `/data/user/0/in.krishnaimperial.mis.dev/cache`.

| P&L PDF | Font load (once) | First in session | Warm median (min–max) | Stages, warm (model · render · write) | Pages |
|---|---|---|---|---|---|
| **normal** (4 + 23 lines) | 75.3 ms | **484.5 ms** (model 1.3 · render 455.1 · write 28.2) | **60.5 ms (49.1–94.9)** | 0.7 · 50.1 · 9.1 | 2 |
| stress (40 + 600 lines) | — | 1,116.8 ms | 871.4 ms (834.6–904.8) | 6.9 · 851.5 · 9.1 | 17 |

- **The other reports.** Every normal report's PDF has a warm median of 36–61 ms, and every
  XLSX 12–16 ms. On the phone the XLSX exercise is internal only; Android still offers the
  P&L PDF alone (D-293).
- **Verdict, T2:** the session's first realistic P&L PDF is about 560 ms including the font
  load, against 2 s: **inside**. **T3:** the stress P&L PDF is reported, not a verdict.

**Share and D-310 on the device** (`p7-android-share`). The Android share sheet
(`ChooserActivity`) opened online and offline. Back cancelled it each time and returned to
the app; nothing was sent to any app. The shared file sat in `cache/share/`, its contents
were checked against the canonical P&L, and the earlier file was removed before the next
share. Sign-out emptied the share folder.

**Not exercised on the device this run.** The phase's accountant-revocation step needs
`reports.export` removed from the accountant role on `krishna-mis-dev`. This session's
permission classifier refused that change, so it was not made and not worked around. The
phase therefore failed at that step, by design, and its cleanup voided its 3 sales and
7 expenses. The capability-loss share check and the user-switch half of D-310 come after
that step, so they did not run on the device. Host tests still cover both
(`shared_export_cleanup_test`, `pnl_share_test`). This is carried to Slice 8.

**Smoke.** `p6-android-dashboard` passed: sign-in, Dashboard, reporting sync against the
D-318 paged backend, and P&L. The clean build launched to an empty sign-in screen with no
Flutter error in the log.

**v22 upgrade.** It was **not exercised on the device**: `flutter test` uninstalls the app at
the end of a run, so no earlier database survived. Host migration tests cover it (D-323).

**Clean APK installed.**

| | |
|---|---|
| File | `build/app/outputs/flutter-apk/app-dev-debug.apk` |
| Size | 247,423,705 bytes |
| SHA-256 | `4aa6fcb90ebb931efa7c5b4e8aee39d3972a7d914d2ac75a99bafc95244c49ac` |
| Secrets | 0 of 6 development passwords and no acceptance marker in any of 562 entries; the scanner is clean over the tree, history and artefacts |
| Installed copy | pulled `base.apk` hash matches |
| Permissions | `INTERNET` only |

**Backend.** Ended at the captured baseline:

| | |
|---|---|
| Role capabilities | 80, hash `c1b4870f…` |
| Grants | 7 rows, 5 active |
| Open revenue · open expenses | 3 · 61, all pre-existing |
| Settings rows · closed periods | 0 · 0 |

**The 20-page PDF limit.** It stays as ruled: non-blocking for V1, already handled safely,
and not changed.

---

# Phase 8 Slice 7 — Stress, failure and recovery hardening (2026-10-02)

## D-328 — What start-up did when local storage failed, measured before anything changed
**Date:** 2026-10-02 · **Status:** Recorded (Phase 8 Slice 7, Steps 1–2)

**Recovery-state inventory, read from the code.**

| Step | Where | Failure it can raise |
|---|---|---|
| configuration check | `bootstrap()` | build problem (`ConfigurationRefused`) |
| folder and file path | `resolveDatabaseFile` | `FileSystemException` (storage) |
| key lookup | `DatabaseKeyManager.obtainKey` | store read or write failure, malformed key, missing key |
| open and key check | `applyEncryptionKey` | wrong key or damaged file (`SQLITE_NOTADB`), lock, I/O |
| upgrade | `AppDatabase.migration` | any SQL failure, full disk, lock |
| first write | `OutboxRepository.recoverStaleInFlight` | lock, full disk |
| session, cache, generations | after start-up, inside the app | not start-up failures: fail closed (D-051), coverage markers (D-108), D-240 |

Before Slice 7 the connection was lazy, so the open, key and upgrade failures all surfaced
at the outbox recovery query, and every failure reached one screen showing
`SelectableText('$error')`.

**Baseline, from a temporary probe on real files in temporary folders** (removed after
recording):

| Case | What happened |
|---|---|
| damaged file | `EncryptedDatabaseUnreadable (sqlite 26)` |
| **missing key, file present** | **a new key was written to the secure store**, then `EncryptedDatabaseUnreadable (sqlite 26)`: "missing" was reported as "unreadable", and the next launch would have seen a *wrong* key |
| wrong key | `EncryptedDatabaseUnreadable (sqlite 26)` |
| malformed key | `DatabaseKeyUnavailable` |
| **another connection holding `BEGIN EXCLUSIVE`** | **`EncryptedDatabaseUnreadable (sqlite 5)`**: a lock reported as an unreadable file |
| another connection holding `BEGIN IMMEDIATE` | raw `SqliteException(5) database is locked` |
| busy timeout | **0**, on the raw `sqlite3` connection and on drift's `NativeDatabase` |
| folder cannot be created | `PathExistsException`, with the **full path** in its message |
| key store throws on read | `DatabaseKeyUnavailable` |

**An upgrade was not atomic.** Drift runs `onUpgrade` statement by statement and writes
`user_version` only after it returns. A v20 database whose v22 step failed kept the v21
column, stayed at version 20, and the next start failed **for ever** with
`duplicate column name: ownership_start_date`. One interrupted upgrade (a full disk, a
killed process) would have made the local data unopenable by every later build.

## D-329 — Start-up classifies its failures; schema steps are atomic; a lock is not damage
**Date:** 2026-10-02 · **Status:** Implemented / Tested

1. **Schema steps run in one transaction.** `onCreate` and `onUpgrade` are wrapped by
   `AppDatabase._atomicSchemaStep`. A failure is raised as
   `LocalSchemaMigrationFailed(from, to, cause)`, and nothing of the attempt is kept. The
   existing upgrade suites (v9 → v22, including drift `alterTable` with a column
   transformer) pass inside the transaction.
   - An upgrade interrupted after its last step leaves version 20 and no new column. A
     retry succeeds, `integrity_check` is `ok`, `foreign_key_check` is empty.
   - An interrupted fresh creation leaves version 0, and the next start creates cleanly.
2. **No key is created for an existing file.** `obtainKey(databaseExists:)` raises
   `DatabaseKeyProblem.missingForExistingDatabase` and writes nothing.
3. **Only `SQLITE_NOTADB` and `SQLITE_CORRUPT` count as "unreadable".** Any other code at
   the key check is rethrown as itself.
4. **The open is forced, and the file is released on failure** (`openLocalStore`). The key
   check, the upgrade and `beforeOpen` run in one place. A failure anywhere in start-up
   closes the database, so *Try again* and recovery find the file free.
5. **Classification** (`StartupFailure.classify`): seven kinds, tabled in
   `ARCHITECTURE.md` §52.10. The cause is read through `LocalSchemaMigrationFailed` and
   through drift's `CouldNotRollBackException`. The second is what a full disk
   mid-transaction actually raises: SQLite rolls back by itself on `SQLITE_FULL`, and
   drift's own `ROLLBACK` then fails. This was found by the disk-full test, not assumed.
6. **The busy timeout is not changed.** It is measured at 0: a lock fails at once and is
   shown as *in use*, with "close any other copy, then try again". Within one process
   drift serialises every statement, so a lock can only come from a second process. A
   short timeout (for example 2 s) would let a start wait out a momentary lock. It is
   **proposed, not made**: nothing measured needs it, and any wait added at start-up is a
   wait a person sees.
7. **No raw technical text on screen.** Each kind has its own words and a reference code
   (`START-<KIND>`); the detail goes to `dart:developer`'s log only. A configuration failure
   still shows the build's curated `ConfigurationProblem` sentence, which was written to be
   shown.

**A defect the UI tests found in this slice's first version.** After a reset, a start that
failed again updated a root the person could no longer see: the reset page stayed on top,
reading "Setting aside…". Each failure screen now has a new identity, so a later failure
replaces the whole screen (control C7).

## D-330 — Reset local data and download again: assessed, confirmed, set aside
**Date:** 2026-10-02 · **Status:** Implemented / Tested (D-312 D4; closes D-316)

* **When it is offered.** Only for `localDataUnreadable` and `upgradeFailed`, and always
  after *Try again*. Never for a lock, a storage problem, an unavailable key store (a
  reset needs a writable store), a build problem or an unknown failure.
* **What would be lost is stated first.** `assess()` opens the file read-only with the
  stored key and counts:
  - entries waiting to be sent: pending, in flight, failed, blocked, and any status this
    build cannot name;
  - entries needing attention: conflict, rejected;
  - bills not yet uploaded.

  It never throws. With no key, or a file that will not read, it says the work **cannot
  be checked and may be lost**; it never says "nothing to lose". "No entries waiting to be
  sent were found" appears only when the outbox was read and holds none. The counts cover
  every person's queued work on the device (D-074).
* **Typed confirmation.** The button is enabled only for exactly `RESET`; surrounding
  spaces are ignored and any other case is refused.
* **Set aside, never deleted**, in an order that is safe to stop at any point:
  1. the key is copied to `<keyName>.quarantine.<id>` and read back;
  2. `recovery.json` is written: reason, time, whether a key was kept, no key material;
  3. the sidecars, then the database, then `attachments/` are **moved** into
     `<support>/recovery/quarantine-<id>/` (a failed move is put back, and the active key
     is kept);
  4. the active key is deleted.

  A key store that will not keep the copy stops the reset before anything moves.
* **Forensic honesty.** With a key, the quarantined copy still opens with the key set aside
  (asserted). Without one, the record says the bytes are kept for forensics only and this
  app cannot open them. The quarantine sits in the app-private support folder, and nothing
  in the app reads it.
* **Starting again.** A completed reset simply starts the application again: a new key, an
  empty database at v22, and none of the previous person's data, staging, cache, authority
  or outbox (every table asserted empty).
  - The session is kept (the D-246 file on Windows). The restored person stays fail-closed
    until a confirmed authority refresh (D-051), and only their authorised data is
    downloaded. D-070, D-074, D-240 and D-318 are unchanged.
  - A download that fails leaves the ordinary *Unable to verify your access … try again*
    state.
  - A start that fails after a reset shows that failure. A reset never claims success on
    its own.
* **D-247.** Nothing in this slice reads, opens or moves the forensic database. **But the
  shipped build would now offer a reset for it.** Any normal (non-acceptance) build launched
  on this workstation finds that file with no key and shows *Local data cannot be opened*,
  with the reset option. Before Slice 7 the same launch would have **written a new key**
  into the secure store. Confirming a reset there would *move* that file into quarantine,
  not delete it. Do not launch a normal build on this workstation until the D-247 disposal
  is decided.

---

# Phase 8 — Revenue ledger correctness remediation (2026-10-02)

## D-331 — The Revenue ledger decides sync state before the page is cut
**Date:** 2026-10-02 · **Status:** Implemented / Tested (pre-Slice-8 remediation). Closes the
carry-forward D-323 and the Slice 7 record named. No schema, server or UX change.

**The defect, reproduced on the Revenue code itself.** `RevenueRepository._ledgerSelect`
applied every filter in SQL except sync state, then cut the page with `LIMIT ? OFFSET ?`;
`_mapLedger` then dropped rows whose state did not match. A sync-state filter therefore
searched the newest window only. With 60 synced July sales in front of 75 May conflicts:
page one of *Conflict* returned **0 rows**, page two returned the wrong rows, and the
next-page probe (`limit 1, offset 50`) answered **no**. Eight regressions went red on the
unfixed code.

**The fix.**
* `RevenueRepository.ledgerSyncStateSql` states `_stateOf` as one SQL expression over the
  ledger's own outbox join (`o.entity_id = e.id`, not `done`). It is generated from
  `OutboxStatus.userVisibleState`, the one mapping (D-119), as the expense ledger's is. A
  status this build cannot name becomes NULL and matches no filter.
* The statement selects it as `ledger_sync_state` and, when a sync state is chosen, adds
  `HAVING ledger_sync_state = ?` **before** `ORDER BY … LIMIT ? OFFSET ?`. HAVING rather than
  WHERE, so a row is kept or dropped on exactly the value it then displays.
* The Dart post-filter is removed. The display mapping (`_stateOf`) is unchanged, and a test
  holds the SQL and Dart answers equal for every outbox status.

**Unchanged:** page size 50, the page-at-a-time pager, the reset to page one on any filter
change, `business_date desc, captured_at desc, id desc` ordering (already total), scope,
voided and quarantine predicates, financial figures, outbox semantics.

**Cost (E-HOST, in-memory, indicative; 5 runs after a warm-up).** Same plan shape as the
unfiltered ledger: scan, component index, automatic partial outbox index, temp B-tree for the
order. No index added.

| Fixture | Query | Before | After |
|---|---|---|---|
| 2,800 entries, 83 conflicts | Conflict, page 1 | 5.3 ms, **0 rows** | 3.4 ms, 50 rows |
| | has-more probe | 4.8 ms, **0** | 2.6 ms, 1 |
| | no filter, page 1 | 5.6 ms | 5.4 ms |
| 50,000 entries, 1,471 conflicts | Conflict, page 1 | 83.8 ms, **0 rows** | 48.3 ms, 50 rows |
| | Conflict, deep page | 182.2 ms, **0** | 84.5 ms, 50 |
| | Synced, page 1 | 147.1 ms, 49 rows | 160.4 ms, 50 rows |
| | no filter, page 1 | 82.0 ms | 83.6 ms |

**Positive control.** The pre-fix repository restored: 8 of 12 regressions red. The fixed
file restored byte-identically (`cmp`): 12 of 12 green.

---

# Phase 8 Slice 8 — Windows and Galaxy A06 acceptance (2026-10-03)

## D-332 — Phase 8 is accepted in the real applications; three harness defects, D-248 narrowed
**Date:** 2026-10-03 · **Status:** Implemented / Tested (Phase 8 Slice 8). No product code,
schema or server change.

**What ran.** Five new phases (`p8-recovery`, `p8-migration`, `p8-revenue-ledger`,
`p8-double-submit`, `p8-windows-export`, added at `f807631`) and the existing phases each Phase 8
slice touched, in the real Windows executable and on the Galaxy A06 over USB (D-288). Every one
passes on the final code. The emulator was not used: its ADB session stayed unauthorised, and
the A06 is the reference device (D-313). Results: `PROJECT_STATUS.md`, *Phase 8 Slice 8*.

**Isolation, carried from `f807631`.** Four acceptance "restart" steps had called `bootstrap()`
without the acceptance folder, so on Windows they opened the D-247 database (wrong key, closed,
not modified). They now pass the folder, and `acceptance_isolation_guard_test.dart` refuses the
shape across `integration_test/`.

**Three defects, all in the harness, each found on the phone.**
1. `classify` tapped the expense form's "Charged to" row after the notes were typed. The form is
   a lazy list; on a phone that row had been scrolled out and disposed. It now scrolls back until
   the row is built.
2. `p8-migration` opened the P&L through the Windows Analytics route. It now uses the phone's
   Reports tab on Android.
3. **D-248 recurred once** (`android-pnl`, 2 Oct). Its diagnostic answered the question D-248
   left open: the run had work to do (the header control ran it), so it was the **pull that did
   not start a refresh**, not a run that returned early. A `RefreshIndicator` ignores a new pull
   while the previous one is still dismissing, and the run settling does not mean the indicator
   has gone. The helper now waits for no indicator before pulling. Whether the indicator was
   showing at the failed pull was not recorded, so the cause is **probable, not proven**; the
   diagnostic stays and now records it. This is ordinary Flutter behaviour, not a product
   defect: a person whose pull lands in that animation pulls again.

**Live capability round trip (the D-243 pattern, approved by the project lead for this run).**
During `p7-android-share`, `reports.export` was removed from the accountant role on
`krishna-mis-dev` and then restored; the phone withdrew and restored the share. The role
capabilities read back 80 rows, hash `c1b4870f…`, identical to the baseline. The same run proved
D-310's user-switch cleanup on the device.

**Backend.** The suite's fixtures were reversed by `expense-cleanup` and `revenue-cleanup`; the
open-document id sets, grants, roles, settings, closed periods and ledger are identical to the
pre-Slice-8 capture.

---

# Phase 8 — Performance, Hardening & Recovery: closure (2026-10-03)

## D-333 — Phase 8 is closed, and this is what each of its decisions finally says
**Date:** 2026-10-03 · **Status:** Accepted (project-lead approval: Slice 8 accepted at
`1a4dd12`; the emulator waiver and the D-248 disposition ruled by the project lead)

Phase 8 closes at Slice 9. **Slice 9 is documentation and closure gates only**: no product
code, no test code, no schema, no migration and no server change. This entry gives the final
disposition of every Phase 8 decision and classifies every open observation. **No earlier
entry is rewritten or renumbered.**

### Final dispositions

| Decision | Final state |
|---|---|
| D-312, D-313 | Final. The rulings and the measurement contract (`ARCHITECTURE.md` §52.1–§52.4) |
| D-314 | Final. Every ledger pages with LIMIT/OFFSET; keyset was measured as unnecessary (D-323) |
| D-315 | Final. D-223's `org_id`-led local index stays, unused by production reporting; no schema change |
| D-316 | Closed by D-328 … D-330 |
| D-317 | Closed by D-323 |
| D-318 | Closed by D-320 and D-321 |
| D-319 | Final. The harness stays in `tool/perf/`; its replay-order finding is carried to Phase 9 (D-146) |
| D-320, D-321 | Final. Set-based reporting authority, scoped scans, the paged transport with no historical cutoff; row identity proven 238 of 238 |
| D-322 | Final. One-shot acts never wait on a provider's retries |
| D-323, D-324 | Final. The Expense ledger reaches every match; local schema v22; no server change |
| D-325 | Final. Missed taps are fatal across the host suite and in the Windows shell test; no opt-out remains in `test/` or `integration_test/` |
| D-326 | Closed by **D-326 (fixed)** |
| D-327, D-327 (A06) | Final. Inside T2 on Windows and the Galaxy A06; the 20-page PDF boundary is accepted for V1 |
| D-328 … D-330 | Final. Start-up classification, atomic schema steps, set-aside recovery |
| D-331 | Final. **The Revenue ledger sync-state defect is fixed** (below) |
| D-332 | Final. Slice 8 accepted; three harness defects fixed, none in the product |

### The Revenue ledger correctness carry-forward — FIXED, before Slice 8

Fixed at `34a2834` (D-331), committed before the Slice 8 acceptance and exercised by it.

| Requirement | Evidence |
|---|---|
| sync state decided before the page is cut | `RevenueRepository._ledgerSelect`: `HAVING ledger_sync_state = ?` precedes `ORDER BY … LIMIT ? OFFSET ?` |
| more than one page of matches reachable | `revenue_ledger_sync_state_paging_test.dart`: *every conflict is reachable, beyond the first page*; *both conflict pages are reachable, and say so*. Real app: `p8-revenue-ledger`, 75 conflicts walked page by page on Windows and the A06 |
| no duplicate, no omission | *nothing is duplicated and nothing is skipped*; *the second page continues exactly where the first ended* |
| changing the sync state resets paging | *changing the sync state returns to the first page* |
| deterministic order | `business_date desc, captured_at desc, id desc`, unchanged |
| SQL and Dart agree | *the SQL state is the Dart state, for every outbox status* |
| positive control | the pre-fix repository restored: 8 of 12 red; the fix restored byte-identically: 12 of 12 green |

**No known V1 correctness defect is carried out of Phase 8.**

### Slice 8 acceptance, as accepted

* **Windows: PASS.** Real `krishna_mis.exe` on the isolated acceptance data folder
  (`%TEMP%\krishna_mis_acceptance`, D-246, D-249), held by `acceptance_isolation_guard_test.dart`.
  Windows shell (15 tests) with missed taps fatal; recovery and start-up screens (`p8-recovery`);
  the v21 → v22 upgrade (`p8-migration`); Revenue ledger paging; the double Save press; native
  Save As and Print; offline save; restart; dashboard, P&L, both ledgers and offline revenue.
* **Galaxy A06: PASS.** SM-A066B, Android 16, USB serial `R9ZY50M3GVX`, USB only (D-288).
  The real-device v21 → v22 upgrade kept **8,334 rows over 34 tables**, `integrity_check` ok,
  first ledger page equal, 30 ms. Dashboard; paged reporting sync; P&L; Expense ledger; Revenue
  ledger; share online and offline; `reports.export` removed from the accountant role live and
  the share disappearing, then restored and reappearing (role capabilities read back 80,
  `c1b4870f…`); D-310 sign-out and user-switch cleanup; clean dev APK 247,462,769 bytes,
  SHA-256 `ee942fb6…66b4`, installed hash equal, `INTERNET` only.
* **Android emulator: NOT EXECUTED.** ADB stayed unauthorised. **Explicitly waived for Phase 8
  closure by the project lead**, because the Galaxy A06 — the reference device (D-313) —
  completed the stronger physical-device acceptance. This is not an emulator pass, and it is
  not a Phase 9 release blocker. Emulator runs continue only where useful.

### D-248 — UNCONFIRMED, diagnostic retained

The 2 October recurrence showed the run had work to do: the header control ran the same
refresh and it completed, so **the production refresh itself passed independently**. What did
not start a refresh was the test's pull. The probable cause is the pull landing while Flutter's
previous refresh indicator was still dismissing; the helper now waits for it to go. That is a
plausible harness timing explanation, **not proof of the original cause**. D-248 is not fixed;
its diagnostic stays, and now records whether an indicator was showing.

### D-247 — preserved, deliberately unresolved

The real Windows installation's `krishna_mis.db` was **not opened, migrated, reset,
quarantined or replaced** in Phase 8, and still has no secure-storage key. **Operational rule:
no normal (non-acceptance) build may be launched against this workstation's normal AppData
until D-247 is separately dispositioned** — such a build would now offer a reset and, if
confirmed, set the file aside (D-330). Phase 8's closure does not depend on recovering it. It
is carried to Phase 9 operational planning.

### Open observations, classified

| Observation | Class |
|---|---|
| Revenue ledger sync state after the cut | **CLOSED** (D-331) |
| integration-test drag opt-outs; the Windows shell missed-tap policy | **CLOSED** — no opt-out remains; the shell test is fatal |
| D-326 double Save | **CLOSED** |
| emulator acceptance | **Waived** for Phase 8 (above) |
| D-248 | **Accepted non-blocking**: unconfirmed, diagnostic retained |
| P&L PDF beyond ~840 lines / 20 pages fails safely (D-327) | **Accepted non-blocking limitation** |
| five-year unmatched Expense filter 540 ms and text search 244 ms on E-WIN (D-323) | **Accepted non-blocking limitation** — STRESS worst case; tens of ms at SCALE |
| raw `$error` text on the Masters (both shells), Vendors and Revenue ledger error states; the exception *type name* in the Expense save-failure sentence | **Accepted non-blocking limitation** — presentation, not correctness. A small pass before go-live is recommended; the project lead decides |
| PDF rendering on the UI isolate (~200 ms at stress size, Windows) | **Accepted non-blocking limitation** |
| a short SQLite busy timeout (D-329 §6); `recentExpensesProvider` with no reader | **Future enhancement** |
| D-223 unused local index | **Accepted non-blocking** (D-315) |
| Print-to-PDF empty-file residue (D-309) | **Accepted non-blocking** (unchanged from D-311) |
| D-247 | **Phase 9 operational** |
| D-146 fresh-branch replay in ledger order, owner bootstrapped first (D-319) | **Phase 9 operational** |
| production Supabase, secrets, signing, AAB, Play Internal Testing, Windows installer, reproducible PDFium build (D-298), release executable launch | **Phase 9 operational** |
| physical printer acceptance | **Phase 9 operational** |
| genuine low-disk device check (engine `SQLITE_FULL` proven on host) | **Phase 9 operational** |
| rebuild every installed client (pre-D-320 builds cannot sync reporting) | **Phase 9 operational** |

### Product-lead inputs still outstanding

1. **The production 50:50 ownership effective-from date — UNKNOWN.** Not guessed. Production
   Owner Settlement stays unconfigured and **blocked** until it is supplied.
2. **D-247 disposition**, needed before any normal build is installed or launched on this
   workstation.
3. Whether to make the recommended presentation pass on the remaining raw-error surfaces before
   go-live.
4. Carried unchanged from D-311: the Administration placeholder copy; whether a
   transaction-list export is wanted (D-296); optionally the Print-to-PDF residue (D-309).

The closure evidence is recorded in `PROJECT_STATUS.md`, *PHASE 8 — PERFORMANCE, HARDENING &
RECOVERY: COMPLETE AND CLOSED*. **Phase 9 — Distribution: not started.**

---

# Phase 9 — Production Release, Deployment & Go-Live (2026-10-03)

Phase 8 closed at `d7c7e22`. Phase 9 was scoped by a read-only audit; the project lead
accepted it, accepted the nine-slice plan below, and directed Slice 1 as governance and
documentation only. D-334 … D-345 record that contract. **Slice 1 changes no executable
behaviour, schema, migration, manifest, signing material or server.** Every finding below
that needs code is recorded here and fixed in the slice that owns it.

## D-334 — What Phase 9 is, and its plan
**Date:** 2026-10-03 · **Status:** Accepted (project-lead direction)

**Definition.** Phase 9 is **Production Release, Deployment & Go-Live**. It takes the closed
V1 and produces:

* a production Supabase backend, reached by a deterministic fresh migration replay (D-338);
* production security verification (D-339);
* a signed Android release, an AAB, and a Play Internal Testing build (D-341);
* a Windows production release, an installer, and clean-machine acceptance (D-342);
* operational proof of backup and recovery (D-344);
* a production smoke test, a go-live runbook, and final release closure.

**Phase 9 adds no V1 business feature and changes no financial semantic.** Spec §34 names
the phase "Distribution"; this entry is its detailed definition and **the spec is not
amended** — the version stays **1.2**, as for every earlier phase.

**The plan.**

| # | Slice |
|---|---|
| 1 | Governance and production inputs — **this record** |
| 2 | Release-build hardening (D-335) |
| 3 | Pre-release UX wording (D-343) |
| 4 | Authoritative migration replay and rehearsal (D-338, D-339) |
| 5 | Production Supabase (D-337, D-340) |
| 6 | Android release, AAB, Play Internal Testing (D-341) |
| 7 | Windows release, installer, clean-machine acceptance (D-342) |
| 8 | Production smoke, backup, recovery, go-live readiness (D-339, D-344) |
| 9 | Final V1 release closure |

One slice at a time; **no slice starts automatically**. Product-lead inputs a slice needs
are listed in the Phase 9 input register (`PROJECT_STATUS.md`) and are never guessed.

## D-335 — Six release blockers, verified in the code at `d7c7e22`, owned by Slice 2
**Date:** 2026-10-03 · **Status:** Recorded — **not fixed in Slice 1**

Each was read in the code before it was written down (governance rule 1).

| # | Blocker | Evidence |
|---|---|---|
| 1 | The production Android manifest has no `INTERNET` permission | only `android/app/src/debug/` and `src/profile/AndroidManifest.xml` declare it; `src/main/AndroidManifest.xml` does not, and a release build merges main alone |
| 2 | Release signing is not wired | `android/app/build.gradle.kts`: `release { … // TODO(Phase 9) … signingConfig = signingConfigs.getByName("debug") }` |
| 3 | The R8 rules file the release build names does not exist | `proguardFiles(…, "proguard-rules.pro")` with `isMinifyEnabled = true`; `android/app/proguard-rules.pro` is absent |
| 4 | A prod build with no backend falls into seeded/demo masters | `config/prod.example.json` carries empty values; `AppConfig.hasBackend` is then false and `bootstrap()` runs `seedMasterData` (D-052). Production must refuse to start without its backend instead |
| 5 | Development and production share one Windows data identity | `windows/runner/Runner.rc` fixes `CompanyName` "Krishna Imperial" and `ProductName` "Krishna Imperial MIS" for every build; `resolveDatabaseFile` uses `getApplicationSupportDirectory()` + `krishna_mis.db`; `DatabaseKeyManager.storageKey` is `krishna_mis.db_key.v1` for every non-acceptance build |
| 6 | That shared identity is the D-247 folder on this workstation | a prod build launched here would open `%APPDATA%\Krishna Imperial\Krishna Imperial MIS\krishna_mis.db`, find no key, and offer the D-330 reset |

Slice 2 fixes all six. Blocker 6 is closed by blocker 5's fix plus the D-247 rule (D-336);
it is never closed by touching the D-247 file.

## D-336 — Rulings that bind Phase 9
**Date:** 2026-10-03 · **Status:** Accepted (project-lead rulings; restated so no slice re-asks)

1. **D-247 is untouched.** The legacy Windows database is never opened, migrated, reset,
   quarantined, deleted, renamed or re-keyed, and no normal development or production build
   is launched against that AppData. Windows release work uses isolated AppData or a separate
   clean Windows user or machine.
2. **The 50:50 ownership effective-from date is UNKNOWN** and is not guessed. Owner
   Settlement functionality that depends on it stays blocked; production ownership-share
   configuration stays untouched until the date is supplied. This blocks no other Phase 9
   work.
3. **Transaction-list export stays deferred** (D-296). Not added in Phase 9 without a
   separate approval.
4. **The Print-to-PDF empty file** after authority loss mid-dialog stays accepted (D-309).
   The `printing` plugin is not forked to remove it.
5. **Raw technical error wording is cleaned before go-live** on the Windows and Android
   Masters views, Tax Rates, Vendors, the Revenue ledger and the Expense save failure —
   Slice 3 (D-343).
6. **The Administration placeholder** (desktop router, "arrives in Phase 2") is replaced in
   Slice 3 with neutral V1 wording. Administration functionality is not redesigned.

## D-337 — The production environment contract
**Date:** 2026-10-03 · **Status:** Accepted — **nothing is provisioned in Slice 1**

**Supabase production** must be:

* a separate project from `krishna-mis-dev` and from the rehearsal target (D-339);
* in `ap-south-1` (Mumbai) unless later evidence requires otherwise (D-013);
* email and password authentication, **public sign-up disabled**, users created and
  confirmed by an administrator;
* leaked-password protection enabled **where the selected plan supports it**;
* reached by the client with **only** the project URL and the publishable key, compiled in
  from a git-ignored `config/prod.json` (`.gitignore` already excludes `config/*.json` and
  keeps the `*.example.json` files);
* **no service-role secret in any client binary** (spec §24);
* the private Storage bucket created by the migration chain, never by hand;
* RLS on every public and financial table, **anonymous callable API = 0**.

## D-338 — D-146 made concrete: the authoritative migration replay
**Date:** 2026-10-03 · **Status:** Accepted — the contract Slice 4 builds and rehearses

**Filename order is not authoritative.** A fresh replay in lexical order fails (D-319).
The production and rehearsal replay therefore:

1. reads an **explicit, committed, ordered manifest** of every migration file, each with its
   **SHA-256**, and refuses to run if any file is missing, extra or changed;
2. applies **every committed migration file** in manifest order;
3. **stops** before `20260901132225_revenue_verified_baseline_fy2627.sql`, which refuses to
   install without an owner profile to attribute the baseline to;
4. **bootstraps the Owner** at that point (D-340), then continues;
5. **fails on the first SQL error** and applies nothing further;
6. records migration history deterministically, one row per applied file;
7. never edits a historical applied migration to make the replay simpler (A0, D-056).

**The known ordering anomaly.** `20260829090500_api_surface_invariant.sql` (ledger
`api_surface_invariant_v5`, 20260829133240) must run **after**
`20260829100000_usage_and_attachment_storage.sql`, because it names two functions that file
creates. Every other file runs in filename order. Proven by the D-319 harness
(`tool/perf/localpg.sh schema`), which is the precedent the manifest formalises.

**The file count, verified rather than repeated.** At `d7c7e22` there are **98** committed
`.sql` files in `supabase/migrations/` (the D-319 replay applied 94; D-320 and D-321 added
four). The Slice 1 direction said 99; the count in the repository is 98, and the manifest
will be generated from the repository, not from a number in a brief.

**History will differ from development, and that is correct.** A clean replay ends with one
history row per file. `krishna-mis-dev` holds **105** ledger versions, because Supabase
recorded server-assigned versions for steps that were later committed as grouped files
(`supabase/migrations/LEDGER.md`). The difference is expected and is **never "fixed" by
falsifying history** on either side.

## D-339 — Rehearsal first, production security proven, production smoke read-only
**Date:** 2026-10-03 · **Status:** Accepted

**Rehearsal is mandatory.** Production must not be the first clean Supabase replay. A
non-production rehearsal target receives the D-338 replay first. **Which target — a
separate staging project, or a supported Supabase branch — is PENDING PRODUCT LEAD.** The
audit recommends a separate staging project: it is the same kind of object production is,
and it can be kept.

**Production security acceptance**, before any distribution, must prove:

* RLS on every public and financial table; anonymous callable API = 0;
* the authenticated API surface equals the reviewed inventory (57 at `d7c7e22`);
* Owner, Manager (scoped), Accountant and Data Entry authority;
* one-property and consolidated scopes (D-164, D-187); own-expense semantics (D-169);
* revoked capability, revoked property, user switch, and stale or in-flight publication
  (D-070, D-074, D-240); the paged reporting transport and its authority (D-318, D-320).

**Where each kind of test may run.** Full live and destructive suites run on **rehearsal**.
They must **not** run on production: they create test identities and financial history that
can only ever be voided (D-006). Production security verification is **read-only** wherever
possible — catalogue queries, grants, policies, the API inventory.

**Production smoke is read-only (binding unless the project lead changes it).** Any
production financial write creates permanent, audited history and consumes a `KI-REV` or
`KI-EXP` number. So write-path testing belongs on rehearsal; production avoids test
financial entries; and if a production write is ever needed, it is **one deliberate real
business entry, approved to remain**.

## D-340 — Production bootstrap, and the administration gap
**Date:** 2026-10-03 · **Status:** Bootstrap sequence accepted; **administration path
PENDING PRODUCT LEAD**

**Bootstrap sequence.**

1. Create the Owner's authentication user (Supabase Auth; credentials never in a document).
2. At the D-338 stop point, call `app.bootstrap_owner(p_email, p_full_name, …)` — internal,
   revoked from every client role.
3. Continue the replay.
4. Provision real staff through the approved administration path (below).
5. Grant roles and business-unit scopes (D-025).
6. **Leave Owner Accounts and ownership-share configuration untouched** until the real 50:50
   effective-from date is supplied (D-336 §2).

No real email address or password appears in any document, log or chat.

**The gap.** V1 has no complete Administration screen for user provisioning, role grants or
period close and reopen. The reviewed RPCs exist (`user_provision`, `user_role_grant`,
`user_deactivate`, `user_reactivate`, `period_close`, `period_reopen`); the development admin
tooling is development-specific. Two production paths:

| | Path |
|---|---|
| **A** | a documented SQL-editor procedure in the runbook |
| **B** | a small production administration CLI that authenticates **as the Owner**, asks for credentials at run time, stores no password, and calls only the existing reviewed RPCs |

The audit recommends **B**: it uses the same authority path production enforces, and leaves
no service-role session in anyone's hands. **PENDING PRODUCT LEAD DECISION.** Not
implemented in Slice 1.

## D-341 — The Android release contract
**Date:** 2026-10-03 · **Status:** Accepted — gates for Slices 2 and 6

* application id **`in.krishnaimperial.mis`** (D-029), prod flavour;
* `INTERNET` in the production manifest (D-335 §1), and the merged release manifest
  inspected — no permission beyond what is justified;
* production configuration mandatory; a release refuses to start without its backend
  configuration (D-335 §4);
* production **upload** signing from a local-only `android/key.properties`; **no debug
  signing fallback**; the keystore is never committed (already git-ignored);
* R8 and its rules file present and verified — obfuscation must not break Drift, JSON
  serialisation, `printing` or the plugins;
* release APK and AAB pass the secret scan; exact SHA-256 of each artefact recorded;
* **Play App Signing**; first distribution to **Internal Testing**.

Current version `1.0.0+1`. **The versioning scheme is PENDING PRODUCT LEAD DECISION.**

## D-342 — The Windows release contract
**Date:** 2026-10-03 · **Status:** Accepted — gates for Slices 2 and 7

* production gets its **own environment-specific data identity** — a support folder that is
  not the development one and not the D-247 one, and a distinct database-key name where the
  store is shared (D-335 §5–6); the mechanism is Slice 2's, the choice of name an input;
* production **never reuses** the legacy development or D-247 AppData;
* the installer **preserves AppData on uninstall** (local data, including unsent work and
  the D-330 quarantine, is never removed by an uninstall);
* the release executable is launched only on a clean or isolated environment; install,
  upgrade and uninstall are tested there;
* Visual C++ runtime dependencies are proven on clean Windows;
* SHA-256 of `pdfium.dll` and `sqlite3mc.dll` recorded with each release (D-298);
* **no release launch against D-247.**

The audit recommends **Inno Setup, per-user, no administrator rights**. **Installer choice
and Windows code-signing certificate: PENDING PRODUCT LEAD DECISION.**

## D-343 — Pre-release UX wording (Slice 3)
**Date:** 2026-10-03 · **Status:** Accepted — scope fixed, not implemented

Presentation only. Exactly these surfaces:

| File | What |
|---|---|
| `lib/features/masters/presentation/windows_masters_view.dart` | raw error text |
| `lib/features/masters/presentation/android_masters_view.dart` | raw error text |
| `lib/features/tax/presentation/tax_rates_view.dart` | raw error text |
| `lib/features/vendors/presentation/vendors_view.dart` | raw error text |
| `lib/features/revenue/presentation/revenue_ledger_page.dart` | raw error text |
| `lib/features/expenses/presentation/expense_entry_page.dart` | the exception type name in the save-failure sentence |

Technical detail goes to developer diagnostics (`dart:developer`, as D-323 and D-326 did),
never to user-visible text. The Administration placeholder is replaced with this proposed
wording, to be confirmed in Slice 3:

> Users, roles, period close and audit review are handled by the project administrator in
> this version.

## D-344 — Backup and recovery, physical printer, low disk
**Date:** 2026-10-03 · **Status:** Accepted — proved in Slices 7 and 8

**Server.** The selected Supabase backup or PITR posture is recorded, and **at least one
real restore** into a scratch, non-production target is performed.

**Storage.** Database backups are **not assumed** to include Storage object bytes. If they
do not, an explicit Storage backup or export procedure is established.

**Device.** D-330's reset and re-download stays the canonical device recovery; the
quarantine stays preserved; nothing depends on an OS or device backup.

**Runbook** (skeleton in `docs/PRODUCTION_RUNBOOK.md`) covers at least: password reset,
user deactivation, role and scope change, period close and reopen, lost phone, damaged local
database, restore, production outage, and contact and escalation ownership. No secrets.

**Physical printer**, if hardware is available: A4 prints of a one-property P&L, a
consolidated P&L and one detailed analysis report, checked for ₹, negative values, margins,
repeated headers, page numbers, page breaks, no clipping, and screen/PDF/print amount
parity; then one print cancelled and Save As confirmed working (D-308). Without hardware the
result is **NOT EXECUTED**, never PASS.

**Low disk.** No real device is dangerously filled; **the Galaxy A06 is never intentionally
filled.** Safe evidence may use an isolated small Windows virtual disk, a controlled emulator
data partition, or the existing host `SQLITE_FULL` injection (Slice 7). If no safe
operational test is possible, the result is **NOT EXECUTED / accepted limitation**.

## D-345 — Inputs, secrets and the runbook live in the repository as registers, never as values
**Date:** 2026-10-03 · **Status:** Accepted

* The **Phase 9 product-lead input register** (twenty items, each classified by when it is
  needed) is in `PROJECT_STATUS.md`. No answer is invented.
* The **secrets register** in `docs/PRODUCTION_RUNBOOK.md` lists what exists outside git and
  who holds it. **Secret values are never written into documentation, git, test logs or
  chat.**
* `docs/PRODUCTION_RUNBOOK.md` is a **skeleton** in Slice 1; later slices fill it.
* **A stale checklist line is corrected.** `RELEASE_CHECKLIST.md` §K.2 said "No tax rule is
  seeded (D-043)". That was true until D-096: the four verified rules are seeded by
  `20260901132225_revenue_verified_baseline_fy2627.sql`. The checklist now states the current
  state. D-043 and D-096 are not rewritten.
* `test/docs/phase9_governance_guard_test.dart` holds the parts of this record that a later
  change could silently break: the runbook's sections, the corrected §K.2, the replay
  anomaly files and the committed migration count.

---

# Phase 9 Slice 2 — Release-build hardening (2026-10-03)

## D-346 — The six release blockers are fixed, and production local data has its own identity
**Date:** 2026-10-03 · **Status:** Implemented / Tested (Phase 9 Slice 2). Closes D-335.
Input register #3 approved by the project lead.

**A · INTERNET in every build.** `android/app/src/main/AndroidManifest.xml` now declares
`android.permission.INTERNET`. Merged manifests read after the builds: prodRelease,
stagingRelease, prodDebug, devDebug and stagingDebug each carry `INTERNET` and androidx's
app-private `<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (a signature-level
permission androidx.core declares for itself), and nothing else. The prod release APK reads
the same through `aapt2 dump badging`. A guard requires the main manifest to declare it and
nothing more.

**B · Release signing, with no debug fallback.** `build.gradle.kts` reads a git-ignored
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). With all
four present and the keystore on disk, the `release` build type is signed with that upload
key. Otherwise `signingConfig` is null and `verifyReleaseSigning`, wired to every
`pre…ReleaseBuild`, stops the build before anything is compiled:

> Release signing is not configured: android/key.properties is missing. A release build is
> never signed with the debug key.

Every Android release build needs it — dev and staging too — because a release artefact
signed with the debug key is never wanted. Debug and profile builds never read the file;
`flutter build apk --debug --flavor dev` was rebuilt without one. No value from the file is
printed; `.gitignore` already covered `key.properties`, `*.jks`, `*.keystore`, `*.p12`, and a
guard asks `git check-ignore` each time. **No real keystore was created.** Verification used a
throwaway JKS in the session scratchpad (`CN=Throwaway Slice2 Test, O=NOT FOR RELEASE`, valid
two days), and the `key.properties` pointing at it was deleted after the builds.

**C · R8.** `android/app/proguard-rules.pro` exists and holds no rules: the prod release
APK, the staging release APK and the prod AAB all built with R8 on and nothing extra needed
(the Flutter plugin supplies the engine's rules, plugins ship consumer rules, and the Dart
code is AOT-compiled outside R8). The file says to add nothing without a build finding.
Shrinking was not disabled.

**D · Production fails closed.** `AppConfig.problem` now refuses, before any storage is
opened:

| Build | Result |
|---|---|
| prod with no URL, no key, or either missing | *This production build has no backend configuration.* |
| prod pointed at `krishna-mis-dev` | *This production build is configured with a development backend.* |
| `APP_FLAVOR` naming an unknown environment | refused — no longer silently development |
| Android flavour and `APP_FLAVOR` disagreeing (e.g. `--flavor prod` with `config/dev.json`) | refused |
| a release build that declares no `APP_FLAVOR` | refused |

`permitsOfflineSeed` (no backend **and** not production) now guards the demonstration seed;
development and staging keep their offline mode. No message repeats a value. On the Galaxy
A06 the prod-flavour release built against the dev backend showed exactly the second
message under *This build is not configured safely* (`START-CONFIGURATION`), and was
uninstalled.

**E · Windows production data identity.** Approved values:

| | Production | Non-production (dev, staging) | Acceptance |
|---|---|---|---|
| Windows folder | `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production` | `%APPDATA%\Krishna Imperial\Krishna Imperial MIS` (D-247's folder) | the harness's folder |
| Android folder | the production app's private storage | each flavour's own | — |
| Key name | `krishna_mis.db_key.prod.v1` | `krishna_mis.db_key.v1` | `krishna_mis.acceptance.db_key.v1` |
| Windows key store | its own DPAPI file in the production folder | the plugin store (unchanged) | the plugin store (D-249) |

The environment comes from the compiled build (`APP_FLAVOR`, cross-checked against the
Android flavour), never from text a person can change. One module,
`lib/data/local/local_storage_location.dart`, resolves the folder and the key; bootstrap,
`main()`'s recovery, the session store and staged bills all use it, and it is the only file
in `lib/` that asks `path_provider` for the application support folder.

**Found while building it — the reason production cannot use the plugin store on Windows.**
`flutter_secure_storage_windows` 3.1.2 writes its whole blob to
`getApplicationSupportDirectory()\flutter_secure_storage.dat`, and on Windows that folder is
named by `Runner.rc` (`Krishna Imperial` / `Krishna Imperial MIS`) for every build. A
production key kept there would have been written into the D-247 folder. Production on
Windows therefore keeps its key in `krishna_mis.db_key.prod.v1.dpapi` inside its own folder —
`ProtectedFileSecretStorage`: DPAPI, current user, no entropy (D-036's protection); one file
per entry, atomic replace, serialised, never deleted on a failed read; an unreadable file is
reported as an unreadable store, never as "no key" (D-329). The production folder is built
from `FOLDERID_RoamingAppData` and two fixed names, never from the version resource; on
Windows production never calls `getApplicationSupportDirectory()` (which also creates the
folder it names), never reads the plugin, and its session file is in its own folder with the
D-246 one-time move disabled.

**No migration.** Production starts empty and downloads what its signed-in person may
receive. Nothing copies, renames, opens or re-keys the legacy folder; D-247 is untouched.
Existing development data stays where it is, under its existing key, and is not moved.

**Evidence.** 62 new host tests (`production_config_test`, `local_storage_location_test`,
`release_build_guard_test`) including the real DPAPI round trip and the real roaming folder
computed on this Windows host without touching it; the D-247 guards 1–8; nine positive
controls, each RED and restored byte-identically (SHA-256): C1 the production path computing
the legacy folder (7 red), C1b the resolver using the legacy folder with its defence removed
(3), C2 the production key equal to the legacy key (4), C3 the prod no-backend refusal
removed (5), C4 a debug-key fallback (1), C5 INTERNET removed (2), C6 the seed guarded by
`hasBackend` alone (2), C7 a second application-support caller (1), C8 an unknown flavour
read as development (1).

**Recorded, not changed.**

1. **Windows staging shares the development identity** — the legacy folder and key. Staging
   is non-production and the brief named no staging values; a staging build on a machine
   holding development data would open it. It needs a decision before any staging client
   build is run on Windows (Slice 4 rehearsal) — added to the input register as #21.
2. The acceptance suite's key still lives in the shared plugin store (D-249, unchanged).
3. Release-mode sign-in was **not** exercised: it needs credentials, which this session does
   not type. The staging release started on the A06 to the sign-in screen — encrypted
   store opened, Keystore key created, Supabase initialised, no crash in logcat. Signed-in
   release acceptance is Slice 6.

## D-347 — Version convention
**Date:** 2026-10-03 · **Status:** Accepted (project-lead direction for Slice 2)

* `versionName` is the user-visible semantic version, `MAJOR.MINOR.PATCH`, changed by the
  ordinary rules (fix → patch, feature → minor, breaking → major).
* `versionCode` is a positive integer that increases with **every** Play upload — never
  reused, never decreased, independent of `versionName`.
* Both come from `pubspec.yaml` (`version: 1.0.0+1`) through `flutter.versionName` /
  `flutter.versionCode`; Gradle holds no hand-typed number, and a guard keeps it so.
* The version stays **1.0.0+1** until a real upload needs a new code. Local test builds do not
  bump it. A replacement Internal Testing AAB raises `versionCode` when, and only when, it is
  actually uploaded (Slice 6).
* Dev and staging keep their `-dev` / `-staging` name suffixes and their own application ids.
