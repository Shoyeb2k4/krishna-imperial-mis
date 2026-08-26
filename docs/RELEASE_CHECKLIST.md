# Release Checklist

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**
Status: **Prepared in Phase 0.** No release has been produced.

Every box must be genuinely verified, not assumed. Anything unverified is reported as
*Not tested* — never as done.

---

## A. Code quality gate

- [ ] `dart format --set-exit-if-changed .` clean
- [ ] `flutter analyze` — zero errors, zero warnings
- [ ] No `TODO`/`FIXME` left on a financial code path
- [ ] No `double`/`num` anywhere in currency handling (grep-verified)
- [ ] No `print()`; structured logging only, no financial data in logs
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
      (Android Keystore-backed; Windows DPAPI-backed)
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
