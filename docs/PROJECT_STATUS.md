# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Last updated: **2026-08-26**

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 1 — Foundation.** Substantially complete and verified, with **one open item**:
the Windows build is blocked on a missing Visual Studio component (see *Blockers*).
Everything else in the Phase 1 brief is implemented and tested.

Phase 0 is complete, approved, and committed (`3a4502f`).

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

Nothing. Phase 1 is at its verification gate, pending the Windows toolchain component.

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
| Windows desktop build | **Blocked** | missing Visual Studio ATL component — see below |
| App starts as a Windows executable | **Blocked** | depends on the Windows build |
| Windows-host execution of domain/data layers | **Tested** | the 105-test suite runs on Windows against the Windows native SQLite build |
| Backend, auth, financial modules | **Not implemented** | later phases, by design |

## Known issues

1. **`flutter_secure_storage` pinned to 9.2.4.** Version 11.x requires `compileSdk 37`;
   this toolchain has Android SDK 36 (D-031). Revisit when the SDK moves.
2. **`riverpod_lint` / `custom_lint` deferred.** They pull an `analyzer` version that
   conflicts with `drift_dev` (D-032). Revisit at Phase 2.
3. Two layout defects (a 2px overflow in the Android tab bar, a 3px overflow in the
   Windows sidebar) were found by the widget tests and fixed.

## Blockers

1. **Windows build — missing Visual Studio C++ ATL component.**
   `flutter_secure_storage_windows` includes `<atlstr.h>`; every version of the package
   does. Without ATL the Windows build fails with
   `C1083: Cannot open include file: 'atlstr.h'`. This is a one-time build-machine
   prerequisite, not a design problem, and it was found in Phase 1 exactly as
   `ARCHITECTURE.md` §8.3 intended. **Owner action required — see below.**
2. **Backend not provisioned.** No Supabase project exists. Deliberate. Blocks
   authentication wiring and all of Phase 2.

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

1. **Owner installs the C++ ATL component** (below), then:
   `flutter build windows --debug` and
   `flutter test integration_test/encrypted_storage_test.dart -d windows`
   to close the last Phase 1 verification gate.
2. Begin **Phase 2 — Masters & Permissions**: the master-data schema and migrations, the
   capability model with mandatory business-unit scope (D-025), and the period-lock
   enforcement path (D-026) — all buildable and testable locally before any backend
   exists.

## Open questions for Shoyeb

**Q10 — Costs spanning two accounting months (non-blocking).** An electricity bill
covering 15 May – 14 June currently lands **entirely in June** (the month of
`accounting_period_end`). No proration is performed in V1. Confirm this is acceptable, or
state the split rule you want.

*Resolved:* Q1 → D-016 · Q2 → D-017 · Q3 → D-018 · Q4 → D-019 · Q5 → D-023 ·
Q6 → D-024 · Q7 → D-025 · Q8 → D-026 · Q9 → D-027 · Q11 (application identity) → D-029.

## Owner actions required

1. **Install the Visual Studio C++ ATL component** (unblocks the Windows build):
   - Open **Visual Studio Installer** (Start menu).
   - On **Visual Studio Build Tools 2026**, click **Modify**.
   - Go to the **Individual components** tab.
   - Search for `ATL` and tick **"C++ ATL for latest build tools (x86 & x64)"**.
   - Click **Modify** and let it install (a few minutes).
   - Tell me when it is done and I will build and verify Windows.
2. Answer Q10 when convenient. It affects month-boundary figures only.

No infrastructure is to be created yet. **You will never be asked to paste a password,
service-role key, database password, private key or signing password into chat.**

## Test totals

Unit **95** · Widget **8** · Integration **6 (Android, passing)** · Database 0 ·
Parity 0.
Host suite: **105 passing, 0 failing.** On-device: **6 passing on Android**, Windows
blocked.

## Build status

| Target | Status |
|---|---|
| Android (debug, dev flavour) | **Built and installed on an emulator** |
| Android (release APK / AAB) | Not attempted — Phase 9, needs the owner's keystore |
| Windows (debug) | **Blocked** — missing C++ ATL component |
| Windows (release + installer) | Not attempted — Phase 9 |

## Database migration status

Local Drift schema **v1**: `app_meta`, `sync_outbox`. Created and exercised on both the
Windows host and an Android device. No Postgres migrations exist yet;
`docs/DATABASE_SCHEMA.md` remains a proposal awaiting Phase 2.

## Last important decision

**D-030 — encryption via `package:sqlite3` build hooks with the SQLite3MultipleCiphers
build**, replacing the now end-of-life `sqlcipher_flutter_libs`. Encryption is asserted by
tests rather than assumed: if the plain SQLite build were ever silently substituted, the
suite fails instead of shipping a readable database.

## Master Spec version

**1.1**
