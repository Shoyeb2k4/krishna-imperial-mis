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
Last updated: 2026-10-02 — **Phase 8 Slice 7**: start-up failure classification, atomic schema steps and the damaged-database recovery flow (§8.2, §52.10, D-328 … D-330); 2026-10-01 — **Phase 8 Slice 5**: missed taps are fatal across the host suite (§52.9, D-325); 2026-10-01 — **Phase 8 Slice 4**: the Expense ledger read path, local schema v22, and the server expense-read residual measured and declined (§52.8, §9, D-323, D-324); 2026-10-01 — **Phase 8 Slice 3**: retry and hang hardening (§52.7, D-322); 2026-09-30 — **Phase 8**: the D-318 redesign as built and measured (§52.6, D-320, D-321); 2026-09-29 — **Phase 8 Slice 2**: the D-186 harness and what the reporting predicate costs at scale (§52.5, D-318, D-319); **Phase 8 Slice 1**: the measurement contract (section 52), §9 corrected to LIMIT/OFFSET paging (D-314), §8.2 marks the recovery flow as not yet built (D-316); 2026-09-28 — **Phase 7 closed** (D-311): section 51 now describes what shipped; 2026-09-28 — **Phase 7 Slice 10**: print authority re-check (D-309) and the runner apartment (D-308), sections 51.5 and 51.7; 2026-09-25 — **Phase 7 Slices 8–9**: Android sharing and the analysis exports, as built (sections 51.2, 51.5, 51.7); **Phase 7 Slice 1**: the export, PDF and printing contract (section 51); 2026-09-25 — **Phase 6 closed**: the stable contract Phase 7 may build on (section 50), and the final D-286 real-line rule (section 49); 2026-09-24 — money at large text sizes (section 49); 2026-09-23 — dashboard drill-down integration (section 48); the Windows Analytics workspace (section 47); the Android Home dashboard (section 46); 2026-09-22 — the Windows Overview (section 45); 2026-09-17 — Phase 6 dashboard periods and comparison rules (section 41); Slice 11's corrections and the Slice 12 closure architecture (section 40); 2026-09-13 — the Android P&L surface (section 38); the Windows P&L surface (section 37); Slice 7 reporting security closure (section 36); 2026-09-11 — the Owner Settlement surface and its security boundary (section 35); the Owner Settlement Engine (section 34); the Owner Ledger (section 33), with the V1 ownership vector in §33.3; Phase 5 Slice 6 corrective (section 32); Slice 5 in section 31; Slices 1-4 in sections 27-30

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
| Excel | a small internal OpenXML writer on `archive` 4.x (D-298) | **Windows only** in V1 (D-293). The `excel` package was rejected because it needs `archive` 3.x |
| PDF + print | **`pdf` 3.13.1** + **`printing` 5.15.1**, pinned (D-298) | `printing` covers the Windows print dialog and Android sharing; `share_plus` was rejected because it needs `win32` 6.x; section 51 |
| Charts | **fl_chart 1.2.0**, pinned, styled by our tokens | evaluated and adopted in Phase 6 Slice 5 (D-269); no default chart theme ships, and nothing outside `core/design/charts` imports it |

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

Every report result object carries a freshness descriptor, surfaced in the UI.

**Amended 2026-09-08 (D-167, D-188).** The table as written had three states and the first
of them is **superseded for P&L**:

| State | Meaning |
|---|---|
| ~~**Local — current** (`N unsynced entries`)~~ | **Superseded.** A canonical P&L contains only server-accepted facts, so an unsynced attempt contributes nothing and there is no figure for it to be *included in*. No valid P&L can construct this, and an arm nothing constructs is the gap D-108 had to reopen — so it is not preserved |
| **Synchronized as of `<server-confirmed time>`** | The local canonical reporting cache represents the complete authoritative reporting snapshot successfully synchronized at that time. It does **not** claim the device has proved nothing changed since, so an offline device may truthfully stay here |
| **Server has newer canonical changes** | An authoritative answer about **reporting** data says the server has moved past what the device holds. A vendor rename, a tax-rule change or an audit row moves the global sequence and changes no contribution, and must never land a report here |

Unsynced work stays real and stays visible on the **transaction** surfaces as operational
sync status. *"N unsynced transactions"* there is a statement about queued work and never
an implication that those transactions moved a reported figure.

**Availability is a separate question** and is answered by the coverage vocabulary —
*complete*, *not downloaded*, *not authorised* — which is never reported as a monetary zero
(D-170, D-183). Freshness describes how current an **available** figure is, and a report
whose segments cannot be shown to belong to one authoritative snapshot carries **no**
freshness claim rather than a third state (§32).

There is **no reporting TTL**: age is disclosed, not enforced. Exports embed the same
freshness statement in their header, so a PDF mailed to someone else states the basis and
the freshness on its face.

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

**Since D-246 the Windows session is not in that blob.** It lives in its own
DPAPI-protected file, `krishna_mis.session.dpapi`, written atomically and never deleted on
a failed read, because the plugin deletes its whole blob — database key included — when a
read fails. Only the database key stays in the plugin store.

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
  **Not yet built (D-316, 2026-09-29):** the shipped application stops on a start-up failure
  screen that shows the raw exception, with no *Try again* and no reset. Phase 8 Slice 7
  builds the flow under the project lead's rules in D-312 (D4).
  **Built (Phase 8 Slice 7, 2026-10-02, D-328 … D-330):** start-up classifies the failure,
  shows plain words and *Try again*, and offers *Reset local data and download again* only
  for data that cannot be opened or upgraded — behind a statement of what would be lost and
  a typed confirmation. The data is **set aside, not deleted**. See §52.10.
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
  `(org_id, business_unit_id, pnl_date)`, `(org_id, category_id, pnl_date)` in Postgres.
  *Corrected 2026-09-29 (D-314, D-315):* this line said "both locally and in Postgres". A
  device holds one organisation, so no local query constrains `org_id` and an `org_id`-led
  local index cannot serve it; the local reporting cache is indexed by owner, property and
  period instead (§30).
- Ledger screens paginate with **LIMIT/OFFSET** — the revenue ledger 50 rows a page; the
  expense ledger, since Phase 8 Slice 4, a window that grows by 50 with every "Load more", read
  as one ordered statement (D-317, D-323, §52.8). *Corrected 2026-10-01:* this line said "one
  window of 100" — and that window was the whole of what the expense ledger could ever show
  (D-314). *Corrected 2026-09-29:* this line said "keyset
  pagination, never OFFSET"; no keyset paging was ever built. Keyset paging is built only if
  Phase 8 profiling shows OFFSET is materially problematic at the approved scale (D-312 D5).
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

---

## 27. One reporting vocabulary, and who may read it (2026-09-07)

Phase 5 Slice 1. It builds **no P&L**, no engine, no surface and no pull — those are
Slices 2 to 5. What it does is make the two accepted transaction engines answer the same
question the same way, because a P&L that sums two shapes which merely resemble each other
is a P&L that is wrong in a direction nobody notices.

Four findings from the Phase 5 planning audit, all proven before they were fixed.

### 27.1 `expense.view.own` meant the property, not the author (E1, D-169)

The catalogue says *"View expenses this user created"*. `expense_visible_units()` returns
the units where the caller holds `expense.view.all` **or** `expense.view.own`, and no read
path anywhere applied a `created_by` predicate. Read as the development Data Entry
identity, which holds `expense.view.own` on Crystal Canopy and nothing else:

```
        RED                              GREEN
        expense_document               787 rows, 724 others   ->  63, 0
        expense_period_contributions   865 rows, 802 others   ->  63, 0
        expense_allocations            787 rows, 724 others   ->  63, 0
```

**Ownership is a property of a document, and a set of unit ids cannot express "mine".** So
the question was split rather than the unit set edited:

```
        expense_visible_units()      unchanged — whose LINES may I see, per unit
        public.may_read_expense(id)  new      — may I see this DOCUMENT at all
```

and the document predicate is `AND`-ed into **every** expense read path. It has to be every
one: `expense_allocations_read` is line-level, so leaving it alone would go on handing a
`view.own` holder another author's rows through the child table. A deploy-time invariant
enumerates the paths from the catalogue and refuses the migration if one does not consult
it — a list of the paths I remembered touching is exactly what the next one would escape.

It can only narrow. For a pure `view.all` holder the own-branch is unreachable and the
predicate reduces to the old one, which the live matrix confirms: Owner 787, CCR manager
787, HKI manager 121, Accountant 787, all unchanged, with the foreign-document probe
invisible only to Data Entry.

One behavioural consequence, stated rather than discovered later: a Data Entry user can now
attach evidence only to documents they recorded, because `may_attach_to_expense` is built on
the read predicate. Attaching to a manager's expense was never a designed workflow; it
followed from the defect.

### 27.2 The regression that fix introduced, and the guard for it (D-174)

`expense_view_own_means_own` rebuilt `expense_attachments_read` from the migration that
first **created** it rather than the one that last **replaced** it, reinstating an inline
`select ... from public.expenses` inside a policy expression. A policy runs with the
querying user's privileges and no client role may read that table, so
`expense_attachments` became unreadable by everybody, the Owner included — fail-closed
rather than a leak, and still a defect, because D-063's read authority stopped reaching the
users it exists to serve.

This is D-045 and D-109 by a new route: not a predicate written against the wrong schema,
but a correct predicate restored from a superseded version of itself. **A
`create or replace` has to be built from what the object is now.** The guard is now general
and catalogue-wide: no RLS policy on a financial relation may read a financial base table
inline.

### 27.3 The two engines disagreed about what counts (E2, D-168)

`RevenueRepository` applied three exclusions — voided, scope-revoked, and **canonical-only**
(`txn_number IS NOT NULL`). `ExpenseRepository` applied the first two.

Combined into a P&L that subtracts costs the server has never accepted from sales it has:

```
        Net Sales        canonical revenue only
      - Expenses         canonical costs + this device's unsent attempts
      = Operating Profit understated, silently, always in the same direction
```

Proven by the shipped suite rather than by reading it — an existing test saved an expense
with `createLocally` alone and asserted it contributed ₹200.

There is now **one canonical reporting semantic** on both engines: an amount contributes
only if it is server-accepted, not voided, not scope-revoked. `txn_number` is the marker on
both sides, issued by the server on acceptance and by nothing else, tied to
`financial_year` by a check constraint, and impossible for a client to invent (D-008,
D-085). Pending, rejected, conflicted and quarantined work contributes zero and stays
visible in the transaction surfaces (D-167).

### 27.4 Reporting aggregates in SQL, over a named projection (E3)

The expense reporting path read three tables through a hand-built join and folded the rows
in Dart, taking only a period key. Revenue already read a named view and aggregated in SQL.
Two shapes for one question is how 27.3 came to be true on one side and not the other.

Local schema **v16** adds `expense_period_contributions`, the local half of the server view
column for column, plus the two columns that only mean something on a device: `txn_number`
and `scope_revoked_at`. The repository now offers `contributions`, `contributionTotals` and
`contributionTotalsByCategory` over **one shared predicate**, mirroring revenue exactly, so
the three exclusions cannot be present in one query and forgotten in the next.

The range filters `pnl_date`, never the business date: a June salary paid on 5 July is a
June cost, and a report that filtered the operational date would put it in July (D-016,
spec §5.3).

The v16 step carries **no version floor**, and that is a claim rather than an oversight: the
expense tables arrive at v7 and `expenses.scope_revoked_at` at v9, and the v9 step runs
before this one in source order. A test holds that ordering, because a step that only ever
ran against a fresh database would not notice it being reordered (D-144).

### 27.5 A documented surface that never existed (E4)

`DATABASE_SCHEMA.md` §11 named `v_expense_period_lines` and `v_revenue_lines` and called the
first *"THE expense reporting surface"*. Neither has ever existed anywhere, and the SQL
sketched for the first referenced a column and a predicate that do not exist, so it could
not have run. §11 now documents the two projections that are real, what they share, where
they legitimately differ, and what is still missing.

### 27.6 What Slice 1 deliberately did not do

No `reports.view` evaluator — that is Slice 7, and D-139's exemption entry stays until the
migration that owns the reporting boundary removes it deliberately. No `domain/finance`,
which is Slice 2. No engine, no cache, no pull, no surface. And no change to
`public.expense_sees_whole_org()`, which is on the reviewed API surface and is called by
nothing — a fifth instance of the family D-068, D-071, D-077, D-103 and D-116 record,
reported rather than removed inside a slice that did not scope it (D-127).

---

## 28. `domain/finance` — the canonical calculation specification (2026-09-07)

Phase 5 Slice 2 creates the directory `CLAUDE.md` and spec §21.1 have mandated since Phase
0 and which did not exist: *"all derived financial arithmetic lives once, in
`domain/finance/`"*. Section 6 states the principle; this states what was built to it.

**It is pure Dart and nothing else.** No Drift, no Supabase, no Riverpod, no Flutter, no
`dart:io`, and no import of `data/`, `features/` or `app/` — asserted over the whole
directory by `finance_purity_test.dart` rather than reviewed per file, because the property
has to hold for the files nobody has written yet.

### 28.1 The division of labour

```
        LocalReportingEngine  ─┐
                               ├─ primitive summed paise ──► domain/finance ──► PnlResult
        RemoteReportingEngine ─┘
```

An engine selects and sums canonical rows. **Neither engine computes Net Sales, Operating
Profit or margin.** That is the whole of §6.2 made concrete: the divergence surface between
two physical execution environments shrinks from "the P&L" to "did you sum the right rows",
which is small enough for a parity test to pin down completely (D-020).

### 28.2 The identities

```
        Gross Sales      = Σ accepted revenue gross      summed, never Net + GST
        GST              = Σ accepted revenue tax
        Net Sales        = Σ accepted revenue net
        Gross Sales      = GST + Net Sales               exactly, asserted, no tolerance

        Expenses         = Σ accepted expense contributions
                           gross cost including GST, no input credit (spec §6.1, D-018)

        Operating Profit = Net Sales − Expenses          may be negative, never clamped
```

The three revenue figures are three **independent sums** of stored component snapshots.
Deriving one from the other two would make a rounding difference invisible, and it is the
independence that makes `reconciles` a real check rather than a tautology.

**Nothing is re-rated.** The calculator is handed `tax` and is never handed a rate, so it
has no way to reproduce the classic error. The control is the project's own: two accepted
Restaurant days sum to `750715` paise of tax, where re-applying 5/105 to the aggregate
`15765000` would give `750714`. The test asserts the first, computes the second beside it,
and asserts they differ.

### 28.3 Consolidation

Per-property results add into an organisation result by exact sums — gross, GST, net and
expenses — and the consolidated Operating Profit follows from the consolidated net and
expenses. `Σ per-unit == consolidated` holds for every primitive, and is tested for
associativity and order-independence.

**Percentages are never averaged.** The consolidated margin comes from the consolidated
ratio. Averaging two properties' margins would weight a small property equally with a large
one and produce a figure that is neither property's and not the organisation's.

Consolidating an empty set throws rather than returning zeroes: a report over no permitted
property is a refusal, not a result. Consolidating results over different ranges throws
too, because presenting one period as another is the failure that would follow.

### 28.4 Zero, negative, and unavailable — three different things

| | |
|---|---|
| **zero** | real trade that netted nothing, or a month with no entries. `SideAvailable` carrying zeroes. Computes normally |
| **negative** | expenses exceeded net sales. Reported as it is; this is a management P&L, not a counter that only goes up |
| **unavailable** | nobody knows. A `SideUnavailable` variant, and the report is **refused** (D-163, D-176) |

Both sides of `Pnl.compute` are required and non-nullable, and the refusal is decided by an
exhaustive switch over both at once, so the compiler guarantees every combination is
answered.

### 28.5 Margin

An exact rational, never a `double`, with the display precision deferred to the caller that
is about to print it, and `MarginNotApplicable` as a separate variant when net sales are
zero (spec §10). Rounding is half **away from zero** rather than half up, because a margin
is signed and the two directions must round symmetrically. Full reasoning in D-175.

### 28.6 Report periods, normalised once

Every period a manager can pick — a single trading day, a week, a month, a financial year,
a custom range — resolves to one inclusive `ReportRange` of P&L dates. One boundary
contract, so the local and remote engines need one query shape rather than five that agree
until somebody edits one.

**These are report-selection semantics, not a second accounting-period model.** Which
period an amount *belongs* to is already computed once at write time and stored as
`pnl_date` / `pnl_period_key` (spec §5.2, D-016). A range selects over those stored dates
and reinterprets nothing — so an expense's reporting month is its contribution's accrual
date, never its business date and never its payment date.

**The week is Monday to Sunday, on the business date (D-165).** Spec §10 named the week and
nothing in the repository defined it. A sale rung up at 01:00 on a Monday carries a business
date of Sunday under the property's 05:00 cut-off and belongs to the week that is closing —
proven with a real `BusinessDate.fromInstant` in `Asia/Kolkata`, not asserted in prose.
Weekday is computed with `DateTime.utc` used as a **calendar**, never as an instant; naming
UTC is what stops the host machine's zone from shifting the day.

**The financial year is the project's own.** `FinancialYear` is imported from
`domain/expenses/expense_number.dart`, where it has lived since Phase 3, rather than
restated — the same type the `KI-EXP` and `KI-REV` sequences use, agreeing with
`app.financial_year_of` and `app.revenue_financial_year` on the server. A second FY
algorithm written for reports would be a second answer to *"which year is this"* (§15 of
the Slice 2 brief).

**A reversed custom range is rejected, never silently swapped.** Guessing which end was
meant is how a report quietly covers a different period from the one on screen.
`ReportRange` has no public constructor, so the invalid case cannot be built and then left
unchecked; same-day start and end is valid and covers one day.

### 28.7 The reference oracle

§6.3 requires the parity suite to have something independent to assert against before a
second engine exists. `test/support/pnl_reference.dart` is it: two `for` loops over plain
`int`s, using no `Money`, no `BusinessDate` and no domain type, so a defect in a shared
primitive cannot hide by being present on both sides of the comparison.

It **does not call the production calculator**, and a guard asserts it never will — an
oracle that delegates proves a function equals itself. It does not ship, and a second guard
asserts nothing in `lib/` references it. The one thing it deliberately shares with
production is the input grain: it folds individual contributions where `Pnl.compute`
receives sums an engine produced, so between them they check both the summing and the
deriving.

### 28.8 What Slice 2 deliberately did not build

No reporting engine, no repository method, no query, no cache, no pull, no screen, no
export. No Drift migration and no Supabase migration — the slice adds no schema of any
kind. Freshness and as-of are Slice 6's and are composable with `PnlResult` rather than
hardwired into it.

---

## 29. `LocalReportingEngine` (2026-09-07)

Phase 5 Slice 3. The first of the two engines §6.1 draws, and the shape §28 was built to
feed.

```
        ReportingPeriod ──normalise once──► ReportRange
                                              │
        DriftReportingSource ──► primitive summed paise + ReportingCoverage
                                              │
        LocalReportingEngine ──► Pnl.compute ──► PnlResult
                             └─► Pnl.consolidate for the organisation
```

Three files, and the layering is the point:

| | |
|---|---|
| `domain/finance/reporting_source.dart` | the **port**: `ReportingCoverage`, `ReportingScope`, `ReportRequest`, `UnitReportingFacts`, `LocalReportingSource`. Pure domain |
| `data/reporting/local_reporting_engine.dart` | orchestration. Knows the port and `Pnl`, and **no storage at all** |
| `data/reporting/drift_reporting_source.dart` | the only file in the path that knows what a database is |

### 29.1 The engine derives nothing, and it is asserted

No Net Sales, no Operating Profit, no margin, no tax extraction, no rate, no business-date
derivation, no financial-year derivation. `local_reporting_engine_guard_test.dart` asserts
it over the whole directory: no `Money.fromPaise`, no `Money.sum`, no `.paise`, no
`gross − tax` or `net − expense` shape, no `TaxRule`, no `double`, no `fromInstant`, no
`DateTime.now`, and no static or cached report anywhere.

The complement is asserted too, because a file that computed nothing *and delegated
nothing* would pass all of that: the engine must contain `Pnl.compute(` and
`Pnl.consolidate(`, and the source must call `contributionTotals(` and must not contain a
SQL statement of its own. Proven by sabotage — an added `grossSales.paise - gst.paise`
turned the guard red, and it was restored and read back.

### 29.2 Coverage, and what Slice 3 honestly cannot do

**This is the constraint that shapes the whole slice.** A device holds only the
transactions it recorded itself — there is no reporting pull on either engine (D-173) — so
rows being present proves nothing about whether a range is complete. An engine that
reported those rows as "the hotel's June" would be wrong in a way no reader could detect
from the figure.

So coverage is a **first-class answer**, carried with the figures rather than inferred from
them, and `LocalReportingSource` returns it alongside the sums. The production wiring
answers [ReportingCoverage.notDownloaded] for every range, through `NoCanonicalCoverage`,
and **the engine refuses**. That is not a placeholder for Slice 4 to tidy away; it is the
honest answer until the canonical reporting cache and its marker exist.

Coverage has **two values, deliberately not three**. An `unavailable` beside
`notDownloaded` had no producer: every path that fails to establish coverage today fails
for the same reason. A value nothing constructs is the gap D-108 had to reopen, where a
distinction lived in the type and never in the behaviour. Slice 4 adds what its markers can
actually distinguish; Slice 6 owns freshness, and none of its vocabulary is here.

**Zero and unavailable stay apart end to end.** A known-complete range with no transactions
is a real zero P&L — gross, GST, net and expenses all nil, margin not applicable — and it
computes. An unproven range refuses. The two are different variants, not different values
(D-163, D-176).

### 29.3 One range mapping, and the caller does not choose it

`ReportRange.wholeMonthKey` returns `YYYY-MM` when the range is exactly one calendar month
and null otherwise, so a whole month is answered by the indexed `pnl_period_key` equality
both projections store and everything else by an inclusive `pnl_date` range. The
optimisation is a **property of the range**, derived from it — a month asked for as a month
and the same month asked for as a custom range are the same range and take the same path,
so they cannot give different answers.

Every range filter is on `pnl_date`. Never `captured_at`, never `payment_date`, never
`created_at`, never the device clock, and never an expense's own business date: a June
salary paid on 5 July is a June cost (D-016), and an accrual recorded on 3 July for the
June service period reports in June. Both are permanent tests.

Slice 3 also unified the two sides' vocabulary: the revenue contribution predicate filtered
`business_date` where the expense one filtered `pnl_date`. For revenue those are the same
column — the projection aliases it — so the change is behaviour-identical, and it means one
range maps onto both engines by one name.

### 29.4 Scope is explicit and never inferred

`ReportingScope` is always an explicit set of business unit ids. There is deliberately no
"null means the whole organisation" convention: that is how an engine ends up aggregating a
property the reader was never granted. An empty scope is refused
(`PnlRefusal.noPermittedBusinessUnit`), not reported as zero.

Consolidation computes each property on its own and hands the results to `Pnl.consolidate`
— there is one consolidation formula in this project and it is not in an engine. **One
property whose coverage is unproven refuses the whole consolidated report**, because a
total assembled from a complete property and an unproven one gives the reader no way to see
which part is missing.

The engine holds **no state**. Every call carries its own scope and range, and there is no
process-level "latest P&L" — that is how a user switch or a confirmed revocation ends up
showing one person another's figures (D-074), prevented here by construction rather than by
a purge.

### 29.5 Aggregation stays in SQL

The source assembles a `RevenueContributionQuery` and an `ExpenseContributionQuery` and
lets the repositories answer, so the canonical predicate — accepted, not voided, not
scope-revoked (D-168) — keeps one home per engine and the range, scope and aggregate are all
decided in SQL. A second query written in the source would be a second place for that rule
to live, and the two engines had already drifted apart once.

Measured on a two-year fixture (2,920 revenue components, 244 expense contributions):

| Query | Plan | Time |
|---|---|---|
| revenue month, period key | `SEARCH ix_revenue_entries_day` → `SEARCH ix_revenue_components_entry` | 0.42 ms |
| revenue financial year, date range | the same two indexes | 0.58 ms |
| expense month, period key | `SCAN expense_period_allocations` → indexed joins | 0.07 ms |
| expense financial year, date range | the same | 0.12 ms |

No N+1: one aggregate query per side per property, returning one row. Nothing loads
financial history into Dart.

**One finding recorded rather than fixed.** `ix_expense_contributions_reporting` leads with
`org_id`, and the local reporting queries never constrain it — a device holds one
organisation, so the predicate has no reason to name it. The index is therefore unusable on
the local path and the expense side scans. At V1 volume that scan is 0.07 ms over the whole
fixture, so no index is *measurably* required and the schema stays at **v16**; changing an
index on a measured non-problem would be speculative. It is recorded because an index
nothing can use is the same family as a rule nothing evaluates, and Slice 8 owns
performance hardening.

---

## 30. The canonical reporting cache and its delta (2026-09-07)

Phase 5 Slice 4. §29 built an engine that reads canonical facts and **refuses** rather than
reporting a figure it cannot stand behind. This is what gives it something to stand behind:
a synchronised cache of server-owned financial facts, and the delta that fills it.

It closes D-173. Before it, **neither** engine had a reporting pull, so a device could
report only what it had itself recorded — and the failure had no symptom. A manager's
second phone, a fresh installation, or a property whose sales somebody else enters all
produce the same thing: a query that returns rows, sums them exactly, and reports a number
that is not the hotel's.

### 30.1 A different authority class, in its own storage (D-171)

```
        revenue_entries / expenses          reporting_*_contributions
        ──────────────────────────          ──────────────────────────
        this actor's work, in every         canonical accepted figures the
        state work can be in: pending,      SERVER returned, belonging to a
        rejected, conflicted, voided,       synchronisation generation
        quarantined, never sent
        editable; carries a row version     read-only; no row version, no
        and an outbox intent                mutation id, no notes, no payload
```

Separate tables, because mixing them would make every reporting query re-derive which rows
are canonical, on tables where the answer varies per row and per user — the arrangement
that produced the E2 defect Slice 1 had to correct (D-168). Kept apart, the reporting query
has **nothing to filter**: every row is canonical by construction, because only the
synchroniser writes one, and a host test scans `lib/` to keep it that way.

**Every row is owned by a user.** A back-office workstation is shared, so "the cached P&L
for Crystal Canopy" is a fact about *a person's* authority at a moment, not about the
installation. Every primary key and every index leads with `owner_user_id`, which makes
User B reading User A's figures structurally unavailable rather than something a query must
remember (D-074).

**A confirmed revocation removes it outright.** Unlike a financial document there is no
exception to make: nothing here is anybody's unsent attempt, and the server hands it all
back when authority returns. The marker is deleted **first** — a coverage claim standing
over rows that are about to go would tell the engine a property is complete while its
figures are removed underneath.

### 30.2 Completeness is a marker, never a row count

An empty cache and a fully synchronised year with no trade are identical in the data.
Collapsing them is how a device tells a manager the hotel earned nothing (D-106's lesson,
one layer up), so the claim is a separate record, written **last, inside the same
transaction** as the rows it certifies (D-108).

Keyed per **user x business unit x dataset x financial year** — the smallest thing that can
honestly be complete on its own:

| | |
|---|---|
| per user | a shared workstation (D-074) |
| per business unit | authority is granted a property at a time |
| per dataset | revenue may synchronise while expenses fail, and a P&L needs both (D-163) |
| per financial year | retention is current + previous FY, and a range crossing 1 April needs both sides |

Coverage is therefore a **conjunction**, and every term is load-bearing: a range is covered
only when both datasets are certified for every financial year it touches, for this owner
and this property.

### 30.3 The delta asks for changed documents, never for a period

The obvious query is *"changed rows inside the year I am refreshing"*, and it is wrong in a
way that never surfaces as an error.

```
        a sale is corrected from 30 June to 1 July

        a June-filtered delta   returns NOTHING for it — there is no June row any more
        the cache               keeps its June figure, for ever
        the figure              is wrong, stable, and reconciles against itself
```

So the delta asks for **every** contribution the caller may see whose document generation
is above the watermark, in any period, and the **document** is the unit of replacement: for
each retained year, a changed document has its cached rows for that year deleted and its
current ones inserted. June loses the rows and July gains them without anything knowing a
correction happened.

Replacement is **bounded by the year**, so refreshing one year cannot delete another's rows
for a document that contributes to both (§15).

### 30.4 A void arrives as a row and is dropped on the way in

Both projections **carry** `voided_at` rather than filtering it: a voided document stays
inspectable and every aggregate excludes it (D-006). That is precisely what makes a void
visible to a delta — the row comes back, its document is replaced, and the voided rows are
not stored. Active effect zero, with nothing to remember.

Had the projections filtered voided rows, a voided document would simply vanish from the
delta and its stale contributions would stay cached for ever. The rule that keeps evidence
inspectable is the same rule that makes the cache correctable.

### 30.5 The watermark is the lowest, and the overlap is a mitigation

```
        since = min(marker.generation) over every requested (unit, year),
                taking 0 for any scope with no marker
        ask   = max(0, since - safetyOverlap)
```

**The minimum, not the maximum.** A property granted today has never been certified, so
taking the highest watermark would ask the server for changes since a point that property
never reached — and every document written below it would be missed: a gap no later run can
notice, because the marker would say they had arrived.

The overlap addresses the commit-visibility hazard §5.2 already records — a sequence value
is allocated at write and becomes visible at commit, so a naive `> max(seen)` can step over
a transaction that committed late. Re-reading below the watermark is free of consequence
because replacement is keyed on document identity: the same document delivered twice lands
in exactly the same state. **It is a mitigation, not a fix**, and the documented upgrade is
still a snapshot cursor.

Because the overlap masks a wrong watermark until the two generations are further apart
than the overlap itself, the regression that pins the minimum places them 5,000 apart.

### 30.6 Failure is per dataset, and a failed run changes nothing

Revenue may land while expenses do not. Each writes its own marker, so a P&L over a
half-synchronised scope **refuses** rather than presenting takings as though they were
profit (D-163). A run that fails writes nothing and withdraws nothing: unknown is not
revoked (D-048 §1), and a network failure is not evidence about a property's books.

Every unit in a run is certified to the **same** generation, including one that had no
changed document — one run is one authoritative boundary, and a quiet property certified
lower than a busy one would drift permanently behind and re-read the same delta for ever.

### 30.7 Retention

Current and previous financial year, plus whatever was fetched **on demand** (D8). Pruning
is a separate object from synchronising, because it is a different decision taken on a
different clock: folding it into a run would mean a device that synchronises on 1 April
silently loses the year it was reporting five minutes earlier, in the call that was meant to
refresh it. An on-demand year survives the sweep — somebody deliberately fetched it, and
deleting it under them would make the older-range workflow useless in the one case it exists
for.

Outside retention the honest answer is `notDownloaded`, never a confident zero over an empty
table.

### 30.8 Production reads the cache, and that is asserted

Two adapters sit behind `LocalReportingSource`, and wiring the wrong one produces no error
and no empty state — just a correct sum of the wrong rows:

| | |
|---|---|
| `CachedReportingSource` | the synchronised cache. **What production resolves.** |
| `DriftReportingSource` | this device's own contribution projections |

`bootstrap` builds the gateway beside every other one, `main()` overrides the provider, the
acceptance harness covers it — D-134's guard refused the change until it did — and a host
test reads what production actually returns. That is the D-077 shape, applied before the
surface exists rather than after two real devices have shipped without it.

### 30.9 What the guard caught, and why three files moved

The Slice 3 assertion that *no management formula lives in an engine* refused three new
files. It was right in every case, and each was fixed by moving the file rather than
widening the check — which is the D-103 anti-pattern:

* the **cache** sums in SQL and wraps the result in `Money`, which is what a repository
  does, so it lives with the repositories;
* the **synchroniser** copies a rate across the wire without computing with it, which is
  transport, so it lives with the sync engine;
* *"which financial years does this range touch"* is **period math**, so it lives in
  `domain/finance` where the engine, the coverage oracle and retention all read one answer
  (spec §21.1).

`lib/data/reporting/` now holds the engine and its two sources, and nothing in it touches
paise, a rate, or a date derivation.

---

## 31. The server reporting boundary, and D-020 parity (2026-09-08)

Phase 5 Slice 5. §30 gave the local engine something to stand behind; this gives it
something to be **checked against**, and answers the question the slice exists for:

> Given the same authorised scope and the same `ReportRange`, do the offline canonical
> reporting engine and an authoritative server calculation produce exactly the same
> management financial result?

```
        ReportRequest ──normalise once──► ReportRange
                              │
          ┌───────────────────┴───────────────────┐
          │                                       │
   CachedReportingSource                  RemoteReportingSource
   (the synchronised cache)               (public.reporting_primitives)
          │                                       │
          └────────► primitive summed paise ◄─────┘
                     + per-side coverage
                              │
                       Pnl.compute / Pnl.consolidate      ← one calculator
                              │
                        ReportEnvelope
```

### 31.1 Coverage is per side (D-183)

Slice 4 stored coverage markers per **dataset** and then collapsed them into one value per
property, so a scope whose expenses were complete and whose revenue had never arrived
refused as `bothSidesUnavailable` — naming neither the missing side nor the sound one. The
refusal was right and the reason was wrong, which is not cosmetic: it sends a reader to look
for a problem that is not there.

`UnitReportingFacts` now carries `revenueCoverage` and `expenseCoverage`, the oracle answers
per side, and the engine maps each independently into `Pnl.compute`. Revenue missing alone
refuses `revenueUnavailable`; expenses missing alone `expensesUnavailable`; both, both. Both
complete over a range with no trade is a real ₹0 report, because **zero is a figure and
unavailable is not**.

`ReportingCoverage` gains `notAuthorised` beside `notDownloaded`. Slice 3 wrote the enum
with two values precisely because nothing could construct a third; the remote source now
can, and *"synchronise this"* and *"ask somebody for a grant"* are different instructions
that must not arrive as one.

### 31.2 The boundary is `security invoker`, and it enforces D-164 in full (D-184, D-187)

> **Corrected 2026-09-08.** This section first said that `security invoker` was *"the whole
> of its safety"* and that the absence of a `reports.view` check *"creates no exposure"*.
> The first half is true about **data access** and was the wrong test to apply: D-164 is a
> statement about the reporting **authorization contract**, and a client-callable P&L that
> enforced two of its three capabilities was under-authorized against it. Proven red — a
> principal holding `revenue.view` and `expense.view.all` for Crystal Canopy and no
> `reports.view` received ₹2,28,086.02 of that property's cost base — and closed in
> `20260908050614`. The corrected rules are below; the reasoning is D-187.

`public.reporting_primitives(uuid[], date, date, boolean)` returns the primitive canonical
sums for a named set of properties over one inclusive `pnl_date` range.

It runs with the **caller's own privileges**, over the two `security_barrier` contribution
projections and nothing else, so every predicate that already governs a reporting read
governs it. **Anything it can return, the caller could already have selected row by row and
added up** — it grants no new data access. A `security definer` version would have run as
the owner against tables the caller deliberately cannot read; two invariants assert
`prosecdef = false`.

That is necessary and it is not sufficient, which is the whole of the correction. The
authorization contract is D-164, and it is enforced here in full:

```
        reporting_ok(unit) = has_capability('reports.view', unit)
                             AND (one property requested OR unscoped reporting authority)

        revenue_authorised = reporting_ok AND has_capability('revenue.view', unit)
        expense_authorised = reporting_ok AND has_capability('expense.view.all', unit)
```

`expense.view.own` is named nowhere and cannot qualify; nothing branches on a role code. An
unauthorised side comes back **null, never zero**, so a Data Entry holder cannot be handed a
plausible P&L built from their own costs against a revenue side of nothing — and a principal
without `reports.view` loses **both** sides together, so no combination of missing
capabilities can produce half a P&L (D-163).

**A request naming more than one property is the organisation report**, and needs the
unscoped form of all three capabilities. Two scoped grants do not silently add up to an
organisation-wide privilege: their holder keeps every per-property report their authority
supports and does not get the consolidated view. Proven live in both directions — the
scoped holder refused, the unscoped Owner answered.

`reports.view` therefore came off D-139's exemption list in the same migration, which is
where an exemption is supposed to go: the sentence that excused it — *the surface it governs
does not exist yet* — stopped being true the moment this RPC was granted to `authenticated`.
`reports.export`, `reports.print` and `settings.manage` stay exempt, and Slice 7 still owns
the comprehensive reporting capability audit.

**It derives nothing** — no tax rule, no rate, no business date, no accounting period, no
Net Sales, Operating Profit or margin. It needs no tax configuration to answer a historical
P&L. Every sum is cast to `bigint`, and an invariant refuses a body naming `float`, `real`,
`double precision`, or reaching for a rate.

**Scope cannot widen by omission**: `unnest(coalesce(p_business_unit_ids, '{}'))` over a null
or empty array yields no units, so there is no branch in which an omitted id means the whole
organisation.

### 31.3 One statement, therefore one snapshot

Both sides are read in a **single SQL statement**, so under Postgres MVCC they come from one
snapshot. The dangerous shape — read revenue, let a transaction commit, read expenses, and
call the pair one P&L — is excluded structurally rather than by care: the function is
`language sql` and an invariant refuses a body containing more than one statement or a
`plpgsql` rewrite, where two statements under READ COMMITTED would take two snapshots. The
port's scope-wide read exists for the same reason, so a consolidated total is never assembled
from two properties read at two moments.

The hazard is demonstrated rather than argued. The live control drives the interleaving
itself — read revenue, void both documents, read expenses — with no sleep and no race, and
produces a pair that was never true of the hotel at any instant. The RPC, asked at any
moment, returns one of the states that were.

### 31.4 Two engines, one orchestration (D-185)

Spec §21.2 leaves an engine nothing to differ about except its source, so
`LocalReportingEngine` and `RemoteReportingEngine` are one `ReportingEngine` over two
adapters behind one port — and the D-020 suite therefore compares the thing that can
actually differ: **does the synchronised offline cache mean the same thing as the
authoritative backend?**

The comparison is exact: range, scope, Gross Sales, GST, Net Sales, Expenses, Operating
Profit, **contribution counts**, per-unit and consolidated totals, the revenue category
breakdown **including its treatment**, and the expense hierarchy breakdown. No tolerance,
integers only. Two controls give it teeth — a zero-valued ghost row that fails on the count
alone, and a re-rated aggregate returning `750714` where the truth is `750715`.

One asymmetry is designed and is stated rather than skipped: the remote engine can answer a
range the device has never downloaded, and the local engine says `notDownloaded` for it
(D-170). That is a disagreement about coverage, not about money, so parity is asserted only
where local coverage is complete and the other case is asserted explicitly.

**The remote engine writes nothing** — no cache, no marker, no local row — and a guard
forbids the words that would let it. A remote read that synchronised on the way past would
make the two sources agree because one had just overwritten the other. Retry is free: the
query is read-only and `stable`. The local engine holds no reference to the remote one, so
reporting stays ungated on connectivity (spec §21.4).

### 31.5 Measured, and what is recorded rather than fixed (D-186)

`EXPLAIN (ANALYZE, BUFFERS)` as the development Owner, whole of FY 2026-27:

| | |
|---|---|
| revenue aggregate | **0.3 ms**, `Index Scan using revenue_entries_reporting_idx` |
| expense aggregate | **368.7 ms**, dominated by `Filter: may_read_expense(expense_id)` over 1,094 rows |
| FY consolidated + breakdown | **774 ms** before, **398.6 ms** after |
| FY consolidated, no breakdown | **368.7 ms** |
| one month, one property | **39 ms** server-side; 98–185 ms end to end to Mumbai |

The first version scanned the expense projection **twice** when a breakdown was asked for.
Each side is now grouped once at its finest grain and the headline rolls up from those
subtotals — the same integer, because integer addition is associative and rounding happened
once at the component and was stored (spec §6.5). `p_breakdown` governs what is returned,
not what is read.

The remaining cost is `may_read_expense` evaluated once per candidate row: a reviewed
authority predicate (D-169). Making it cheaper belongs with the reporting capability model
(Slice 7) or performance hardening (Slice 8), not inside a parity slice. **No materialised
view and no aggregate table** — nothing has been measured that needs one, and one month sits
comfortably inside the 400 ms escalation trigger §9 records.

### 31.6 What Slice 5 deliberately did not build

No P&L screen on either platform, no filters, no charts, no exports, no freshness
presentation, no transaction drill-down, no production release infrastructure. No change to
`public.expense_sees_whole_org()`, which is still on the reviewed API surface, still called
by nothing, and still carried to Slice 7 (D-127).

**And the corrective is bounded to what it names.** It adds a `reports.view` evaluator at
the one client-callable reporting boundary and deletes that capability's exemption line.
It does **not** remove `expense_sees_whole_org()`, redesign the reporting role templates,
build any Slice 7 reporting-security UI or provider work, or add an export or print
evaluator. Slice 7 still owns all four, plus the comprehensive reporting capability audit
and the accumulated-state security acceptance.

---

## 32. One report is one snapshot (2026-09-08)

Phase 5 Slice 6 opens with an audit of local as-of coherence, and the audit found that the
Slice 4 cache could not honestly say *"as of T"* — not because a line was wrong, but
because nothing had ever established what "as of" meant. This is the corrective. Decision
D-188; local schema **v18**; migrations `20260908122910`, `20260908123059`,
`20260908124127`.

### 32.1 What was wrong, in three facts

* `generation` was `max(change_seq)` **over the rows the delta happened to return**. It is
  data-derived, and a boundary is not.
* The two datasets were **two HTTP calls**, therefore two MVCC snapshots. Anything
  committing between them lands in one and not the other.
* `server_confirmed_at` existed on the marker and **no reporting call site wrote it**.

```
        t0   revenue certified to 19981
        t1   a sale accepted            19990
        t2   an expense accepted        19991
        t3   expense certified to 19991

        the cache now equals the server's state at NO instant
```

Both halves canonical, the pair a P&L of a moment that never existed — and under D-163 the
two sides are subtracted from one another, so the error lands in Operating Profit and every
figure still reconciles.

### 32.2 The transport: one statement, one snapshot, one server time

```
public.reporting_snapshot(p_business_unit_ids uuid[],
                          p_revenue_since bigint,
                          p_expense_since bigint) returns jsonb
        language sql · volatile · SECURITY INVOKER · search_path = public, pg_temp

        snapshot_id   pg_current_snapshot()::text     opaque, server-issued
        server_time   now()                           the SAME statement's transaction time
        units[]       reporting_authorised per unit
        revenue[] · expense[]                         both datasets, one MVCC snapshot
```

An invariant refuses a body of more than one statement or a `plpgsql` rewrite, which is the
structural argument `reporting_primitives` already carries (§31.3): *revenue query, then
expense query* cannot be written here.

`now()` rather than `clock_timestamp()`, because the transaction timestamp is the moment the
snapshot belongs to and PostgREST gives each RPC its own transaction. Never a second
`select now()`, which dates one moment with another's clock, and never `DateTime.now()`,
which is a device reading and is not evidence about a server (spec §9).

**It is not the Slice 5 aggregation RPC.** It returns canonical facts and nothing derived —
no P&L arithmetic, no tax re-rating, no UI strings. Authority is the Slice 5 boundary
unchanged and stated per unit: `reports.view` ∩ `revenue.view` ∩ `expense.view.all` (D-164,
D-187), `security invoker`, no base table exposed, no role name, non-enumeration preserved,
and `reports.export` / `reports.print` deliberately not required — reading a report is not
exporting one.

### 32.3 Snapshot identity is not the delta cursor

| | Answers |
|---|---|
| **snapshot identity + server time** | which authoritative moment these facts jointly are |
| **`change_seq` cursor** | where the next delta resumes |

A sequence value is allocated when a row is written and becomes visible when its
transaction commits (§5.2), so it orders work and **dates nothing**. *Complete through
generation G* therefore does **not** mean *every canonical transaction with
`change_seq <= G` was in this snapshot*, and the safety-overlap doctrine stays exactly as
D-180 left it.

**`min(generation)` is prohibited as a coherence rule**, and the prohibition is installed
rather than written down: a behavioural regression certifies two properties to the
*identical* generation from two runs and requires the freshness claim to be withheld, and a
structural guard fails if any file in `lib/data/reporting` names a generation at all. Both
were seen to fail before they were trusted.

### 32.4 The local commit order is part of the rule

```
        receive the whole snapshot
          → begin transaction
              → revenue replacements
              → expense replacements
              → coverage markers
              → shared snapshot evidence            ← LAST
          → commit
```

A run that fails anywhere leaves no evidence and no half-certified side. That is what makes
*one snapshot or none* true rather than intended, and it is the same discipline D-108
applied to the configuration marker one phase earlier.

### 32.5 What a report may claim

Every required segment — every property, **both** datasets, every financial year the range
touches — must carry the **same** evidence. Otherwise the report is produced with **no
freshness claim**: the figures are canonical, availability is unchanged, and not a paisa
moves. Withholding the stronger claim is the whole remedy, and null is **not** a third
freshness state.

A transport failure changes none of it — no purge, no coverage downgrade, no destroyed
marker, no zeroed figure (D-070) — and an authorisation refusal is not staleness.


---

## 33. The Owner Ledger (2026-09-10)

Phase 5 OA-1. A **second financial subsystem**, deliberately beside the P&L rather than
inside it: owners take money out of the business and consume without paying, and neither act
is an operating expense or a sale. Decisions D-189 … D-203.

**OA-1 is the foundation only.** No settlement calculation, no statement, no owner reporting
surface, no client screen. Those are OA-2 and OA-3, and a structural guard asserts the owner
layer computes no balance and no entitlement.

### 33.1 Why it is a separate ledger rather than a category

The cheapest-looking implementation is an expense category called "Owner Withdrawal". It
would be wrong in the one direction nobody notices: an owner drawing ₹50,000 would flow
through `expense_period_contributions`, reduce Operating Profit by ₹50,000, and the
management P&L would report that the business performed worse than it did. A distribution to
an owner is not a cost of running the hotel.

So the Owner Ledger writes to `owner_ledger_entries` and to nothing else, and **there is no
path from it to either contribution projection.** That is asserted two ways — a scan
requiring the owner write path to name no expense or revenue table, and a live comparison of
both contribution totals before and after a run that records ten movements.

The reachable mistake that remains is a person creating that category by hand, and that is
what the `KM032` trigger refuses (§33.6).

### 33.2 The current account, and why its balance is derived

An owner's position is a carry-forward current account. **The closing balance is derived
from the movements and never stored** (D-190).

A stored balance is a second copy of a figure the movements already determine, and every
hazard of one is the hazard of maintaining it — a correction that forgets it, a void that
leaves it, a replay that applies twice, a device that recomputes it differently. It is
D-157's argument for the revenue contribution projection, in the one place where being wrong
is invisible: a wrong balance reconciles against itself perfectly.

```
        owner position  =  Σ credits − Σ debits   over canonical movements
        stored anywhere =  nothing
```

An opening position that predates the system is an `opening_balance` **movement** — dated,
audited, correctable, voidable — rather than a column on the owner master with no date, no
reason and no author (D-191).

### 33.3 The share is basis points, and its timeline moves forward only

`ownership_shares` carries `share_basis_points integer`, date-effective, two owners at 5000
each totalling exactly 10000 (D-189). Never a percentage, never a `double` — 50% of an odd
number of paise has to reconcile exactly, which is why `rate_bp` has had this shape since
D-017.

**V1 fixes the vector at `[5000, 5000]` (D-204).** Ownership is 50:50 between exactly two
owners, and 60/40, 70/30, a third owner, a single owner holding everything, a partial total
and a total above 100% are all refused rather than allocated. It is enforced twice, because
the two failures are different: `OwnershipShareSet.resolveV1For` refuses to **infer** a
ratio nobody approved, and `owner_share_set` refuses to **accept** one, so the database
never holds a configuration every settlement would later refuse. A host guard pins the two
numbers to each other.

The rule composes rather than replaces: `resolveFor` stays the general date-effective
resolution — which is what keeps historical records readable, and history legitimately
contains ratios V1 no longer configures — and `resolveV1For` adds the ruling on top. **The
schema is untouched and the migration asserts it**: encoding a business rule on the column
would make an authorised future ratio a migration of history.

Two further rules bound the timeline, and **both refuse with a sentence rather than with a
constraint**:

| | |
|---|---|
| a change takes effect on the **first of a month** | a mid-period change would split a settlement period into two ratios, and OA-1 builds no apportionment for that |
| a change may only be **later** than every share the owner already has | rewriting a historical ratio would silently restate every settlement computed under it (D-201) |

Setting a share closes the one still open on the day before the new one begins, so a ratio
change is a single business act rather than a window in which the shares do not total 10000.

### 33.4 Attribution is the server's, and the client's opinion is compared

A family member is linked to exactly one owner with effective dates. Non-chargeable
consumption by that person is attributed to that owner; family members receive no profit
share, and a family member may be recorded as who *collected* a withdrawal while the debit
stays with the owner (D-195).

```
        client sends   the person, and optionally a declared owner
        server does    resolve the link at the movement's business date
        on agreement   record, snapshotting the owner it resolved
        on difference  refuse — never re-attribute silently
```

The declaration is **compared, never used**, which is D-114's contract applied to attribution
instead of to tax: two defensible answers exist and neither may overwrite the other silently.

**The link is immutable.** Re-pointing a family member at a different owner would restate
every movement already attributed through them, so the row is the identity — ending a link
and creating a new one is the supported act, and a trigger refuses the reassignment. Each
movement snapshots the resolved owner, so history explains itself with no mapping lookup, the
discipline D-080 established for the tax snapshot.

### 33.5 Movements, and what the boundary refuses

Five types, one table, one write path. Amounts are **positive integers and the type decides
the sign**, so a negative amount is refused rather than reinterpreted; `opening_balance` and
`manual_adjustment` state their direction because either is legitimate for them.

Everything the rest of the project's financial write path already guarantees is reused
rather than rebuilt: `mutation_id` idempotency (D-004), `base_row_version` on update and void
with a mismatch surfacing as a **conflict** (D-021), the property's business date under the
unit cut-off (D-067), period locks, the edit window, one queued intent per document with a
correction rewriting it in place (D-125), and a rewritten update carrying the base version it
was made against (D-130). `KI-OWN` numbers are server-issued on acceptance and a replay
returns the same one.

A **manual adjustment** requires a stated reason, and so does a void — under the canonical
whitespace rule, so a tab is not a reason (spec §14.1, D-142). The local mirror of that
CHECK had to be written `trim(x, char(32,9,10,13))`, because SQLite's one-argument `trim()`
strips spaces alone — D-138's server-side defect, in SQLite (D-202).

### 33.6 The Expense guard, and what it is not

A trigger refuses an expense category whose name could only mean an owner movement — an
owner, partner or proprietor qualifier followed by a drawing, a withdrawal or a settlement —
with `KM032` and a sentence naming the Owner Ledger, so the person meets the right workflow
rather than a wall.

**"Drawings" alone is not refused**: a hotel's building expenses may legitimately involve
architectural drawings. The migration proves both directions at deploy time against real
rows — the refusal, and that an ordinary category still inserts — because a guard that
refused everything would satisfy its own negative test perfectly and would have broken master
administration entirely.

**No fifth `nature` value was invented.** Adding `owner_drawings` to the CHECK would be a
label nothing evaluates unless something did, and if something did the expense engine would
have acquired a concept of owner movements — which is what this design says it must not.

**The revenue side needs no trigger, and that is not an omission.** There is no path from the
Owner Ledger to `revenue_period_contributions`. What *would* be a defect is a non-chargeable
bill typed into the Restaurant revenue screen, and no database trigger can tell that from a
real sale — the amounts and the category are identical. That is an operator-workflow
question, recorded as one rather than pretended away with a rule that cannot see it.

### 33.7 Authority

Eight capabilities under **`owner_masters.*`** and **`owner_ledger.*`**. The underscore is
mechanical rather than aesthetic: three shipped reporting migrations refuse any boundary body
matching `\mowner\M` as a role-name branch, Postgres word characters exclude `_`, so
`owner.ledger.view` would have failed a deploy-time invariant with a message about role-name
branching three migrations from the file being edited (D-199).

| | |
|---|---|
| Owner | everything, unscoped |
| Accountant | six — records, reads, corrects, voids; **not** `owner_masters.manage`, **not** `owner_ledger.adjust` |
| Manager, Data Entry | **nothing in this domain in V1** |

Reading the ledger is **all-or-nothing and never sliced by property**: an owner's current
account spans both business units, so a per-property slice is not a narrower view but a
misleading one, and the read policies are asserted to carry no `business_unit_id` predicate
at all (D-196).

That assertion is what exposed D-200. The reads were first gated on
`has_unscoped_capability('owner_ledger.view')` — and D-025 forces every non-Owner grant to
name a business unit, so an unscoped requirement is satisfiable by the Owner and by nobody
else, for ever. The Accountant could record, correct and void a movement and then read
nothing. **That is D-110 and D-116 a third time**, and it is invisible to a test that only
checks a scoped user sees *less* than the Owner, because both see zero. `has_capability_anywhere`
keeps the all-or-nothing principle exactly while making the grant satisfiable, and the class
is now closed by a catalogue search over policies **and** over functions.

### 33.8 The local half

Drift **v19** adds the four tables. The three masters are `organizationGlobal`; the ledger is
`scopedFinancialHistory` — purged on a confirmed revocation, sparing the actor's own unsent
work (D-070, D-074) — and every table is classified, because an unclassified one is a
decision nobody made.

Revenue is a registered mutation type in the existing transport rather than a second sync
engine: the same outbox, worker, backoff clock and actor filter, with
`RoutingMutationEndpoint` gaining a fourth arm. A build with no owner endpoint routes the
intent to one that does not recognise it and answers terminally, so the entry is kept for a
person to see rather than discarded.

### 33.9 What is deliberately absent

No settlement calculation, no entitlement, no statement and no state machine. No owner
reporting surface, no P&L change, no export. **No client screen on either platform.** No
`owner_settlement.view` capability, because a capability granted and evaluated by nothing is
the family this document keeps recording — OA-3 creates it together with the boundary that
reads it (D-197).

**No Petpooja integration, and no claim that automatic POS reconciliation exists.**
**Statutory GST treatment of a non-chargeable supply is not settled by this feature.**

---

## 34. The Owner Settlement Engine (2026-09-10)

Phase 5 OA-2. §33 built the ledger; this computes what it means. Decisions D-206 … D-211.

**It builds no surface.** No settlement screen, statement, export or payout control — OA-3
owns presentation and its security boundary, and a guard asserts the feature tree names
none of it.

### 34.1 The audit that had to come first

A settlement engine over device-local partial history reconciles against itself perfectly
and is wrong by exactly the movements it never saw, so OA-2 opened by proving what a second
device could actually obtain. Against the real backend, with a fresh device: **nothing**.
Not the movements another device recorded, and not the owners, ownership shares or family
links a settlement allocates by — `ownershipShares()` read a local table nothing in
production writes, and the gateway's three master reads had no caller anywhere in `lib/`
(the D-077 shape).

**The gap was client-side.** The same session was handed everything by the server, so the
fix is a caller rather than a boundary — D-173's finding, in a second domain.

### 34.2 A full replace, and the machinery it removes

```
        owner_ledger_snapshot()        one SQL statement, security invoker
          -> snapshot_id, server_time, movements, owners, ownership_shares
          -> one local transaction: replace all, coverage evidence LAST
```

The ledger is small, so the pull takes everything every time. A correction arrives
corrected, a void arrives carrying `voided_at`, and a withdrawn movement ceases to exist —
because nothing is preserved across a run. That removes the watermark, the safety overlap,
the document-grain replacement and the lowest-watermark rule the reporting delta needs
(D-178, D-180), one of which took two attempts to control.

**One statement, therefore one snapshot.** Four separate reads would be four MVCC snapshots
and the settlement would describe a moment that never existed — the defect D-188 corrected
for reporting. An invariant refuses a `plpgsql` rewrite or a second statement.

**It calculates nothing.** No entitlement, no position, no balance, no P&L. So it needs no
new capability: `security invoker` returns only rows the caller could already select under
`owner_ledger.view`, and `owner_settlement.view` stays reserved for OA-3, asserted at
deploy.

### 34.3 Storage, and why the masters moved

`canonical_owner_movements`, `canonical_ownership_shares`, `canonical_owners` and
`owner_settlement_coverage`, all keyed by the **signed-in person** (D-074) and all purged
whole on a confirmed revocation, coverage row first.

They are a different authority class from `owner_ledger_entries` beside them: that table is
this actor's attempt state, with an outbox pointer and a retention stamp, while these are
server-owned facts that may belong to another actor entirely (D-171). Kept apart, the
settlement query has nothing to filter — every row is canonical by construction.

**The masters are owner-keyed for a reason the audit surfaced.** OA-1 classified them
`organizationGlobal`, which survives a user switch. That was safe while nothing wrote them;
filling them would leave the ownership ratio readable by whoever signs in next on a shared
workstation, against OA-1 §33.7's staff-privacy line. The OA-1 tables therefore stay empty
and the settlement reads an owner-keyed copy (D-208).

### 34.4 The arithmetic

```
        closing = opening
                + profit entitlement          (signed; a loss reduces it, never clamped)
                - withdrawals - NC - settlement paid
                + adjustment credits - adjustment debits
```

Positive means the business owes the owner; negative means the owner has overdrawn. One
statement in code, because every movement knows its own direction — so a type added later
cannot be forgotten by an arm of a `switch`.

**Cumulative entitlement, not monthly.** Halving each month strands a paisa every odd month;
the period figure is the difference of two cumulative splits, so two months of one paisa
allocate both. The remainder belongs to neither owner, is never persisted as a movement, and
resolves when cumulative profit becomes divisible. The split truncates toward zero, so
neither owner is favoured in either direction.

**Operating Profit is consumed, never recreated.** `Net Sales − Expenses` lives once, in
`domain/finance` (D-020); a guard fails the build if the settlement directory names
`netSales`, `grossSales` or `Pnl.compute`.

**Nothing is stored.** The opening position is derived from history before the period, which
is why a correction and a void need no propagation machinery at all: they recompute
everything downstream on their own (OA-D2, D-190).

**And a settlement is not cash.** A positive position claims nothing about a bank balance;
paying it is a separate `settlement_paid` movement through OA-1, and calculating one writes
nothing.

### 34.5 What is deliberately absent

No stored settlement snapshot. No provisional settlement — canonical accepted facts only.
No treasury logic. And **no automatic trigger for the pull**: `ReferenceSync` runs for every
signed-in person, and certifying complete canonical owner history to a principal entitled to
read none of it would be a claim worse than none. The trigger belongs with the surface that
holds the capability, which is OA-3's.

---

## 35. The Owner Settlement surface and its security boundary (2026-09-11)

Phase 5 OA-3. §34 built the engine; this is who may see its answer, where it appears, and
what it may never do. Decisions D-212 … D-219.

### 35.1 Four conditions, decided before a figure exists

```
        a preview is available only when
          owner_settlement.view is held                              (Q2)
          the consolidated P&L is authorised — unscoped reports.view,
            revenue.view and expense.view.all — and complete         (D-164, D-187)
          the canonical owner history is authorised and complete     (OA-2 §18)
          the 50:50 start date is configured                         (Q1)
```

Missing any one, `OwnerSettlementPreviewService` returns
`OwnerSettlementPreviewUnavailable` with the reason — `notAuthorised`,
`reportingNotAuthorised`, `ownerHistoryNotDownloaded`, `startDateNotConfigured`,
`beforeStartDate`, `reportingNotDownloaded` or `ownershipUnavailable` — and **never ₹0**.
The decision lives in the data layer, so a widget that forgot to check is still handed a
refusal.

### 35.2 The server withholds the datasets, not the client

`owner_ledger_snapshot()` computes `settlement_authorised` from `owner_settlement.view`,
`owner_ledger.view` and `reports.view` in the same statement that reads the facts, and
returns movements, owners, shares, family links and the start date **only** when it is
true — otherwise each is **null**, never an empty list (D-213). Ledger RLS is unchanged, so
recording authority still reads the ledger; **seeing the ledger is not seeing the
settlement**.

On the client, `false` is its own result and withdraws this person's canonical owner cache
in one transaction, coverage first.

### 35.3 The start date

One row per organisation in `owner_settlement_settings`, first-of-month, no default, shipped
empty; written only by `owner_settlement_start_set` under unscoped `owner_masters.manage`,
audited, concurrency-checked, idempotent (D-212). The snapshot carries it to the device
inside the same MVCC snapshot as the movements it governs, so "history as of T" and "the
date it begins from" cannot disagree.

### 35.4 Two pulls, two snapshots, no combined "as of"

`OwnerSettlementRefresher` starts both synchronisations the preview needs — the canonical
owner history first, because it carries the start date that sizes the P&L range, then the
reporting delta for every financial year that range touches (on demand for a year normal
retention would prune, D-170). **Initiating is its job; certifying is not.** The preview
reads the coverage each run left on disk and refuses on whatever is missing, so a failed
pull can never pass through as a valid zero.

The owner history and the P&L are two distinct authoritative snapshots, and the surface
shows **each dataset's own** server-confirmed time. Nothing manufactures a combined one
(D-188).

### 35.5 Revocation reaches the owner cache (D-214, D-215)

A confirmed capability loss — `owner_settlement.view`, `owner_ledger.view` or
`reports.view` — purges this person's canonical owner cache **even with business-unit
access unchanged**, decided from the confirmed principal's current state rather than a diff.
The OA-1 ledger cache is now actually purged on revocation, as it was always classified.
Nothing is purged on a network failure, and actor-owned unsent work is retained (D-070,
D-074).

### 35.6 The surface formats and nothing else

`OwnerSettlementPage` is a separate destination on both shells (§10), gated for the
interface by `owner_settlement.view` and refusing regardless when reached another way. Every
figure it shows is a field of the OA-2 result — consolidated Operating Profit, per-property
figures marked informational, the undivided remainder, and per owner the opening position,
entitlement, withdrawals, non-chargeable consumption, settlement paid, adjustments and the
closing position — with words beside the sign: **Due to owner**, **Recoverable from owner**,
**Nil — nothing due either way**. A guard asserts the feature contains no `.paise` arithmetic, no settlement formula,
and no finalize, reopen, lock or approval identifier, and that it never reads the OA-1
organisation-global owner masters (D-216).

**It is a preview.** A **PREVIEW** banner states that it is *a live settlement derived from
canonical history, not a finalized statement, and changes when the underlying figures
change*, and no statement is stored.

### 35.7 What is deliberately absent

No finalized statement, versioning or approval. No administrative screen for the start date
(the RPC is the boundary). No per-family-member breakdown. No chart. And the OA-1
owner-ledger outbox transport is still not wired in `bootstrap` — latent, because no surface
creates an owner movement (D-218).

## 36. Reporting security closure — Phase 5 Slice 7

The audited capability matrix, live controls and provenance are recorded in
`SLICE7_SECURITY_AUDIT.md` (D-220…D-222).

`CachedReportingSource` now receives the session's `Principal`, not a separately supplied
cache-owner string. Unit reporting requires `reports.view`, `revenue.view` and
`expense.view.all`; consolidated reporting requires all three unscoped. Coverage and
freshness evidence cannot substitute for authority. Unauthorised sides are not queried,
are marked unavailable, and never become a half-P&L. Providers watch session changes.

The owner-settlement repository independently checks settlement, ledger and reporting
capabilities before reading any owner-keyed dataset. The preview retains its stronger
unscoped P&L gate. Navigation remains only an interface filter.

Confirmed reporting-capability loss now reaches canonical reporting cache even when
property access remains: marker first, facts next, owner and unit filtered, transactional.
Sign-out discovers reporting-only units without depending on master rows. Network failure
does not purge and actor-owned pending work remains protected. Existing owner-cache and
no-global-master-writer safeguards remain in force.

The dead `expense_sees_whole_org()` helper is removed; reviewed API count is 57. No new
reporting capability, arithmetic, local schema version or reporting UI was introduced.

## 37. The Windows P&L surface — Phase 5 Slice 8

Decisions D-223…D-227. **No schema change, no migration, local Drift schema v21.**

```
        ProfitAndLossPage (Analytics branch, desktop router only)
          └─ pnlViewProvider ── PnlAuthority ── per-property presets ── ReportingCacheLock
               └─ localReportingEngineProvider → CachedReportingSource → Pnl.compute
          └─ pnlSyncProvider ── head check ── ReportingSync (retained / on-demand years)
```

* **Formats only.** The page reads providers; every figure is a `PnlResult` field. A
  structural guard (with planted-violation self-tests and a real sabotage seen red) forbids
  paise access, money construction or arithmetic, calculator calls, margin rounding,
  `double`, SQL, storage imports, role bundles, a hard-coded property zone, department /
  section / vendor detail, navigation, export, printing and charts in the feature.
* **Authority** (D-226): scope options and every direct read use `PnlAuthority`.
* **Periods** (D-225): presets per property via `BusinessDayRule`; consolidated refuses
  disagreeing ranges; Custom is explicit and a reversed range is refused.
* **States**: loading, synchronising, computed profit, loss, genuine zero, margin N/A,
  not authorised, revenue / expense / both unavailable, not downloaded, downloading,
  download failed, offline-but-readable, synchronised at server time, server has newer, no
  freshness evidence. None renders a refusal as ₹0.
* **Freshness and coherence** (D-227): reads and syncs serialised; server time shown in the
  scope's own property zone; figures never move on a head check.
* **Category lines**: canonical category primitives behind `breakdownReconciles`.

**Clarification (D-223):** earlier references in §29 and §31.5 to "Slice 8 performance
hardening" mean **Phase 8 — Production Hardening**. The `may_read_expense` per-row cost and
the `org_id`-leading local expense reporting index are carried there; Slice 8 did not change
them. Android (Slice 9), drill-down (Slice 10), charts, exports, printing and finalized owner
statements are not built.

## 38. The Android P&L surface — Phase 5 Slice 9

Decisions D-228…D-232. **No schema change, no migration, local Drift schema v21.**

```
        Reports tab (mobile router) ─► MobileProfitAndLossPage
          ├─ pnlViewProvider · pnlScopeOptionsProvider · pnlSelectionProvider
          │  pnlPresetAvailabilityProvider · pnlSyncProvider      ← the Slice 8 providers, unchanged
          ├─ pnlViewShownTo / pnlScopeOptionsShownTo              ← only the viewer's own (D-231)
          └─ pnl_presentation.dart                                ← wording shared with Windows (D-232)
```

* **A presentation, not a second P&L.** The phone page reads the same providers, engine, cache,
  lock, synchroniser, coverage and freshness as Windows. It arranges figures for a portrait phone
  and computes none of them. The Slice 8 calculation and boundary guards scan it.
* **Layout.** Portrait-first: title and freshness; property in a bottom sheet; relative presets
  in a horizontally scrollable strip; Custom through the calendar picker; the headline card;
  revenue by category (gross, GST, net stacked per line); expense by category; state messages;
  pull-to-refresh; and bottom clearance for the docked [ + ] action. Amounts are never shrunk:
  a figure that does not fit beside its label moves to its own line (corrected by D-286). Landscape stays usable and scrollable without a separate design.
* **Overlays** (the scope sheet and the date picker) open over the root navigator, so no choice
  and no Apply sits behind the bottom bar or the [ + ]. Android back closes either and changes
  nothing.
* **Custom dates** are calendar-only (D-229). A tapped day is its own P&L date, read by year,
  month and day with no zone, UTC or clock conversion, and never swapped.
* **Authority, periods, older years, freshness and offline behaviour** are Slice 8's, unchanged:
  the D2 intersection per property and unscoped consolidation; presets per property with disagreeing
  consolidated presets disabled and pointed to Custom; on-demand download of every missing financial
  year; synchronised-as-of, server-has-newer and no-freshness-evidence; cached complete reports
  readable offline.
* **Refresh.** On opening, whenever the person changes, from the header control, or by pull-to-refresh,
  always through `pnlSyncProvider` under `ReportingCacheLock` (D-227).

Not built, and still later slices: department and section breakdowns, transaction drill-down
(Slice 10), charts, trends, comparisons, exports, printing and finalized owner statements. D-227's
owner-settlement lock gap is still carried forward.

## 39. Reporting breakdown and read-only drill-down — Phase 5 Slice 10

Decisions D-233…D-238. **No schema change, no migration, local Drift schema v21.**

```
        category line on the P&L (Windows pane · Android pushed page)
          └─ pnlDrillProvider          location, anchored to viewer + scope + range; reset on change
          └─ pnlDrillLevelProvider     PnlAuthority → reportingDrilldownSourceProvider (under lock)
               └─ CachedDrilldownSource → ReportingCache.revenueDocuments / expenseDocuments
               └─ PnlDrilldown.*ChildrenReconcile      exact paise, or no rows at all
          └─ pnlDocumentDetailProvider  documents.contains(line), then ReportDocumentReader
               └─ gateways' fetch* only → RevenueEntry / ExpenseDocumentDetail, held in memory
               └─ PnlDrilldown.*DocumentExplains       Ready · Changed · NotAvailable · NotDownloaded
          └─ RevenueDocumentBody / ExpenseDocumentBody  values in, no actions
```

* **Two kinds of truth, kept apart.** Hierarchy, rows and amounts come from the canonical
  reporting cache and work offline. Detail comes from the server on demand, and is written
  nowhere (D-233).
* **Exact or nothing.** A level shows children only when they add up to the displayed
  parent in integer paise. A document opens only when it explains the cached row;
  otherwise the surface says it changed and offers Refresh (D-236).
* **Every open is a fetch.** Opening a document row discards any copy still held from the
  last time it was open. On Windows that happens in `PnlDrillController.select`; on
  Android, in the drill page's `onSelect`. Offline, a re-opened document says it is not
  downloaded; online, it is current (D-239).
* **Read-only by construction.** The bodies own no actions, and guards scan every P&L file
  and both bodies for mutation surfaces (D-234, D-237).
* **Unchanged:** authority (D2 per property, unscoped consolidated), session isolation
  (D-231), older years (a report that is not downloaded offers no drill-down), and the
  cache lock (D-227).
* **Not built:** owner settlement drill-down, charts, trends, comparisons, export,
  printing, editing from reports, and finalized owner statements.

## 40. What Slice 11 corrected, and what Slice 12 closed — Phase 5

Decisions **D-240 … D-250**. No schema change in either slice: local Drift schema stays
**v21** and the migration ledger stays at **101** versions.

### 40.1 A superseded synchronisation writes nothing (D-240, closing D-231)

A reporting or owner-settlement run holds the signed-in person's id from the moment it starts.
If that person signs out, or a confirmed refresh withdraws a reporting capability, the purge
removes the cache — and the run's answer, still on the wire, was written back under the old id.
Six of seven cases re-applied data when proven red.

A **cache authority generation** in `app_meta` — no schema change — is advanced **inside the
purge's own transaction** on sign-out, a user switch, the fail-closed quarantine, and a
confirmed authority whose reporting or owner-settlement capabilities differ from the last one
recorded. Both synchronisers read it before asking the server and re-check it **inside the
transaction that writes**; a stale run rolls back and reports `DatasetAbandoned` /
`OwnerSettlementSyncAbandoned`, which the surfaces show as neither failure nor success.

`AuthorityStore` could not enforce this: it is saved and cleared outside the purge's
transaction, so a write can land after the purge commits and before the stored authority
changes.

### 40.2 One canonical-cache boundary (D-241, closing D-227)

Slice 8's lock lived in the P&L feature. The settlement preview reads the P&L several times
and the settlement refresh writes the reporting cache; neither took it, so a refresh landing
between two reads paired revenue from one snapshot with expenses from another (D-188).

`CanonicalCacheLock` now lives in the data layer, with one app-wide instance
(`canonicalCacheLockProvider`). P&L reads, drill-down reads, the P&L sync, the settlement
refresh and the settlement preview each run as one span under it, and the refresh invalidates
the reporting sources while still holding it. Owner Settlement depends on no P&L provider.

### 40.3 A P&L on screen belongs to one person and one authority (D-242, D-245)

The Windows drill state and the Android drill and document pages reset on
`pnlReadAuthorityKey` — the person plus exactly the P&L read grants they hold — so the same
person losing a capability closes what is open, while a session refresh that changes nothing
leaves the chosen property, period and month alone. The selection controllers and both sync
controllers are keyed on the person rather than on the whole session state.

### 40.4 Windows secure storage, as it now stands (D-244, D-246, D-249)

```
        %APPDATA%\<Company>\<Product>\
          flutter_secure_storage.dat     one DPAPI blob, plugin-managed
            krishna_mis.db_key.v1            the installation's database key
            krishna_mis.acceptance.db_key.v1 an acceptance run's own key (D-249)
          krishna_mis.session.dpapi      the session, its own protected file (D-246)
          krishna_mis.db                 the encrypted database
```

* **The session left the blob.** `flutter_secure_storage_windows` 3.1.2 deletes the whole blob
  when a read fails to decrypt, and the session is rewritten on every sign-in and refresh while
  the database key is written once. `ProtectedFileSessionStore` protects its own file with
  DPAPI (current user, no entropy — the same protection, no weaker and no stronger), writes
  through a temporary file and renames over the old one, serialises its own reads and writes,
  and **never deletes the file because a read failed**.
* **The persisted session is handed back whole** (D-244), so `recoverSession` can parse it and
  a restart restores the session rather than falling back to the sign-in screen.
* **The acceptance suite holds its own key** (D-249), selected by the data folder that already
  existed rather than by a caller passing a string: `main()` passes no folder and cannot reach
  the acceptance entry; a run given one cannot reach the production entry.
* **Android is unchanged**: the session stays in the Keystore-backed plugin store, and an
  Android acceptance run keeps the production identifier, because the harness passes a folder
  on Windows only.

The residual risk is D-036's and is unchanged: DPAPI binds to the Windows user account, not to
hardware, so any process running as that user can unwrap what that user can.

### 40.5 What Slice 12 is, and is not

Slice 12 is closure: proving Phase 5 is complete, internally consistent, reproducible and
documented. It adds no chart, no export, no printing, no finalized owner statement, no
performance work, no production deployment and no financial semantics. The one code change it
carries is D-249, which the project lead ruled must land before closure.

## 41. Dashboard periods and comparisons — Phase 6 Slices 1–2

Decisions D-251 … D-261. **No schema change, no migration, local Drift schema v21.**

```
        DashboardPeriods  ── business date(s) ──►  DashboardPeriodPair
                                                   (current, comparison, capped)
                 │
        ReportingEngine (Phase 5, unchanged) ── once per range ──►  PnlOutcome × 2
                 │
        PnlComparison.compare  ──►  MoneyComparison × 5, MarginComparison
        DashboardTrends        ──►  TrendBucket ranges, each reported like any range
        DailyNetSalesRanking   ──►  best / worst day on Net Sales
        TopN                   ──►  top lines + exact Others, after reconciliation
```

* **The dashboard adds rules, not a calculation model.** Every figure a comparison, trend,
  ranking or Top-N reads is a field of a `PnlResult`. The only new arithmetic is the change
  between two results and the grouping of lines that have already reconciled. All of it is pure
  Dart in `domain/finance`, and the Slice 2 purity guard covers the new files.
* **Two period vocabularies, deliberately.** `RelativePreset` is the P&L screen's (whole month,
  whole year, D-225). `DashboardPeriodKind` is the dashboard's (to date, D-252). Neither is
  derived from the other, so a change to one cannot move the other.
* **Ranges are built only through `CustomRangePeriod.resolve`**, the one validated constructor,
  so a dashboard range whose end precedes its start cannot exist.
* **Consolidated agreement is checked on both sides** (D-254), through `pairForUnits`, which
  takes the pairing as a function so the second check is proven rather than assumed.
* **Exactness.** Percentages and percentage points are rationals over paise, rounded once, half
  away from zero, at the precision the caller prints. The margin movement's cross product is
  computed in `BigInt`, because two crore-scale paise figures multiplied pass 2^63.
* **Unavailable is a type.** `MoneyComparisonUnavailable` carries no change, no previous figure
  and no percentage, so no surface can print a comparison it does not have.
* **Trend grain is enforced where buckets are made** (D-255): a daily or weekly bucket list
  cannot be requested for Expenses or Operating Profit.

### The three rules settled after Slice 2 (2026-09-20)

* **An ordinary figure's percentage needs a positive base** (D-256, final). Gross Sales, GST,
  Net Sales and Operating Expenses show one only when `previous > 0 && current >= 0`; the
  rupee movement is shown in every case. `currentNegative` joins the two reasons Slice 2 had,
  and the three are tested in order so a doubly negative comparison names the base. Operating
  Profit is untouched and keeps its own stricter rules.
* **A custom range's grain is a property of its span** (D-263). `netSalesGrainForCustom` reads
  the inclusive day count — daily to 31, weekly to 180, monthly beyond — and
  `offersMonthlyCostTrend` withholds an Expenses or Operating Profit trend that would have one
  bucket, because one point is not a trend. `grainsFor` therefore takes the measure, and takes
  the range when the kind is custom.
* **A bucket with no figure is a gap** (D-263). `TrendSeries` maps buckets and outcomes to
  `TrendValue` or `TrendGap`; **there is no arm that builds a zero from a refusal**, which is
  D-176's move applied to a trend point. A real zero stays a value, and a partial bucket is a
  real value too — clipped, labelled, never extrapolated.
* **Displayed margin movement reconciles** (D-264). `pointsScaled` stays the canonical exact
  figure; `displayedPointsScaled` is `round(current) − round(previous)` and is what
  `displayTwoDecimals` prints, so the three figures beside each other add up. A 60,500-pair
  sweep across five precisions asserts it, and a bound proves the two answers never differ by
  more than one unit at the display precision.

Still to come in Phase 6, and not built here: the `fl_chart` presentation layer and its
no-arithmetic guard (Slice 5), and the surfaces (Slices 6–9).

## 43. Dashboard authority and providers — Phase 6 Slice 4

Decision **D-267**. **No schema change, no migration, no server or API change, no chart and
no screen.** Local Drift schema stays **v21**; migration ledger stays **101**.

```
        sessionProvider ──► PnlAuthority.readKey  ── keys ──┬─ dashboardSelectionProvider
                                                            ├─ dashboardSyncProvider
                        └─► pnlScopeOptionsProvider          └─ stamped on every state
                                    │
        dashboardSelectionProvider ─┤
        businessDayRulesProvider ───┼──► DashboardPeriods.forUnits / forCustom
        reportingClockProvider ─────┘            │
                                                 ▼
                                    dashboardRequestFor  (grains from grainsFor)
                                                 ▼
                          dashboardViewProvider ──► DashboardEngine.build  (Slice 3)
                                                 ▼
                                          DashboardState
                                                 │
                    dashboardShownTo(state, principal)  ── authority key, not person
                                                 ▼
                               dashboardPresentation(state, sync, principal)
                            loading · available(+refreshFailure) · unavailable(reason)
```

* **One financial authorization model.** The dashboard reads the **same** scope-options
  provider the P&L does, so it cannot offer a property the P&L would refuse. The guard
  asserts the provider names no `Capability.` and no role name at all — it has no way to
  decide what qualifies for itself.
* **Authority identity is dashboard identity.** Every state carries the authority's
  `readKey`, captured before anything is read, and is shown to no other authority. That
  covers a different person *and* the same person whose capabilities have moved — the
  second is the one a person key misses, and is D-231's defect.
* **Selection survives what it should.** Keyed on the authority: a no-change session
  refresh keeps the reader's property and period (D-245); a different person or a changed
  capability starts clean, so a revoked property cannot remain selected.
* **Periods are the planner's.** `DashboardPeriods` resolves every date under each
  property's own business-date rules, with both ranges required to agree across a
  consolidated scope (D-254). The guard forbids date arithmetic in the provider.
* **One dashboard path.** Every figure comes from one `DashboardEngine.build`; the guard
  forbids a second reporting path and forbids the provider reassembling any part of the
  view.
* **Freshness is passed through, never made.** Null stays null when the engine can name no
  one snapshot (D-188).
* **Five states, no zeros.** Loading, available (with a refresh failure reported beside a
  dashboard that is still complete), not authorised, period unavailable, required data
  unavailable. `dashboardPresentation` is pure, so a surface cannot reach a different
  answer from the tested one.

## 42. The dashboard engine — Phase 6 Slice 3

Decisions **D-265**, **D-266**. **No schema change, no migration, no dependency, no
surface, no server function.** Local Drift schema stays **v21**; migration ledger stays
**101**.

```
        DashboardRequest  (a resolved pair, a scope, trends, ranking, top N)
             │
        plan        every DISTINCT range the view needs, headline first
             │
        ┌────┴──────────────── one CanonicalCacheLock span ───────────────┐
        │  ReportingEngine.report(...)  once per distinct range           │
        │  a refused headline stops after the comparator                  │
        └────┬────────────────────────────────────────────────────────────┘
             │
        assemble    PnlComparison · DashboardTrends.series
                    DailyNetSalesRanking · TopN
             │
        DashboardView  (+ combined coverage, one freshness claim or none, read stats)
```

* **It derives nothing**, like the engine beneath it. Every figure comes from
  `domain/finance`; `dashboard_engine_guard_test.dart` asserts both halves — that the
  delegation is present, and that none of thirteen domain result types is constructed here.
* **One report per distinct range.** A daily trend and a daily ranking over one period are
  the same reads and are paid for once: 37 reports for the heaviest dashboard, not 67.
* **One span, therefore one moment** (D-188, D-241). Proven behaviourally: a
  synchronisation queued on the same lock after the view's first read cannot commit until
  the view finishes. The guard counts spans; *containment* is the behaviour test's, and the
  guard says so rather than implying more than a count can establish.
* **One freshness claim, or none.** Every read must carry the same snapshot evidence.
  A badge taken from the headline would date a chart drawn from an older financial year to
  a moment that chart does not belong to. Coverage combines the same way — the weakest of
  each side across every read.
* **A refused headline refuses the view** and stops reading (D-163); the comparator is
  still read, so a refused period beside an available previous one is described honestly.

**The gate (D-266).** Two financial years, two properties, 7,300 contributions, the real
encrypted database on both platforms. Worst steady-state dashboard **168 ms** (Windows, 37
reports); Android emulator **31–41 ms** for the same workload. Cost is linear in reports
and the per-report cost is the Phase 5 engine's. **Nothing was added** — no dashboard RPC,
no second cache, no materialised aggregate, no index, no server function. The D-255 and
D-263 grain rules turn out to be what bounds the work: a year-long custom range is 14
reports because its Net Sales trend is monthly, not 367 because it is daily.

## 44. The chart foundation — Phase 6 Slice 5

Decisions **D-268**, **D-269**. **No schema change, no migration, no server or API change,
and no screen.** Local Drift schema stays **v21**; migration ledger stays **101**.

```
        domain/finance  ──decided figures──▶  chart adapters  ──▶  chart widgets
        TrendSeries                           TrendChartData        TrendLineChart
        TopNOutcome                           RankedBarChartData    ProfitBarChart
        PnlResult lines                       ComparisonChartData   RankedBarChart
                                                                    ComparisonBarChart
```

* **One direction only.** `ChartAmount` holds the exact `Money` and the string the
  application's formatter produced from it; its coordinate is a **getter** over that
  figure. There is no constructor taking a `double`, so money cannot be reconstructed from
  a position — the move D-094 made for `RevenueTaxFacts` and D-150 for the revenue
  attachment schema, applied to pixels.
* **A tooltip is a lookup, not a conversion.** fl_chart reports *which* mark was touched —
  `spotIndex`, `touchedBarGroupIndex` — and the figure is looked up in the points the
  domain supplied. Exactly one place in the layer converts a coordinate to anything, and it
  converts to a **category index**, which carries no money (`ChartSelection.indexAt`).
* **Coordinates are paise**, so they stay whole. A `double` holds every integer below 2^53
  exactly, which is about ₹90,07,19,92,54,740 — past anything this business will record.
* **A gap is a gap.** A `TrendGap` becomes `ChartAbsent`, which carries **no amount at
  all**; the line breaks at `FlSpot.nullSpot` and the bar chart draws no rod. A break-even
  month draws a rod *at* zero, so the two never render the same (D-263).
* **The value axis is anchored at zero**, always. A truncated axis exaggerates variation,
  and this is a management report. It is also what gives an Operating Profit chart a
  baseline to draw a loss beneath, and the baseline is an explicit reference line rather
  than whichever grid line happens to land there — a generated grid does not promise to
  include zero at all.
* **Axis labels are resolved, never parsed.** A tick's label is formatted from that tick's
  own integer paise, and `ChartAxis.labelFor` answers only for a coordinate the axis itself
  produced. `ChartBounds` sets the tick step to a quarter of the data span so the data's own
  minimum and maximum land exactly on positions fl_chart generates.
* **Never colour alone** (spec §20). Each series carries a marker shape and a dash pattern
  beside its colour and is named in the legend; a profit or a loss is stated by the side of
  the baseline, by the sign on the figure, by the word in the readout and by the word in the
  description. Break-even is its own word.
* **Nothing is recomputed.** The layer calls none of `Pnl.compute`, `PnlComparison.compare`,
  `DashboardTrends.*`, `DailyNetSalesRanking`, `TopN.*` or `Money.sum`, sorts nothing, and
  derives no date — a position's name arrives as a label from the surface that owns the
  application's date wording. A refused domain result draws **no financial data**.
* **One interaction model.** fl_chart reports a Windows hover and an Android touch through
  the same callback, and arrow keys move the same selection, so there is no second
  interaction model to keep in step (the discipline D-232 settled for the P&L wording).
* **Animation is off.** A financial chart gains nothing from motion, and a running animation
  makes an assertion read a figure that is on its way somewhere (D-152).

**The ranked families are composed, not plotted.** Revenue mix, top expense categories and
department spending are a **list with a bar**: a category reads *Crystal Canopy Rooftop ·
Kirana & Pulses*, which as an axis tick at 360dp either truncates the name or takes a third
of the plot from the bars, and **money must never be truncated or wrapped** — a truncated
amount is a wrong amount. So each line is real text with a proportional fill: at phone width
the name sits on its own line above the figure, and at desktop width the two occupy separate
slots. fl_chart can draw horizontal bars (`rotationQuarterTurns`), so this is the right
primitive for a ranked list rather than a workaround for something the package cannot do,
and the same models, formatters, selection and description serve it (D-269).

**Slice 5 wires the foundation into no screen.** A guard asserts that nothing outside
`lib/core/design/charts` imports it, and that assertion is the one Slice 6 must deliberately
change. A second guard asserts no file outside the layer imports `package:fl_chart`, so
replacing the package is never a change to a screen.

## 45. The Windows Overview — Phase 6 Slice 6

Decisions **D-270 … D-273**. **No schema change, no migration, no server or API change.**
Local Drift schema stays **v21**; the migration ledger stays at **101** versions.

```
        dashboardViewProvider (Slice 4)  ──►  DashboardEngine.build (Slice 3)
                    │                                   │
        dashboardPresentation ──► DashboardAvailable ──► DashboardView
                    │                                   │
        overview_page.dart  ── arranges ──►  dashboard_presentation.dart  ── words
                    │
                    └── core/design/charts  ── draws prepared values (Slice 5)
```

* **It arranges, and nothing else.** Every figure is a field of a result `domain/finance`
  produced: the P&L from `Pnl.compute`, the movements from `PnlComparison`, the buckets and
  their gaps from `DashboardTrends`, the ranked lines and Others from `TopN`, the
  per-property split from `PropertyComparison`. The Slice 6 guard forbids money arithmetic,
  sorting, ranking, navigation, mutation, export, Owner Accounts and storage in the feature.
* **Content, in order** (§17): header with scope, period, freshness and refresh; four
  headline figures — Net Sales with Gross Sales and GST secondary to it, Operating
  Expenses, Operating Profit or Loss, Operating Margin; the Net Sales trend; the monthly
  Operating Profit trend where the planner offers one; property comparison when
  consolidated; revenue mix; top expense categories; department spending.
* **Periods are the dashboard's, not the P&L screen's** (D-252): *Today so far*, *Week to
  date*, *Month to date*, *Financial year to date*, *Custom*. A period the properties
  disagree about is disabled and refused, and the reader is sent to Custom (D-254).
* **Comparisons are rendered, never computed.** The rupee movement always; a percentage only
  where the domain produced one, with the reason stated when it did not (D-253, D-256); the
  margin in percentage points, printed beside the previous margin so the three figures on
  screen reconcile (D-264).
* **Nothing is ever ₹0 that is not ₹0.** Not authorised, not downloaded, one side
  unavailable and a refused period are each their own state; a reader without qualifying
  authority sees the approved neutral line and no property name, no scope chip and no chart
  (D-163, D-259).
* **Freshness is the engine's combined claim, or none.** Where the view cannot be shown to
  belong to one snapshot, no time is stated and none is invented (D-188).
* **A failed refresh never blanks a complete dashboard.** A failed run writes nothing
  (D-048), so the figures stay and the failure is reported beside them.
* **Layout.** Four metrics across at 1366 and above, two then one as the window narrows; the
  analytical panels in two columns where the width allows. No horizontal page scroll at any
  tested size.
* **Drill-down is Slice 9.** The sections carry selection callbacks and no route: nothing
  duplicates the P&L drill-down and no temporary detail screen exists.

## 46. The Android Home — Phase 6 Slice 7

Decisions **D-274 … D-276**; `RELEASE_CHECKLIST.md` §R. **No schema change, no migration,
no Supabase or server change, no new dependency.** Local Drift schema stays **v21**; the
migration ledger stays at **101** versions.

```
        Home branch (mobile router)  ──►  MobileHomePage
              │
        dashboardViewProvider (Slice 4) ──► DashboardEngine.build (Slice 3)
              │
        dashboardPresentation ──► DashboardAvailable ──► DashboardView
              │
        mobile_home_page.dart  ── arranges ──►  dashboard_presentation.dart  ── words
              │                                      (shared with the Overview)
              └── core/design/charts  ── draws prepared values (Slice 5)
```

* **One dashboard, two arrangements.** The phone reads the same providers, authority,
  engine, lock span, coverage and freshness as the Overview (§45) and computes nothing.
  The Slice 6 surface guard now runs every rule over **both** files, so the phone is
  covered by construction rather than by a second copy of the guard (D-275).
* **One vocabulary.** Every sentence, range label, instant label and category ordering
  comes from `dashboard_presentation.dart`. Slice 7 moved the last stray literal —
  *Both properties (consolidated)* — into it as `dashboardConsolidatedScopeLabel`.
* **Content** (D-260): scope, period and freshness; Net Sales with Gross Sales and GST
  secondary to it, Operating Expenses, Operating Profit or Loss and Operating Margin,
  each with its comparison; the Net Sales trend; property comparison when consolidated
  authority exists; top expense categories; and *See full P&L*. **Revenue mix, department
  spending and the monthly profit trend stay on the Windows workspace.**
* **Portrait first.** A single scrolling column at 360, 390 and 430dp and in landscape,
  with the last item clearing the docked [ + ]. Money is never truncated, shrunk or
  ellipsised. A headline figure moves to its own line at full size. Only when it is wider
  than that whole line does it break, and then only between digit groups. The Gross/GST
  pair flows onto a second line (D-276, corrected by D-286).
* **Controls.** The property in a bottom sheet, the period in a horizontal chip strip —
  the only sideways scroll on the page — and Custom through the Material calendar with
  typed entry off (D-229, D-250). Both overlays open on the **root** navigator, so
  nothing sits behind the bottom bar or the [ + ].
* **Refusals.** Not authorised, a period the properties disagree about, a report not
  downloaded and one side unavailable are each their own sentence; a reader without
  qualifying authority sees no property name, no scope selector, no period strip and no
  `MoneyText` (D-259, D-163). A failed refresh keeps the figures and reports beside them.
* **The one navigation.** *See full P&L* switches the shell to
  `AppRouter.mobileReportsBranch`, a named constant a guard checks against the router's
  own branch order. Drill-down from a dashboard figure is Slice 9's.

## 47. The Windows Analytics workspace — Phase 6 Slice 8

Decisions **D-277 … D-280**. **No schema change, no migration, no Supabase or server change,
no new dependency.** Local Drift schema stays **v21**; the migration ledger stays at **101**
versions.

```
        Analytics branch (desktop router)  ──►  AnalyticsPage
              │
        SegmentedButton  ── analyticsSectionProvider (keyed on PnlAuthority.readKey)
              │
        IndexedStack
          ├─ ProfitAndLossPage              the Phase 5 page, unchanged   periodModel: pnlPresets
          └─ AnalyticsWorkspace             built on first open           periodModel: dashboardToDate
                │
                dashboardViewProvider ──► dashboardPresentation (once) ──► DashboardReady
                │
                ├─ RevenueAnalysisSection          ┐
                ├─ ExpenseAnalysisSection          ├ handed the ready view; arrange only
                └─ BusinessComparisonSection       ┘
```

* **One prepared view.** The three analysis sections share the dashboard's selection, its one
  `DashboardEngine.build` and its authority-stamped state (D-267). Switching sections reads
  nothing again. The Overview shares the same selection, so the two move together (D-277,
  flagged).
* **The P&L is embedded, not rebuilt.** One `ProfitAndLossPage`, with its own whole-month and
  whole-year presets, drill-down and synchronisation. The section's `periodModel` states the
  difference.
* **Arrange only.** Every figure is a field of the canonical `PnlResult`, a `PnlComparison`
  movement, a `DashboardTrends` series, a `TopN` grouping or a `PropertyComparison` split. The
  analytics guard asserts it with the dashboard guard's own token lists, shared through
  `test/support/surface_guard_tokens.dart` (D-279).
* **Revenue:** ruled Gross / GST / Net summary, the Net Sales trend at the planner's grain, and the
  revenue mix as composed ranked rows (D-269).
* **Expenses:** ruled Operating Expenses, the **monthly** expense trend or a statement of why
  there is none, top categories with the domain's exact Others, and department spending.
* **Business Comparison:** a ruled table per property and combined, in id order, in neutral ink,
  with *Profit* / *Loss* / *Break-even* in words; a grouped chart secondary to it. Only for a
  consolidated scope; otherwise an explicit unavailable state (D-278).
* **Refusals are the dashboard's own.** Not authorised, a disagreeing period, not downloaded and
  one side unavailable are each stated, never ₹0. A failed refresh keeps the analysis on screen and
  reports beside it. A set that does not reconcile draws no rows at all.
* **Shared Windows building blocks.** The scope bar, period bar, refresh control, metrics, panels,
  grid and state messages live in `dashboard_widgets.dart`, used by both the Overview and the
  workspace, with the keys Slice 6 shipped (D-279).
* **Drill-down is Slice 9.** Rows carry an `AnalyticsDrillIntent` in the domain's order, Others
  none; nothing navigates.
* **Not built:** a percentage share per category and a per-category period comparison — neither is
  prepared by the domain, and both are flagged (D-278). No value-band, subtype, vendor, occupancy,
  forecast, target or budget analysis; no export, printing or Owner Accounts.

## 48. Dashboard drill-down integration — Phase 6 Slice 9

Decisions **D-280 (closed) … D-285**. **No schema change, no migration, no Supabase or server
change, no financial-calculation change, no new dependency.** Local Drift schema stays **v21**;
the migration ledger stays at **101** versions.

```
    a figure (Overview · Analytics sections · Android Home)
          │  index or tap — never hover (D-284)
          ▼
    DashboardDrillTargets.of(ready, principal)       dashboard_drill.dart — the ONE adapter
          │  canonical ids + scope + RESOLVED range; no name, no figure, no clock
          ▼
    openDashboardTarget(origin)
      ├─ DashboardDrillLevel(location) ──► Windows: dashboardDrillProvider → DashboardDrillPane
      │                                    Android: pushPnlDrillLevel → MobilePnlDrillPage
      │        │
      │        ▼  pnlDrillLevelProvider  (origin = dashboard)
      │           viewer check → PnlAuthority again → pnlDashboardDrillReportProvider
      │           → the Phase 5 levels, reconciliation, rows and immutable detail, unchanged
      │
      └─ DashboardPnlHandoff(scope, range) ──► pnlSelection.selectScope + selectCustom
                                               → Analytics › Profit & Loss / Android Reports
```

* **Dashboards produce intent, and only intent.** No surface builds a location, reads a
  drill-down row, reads a document or routes anywhere itself. The adapter is the one place
  targets are built and opened, for both platforms. A guard holds this structurally, and
  planted violations prove the guard fails when it should.
* **The range is the figure's own.** The headline uses the pair's `current` range; a trend point
  uses its bucket's range, clipped exactly as the planner clipped it. Nothing in the adapter
  reads a clock, a calendar or a business-day rule.
* **The destination is authoritative.** A dashboard-origin anchor (D-282) is refused for a
  different person. It is also refused for anyone the P&L authority would refuse now: first by
  the destination's own check, then again by the Slice 7 cache adapter. The report beneath it is
  read by the destination through the P&L's own engine call.
* **What has transactions opens the drill-down:** Net Sales, Operating Expenses, a Net Sales or
  expense trend point, a revenue category, a top expense category and a department. A dashboard
  enters revenue at `PnlRevenueCategoriesAt`, a level added for this origin only.
* **What has none opens the P&L:** Operating Profit, the margin, Gross Sales and GST, a profit
  trend point and a property. Each is handed to the P&L as an explicit Custom period through its
  existing contract (D-283). The P&L's presets are untouched.
* **Read-only, and online for detail, exactly as Phase 5.** The document is the immutable body.
  Every open fetches again (D-239), including the Windows pane's `select`. Offline, full detail is
  "not downloaded", and a report changed since synchronisation is refused, never substituted.
* **Back.**
  * On Windows, the pane replaces the surface it was opened from inside an `IndexedStack`. The
    surface stays mounted, so its section, scope, period and scroll position return unchanged.
  * On Android, each level is a pushed page on the Home branch, so each back press goes up one
    level.
  * A change of person or authority closes the drill-down on both platforms.
* **Not built:** a percentage share per category, a per-category period comparison (D-281), a GST
  transaction list, "profit documents", and any Owner Accounts route.

## 49. Money at large text sizes — Phase 6 Slice 10 (D-286)

* **No shrink-to-fit anywhere.** `lib/` holds no `FittedBox`, `BoxFit.scaleDown`,
  `Transform.scale` or text-scale clamp, and a guard in `test/core/money_shrink_guard_test.dart`
  keeps it that way.
* **`FigureReflow`** (`core/design/components/figure_reflow.dart`) is the one primitive for a
  lead beside a figure. The two share a line while the figure's whole one-line width fits,
  measured at the reader's text scale. Otherwise the figure takes a full line at full size and
  the row grows taller. It serves the headline metrics, ranked rows, the chart header, the
  Windows analysis rows, and the Android P&L and drill-down lines.
* **The last resort is a break between digit groups.** `MoneyText` offers invisible break
  opportunities after commas only. A figure wider than a full line of its own therefore breaks
  as "₹1,66," then "383.00", never inside a group and never after a sign.
* **Layout tests measure real glyphs.** They load Roboto from the Flutter SDK. Every paragraph
  showing ₹ must be drawn at scale 1, at the system text scale, whole, and inside the screen
  (`test/support/money_layout.dart`).
* **The empty line is measured, not estimated** (D-286 clarified and test-tightened,
  2026-09-25). An exact amount stays on one line whenever the complete amount fits on the
  actual empty line available to it at the reader's text scale. The layout check accepts a
  wrapped figure only when all of these hold:
  - it lies in the **figure** child of a `RenderFigureReflow`;
  - that reflow has stacked it onto a line of its own;
  - it was given that line's full measured width;
  - its complete one-line width exceeds that width.

  Two focused tests pin the exact boundary (`test/core/figure_reflow_test.dart`).

## 50. Phase 6 closure — the stable contract Phase 7 builds on

Decision **D-289**. **No schema change, no migration, no server change in Phase 6.** Local
Drift schema **v21**; migration ledger **101**.

Phase 6 closed on 2026-09-25. It added dashboards and analytics as **presentations of the
Phase 5 reporting boundary**, and nothing beneath that boundary moved. This section states
what Phase 7 (Export & Printing) may treat as stable, and what it must not do.

### 50.1 Stable, and to be consumed as it is

| Contract | Where | What it guarantees |
|---|---|---|
| `PnlResult` | `domain/finance/pnl.dart` | Every P&L figure computed once by `Pnl.compute` from summed paise: Gross Sales, GST, Net Sales, Expenses, Operating Profit, the exact margin, and category and hierarchy lines that reconcile exactly (§28, D-020) |
| `DashboardView` | `data/reporting/dashboard_engine.dart` | One dashboard read under one `CanonicalCacheLock` span (D-265). Carries the headline pair and its `PnlComparison`, the trend series (`TrendValue` / `TrendGap`), the daily ranking, `TopN` groupings, the property split and department spending. It also carries one combined coverage and **one freshness claim or none** (D-188) |
| `PnlAuthority` | `domain/finance` | The only reporting authority test. A property needs `reports.view` ∩ `revenue.view` ∩ `expense.view.all`; consolidated needs all three unscoped (D-164, D-187, D-226). `expense.view.own` never qualifies, and no role name is read. Its `readKey` is the identity a displayed or exported figure belongs to (D-267) |
| Canonical reporting / cache boundary | `ReportingCache`, `CachedReportingSource`, `LocalReportingEngine`, `reporting_primitives`, `reporting_snapshot` | Canonical accepted facts only (D-167, D-168); coverage per side (D-183); one-snapshot evidence (D-188); abandoned on an authority change (D-240) |
| Exact money and domain rules | `Money`, `MoneyFormatter`, `domain/finance/*` | Integer paise, Indian grouping, and half-away-from-zero display rounding. Comparisons (D-253, D-256 closed), periods (D-251, D-252, D-254), trend grain (D-255, D-263), displayed margin reconciliation (D-264), and Top N with an exact Others (D-258) |
| Read-only drill-down boundary | `dashboard_drill.dart`, `pnl_drilldown_*` | Canonical IDs and exact resolved ranges in, immutable document detail out. Online-only detail, a re-fetch on every open (D-239), a changed row refused and never substituted (D-236). Authority is checked again at the destination (D-282, D-285); the P&L hand-off is an explicit Custom period (D-283 final) |
| Presentation vocabulary | `pnl_presentation.dart`, `dashboard_presentation.dart`, `report_dates.dart` | One wording for each refusal, freshness state, range and instant (D-232, D-271) |

### 50.2 What Phase 7 must not do

- **Create a second financial calculation path.** An export or printout renders the same
  result objects the screen rendered — `PnlResult`, `DashboardView` and the drill-down
  values — and contains no formula (spec §16, §21.3). No workbook formula, PDF template or
  print layout may compute Net Sales, GST, profit, a margin, a percentage, a total or an
  Others figure. The parity statement in §6.3 extends to every export.
- **Read a financial table or projection directly.** No export path bypasses the
  reporting engine, the cache lock or `PnlAuthority`.
- **Treat an unavailable figure as zero.** Refusals, `TrendGap`s, withheld comparisons
  and a missing freshness claim are carried into an export as what they are.
- **Shrink or cut money.** D-286 holds on paper as on screen: no scaled-down figure, no
  ellipsis, and a break only between digit groups when no empty line can hold the figure.
- **Grant export by visibility.** An export requires the reading authority above **and**
  the action capability for the exact scope.
  *Superseded in part by D-291 (2026-09-25):* this bullet originally said Phase 7 would
  remove the D-139 exemption in the migration that adds a server evaluator. The project
  lead ruled otherwise. `reports.export` and `reports.print` are client-enforced
  product-action controls, **no server evaluator is added**, and the exemption stays. See
  section 51.

### 50.3 Evidence at closure

Host **2,648**; live **106**, run serially. Windows real-executable, emulator and Galaxy
A06 automated acceptance all pass, and the Galaxy A06 manual checklist (§S.3) is **20/20
PASS**. Performance is inside the D-266 envelope on both platforms (recorded in D-289).

## 51. Export, PDF and printing — Phase 7

Decisions **D-290 … D-311**. **Phase 7 is closed (2026-09-28, D-311)**, and this section now
describes what shipped. It was written in Slice 1 as the contract for Slices 2 to 9, before
anything was built. The corrections made during acceptance are in 51.5 (D-308, D-309) and
51.7 (D-310). It builds only on the stable Phase 6 contract in section 50.

The export design needs **no schema change, no migration and no server change**. Local
Drift schema stays **v21**; the migration ledger stays at **101**.

### 51.1 One direction, one model, two renderers

```
    PnlResult / DashboardView                  ← the screen's own canonical result, read
    + cached master names                        under the same authority, scope, period
    + resolved scope, period, freshness          and CanonicalCacheLock span
          │
          │   ExportAuthority: view authority ∩ action capability, exact scope   (51.3)
          ▼
    export document model                      ← immutable; exact Money; no arithmetic
          │
          ├──► PDF renderer  (pdf 3.13.1, bundled Noto Sans)
          │        ├──► Windows: Save As (file_selector getSaveLocation)
          │        ├──► Windows: Print   (Printing.layoutPdf → native Windows dialog)
          │        └──► Android: Share   (app cache → system share sheet → cleanup)
          │
          └──► XLSX writer   (internal OpenXML on archive 4.x)
                   └──► Windows: Save As
```

**Planned file layout.** Slices may refine the names, but the layer boundaries are part of
the contract:

| Layer | Where | May | May not |
|---|---|---|---|
| authority | `lib/domain/finance/export_authority.dart` | combine `PnlAuthority` with the action capability | read a role name; grant visibility |
| document models | `lib/domain/export/` | copy figures, carry labels and freshness | compute, sort by amount, group, reconcile, read storage |
| XLSX writer | `lib/core/export/xlsx/` | package OpenXML: sheets, cells, styles, number formats, panes, filters, ZIP | contain a finance formula; know what a P&L is |
| workbook layouts and shared wording | `lib/core/export/workbook/`, `lib/core/export/export_wording.dart` | place a document model's figures in cells; name them in the screen's words | do arithmetic; sum a table into its Total; parse a figure |
| PDF renderer | `lib/core/export/pdf/` | lay out a document model | compute; fetch a font; read the clock itself |
| delivery | `lib/features/export/` | save, share, print, and report the outcome | build a model from anything other than the canonical providers |

### 51.2 What each output is made from

| Output | Platforms | Formats | Canonical source |
|---|---|---|---|
| Profit & Loss | Windows, Android | PDF, Excel (Windows only) | `PnlReportView.envelope` → `PnlResult`; `PropertyComparison` for per-property sections of a consolidated P&L; `OperatingMargin.displayTwoDecimals` |
| Revenue Analysis | Windows | PDF, Excel | `DashboardView`: comparison, the Net Sales trend series, the revenue mix `TopN` |
| Expense & Department Analysis | Windows | PDF, Excel | `DashboardView`: comparison, the monthly expense series, top expense categories, department spending |
| Business Comparison | Windows, **consolidated only** | PDF, Excel | `DashboardView.propertyComparison` (`PropertyFigures` via `Pnl.compute`, D-270) |

**Labels** come from the cached master graph, the source the screen already uses. They show
the current name (D-035). Range and instant labels come from `report_dates.dart`. The
sentences are the screens' own words: `lib/core/export` may not import a feature file, so
they are restated in `export_wording.dart` and a parity test holds them equal to
`pnl_presentation.dart`, `dashboard_presentation.dart` and the Analytics wording (D-232,
D-271, D-307).

**Not exported** (D-290, D-296):
- the Overview dashboard;
- chart images and screenshots;
- transaction or drill-down lists;
- single-document PDFs;
- Owner Accounts outputs of any kind.

### 51.3 Authority

```
    ExportAuthority.mayExport(principal, scope)
        = view authority for scope                      (PnlAuthority; consolidated for
                                                         Business Comparison)
          AND reports.export covering scope             (unscoped, or held for every
                                                         included property)

    ExportAuthority.mayPrint(principal, scope)          — the same with reports.print
```

**It decides before anything is built.** The check runs before any model, file or print job
exists. A refused scope produces nothing.

**An action capability never grants visibility.** Holding `reports.export` or
`reports.print` without view authority offers no action and reveals no figure. No role name
is read.

**Where enforcement lives.** It is **client-side by design** (D-291).
- The confidentiality boundary for financial data is the server's reporting authorization,
  enforced in `reporting_primitives`, `reporting_snapshot` and the RLS behind them. That
  already decides which figures reach the device.
- `reports.export` and `reports.print` are product-action controls. No server evaluator
  exists or is planned. They stay on D-139's exemption list.
- Any document that describes these controls must not claim they are enforced on the server.

**Role bundles are unchanged** (D-292). The Manager holds `reports.view` without the two
action capabilities, so a Manager can read a report but is not offered Export or Print.

### 51.4 The document model

One immutable model per output. Every model carries:

| Carried | Rule |
|---|---|
| title and scope | the property names, or "Both properties (consolidated)" (`dashboardConsolidatedScopeLabel`) |
| exact period | the resolved `ReportRange`, plus the preset or dashboard period kind that produced it |
| date basis | "P&L date" (spec §5.3), and which expenses are included (spec §10) |
| figures | `Money` values copied from the canonical result; rows exactly as the screen orders them |
| refusals | carried as refusals — a withheld comparison, a trend gap or a refused Top N is **never** a zero |
| profit / loss | stated in words beside the sign (spec §20) |
| margin | the D-224 display string, or **N/A** |
| freshness | three separate fields (51.6) |

**A guard enforces the model's rules.** It reuses the dashboard and analytics guard token
lists (D-279) and forbids the following in the model layer and in both renderers:
- money arithmetic and `Money.sum`;
- calling `Pnl.compute`, `PnlComparison.compare`, `DashboardTrends.*` or `TopN.*`;
- `double` on a money path;
- sorting by amount;
- storage and network imports.

### 51.5 Formats

**Excel** (D-294, D-298):
- Numeric money cells, written as exact decimal literals built from integer paise by integer
  formatting. **No Dart `double`** touches a money value.
- **No formulas** and no raw-paise column.
- The margin is a numeric percentage from the exact scaled integer, or the text "N/A".
- A period-over-period percentage change is the screen's rounded text, or "N/A" (D-307).
- The number format is the best reliable one available. Lakh/crore grouping is used only if
  it can be proven correct for every positive **and** negative value the workbook can hold;
  otherwise a conventional numeric currency format.
- Each workbook has a header block (scope, period, date basis, inclusions, freshness,
  generated-at), frozen header panes, and auto-filters on line tables.

**PDF** (D-295):
- A4 portrait for all four reports. Landscape was allowed where a comparison table needed
  the width; none does (D-307).
- One page furniture for every PDF (`pdf_page.dart`): one header, footer, opening block and
  table style, and one `pw.Document`.
- Every page carries a header (property, period, date basis) and a footer (page *n* of *N*,
  generated-at, synchronised-as-of).
- Tables continue across pages with repeated column headers.
- Exact Indian INR formatting through `MoneyFormatter`.
- **Money is never shrunk or cut** (D-286 applies on paper too).
- Noto Sans is bundled; no runtime font download. The Regular and Bold files and their SIL
  Open Font License live in `assets/fonts/noto_sans/`. The renderer is handed the font bytes
  and refuses a font that cannot draw ₹ (D-304).
- There is no document-information dictionary: no title, author, producer or creation date
  (D-304, §51.8).

**Printing:** the Windows print dialog receives the **same PDF bytes** the renderer made for
that model. There is no print-specific layout and no direct printer protocol. All four
reports print (D-307).
- The dialog asks for the document only when Print is pressed, and authority is decided again
  at that moment. If `reports.print` has gone, the dialog gets no bytes, the job is aborted, and
  the outcome is Abandoned (D-309). Microsoft Print to PDF may leave an empty file.
- On Windows the runner holds a second COM apartment reference, so a print can never freeze a
  later Save As (D-308).

**Suggested filenames** use readable names, never an internal id:
- `KrishnaImperialMIS_<Report>_<Scope>_<from>_<to>.pdf`
- `KrishnaImperialMIS_<Report>_<Scope>_<from>_<to>.xlsx`

### 51.6 Offline and freshness

**Offline.** Export works whenever all three hold:
- the canonical report is complete locally;
- the principal is still authorised;
- the principal holds the action capability.

**Export never syncs or fetches.** An unavailable report stays unavailable: the export is
refused with the reason the screen already gives, and missing data never becomes ₹0.

**Freshness.** Three separate statements, never merged:

| Statement | Source | Shown when |
|---|---|---|
| **Synchronised as of T** | `ReportingFreshness.synchronisedAt` — server-confirmed | canonical snapshot evidence exists (D-188) |
| **Server has newer changes** | `ReportingFreshnessState.serverHasNewer` | only when a head check actually confirmed it |
| **Generated on this device at …** | the injected reporting clock, labelled as the device's | always |

With no evidence, the document makes no freshness claim. It never presents the generation
time as synchronisation time.

### 51.7 Files

**Windows:**
- Save As through the existing `file_selector` (`getSaveLocation`), with a suggested name.
- Overwrite and collision behaviour, and write errors, are tested in the Windows UI slice.
- A failed write leaves no partial file behind that claims to be the report.

**Android:**
- The PDF is written to app-private cache and shared through the system share sheet
  (`printing`'s FileProvider).
- The file cannot be removed while the receiving app may still read it. This app's earlier
  shared exports are removed before the next share, and when the phone P&L's share control
  is first built in a session (D-306).
  - They are also removed when the person signs out, or when another person takes the
    session (D-310). This is done by a provider kept alive at the app root that watches who
    is signed in, and it never blocks sign-out.
  - Returning to the Reports tab (kept alive by the phone shell) is deliberately not a
    trigger.
  - The file is readable only by the app.
- No storage permission is declared.
- `file_selector_android` cannot show a save dialog, so the share sheet is how a user saves
  (D-293).

### 51.8 Privacy of the generated bytes

**Never present in a generated file:**
- identifiers: database, auth or Supabase ids, snapshot ids, change sequences, row
  versions;
- internal names: capability codes, cache or coverage metadata, local paths;
- test material: acceptance or test markers;
- credentials: tokens, keys, passwords.

A byte-level guard checks the generated PDF and XLSX in tests.

### 51.9 Tests the slices owe

- **Parity** (spec §21.3). The same fixture gives the same integer paise on screen, in the
  document model, in the XLSX cells and in the extracted PDF text.
- **XLSX structure.** Open the workbook and assert sheet names, cell types, number formats
  and exact values. Assert that there are **no formulas**.
- **PDF content.** Extract the text semantically and check it; check the page count; check
  the freshness wording; check ₹ is rendered with the bundled font and the network absent.
- **Authority.** The allow and deny matrix per scope, including a consolidated scope
  missing the action capability for one property. The Manager bundle is offered no action.
- **Leakage.** The byte-level guard of 51.8.
- **Performance.** Measure export rendering separately from report reading (Phase 8 owns
  the reporting engine).

### 51.10 Not in Phase 7

- Transaction or drill-down list export (D-296).
- Android Excel, Android direct printing, Android analysis exports (D-293).
- Owner Accounts exports and settlement statements (carry-forward F).
- The Overview as its own export; chart images.
- Any schema, migration, reporting RPC, reporting cache or server change. **If one turns out
  to be needed, stop and report.**

## 52. Phase 8 — how performance and hardening are measured

Decisions **D-312 … D-316**. This section is the contract Phase 8's slices report against. It
adds no code, schema or behaviour.

### 52.1 What Phase 8 may and may not change

* **Frozen:** money, GST and inclusive-total semantics, business dates, the P&L and dashboard
  rules, Owner Accounts accounting, `PnlAuthority`, export and print authority, D-070 and
  D-074. No capability check becomes a role-name check.
* **Allowed, on evidence only:** an index, a query rewrite, a retry policy, an ordering fix, a
  recovery flow. A schema or index change first reports the query, its plan, current index
  coverage, the before timing, the storage and write cost, the migration and the rollback.
* **Not without a separate decision:** aggregate tables, materialised caches, a new RPC to
  avoid local work, or reporting logic duplicated on the server.

### 52.2 Environments and datasets

Six environments (E-DEV, E-LOCALPG, E-WIN, E-A06, E-EMU, E-HOST) and three dataset classes
(CURRENT, SCALE = 100,000 contribution rows a year, STRESS = 500,000 over five years), defined
in D-313. A *contribution row* is one row of either contribution projection. A timing is a
claim about its own environment and dataset only; E-A06 is the reference Android device, and
E-HOST produces counts and plans, never a timing verdict.

E-LOCALPG is a throwaway PostgreSQL 17 cluster the harness creates in a scratch directory on
its own loopback port. It never uses the workstation's installed PostgreSQL service or its
databases, and synthetic data never reaches `krishna-mis-dev`.

### 52.3 Thresholds

| Id | Threshold |
|---|---|
| T1 | one-month canonical P&L ≤ 400 ms on E-A06; local database ≤ 500 MB (§9) |
| T2 | normal export, document model + XLSX or PDF render + file write: E-WIN < 1 s, E-A06 < 2 s; every dialog and human wait excluded |
| T3 | a stress export is reported separately and is not automatically a defect |

Anything else is measured against 400 ms as a **reporting line**: recorded, and acted on only
after a ruling.

### 52.4 How a result is reported

Id, date, commit, environment, build mode, dataset class with exact row counts and voided
share, principal by capability set, workload, run count with the warm-up discarded, median,
minimum, maximum (p90 from ten runs), threshold and verdict, and the plan or stage breakdown.
Host tests assert counts, plans and results — never a wall-clock budget.

### 52.5 The D-186 harness, and what it measured (Slice 2)

`tool/perf/` measures a server read path for a principal without changing anything: every
batch against krishna-mis-dev is one transaction that creates only a temporary probe function
and ends in ROLLBACK (D-319). E-LOCALPG is a throwaway cluster with no TCP listener, the
repository's migrations replayed in ledger order, and synthetic SCALE and STRESS data loaded
through every constraint and trigger. Its reporting objects were fingerprinted against
krishna-mis-dev and match (34 byte-identical, two identical apart from comments); an
authorisation self-test with a rolled-back positive control guards every run.

What it established (D-318): the expense read paths cost about **0.335 ms per expense row
scanned**, almost all of it the per-row SECURITY DEFINER predicate `may_read_expense`, which is
evaluated before voided, unnumbered, unrequested-property and delta filters. The reporting
transport (`reporting_snapshot`) has no date bound. At CURRENT volume every path is under
1.1 s; at SCALE a financial-year report and every sync exceed the 8 s `authenticated`
statement timeout, and at STRESS a first full sync exceeds PostgreSQL's 256 MB `jsonb` limit.
A redesign is proposed in D-318 and is **not** built. *(Superseded: built as D-320, §52.6.)*

### 52.6 The D-318 redesign as built (D-320, D-321)

**Authority, once per statement (R1).** The two reporting projections no longer call a
SECURITY DEFINER predicate per row. The caller's view-all, view-own and revenue-view property
sets are each computed once, as scalar InitPlans, by `has_capability` over every property;
the D-169 document rule is stated in set form. `may_read_expense` still guards every
single-document path. Exactness rests on the D-040 key ladder: every line's property is a
`business_units` row.

**Scoped scans (R2).** `reporting_primitives` applies the requested and authorised
properties as a scan predicate, so a one-property report reads only that property and a
refused request reads nothing.

**A paged transport (R3).** `reporting_snapshot_page` replaces `reporting_snapshot`:

```
        client                                   server (one SQL statement per page)
        ──────                                   ─────────────────────────────────
        cursor = start                     ──►   documents after cursor, in (generation, id)
        stage page under <owner>#staging   ◄──   ≤ n per dataset, never split; their rows in
        save resume state                         the requested years; has_more; snapshot id
        …repeat until both has_more=false
        publish: staged + final page +
          markers + evidence, one transaction
```

* **The document is the unit** of paging, as it is of replacement (D-178). The delta cursor
  is the document's own generation, which every server writer of lines advances (D-177,
  guarded by `document_generation_invariant_test.dart`).
* **No retention cutoff.** A first synchronisation walks every authorised document in the
  requested years, however many pages that takes; a delta lists every changed document,
  including one whose rows all left the requested years, so it can be cleared.
* **Coherence (D-188, amended).** The final page certifies the run. Because the pass is
  ordered by generation, a document changed after an earlier page reappears later at its
  newer version, so the published cache equals the final page's snapshot, up to the
  late-commit hazard the overlap already mitigates (D-180).
* **A page's cost is its own neighbourhood of the index, not the history** (D-321). The
  projections are security-barrier views, so `ORDER BY … LIMIT` cannot be pushed into them;
  a plain comparison on the generation can, and a bounded range on it is an index range. A
  page therefore reads a generation window that starts at its cursor and grows fourfold
  until it holds the page's 4n + 1 candidate rows, then fetches the page's rows inside its
  documents' own generation range. The answer is identical to an unbounded scan; the cost is
  not.
* **Nothing half-run is readable.** Intermediate pages live under the staging owner key; a
  run resumes only with an identical scope and authority generation (D-240), and is
  discarded on any change of authority, session or authorised set.

### 52.7 Retry and hang hardening (Slice 3, D-322)

**What Riverpod 3.4.2 does, read from its source** (`ProviderContainer.defaultRetry`,
`ProviderElement.triggerRetry`, `ElementWithFuture`, `ProviderElement.isActive`) and pinned by
`test/features/retry_hang_test.dart`:

| | |
|---|---|
| Default policy | up to **10** retries; delay 200 ms × 2ⁿ, capped at 6.4 s — 38.2 s in all |
| Not retried | an `Error` (`StateError`, `ArgumentError`, `FlutterError`, …) and a `ProviderException` (a dependency's failure, rethrown) |
| Which providers | every provider type, sync and async; a build that throws, or a future that errors |
| While retrying | the state is `AsyncLoading` carrying the error (`hasError` true); a `.future` already handed out **stays pending** until a retry succeeds or the last one fails |
| Who triggers it | a timer that invalidates the provider — which rebuilds it **only while somebody watches it** (`isActive`). A `.future` read once from a provider nothing watches never settles |
| Cancellation | disposal or an invalidation cancels the pending timer; an invalidation rebuilds at once |
| Project overrides | none on the container; `exportShareCacheRootProvider` already answered once |

**Policy.** A one-shot act — a refresh, an export — never waits on a provider's retries:

* **It reads its inputs once, itself.** The P&L, dashboard and owner-settlement refreshes read
  the master hierarchy and business-day rules from the repository (`readReportSyncInputs`),
  not through the providers' `.future`.
* **It is visibly running before it awaits anything**, and a second tap meanwhile is ignored.
* **Every failure lands in a status.** A failure on this device publishes `failed` with
  `localFailure`; it is never left running and never thrown at the button. Nothing is written,
  the figures on screen stay, and the person retries. A run whose person or authority changed
  publishes nothing (D-074, D-231, D-240 unchanged).

**Providers that answer once** (`retry: noAutomaticRetry`, `lib/app/providers.dart`):

| Provider | Why |
|---|---|
| `pnlScopeOptionsProvider`, `localReportingEngineProvider`, `dashboardEngineProvider` | derived: their own retry only re-reads the source's failure, doubling the wait |
| `localReportingSourceProvider`, `reportingDrilldownSourceProvider` | awaited while the canonical cache lock is held: each retry held every synchronisation waiting (76 s measured) |
| `businessDayRulesProvider` | a local read only reporting surfaces use, each with Try again |
| `exportPdfFontsProvider` | a bundled asset: a failure is not mended by repetition; a failed export clears it so the next press tries afresh |

`masterGraphProvider` **keeps** the default retry: the entry forms and Masters screens it
serves recover on their own, and no one-shot act awaits it any more.

**Explicit retry reaches the failed input.** Try again on the P&L, dashboard, Analytics and
drill-down surfaces, and every refresh a person starts, call `retryFailedReportInputs`
(`retryFailedDashboardInputs` adds the dashboard engine): each input that exists and holds an
error is invalidated, so it is read afresh now. Re-reading the report alone would meet the same
stored failure.

**Guard.** `test/app/one_shot_read_guard_test.dart` fails if `lib/` reads any provider's
`.future` with `ref.read` unless that provider answers once.

### 52.8 The Expense ledger read path (Slice 4, D-323, D-324)

```
        ExpenseFilter ─┐
        authority key ─┼─► expenseLedgerPagesProvider (reset on any change) ─┐
                       │                                                     ▼
                       └────────────► filteredExpensesProvider (stream) ── ExpenseRepository.watchQuery
                                       limit = pages × 50 + 1, offset 0       one statement:
                                                                               every filter in SQL,
        ExpenseLedgerWindow ◄── rows (≤ pages × 50) + hasMore                 sync state derived in SQL,
           stamped: authority key, filter, pages                              ORDER BY business_date,
                                                                               captured_at, id DESC
        expenseLedgerShownTo ── refuses a window for another person or question
                                                                            + 3 hydration statements
                                                                              (one IN list per child)
```

* **Every filter is a predicate of the statement that cuts the page.** Sync state is derived
  in SQL by `ExpenseRepository.ledgerSyncStateSql`, generated from
  `OutboxStatus.userVisibleState`, so the SQL and the Dart rule (`_syncStateFor`, still used by
  `load`) cannot disagree; a host test holds them equal for every outbox status.
* **One window, not appended pages.** "Load more" raises the page count and the window is read
  again as one ordered statement; appending OFFSET pages would duplicate or skip a document
  synced between two presses.
* **A total order** — `business_date desc, captured_at desc, id desc`.
* **Four statements a page**, however long: the page, then one `IN` list each for allocations,
  contributions and attachments.
* **Local schema v22** indexes `expense_id` on the three child tables and the ledger's order
  (partial on browsable rows). Hierarchy filters are a correlated `EXISTS` through the
  allocation index, so the ledger is walked in index order and stops after one page.
* **LIMIT/OFFSET stays** (§9): measured, keyset is not needed.
* **Freshness**: a stream, so a sync-state change reaches a loaded window without losing the
  reader's place (D-160). **Isolation**: a window is stamped and shown only to the authority and
  filter it was read for (D-074, D-231).
* **Failure**: plain words and Try again; the exception goes to `dart:developer`'s log
  (`expense_read_failure.dart`), never to the screen.

**Server.** No change (D-324). Every production read of `expense_document` and the expense
tables under RLS names one document and makes one `may_read_expense` call (0.5–4 ms at CURRENT
and STRESS); the per-row month residual of D-321 belongs to a read shape no client issues.

### 52.9 A missed tap is a failure (Slice 5, D-325)

```
        flutter test  ──wraps every file under test/──►  test/flutter_test_config.dart
                                                           flag = fatal
                                                           setUp:    flag = fatal       (every test)
                                                           tearDown: flag still fatal?  (else fail)
        integration_test/device_acceptance  ──►  its own D-075 setting (outside the config)
```

* **One switch, owned by the config.** No test file assigns
  `WidgetController.hitTestWarningShouldBeFatal`; the guard
  `test/app/missed_tap_policy_test.dart` holds that.
* **Per test, not per file.** Re-asserted before every test and checked after it, so test order,
  sharding and concurrency cannot alter the policy, and a test that leaks the flag fails by name.
* **An opt-out is one call.** `warnIfMissed: false` with a `// missed-tap opt-out:` reason in the
  three lines above; none exists today.

### 52.10 Start-up failure and recovery (Slice 7, D-328 … D-330)

```
        bootstrap()
          openLocalStore()          key → file → key check → upgrade (one transaction) → beforeOpen
            fails ─────────────────► closes the file, rethrows
          the rest of start-up       fails → closes the file, rethrows
        StartupRunner.start()       catches, logs the detail (developer log only), classifies
          StartupFailureApp         plain words · reference code · Try again
            permitsReset?  ───────► ResetLocalDataScreen
                                       assess()   read-only: unsent entries, bills, or "cannot check"
                                       typed RESET
                                       setAsideAndReset()
                                       Try again → the next start decides what is shown
```

* **Classification decides, and the cause decides first.** `StartupFailure.classify`
  (`lib/app/startup/startup_failure.dart`):

  | Kind | Comes from | Reset offered |
  |---|---|---|
  | configuration | `ConfigurationRefused` | no |
  | keyStoreUnavailable | key store read or write failed | no |
  | localDataUnreadable | key missing for an existing file, key malformed, `SQLITE_NOTADB`/`CORRUPT` | **yes** |
  | upgradeFailed | an upgrade step failed, cause not storage, lock or damage | **yes** |
  | inUse | `SQLITE_BUSY`/`LOCKED` | no |
  | storage | `SQLITE_FULL`/`IOERR`/`CANTOPEN`/`READONLY`, `FileSystemException` | no |
  | unexpected | anything else, including a fresh database that could not be created | no |

  A schema failure and drift's `CouldNotRollBackException` are classified by their cause,
  so a full disk during an upgrade or a save is *storage*, never *damage*.
* **Schema steps are atomic.** `onCreate` and `onUpgrade` run inside one transaction
  (`AppDatabase._atomicSchemaStep`); a failure leaves the file at its old version with
  nothing of the attempt kept, and is raised as `LocalSchemaMigrationFailed(from, to, cause)`.
* **No key is created for an existing file** (`obtainKey(databaseExists:)`), so a missing
  key is reported as missing and the secure store is not written.
* **A lock is not damage.** `applyEncryptionKey` reports only `SQLITE_NOTADB`/`CORRUPT` as
  unreadable. The busy timeout is 0 (measured); a lock fails at once and is *in use*.
* **Set aside, in an order that is safe to stop** (`LocalStoreRecovery`,
  `lib/data/local/local_store_recovery.dart`): copy the key to
  `<keyName>.quarantine.<id>` and read it back → write `recovery.json` (no key material) →
  move sidecars, then the database, then `attachments/` into
  `<support>/recovery/quarantine-<id>/` (a failed move is put back) → delete the active key.
  The next start creates a new key and an empty database at the current schema; the normal
  session and synchronisation then download what the person is authorised to receive.
* **No raw technical text** reaches the screen; a guard in
  `test/app/startup_failure_app_test.dart` holds that over the three start-up files.
