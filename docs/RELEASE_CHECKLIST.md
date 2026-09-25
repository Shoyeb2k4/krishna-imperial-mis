# Release Checklist

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
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
- [ ] Storage buckets private, and read through Storage own authenticated download under
      the parent document authority. **No signed-URL issuer exists** and none is required
      (D-151); an earlier wording here named one
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

## F. Functional acceptance (with the project lead)

- [ ] P&L for a chosen historical period matches the project lead's own figures
- [ ] Every dashboard total drills down to its source transactions
- [ ] Split electricity bill appears correctly in both business units and in consolidated
- [ ] Excel and PDF exports reviewed and approved by the project lead
- [ ] Windows printing produces a correct, well-laid-out page
- [ ] Indian number formatting correct everywhere (₹12,36,420)

## G. Performance

- [ ] One-month P&L renders within 400 ms on the reference Android device
- [ ] Ledger with 100k+ rows scrolls smoothly; pagination verified
- [ ] Cold start under 3 s on the reference device
- [ ] Local database size measured and projected for three years

## H. Android release

- [ ] `applicationId` final; version name and code bumped
- [ ] Release keystore generated and stored **only** by the project lead, backed up offline
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
- [ ] Release notes written in plain language for the project lead
- [ ] Artefacts archived with their version, build date and commit hash
- [ ] Known issues stated openly to the project lead — nothing buried
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
- [ ] Storage buckets private, and read through Storage own authenticated download under
      the parent document authority. **No signed-URL issuer exists** and none is required
      (D-151); an earlier wording here named one

### K.2 Migrations

- [ ] Every migration in `supabase/migrations/` is applied, in order, with no manual step
- [ ] Every migration applied to the project exists as a committed file (D-056)
- [ ] The API surface invariant passes: nothing callable by `anon`, exactly the reviewed
      list callable by `authenticated`, and every reviewed function still callable
- [ ] No RLS policy references the `app` schema (D-045)
- [ ] No tax rule is seeded (D-043) — the project lead supplies the first rule per revenue
      category, with its rate, treatment and effective date

### K.3 Identity

- [ ] Production accounts are created through the ordinary sign-up path and enrolled with
      `user_provision`. No profile is ever inserted behind the authorisation model
- [ ] Every non-Owner grant names a business unit (D-025), enforced by the database
- [ ] Exactly one Owner grant is unscoped, and it belongs to the project lead
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

## L. Financial write gate (added end of Phase 3)

Everything below is about money reconciling exactly and about one user never learning
another property's figures. Each line is checked against `krishna-mis-dev` with the real
signed application, not asserted from shared code.

### L.1 Reconciliation, to the paisa

- [ ] A simple expense: one line, one derived period contribution, contributions total
      equals the document total
- [ ] A shared bill: ₹58,000 as ₹25,000 + ₹33,000, exactly
- [ ] An odd amount split three ways reconciles with no paisa lost or invented
      (largest remainder)
- [ ] A cross-period split: ₹60,000 as ₹30,000 May + ₹30,000 June, and **not** also
      ₹60,000 against a document date
- [ ] Shared *and* cross-period at once reconciles on both dimensions and globally
- [ ] An unbalanced write is refused by the deferred constraint, not merely by the UI

### L.2 Scoped visibility — the covert channel stays closed

- [ ] `authenticated` holds no `SELECT` on `public.expenses` (the read path is
      `expense_document`)
- [ ] A unit-scoped user's projection carries `is_complete = false` and a **null** total
- [ ] The same bill synced to three devices: inspect the **raw SQLite** of each and
      confirm no unauthorised amount is present in any column
- [ ] A scoped user cannot download the attachment object directly from Storage
- [ ] The attachment bucket is private and no client role holds DELETE

### L.3 Authority on the write path

- [ ] A unit-scoped manager is refused `KM002`, naming the unit, for a line outside scope
- [ ] Holding both scopes without `expense.allocate_cross_unit` is refused `KM001`
- [ ] A period split without `expense.allocate_periods` is refused `KM001`
- [ ] An ordinary one-period expense needs **neither** of those capabilities

### L.4 Period locks and the edit window

- [ ] Open period: create succeeds
- [ ] Closed period: create, edit and void all refused `KM004`, and never as a conflict
- [ ] Reopen is audited, carries a mandatory reason, and only then does the correction work
- [ ] Edit window: business date D is editable on **D+7** and refused `KM021` on **D+8**
- [ ] `transaction.correct.beyond_window` permits an old correction while the period is open
- [ ] …and is still refused `KM004` when the period is closed — the lock is never bypassed

### L.5 Void

- [ ] Data Entry and Manager are refused, and are not offered the action
- [ ] Accountant and the Owner role succeed while the period is open
- [ ] A reason is mandatory and no default is offered
- [ ] `base_row_version` is required; a stale void is a `KM003` conflict
- [ ] A voided document is immutable, stays in the ledger marked VOIDED, and keeps its
      attachments
- [ ] Historical master usage is unchanged by the void; active usage decreases

### L.6 Offline and recovery

- [ ] An expense saves with no network and is queued in the same transaction
- [ ] Killing and restarting the app preserves both the expense and its queued intent
- [ ] Server-commits-then-response-lost yields **one** server record and one local record
- [ ] A local write failing after acceptance leaves the intent queued, not done
- [ ] A queued expense delivered after a permission change is refused and recorded as
      terminal `Rejected`, never `Conflict`, and is not retried forever
- [ ] Attachment upload failure never changes the expense's own state


### L.7 Expense correction through the client (D-072a)

The server's `expense_update` was proven long before anything could call it. These lines
are about the client path, which is where the concurrency semantics are actually exposed
to a person.

- [ ] A correction keeps the document's identity: same id, same `KI-EXP` number, and the
      row version moves
- [ ] `base_row_version` is captured when the draft opens and **cannot** be re-based by a
      background pull while somebody is typing
- [ ] A stale edit is presented as a conflict for a person to resolve — never merged, and
      never last-writer-wins
- [ ] An edit made offline queues, survives an app restart, and reconciles **once**
- [ ] A **scoped** share of a shared bill is read-only: no Edit control, the draft loader
      refuses it, and the server refuses a forged attempt regardless
- [ ] Editing lines and period contributions replaces them wholesale, so a document never
      holds lines that do not add up to it
- [ ] Void remains a distinct action with a mandatory reason — an edit is not a soft void

### L.8 Attachment upload (D-073)

- [ ] A bill uploads only **after** the server has accepted its expense, and the states in
      between say so (`waitingForExpense` → `pendingUpload`)
- [ ] The object lands at its deterministic path and is registered through
      `attachment_register`, which refuses a size or SHA-256 that disagrees with the object
- [ ] Redelivery produces **one** object and **one** metadata row
- [ ] A transient failure leaves the expense `Synced` and the bill `retryNeeded`, on the
      durable backoff clock, and an explicit retry works
- [ ] `rejected` is terminal, carries no `nextAttemptAt`, and is never retried automatically
- [ ] A crash mid-upload recovers at start-up rather than leaving `uploading` for ever
- [ ] A scoped manager is refused the object, the metadata row **and** the right to attach
- [ ] A revocation removes the bill's metadata and its staged bytes; a **void** keeps both
- [ ] Staging bytes are reclaimed after confirmation, and after the retention window
- [x] **Manual, once per platform:** the real OS picker returns a file to the entry form.
      **Android PASS · Windows PASS, 2026-08-31.** The automated suite injects at the point
      the picker returns and proves everything after it; it does not drive the picker, and
      must not be reported as if it did.

      **This line earned its place.** Its first run FAILED on both platforms and exposed
      that the production picker had never been implemented, after a full green automated
      attachment acceptance (D-077). Keep it manual, keep it per-release, and do not let a
      green suite argue you out of running it.

- [x] **Manual, once per platform, for a SALE:** the real OS picker returns a file to the
      revenue surface. **Android PASS · Windows PASS, 2026-09-06**, reported by the
      project lead. The observation is his: no harness opens an OS picker, which is the
      whole reason this line is manual.

      **Recorded with it:** `krishna-mis-dev` holds no artefact of the manual run. Every
      revenue attachment row and every registration in the append-only audit trail is
      accounted for by an automated suite, and the KI-REV sequence has no gap. That bears
      only on the save-and-sync leg, not on the picker, and the ordinary explanations are
      benign (a build with no backend configured, or a picker checked to the point the
      file appears on the form). It is noted so nobody later reads the automated
      `synthetic-receipt.jpg` rows as evidence of this line.

      Revenue attachments ship on the shared strip and the shared production source, so
      the *wiring* is asserted from the host — `attachment_source_wiring_test.dart` reads
      what production resolves, and the revenue entry form and sale detail panel are each
      rendered against that production source rather than an injected one, so a revenue
      surface cannot silently resolve a picker the expense surface does not.

      **That is not the same claim as this line.** The OS picker is a separate activity
      no harness opens, so a person still has to open one from a *sale* and see the file
      come back. The exact gate:

      * **Android** — Add Sale, choose the property and category, More details, Add file,
        the system Photo Picker opens, choose one small image, the app shows it Attached,
        Save, let it sync, then open the sale and see the evidence listed.
      * **Windows** — the compiled `krishna_mis.exe`, Transactions to Sales, open a
        recorded sale, Add file, the native Windows dialog opens, choose a file, the
        panel shows it Attached, and it is still there after the upload confirms.

      D-077 is the reason the wording is this careful: a full green automated attachment
      acceptance ran against a picker that did not exist. Do not report this line from a
      wiring assertion, and do not report it from the expense run.

## M. Revenue write gate

**Corrected 2026-09-07.** This section used to open *"nothing in this section is
implemented"*, and it was written deliberately ahead of the code so the gate would exist
before there was anything to describe. **Phase 4 is complete**: every item below is
implemented and was exercised in the Slice 13 acceptance on both platforms against
`krishna-mis-dev`.

It stays a **release** gate rather than becoming a record of what passed once — that is
what `PROJECT_STATUS.md` is for. The boxes are unticked because a checklist is run per
release, not per phase.

### M.1 Tax resolution

- [ ] A category with **no applicable rule** refuses the save, and the message names which
      condition could not be satisfied
- [ ] A **configured 0%** and a **configured `none`** both save, and are displayed as
      decisions — never as "no rule configured"
- [ ] Two rules that could both match the same facts on the same date are **refused at
      configuration time** by constraint
- [ ] An ambiguous resolution at entry time refuses the save; nothing is tiebroken
- [ ] A rule requiring a premises status, with none configured, refuses
- [ ] A component whose value band no rule covers refuses
- [ ] The same facts resolve identically on the client and on the server
- [ ] **Categories that share a treatment do not share a rule** (D-089): changing
      Restaurant's rule leaves Nandbhog's figures untouched, and vice versa

### M.2 Amount basis and arithmetic

- [ ] `inclusive_total`: the operator's figure is the customer total; tax is extracted and
      `net = gross − tax`
- [ ] `pre_tax`: the operator's figure is pre-tax; `gross = net + tax`
- [ ] The input field's **label follows the configured rule** and is never universally
      "Gross"
- [ ] The basis comes from the **configured rule**, never inferred from how a source
      invoice presents tax (D-088) — Restaurant's POS bill adds CGST + SGST to a subtotal
      and its management basis is nonetheless `inclusive_total`
- [ ] `entered_amount_minor` and `entered_basis` are stored beside the derived trio, so a
      historical figure can be explained without consulting the current rule table
- [ ] Rounding is half-up, once, at the component; aggregates sum stored paise
- [ ] `SUM(components) = header` is refused by the deferred trigger when violated
- [ ] No `double` appears anywhere in the revenue path

### M.3 Historical stability

- [ ] Changing a tax rule today does **not** move any previously recorded figure
- [ ] A new date-effective rule applies from its effective date and not before

### M.4 Room, Banquet, Nandbhog

- [ ] Room with one rule in force renders **one** amount field
- [ ] Room with two bands renders two, labelled with the **configured** boundary — no
      threshold constant appears in application code
- [ ] Banquet with no configured subtypes behaves as an ordinary category
- [ ] Banquet resolves to **exactly one** rule whose treatment is `none`: tax ₹0, net equal
      to the entered amount, and **no second 5% rule is active** (D-091)
- [ ] Nandbhog is a Crystal Canopy revenue category, not a business unit, and reports
      separately from Restaurant even while both carry the same treatment

### M.5 Offline

- [ ] With the required rules cached, a revenue entry saves offline and queues atomically
- [ ] With the required configuration **absent**, the local save refuses and **nothing is
      queued**
- [ ] The offline resolver is the same code as the online one

### M.6 Lifecycle, as expenses

- [ ] Edit within the window by capability; beyond it only with
      `transaction.correct.beyond_window`
- [ ] Closed period refuses create, edit and void, with its own reason
- [ ] Stale `base_row_version` is a Conflict, not an overwrite
- [ ] Void requires capability, a mandatory reason and `base_row_version`
- [ ] Redelivery of the same `mutation_id` yields one record
- [ ] `KI-REV-…` numbering is server-issued and does not share the expense sequence
- [ ] Attachments are optional and reuse the D-073a pipeline unchanged

## N. Owner Settlement preview (Phase 5 OA-3)

### N.1 Before any real settlement figure is shown to anybody

- [ ] **The production 50:50 start date has been supplied by the project lead** and set
      through `owner_settlement_start_set` by an Owner session — never guessed, never
      defaulted, never copied from the development fixture (D-212)
- [ ] The production ownership vector resolves to exactly `[5000, 5000]` from that date
      (D-204)
- [ ] `owner_settlement_settings` on **staging and production** holds no row until that date
      is set — the development project's `2026-05-01` is a test fixture (D-217) and must not
      travel

### N.2 Authority, on the real backend

- [ ] `owner_settlement.view` is held by the Owner role and by no other role
- [ ] As the Accountant, `owner_ledger_snapshot()` returns `settlement_authorised: false`
      with every owner dataset **null**, while ledger rows are still readable through RLS
- [ ] Accountant, Manager and Data Entry are refused `owner_settlement_start_set`
      (`KM001`/`KM002`), and read no `owner_settlement_settings` row
- [ ] A mid-month start date is refused `KM031` with a sentence; a stale base is `KM003`
- [ ] Every start-date change appears in `audit_logs` as `ownership_start_set` with before
      and after values

### N.3 The surface, on both platforms

- [ ] "Owner Settlement" appears in the Windows sidebar and under Android More → Owner
      Accounts **only** for a holder of `owner_settlement.view`
- [ ] It is a separate screen, not a tab in Reports or the P&L
- [ ] The **PREVIEW** banner is visible; no Finalize, Reopen, Lock or Approve control exists
- [ ] "Settlement start date not configured" shows while no date is set, with no figure
- [ ] Owner history and P&L each show their **own** "synchronised as of" time; no combined
      time is shown
- [ ] A refusal never renders ₹0; a real zero renders as ₹0 with "Nil — nothing due either
      way"
- [ ] A positive closing position reads "Due to owner", a negative one "Recoverable from
      owner" — the sign is never the only signal

### N.4 Revocation and a shared workstation

- [ ] Withdrawing `owner_settlement.view` from a user whose business-unit access is unchanged
      purges their canonical owner cache on the next confirmed refresh (D-214)
- [ ] A network failure purges nothing
- [ ] Signing out and signing in as another person leaves the first person's owner history
      unreachable

### N.5 Evidence

- [ ] `test/remote/owner_settlement_live_test.dart` green against the target environment,
      run **with `--concurrency=1`** alongside `owner_accounts_live_test.dart` — the two
      share one owner ledger (D-217)

## O. Android P&L surface (Phase 5 Slice 9)

### O.1 Emulator acceptance (Slice 9) — not a substitute for O.2

Run on the local `Pixel_8` emulator against `krishna-mis-dev`, one process launch per phase:

    flutter test integration_test/device_acceptance_test.dart -d emulator-5554 \
      --flavor dev --dart-define-from-file=config/dev.json \
      --dart-define-from-file=<scratch>/identities.defines.json \
      --dart-define=PHASE=<phase>

- [x] `android-pnl`: Reports opens straight to P&L; consolidated and Crystal Canopy equal
      `reporting_primitives` to the paisa; category lines reconcile; Custom chosen on the calendar;
      pull-to-refresh; void; offline cached read; older-FY download; fixtures voided
- [x] `android-pnl-scope`: one property's D2 authority (asserted by capability) reports it; the
      other property and consolidated are refused on the phone and withheld by the server
- [x] `android-pnl-switch`: Owner → scoped principal on one installation; no selection, figure
      or cache of the Owner's survives

### O.2 Physical Android device — **PASS, 17 September 2026** (D-230)

**Physical-device acceptance recorded 17 September 2026** — Galaxy A06 (SM-A066B, Android 16 / API 36), observer: the project lead. The automated phases were run by the suite; the manual lines are his observation and are recorded as his (D-077, D-156).

**Automated physical-device phases ran on the Galaxy A06 (SM-A066B, Android 16 / API 36)
on 2026-09-17 and PASS**: `android-pnl`, `android-pnl-scope`, `android-pnl-switch`. The lines
below are the *manual* half and are performed by a person; they are not discharged by that run.

On a real phone (the Galaxy A06 or another approved target), with a clean dev build:

- [x] Reports opens directly to Profit & Loss; no reports menu; Owner Settlement not reachable from it
- [x] The scope bottom sheet and the calendar picker open over the whole screen, and Android back
      closes each without changing the report
- [x] Custom offers no typed entry; the tapped days appear as the report's range
- [x] Pull-to-refresh updates the freshness line; with networking off, the last complete report stays
      readable and older history says a connection is required
- [x] With the system font enlarged, nothing overflows and the last line scrolls clear of the [ + ]
- [x] Recorded as **physical-device acceptance**, with the device named. The emulator run in O.1 is
      never reported as this

## P. Reporting breakdown and read-only drill-down (Phase 5 Slice 10)

### P.1 Real-app acceptance against `krishna-mis-dev`

One process launch per phase, with the same commands as §O.1:

- [x] `windows-pnl-drill` (Windows, `-d windows`):
  - Revenue → Restaurant → the sale opens read-only.
  - Expenses → department → section → Kirana → the shared bill opens, showing ₹25,000,
    Crystal Canopy's contribution.
  - The device's transaction, outbox and reporting-cache row counts are unchanged.
  - Offline, the rows stay and the detail says it is not downloaded, including for a
    document opened a moment earlier (D-239).
  - Fixtures are voided.
- [x] `android-pnl-drill` (emulator, `--flavor dev`): the same, with a pushed page per level
  and Android back walking up one level at a time.

### P.2 Physical Android device — **PASS, 17 September 2026**

**`android-pnl-drill` ran on the same physical phone on 2026-09-17 and PASSES.** The lines
below are the manual half.

- [x] A category line opens its documents; each level adds up exactly to the line it came from.
- [x] A document opens read-only, with no Edit, Void, Review latest or attachment control,
      even for a principal who could do those from the ledger.
- [x] With networking off, the rows stay, and re-opening a document says it is not downloaded.
- [x] Recorded as physical-device acceptance, with the device named.

## Q. Full reporting and Owner Accounts acceptance (Phase 5 Slice 11)

### Q.1 Real-app phases against `krishna-mis-dev`

One process launch per phase, run strictly one at a time, with the same commands as §O.1.
The revocation phase also needs `--dart-define=S11_HANDSHAKE=<scratch>/slice11_handshake.json`
and the host acting on each handshake step (D-243).

- [x] `windows-owner-settlement` / `android-owner-settlement` — **PASS**, Windows and the physical Galaxy A06 (2026-09-17): "Settlement start date not
      configured" on the clean baseline; a disposable start date through the audited RPC; the
      June preview equal to the independent oracle; offline still readable; a reader refused
- [x] `slice11-shared-device` (Windows, Android) — **PASS** on both, the phone physical (2026-09-17): the next person inherits nothing of the
      previous person's figures, scope, drill-down, document, freshness, coverage or settlement
- [x] `slice11-lifecycle` (Windows, Android) — **PASS** on both, the phone physical (2026-09-17): create → correct across periods → closed period →
      void → offline and reconnect → older financial year, every figure equal to the server
- [x] `slice11-revocation` (Windows, host-coordinated) — **PASS** (2026-09-17), five capabilities removed and each restored exactly: each P&L capability, `owner_settlement.view`
      and unscoped `reports.view` lost while open; exact restoration read back
- [x] After every phase: the disposable start date removed through the administrator path, and
      the development baseline compared and restored — done three times; settings rows **0**,
      role-capability hash and grant ids identical to the pre-run capture

### Q.2 Physical Android device — **manual checklist for the project lead**

Performed by a person on the Galaxy A06 (or another approved phone) with the clean dev build.
Record each line as **PASS / FAIL / NOT TESTED**. Automation never fills these in.

Issued to the project lead on 2026-09-17, with a clean dev build installed on the phone
(rebuilt with `config/dev.json` only, 0 of 6 identity passwords in it). **He performed all ten
on the Galaxy A06 and reported every one PASS on 17 September 2026.**

| # | Check | Result |
|---|---|---|
| 1 | Settings → Display → Font size set to the largest step: Reports → Profit & Loss has no clipped figures, and the last line scrolls clear of the [ + ] button | **PASS** |
| 2 | Open the property sheet, then press Android back: the sheet closes and the report is unchanged | **PASS** |
| 3 | Open Custom, then press Android back: the picker closes and the period is unchanged | **PASS** |
| 4 | Open a category, then a document, then press back twice: document → list → report, one step each | **PASS** |
| 5 | The date-range picker covers the screen, offers no typing, and the tapped days become the report's range | **PASS** |
| 6 | With a report open, force-stop the app (Settings → Apps → Krishna Imperial MIS → Force stop) | **PASS** |
| 7 | Reopen the app: still signed in as the same person, no previous person's figures shown | **PASS** |
| 8 | Turn on aeroplane mode, reopen Reports: the last complete report is readable, never ₹0 | **PASS** |
| 9 | Still offline: open a document from a category — it says detail needs a connection | **PASS** |
| 10 | Turn aeroplane mode off and pull to refresh: it refreshes and the "synchronised as of" time moves forward | **PASS** |

**All ten performed and reported PASS by the project lead on the Galaxy A06, 17 September 2026.**
Recorded as his observation: no automated run fills these in, and none did.

## R. Android Home dashboard (Phase 6 Slice 7)

### R.1 Host acceptance — **DONE**

Slice 7's acceptance is 28 widget tests through the **real** provider chain, rendered
inside the real mobile router and `MobileShell` at 360×740, 390×844, 430×932, landscape
and at a 1.6 system font scale (`test/features/dashboard_mobile_home_test.dart`). Every
paisa is synchronised into the canonical cache and read back by the engine; only the
remote transport and "now" are substituted.

- [x] The figures on screen are the engine's, for one property and consolidated.
- [x] Gross Sales and GST are secondary to Net Sales; a loss is labelled and signed.
- [x] Every movement is the domain comparison; a withheld percentage is not printed and
      its reason is stated; the margin moves in points and the three figures reconcile.
- [x] The Net Sales trend, property comparison and top expense categories are present;
      revenue mix, department spending and the profit bar chart are **absent** (D-260).
- [x] The scope sheet and the calendar picker open on the root navigator; a disagreeing
      consolidated period is disabled and refused.
- [x] No authority names no property and renders no money; not downloaded is not zero; a
      failed refresh keeps the figures and reports beside them.
- [x] *See full P&L* switches the shell to the Reports branch.
- [x] Nothing overflows at any tested size or font scale, and the last item clears the
      docked [ + ].

### R.2 Physical Android device — **PASS, 25 September 2026** (satisfied by §S.1 and §S.3)

*Written as PENDING at Slice 7, when no physical pass existed. The Phase 6 acceptance slice
has since supplied it (D-230). Each line below cites the evidence that discharged it; the
evidence itself lives in §S.*

- [x] Home opens to the dashboard on the real device, with the property, period and
      freshness readable at the device's own font scale — §S.3 items 1 and 6; `p6-android-dashboard` on the A06 (§S.1).
- [x] The scope sheet and the date picker open over the bottom bar and the [ + ], and
      Android back closes each without changing the selection — §S.3 items 3 and 4.
- [x] Pull-to-refresh runs the synchronisation and the "synchronised as of" time moves — §S.3 item 14.
- [x] Aeroplane mode: the last complete dashboard stays readable and never becomes ₹0 — §S.3 item 15.
- [x] *See full P&L* lands on the Reports tab showing the P&L — §S.3 item 12.
- [x] Recorded as physical-device acceptance, with the device named — Galaxy A06 (SM-A066B),
      Android 16 / API 36, USB serial `R9ZY50M3GVX`; manual lines reported by the project lead.

## S. Dashboard and analytics — full acceptance (Phase 6 Slice 10)

### S.1 Real-app phases against `krishna-mis-dev`

One process launch per phase, run one at a time:

```
flutter test integration_test/device_acceptance_test.dart -d <target> [--flavor dev] \
  --dart-define-from-file=config/dev.json \
  --dart-define-from-file=<scratch>/identities.defines.json \
  --dart-define=PHASE=<phase>
```

| Phase | Target | Result |
|---|---|---|
| `p6-windows-dashboard` | real `krishna_mis.exe` | **PASS** — rerun after D-286, 2:08 |
| `p6-windows-authority` | real `krishna_mis.exe` | **PASS**, host steps applied and restored |
| `p6-android-dashboard` | `Pixel_8` emulator | **PASS** (before D-286; host suites carry the layout evidence) |
| `p6-android-authority` | `Pixel_8` emulator | **PASS** on the cold-boot run; run 1 stalled with no known cause (D-287) |
| `p6-android-dashboard` | **Galaxy A06 (SM-A066B)**, USB serial `R9ZY50M3GVX`, Android 16 / API 36 | **PASS** 2026-09-25 — identity unchanged before and after (transport 2) |
| `p6-android-authority` | **Galaxy A06 (SM-A066B)**, USB serial `R9ZY50M3GVX`, Android 16 / API 36 | **PASS** 2026-09-25 — all 28 steps; identity unchanged before and after |

Before a physical run: shut the emulator down, and confirm that `adb devices -l` lists
**exactly one** target, the A06 **by its USB serial**, with USB debugging authorised.
**Wireless debugging must be off** on the phone and the adb server started with
`ADB_MDNS_AUTO_CONNECT=0` for the session — otherwise adb switches the phone to its Wi-Fi
identity (`adb-<serial>-…._adb-tls-connect._tcp`) mid-run and every `-s <serial>` command
fails (D-288). Watch the USB serial for 90 seconds before launching.

After both phases (2026-09-25): backend baseline identical to the pre-run capture (0 open
acceptance revenue or expenses — 6 and 14 created, all voided; 61 pre-existing open
expenses; 0 owner movements; 0 settings rows; 0 closed periods; 7 grant rows, 5 active,
grant-shape hash unchanged; 80 role capabilities, hash `c1b4870f…`; 4 roles; 4 live tax
rules; ledger 101). Clean dev APK rebuilt with `config/dev.json` only — 0 of 6 identity
passwords in any of its 558 entries; the secret scanner clean over tree, history and
artefacts — and installed on the phone, byte-identical (SHA-256 `6f334b6f…9b45`).

### S.2 Layout — money never shrinks (D-286)

- [x] `lib/` contains no `FittedBox`, `BoxFit.scaleDown`, `Transform.scale` or text-scale
      clamp (`test/core/money_shrink_guard_test.dart`).
- [x] Phone Home, the Android P&L and the drill-down pages at 320, 360 and 411 dp × 1.0,
      1.6 and 2.0 text: every amount is drawn at scale 1 and at the system text scale, is
      whole, and stays on screen. The last content clears the docked [ + ].
- [x] Windows Overview and the analysis sections at 1366×768, a narrower window and
      1920×1080: every amount is whole, and nothing scrolls sideways.
- [x] A figure wider than a full line of its own breaks only after a comma between digit
      groups, at full size (project-lead ruling on D-286).

### S.3 Physical Galaxy A06 — **manual checklist: 20/20 PASS (25 September 2026)**

**All 20 performed and reported PASS by the project lead** on the Galaxy A06 (SM-A066B,
Android 16 / API 36), 25 September 2026, with the clean dev build installed (SHA-256
`6f334b6f…9b45`). Recorded as his observation: no automated run fills these in, and none did.
Signed in as the development Owner unless a line says otherwise.

The checks ran against 14 temporary fixtures in `krishna-mis-dev`: 9 sales across all four
categories, dated 16 and 21–25 September plus 18 and 20 August as the comparator, and 5
expenses including one shared bill. Each note is marked `S10-MANUAL-FIXTURE`, and each was created
through the ordinary RPCs as the development Owner. All 14 were **voided** through
`revenue_void` / `expense_void` after the checks, and the voided rows remain as history
(D-006). Nothing was deleted.

1. [x] Home opens to the dashboard with property, period and "synchronised as of" readable.
2. [x] Today so far, Week to date, Month to date and Financial year to date each change the
       figures, and each label says the period is unfinished.
3. [x] Custom opens the calendar over the bottom bar and the [ + ]; Android back closes it
       and leaves the period unchanged.
4. [x] The scope sheet switches between one property and both properties; Android back
       closes it without changing the scope.
5. [x] Net Sales, Operating Expenses, Operating Profit/Loss and Margin each show a
       comparison, or a stated reason where there is none, and never ₹0 in place of a
       comparison.
6. [x] System font size set to the largest: no amount is shrunk, cut off or run off the
       screen. A figure too wide for its own line breaks only after a comma, like
       "₹1,66," then "383.00".
7. [x] At the largest font, the last item on Home clears the [ + ] button.
8. [x] Tapping a Net Sales trend point opens that bucket's revenue categories.
9. [x] Tapping a top expense category opens its documents; one document opens read-only,
       with no Edit or Void.
10. [x] Android back goes up one level at a time, and finally returns to Home as it was left.
11. [x] Tapping Operating Profit opens the Reports tab with the P&L set to the same dates
        as a Custom period.
12. [x] "See full P&L" opens the Reports tab.
13. [x] Property comparison shows both properties and the total, with no word such as
        "winner", "better" or "best".
14. [x] Pull-to-refresh runs a synchronisation and the "synchronised as of" time moves.
15. [x] Aeroplane mode: the dashboard stays readable, says it is offline, and no figure
        becomes ₹0.
16. [x] Aeroplane mode: opening a document says a connection is needed.
17. [x] With the connection back, a refresh succeeds and the offline notice clears.
18. [x] Sign out, then sign in as the Crystal Canopy manager: none of the Owner's figures,
        properties or open drill-down remain.
19. [x] A user with no report authority sees "Management analytics are not available for
        your access." and no property name, figure or chart.
20. [x] No Owner Accounts or settlement figure appears anywhere on Home.

**Both conditions are met:** the automated A06 phases pass (§S.1) and every line of S.3 is
reported PASS. Slice 10 is closed; Phase 6 closure is Slice 11.

## T. Phase 6 closure gates (Slice 11)

Run on the closure commit, one at a time, against `krishna-mis-dev` only (D-289). Each line
records what was actually run and its result.

- [x] `dart format --set-exit-if-changed lib test integration_test tool`: clean
- [x] `flutter analyze`: no issues
- [x] Full host suite
- [x] Live suites with `--concurrency=1`: reporting, parity, owner accounts, owner
      completeness audit, settlement, drill-down
- [x] Administrator cleanup of the disposable settlement start date
      (`supabase/tests/owner_settlement_dev_fixture_cleanup.sql`) → 0 settings rows
- [x] Android dashboard performance re-measured on the **current** `DashboardEngine`
      (`integration_test/dashboard_performance_test.dart -d emulator-5554 --flavor dev`),
      compared with the D-266 envelope
- [x] Windows release build with `config/dev.json` only
- [x] Android dev APK with `config/dev.json` only
- [x] Acceptance or debug intermediates carrying identity material removed before the
      artefact scan
- [x] Secret scan over the working tree, git history and rebuilt artefacts
      (`dart run tool/check_no_client_secrets.dart --history --artefacts`)
- [x] Backend baseline:
  - 0 open revenue;
  - 61 open expenses, all pre-existing;
  - 0 owner movements, 0 settings rows, 0 closed periods;
  - 7 grants, 5 active; 4 roles; 80 role capabilities;
  - 4 live tax rules;
  - storage rows and objects equal, with 0 stranded;
  - dead helper absent;
  - ledger 101
- [x] Migration and schema provenance: Drift v21; ledger 101; no Phase 6 change under
      `supabase/` or `lib/data/local/`
- [x] Clean working tree

The results, with their numbers, are recorded in `PROJECT_STATUS.md` under *PHASE 6 —
DASHBOARD & ANALYTICS: COMPLETE AND CLOSED* and in D-289.
