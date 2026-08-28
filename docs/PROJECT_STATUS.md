# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.1**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-08-28**

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

**Phase 3 — Expense Engine: proposed, not started.** No Phase 3 code exists. The plan is
with the project lead.

Phase 0 complete and committed (`3a4502f`). Phase 1 complete. Phase 2 backend integration
checkpointed at `58526c0` and completed at the Phase 2 commit recorded below.

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
| `dart format --set-exit-if-changed` | **Tested** | clean (104 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **408 tests, all passing** |
| Secret scan — tree, git history, built binaries | **Tested** | clean; positive control proves it detects |
| Migration audit (search_path, API surface, policy boundary) | **Tested** | 14 host tests |
| Backend schema parity (migrations vs the claims made about them) | **Tested** | 18 host tests |
| Live backend suite against `krishna-mis-dev` | **Tested** | **19 tests** across 7 phases |
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
| Reporting engines and parity suite | **Not implemented** | Phase 5, by design |
| Financial tables, expenses, revenue | **Not implemented** | Phase 3+, by design |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | 408 | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | all passing |
| Android device acceptance (real APK) | 19 | all passing |
| Windows acceptance (real executable) | 18 | all passing |
| Windows shell (real executable) | 15 | all passing |
| Encryption on device — Android 8, Windows 8 | 16 | all passing |
| **Total** | **495** | **0 failing, 0 skipped-and-counted** |

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

**Phase 3 — Expense Engine.** The proposal is with the project lead and no code has been
written.
It covers the expense document, allocation lines with exact reconciliation, optional
cross-period allocation (D-034), attachments with deferred upload, offline creation with an
atomic outbox write, the Phase 3 Postgres schema with its RLS and RPC boundary, correction
and void semantics, and the Android and Windows entry surfaces.

Four project-lead decisions are needed before implementation begins — see the proposal.

## Open questions for the project lead

**None outstanding from Phase 2.** The Phase 3 proposal raises four new ones.

## Project lead actions required

1. **Read the Phase 3 proposal and answer its four questions.** Nothing else blocks work.
2. **Supply the first tax rule per revenue category** — Restaurant, Nandbhog, Room,
   Banquet — when the real treatment has been verified (D-043). Both applications
   currently show "No rule configured", which is correct and honest until then. This does
   not block Phase 3, but Phase 4 revenue entry cannot be completed without it.
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
| Windows (release + installer) | Not attempted — Phase 9 |

## Database migration status

**Local Drift schema v6.** v1 `app_meta` and `sync_outbox`; v2 masters and period locks;
v3–v4 the Phase 2 master refinements; v5 makes `vendors.default_business_unit_id` and
`default_category_id` soft pointers rather than foreign keys, because a per-user cache
legitimately holds a vendor whose usual property is one this user cannot see (D-049); v6
adds `sync_outbox.actor_user_id` (D-050).

**Postgres: 24 migrations, all applied to `krishna-mis-dev` and all committed.** The live
suite asserts the repository and the server agree (D-056).

## Last important decision

**D-059 — the outbox has a real transport, and it sends only its owner's work.** Building
the offline addendum exposed that `SyncEngine` had never had a real endpoint — nothing
joined the durable queue to the gateways — and that D-050's actor filter was written down
but never passed. Both are closed, and the round trip is proven on both platforms.

## Master Spec version

**1.1**
