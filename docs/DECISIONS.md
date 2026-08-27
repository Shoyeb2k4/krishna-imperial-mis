# Decision Log

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**

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
