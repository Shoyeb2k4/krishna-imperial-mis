# Architecture

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Status: **Sections 1–12 proposed (Phase 0, revised); section 13 describes what is built
and verified.** Sections 6, 5.3 and 8 carry the project lead's mandated corrections.
Implementation status is tracked in `PROJECT_STATUS.md`.
Last updated: 2026-08-30

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
     op               text     -- 'create' | 'update' | 'void' | 'correct_business_date'
                               -- | 'archive' | 'close_period' | 'reopen_period'
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
| Business-date correction | **required** | reject → conflict |
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
- Storage buckets are private; access is via signed URLs scoped to the org and expiring.
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
