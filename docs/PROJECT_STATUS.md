# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-08-30**

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

**Phase 3 — Expense Engine: in progress. NOT complete.** Slices 1–7 are approved and
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
| Host test suite | **Tested** | **578 tests, all passing** |
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
| Android cross-period entry through the UI | **Not tested** | no acceptance phase written |
| Attachments on either platform, end to end | **Not tested** | no acceptance phase written; host coverage only (18 tests) |
| Windows ledger: filters, paging, detail projection | **Not tested** | no acceptance phase written; widget coverage only |
| Two-device Android ⇄ Windows expense propagation | **Not tested** | no acceptance phase written |
| Payment-date accrual through the application | **Not tested** | domain rule covered; no client-path acceptance |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | 578 | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | all passing |
| Live expense suite against `krishna-mis-dev` (opt-in) | 16 | all passing |
| Android Phase 2 device acceptance (real APK) | 19 | all passing |
| Windows Phase 2 acceptance (real executable) | 18 | all passing |
| Windows shell (real executable) | 15 | all passing |
| Encryption on device — Android 8, Windows 8 | 16 | all passing |
| **Android Phase 3 expense acceptance (real APK)** | **4** | **all passing** |
| **Windows Phase 3 expense acceptance (real executable)** | **4** | **all passing** |
| **Total** | **689** | **0 failing, 0 skipped-and-counted** |

The Phase 3 acceptance figures are four phases per platform — `expense-simple`,
`expense-offline`, `expense-shared`, `expense-refusals` — each one process launch against
the real backend. **Skipped phases are not counted**, and the surfaces listed as *Not
tested* above contribute nothing to this total, because they have no phase to run.

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

Written down rather than glossed. None of these has an acceptance phase yet, so none of
them has passed; each is host- or widget-tested only.

1. **Cross-period allocation through the Android UI** — the ₹60,000 → May ₹30,000 / June
   ₹30,000 split, and an uneven minor-unit split reconciling to the paisa. The *server*
   half is proven by the live suite (`shared and cross-period at once reconciles on both
   dimensions`); the entry surface is not.
2. **Attachments end to end on either platform** — staging, independent upload, hash
   confirmation, transient-failure retry that leaves the expense `Synced`, and a scoped
   manager being refused the complete-document object by Storage rather than by a hidden
   button. Host coverage is 18 tests; the live suite proves the Storage refusal.
3. **The Windows ledger** — filters, keyset paging against SQL rather than an in-memory
   future, and the detail panel never labelling a scoped share as `TOTAL`.
4. **Two-device propagation**, Android ⇄ Windows simultaneously, for expenses.
5. **Payment-date accrual through the application** — a June salary paid 5 July
   contributing ₹80,000 to June and ₹0 to July.
6. **Void through the UI** — mandatory reason, blank reason refused, control absent for a
   Manager. The *server* refusals are proven on both platforms; the surface is not.

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

**Finish the Phase 3 acceptance.** Write and run the six phases listed under *Acceptance
still outstanding*, then re-run the full gate set and close the phase. Nothing is blocked;
this is remaining work, not an obstacle.

The order that costs least: cross-period entry and payment-date accrual share the entry
surface and should be one phase each on Android; attachments need a phase on each platform
because the pickers differ; the Windows ledger needs one; two-device propagation needs two
halves like `propagate-a` / `propagate-b`.

**Do not mark Phase 3 complete until those have run.** Four of the requested surfaces are
covered today only by host and widget tests, and Phase 2 established — five times over —
that a green host suite is not evidence about the real application.

## Open questions for the project lead

1. **Does a revoked scope take that property's cached expense history with it?** (D-068.)
   Today it does not: the scope purge is limited to server-owned *reference* data, so a
   manager who loses Crystal Canopy keeps its cached expense amounts on their device until
   they sign out. That follows from D-048 as written — "nothing a person typed is ever in
   scope" — and the opposite reading is defensible on exactly the security grounds that
   made D-048 choose Option A in the first place. It is a retention decision about
   financial data, so it is yours rather than an implementer's. If you want it purged it is
   one line in `CacheClassification` plus a delete step; nothing else changes either way.

## Project lead actions required

1. **Answer the D-068 retention question above.** It does not block finishing the
   acceptance, and it should be settled before Phase 3 closes.
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

**Local Drift schema v8.** v1 `app_meta` and `sync_outbox`; v2 masters and period locks;
v3–v4 the Phase 2 master refinements; v5 makes `vendors.default_business_unit_id` and
`default_category_id` soft pointers rather than foreign keys, because a per-user cache
legitimately holds a vendor whose usual property is one this user cannot see (D-049); v6
adds `sync_outbox.actor_user_id` (D-050); v7 adds the four expense tables; **v8 makes
`expense_allocations.business_unit_id` a soft pointer** for the same reason v5 existed —
the scope purge legitimately removes a unit while synced history stays, and the foreign key
made sign-out throw (D-068).

**Postgres: 32 migrations, all applied to `krishna-mis-dev` and all committed.** 0033
measures the edit window under the property's business date instead of the database
session's calendar date (D-067). The live suite asserts the repository and the server agree
(D-056).

## Last important decision

**D-067 — the edit window counts days under the property's date, not the server's.** The
seven-day boundary was already correct and tested; what nobody had asked was what
`current_date` meant. It meant UTC, and the properties do not keep UTC time, so for half an
hour every night the server granted an eighth day it had not been asked to grant. The rule
now derives "today" the same way the client derives a business date for a new entry —
`now()` in the unit's timezone, stepped back before the cut-off — so the two layers agree
by construction rather than by coincidence.

## Master Spec version

**1.1**
