# Architecture

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Status: **Sections 1–12 proposed (Phase 0, revised); sections 13–16 and 18–26 describe what
is built and verified; section 17 is the Phase 4 *plan*, since built — read §18–§26 for what
shipped.** Sections 6, 5.3 and 8 carry the project lead's mandated corrections.
Implementation status is tracked in `PROJECT_STATUS.md`.
Last updated: 2026-09-07 — Phase 4 closed

---

## 1. System shape

```
┌──────────────────────────┐        ┌──────────────────────────┐
│  Android app (Flutter)   │        │  Windows app (Flutter)   │
│  phone-first entry       │        │  finance workstation     │
├──────────────────────────┴────────┴──────────────────────────┤
│  Presentation (per platform)  — features/, design system     │
├──────────────────────────────────────────────────────────────┤
│  Domain (shared)  — entities, Money, BusinessDate,           │
│                     capabilities, CANONICAL REPORT SPEC,     │
│                     repository ports                         │
├──────────────────────────────────────────────────────────────┤
│  Data (shared)    — Drift/SQLite (local store + local        │
│                     reporting engine), Sync engine,          │
│                     Supabase remote datasources + remote     │
│                     reporting engine                         │
└───────────────────────────┬──────────────────────────────────┘
                            │ HTTPS (PostgREST + RPC + Storage)
                            ▼
              ┌──────────────────────────────────┐
              │ Supabase — Postgres, Auth,       │
              │ Storage, RLS, SQL functions      │
              └──────────────────────────────────┘
```

**Local-first, not local-only.** The local SQLite database is the app's read model, its
write buffer, and its default reporting engine. The Postgres database is the system of
record. Both apps converge on Postgres through the sync engine described in §5.

## 2. Client technology

| Concern | Choice | Note |
|---|---|---|
| Framework | Flutter 3.44.x, Dart 3.12.x | verified present on this machine |
| Targets | Android, Windows | no web/PWA target is generated |
| State | Riverpod 3, hand-written providers | see D-032: `riverpod_generator` conflicts with `drift_dev` on `analyzer` |
| Routing | `go_router` | declarative routes, auth redirect guard |
| Local DB | Drift + SQLite | typed SQL, migrations, streaming queries |
| Local encryption | SQLite3MultipleCiphers via `package:sqlite3` build hooks | D-030; `sqlcipher_flutter_libs` is end-of-life. Proven on both platforms — §8.3 |
| Secure storage | `flutter_secure_storage` **9.2.4** | Android Keystore / Windows DPAPI. Pinned and needs VS ATL on Windows — D-031 |
| Backend SDK | `supabase_flutter` | auth session, PostgREST, RPC, Storage |
| Time zones | `timezone` (IANA database) | DST-safe business-date derivation |
| Money | project `Money` value object over `int` paise | no `double` anywhere |
| IDs | UUID v7 (client-generated, time-ordered) | index locality + sortability |
| Excel | evaluated in Phase 7 | must support Windows and Android |
| PDF + print | `pdf` + `printing` | `printing` covers the Windows print dialog |
| Charts | `fl_chart` (evaluate) styled by our tokens | no default chart theme ships |

**Single Flutter package**, not a melos monorepo. Layer boundaries are enforced by folder
structure plus import lint rules in CI rather than by package splits.

```
lib/
  app/          bootstrap, DI, router, theme wiring, platform adapters
  core/         design system tokens & components, formatting, errors, Result, logging
  domain/       entities, value objects (Money, BusinessDate), capability model,
                repository interfaces, finance/ (period math, tax math, P&L,
                CANONICAL REPORT SPECIFICATION)
  data/
    local/      Drift database, tables, DAOs, migrations, local reporting engine
    remote/     Supabase datasources, DTOs, mappers, remote reporting engine
    sync/       outbox, push, pull, conflict resolution, scheduler
    repositories/  implementations wiring local + remote + sync
  features/
    auth/ dashboard/ expenses/ revenue/ ledger/ reports/ masters/ admin/
      (each: presentation/, controllers (Riverpod), widgets/)
test/           unit, widget, parity
integration_test/
```

Rules: `domain` imports nothing from `data`, `features` or Flutter. `features` never touch
Drift or Supabase types directly — only repositories and domain types.

## 3. Environments

Three isolated Supabase projects: **development**, **staging**, **production**.

Configuration is compiled in per flavour via `--dart-define-from-file`, using only the
project URL and the **publishable/anon key**. The service-role key never exists on a
client machine, never in the repo, never in CI artefacts that ship. `.env*` files and
`*.keystore` / signing material are git-ignored from commit one.

Android build flavours: `dev`, `staging`, `prod` with distinct application ids so all
three can coexist on one device. Windows: separate build output directories and product
names per flavour.

## 4. Data layer

- Local SQLite is written **first**, inside a single Drift transaction that also appends
  to the outbox. There is no code path where a user-visible save depends on the network.
- Every synced table carries: `id` (uuid v7), `org_id`, `captured_at` (device instant,
  untrusted), `created_at` / `updated_at` (server, authoritative), `row_version`,
  `change_seq`, `sync_state`, and `voided_at` / `archived_at` where applicable.
- Reads are Drift streams, so any successful sync updates the UI reactively.
- Pagination is mandatory on ledger screens; reports run as aggregate SQL, never as
  "load all rows into Dart and fold".

### 4.1 Dates carried on financial rows

Per spec §5 and §9, four date concepts are distinct and all are persisted:

| Column | Source | Used by |
|---|---|---|
| `captured_at` | device instant | forensics only, never authoritative |
| `business_date` | derived from `captured_at` + unit timezone + cut-off, or entered/corrected | ledger, daily views, edit window |
| `pnl_date` / `pnl_period_key` | `COALESCE(accounting_period_end, business_date)`, computed once and stored | **all profitability reporting**, unless the line carries explicit period allocations (D-034) |
| `payment_date` | entered when `payment_status = paid` | cash/outflow reporting only |

Derivation happens once, in shared domain code, and the result is stored. No report
re-derives these rules, so a later configuration change cannot silently restate history.

## 5. Synchronisation protocol

The requirement is explicit: a retry must never create a duplicate financial record.
That is achieved with an **outbox + server-side mutation ledger**, not with request
retries.

### 5.1 Write path (push)

1. User saves. In one local transaction we write the domain rows **and** an outbox entry:

   ```
   sync_outbox(
     mutation_id      uuid v7  -- unique per user intent, generated once, never re-rolled
     entity_type      text     -- 'expense' | 'revenue_entry' | 'vendor' | ...
     entity_id        uuid
     op               text     -- 'create' | 'update' | 'void'
                               -- | 'archive' | 'close_period' | 'reopen_period'
                               -- a business-date correction is an 'update' (§5.3)
     payload          json     -- full canonical document incl. allocation lines
     base_row_version int      -- version the intent was based on (null for create)
     attempt_count    int
     next_attempt_at  timestamp
     status           text     -- pending | in_flight | failed | conflict | blocked | done
     last_error       text
   )
   ```

2. The record shows **Pending Sync**.
3. The sync worker takes a batch of `pending` entries whose `next_attempt_at` has passed,
   marks them `in_flight`, and calls one RPC: `sync_push(mutations jsonb[])`.
4. `sync_push` runs **server side, in a single transaction per mutation**:
   - Insert `mutation_id` into `processed_mutations`. If it already exists, **return the
     stored result and do nothing else** — this is the idempotency guarantee. A duplicate
     network delivery, an app crash after send, or a retry after a timeout all collapse to
     one financial record.
   - Verify the caller's capability **and business-unit scope** for this operation
     (server-authoritative; the client's opinion is ignored).
   - Verify the affected period is **not closed** (spec §13.4). A write into a closed
     period is rejected with a distinct error the UI can explain.
   - Verify the **edit window** and, beyond it, the `transaction.correct.beyond_window`
     capability (spec §13.3).
   - Verify **optimistic concurrency** per §5.3.
   - Apply the change: upsert the header, replace allocation lines, assert
     `SUM(allocations) = header.amount` via a deferred constraint trigger, recompute and
     store `pnl_date` / `pnl_period_key`, bump `row_version`, stamp server timestamps,
     write the audit row.
   - Return `{mutation_id, status, row_version, server_timestamps}`.
5. Client applies the returned server values locally and marks the row **Synced**.

**Retry policy:** deterministic exponential backoff with jitter —
`5s, 15s, 45s, 2m, 5m, 15m, 30m` then hourly, capped. Retries are driven by the outbox
clock, connectivity change events, and app foreground, never by a tight loop.

**Crash recovery:** on startup any `in_flight` entry older than the request timeout is
reset to `pending`. This is safe precisely because push is idempotent.

**Auth expiry:** on 401 the worker refreshes the session. If refresh fails, the queue
enters `blocked_auth`: no entries are dropped, no attempt counters burn, and the UI shows
a re-authenticate banner. Data loss on token expiry is not acceptable.

### 5.2 Read path (pull)

Every server-side row change stamps a monotonic `change_seq` (from one Postgres sequence)
via trigger. The client keeps a per-table watermark and calls
`sync_pull(since_seq, limit)`, which returns changed rows **including tombstones and
voids**, ordered by `change_seq`.

Because a sequence value is assigned at write time but visibility begins at commit time,
a naive watermark can skip a row committed out of order. Mitigation for V1: the client
re-reads with a **safety overlap** (re-request the last N sequence values / last few
minutes) and applies rows idempotently by `(id, row_version)`. At this write volume — a
handful of concurrent operators — that is sound. If write concurrency ever grows, upgrade
the cursor to a transaction-snapshot (`pg_current_snapshot()` / xmin) cursor; this is
recorded as a known limitation, not an unknown one.

Initial sync pulls masters in full and transactions for the current and previous financial
year. Older history is fetched on demand by date range and cached.

### 5.3 Concurrency and conflicts — every financial mutation (corrected)

**Correction to v1.0.** The earlier claim that a void "cannot conflict" was wrong. A void
changes financial state and can be issued from a stale view:

> Device A loads Expense v3. Device B edits it to v4. Device A voids "v3".
> Voiding v4 on that stale intent would destroy an edit nobody reviewed.

Two different mechanisms are in play and must not be confused:

| Mechanism | Answers | Implemented by |
|---|---|---|
| **Idempotency** | "Have I already applied *this exact intent*?" | `mutation_id` + `processed_mutations` |
| **Concurrency** | "Is this intent still based on current state?" | `base_row_version` vs `row_version` |

Re-delivering the *same* void twice is idempotent and succeeds identically both times.
A *new* void based on a stale version is a **conflict** and is refused.

| Operation | `base_row_version` | On mismatch |
|---|---|---|
| Create | not applicable (new identity) | — |
| Update | **required** | reject → `Conflict / Attention Required` |
| **Void** | **required** | **reject → `Conflict / Attention Required`** |
| Business-date correction — **inside `expense_update` / `revenue_update`** | **required** | reject → conflict |
| Master archive | **required** | reject → conflict |
| Attachment upload-state update | not required (advisory metadata) | last write wins, audited |
| Period close / reopen | current period state required | reject with explicit reason |

Conflict resolution is always a human decision: the user is shown their intent beside the
current server state and chooses. Financial records are never resolved by silent
last-writer-wins.

Edge cases and their defined behaviour:

- **Void an already-voided record, same `mutation_id`** → idempotent success (replay).
- **Void an already-voided record, different mutation, matching version** → success,
  no-op, audited once.
- **Void an already-voided record, stale version** → conflict.
- **Update a voided record** → rejected: a voided document is immutable. Correct by
  entering a new document.
- **Any mutation into a closed period** → rejected regardless of version, with a
  period-closed error distinct from a conflict, so the UI can tell the user the truth.

Every one of these rows has a corresponding test (spec §33).

### 5.4 Attachments

Attachments upload out of band from the transaction that owns them, so a bad photo upload
can never block a financial record from syncing.

1. File is copied into app-private storage; an `expense_attachments` row is created with
   `upload_state = pending` and a content hash.
2. Upload targets a deterministic path:
   `org/{org_id}/expenses/{expense_id}/{attachment_id}.{ext}` — the same file uploaded
   twice overwrites itself instead of duplicating.
3. On success, `upload_state = uploaded` and the storage path is synced through the normal
   outbox.
4. Failures retry on the same backoff schedule. Local originals are retained until the
   upload is confirmed.

### 5.5 Sync states shown to the user

`Synced` · `Pending Sync` · `Syncing` · `Sync Failed` (with reason and manual retry) ·
`Conflict / Attention Required`.

## 6. The calculation architecture (corrected)

**Correction to v1.0.** "One aggregation engine in SQL" was the wrong formulation for an
offline-first product. Local execution cannot be optional — an Android device must show
updated financial information the instant an offline entry is saved — and a server-side
engine will exist for large ranges. Two execution environments are a fact of the design.
Pretending there is only one is precisely how two implementations diverge unnoticed.

The rule is restated:

> **One canonical calculation *specification*. Interchangeable engines. Parity proven by
> tests that fail the build when semantics diverge.**

### 6.1 Layering

```
        ┌───────────────────────────────────────────────────────────┐
        │ domain/finance/  — CANONICAL SPECIFICATION (pure Dart)    │
        │  · ReportRequest: date basis, range, unit scope, grouping │
        │  · period math, financial-year math, business-date rules  │
        │  · tax extraction, Net Sales, Operating Profit, margin,   │
        │    period-over-period deltas — ALL derived arithmetic     │
        │  · no Drift, no Supabase, no Flutter, no I/O              │
        └───────────────┬───────────────────────────┬───────────────┘
                        │  ReportingEngine port     │
        ┌───────────────▼──────────┐   ┌────────────▼──────────────┐
        │ LocalReportingEngine     │   │ RemoteReportingEngine     │
        │ Drift/SQLite            │   │ Postgres RPC              │
        │ DEFAULT for every screen│   │ ranges outside local       │
        │ works with no network   │   │ retention; verification    │
        └──────────────────────────┘   └───────────────────────────┘
                        │                           │
                        └───────► identical ◄───────┘
                              primitive aggregates
```

### 6.2 Engines return primitives only

An engine's entire contract is: *given a date basis, a date range, a unit scope and a
grouping, return summed integer paise for the matching rows, plus row counts.* It performs
**no** business arithmetic — no tax extraction, no margin, no netting, no percentage.

Everything derived is computed once, in `domain/finance/`, from those primitives. This
reduces the surface where the two engines could disagree from "the whole P&L" to "select
and sum the right rows" — small enough for a parity test to pin down completely.

### 6.3 Parity suite (build-failing)

- A shared, **sanitised** fixture set (JSON) is loaded into an in-memory SQLite database
  and into a Postgres test database.
- The same `ReportRequest` objects are executed against both engines.
- The suite asserts **exact equality in integer paise** — not tolerance-based comparison.
- The export layer is asserted against the same expected values, because Excel and PDF
  render the same result objects the screen rendered; they contain no formulas.

```
fixture X →  local SQLite P&L : ₹3,26,862
             Postgres      P&L : ₹3,26,862
             Excel export      : ₹3,26,862
             PDF   export      : ₹3,26,862
```

Divergence fails CI. Fixtures deliberately include the awkward cases: cut-off boundary
transactions, split allocations with odd remainders, accrual dates differing from payment
dates, voided documents, zero-revenue periods, and rate changes mid-period.

Until the backend exists, the parity suite runs the local engine against a
**reference implementation** — a deliberately naive, obviously-correct pure-Dart fold over
the same fixtures. That catches SQL mistakes immediately and gives the suite something to
assert against from Phase 1, before Postgres is provisioned.

### 6.4 Offline reporting and freshness (never gated on network)

Every screen reads from `LocalReportingEngine` by default. Reporting never waits for, or
fails because of, connectivity.

Because local results legitimately include entries the server has not seen, every report
result object carries a freshness descriptor, surfaced in the UI:

| State | Meaning |
|---|---|
| **Local — current** (`N unsynced entries`) | Includes everything on this device, some not yet on the server |
| **Synced — as of `<time>`** | Local and server agree; nothing pending |
| **Local — server has newer changes** | A pull is outstanding; figures may rise |

A manager is never left guessing which of these they are looking at. Exports embed the
same freshness statement in their header, so a PDF mailed to someone else states the basis
and the freshness on its face.

### 6.5 Money and rounding rules

- All money is `int` paise. Division (margins, averages) happens only at the presentation
  boundary, on values already rounded by an explicit, tested rule.
- Tax extraction rounds **half-up, once, at the record**, and is stored. Aggregates sum
  stored paise; they never re-apply a rate to a total.
- Allocation splits use **largest-remainder distribution**, so a percentage split of an odd
  amount reconciles to the source total exactly, to the paisa.
- Net sales of zero yields "margin not applicable", never `NaN`, `Infinity`, or `0%`.
- Voided documents are excluded from every aggregate but remain visible in audit views.
- Financial year defaults to 1 April – 31 March; business dates follow spec §9.

## 7. Design system

Tokens first, screens second. `core/design/` defines colour, type, spacing, radius,
elevation, density and motion tokens; components (`AppDataTable`, `MoneyText`,
`SectionHeader`, `FilterBar`, `MetricBlock`, `DrillDownRow`, `SyncStateChip`,
`FreshnessBadge`) consume tokens only. No screen hard-codes a colour or a font size.

Direction: off-white paper surfaces, charcoal ink, restrained brass accent, hairline
rules, generous but deliberate spacing, serif display type for headings paired with a
neutral text face, **tabular figures everywhere money appears**, money right-aligned with
consistent decimal placement, shadows barely present.

Two density scales — comfortable (Android touch) and compact (Windows tables) — are token
values, not separate component implementations.

Indian digit grouping is implemented in one `MoneyFormatter` (₹12,36,420) and verified by
unit tests across lakh/crore boundaries, negatives, and zero. Positive/negative results
are never distinguished by colour alone — a sign or label always accompanies them.

Fonts are bundled assets, not network-loaded, so the apps render identically offline.

## 8. Security architecture

- Supabase Auth (email + password, optional MFA later). Sessions in OS secure storage.
- **RLS on every table.** Baseline: a row is visible only to members of its `org_id`;
  writes additionally require the relevant capability **and business-unit scope**. Policies
  are tested with a dedicated database test suite that asserts both allow and deny.
- All financial writes flow through `SECURITY DEFINER` RPCs that re-check capability,
  unit scope, period state, edit window and row version server-side. Direct table writes
  from clients are not granted for financial tables.
- Storage buckets are private. **Corrected 2026-09-07:** this line used to say access is
  "via signed URLs scoped to the org and expiring". No signed-URL issuer was ever built,
  for either document kind: reading an object back is Storage own authenticated download,
  decided by the bucket policy against the parent document authority (D-063, D-148,
  D-151). The private-bucket requirement is unchanged; the mechanism named was not.
- Client capability checks shape the UI only. The backend assumes the client is hostile.
- No secrets in the repository; CI secrets are separate from production signing material.

### 8.1 Local database encryption — key management per platform (corrected)

The local database holds complete company financial history on both platforms. It is
encrypted with SQLCipher (AES-256). The **key** is a 256-bit value generated with a
cryptographically secure RNG on first run, per installation, and never derived from
anything guessable.

The key must never be: hard-coded; stored in plaintext configuration or preferences;
committed to git; written to a log; or included in diagnostics, crash reports or support
bundles. A CI grep and a logger redaction rule enforce the last two mechanically rather
than by discipline.

**Verified, not assumed** (D-036). The mechanism below was confirmed by reading the code
path that actually executes and then inspecting the artefact the running Windows
application produced.

| | **Android** | **Windows** |
|---|---|---|
| Key store | `flutter_secure_storage` → EncryptedSharedPreferences, master key in **Android Keystore** (hardware-backed where the device provides it) | `flutter_secure_storage` → **DPAPI** `CryptProtectData`, one blob at `%APPDATA%\<Company>\<Product>lutter_secure_storage.dat` |
| Scope | Device hardware / OS keystore; not extractable by a non-root app | `dwFlags = 0` → **user-scoped**, this machine. **No application entropy** is supplied |
| Backup exposure | `allowBackup=false`; data-extraction rules exclude the database and secure store | The blob sits under Roaming AppData but the DPAPI key does not roam, so a roamed profile carries an undecryptable file |
| Residual risk | A rooted device or an unlocked device with a compromised user account can reach the key | **Any process running as the same Windows user** can call `CryptUnprotectData` and recover the key. There is no second factor |

The package also contains a Credential Manager implementation (`CredWriteW`,
`CRED_PERSIST_LOCAL_MACHINE`, AES-128-GCM). **It is not the code path taken** — the Dart
FFI implementation is. `cmdkey /list` shows no credential for the application, which
confirms it. If the residual risk above ever needs reducing, the deliberate fixes are
application entropy passed to `CryptProtectData`, or a user-supplied passphrase.

**Residual risk on Windows is real and is accepted for V1**, mitigated by: requiring a
Windows account password on the finance workstation, short application session lifetimes,
re-authentication after idle, and no automatic sign-in. It is documented here so it is a
known risk, not a surprise.

### 8.2 Logout, key loss and recovery

- **Sign out** clears the auth session only. It **does not** delete the local database,
  because doing so would destroy queued offline mutations that exist nowhere else.
- **Sign out and erase local data** is a separate, explicitly destructive action. It
  **refuses** while the outbox holds unsynced entries, and tells the user exactly how many
  are pending and that they must sync first. It can only be forced with a typed
  confirmation, and the fact is audited on the next successful connection.
- **Key unavailable** (OS keystore reset, Windows profile recreated, app data restored to a
  different device): the database cannot be opened, and this is unrecoverable by design —
  that is what encryption means. The app detects the failure, explains it in plain
  language, and offers to reset the local store and re-download from the server. **Any
  mutation that had not yet synced is lost.** The mitigation is aggressive sync, not false
  reassurance. This is stated in the release notes and in the user-facing message.
- Changing the encryption key (rotation) is not a V1 feature.

### 8.3 Phase 1 obligation — discharged

Encrypted open, persistence and platform-secure key handling were required to be
**proven on both platforms during Phase 1**, not near release. They were:

- **Android** — 8 on-device tests on an emulator.
- **Windows** — the same 8 tests inside the compiled `krishna_mis.exe`, plus external
  verification of the DPAPI artefact (§8.1) and 15 shell tests covering rendering,
  pointer navigation, keyboard focus and overflow at four window sizes.

Two build-machine findings were recorded rather than worked around: the package pin in
D-031, and the Visual Studio ATL requirement, which the project lead resolved.

### 8.4 Server authority (D-037)

The client-side capability, scope, hierarchy, period-lock and edit-window engine gives
immediate offline UX and testable semantics. **It is not the security boundary.** Every
one of those rules is re-decided server-side — RLS for visibility and scope, constraints
and triggers for integrity, `SECURITY DEFINER` RPCs in a transaction where multi-row
integrity is at stake. A modified client must not be able to bypass any of them. The
duplication is deliberate, and the RLS/RPC suite asserts allow **and** deny for each.

## 9. Performance plan

- Indexed on `(org_id, pnl_period_key)`, `(org_id, business_date)`,
  `(org_id, business_unit_id, pnl_date)`, `(org_id, category_id, pnl_date)` both locally
  and in Postgres.
- Ledger screens paginate (50/page) with keyset pagination, never OFFSET on large sets.
- Reports run as single aggregate queries; the UI never folds thousands of rows in Dart.
- Local retention: full detail for current + previous FY; older ranges fetched on demand
  through `RemoteReportingEngine` — which is exactly why that engine exists.
- **Defined escalation trigger:** if a P&L for a one-month range exceeds 400 ms on the
  reference Android device, or the local database exceeds 500 MB, move heavy aggregation to
  the remote engine for the affected ranges. The parity suite already guarantees the
  answers match.

## 10. Information architecture

**Android (phone)** — bottom navigation: Home · Transactions · **[ + ]** · Reports · More.
The `+` opens a fast sheet: Add Expense / Add Sale. Expense flow: Business → Department →
Section → Category → Amount → optional vendor, payment method, reference, receipt → Save.
Business date is pre-filled by the cut-off rule; accounting period and payment details are
progressive disclosure, never in the fast path. Last-used selections are pre-filled where
safe. More: Masters (read/limited), Sync status, Profile, Settings.

**Windows (desktop)** — persistent sidebar:

```
Overview
Transactions   Expenses · Sales · Other Income (if enabled)
Analytics      Profit & Loss · Expense Analysis · Revenue Analysis
               Department Performance · Business Comparison
Reports        saved & generated reports, export, print
Masters        Business Units · Departments · Sections · Expense Categories
               Revenue Categories · Tax Rates · Vendors · Payment Methods
Administration Users · Roles & Permissions · Period Close · Audit Log · Settings ·
               Sync Health
```

Shared across both: a global date-range control, business-unit scope selector, freshness
badge, and the drill-down chain Dashboard → total → breakdown → transaction list →
transaction detail → audit history.

## 11. Testing architecture

- Pure domain logic (Money, BusinessDate/cut-off, tax extraction, periods, allocation
  splits, P&L, capabilities, period locks) is dependency free and unit tested first —
  these are the highest-value tests in the project.
- **Parity tests** (§6.3) are a first-class suite, not an afterthought.
- Sync is tested against a fake transport with injected failures: timeout after send,
  duplicate delivery, 401 mid-batch, version conflict, **stale void**, app kill mid-flight.
  The assertion is always "exactly one financial record exists, with the right amount, and
  no stale intent was applied".
- Database tests run migrations, constraints, RLS allow/deny per unit scope, period-lock
  enforcement, and RPC behaviour.
- Widget tests cover forms, validation, error states, every sync state and every freshness
  state.
- Integration tests cover the end-to-end flows in spec §33.

## 12. Known limitations accepted for V1

1. Pull cursor uses `change_seq` with a safety overlap rather than snapshot-based
   cursors (§5.2). Adequate at this concurrency; upgrade path documented.
2. ~~Costs spanning two accounting months are not prorated.~~ **Withdrawn 2026-08-27**
   by D-034: optional, authorised, exactly-reconciling cross-period allocation is part of
   the model. Automatic day-count proration remains deliberately absent — when added it
   must propose rather than assume.
3. Partial payment is not modelled; `payment_status` is `unpaid` or `paid` (spec §5.4).
4. Windows local-key protection relies on DPAPI, which is user-account-bound rather than
   hardware-bound (§8.1).
5. Approvals are modelled but not enabled in V1 (spec §26).
6. Until the reporting engines exist, engine parity is asserted against a naive reference
   implementation rather than live Postgres (§6.3). The backend itself is now provisioned
   (§13); the parity suite arrives with Phase 5.
7. ~~The offline half of the session lifecycle is proven on Android only.~~
   **Withdrawn 2026-08-28** by D-058: `bootstrap({http.Client? transport})` lets the
   acceptance suite make the real executable's transport fail on either platform, and the
   full offline round trip — go offline, work offline, reconnect, refresh authority first,
   reconcile — is now proven inside the real Windows binary as well as on Android.

---

## 13. The backend half of Phase 2, as built (2026-08-28)

Sections 1–12 were written before a backend existed. This section describes what is
actually running, verified against `krishna-mis-dev` from both the Android application and
the Windows executable.

### 13.1 Remote gateway layout

`data/remote/` is a thin, typed boundary. Nothing above it ever sees a
`PostgrestException`, a SQLSTATE, or a Supabase type.

```
data/remote/
  supabase_gateway.dart          base: holds the client, wraps every call in guard()
  remote_outcome.dart            RemoteOk | RemoteRefused | RemoteUnreachable
  auth_gateway.dart              sign in / sign out / current user, SecureSessionStorage
  authority_gateway.dart         my_authority() → AuthorityRefresh
  master_gateway.dart            pullAll, master_create/rename/archive/restore, usage
  vendor_tax_period_gateways.dart vendor_*, tax_rule_*, period_state/close/reopen
```

Every call returns a `RemoteOutcome`, and the three arms mean three different things that
must never be conflated:

| Arm | Meaning | What the application may conclude |
|---|---|---|
| `RemoteOk` | the server answered and did the thing | apply it |
| `RemoteRefused` | the server **decided** not to | show the reason; never retry blindly |
| `RemoteUnreachable` | no answer | nothing about authority or scope |

A refusal carries a `ServerRefusal`: a stable server code (`KM001` … `KM017`), a
`RefusalKind` the client can branch on, plain-language text aimed at the person who hit it,
and a structured detail payload so a screen can say something specific. **No refusal
message ever contains SQL, a SQLSTATE, a table name or a constraint name** — asserted on
both platforms in the acceptance suite.

`RefusalKind.versionConflict` (`KM003`) is deliberately *not* an authority refusal: a
conflict is about the record and a person resolves it; a missing capability is about the
person and no retry will change it. They surface as two different sync states, `Conflict`
and `Rejected`, and only the latter is terminal.

### 13.2 Authority, and the one call it rests on

`public.my_authority()` returns the caller's organisation, capabilities and business-unit
scopes as **one atomic answer**, derived entirely from `auth.uid()`. It accepts nothing
from the request.

That atomicity is load-bearing. D-048 permits a destructive local purge only on a positive
statement of current scope, so that statement must be one response — not something the
client assembles from several queries, any one of which might have failed. A malformed or
partial payload is therefore treated as **unavailable**, never as "an empty set of grants":
the difference between "the server says you have nothing" and "we could not tell" is the
difference between a correct purge and wiping a manager's cache because a proxy truncated a
response.

### 13.3 ReferenceSync

One pull, in one order, every time authority is established or refreshed:

1. **Refresh authority.** Nothing else happens first. A queued privileged mutation is never
   pushed through a window in which the client is acting on scope the server has already
   withdrawn. The server remains the protection regardless; this removes an avoidable gap.
2. **Purge, only on `AuthorityConfirmed`.** `ScopeCachePurge` compares the confirmed scope
   against the previous snapshot and deletes server-owned reference data for any unit that
   has gone — in one transaction, children before parents. It takes an `AuthorityRefresh`,
   not a list of unit ids, so there is no signature that lets a caller purge on a timeout.
3. **Pull what RLS returns.** Business units, departments, sections, expense and revenue
   categories, vendors, payment methods, tax rules, period locks. The client asks for
   everything and the server decides what that means for this user.
4. **Write it into the local read model**, keyed by id, so a re-pull updates rather than
   duplicates. Seeded ids are derived (D-040), so a restored scope returns the same rows
   under the same ids and nothing is duplicated.
5. **Save the confirmed snapshot** to `AuthorityStore`, keyed by user id.

The outbox is never read or written by any of this.

### 13.4 Session lifecycle

```
                 ┌─────────────────┐
                 │ unauthenticated │◄───────── signOut()
                 └────────┬────────┘
                   signIn │
                 ┌────────▼────────┐
                 │  authenticating │
                 └────────┬────────┘
              credentials │ accepted
                 ┌────────▼────────┐
                 │    verifying    │  ← my_authority()
                 └───┬─────────┬───┘
       confirmed     │         │   never verified here, and unreachable
                 ┌───▼───┐ ┌───▼──────────┐
                 │ ready │ │  unverified  │  ← no access at all
                 └───┬───┘ └──────────────┘
       server says   │
       "not an actor"│
                 ┌───▼─────┐
                 │ expired │
                 └─────────┘
```

`ready` carries a freshness: `confirmed` (just asked) or `stale` (asked before, cannot ask
now). Only `ready` yields real grants; every other state yields `Principal.anonymous`,
which holds nothing, so a screen that forgets to check the state and asks the authoriser
directly still gets "no".

Four rules are load-bearing, and each is exercised on both platforms:

- **Fail closed.** Authenticating establishes *who* somebody is. It establishes nothing
  about what they may do. A user whose device has never received an authoritative snapshot
  gets no operational access — not a reduced menu, not a read-only view. The screen says
  *"Unable to verify your access. Connect to the internet and try again."*
- **Cached authority is per user.** `AuthorityStore.loadFor(userId)` returns nothing for
  anybody else. There is no method that loads cached authority without naming whose it
  should be, so the check cannot be forgotten.
- **Deactivation is a statement, not an outage.** The server declining to treat somebody as
  an actor clears the stored authority and expires the session. It never falls back to
  cache — otherwise a withdrawn account keeps working indefinitely.
- **A user switch isolates before it shows anything.** The previous user's scoped cache is
  purged and their cached authority cleared before navigation opens. Because sign-out
  erases the record of *whose* cache it is, the purge happens at sign-out, while that is
  still known (D-053).

### 13.5 The outbox belongs to people, not to installations

`sync_outbox.actor_user_id` records who queued each intent, and `dueEntries` filters by the
signed-in actor. One person can never submit, edit, retry or inherit another's queued
financial intent, and a signed-out user's work is preserved untouched — it becomes
processable again when that same user signs back in, and at no other time.

### 13.6 What is offline, and what is not

| Concern | Offline behaviour |
|---|---|
| Reading permitted cached reference data | works, marked *Using last verified access* |
| Queuing a privileged mutation | works, stays `Pending Sync`, never shown as accepted |
| Establishing a session for the first time | impossible — authentication needs the server |
| Working on a device that never verified this user | refused, with the message above |
| Purging anything | never — `unknown ≠ revoked` |

### 13.7 Server authority, restated

Every rule the Dart `Authorizer` decides is re-decided in Postgres, and the server's answer
is final (D-037). Three invariants are asserted by migrations rather than by review:

- nothing in `public` or `app` is executable by `anon`;
- `authenticated` may execute exactly one reviewed list of functions, and every function on
  that list is still callable — the assertion fails in both directions, because a policy
  that silently stops working breaks the application just as completely as one that is too
  permissive;
- no RLS policy references the internal `app` schema, which `authenticated` cannot reach.

A `SECURITY DEFINER` RPC checks organisation-wide capability **before** it loads the target
row (D-046), so an unauthorised caller cannot use "unknown entity" versus "no permission"
to discover whether a record exists. The unit-scoped check still runs afterwards, because
it has to know which property the row belongs to.

---

## 14. Dates, and the two layers that must agree (2026-08-30)

§4.1 says business date is derived once, from the capture instant, the unit's timezone and
the unit's cut-off, and then persisted. That covers the date written **onto** a record. It
did not say what date a *rule* compares against, and the Phase 3 acceptance found the gap.

### 14.1 There are two clocks, and only one of them is authoritative

| | Where it comes from | What it is good for |
|---|---|---|
| The **property's business date** | `now()` in the unit's IANA zone, stepped back a calendar day before that unit's cut-off | every business rule: the edit window, which trading day an entry belongs to |
| The **database session's calendar date** | `current_date`, evaluated in the session's timezone — **UTC** on this project | nothing in this product |

`expense_update` measured the seven-day edit window with the second one. Because
`Asia/Kolkata` is UTC+05:30 and the cut-off is 05:00, the two disagreed between **05:00 and
05:29 local time every day**, and inside that half hour an entry that was D+8 old was
counted as D+7 and accepted. The narrowness is an accident of two settings cancelling: a
midnight cut-off widens it to five and a half hours, and a property west of UTC reverses
its sign, refusing edits that are still inside the window (D-067).

### 14.2 One rule, expressed twice, pinned to the same instant

```
        BusinessDate.fromInstant(instant, zone, cutoff)      ← Dart, domain layer
        app.business_date_at(instant, zone, cutoff)          ← SQL, app schema
```

Both take the **instant** as an argument rather than reading a clock, which is what makes
the rule testable at 04:59, 05:00, 23:59 and 00:01 without waiting for those times. Both
are asserted at the same boundary instants — the Dart suite in
`test/domain/business_date_test.dart`, the SQL in migration 0033's own `do` block, which
fails the deploy rather than merely warning. One case is deliberately shared: 23:45 UTC on
15 June, where the UTC calendar date is the 15th and the property's business date is
already the 16th. Client and server are pinned to the *same instant*, not merely to the
same prose.

Deriving the comparison date **through the cut-off**, rather than using the property's
plain calendar date, is what keeps the two consistent: an expense recorded this second has
`elapsed = 0` rather than having already spent a day of its window.

A shared bill charges more than one property, and each property's books are protected
separately. `app.expense_window_today` therefore takes the **greatest** current business
date across the units a document charges — the window must still be open for all of them.

### 14.3 The local read model is a cache, so it does not assert what a cache cannot know

§13.5 and D-062 established the principle; Phase 3's acceptance showed where it had not
been applied. `expense_allocations.business_unit_id` was a real foreign key to
`business_units` with `ON DELETE RESTRICT`, immediately above a `category_id` whose comment
explains at length why it is *not* one.

A foreign key asserts "the target exists in this database". On a per-user cache that is
false by design: the scope purge removes a revoked unit's masters while the expense lines
already synced remain as history, and at sign-out it removes every unit (D-053). So the
restrict fired and **sign-out threw** on any device that had synced an expense — the exact
sequence a shared back-office workstation performs daily, and the one D-054 added the
control for.

Local schema **v8** makes it a soft pointer. The server keeps the real key, where the
assertion is true.

The related lesson is about the guard rather than the column. `CacheClassification` was
supposed to make an unclassified table impossible; the test enforcing it compared the
classified list against itself, so four Phase 3 tables were never classified and nothing
objected. It now compares against `AppDatabase.allTables`, in both directions. **A rule
that nothing evaluates is a comment** — the same shape of finding as D-059, where D-050's
actor filter existed and was never passed (D-068).

---

## 15. What a revocation removes, since D-070 (2026-08-30)

§13.6 and D-048 drew the purge boundary around **server-owned reference data**. The
project lead has moved it: a confirmed revocation now also removes the revoked property's
**synced financial documents** from the browsable local cache, at the authority refresh
rather than at the next sign-out.

### 15.1 The line that replaced "typed versus downloaded"

The old boundary was "nothing a person typed is ever in scope". That reading kept a
revoked manager's cached expense amounts on their device, which is the thing the decision
rejects. The boundary that replaced it is sharper and survives the same reasoning:

| | Purged | Why |
|---|---|---|
| A **synced** expense, its lines, contributions, attachment rows and staged bytes | yes | a projection of server state; the server hands it straight back when authority returns, exactly like a department |
| A **queued, failed, rejected or conflicted** intent and the document rows needed to inspect it | **no** | it exists nowhere else, and losing a property is not a reason to destroy somebody's unsent work |

The retained rows are stamped `expenses.scope_revoked_at` (local schema v9) and are
removed from every canonical financial read — `list`, `query`, `contributionTotal`. They
reach the user only through `listRetainedAfterRevocation`, and only the actor who queued
them, because the outbox is filtered by `actor_user_id` (D-050). Restoring the scope
clears the stamp; a shared document is restored only when every property it charges is
reachable again.

`unknown ≠ revoked` is untouched. `ScopeCachePurge.applyTo` still takes an
`AuthorityRefresh` whose only purging branch is `AuthorityConfirmed`, so there remains no
signature by which a timeout can delete anything.

### 15.2 A partial revocation downgrades the header; it does not merely trim it

```
        held complete            after losing Crystal Canopy
        ─────────────────────────────────────────────────────
        visibility  complete     scoped              ← downgraded
        total       ₹58,000      NULL                ← required
        CCR line    ₹25,000      (removed)
        HKI line    ₹33,000      ₹33,000
        visible     ₹58,000      ₹33,000
```

Leaving the header `complete` beside the one surviving line would publish
`₹58,000 − ₹33,000 = ₹25,000` — the share just revoked. That is the exact arithmetic
§13 and D-062 shaped the local read model to make impossible, so the downgrade is part of
the purge and not a tidy-up after it. The attachment goes too: an attachment is the whole
bill, and D-063 gates it on `is_complete`, which has just become false.

### 15.3 Two ordering rules that are not incidental

**The database first, the filesystem afterwards.** Staged attachment bytes are reclaimed
only once the transaction has committed. A rollback can undo a delete in SQLite; it cannot
put a deleted JPEG back, so nothing on disk is touched while there is still something to
roll back.

**Deleted rows are overwritten, not merely unlinked.** The local database sets
`PRAGMA secure_delete = ON`. Without it the purge was *weaker than the projection it
protects*: D-062's argument was explicitly about a raw SQLite file being readable, and
freed pages kept the revoked figures legible until something happened to overwrite them.
This was found by asserting on the bytes of the file rather than on the rows, and
confirmed by turning the pragma off and watching the revoked ₹25,000 reappear.

### 15.4 The edit surface (D-072a)

This subsection sits under §15 for historical reasons — it was written when the edit gap
was still open and the revocation work was what surrounded it. The rules are the edit
surface's own.


`expense_update` now has a producer. `ExpenseRepository.updateLocally` writes the document,
replaces its lines and contributions and appends the outbox intent in one transaction;
`ExpenseEntryPage.editing` is the same entry screen loaded from an existing document; the
detail panel offers Edit when the document is complete and the person may edit it. The
rules are D-072a's, and three of them are structural rather than conventional:

* **complete-documents only** — `draftFor` refuses a scoped projection, `updateLocally`
  refuses it again at the write, and the server refuses a forged attempt regardless;
* **the version is captured at open and `copyWith` cannot move it**, so a background pull
  cannot re-base an edit somebody is typing;
* **lines and contributions are replaced wholesale inside the transaction**, so a document
  never holds lines that do not add up to it.

Attachment upload — the gap this section used to end on — is built and proven; it has its
own section below.

### 15.5 Superseded: what the client could not do before D-072 was answered

`expense_update` exists on the server, with its edit window measured under the property's
business date (§14). **No client can call it.** `ExpenseRepository` exposes no update,
the detail panel offers Void alone, and nothing in `lib/` ever constructs a
`MutationOp.update` intent for an expense — the endpoint that would dispatch one has no
producer. The seven-day window is therefore, today, a rule about an operation the
applications cannot perform. Recorded rather than quietly filled in, because building it
is a Phase 3 slice with real concurrency semantics attached.

---

## 16. Attachments, from the picker to the bucket (2026-08-31)

§5.4 sketched the upload as four steps. D-073 built it, and three of the four turned out to
carry a rule rather than a mechanism.

### 16.1 Ordering: a bill cannot precede the expense it is evidence for

The Storage write policy calls `may_read_expense_attachments`, which requires the expense
to **exist canonically on the server**. An upload attempted while the expense is still
queued is therefore refused — and refused with something that looks like a permission
error while really being an ordering one.

So ordering is represented rather than hoped for. A freshly staged bill on an unsaved
expense is `staged`; once the expense is queued it is `waitingForExpense`; only when the
server has *accepted* the expense does `promoteAcceptedExpenses()` move it to
`pendingUpload`, which is the first state the upload worker will look at. The worker's due
query cannot see the other two, so the invalid attempt is not merely avoided by the
caller — it is unavailable.

### 16.2 The state machine is durable, and two of its states encode rules

```
staged ─▶ waitingForExpense ─▶ pendingUpload ─▶ uploading ─▶ uploaded ─▶ stagingReclaimed
                                     ▲              │
                                     └── retryNeeded ┘        rejected  (terminal)
```

`uploading` is persisted, so a crash mid-upload is recoverable rather than invisible:
`recoverInterruptedUploads()` returns it to `pendingUpload` at start-up, which is safe
because the object path is deterministic and re-uploading overwrites rather than
duplicating.

`rejected` is terminal and **deliberately carries no `nextAttemptAt`**, enforced by a table
check constraint. A null there once meant "due now", so a refusal retried for ever — the
constraint is in the schema rather than in the worker because the worker is where the bug
was.

### 16.3 Postgres is the record of what evidence exists — not a bucket listing

An object in a bucket is a file. The financial claim *"this expense has a verified bill"*
is a row in `expense_attachments`, written **only** by `public.attachment_register`, which
the client calls after the object lands, passing the byte size and SHA-256 it computed
locally.

**Corrected 2026-09-06 (D-155).** An earlier version of this paragraph said the RPC
"compares them against the stored object and refuses on disagreement". It does not, and
never has: neither register RPC reads `storage.objects` at all, and the size and hash are
taken on trust from the caller. What the hash does mean is one step later and on the client
— `AttachmentUploadWorker` calls an upload `uploaded` only when the hash the **metadata
row** reports matches the one it computed before sending, so a truncated or substituted
upload is not *confirmed*. It could still be *registered*, and adding the server-side object
read that would close that is a change to a reviewed financial boundary with its own scope
(D-127). Stated as it is rather than as it was described.

The consequence that matters for reporting: the canonical answer to "is there a bill?"
comes from the same database, under the same RLS, as the expense — never from listing a
bucket, which no policy makes authoritative and no transaction makes consistent.

### 16.4 The two independences

**An attachment never blocks its expense.** A transient upload failure leaves the expense
`Synced` and the bill `retryNeeded`; the ledger is unaffected. This is asserted on both
platforms rather than argued.

**An expense never re-uploads its attachment.** The upload is not part of the expense's
outbox intent, so an expense redelivery does not re-send bytes, and a re-uploaded object
overwrites itself at its deterministic path instead of creating a second one. One object,
one metadata row, however many times either half is retried.

### 16.5 What a revocation and a void each do to a bill

A revocation (D-070) takes attachments with it — metadata rows *and* staged bytes — on the
same predicate that governs the header: complete-document-only (D-063). A partially
revoked shared bill loses its attachment as part of the downgrade, because the image
states the whole total.

A **void** does not. Voiding is how financial history is corrected, and the evidence for
what was recorded is precisely what an audit needs afterwards. The bill stays, the
document is excluded from every aggregate, and both facts remain inspectable.

### 16.6 The picker itself, and the gap that hid in this very section

An earlier version of this section said the OS picker cannot be driven by the harness, that
a synthetic file is injected at the point the picker returns one, and that the limitation
is stated rather than papered over. All of that was true. It was also, as written,
**describing a picker that did not exist** — see D-077. The injection was proving the
pipeline behind a boundary with nothing on the other side of it, and this document said so
in a way that read like diligence.

The correction is not more prose. It is that the production resolution is now a plain
function of the operating-system name:

```
        attachmentSourceFor('android')  -> AndroidAttachmentSource
        attachmentSourceFor('windows')  -> WindowsAttachmentSource
        attachmentSourceFor(anything)   -> UnavailableAttachmentSource
```

so a **host** test asserts both shipped platforms resolve something that can actually pick
a file, without either device. `attachmentSourceProvider` calls that function directly:
there is no bootstrap step to forget, because forgetting it is exactly what happened.

Android uses the system **Photo Picker** (opt-in; the plugin defaults to an intent that
reads the media store and drags a storage permission with it) and the **Storage Access
Framework** for documents. Windows uses the native **`IFileOpenDialog`**. No storage
permission is declared or requested on Android, and `CAMERA` is deliberately not declared
either — `ACTION_IMAGE_CAPTURE` needs no permission unless the app asks for one.

### 16.7 What the harness can and cannot prove

Everything above is proven on both real clients against `krishna-mis-dev`. The **OS
picker** is not: the Android photo picker and the Windows file dialog are separate
activities the Flutter test harness cannot drive. A synthetic file is injected at exactly
the point the picker returns one — the same technique, and the same honesty, as D-058's
transport injection — and the limitation is stated rather than papered over. Calling that
proof that the picker itself was automated would be false, so it is not called that: it is
recorded as a manual smoke test, one per platform, and until a person runs it, it is
reported as pending rather than passed.

---

## 17. Revenue Engine — the approved plan, since built (2026-08-31)

**Status: this is the planning baseline, and it is now history.** When it was written no
Phase 4 code, migration, table, RPC, widget, provider, test or dependency existed, and the
phase was blocked on verified revenue tax and billing configuration. Both statements were
true then and neither is true now: the configuration arrived on 2026-09-01 and **Phase 4 is
complete** (2026-09-07).

It is kept because the design it records is what the engine was built to, and because the
places where the build diverged from it are the most useful thing on the page. **For what
shipped, read §18 to §26**, which are as-built and win wherever the two disagree.
Decisions D-078 … D-087.

### 17.1 The shape, and why it is not a flat header

The first proposal had revenue as one row with one rate. Four separate corrections from the
project lead all broke it in the same way: **one day's revenue, in one category, can carry
more than one tax treatment.** Room tax may vary by accommodation value; restaurant
treatment may depend on a premises status; banquet may invoice more than one kind of supply.

So revenue takes the shape expenses already have (D-003, D-078):

```
        Revenue Entry  (document — date, unit, category, entry kind, notes, actor)
          │
          ├── Revenue Component   entered amount + basis
          │                       → gross / tax / net
          │                       → the rule snapshot that produced them
          └── Revenue Component   (only when the day genuinely carries a second treatment)

        SUM(components) = header      deferred constraint trigger
```

A simple Nandbhog day is one component and is exactly as fast to enter as before. One model,
one write path, one reconciliation rule — instead of a per-category branch in the code that
computes company revenue.

### 17.2 Conditional tax resolution (D-079)

Five dimensions, and only five. A rule declares conditions; an entry supplies facts.

```
        facts from the entry                 conditions on the rule
        ────────────────────                 ──────────────────────
        revenue category          ─────►     revenue_category_id       (always)
        business date (D-067)     ─────►     effective_from / _to      (always)
        the component's amount    ─────►     value_band_min/max        (nullable)
        chosen supply subtype     ─────►     supply_subtype_id         (nullable)
        configured premises status ────►     premises_status_code      (nullable)
```

**Null means the rule does not depend on that dimension.** Resolution is
**zero-or-exactly-one**, and three properties are load-bearing:

* **bounded, not an expression language** — a general rules engine in the path that computes
  profit would be unauditable and is the speculative module the directive forbids. A sixth
  dimension is a migration and a decision;
* **deterministic** — same facts, same date, same answer, client and server, for ever;
* **ambiguity refuses** — overlapping rules are rejected by constraint at configuration
  time, and an ambiguous resolution refuses the save. Never a tiebreak.

No GST legislation lives in Dart, and none in a widget. The dimensions are a schema; the
rates, bands, subtypes and statuses are configured data.

### 17.3 The entered amount has a basis (D-080)

The rule states which number the operator is being asked for, and the **field label follows
the rule** rather than always reading "Gross":

| Basis | Operator types | Derived, in exact integer paise |
|---|---|---|
| `inclusive_total` | the final customer-billed total | `tax = round_half_up(entered × rate_bp ÷ (10000 + rate_bp))`; `net = entered − tax`; `gross = entered` |
| `pre_tax` | the amount before tax | `tax = round_half_up(entered × rate_bp ÷ 10000)`; `gross = entered + tax`; `net = entered` |

A treatment of `none` gives `tax = 0` and `gross = net = entered` under either basis. The
two are **not coupled** (D-097): `inclusive` needs the total, `exclusive` needs the net
figure, and `none` accepts either because with no tax they are the same number. There is
no third `none` basis — it would describe nothing the other two do not.

Both what was typed (`entered_amount_minor`, `entered_basis`) and what was derived
(`gross`, `tax`, `net`) are stored, beside the rule snapshot. That is what lets a figure be
explained years later without consulting a rule table that may since have changed. Rounding
is half-up, once, at the component; aggregates sum stored paise and never re-apply a rate.

**The basis is not read off the invoice (D-088).** Real evidence made this concrete. The
Crystal Canopy restaurant bill presents `subtotal + CGST 2.5% + SGST 2.5% = grand total`,
which reads exactly like an exclusive treatment — and the management figure the project
lead records is the **tax-inclusive grand total**. Both are true; they describe different
things:

```
        invoice presentation   how the source document shows its arithmetic
        entered_basis          which of those numbers a manager types in here
```

So `entered_basis` comes from the **configured rule**, which is configured from what the
management figure is stated to mean — never inferred from a source document's layout and
never from a heuristic over it. The failure mode this prevents is silent: entering
₹1,00,000 under a wrongly-inferred `pre_tax` basis yields a grand total of ₹1,05,000 and a
Net Sales of ₹1,00,000, every figure internally consistent, every figure wrong, and
Operating Profit overstated by the entire tax component of revenue.

It follows that the input basis is a **management-accounting decision per revenue
category**, confirmed separately for each. All four V1 categories are now confirmed
`inclusive_total` (D-090) — the manager records the final customer-billed amount including
GST where GST applies.

**That they agree is not a reason to collapse the model.** `entered_basis` stays on each
category's rule and is snapshotted onto each component; it is not an organisation-wide
setting, not a default in Dart, and not a fallback when a rule is silent. A rule that does
not state a basis is unresolvable and refuses (D-084). `pre_tax` and `none` stay in the
domain: the rules are date-effective, a convention can change from a date, and a model that
fits only today's cases is the one rewritten the first time a new case appears.

**Categories that agree today still do not share a rule.** Restaurant and Nandbhog are both
5% inclusive and remain two independent rule rows, resolved by `revenue_category_id`, with
no inheritance and no shared row (D-089). Copying a rule from one category to another is a
configuration *action* producing a second independent row — never a link, because a link is
exactly what would let one category's change move another's Net Sales.

### 17.4 Room, Restaurant, Banquet, Nandbhog

**Room (D-081)** — manual-first, one figure per tariff band that had business that day. No
room-by-room data and no PMS. **The form derives its own fields from the configured rules**:
one rule in force means one field; two bands mean two, labelled with the configured
boundary. No threshold is a constant in application code.

**Restaurant (D-082)** — where treatment depends on a premises or financial-year status,
that status is a date-effective configured master, entered by the Owner from what the
accountant states. The application never infers it. A rule requiring one, with none
configured, refuses the save.

**Banquet (D-083, D-091)** — the confirmed treatment is **`none`**: no GST, tax ₹0, net
equal to the entered customer total. **Exactly one active Banquet rule.** The earlier
observation that 5% is sometimes applied is closed as an observation and is not encoded —
a GST-bearing banquet supply, if ever required, arrives as a separately approved rule or
subtype after its accounting treatment is verified. A second active rule would make
resolution ambiguous, which D-084 refuses, and the user would meet a blocked save rather
than the configuration question behind it.

`revenue_supply_subtypes` still exists and still **ships empty**. No subtypes configured
means no subtype field and ordinary behaviour; subtypes configured means a selector and
per-subtype rules. The hinge exists — and is where a taxed banquet supply would most
naturally live — but no speculative subtype is invented.

**Nandbhog (D-024)** — a revenue category under Crystal Canopy Rooftop, not a business unit,
with **no assumed tax treatment**.

### 17.5 No rule, or an ambiguous rule, refuses (D-084)

Refusal covers every failure mode: no category/date rule, an uncovered value band, a
required subtype not chosen, a required premises status not configured, and two rules that
both match. **"No rule configured" stays permanently distinct from a configured `0%` and
from a configured `none`.** The first is a gap; the others are decisions somebody made.
Collapsing them silently overstates Net Sales, and Net Sales feeds Operating Profit.

### 17.6 Offline (D-086)

`ReferenceSync` must cache the revenue tax rules, their condition discriminators, the
supply-subtype master and the premises-status timeline. Online and offline use **the same
deterministic domain resolver**, so they cannot drift.

If the required configuration is not cached, the local save is **refused and nothing is
queued** — a deliberate departure from the expense engine, where a local save always
succeeds. An expense's correctness does not depend on configuration the device may lack; a
revenue figure's does, and a rejected entry sitting in somebody's outbox is worse than being
told at the time that it cannot yet be recorded.

### 17.7 Reporting interface (D-087)

`revenue_period_contributions`, one row per **component**, carrying org, unit, category,
supply subtype, value band, `pnl_period_key`, and gross / tax / net. The mirror of
`expense_period_contributions` (D-060), so Phase 5's engines sum one shape per side.
Component grain is kept deliberately: tax buckets survive into reporting instead of being
flattened at the door.

**Phase 4 populates this interface. Phase 4 does not build the P&L** — that is Phase 5,
with the parity suite D-020 requires.

### 17.8 Unchanged, reused as proven

Business date under D-067 (unit timezone and cut-off, never the device clock, never the
database session's `current_date`). Capability-based edit with the 7-day window and
`transaction.correct.beyond_window` for corrections beyond it; period locks always
authoritative; stale write → `Conflict`; closed period → rejected with its own reason
(D-021, D-026, D-065). Void by capability only, with a mandatory reason and
`base_row_version`. Attachments optional, reusing the D-073a pipeline with no second upload
architecture. Server-issued numbering over client UUID v7 identity, on its own sequence
(D-085). Other Income is out of V1. Integer paise everywhere.

---

## 18. Revenue tax resolution offline, and where the numbers are proven (2026-09-01)

§17 recorded the approved plan. Slices 2 to 5 built the resolution half of it: the domain
resolver, the local schema, the authoritative server schema, and the adapter that lets a
device resolve with no network. Entry, sync and the UI are Slices 6 onward and are not
built.

### 18.1 The adapter is an adapter

`RevenueTaxRepository` reads the Drift cache, reconstructs `TaxRule` objects, and hands the
decision to `RevenueTaxRuleSet.resolve` — the same pure code the domain suite proves and
the same code a future parity suite will run against server fixtures. **No tax semantics
are expressed in SQL**, and nothing is defaulted on the way through.

The one place that discipline is load-bearing is `input_basis`. A cached rule without one
becomes a rule with a null basis, which the resolver classifies as `incompleteRule`. It is
never promoted to `inclusive_total` because all four verified categories happen to use
that: the server refuses to create such a rule now (A1), but a cache can still hold one
from before, and the honest answer is to say so rather than to decide silently whether a
recorded figure includes tax.

It also loads **every** candidate rule for the category rather than filtering to one in
SQL. A query returning the first match by ordering would reintroduce the ranking D-094
forbids, and would hide a stale or corrupted cache holding two matching rules — which is
exactly when a local check earns its keep.

### 18.2 Two empty results that mean different things

```
        cache query returns nothing
              │
    ┌─────────┴──────────┐
    │                    │
 snapshot marker      no marker
 present              present
    │                    │
 noApplicableRule    configurationUnavailable
 "the Owner has      "this device has not
  not configured      received the
  a rule"             configuration"
```

Both stop a revenue entry. Only one of them is a statement about the organisation's tax
configuration, and making it on the strength of a network condition is how a manager gets
told something false about their own company.

The marker is an `app_meta` key written when reference configuration is pulled — **not** a
row count, because a confirmed revocation legitimately empties the rule cache (D-070) and
"no rows" must never be promoted to "no rules exist". The decision happens *before* the
cache is queried, so emptiness is never the evidence.

`configurationUnavailable` carries why: `neverSynchronised` or `revoked`. A confirmed
revocation therefore stops new offline revenue outright rather than letting stale
configuration pick a rate.

**An already-recorded component is untouched by any of this.** It carries its own rate,
treatment, basis and rule id as a snapshot, consults no cache, and stays fully explainable
with no rule rows on the device at all — asserted by deleting every rule and reading the
component back. That is the same property §15 relies on for retained expenses: the thing
that must survive a revocation does not live in a row a revocation may delete.

### 18.3 The cache is read-only, and it is checked by counting

A client that "repaired" or backfilled cached configuration would be inventing a tax fact.
The suite takes a row census of all eight relevant tables, performs every read the adapter
offers, and requires the census to be identical afterwards. Asserting on the code's shape
would have been an argument; asserting on the rows is a test.

### 18.4 Where the arithmetic is proven

Three implementations of one specification now exist: `TaxRule.compute` in Dart, the
adapter that feeds it, and `app.revenue_compute` in Postgres. D-020 requires their
agreement to be proven rather than assumed.

The vectors live **once**, in `20260901144002_revenue_arithmetic_parity.sql`.

**They are not a database object.** That migration contains no DDL at all — two anonymous
`do $$ … $$` blocks and nothing else — so the vectors are a SQL `values (…)` literal
evaluated during deployment and discarded when the block ends. There is no table, no view,
no function and no type to grant, expose through PostgREST, or mutate; `app.revenue_compute`
itself is executable by neither `anon`, `authenticated` nor `PUBLIC`. The Dart half parses
the **repository file**, in `test/`, which no code under `lib/` references. So the
application's runtime depends on none of it: a device could not reach the fixture if it
tried, and a deploy that skipped the assertion would still leave a working application —
it would simply have stopped proving the two engines agree.

```
        migration `do` block            test/support/revenue_parity_vectors.dart
        asserts app.revenue_compute  ◄──── parses the SAME values table ────►  Dart
        FAILS THE DEPLOY on mismatch                                    TaxRule.compute
```

This is deliberately the pattern §14.2 already uses for the business-date rule, and for the
same reason: two implementations of one rule is the situation that drifts, and "both were
written from the same prose" is not evidence.

The alternative — a Dart fixture list plus a public RPC wrapper so a live test could call
`app.revenue_compute` — was rejected. It would expand the reviewed API surface (D-044) for
no product reason, and a test-only endpoint in a financial system is a thing that
eventually gets called.

Thirteen vectors, chosen where rounding decides something rather than where it is
comfortable: one paisa, seven paise, thirty-three paise (the smallest amount at which
half-up matters), an amount past 32-bit, a configured 0% beside a treatment of `none`, and
both exclusive cases. Exact integer equality, no tolerance, plus a **separate**
reconciliation assertion — a pair of wrong figures can still add up. The Dart parser
refuses to run on fewer than ten vectors, because a parity suite that silently checks
nothing reports success.

### 18.5 The conversion nothing exercised

`EnteredBasis` was written and read through Dart's `.name`, which is `inclusiveTotal`.
Both schemas store `inclusive_total`. Every rule carrying a basis would have thrown on
read.

It survived three slices because **nothing crossed the boundary**: the domain tests built
`TaxRule` objects directly and were checking Dart against itself, and the live tests read
`input_basis` as raw JSON without ever parsing it. Two correct halves and no test between
them.

The stored form is now stated explicitly on the enum and pinned on both sides — a host test
on the exact strings, and a live test that reads the real column and requires the client to
parse it. Neither can be edited into agreement with the other, which is the property that
matters; an unrecognised value throws rather than defaulting, because there is no safe
default for *which amount this is*.

### 18.6 What archived configuration means for assertions

No client role holds DELETE on financial configuration (D-006), so a live test that creates
a rule can only **archive** it afterwards. That is the correct trade rather than a gap to
close by granting a delete — with the consequence that archived scaffolding accumulates in
the development project across runs.

Therefore: **no assertion may read `revenue_tax_rates` without filtering `archived_at`.**
One did, and failed for that reason rather than for a defect (D-107).

---

## 19. Revenue configuration synchronisation (2026-09-02)

§18 described a device resolving tax from a cache. This is what fills it. **Slice 6 is
configuration only:** no revenue create transport, no outbox intent, no UI.

### 19.1 The proven sync is extended, not duplicated

`ReferenceSync` already had every hard part: authority first and nothing before it, purge
only on a confirmed answer, pull what RLS returns, one local transaction, remember the
confirmed scope. A second engine for revenue would have had to re-derive all of that and
would have drifted from it. So revenue is three more datasets and one more thing written
at the end of the same transaction.

The three datasets are **not optional extras**. The resolver consults all of them: a rule
may name a value band, a supply subtype and a premises status, and a rule naming one the
device never received resolves to `missingFact` — which an operator reads as *"choose a
band"* when there is no band to choose. Received together or not at all.

### 19.2 What a complete snapshot is

For one user and one business unit:

```
        revenue categories of the unit
        tax rules for those categories      — ALL effective dates, incl. end-dated
        value bands for those categories    — incl. superseded (D-100)
        supply subtypes for those categories
        premises tax statuses for the unit  — incl. end-dated (A2)
```

Recorded in `revenue_config_snapshots`, keyed `(user_id, business_unit_id)`, carrying the
dataset codes proven present, the greatest `change_seq` observed as the snapshot's
generation, and the **server's** confirmed time. The device clock sits beside it and
decides nothing.

**Zero rows is a synchronised answer.** The verified baseline has no bands, no subtypes and
no statuses; that is configuration, not absence of it. Storing a dataset list rather than
counting rows is what keeps *"the Owner configured none"* distinct from *"this device never
asked"* — the same distinction §18.2 draws for rules, extended to the datasets that were
not there to draw it for.

### 19.3 Atomic, and the marker is the last thing written

```
        confirmed authority
          → purge revoked scopes            (D-048: only on a confirmed answer)
          → pull the whole snapshot
          → VALIDATE it                      (§19.5)
          → one transaction:
                upsert every dataset
                remove rows the snapshot no longer contains
                withdraw claims for units the snapshot does not cover
                write the completeness marker   ← LAST
          → commit
```

The forbidden sequence is *rules succeed → mark synchronised → bands fail → device claims
complete configuration*. It cannot happen here because the marker is inside the same
transaction and is the final statement in it: a failure anywhere rolls back the claim
together with the data.

### 19.4 What a failure leaves behind

A pull that does not arrive changes nothing: the previously committed snapshot stands, the
marker is untouched, and it is reported as stale rather than wrong. This is the
`unknown ≠ revoked` rule (D-048 §1) applied to configuration, and both halves are tested —
a confirmed pull that omits a unit **does** withdraw that unit's claim, and a failed pull
withdraws nothing at all.

### 19.5 Fail closed on a payload, never repair it

The server prevents ambiguous and incomplete configuration; the client checks anyway,
because replacing working configuration with unusable configuration is strictly worse than
keeping yesterday's — the device would then refuse every revenue entry *while claiming to
be synchronised*.

Refused: a rule with no input basis, an unrecognised basis or treatment, a rule naming a
band or subtype the snapshot does not contain, a band describing no range. On refusal the
prior snapshot is retained whole, the marker does not move, and the reason is reported
separately from a transport failure — they are different facts and a diagnostics screen
must not conflate them.

**Nothing is repaired on device.** Filling in a missing basis or inventing a range would be
deciding a tax fact on the server's behalf (D-043).

### 19.6 The read boundary, narrowed rather than widened

Reference configuration is read the way Phase 2 already reads masters: RLS-protected
`select`, no new snapshot RPC, the server deciding what the scope means. Auditing it before
synchronising through it found three policies that had never been exercised (D-110) —
including one requiring a capability **no role holds**, which no client could ever have
satisfied. All three now match the tax-rule policy: this organisation, and a unit the
caller may view.

The first attempt at that fix broke every band and subtype read by calling a helper in
`app`, which `authenticated` cannot execute (D-109). That is D-045 in a new place, and the
lesson is recorded a second time because the first recording did not generalise into a
check that would have caught it.

### 19.7 Bands, and why sync must not tidy them

A band's bounds are write-once (D-100). Sync upserts by the band's own id, so supersession
arrives as a **second band plus a pointer** and never as an edit to the first one's bounds.
Updating band A's ceiling to band B's would retroactively redefine what every rule
referencing A applied to, for dates already recorded — which is the harm the whole
date-effective model exists to prevent.

Only live bands are offered for a new entry; superseded ones stay resolvable so history
remains explainable.

### 19.8 Nothing here owns financial explainability

Reference rows are a cache and are removed when the authoritative dataset no longer
contains them. A recorded component is unaffected by any of it: it carries its own rate,
treatment, basis and band snapshot and consults no reference row, so a band deleted by a
sync still explains the entries that named it (D-070 §11). Retained unsynced work is
likewise the actor's and is not made browsable by configuration arriving — reference data
conveys no financial-document ownership (D-074).

### 19.9 Freshness, and the question that is not answered here

The project has no TTL anywhere. `confirmed` / `stale` / `unknown` describes whether the
device could ask, not how old the answer is, and cached authority already works offline
indefinitely on that basis.

Slice 6 applies that policy unchanged: a complete snapshot permits offline resolution for
as long as it stands. **That is the existing rule, not a new decision**, and the question of
whether revenue tax configuration should have a maximum age before a device refuses to
create *new* revenue is recorded as D-112 and left to the project lead. It matters because
a stale permission is caught server-side on delivery and a stale rate is not.

---

## 20. The revenue create path (2026-09-02)

§19 filled the configuration cache. This is the first complete revenue mutation: draft →
eligibility → deterministic local resolution → one atomic write → outbox → `revenue_create`
→ reconciliation. **Slice 7 builds no entry screen and no ledger surface** — Slices 8 and 9
own those, and a test asserts neither exists.

### 20.1 Checked before it is written, which expenses are not

An expense always saves locally and lets the server refuse later. That is right for an
expense: its correctness does not depend on configuration the device might lack, because an
amount, a vendor and a category are facts the operator supplies.

A revenue figure is different. Its tax comes from configured rules, so a device that cannot
resolve them cannot produce a defensible number at all — and a rejected revenue entry
sitting in somebody's outbox is worse than being told, at the time, that it cannot yet be
recorded (D-086).

So the whole contract is evaluated first:

```
        signed-in principal, confirmed
        revenue.create for THIS business unit        (org-wide covers every unit)
        at least one component
        category exists here AND belongs to that unit
        period open
        configuration complete for (user, unit)      §19.2
        configuration fresh                          D-112, 24 hours
        exactly one rule resolves per component      D-094
        every required conditional fact supplied
```

Only then does anything reach the database. Seventeen refusal reasons, each naming a
different thing to do about it, because *"Cannot save"* tells an operator nothing and a raw
exception tells them something they cannot act on and should not see. Asserted: no refusal
message contains an exception name, a SQL state, a table name or a refusal code.

### 20.2 One transaction, and the marker of a correct one

Entry, components with their full financial snapshot, and the outbox intent all commit
together. There is no ordering in which a revenue document exists without the intent to
send it, or an intent points at a document that was never written. Proven by forcing a
failure at the component write and finding nothing at all — no orphan header, no orphan
intent.

Every component stores what was typed and everything derived from it: entered amount and
basis, gross, tax, net, the rule id, rate and treatment, and the band identity and bounds
that selected it. **A recorded attempt is never re-rated**: the payload is captured at save
time and delivered verbatim, so a retry sends the facts the operator approved rather than a
re-resolution against configuration that has since arrived.

No transaction number is invented locally. The server issues `KI-REV-…` on acceptance, and
two offline devices inventing one would both claim the same permanent-looking reference
(spec §8.4).

### 20.3 The client declares; the server decides; neither overwrites the other

`revenue_create` resolves the rule and computes gross, tax and net itself and ignores
anything the caller says about them. What it did **not** do was give the client any way to
learn that its own figures differed — so an entry prepared under a rule that had since
changed would be accepted, and the operator who approved one GST figure would hold a
document stating another, with nothing reporting the disagreement.

```
        client sends   entered amount + the facts + declared gross/tax/net
        server does    resolve, compute, and COMPARE the declared values
        on agreement   record the server's own figures
        on difference  refuse KM030, carrying both sets and the rule
```

The declared values are **compared, never used**. A mismatch becomes a **conflict**, not a
rejection: two defensible answers exist and a person chooses between them, exactly as a
stale row version is handled and for the same reason — financial state is never resolved by
silent last-writer-wins (§5.3). The local attempt keeps the figures the operator approved.

### 20.4 One transport, one queue

Revenue is a registered mutation type in the engine that already exists: the same outbox,
worker, backoff clock and actor filter. `RoutingMutationEndpoint` gained a third arm and
`RoutingMutationReconciler` composes the per-type reconcilers; a build with no revenue
endpoint routes the intent to one that does not recognise it and answers terminally, so the
entry is **kept for a person to see** rather than discarded.

Recovery re-sends **the same intent**. A fresh mutation id would be a second financial
record for one act, and no care afterwards could tell the two apart — least of all when
both carry a real KI-REV number. Proven against a server that commits and then loses the
answer: the client stays queued and invents nothing, the retry replays, and the entry
reconciles to the number it never saw the first time.

### 20.5 D-112, and the one distinction it turns on

A complete snapshot supports **new** offline creation for 24 hours from its
server-confirmed timestamp — inclusive at the boundary, per user and per business unit, no
override. A device clock reading materially earlier than that timestamp fails closed with
its own reason, because a backwards clock would otherwise make every snapshot look newly
fresh, and *"your clock is wrong"* sends somebody to fix a different thing from *"your
configuration is old"*.

**Expiry governs creation and nothing else.** An attempt created at ten hours' age and
still pending at thirty is submitted unchanged: it carries its own snapshot, and the server
decides whether it remains acceptable. Deleting or re-rating it because a window closed
would destroy work nobody asked to lose — and the tempting reading of the rule is exactly
that one, which is why it is tested explicitly.

### 20.6 What the acceptance found, and why it took this long

Two Slice 4 defects surfaced the first time anything exercised the path rather than the
boundary around it.

`revenue_create` **had never successfully created an entry**: an OUT parameter named
`financial_year` collided with the column in its own `on conflict` target, so every call
failed after all validation and after the inserts (D-115). And all three revenue read
rules required `revenue.view.all`, **a capability no role holds**, so the only sanctioned
way to read revenue returned nothing to anybody including the Owner (D-116) — the same
defect D-110 recorded for the premises-status policy, in three more places.

Both were invisible to a suite that proves the boundary. A view that returns nothing to
everyone satisfies *"a scoped user sees less than the Owner"*, and a create RPC nobody
calls cannot fail. The general assertion added with the second fix — that every capability
named by a revenue policy or projection is actually granted to some role — refused its own
migration on the first run, naming a place the fix had missed.

*A rule that nothing evaluates is a comment* (D-068, D-071, D-077). This is its quieter
twin: **a rule that can never evaluate true refuses everything, silently, and looks like a
security boundary working.**

---

## 21. The Android revenue surface (2026-09-04)

§20 built the create path. This is the screen that calls it, and the two things about it
that are not cosmetic.

### 21.1 The form's shape is configuration, not code

An entry screen for revenue cannot know how many amount fields a category has, because
that is a property of the configured tax rules rather than of the category. Room has one
generic rule today and may have two banded ones later (D-081).

So the screen asks:

```
        rules.liveBandsFor(category, businessDate)
          []            -> one plain amount field
          [lower]       -> one field, labelled with the band
          [lower, upper]-> two fields, in configured boundary order
```

No threshold appears anywhere in the widget layer, and nothing compares an amount against a
band's bounds — a band is **selected**, never calculated (D-094). A second Room band is
therefore a configuration change and a sync, not a release, which is asserted by a test
that configures two bands and finds two labelled fields.

The amount label comes from `EnteredBasis.fieldLabelFor(treatment)` and so takes the
**treatment** as well as the basis. Banquet reads *"Amount billed to the customer"*, and its
breakdown says **No GST** rather than "GST ₹0" — the first is the statement the
configuration makes; the second reads like an amount that happened to come out at nothing.

### 21.2 The preview is the record

Every figure under the amount field comes from `TaxRule.compute`, which is the same call
`RevenueRepository.createLocally` makes when it writes and the same arithmetic
`app.revenue_compute` is proven equal to, to the paise (D-105). They cannot disagree,
because they are one function called twice rather than two that agree today.

That is why the acceptance asserts the stored component's paise against the same parity
vectors the migration asserts: what the operator approved and what was persisted are
checked to be the same number, on a real device.

### 21.3 What a screen finds that nothing below it can

Three defects reached a working, reviewed, green state and were caught only by rendering
(D-119): an infinite rebuild loop that presented as a `pumpAndSettle` timeout and would have
presented on a phone as heat and a flickering form; a five-pixel overflow that appeared only
in the conflict state, which is the one an operator most needs to read; and a screen that
called `Navigator.pop` unconditionally — true in production, an assertion the moment the
page is not pushed.

None was visible in the domain, the repository or the server. That is the argument for a
widget suite that drives the real providers rather than one that renders a stub.

---

## 22. The Windows revenue ledger (2026-09-04)

§21 built the phone's entry surface. This is the finance workstation's, and the three
things about it that are not presentation.

### 22.1 The query is the ledger

`RevenueRepository.query` takes a `RevenueQuery` — an interface the presentation's
`RevenueFilter` implements — so the data layer never learns a filter bar exists. Every
predicate is SQL:

```
        e.scope_revoked_at IS NULL          <- first, so no branch can forget it
      + voided / dates / unit / category
      + kind / actor / search
      + business_unit_id IN (authority)
      ORDER BY business_date DESC, captured_at DESC, id DESC
      LIMIT ? OFFSET ?
```

The `id` tie-break is load-bearing. Two sales recorded in the same second on the same day
have no defined order without it, and an undefined order across a page boundary is exactly
how a row is shown twice or skipped — asserted by paging 25 rows in windows of six and
requiring 25 distinct ids.

Dates filter on the **business date**, never `captured_at`: a sale rung up at 02:00 belongs
to the previous trading day (D-067), and filtering on the capture instant because it suits
SQL would put it in the wrong month of a report.

**Scope is not a filter.** `businessUnitIds` comes from confirmed authority and
`businessUnitId` is a choice; applying authority after paging would compute a window over
rows the reader may not have, and `Clear filters` deliberately cannot drop it.

### 22.2 The panel explains the sale from the sale

Nothing in the detail surface re-queries `revenue_tax_rates`. Rate, treatment, basis and
band all come from the component's own snapshot, which is the whole reason it exists
(D-080): a June sale must still explain itself in December, and a panel that re-resolved
would restate history the moment a rate changed. Proven by deleting every rule and finding
the panel unchanged.

`none` and a configured `0%` are shown differently — **No GST** against **GST at 0%** —
because ₹0 arrived two different ways and only one of them is a rate anybody set (D-091).

### 22.3 What rendering at real sizes finds

Slice 8 recorded a chip overflowing a phone by five pixels in the conflict state alone.
Slice 9 produced two more of the family: a dropdown that laid its selected item out at
natural width, and a table minimum written down as `940` beside columns summing to `1204`,
which overflowed an ordinary 1366pt laptop by 211 pixels.

Both are now structural — `isExpanded`, and a minimum **derived from the column widths** —
and the widget suite renders the ledger at three sizes in every sync state, because the
states differ in width and the dangerous one is the one an operator most needs to read.

A hand-picked layout constant sitting beside the values it describes will drift from them,
and the drift is invisible until something renders at the size where it matters.


---

## 23. Correcting and voiding a sale (2026-09-04)

§20 built the create path and §21–§22 the two surfaces. This is how a recorded sale is
changed afterwards, and the four things about it that are not presentation.

### 23.1 The server re-rates every correction, and says so when it disagrees

An expense correction restates figures the operator supplied. A revenue correction cannot:
its tax comes from configured rules, so the server resolves again — against the entry's
category and its **new** business date — and computes gross, tax and net itself.

```
        client sends   entered amount + the facts + declared gross/tax/net
        server does    re-resolve, re-compute, and COMPARE the declared values
        on agreement   record the server's own figures
        on difference  refuse KM030, carrying both sets and the rule
```

The declared values are **compared, never used** (D-114). The failure this closes is silent:
a correction prepared under a rule that changed between opening the form and pressing save
would otherwise be accepted, and the operator who approved one GST figure would hold a
document stating another.

`revenue_update` also differs from `expense_update` in two further places, both deliberate
and both recorded in D-124: it checks **the source period as well as the target**, because
moving an entry out of a closed month affects that month's totals as surely as moving one
in; and it takes **no business unit and no revenue category**, so a correction that moved
revenue between properties is unavailable rather than guarded.

The transaction number is never restated. It belongs to the document's identity and survives
every correction — the defect D-072a records for expenses.

### 23.2 One queued intent per document

This is the substantive divergence from the expense engine, and it exists because the
expense shape has two reachable failure modes:

```
        create queued, edit queued   ->  create fails transiently, update arrives first,
                                         KM015, terminal - a legitimate correction
                                         becomes a rejection
        two edits before either syncs ->  both carry the same base version; the second
                                         conflicts with a version nobody ever saw
```

So a revenue document has at most one queued intent, and a correction rewrites it in place —
a create stays a create, an update stays an update on the version it was first based on, and
a void replaces either. The entry keeps its own mutation id, actor and creation time, so
idempotency, ownership and retention all still key on the same values; only the payload
changes, and the payload is the operator's current intent.

Voiding a sale whose create has not reached the server is refused. There is nothing to void,
and cancelling the create instead is a different decision.

### 23.3 A conflict is resolved by a person, in one direction only

Two refusals mean *two defensible answers* — a stale row version (`KM003`) and a tax
mismatch (`KM030`) — and both surface as `Conflict / Attention Required`. Everything else is
terminal, and a closed period keeps its own truthful reason rather than being dressed up as
a conflict.

**Review latest** is the only forward action:

```
        capture the attempt (the local row still holds it)
          -> re-read the document and its components from the server
          -> replace the local copy
          -> show both, side by side
          -> reopen the form on the CURRENT record, if the operator still wants to
```

The replacement is refused while an intent may still be delivered, and permitted on a
`conflict` or `rejected` one — where the attempt survives in that intent's own payload, so
nothing is destroyed. The intent is never deleted (D-048 §2). There is no merge and no
"overwrite anyway", and reapplying re-enters the correction against what the sale now says
rather than re-sending an old draft with a refreshed version number.

### 23.4 A void keeps everything except the figure's place in reporting

`revenue_void` needs `revenue.void` for the property, an open period, a matching row version
and a mandatory reason. The document, its number, its components and their snapshots all
remain; the sale is excluded from ordinary reporting and stays fully inspectable
(spec §14, D-006). A voided sale is immutable — a correction against it is refused `KM020`,
and the interface offers neither Edit nor Void and says why rather than showing two dead
buttons.

A stale void is refused. Device A loads v3, device B corrects it to v4, device A voids "v3":
voiding v4 on that intent would destroy a correction nobody reviewed (D-021). Proven against
the real server.

Locally the void is stamped as **the actor's intent**, exactly as an expense is: the local
write succeeds, the server decides, and a refusal makes the intent terminal `Rejected` and
keeps it for a person rather than quietly reversing it.

### 23.5 What is offered is decided by capability, and by the document's own state

`mayEditRevenue` and `mayVoidRevenue` read capabilities and never a role name — a widget
that read `role == 'accountant'` would be a second authorisation model the server never
consults, and the first thing to drift. The server refuses regardless (D-037); the client
rule exists so the interface does not offer what would be refused.

`revenue.edit.all` is new in this slice (D-128) and gives revenue the split expenses have
had since D-072a: a Manager corrects what they recorded, an Accountant corrects anybody's.
The client cannot know the edit window or the period lock without asking, so those are
refused server-side and surfaced as sentences rather than predicted.

### 23.6 What the mandatory acceptance found (2026-09-05)

Slice 10's implementation reached a clean `analyze`, a green host suite, a green widget
suite and a green live boundary suite. The three acceptance phases it had **not** run then
found two defects, and both are worth stating because of *where* they lived.

**A conflict was unresolvable through the shipped path (D-130).** A correction re-applied
after Review latest carried the row version it had already been refused on, so it was
refused again, and would have been for ever. Every layer was individually correct — the
server was right to refuse a stale version twice, the repository was right to coalesce, the
widget was right to offer Review latest. The defect lived in the **sequence**, which needs
two clients and a real server to exist at all.

**Two surfaces described one sale differently (D-131).** The ledger derived a sale's sync
state by joining the outbox on the document's id; the detail panel joined on
`pending_mutation_id`. On the accumulated Windows database that pointer was null for a
document whose correction had just been refused, so the panel showed **Synced** for a sale
in conflict — hiding the banner and the one action that resolves it. There is now one
derivation, and it is a **stream**: a conflict arrives from the sync worker, which
invalidates no provider and knows about no screen, so a cached snapshot went on being wrong
until something else happened to refresh it.

Both are the same shape as the findings this project keeps recording, one level up from
where they usually appear. D-104 was a *conversion* nothing exercised; D-119 was a *rule*
duplicated into two switches. These are a **path** nothing traversed, and a **query**
duplicated into two joins.

### 23.7 Proving a lost response, rather than a duplicate call

A duplicate RPC call proves idempotency and proves nothing about recovery: in a duplicate
call the client was told the outcome the first time, and the state that matters is the one
where it was not.

`ControllableTransport` therefore gained a second mode beside its offline switch. The next
matching request is sent, the server answers, the body is drained, and only then does the
transport throw the platform's own `SocketException` — so the server has committed and the
client knows nothing. Nothing above the cable is simulated, which is the same honesty D-058
established for the offline case.

```
        client ──── revenue_update ───▶ server   committed
        client ◀───     ✗ dropped    ─── server
        client ──── revenue_update ───▶ server   replayed, same row version
```

Both mutations are proven that way against `krishna-mis-dev`, through the real repository
and worker: the retry replays the **same** mutation id, the document moves exactly one row
version, the KI-REV number is unchanged, no component is duplicated, and the audit holds one
effect.

---

## 24. Correcting an expense's business date (2026-09-05)

A Phase 3 financial-integrity corrective, found while auditing the correction path before
extending it for revenue (D-127) and deliberately not taken inside a revenue slice.

### 24.1 One contract, and the endpoint that never existed

**`expense_update` is the authoritative Expense correction RPC.** It handles an ordinary
edit *and* an authorised business-date correction, and it applies additional checks on the
branch where the canonical date actually changes. There is no
`expense_correct_business_date` and no `revenue_correct_business_date`; the server exposes
exactly six financial RPCs:

```
        expense_create   expense_update   expense_void
        revenue_create   revenue_update   revenue_void
```

Three canonical documents named the expense one, and this document's §5.3 gave it a row of
its own in the concurrency table. Nothing was ever behind the name. Option A was taken —
keep one write path — because two write paths for one financial document is the recurring
cost this project has already paid twice, and because revenue would otherwise need a
matching second endpoint, doubling the divergence surface rather than halving it.

The client half is gone too: `MutationOp` no longer carries a `correctBusinessDate` value.
Nothing ever produced one, and an op no endpoint dispatches is answered terminally by the
router — so leaving it available would have turned the first real correction into a
permanent rejection.

### 24.2 What the server does when the date moves

The question is decided from **canonical state**, never from a flag in the request:

```
        v_date_moved := p_business_date is distinct from e.business_date
```

A client able to declare "this is not a correction" would be choosing which rules apply to
it. On that branch, and on no other:

| | |
|---|---|
| capability | `transaction.correct.business_date`, per property the document charges |
| reason | required, non-empty after **all** whitespace is stripped |
| provenance | `business_date_source = 'corrected'` (D-019) |
| audit | a distinct `expense_business_date_corrected` action carrying both dates and the reason |

An ordinary correction — an amount, a vendor, a note — gains no field and no permission
requirement, and does not restate the provenance of a row that already reads `corrected`.

**The capabilities compose; none replaces another.** `transaction.correct.business_date`
authorises the *kind* of act. It grants no relief from the edit window, the period locks,
the unit scope or `base_row_version`, each of which is a separately written guard. Equally,
`transaction.correct.beyond_window` lifts the age rule and authorises no date move.

### 24.3 Both periods, read from the one reporting source

The defect this corrective exists for: `app.validate_expense_allocations` only ever sees
the periods in the **incoming payload**, so it could say where an amount was going and
never where it was being taken *from*. An expense sitting in a **closed** month could be
moved to an open one, and the closed month's Total Expenses changed with nobody's
permission.

Proven by probe against `krishna-mis-dev` before anything was changed: ₹45,000 in a closed
2026-03, moved to an open 2026-04, `status: applied`, contributions `{2026-03: 4500000}` →
`{2026-04: 4500000}`.

```
        source periods ← expense_period_allocations   (the rows reporting reads, D-060)
        target periods ← app.validate_expense_allocations, shared with create
        each one → app.require_period_open(period_key, business_unit_id)
```

Reading the source from the contributions rather than from `business_date` is what makes a
**cross-period** bill safe: a ₹60,000 invoice split May/June contributes to both months,
and a guard that looked at the document's own date would miss the other one entirely.
Nothing re-implements P&L arithmetic for the lock check — the rows the reports will sum
are the rows checked here. `expense_void` has always done this; `revenue_update` does it
(D-124); `expense_update` now does it too.

Spec §13.4 is the authority, and the operative word is *affecting*: **closed source →
refused, closed target → refused, both open → the ordinary checks continue.** No role and
no correction capability reopens a period. Reopening stays the separate, reasoned, audited
Owner act it has always been.

### 24.4 The surface a person meets

The Expense edit form already had a business-date row, so this is a change to an existing
control rather than a new screen. In edit mode it opens only for somebody holding
`transaction.correct.business_date` — the date is still shown, because it is part of the
document, and it simply does not open for anybody else. Recording a *new* expense against
a chosen date is untouched: that is `manual`, not `corrected`, and has never needed a
capability.

When the date differs from the one the form was loaded with, a reason field appears and
Save waits for it. The loaded date is captured once, at load, and `copyWith` cannot move
it — the same discipline `baseRowVersion` has carried since D-072a, and for the same
reason: a field that moved on every keystroke would stop calling an edit a correction
halfway through typing it.

Hiding the control is **not** the security boundary. The server refuses regardless
(D-037); the client rule exists so that nobody fills in a form that was always going to be
refused.

### 24.5 Offline, and response loss

The reason travels in the outbox payload like everything else, so an authorised correction
queued with no network still carries it when it is delivered days later from a different
process. A reason held only in a widget's state is a reason that disappears on sync.
Nothing else about the transport changes: same outbox, same worker, same `mutation_id`,
same `base_row_version`, and a lost response recovers by redelivering the *same* intent —
proven against the real server with `ControllableTransport`, which lets the server commit
and then drops the answer on the wire (D-132).

### 24.6 The capability that was a comment

`transaction.correct.business_date` was granted to the accountant and owner bundles and
named by **0** functions and **0** policies. It is now evaluated at the authoritative
mutation boundary, and two invariants keep it that way: a deploy-time assertion over the
live catalogue, and a host test over the migrations that reads **function bodies and
policy expressions only** — not comments, not grant blocks, and not the deploy-time
assertions themselves, all three of which let a deliberate sabotage pass on the first
attempt.

Four capabilities are exempt by name — `reports.view`, `reports.export`, `reports.print`,
`settings.manage` — because the surfaces they govern are Phase 5 and Phase 7 and do not
exist yet. That is a list a later phase deletes a line from, not a rule that absorbs the
next dead grant.

---

## 25. Evidence for a sale (2026-09-06)

Phase 4 Slice 11. Revenue attachments are the Phase 3 architecture applied to a second
document, and the substance of this section is what had to be *shared* rather than
copied, plus the one thing that legitimately differs.

### 25.1 What was extracted, and why that was the smaller change

Nothing in the attachment lifecycle was ever about expenses. `domain/attachments/` now
holds `AttachmentUploadState`, `AttachmentPolicy` and `DocumentAttachment`, lifted out of
`domain/expenses/expense.dart` unchanged in substance; `ExpenseAttachment` is a typedef of
the last of these, so every expense call site is untouched. `AttachmentSource`, the two
platform pickers, `ImageOptimizer` and `AttachmentTypes` already carried no document
concept and were reused as they stood.

The alternative was a `RevenueAttachment` that was a copy of a class, a second policy with
the same five numbers in it, and a second `switch` from state to words. This project has
recorded that outcome twice — a duplicated status mapping (D-119) and a duplicated join
(D-131) — and both had already drifted by the time they were found.

**One worker, not two.** `AttachmentUploadWorker` drives both tables through a small
internal descriptor: table name, parent table, parent column. It keeps one backoff clock,
one definition of `uploaded`, one recovery pass and one reclamation policy. The 73
existing expense attachment tests pass over the rewritten worker unchanged, which is the
evidence that the generalisation is behaviour-neutral rather than the claim that it is.

**`waitingForExpense` keeps its name for both.** It means *the parent financial document
has not been accepted yet*, and it is the value stored in `upload_state` on every device
in the field, named by two SQLite check constraints. Renaming it would be a data migration
of live expense rows for no behavioural gain. D-104's lesson is to pin a wire name, not to
churn one.

### 25.2 The authority is the parent's, and revenue's parent is simpler

An expense attachment is complete-document-only (D-063), because a shared invoice states
the whole total on its face and an expense can be *partly* visible. A revenue entry cannot
be: it names one business unit and one revenue category on its header (spec §8), there is
no allocation model and no scoped projection. So `may_read_revenue_attachments` asks the
question the revenue projection already asks — this organisation, `attachment.view`
anywhere, and `revenue.view` for the entry's own unit — and reproduces none of the
allocation arithmetic. There are no lines to be outside anybody's scope.

It is `security definer` for the reason every predicate here is: a policy subquery runs
with the **caller's** privileges, so a predicate reading `revenue_entries` directly would
answer from rows the caller can already see rather than from the truth (D-045, D-110).

### 25.3 One bucket, two prefixes, two policies

```
        org/{org}/expenses/{expense}/{attachment}.{ext}   the expense predicate
        org/{org}/revenue/{entry}/{attachment}.{ext}      the revenue predicate
```

A second bucket would duplicate the size limit, the MIME list and four policies, all then
kept in step by hand. The bucket id still reads `expense-attachments`, which is a
historical name for where financial evidence physically lives: renaming it would strand
every bill already uploaded, for a word. The two path parsers are asserted at deploy time
to be mutually exclusive, so neither prefix is reachable through the other's rule.

### 25.4 Two writes, and evidence is never the ledger

`revenue_attachment_register` is the only writer of `public.revenue_attachments`, exactly
as `attachment_register` is for expenses. Putting bytes in a bucket does not put a till
report in the books: the object listing carries no content hash this application controls,
no uploading actor, no audit row and no foreign key to the sale (spec §23).

Two RPCs rather than one with a discriminator. Each re-checks the authority of its own
parent, and a single endpoint taking *"which kind of document is this"* from the caller
would be a client choosing which rules apply to it.

### 25.5 Attaching is not editing

This is the rule the client surface is shaped around. `RevenueRepository.attachLocally`
takes no `base_row_version`, queues no outbox intent, does not advance the entry's row
version, and touches no amount, tax figure, business date or transaction number. Evidence
travels on the attachment pipeline's own clock, so a correction queued against the same
sale is unaffected — **the attachment belongs to the document's identity, not to any one
mutation.**

A test captures a sale's whole financial state before evidence is attached and compares it
after every path that touches an attachment: attach, upload, fail, retry, restart. On the
server the same comparison runs over `revenue_document`.

### 25.6 What is deliberately absent

**No removal.** V1 ships none for expenses either (D-072a), and
`expense_attachments.removed_at` has no writer anywhere in the product.
`revenue_attachments` therefore carries no removal columns at all, asserted by the
migration — because a constraint with no writer is what D-145 had to reason about, and the
honest answer is not to create a second one. If removal is ever approved, its mandatory
reason uses `app.stated_reason` (D-142).

**No download RPC and no signed-URL issuer.** Phase 3 built neither: reading an object
back is Storage's own authenticated download under the read policy, and the surfaces show
a file name, a size and a state. Revenue gets the same and nothing more.

**No `attachment_count` on the projection.** It is a derived figure duplicated onto a
header, which is the shape `revenue_tables.dart` declines for the money itself.

### 25.7 What a revocation does

The same as for an expense, with one branch fewer. A purged sale loses its evidence rows
and its staged bytes; a sale retained because its actor still has unsent work keeps both.
There is no partially-revoked document to downgrade, because a revenue entry is never
partly visible. The bytes are reclaimed **after** the transaction commits, because SQLite
can roll a delete back and the filesystem cannot put a file back (D-070 §3).

An un-uploaded file on an *already synced* sale goes with the sale, and that is correct
rather than a gap: the property has been withdrawn, and the Storage policy would refuse
the upload from that moment anyway. Retaining bytes for a property the user has lost is
the thing D-070 exists to prevent.

### 25.8 What the acceptance can and cannot prove

The same boundary as D-073a, restated because it is the boundary that cost the most. The
OS picker is a separate activity the harness cannot drive, so a synthetic source is
injected at exactly the point the picker returns a file. That proves the pipeline behind
the picker and nothing about the picker. What proves the picker is wired at all is
`attachment_source_wiring_test.dart`, which reads what **production** resolves — the
assertion that was missing while `UnavailableAttachmentSource` shipped to two real
devices (D-077) — and the manual smoke test, which stays in the release checklist.

One acceptance assertion had to be weakened, and the reason is worth keeping. The online
phase first asserted that a freshly saved sale's evidence had *not* yet uploaded, to
demonstrate the ordering rule. Against a real server the whole chain — save, push, number,
promote, upload — finishes inside the same two-second pump, so the assertion was requiring
the product to be slow. The ordering rule is now proven in the **offline** phase, where no
number can arrive and the upload provably cannot start. Slice 8 records the identical
lesson for *"no number yet"* (D-119).

### 25.9 What happens to the bytes when the second write refuses (2026-09-06)

Slice 11 shipped an upload whose two halves disagreed about one condition, and the
disagreement left files in a private bucket that nothing could reach. This is the closure,
and it is the third section of this document to record that **a rule which can never
evaluate true refuses everything and looks like a boundary working** (D-110, D-116).

**The two halves, and where they parted.** The Storage write policy asked
`may_read_*_attachments` — may this caller *read* the document. The register RPC asks that
and, additionally, refuses a **voided** parent with `KM020`. A read predicate must not care
about a void, because a void keeps its evidence readable for ever (D-006, §16.5). So the
ordinary sequence walked into the gap: a sale is recorded with a till photo, the upload
fails transiently and goes on the backoff clock, the accountant voids the sale, the backoff
elapses, **Storage accepts the bytes**, the registration refuses, the worker marks the row
terminally `rejected`, and the object stays for ever.

Four of the eight objects the Slice 11 report could not account for were produced by
exactly that, with no seam and no forgery involved, and the expense engine had the same hole
from D-073a (D-154).

```
        write authority   =  read predicate
                          +  attachment.upload
                          +  a parent that exists and is NOT voided
        read authority    =  unchanged; a voided sale keeps its evidence
```

**Three layers, and the last one is what makes the second safe.**

1. `may_attach_to_expense` / `may_attach_to_revenue` decide every INSERT and UPDATE, so the
   largest class can no longer put bytes in the bucket at all. A deploy-time assertion
   refuses the migration if a *read* policy ever acquires attach authority.
2. A narrow `delete` policy per kind lets the client that wrote an object take it back when
   registration terminally refused it — the residual classes are the attachment limits and
   a path the server derives differently, and for those the bytes are legitimate when they
   are written.
3. Both the UPDATE and the DELETE policies refuse while **any metadata row names the path**.
   That is what separates reclaiming stranded bytes from removing evidence: Postgres is the
   record of what evidence exists (spec §23), so an object no row names is not evidence, and
   the guard is a `not exists` the database evaluates rather than a promise the client
   makes.

**A lost response is answered by asking, not by guessing.** The worker now establishes
whether the registration committed *before* it re-uploads — only on a retry, because a first
attempt cannot have registered anything — and reconciles straight to `uploaded` when it has.
That is what a lost response actually calls for, and it is also what makes layer 3 safe on
the UPDATE side: the legitimate retry no longer depends on overwriting an object that may
already be canonical evidence.

**The bucket has to reconcile, and now says so.** The Slice 11 run reported what it left
behind; the run now reclaims what nothing names and then asserts there is nothing left, over
both prefixes. Sixteen stranded objects went on the first execution, and the two sides now
agree exactly — 79 revenue objects to 79 rows, 46 expense objects to 46 rows.

---

## 26. The revenue reporting interface (2026-09-06)

Phase 4 Slice 12. It defines and exposes what Phase 5 will aggregate, and **builds no
P&L** — no dashboard, no export, no margin (D-087). A test asserts the repository grew no
such method, because a slice boundary nothing evaluates is a comment.

### 26.1 Derived, not stored, and the reason is what a contribution *is*

The obvious move was `revenue_period_contributions` as a table, mirroring
`expense_period_allocations`. Reading the expense side rather than remembering it says
otherwise, and the distinction is the whole of this slice's design.

```
        expense_period_allocations   a PHYSICAL TABLE
          because a cross-period split is a decision a person made (D-034) and
          exists nowhere else — remove the row and the information is gone

        expense_period_contributions a VIEW over it
        revenue_period_contributions a VIEW over the components
          because a revenue contribution carries NO such decision:
            its period is the entry's stored pnl_period_key, under a CHECK
            its money  is the component's stored gross, tax and net
```

`DATABASE_SCHEMA.md` calls the revenue projection *"the mirror of
`expense_period_contributions`"*, and that projection is a view. The mirror of a view is a
view.

**What storing it would buy is nothing, and what it would cost is a lifecycle.** Every
hazard the Slice 12 brief lists is a hazard of *maintaining a second copy*:

| The hazard | With a table | Derived |
|---|---|---|
| a business-date correction moves a period | delete the old rows, write new ones, in the same transaction as the mutation, on every path | the entry moved |
| an edit replaces the figures | replace, never append — and an append is one forgotten `delete` away | the components were replaced |
| a void removes the effect | flag or delete, and every aggregate must agree which | the entry is voided |
| a replayed mutation applies twice | contribution idempotency has to be built and kept in step with mutation idempotency | there is nothing to insert twice |

None of those is a rule anybody has to remember. That is the argument, and it is the same
one D-060 makes in the opposite direction for expenses: put the money in exactly one place.

### 26.2 Component grain, and the paisa it protects

One row per component, never per document (D-087). A two-band Room day is two
contributions even though the document totals aggregate them; flattening them into one
blended rate would state a rate that was applied to nothing, and would destroy the only
structure that makes *"why did room tax change this month?"* answerable.

The grain also protects the arithmetic, and the acceptance states the difference rather
than assuming it. Two Restaurant days of ₹76,450 and ₹81,200:

```
        summed at the component   364048 + 386667  = 750715   <- what is reported
        the rate re-applied       15765000 x 5/105 = 750714   <- one paisa less
```

Rounding happens once, at the component, and an aggregate sums stored paise (spec §6.5,
D-017). The two differ by a paisa here and by more over a month, and only the first is the
sum of figures anybody approved.

### 26.3 Nothing joins to configuration that can still change

Every rate, treatment, basis and band on a contribution is the snapshot the component
recorded when the server accepted it. The projection reaches no tax table at all, so
deleting every rule in the organisation leaves historical reporting unchanged — asserted by
deleting them in the host suite, where the fixture is disposable, and by the structural
property on the live server, where the four verified rules are the approved baseline and a
test does not get to archive one to make a point (D-080, D-096, D-122).

`business_date_source` is carried as a **dimension** (D-143). Phase 5 may surface it;
nothing may compute with it, and two entries that differ only in provenance contribute
identically.

### 26.4 What contributes, and what merely exists

Three exclusions, applied before any filter, in one shared predicate so they cannot be
present in one query and forgotten in the next:

| | |
|---|---|
| `voided_at IS NULL` | a voided sale contributes nothing and stays inspectable (D-006) |
| `scope_revoked_at IS NULL` | a retained unsent attempt over a property this user no longer holds is nobody's revenue (D-070, D-074) |
| `txn_number IS NOT NULL` | **canonical only** — a sale the server has not accepted is an attempt, not revenue |

The third is the one worth stating. A local attempt is a person's intent; putting it in an
authoritative total would report money the business does not yet have. Phase 5 may add an
explicitly labelled provisional operational figure, and Slice 12 deliberately does not
invent one (D-158).

### 26.5 Where reporting can be read, and where it is authoritative

The **server** projection is authoritative and is scoped by `revenue.view` per business
unit, through a `security_barrier` view, with the base tables ungranted — the boundary
`revenue_document` already draws (D-062, D-116).

The **local** view answers for what this device holds. That is every sale this device
recorded, and it is **not** every sale the organisation has: there is no revenue pull, so a
device cannot report a month it did not record. That is the shipped state after Slice 11
and it is stated here rather than discovered in Phase 5, which will need one before a
dashboard can be honest offline.

Filtering, scoping and the aggregate all happen in SQL. A month of a property's revenue is
one row off the database rather than every component folded in Dart, which is what spec §27
asks for and what the expense side does not yet do.
