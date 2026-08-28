# Release Checklist

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**
Status: **Prepared in Phase 0; section H added at the end of Phase 2.** No release has
been produced.

Every box must be genuinely verified, not assumed. Anything unverified is reported as
*Not tested* — never as done.

---

## A. Code quality gate

- [ ] `dart format --set-exit-if-changed .` clean
- [ ] `flutter analyze` — zero errors, zero warnings
- [ ] No `TODO`/`FIXME` left on a financial code path
- [ ] No `double`/`num` anywhere in currency handling (grep-verified)
- [ ] No `print()`; structured logging only, no financial data in logs
- [ ] `dart run tool/check_no_client_secrets.dart --history --artefacts` clean — working
      tree, every committed blob, **and the built binaries**
- [ ] `dart run tool/check_config.dart` clean for the flavour being built
- [ ] Generated files (`build_runner`) regenerated and committed
- [ ] Dependency licence review; every package confirmed to support Android **and** Windows

## B. Tests

- [ ] Unit: Money arithmetic, Indian formatting (lakh/crore, negative, zero, rounding)
- [ ] Unit: period math — day, week, month, financial year, custom range, boundaries
- [ ] Unit: business-date derivation at 04:59 / 05:00 / 23:59 / 00:01 per unit cut-off
- [ ] Unit: tax extraction (inclusive and exclusive), rounded once, at the record
- [ ] Unit: accrual attribution — `pnl_date` vs `business_date` vs `payment_date`
- [ ] Unit: allocation split reconciles to the paisa (largest-remainder)
- [ ] Unit: P&L, including zero-revenue and negative-profit cases
- [ ] Unit: capability resolution — allow **and** deny, per business-unit scope
- [ ] Unit: period-lock and edit-window decisions
- [ ] Sync: duplicate delivery, timeout-after-send, kill mid-flight, 401 mid-batch,
      version conflict, **stale void rejected**, write into closed period rejected —
      each asserting exactly one financial record results and no stale intent applied
- [ ] Repository/data: CRUD, filtering, keyset pagination, transactional integrity
- [ ] Database: constraints, deferred allocation-sum trigger, hierarchy-consistency trigger
- [ ] Database: RLS allow **and** deny per role, including unit-scoped managers
- [ ] Migration audit: every `SECURITY DEFINER` function fixes `search_path`; the API
      surface invariant passes in both directions; no policy references the `app` schema
- [ ] Migration integrity: every migration applied to the target project exists as a
      committed file (D-056) — run the live suite's `drift` phase against that project
- [ ] Widget: forms, validation, error states, all five sync states
- [ ] Integration (spec §27): login · create expense · offline expense · sync expense ·
      create revenue · dashboard · report drill-down · export P&L · permission refusal
- [ ] **Parity suite green:** identical fixtures through local SQLite engine, Postgres
      engine, Excel and PDF produce **exactly equal integer paise** (spec §21.3)
- [ ] Parity fixtures include cut-off boundaries, odd-remainder splits, accrual ≠ payment
      dates, voided documents, zero-revenue periods, and a mid-period rate change
- [ ] Test totals recorded in `PROJECT_STATUS.md`

## C. Data and migrations

- [ ] Migrations apply cleanly to an empty database
- [ ] Migrations apply cleanly to a copy of the current production database
- [ ] Rollback path exists and is documented for each migration
- [ ] Local Drift schema version bumped; local migration tested from the previous release
- [ ] Seed data idempotent and re-runnable; contains no credentials
- [ ] Backups verified: a **restore** has actually been performed, not just configured

## D. Security

- [ ] No secret in the repository or in any build artefact
      (`git log -p` scanned; APK/exe inspected for keys)
- [ ] Only the publishable/anon key ships in clients; service-role key never leaves the server
- [ ] RLS enabled on every table; deny tests pass
- [ ] Storage buckets private; signed URLs scoped and expiring
- [ ] Local database encryption active on both platforms; key in OS secure storage
      (Android Keystore-backed; Windows **user-scope DPAPI**, verified per D-036 —
      re-verify after any `flutter_secure_storage` upgrade, because the package ships a
      second Credential Manager implementation that a version bump could switch to)
- [ ] Key never appears in code, config, git history, logs, diagnostics or crash reports
      — grep-verified and logger redaction tested
- [ ] Logout does not destroy unsynced outbox entries; erase-local-data refuses while
      pending entries exist
- [ ] Key-loss behaviour verified: clear message, reset-and-resync offered, no false
      reassurance about unsynced data
- [ ] Period-close enforcement verified server-side; no path reopens a period implicitly
- [ ] Non-Owner role grants rejected without an explicit business-unit scope
- [ ] Session expiry and re-authentication handled without data loss from the outbox
- [ ] Audit log append-only; no client grant to UPDATE or DELETE it
- [ ] Production, staging and development are fully separate projects
- [ ] Exports contain only data the exporting user is permitted to see

## E. Offline and sync validation ("torture tests", on real devices)

- [ ] Create expense with a receipt photo in aeroplane mode → save succeeds instantly
- [ ] Force-kill the app mid-sync → queue recovers, exactly one record on the server
- [ ] Network drops mid-batch → no duplicates, no lost entries
- [ ] Token expires while queued → re-auth banner, queue intact, then syncs
- [ ] Same expense edited on Android and Windows while offline → conflict surfaced,
      no silent overwrite
- [ ] Attachment upload fails repeatedly → transaction still syncs; attachment retries
- [ ] Android and Windows show identical figures after convergence
- [ ] Device clock set wrong → server timestamps still authoritative

## F. Functional acceptance (with the owner)

- [ ] P&L for a chosen historical period matches the owner's own figures
- [ ] Every dashboard total drills down to its source transactions
- [ ] Split electricity bill appears correctly in both business units and in consolidated
- [ ] Excel and PDF exports reviewed and approved by the owner
- [ ] Windows printing produces a correct, well-laid-out page
- [ ] Indian number formatting correct everywhere (₹12,36,420)

## G. Performance

- [ ] One-month P&L renders within 400 ms on the reference Android device
- [ ] Ledger with 100k+ rows scrolls smoothly; pagination verified
- [ ] Cold start under 3 s on the reference device
- [ ] Local database size measured and projected for three years

## H. Android release

- [ ] `applicationId` final; version name and code bumped
- [ ] Release keystore generated and stored **only** by the owner, backed up offline
      (losing it means no future update can be installed over the existing app)
- [ ] Signing configured via a git-ignored properties file — never committed
- [ ] `flutter build apk --release --flavor prod` succeeds
- [ ] `flutter build appbundle --release --flavor prod` succeeds (AAB readiness)
- [ ] Installed on a clean device from the signed APK and smoke-tested
- [ ] Upgrade from the previous version tested — local data survives
- [ ] Permissions justified and minimal; camera/storage rationale shown
- [ ] ProGuard/R8 rules verified; obfuscation does not break Drift or serialisation
- [ ] App icon, name and splash correct

## I-0. Windows runtime verification (every release, not only the first)

Host tests do not exercise the Windows runtime. The executable must actually run.

- [ ] `flutter build windows --debug` and `--release` both succeed
- [ ] The built `.exe` launches; process responds; window title correct
- [ ] No startup exception on stdout/stderr
- [ ] `flutter test integration_test/windows_shell_test.dart -d windows` green —
      rendering, pointer navigation, keyboard focus, and **no overflow at 1024x768,
      1280x720, 1536x864, 1920x1080 and a cramped 820x600**
- [ ] `flutter test integration_test/encrypted_storage_test.dart -d windows` green
- [ ] Window fits the work area on the smallest supported display, at 100% **and 125%**
      display scaling (measure with a DPI-aware tool — a non-aware one reports
      virtualised coordinates and will mislead)
- [ ] Application closes cleanly; process exits; no orphan holding the database file

## I. Windows release

- [ ] `flutter build windows --release` succeeds
- [ ] Product name, version, company and file description set in the executable metadata
- [ ] Installer built (MSIX or Inno Setup — decided in Phase 9)
- [ ] Installs and uninstalls cleanly on a machine without Flutter or Visual Studio
- [ ] Start Menu entry and icon correct
- [ ] Runs as a standard (non-administrator) user
- [ ] Upgrade over the previous version tested — local data survives
- [ ] Printing and file export verified on the target machine

## J. Release record

- [ ] `PROJECT_STATUS.md` updated: phase, verified items, known issues, test totals
- [ ] `DECISIONS.md` updated with any decision taken during the release
- [ ] Release notes written in plain language for the owner
- [ ] Artefacts archived with their version, build date and commit hash
- [ ] Known issues stated openly to the owner — nothing buried
- [ ] Rollback plan documented for both platforms

---

## K. Backend and identity gate (added end of Phase 2)

Everything here is verified **against the environment being released to**, not against
development. A staging or production release repeats every line.

### K.1 Environment

- [ ] `config/<flavour>.json` points at the correct project — never at development
- [ ] The configured key is a publishable/anon key. `AppConfig` refuses a secret key, a
      service-role JWT and a connection string at start-up; confirm the build starts
- [ ] No service-role key, database password, JWT signing secret or connection string
      exists on the build machine's project configuration
- [ ] Storage buckets private; signed URLs scoped and expiring

### K.2 Migrations

- [ ] Every migration in `supabase/migrations/` is applied, in order, with no manual step
- [ ] Every migration applied to the project exists as a committed file (D-056)
- [ ] The API surface invariant passes: nothing callable by `anon`, exactly the reviewed
      list callable by `authenticated`, and every reviewed function still callable
- [ ] No RLS policy references the `app` schema (D-045)
- [ ] No tax rule is seeded (D-043) — the owner supplies the first rule per revenue
      category, with its rate, treatment and effective date

### K.3 Identity

- [ ] Production accounts are created through the ordinary sign-up path and enrolled with
      `user_provision`. No profile is ever inserted behind the authorisation model
- [ ] Every non-Owner grant names a business unit (D-025), enforced by the database
- [ ] Exactly one Owner grant is unscoped, and it belongs to the owner
- [ ] No development identity exists in the target project
- [ ] No password is committed, in a fixture, in a document, in a screenshot, or in a
      distributable asset. Repeatable device acceptance uses a git-ignored
      `config/dev-identities.local.json`, which exists on developer machines only

### K.4 Session and authority behaviour, on the real build

Each verified in the installed application, not in a test harness:

- [ ] Sign in succeeds; a wrong password is refused in plain language with no SQLSTATE,
      no HTTP status and no provider error text
- [ ] Keyboard alone drives the login form on Windows: Tab, Shift-Tab, visible focus,
      Enter submits; the password is obscured until the user asks
- [ ] Real authority is fetched and the shell reflects it — a scoped user sees their
      property only, and administration is absent where the capability is absent
- [ ] Closing and relaunching the application restores the session without credentials
- [ ] Sign out works from the account control and leaves the outbox intact
- [ ] Signing in as a second user on the same installation shows nothing of the first
      user's data, and their queued work is preserved and still theirs (D-050, D-053)
- [ ] Offline: permitted cached data remains readable, marked *Using last verified
      access*; nothing is purged; a privileged mutation stays `Pending Sync`
- [ ] A user who has never verified on this installation, offline, gets no access at all
      and the message *"Unable to verify your access. Connect to the internet and try
      again."*
- [ ] Revoking a scope, then reconnecting: authority refreshes first, the server-owned
      cache for that property is purged, organisation-global data and the outbox survive,
      the queued mutation is refused and recorded as terminal `Rejected`, and the property
      disappears from navigation
- [ ] Deactivating an account expires its session at the next refresh, with no fallback to
      cached authority
- [ ] `Rejected` and `Conflict` read as visibly different states

### K.5 Two-client agreement

- [ ] A cosmetic rename on one platform reaches the other with the same id, the same
      immutable code, an incremented row version and no duplicate record
- [ ] An archive reaches the other client, disappears from new-use pickers, and leaves
      historical references intact
- [ ] A mutation submitted on a stale row version is refused as `Conflict`, not `Rejected`,
      and the canonical server state is preserved

### K.6 Leaving the environment as it was found

- [ ] Any fixture changed during acceptance is restored, and the restoration is verified
      by reading it back
- [ ] Any grant revoked during acceptance is re-granted
- [ ] Any account deactivated during acceptance is reactivated
- [ ] The project is not left in an unexplained modified state
