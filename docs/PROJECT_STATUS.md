# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-08-30** (third checkpoint — the expense edit surface)

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 2 — Masters & Permissions: COMPLETE**, plus one acceptance addendum accepted
afterwards (D-058, D-059) that closed the single gap the completion report recorded as
*Not tested*: the Windows offline transport path. The Phase 2 commit `1ba1e3a` is not
rewritten; the addendum is its own commit.

Every gate passed, including the ones that can only be passed by running the real signed
application: the Android package on a device, and the compiled Windows executable, both
against the real `krishna-mis-dev` project, with the real development identities.

**Phase 3 — Expense Engine: in progress. NOT complete. The expense edit surface is now
built and proven on both clients (D-072, D-072a); a second gap of the same shape has been
found in attachment upload (D-073) and needs the project lead's decision.** Slices 1–7 are approved and
committed (`81ef239`, `03e8b93`); slices 8–13 — the Android entry surface, the Windows
ledger and detail, edit/void, cross-business and cross-period allocation, and the audit
presentation — are built and committed (`3871b9f`) and covered by host tests.

**Device acceptance is under way and is partly done.** The core lifecycle is proven on both
real clients against `krishna-mis-dev`: routine entry, the full offline round trip, the
shared-bill scoped projection, and the refusal set (closed period, stale-version conflict,
who may void). Three defects were found and fixed, one of them a server-side correctness
bug in the edit window that no host test could have caught (D-067), one a crash on sign-out
(D-068), and one in the secret scanner itself (D-069).

**What remains before Phase 3 can be called complete** is listed under *Acceptance still
outstanding* below. It is deliberately not glossed: several requested surfaces have no
acceptance phase written yet, and a phase that has not run is not a phase that passed.

Six decisions were recorded during it, three of them corrections the project lead required
or the work exposed: period contributions as the only reporting source (D-060), cross-unit
allocation as its own capability (D-061), the local read model as a deliberate sibling of
the server schema rather than a copy (D-062), attachments as complete-document-only
(D-063), historical usage surviving a void (D-064), and the edit window's exact boundary
(D-065). D-066 records how development acceptance events are recognised without weakening
audit integrity.

Phase 0 complete and committed (`3a4502f`). Phase 1 complete. Phase 2 backend integration
checkpointed at `58526c0`, completed at `1ba1e3a`, and closed by the acceptance addendum
at `7d19f15`.

## Completed

**Phase 0 — Discovery & Architecture.** Governance documents, 15 decisions (D-001 …
D-015), the project lead's decisions (D-016 … D-019, D-023 … D-027) and three architectural
corrections (D-020 … D-022). Master spec bumped to v1.1 (D-028).

**Phase 1 — Foundation.** Flutter project for Android and Windows only; three environment
flavours with typed `AppConfig`; layered module architecture; `Money` in integer paise with
Indian formatting; `BusinessDate` with per-unit timezone and cut-off; encrypted local
database proven on both platforms; the sync foundation with a durable outbox, idempotency
and optimistic concurrency; the design-token system; and separate Android and Windows
navigation shells over one codebase.

**Phase 2 — Masters & Permissions.**

*Local half (built earlier in Phase 2):* the capability model and central `Authorizer`;
business-unit scoping; period locks; the edit window; hierarchy integrity; archive
semantics; historical-integrity labels; local schema with real foreign keys; the master,
vendor and tax repositories; the idempotent seed; and the Masters, Vendors and Tax
configuration UI on both platforms, built around the rename distinction in D-038.

*Backend half (this checkpoint):*
- **Postgres schema and integrity.** Identity, masters, the composite foreign-key ladder
  that makes an impossible hierarchy structurally unavailable (D-040), roles and scoped
  grants, period control keyed by `period_key` (D-042), date-effective tax rules, audit and
  the O(1) usage counter (D-041).
- **Server-authoritative authorisation.** RLS on every table; twenty-four reviewed
  `SECURITY DEFINER` RPCs and nothing else callable; nothing at all callable by `anon`
  (D-044); policies that call a published helper rather than the internal schema (D-045);
  permission decided before existence is revealed (D-046); user provisioning as a
  first-class administrative action (D-047, D-055).
- **Client integration.** Typed remote gateways returning `RemoteOk` / `RemoteRefused` /
  `RemoteUnreachable`, so no SQLSTATE can reach a user; `ReferenceSync`; `ScopeCachePurge`
  that can only run on positively confirmed authority (D-048); vendors as
  organisation-global masters with a derived per-user effective default (D-049); an
  actor-owned outbox (D-050); and the session state machine with fail-closed, cached,
  deactivated and user-switch semantics (D-051).
- **No tax rate is seeded and none is assumed** (D-043). Both applications show the
  "no rule configured" state explicitly.

*Corrections forced by the device acceptance (D-052 … D-056)* — see **Defects found** below.

## Verified

Labels used exactly as defined: **Implemented / Tested / Partially tested / Not tested /
Blocked.**

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean (140 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **651 tests, all passing** |
| Secret scan — tree, git history, built binaries | **Tested** | clean — tree, history and rebuilt distributables; the scan now proves its own controls every run (D-069) |
| Migration audit (search_path, API surface, policy boundary) | **Tested** | 14 host tests |
| Backend schema parity (migrations vs the claims made about them) | **Tested** | 18 host tests |
| Live backend suite against `krishna-mis-dev` | **Tested** | **19 tests** across 7 phases |
| Live expense suite against `krishna-mis-dev` | **Tested** | **16 tests**: reconciliation, scoped raw-cache security, period locks, the 7-day boundary, usage semantics |
| Repository ↔ server migration integrity (D-056) | **Tested** | live `drift` phase |
| Android device acceptance, real APK, real backend | **Tested** | **19 tests** across 10 phases |
| Windows acceptance, real `krishna_mis.exe`, real backend | **Tested** | **18 tests** across 11 phases |
| Two-client propagation, Android ⇄ Windows simultaneously | **Tested** | rename, archive, stale-version conflict |
| Windows shell: render, pointer, keyboard focus, overflow | **Tested** | 15 tests inside the real `.exe` |
| Local database encryption + platform key handling | **Tested** | 8 on Android, 8 on Windows |
| Login UX: keyboard, focus, Enter, obscured password, refusal wording | **Tested** | 3 tests on each platform |
| Tax "no rule configured" on both platforms | **Tested** | the `owner` acceptance phase, both platforms |
| Android debug build (dev flavour) | **Tested** | `app-dev-debug.apk` built, installed, driven |
| Windows debug build | **Tested** | `krishna_mis.exe` built, launched, driven |
| Windows offline/cached-authority behaviour | **Tested** | Phase 2 addendum — 14-point offline round trip inside the real `.exe` (D-058) |
| Android offline behaviour via the same injected transport | **Tested** | the same phase, on the real APK |
| Android release APK / AAB, Windows installer | **Not tested** | Phase 9, needs the project lead's keystore |
| Expense domain, schema, RLS and RPC boundary | **Tested** | 53 domain tests; every rule proven against the real server |
| Local expense read model and atomic offline create | **Tested** | 19 repository tests including rollback at each write boundary |
| Expense sync, idempotency and response-loss recovery | **Tested** | 10 tests; one server record and one local record in every variant |
| Attachment staging, upload, hash verification and retry | **Tested** | 18 tests |
| Android and Windows expense surfaces | **Tested** | 37 draft-model tests + 17 widget tests |
| Reporting engines and parity suite | **Not implemented** | Phase 5, by design |
| Revenue tables and entry | **Not implemented** | Phase 4, by design |
| Android expense acceptance — routine entry, offline round trip, shared projection, refusals | **Tested** | 4 phases on the real dev APK against `krishna-mis-dev` |
| Windows expense acceptance — the same four phases | **Tested** | 4 phases inside the real `krishna_mis.exe` |
| Edit window under the property's business date (D-067) | **Tested** | migration 0033 asserts 04:59 / 05:00 / 05:15 / 23:59 / 00:01; live suite re-run green |
| Device timezone cannot influence a business date | **Tested** | `business_date_test.dart`, pinned to the same instant the server asserts |
| Secret scan — tree, history, **rebuilt distributable** APK + Windows Release | **Tested** | clean; scanner self-test proves its own controls, verified by breaking it |
| Android cross-period entry through the UI | **Tested** | `cross-period`: ₹60,000 → May ₹30,000 / June ₹30,000, plus an odd-paise split reconciling exactly |
| Attachments on either platform, end to end | **Not tested** | no acceptance phase written; host coverage only (18 tests) |
| Windows ledger: filters, paging, detail projection | **Not tested** | no acceptance phase written; widget coverage only |
| Two-device Android ⇄ Windows expense propagation | **Not tested** | create/refresh/void legs schedulable; edit and conflict legs blocked by D-072 |
| Expense **edit** through the UI | **Tested** | `expense-edit` on both real clients: identity kept, version advanced, D+7/D+8, stale → Conflict (D-072a) |
| Attachment **upload** end to end | **Blocked** | the application never uploads: no object store, no worker, no scheduling (D-073) |
| D-068 financial cache retention | **Tested** | 3 tests on the real APK and 3 inside the real `.exe` |
| Client and server agree on a business date at one instant | **Tested** | 10 host tests reading migration 0033's own assertion table |
| Payment-date accrual through the application | **Tested** | `payment-accrual`: ₹80,000 to June, ₹0 to July, paid 5 July |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | 651 | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | all passing |
| Live expense suite against `krishna-mis-dev` (opt-in) | 16 | all passing |
| Android Phase 2 device acceptance (real APK) | 19 | all passing |
| Windows Phase 2 acceptance (real executable) | 18 | all passing |
| Windows shell (real executable) | 15 | all passing |
| Encryption on device — Android 8, Windows 8 | 16 | all passing |
| **Android Phase 3 expense acceptance (real APK)** | **4** | **all passing** |
| **Windows Phase 3 expense acceptance (real executable)** | **4** | **all passing** |
| **D-068 retention, Android (`d068-switch`, `d068-revoke`)** | **3** | **all passing** |
| **D-068 retention, Windows (`d068-switch`, `d068-revoke`)** | **3** | **all passing** |
| **Android cross-period (`cross-period`)** | **2** | **all passing** |
| **Android payment-date accrual (`payment-accrual`)** | **1** | **all passing** |
| **Acceptance fixture reversal (`expense-cleanup`, both platforms)** | **2** | **all passing** |
| **Expense edit (`expense-edit`, both platforms)** | **6** | **all passing** |
| **Scoped-share edit security (`expense-edit-shared`, both)** | **2** | **all passing** |
| **Offline edit (`expense-edit-offline`, both platforms)** | **2** | **all passing** |
| **Edit refusals (`expense-edit-refused`, both platforms)** | **4** | **all passing** |
| **Windows ledger (`windows-ledger`)** | **1** | **all passing** |
| **Attachment staging (`attachment-staging`, both platforms)** | **2** | **all passing** |
| **Total** | **790** | **0 failing, 0 skipped-and-counted** |

The Phase 3 acceptance figures are four phases per platform — `expense-simple`,
`expense-offline`, `expense-shared`, `expense-refusals` — each one process launch against
the real backend. **Skipped phases are not counted**, and the surfaces listed as *Not
tested* above contribute nothing to this total, because they have no phase to run.

**Two suites in this table were not re-run at this checkpoint** and are carried forward
from the previous one: the live backend suite (19) and the live expense suite (16). They
were green when last run and nothing in this change touches the RPCs they exercise, but
"carried forward" is not "re-verified", and they are named here so the total cannot be
read as a claim that everything in it ran today.

Skipped phases are *not* counted. Each acceptance phase reports its own tests as passing
and every other phase as skipped; only the phase that ran contributes to the total above.

## Defects found and fixed during the Phase 2 acceptance

Every one of these passed review, `flutter analyze`, and a green host suite. Each was found
only by running the real application.

1. **The sign-in screen painted a framework error where the password field should be.**
   The session gate is installed through `MaterialApp.builder`, which sits above the
   router's Navigator, so no `Overlay` was in scope — and the show/hide-password button
   carries a tooltip. The first launch of the real Android build showed a red error box.
   Fixed with an `Overlay` around the gate's own screens; covered by tests that assemble
   the app exactly as `main()` does and fail without the fix.
2. **There was no way to sign out.** `signOut()` was reachable only from the "access not
   verified" screen. Fixed with `AccountControl` in both shells (D-054).
3. **Signing out left the previous user's downloaded hierarchy in place.** The isolation
   check compares the cached authority's owner — and sign-out had already erased it, so it
   found nothing to compare. The Owner signed out, a Crystal Canopy-only Manager signed in,
   and Hotel Krishna Imperial was still there. Fixed by purging at sign-out (D-053).
4. **The outbox never recorded who queued anything.** `actor_user_id` existed from the
   first migration and nothing wrote it, so D-050 was unenforceable. Now written, and
   `dueEntries` filters by the signed-in actor.
5. **The shipped seed handed every installation both properties.** A scoped Manager on a
   clean install could browse the other property's hierarchy. The seed now runs only with
   no backend configured (D-052).
6. **The masters panel did not refresh after a sync or a purge**, and its empty state named
   a property the user might have no scope for. Both fixed.
7. **A migration existed on the server and not in the repository.** `my_authority()` — the
   call the whole authorisation model rests on — had never been committed. Recovered, and
   the live suite now asserts every exposed RPC is created by a committed file (D-056).
8. **`user_deactivate` had no counterpart**, making suspension a one-way door through the
   API. `user_reactivate` added (D-055).
9. **A Windows integration test used two different ids for one queued mutation**, so the
   erase-refusal test failed for a reason that looked like a lifecycle defect. Fixed.
10. **The secret scanner reported false positives on compiled binaries** and, once
    corrected, found that acceptance-test builds bake the development passwords into
    `kernel_blob.bin`. Those artefacts must never be distributed; the scanner now proves
    the distributable build is clean and the check has a positive control.

## Defects found and fixed during the Phase 3 acceptance

Each passed review, `flutter analyze` and a green host suite beforehand. Each was found
only by running the real application, or by asking what a committed rule actually evaluated
to. Full reasoning in `DECISIONS.md` D-067 … D-069.

1. **The edit window was measured against the server's calendar date, not the property's.**
   `expense_update` used Postgres `current_date`; the session timezone is UTC, the
   properties are `Asia/Kolkata` with an 05:00 cut-off, so for **thirty minutes every day**
   an entry that was D+8 old was counted as D+7 and accepted for edit. Narrow only because
   the +05:30 offset and the 05:00 cut-off happen to cancel — a midnight cut-off is wrong
   for five and a half hours a day. Fixed in migration 0033 (D-067).
2. **The migration was refused by its own assertion on first application** — Postgres had
   granted `PUBLIC EXECUTE` on both new helpers, because `ALTER DEFAULT PRIVILEGES` covers
   only objects created by the role that ran it. The revoke is now explicit and sits beside
   the functions it protects. The invariant working exactly as D-044 intended.
3. **Signing out threw a foreign-key error on any device that had synced an expense.**
   `expense_allocations.business_unit_id` was a real FK with `ON DELETE RESTRICT` while the
   column below it was deliberately soft, and the scope purge deletes every unit at
   sign-out. Local schema v8 makes it a soft pointer (D-068).
4. **The cache-classification guard had never been evaluated.** It iterated the classified
   list and asserted each entry was in the classified list. Phase 3 added four expense
   tables, none was classified, and the suite went on passing. It now compares against
   `AppDatabase.allTables` in both directions (D-068).
5. **The secret scanner reported a database password inside the Windows Release binary.**
   A 297-character false positive assembled from adjacent AOT string-table symbols. The
   pattern gained a verifier — and, because every verifier narrows the scan, the tool now
   proves its own controls on every run (D-069).
6. **An acceptance assertion raced the shipped sync worker.** `expense-offline` asserted
   `transientFailures == 1`, which claims *that particular call* did the work; `pushOnce`
   returns an empty report both when nothing is due and when a cycle is already running.
   Now asserts the durable consequence — nothing applied, the intent still queued with a
   recorded attempt, no number invented locally.

## Acceptance still outstanding

**A phase that has not run is not a phase that passed**, and one item below cannot run at
all because the application does not perform the operation it would exercise.

### Closed since the last checkpoint

| Surface | Status | Evidence |
|---|---|---|
| **Expense edit through the UI** (D-072) | **Tested** | `expense-edit`, 3 tests, Android **and** Windows |
| Edit of a scoped shared bill — refused | **Tested** | `expense-edit-shared`, both platforms, UI **and** server |
| Edit offline, restart, reconcile once | **Tested** | `expense-edit-offline`, both platforms |
| Closed period and withdrawn permission | **Tested** | `expense-edit-refused`, 2 tests, both platforms |
| D+7 / D+8 through a real client | **Tested** | inside `expense-edit`, with an identity that lacks the beyond-window capability |
| Stale edit → `KM003` → Conflict, server value stands | **Tested** | inside `expense-edit`, both platforms |
| Windows ledger: filters, paging, selection, scoped caption | **Tested** | `windows-ledger`, 1 test in the real `.exe` |
| Attachment staging to the picker boundary | **Tested** | `attachment-staging`, both platforms |
| D-070 physical purge across every SQLite surface | **Tested** | 3 host tests over `delete` **and** `wal`, with a positive control |

### Still outstanding

1. **Attachment upload — BLOCKED, the application never uploads (D-073).** No
   `AttachmentObjectStore` implementation exists outside the tests, `AttachmentUploadWorker`
   is never constructed, and nothing schedules an upload. Staging, hashing and the server's
   Storage policy are all proven; the upload between them is not performed. Successful
   upload, hash confirmation, transient-failure retry and reconnect cannot be tested until
   it is built. **Needs the project lead's decision.**
2. **Manual picker smoke test, one per platform** — *Not done, and needs a person.* The
   Android photo picker and the Windows file dialog are separate activities and OS dialogs;
   the Flutter harness cannot drive them. `attachment-staging` injects a synthetic file at
   exactly the point the picker returns one and proves everything after it. Confirming that
   the picker itself opens, returns, and hands over a file is a human action.
3. **Two-device propagation**, Android ⇄ Windows, for expenses — *Not tested.* Create,
   refresh, edit, conflict and void legs are now all schedulable, because the edit surface
   exists.
4. **Ledger filters the UI does not offer** — the query layer supports date range,
   department, section, category and vendor; the filter bar exposes search, business unit,
   unpaid-only, needs-attention and include-voided. `windows-ledger` covers what exists.
   Whether the rest belong in V1 is a product question, not a test gap.
5. **Final distributable rebuild and binary secret scan** — *Not done this checkpoint.*
   Tree and history scan clean with the scanner's own controls passing.

## Known issues

1. **`flutter_secure_storage` pinned to 9.2.4.** 11.x requires `compileSdk 37`; this
   toolchain has Android SDK 36 (D-031). Revisit when the SDK moves.
2. **`riverpod_lint` / `custom_lint` deferred** — analyzer conflict with `drift_dev`
   (D-032). Revisit at Phase 3.
3. **The Windows Overview placeholder names both properties in its description copy.** A
   scoped Manager therefore sees the words "Hotel Krishna Imperial" on a screen that holds
   none of that property's data. Not a data leak — business unit names are not secret — but
   it is a small scope-hygiene wrinkle, and it briefly confused an acceptance assertion.
   Worth revisiting when the Overview becomes a real dashboard in Phase 6.
4. **Windows local-key protection relies on user-scoped DPAPI**, not hardware (D-036).
   Accepted for V1, mitigated as recorded.

## Blockers

**None.** The backend is provisioned, the migrations are applied and committed, and both
platforms run against it.

## Deferred (by design)

- Approval workflow — modelled in the schema, disabled in V1 (spec §26).
- Partial payments / payables ageing (spec §5.4).
- Input tax credit and any statutory GST support (spec §6.1).
- Snapshot-based sync pull cursor (`ARCHITECTURE.md` §5.2).
- Historical Excel/CSV import — separate controlled workflow (spec §32).
- Bundled licensed fonts — the type scale is fixed; the family is a one-line swap.
- The period-close console. Enforcement is built into the write path; the console is a
  later phase.

## Next exact task

**Settle D-073**, the way D-072 was settled. If attachment upload is a Phase 3 slice it is
a real one — a Supabase Storage implementation of `AttachmentObjectStore`, a place to
schedule it on the outbox's own backoff clock, the D-063 predicate held on the read side,
and `expense_attachments` rows synced back. If it is deferred, this document and the master
spec's §15 must say so, and the interface must stop implying a bill has been filed
anywhere but this device.

Then:

1. Two-device `propagate-expense` for create, refresh, edit, conflict and void.
2. The two manual picker smoke tests — one on Android, one on Windows.
3. Rebuild clean distributables and scan the binaries.
4. Re-run the whole gate set, including the live backend and live expense suites, and
   close the phase.

## Open questions for the project lead

1. **Does a revoked scope take that property's cached expense history with it?**
   **Answered 2026-08-30 — yes.** D-070, implemented and proven on both platforms.

2. **Should the expense edit surface be built, or descoped?**
   **Answered 2026-08-30 — build it.** D-072a records the rules it was built to. Proven
   on both real clients.

3. **Is attachment upload a Phase 3 slice, or is V1 shipping with bills staged locally?
   (D-073.)** New, and it blocks Phase 3 closure either way: if it is to be built, Phase 3
   is not finished; if it is deferred, the documents and the interface have to stop
   implying otherwise.

## Project lead actions required

1. **Decide D-073 — build attachment upload, or defer it explicitly.** The same shape as
   D-072, and it blocks closure the same way. Staging and the server's Storage policy are
   both proven; nothing in the application carries a bill between them.
2. **Two manual picker smoke tests, one per platform.** The harness cannot drive an OS
   file dialog or the Android photo picker, and calling an injected boundary proof that it
   can would be false. Everything after the picker returns is proven automatically.
2. **Supply the first tax rule per revenue category** — Restaurant, Nandbhog, Room,
   Banquet — when the real treatment has been verified (D-043). Both applications
   currently show "No rule configured", which is correct and honest until then. This does
   not block Phase 3, but **Phase 4 revenue entry cannot be completed without it.**
3. **Optional decision:** whether archiving should also offer a *confirmed* cascade for a
   whole subtree (D-039).

No production credentials are ever requested. **You will never be asked to paste a
password, service-role key, database password, private key or signing password into chat.**

## Build status

| Target | Status |
|---|---|
| Android (debug, dev flavour) | **Built, installed, and driven on an emulator against the real backend** |
| Android (release APK / AAB) | Not attempted — Phase 9, needs the project lead's keystore |
| Windows (debug) | **Built, launched, and driven against the real backend** |
| Windows (release) | **Built** — `krishna_mis.exe`, scanned clean |
| Windows installer | Not attempted — Phase 9 |

**Acceptance builds are not distributable.** Driving the acceptance suite compiles the
development identity passwords into `kernel_blob.bin`; the scanner proves it, and proved it
again this phase. The artefacts that survive a run are rebuilt without the identity defines
and re-scanned before anything is called distributable.

## Database migration status

**Local Drift schema v9.** v1 `app_meta` and `sync_outbox`; v2 masters and period locks;
v3–v4 the Phase 2 master refinements; v5 makes `vendors.default_business_unit_id` and
`default_category_id` soft pointers rather than foreign keys, because a per-user cache
legitimately holds a vendor whose usual property is one this user cannot see (D-049); v6
adds `sync_outbox.actor_user_id` (D-050); v7 adds the four expense tables; **v8 makes
`expense_allocations.business_unit_id` a soft pointer** for the same reason v5 existed —
the scope purge legitimately removes a unit while synced history stays, and the foreign key
made sign-out throw (D-068); **v9 adds `expenses.scope_revoked_at`**, because a confirmed
revocation now purges synced financial cache (D-070) and the one thing that must survive —
a document still carrying the actor's own unsent intent — needs somewhere to say it is
retained for that reason and is not browsable financial data. The local database now also
sets `PRAGMA secure_delete = ON`, so a purge does not leave the revoked property's figures
legible in freed pages.

**Postgres: 32 migrations, all applied to `krishna-mis-dev` and all committed.** 0033
measures the edit window under the property's business date instead of the database
session's calendar date (D-067). The live suite asserts the repository and the server agree
(D-056).

## Last important decision

**D-070 — a confirmed revocation now takes the revoked property's figures with it.** The
open question D-068 left for the project lead is answered, and answered the other way:
synced financial data for a revoked unit leaves the browsable local cache at the authority
refresh, not at the next sign-out. What survives is narrower and sharper — the actor's own
unsent, rejected or conflicted intent, retained whole, stamped, and excluded from every
canonical financial read, because it exists nowhere else.

Two things fell out of implementing it. A partially revoked shared bill has to be
*downgraded*, not merely trimmed: a complete header beside one surviving line publishes the
share that was just revoked. And the purge was, as first written, weaker than the
projection it protects — SQLite left the deleted figures legible in freed pages until
`PRAGMA secure_delete` was turned on, which a byte-level test found and a deliberate
un-fix confirmed.

## Master Spec version

**1.1**
