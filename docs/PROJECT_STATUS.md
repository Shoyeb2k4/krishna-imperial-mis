# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Last updated: **2026-08-27**

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 1 — Foundation: COMPLETE.** All gates passed, including the Windows ones, which
were closed by building and **actually running** the compiled desktop application rather
than inferred from host tests.

**Phase 2 — Masters & Permissions: local half complete.** Steps 1–3 of the execution
order (Masters UI, vendor management, date-effective tax configuration) are built and
tested on both platforms. Steps 4–8 — development Supabase, migrations, RLS/RPC
server-authoritative enforcement, remote repository and end-to-end verification — are next
and need the owner to create the development project.

Phase 0 complete and committed (`3a4502f`).

## Completed

**Phase 0 — Discovery & Architecture (spec v1.0, then revised to v1.1)**
- Empty workspace confirmed; toolchain verified (`flutter doctor` clean).
- Governance documents authored; 15 decisions recorded (D-001 … D-015).
- Owner decisions recorded as given (D-016 … D-019, D-023 … D-027): management accrual
  basis; date-effective per-category tax configuration; expenses at gross cost with no
  ITC; per-unit business-day cut-off defaulting to 05:00; multi-entry revenue schema with
  a daily-summary UI; Nandbhog as a Crystal Canopy revenue category; mandatory
  business-unit scoping for non-Owner roles; 7-day edit window with explicit period
  close/reopen; no production history, sanitised fixtures only.
- Architectural corrections applied: one calculation *specification* with parity-tested
  engines (D-020, supersedes D-007); explicit concurrency for voids and every financial
  mutation (D-021, amends D-005); per-platform encryption key management and threat model
  (D-022, extends D-010). Master spec bumped to v1.1 (D-028).
- Committed as `3a4502f` — *chore: establish phase 0 architecture and governance*.

**Phase 1 — Foundation**
- **14.1 Flutter project** — Android + Windows only, no web target. Identity approved by
  the owner and applied: **Krishna Imperial MIS** / `in.krishnaimperial.mis` (D-029).
- **14.2 Environments** — `dev` / `staging` / `prod` Android flavours with distinct
  application ids and launcher labels; typed `AppConfig` from `--dart-define-from-file`;
  git-ignored `config/*.json` with committed examples. No real credentials exist.
  `AppConfig` refuses a key that looks like a service-role key.
- **14.3 Module architecture** — `app/ core/ domain/ data/ features/`. `domain/` has no
  Flutter, Drift or Supabase dependency. No `utils.dart` grab-bag.
- **14.4 `Money`** — integer paise, no floating point, explicit half-up-away-from-zero
  rounding, largest-remainder allocation that always reconciles exactly, exact parser.
  One `MoneyFormatter` with Indian digit grouping; `MoneyText` is the only widget that
  renders an amount.
- **14.5 `BusinessDate`** — IANA timezone + configurable cut-off (default 05:00),
  DST-safe by calendar-day arithmetic, `periodKey` for P&L attribution.
- **14.6 Local database** — Drift + SQLite, encrypted with the SQLite3MultipleCiphers
  build selected through Dart build hooks (D-030). Timestamps stored as ISO-8601 UTC text
  (D-033). Proven encrypted on the Windows host and on an Android device.
- **14.7 Sync foundation** — five user-visible sync states, durable outbox, idempotent
  `mutation_id` reuse, optimistic concurrency including **voids**, deterministic backoff,
  crash recovery, auth-block/resume, unsynced-count stream for the freshness badge.
  Exercised against a fake server with injected failures.
- **14.8 Design system** — colour, spacing, radius, elevation, typography and two density
  scales as tokens; Material 3 as substrate only; `MoneyText`, `SectionHeader`,
  `MetricBlock`, `SyncStateChip`. No screen hard-codes a colour or size.
- **14.9 Routing shells** — separate Android (Home · Transactions · [+] · Reports · More)
  and Windows (Overview · Transactions · Analytics · Reports · Masters · Administration)
  navigation over one codebase, with honest "not built yet" placeholders naming the phase
  that will build each destination.

## In progress

**Phase 2 — Masters & Permissions.** The domain layer is built and tested; the local
schema and repositories are the next slice.

*Done and tested (51 tests):*
- **Capability model** — 26 capabilities with stable string codes, `CapabilityGrant`
  carrying an optional business-unit scope, `Principal` with fail-closed defaults, and
  the four roles as capability bundles. No role name appears in any conditional.
- **Central `Authorizer`** — one place where user × capability × unit scope × record
  state × period state is decided, in a deliberate order so the user is told the most
  actionable truth: permission → ownership → voided → period closed → edit window.
- **Business-unit scoping** — a Manager scoped to Crystal Canopy is refused on Hotel
  Krishna with `outOfUnitScope`, distinct from `missingCapability`. Covering both
  properties requires two explicit, separately revocable grants.
- **Period locks** — closed periods refuse every write including the Owner's and
  including back-dated creates; a unit-scoped close leaves the other property open;
  reopening demands a non-empty reason at both the authoriser and the lock object;
  repeated attempts never wear a lock down. **No path reopens a period implicitly.**
- **Edit window** — 7 calendar days from the *business* date, inclusive at the boundary,
  configurable rather than constant, with `correctBeyondWindow` as the escape hatch.
- **Hierarchy integrity** — `HierarchyValidator` rejects a Hotel Krishna section under a
  Crystal Canopy department, and every other impossible link, reporting each broken link
  rather than cascading from one typo.
- **Archive semantics** — archive never deletes; live children block archiving;
  being referenced by history explicitly does *not* block it.
- **Historical integrity** — `MasterReference` carries stable id, immutable code and a
  transaction-time label snapshot. Archived masters stay valid for existing history and
  are refused only for new entries.

*Also done and tested (25 further tests):*
- **Local schema v2** — `business_units`, `departments`, `sections`,
  `expense_categories`, `revenue_categories`, `vendors`, `payment_methods`,
  `period_locks`, `period_lock_events`. Real foreign keys with `ON DELETE RESTRICT` and
  `PRAGMA foreign_keys = ON`, proven by a test that bypasses the repository entirely and
  asserts the database refuses an orphan. Codes unique per parent. A raw unique index
  collapses NULL to `''` for period-lock scope, because SQLite would otherwise permit two
  org-wide locks on one period.
- **`MasterRepository`** — loads the graph, validates paths, creates with parent checks,
  renames without ever touching the code, archives via `ArchivePolicy`, unarchives. Every
  write bumps `row_version`, so masters obey the same optimistic-concurrency rule as
  financial records (D-021).
- **`MasterGraph`** — typed per level, so a category id passed where a section is expected
  resolves to null instead of silently matching.
- **Idempotent seed** — both properties with their full department/section/category trees
  from spec §4, Nandbhog as a Crystal Canopy revenue category, five payment methods.
  Re-running changes nothing and does not undo an owner's rename. **No financial data.**

**Masters UI, vendors and tax configuration (steps 1–3) — done and tested (94 tests):**
- **Windows**: browsable hierarchy with a persistent detail panel, segmented into
  Hierarchy · Vendors · Tax rules. Search matches name and permanent code and shows the
  full path. Archived records hidden by default. No modal-dialog stack.
- **Android**: section list, then a drill-down — Masters → Crystal Canopy → Kitchen →
  Food Production → Kirana & Pulses — one thumb-reachable level at a time.
- **Detail view**: name, permanent code, status, parent chain, historical usage,
  rename/archive/restore. Internal database ids are never shown.
- **Rename (D-038)**: states the cosmetic-versus-semantic rule with both worked examples,
  shows real usage, and stays disabled until the name changes **and** the rule is
  acknowledged. Acknowledgement is required unless the server has positively confirmed no
  history — a local zero proves nothing.
- **Usage authority (owner §6)**: `MasterUsage` carries its source. Cached figures say so
  on screen; only server figures are authoritative; unknown is distinct from zero.
- **Archive (D-039)**: refuses while live children exist, naming how many. No cascade, no
  orphaning, no reassignment. History always preserved.
- **Vendors**: name is the only requirement; optional fields collapsed behind one tap.
  Duplicate names refused with a useful message. Prefix-ranked search. Archive never
  deletes.
- **Tax (D-017)**: a timeline per revenue category. Changing a rate closes the old period
  and opens a new one atomically — no gap, no overlap, history untouched. No rate is
  hard-coded.

*Next slice:* steps 4–8 — development Supabase, Postgres migrations, RLS/RPC enforcement,
remote repository and sync, then end-to-end acceptance on both platforms.

Phase 1's Windows gate is parked awaiting the owner's toolchain fix.

## Verified

Labels used exactly as defined: **Implemented / Tested / Partially tested / Not tested /
Blocked.**

| Item | Status | Evidence |
|---|---|---|
| `dart format` | **Tested** | clean (36 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **105 tests, all passing** |
| Money arithmetic, rounding, allocation, parsing | **Tested** | 47 tests |
| Indian money formatting | **Tested** | 16 tests incl. every owner-specified example |
| BusinessDate + cut-off (04:59 / 05:00 / 23:59 / 00:01) | **Tested** | 20 tests incl. DST, month/year/leap boundaries |
| Outbox persistence, retry, idempotency, conflict, auth block | **Tested** | 28 tests |
| Local database encryption (Windows host) | **Tested** | 6 tests: cipher active, plaintext absent from disk, wrong key rejected |
| Local database encryption + Android Keystore (device) | **Tested** | **6 integration tests on Android emulator, all passing** |
| Routing shells, both platforms | **Tested** | 8 widget tests |
| Android debug build (dev flavour) | **Tested** | `app-dev-debug.apk` built |
| App starts on Android | **Tested** | installed and executed on emulator by the integration suite |
| Windows desktop build | **Tested** | `krishna_mis.exe` built (debug) |
| App starts as a Windows executable | **Tested** | launched, window titled, responding, no startup exception, exit code 0 on graceful close |
| Windows shell: render, pointer nav, keyboard focus, overflow | **Tested** | **15 integration tests inside the real .exe**; overflow checked at 1024x768 / 1280x720 / 1536x864 / 1920x1080 / 820x600 |
| Windows encryption + platform key handling | **Tested** | **8 integration tests inside the real .exe**, plus external verification of the DPAPI artefact |
| Windows protection mechanism identity | **Verified** | user-scope **DPAPI** (`CryptProtectData`), *not* Credential Manager — D-036 |
| Phase 2 capability model, scoping, period locks, edit window | **Tested** | 30 tests |
| Phase 2 hierarchy integrity, archive, historical labels | **Tested** | 21 tests |
| Local data lifecycle (sign out / erase / key loss) | **Tested** | 7 host tests + on-device proof |
| Phase 2 local schema v2, FK enforcement, repository, seed | **Tested** | 25 tests |
| Phase 2 Masters UI, both platforms | **Tested** | 20 widget tests |
| Phase 2 vendors and tax configuration UI | **Tested** | 17 widget tests |
| Phase 2 tax domain rules and boundaries | **Tested** | 31 tests |
| Phase 2 tax/vendor/usage repositories | **Tested** | 23 tests |
| Phase 2 backend, RLS/RPC, remote sync | **Not implemented** | needs the development Supabase project |
| Backend, auth, financial modules | **Not implemented** | later phases, by design |

## Known issues

1. **`flutter_secure_storage` pinned to 9.2.4.** Version 11.x requires `compileSdk 37`;
   this toolchain has Android SDK 36 (D-031). Revisit when the SDK moves.
2. **`riverpod_lint` / `custom_lint` deferred.** They pull an `analyzer` version that
   conflicts with `drift_dev` (D-032). Revisit at Phase 2.
3. Layout defects found by tests and fixed: a 2px overflow in the Android tab bar and a
   3px overflow in the Windows sidebar.
4. **Keyboard focus was invisible** in both shells — destinations were focusable but
   painted no focus state, so a keyboard user could not see where they were. Fixed with
   `focusColor` on both shells, covered by a Windows integration test.
5. **Measurement lesson, recorded so it is not repeated.** An early reading suggested the
   Windows window opened past the screen edge and that content was clipped. Both were
   **artefacts of a non-DPI-aware measuring process** on a 1920x1080 display at 125%
   scaling, which reports virtualised coordinates. Measured DPI-aware, the window is
   1600x900 physical at (160,60) and fits the screen; the overflow tests confirm no
   clipping. The release checklist now requires a DPI-aware tool. The window-clamping
   code added in `windows/runner/main.cpp` is retained as a genuine safeguard for small
   displays — a 1366x768 screen at 125% would not fit the default — but it fixed no
   existing bug and is described as a safeguard, not a fix.

## Blockers (former Windows blocker resolved 2026-08-27)

1. ~~**Windows build — the Visual Studio installation is in a failed state.**~~
   **RESOLVED.** The owner restarted and completed the installer; `flutter doctor` is
   green, `vswhere` reports `isComplete: true`, and ATL is registered. Retained here for
   the record only. Original detail:
   The ATL component *is* now installed: `atlstr.h` is present under
   `VC/Tools/MSVC/14.51.36231/atlmfc/include`. But the modify that added it was cancelled
   part-way. The installer log records:

   ```
   00:09:02  Showing error: It looks like you're installing or
             modifying another product right now.
   00:09:03  Error 0x8013153b: TaskCanceledException - A task was canceled.
   ```

   `vswhere` now reports `isComplete: false`, `isLaunchable: false`
   (`isRebootRequired: false`), so `flutter doctor` says *"The current Visual Studio
   installation is incomplete"* and the build stops at *"Unable to find suitable Visual
   Studio toolchain."* An `msiexec` process was still resident, which is the usual cause
   of the "another product" error. It was a build-machine state problem, not a code or
   design problem, and nothing in the application had to change.
2. **Backend not provisioned.** No Supabase project exists. Deliberate. Blocks
   authentication wiring and the Postgres/RLS half of Phase 2. The domain model, local
   schema, capability engine and period-lock engine are all buildable and testable
   without it, and that is what Phase 2 is building now.

## Deferred (by design)

- Approval workflow — modelled in the schema, disabled in V1 (spec §26).
- Partial payments / payables ageing (spec §5.4).
- Proration of costs across accounting periods (spec §5.2, open question Q10).
- Input tax credit and any statutory GST support (spec §6.1).
- Snapshot-based sync pull cursor (`ARCHITECTURE.md` §5.2).
- Historical Excel/CSV import — separate controlled workflow (spec §32).
- Bundled licensed fonts — the type scale is fixed; the family is a one-line swap once
  chosen with the owner (`ARCHITECTURE.md` §7).

## Next exact task

**Phase 2, next slice: the Masters UI**, built around the rename distinction in D-038
rather than as a generic CRUD table:

1. A usage count per master (transactions referencing it, and their date range), so the
   rename dialog can state the real impact. Required before the warning can be honest.
2. Rename flow: silent for an unused master; for one with history, a warning stating the
   cosmetic-versus-semantic rule, the number of affected transactions and their period,
   requiring explicit acknowledgement.
3. Archive flow surfacing "archive the records underneath this one first".
4. Windows gets a dense management surface with the hierarchy visible; Android stays
   compact and readable, never a shrunk desktop table.
5. Then vendor management, then date-effective tax configuration (D-017).

## Open questions for Shoyeb

**None open.**

*Resolved:* Q10 (cross-period expenses) -> **D-034**: no universal closing-month rule; the
default stays "whole amount in its own accounting period", with optional, authorised,
exactly-reconciling cross-period allocation for bills that genuinely span months. · Q1 → D-016 · Q2 → D-017 · Q3 → D-018 · Q4 → D-019 · Q5 → D-023 ·
Q6 → D-024 · Q7 → D-025 · Q8 → D-026 · Q9 → D-027 · Q11 (application identity) → D-029.

## Owner actions required

1. **Create the development Supabase project** — the only thing blocking Phase 2 steps
   4–8. Exact steps are in the checkpoint report; nothing secret is ever pasted into chat,
   and only the project URL and the publishable/anon key are needed.
2. **Optional decision:** whether archiving should also offer a *confirmed* cascade for a
   whole subtree (D-039). The safe bottom-up rule is implemented and tested; a cascade
   would be an additional action, not a replacement.

No infrastructure is to be created yet. **You will never be asked to paste a password,
service-role key, database password, private key or signing password into chat.**

## Test totals

Unit **184** · Widget **45** · Database **50** · Parity 0.
**Host suite: 279 passing, 0 failing.**
**On-device: Android 8 · Windows 23** (15 shell + 8 encryption), every one executed inside
the real compiled application.
**Current total: 302 tests, 0 failing** (279 host + 15 Windows + 8 Android).

## Build status

| Target | Status |
|---|---|
| Android (debug, dev flavour) | **Built and installed on an emulator** |
| Android (release APK / AAB) | Not attempted — Phase 9, needs the owner's keystore |
| Windows (debug) | **Built, launched, verified, closed cleanly (exit 0)** |
| Windows (release + installer) | Not attempted — Phase 9 |

## Database migration status

Local Drift schema **v2**: v1 added `app_meta` and `sync_outbox`; v2 adds the masters and
period locks. Both the `onCreate` and `onUpgrade` paths are exercised. Foreign keys are
enforced, verified by a test that writes raw SQL past the repository. No Postgres
migrations exist yet — that half waits on the backend.

## Last important decision

**D-039 — archiving a parent refuses while it has live children.** No cascade, no
orphaning, no silent reassignment; the alternatives and their costs are recorded so the
owner can choose a confirmed cascade later if the bottom-up flow proves tedious.

## Master Spec version

**1.1**
