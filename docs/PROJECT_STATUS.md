# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Last updated: **2026-08-27**

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 1 — Foundation. NOT complete.** Every Phase 1 item is implemented and verified
except the Windows gates, which remain **blocked**: the Visual Studio Build Tools
installation is in a failed state (`isComplete: false`) after the ATL modify was cancelled
mid-run. ATL itself is now present; the installation around it did not finish.
Phase 1 is **not** marked complete, because the instruction was explicit — Windows is not
verified merely because host tests pass.

Phase 2 — Masters & Permissions has begun in parallel, since none of it depends on the
Windows build.

Phase 0 is complete, approved and committed (`3a4502f`).

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

*Next slice:* the masters UI (list, create, rename, archive with the "archive children
first" message), vendor management, and the tax-rate table (D-017).

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
| Windows desktop build | **Blocked** | Visual Studio install incomplete — see Blockers |
| App starts as a Windows executable | **Blocked** | depends on the Windows build |
| Windows-host execution of domain/data layers | **Tested** | the 105-test suite runs on Windows against the Windows native SQLite build |
| Phase 2 capability model, scoping, period locks, edit window | **Tested** | 30 tests |
| Phase 2 hierarchy integrity, archive, historical labels | **Tested** | 21 tests |
| Local data lifecycle (sign out / erase / key loss) | **Tested** | 7 host tests + on-device proof |
| Phase 2 local schema v2, FK enforcement, repository, seed | **Tested** | 25 tests |
| Phase 2 masters UI, vendors, tax-rate table | **Not implemented** | next slice |
| Backend, auth, financial modules | **Not implemented** | later phases, by design |

## Known issues

1. **`flutter_secure_storage` pinned to 9.2.4.** Version 11.x requires `compileSdk 37`;
   this toolchain has Android SDK 36 (D-031). Revisit when the SDK moves.
2. **`riverpod_lint` / `custom_lint` deferred.** They pull an `analyzer` version that
   conflicts with `drift_dev` (D-032). Revisit at Phase 2.
3. Two layout defects (a 2px overflow in the Android tab bar, a 3px overflow in the
   Windows sidebar) were found by the widget tests and fixed.

## Blockers

1. **Windows build — the Visual Studio installation is in a failed state.**
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
   of the "another product" error. **Owner action required — see below.** This is a
   build-machine state problem, not a code or design problem.
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

1. **Owner completes the Visual Studio installation** (below). Then, unattended:
   `flutter build windows --debug`, launch the executable, verify the shell renders, and
   run `flutter test integration_test/encrypted_storage_test.dart -d windows`, which now
   also covers key persistence across restart, wrong-key refusal, absence of a plaintext
   financial marker in raw bytes, and the documented logout / key-destruction behaviour.
   Only then is Phase 1 marked **COMPLETE**.
2. Continue **Phase 2 — Masters & Permissions** (already under way).

## Open questions for Shoyeb

**None open.**

*Resolved:* Q10 (cross-period expenses) -> **D-034**: no universal closing-month rule; the
default stays "whole amount in its own accounting period", with optional, authorised,
exactly-reconciling cross-period allocation for bills that genuinely span months. · Q1 → D-016 · Q2 → D-017 · Q3 → D-018 · Q4 → D-019 · Q5 → D-023 ·
Q6 → D-024 · Q7 → D-025 · Q8 → D-026 · Q9 → D-027 · Q11 (application identity) → D-029.

## Owner actions required

1. **Finish the interrupted Visual Studio installation** (unblocks the Windows build).
   ATL is already on disk; the install session simply needs to complete.
   - **Restart the machine first.** That clears the resident `msiexec` which caused
     *"you're installing or modifying another product right now"*.
   - Open **Visual Studio Installer**. It should offer **Repair**, **Continue** or
     **Update** on *Visual Studio Build Tools 2026* — take it and let it run to the end.
   - Confirm: `flutter doctor` shows a green tick for Visual Studio with no "incomplete"
     line.
   - Tell me, and I will build, launch and verify Windows unattended.

No infrastructure is to be created yet. **You will never be asked to paste a password,
service-role key, database password, private key or signing password into chat.**

## Test totals

Unit **153** · Widget **8** · Database **27** · Integration **8 (Android)** · Parity 0.
Host suite: **188 passing, 0 failing.** On-device: **8 passing on Android** (including the
plaintext-marker probe and the logout/erase proof); Windows blocked.

## Build status

| Target | Status |
|---|---|
| Android (debug, dev flavour) | **Built and installed on an emulator** |
| Android (release APK / AAB) | Not attempted — Phase 9, needs the owner's keystore |
| Windows (debug) | **Blocked** — missing C++ ATL component |
| Windows (release + installer) | Not attempted — Phase 9 |

## Database migration status

Local Drift schema **v2**: v1 added `app_meta` and `sync_outbox`; v2 adds the masters and
period locks. Both the `onCreate` and `onUpgrade` paths are exercised. Foreign keys are
enforced, verified by a test that writes raw SQL past the repository. No Postgres
migrations exist yet — that half waits on the backend.

## Last important decision

**D-035 — historical integrity by stable id, immutable code and label snapshot.** Reports
group by id and show the current name, so a corrected spelling propagates; the document
detail and audit trail always show the label the entry was actually recorded under. Codes
are never editable, so no rename can break a join or a grant.

## Master Spec version

**1.1**
