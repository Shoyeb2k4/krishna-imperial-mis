# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-08-31** — **PHASE 3 COMPLETE**

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

**Phase 4 — Revenue Engine: IMPLEMENTATION AUTHORISED AND UNDER WAY. Slice 1 of 14
complete.**

The last business blocker closed on 2026-09-01: the project lead confirmed **effective from
2026-04-01** for all four verified treatments, and authorised implementation.

**The verified configuration baseline** — four independent rules, none seeded yet:

| Business unit | Category | Treatment | Rate | Entered basis | Effective from |
|---|---|---|---|---|---|
| Crystal Canopy Rooftop | Restaurant | `inclusive` | 5% (CGST 2.5 + SGST 2.5) | `inclusive_total` | 2026-04-01 |
| Crystal Canopy Rooftop | Nandbhog | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Hotel Krishna Imperial | Room | `inclusive` | 5% | `inclusive_total` | 2026-04-01 |
| Hotel Krishna Imperial | Banquet | **`none`** | — (₹0) | `inclusive_total` | 2026-04-01 |

Restaurant and Nandbhog hold independent rows and do not reference each other (D-089).
Banquet has exactly one rule and **no dormant 5% row** (D-091). Room's conditional
architecture is retained: 5% is today's baseline, not a universal rate compiled into
anything (D-081).

**Slice 1 — spec and governance: complete.** The binding specification is amended to
**v1.2**, confined to the revenue model (D-092): §8.0 documents-with-components, §8.1
conditional resolution over five bounded dimensions with ambiguity refused, §8.3 manual
room entry by value band, §8.4 revenue numbering. No other section is touched, and §30 says
so explicitly.

**The audit found one genuine architecture contradiction in shipped code (D-093).**
`revenue_tax_rates_no_overlap` — the Phase 2 exclusion constraint that currently
*guarantees* deterministic resolution — refuses two active rules for one category over
overlapping dates. Room's two value bands are by construction exactly that, so **the
approved feature cannot be configured against the schema as it stands.** The constraint is
being replaced rather than removed, by a discriminator-aware one in which disjoint bands are
legal and a null discriminator against a specific one is still a conflict; the reasoning and
its five-case table are in D-093. Found before any Phase 4 code was written, which is the
point of auditing the tree rather than trusting the plan.

## Phase 4 implementation slice plan (against the real repository)

Authorised 2026-09-01. Each slice ends with `dart format`, `flutter analyze`, its tests,
a commit and a reported hash. **No slice moves past a failed security or correctness gate.**

### What already exists and is being reused, not rebuilt

Audited against the tree rather than recalled:

| Primitive | Where | State |
|---|---|---|
| `TaxTreatment`, `TaxComputation`, `TaxRule`, `TaxRuleSet` | `lib/domain/tax/tax_rule.dart` (307 lines) | **Inclusive / exclusive / none arithmetic already exists**, in integer paise, half-up, with `ruleFor(date)` returning null rather than defaulting to zero |
| `Money` | `lib/domain/value_objects/money.dart` (260) | integer paise, Indian grouping |
| `BusinessDate` | `lib/domain/value_objects/business_date.dart` (193) | D-067 cut-off semantics, client half |
| `app.business_date_at` | migration 0033 | D-067 server half, instant-parameterised |
| `revenue_tax_rates` + `tax_rule_create` / `_archive` | Phase 2 migrations | **already shipped and RLS-protected** |
| Tax configuration UI | `features/masters` | already shows "No rule configured" |
| `ExpenseRepository` (902 lines), gateways, outbox, `ExpensePull`, attachment pipeline | Phase 3 | the template Revenue follows |

**Phase 4 extends this; it does not start from nothing.** The single largest piece of new
domain work is the conditional resolver, and even that is an extension of `TaxRuleSet`.

### The slices

| # | Slice | Substance | Gate |
|---|---|---|---|
| **1** | **Spec and governance** | Spec §8 amended, v1.2, `CLAUDE.md` and five docs, D-092, D-093, this plan | docs consistency, secret scan |
| 2 | Domain model and resolver | `RevenueEntry` / `RevenueComponent`; `entered_basis`; conditional `TaxRuleSet.resolve(facts)`; discriminator-aware `refusalFor` (D-093); reconciliation | unit tests incl. the five D-093 rows and the refusals |
| 3 | Local schema | Drift v11: `revenue_entries`, `revenue_components`, extended rule cache, subtype and premises-status caches | migration test v10→v11, `CacheClassification` completeness |
| 4 | Server schema, RLS, RPC boundary | tables, the **replaced** exclusion constraint, `revenue_document` projection, `revenue_create/update/void/correct_business_date`, KI-REV sequence, audit, usage | migration audit, API-surface invariant, allow **and** deny tests |
| 5 | Offline resolution and refusal | resolver over cached config; refuse-and-queue-nothing (D-086) | repository tests |
| 6 | Sync, outbox, gateway | `RevenueGateway`, `RevenueMutationEndpoint`, `RevenuePull` | idempotency, response-loss, stale-version tests |
| 7 | Create workflow | atomic local write + outbox in one transaction | rollback-at-each-boundary tests |
| 8 | Android entry surface | unit → category → band field(s) → live gross/GST/net → save | widget + draft-model tests |
| 9 | Windows ledger and detail | dense ledger, filters, component breakdown, rule snapshot | widget tests |
| 10 | Correction and void | edit window, capabilities, conflict presentation | domain + widget tests |
| 11 | Attachments | reuse D-073a unchanged | wiring test in the D-077 shape |
| 12 | Reporting contributions | `revenue_period_contributions` populated | reconciliation tests |
| 13 | Live and device acceptance | both platforms, real backend, two-device | the §23 acceptance list |
| 14 | Closure | docs, totals, clean artefacts | full gate |

### Two things carried forward from Phase 3's failures

**Production wiring is asserted, not assumed.** D-077 shipped a feature that did not exist
because every test overrode the provider and none read what production resolves. Slice 11
carries an explicit wiring test in that shape, and Slice 8's tax resolution is asserted
through the real provider chain, not only through an injected resolver.

**A rule that nothing evaluates is a comment.** D-093's replaced constraint gets tests for
the cases that must still be **refused**, not only the ones that must now be allowed —
D-069, D-071 and D-077 were all checks that had silently stopped checking.

### One decision deferred to Slice 4, flagged now rather than taken quietly

**Where the verified configuration lives.** The four rules are real business configuration,
not financial history, so §32 does not forbid committing them. Two options:

* **a committed migration** — all three environments get identical, reviewed configuration;
  a rate change is a reviewed diff with an author and a date; and dev/staging/prod cannot
  drift. A GST rate is not a secret.
* **configured per environment through `tax_rule_create`** — matches D-043's original
  wording, and keeps configuration out of source control entirely.

**Recommendation: the committed migration**, for the audit trail and because three
environments configured by hand will diverge. Raised at Slice 4 rather than decided here.


---

**Phase 3 — Expense Engine: COMPLETE.** All four gates are closed:

| Gate | Status |
|---|---|
| Implementation | **Complete** |
| Automated acceptance | **Complete** — 674 host tests, 48 acceptance tests across 37 real process launches on both platforms, live backend 19, live expense 16 |
| Manual native-picker acceptance | **Complete** — Android **PASS**, Windows **PASS** (2026-08-31) |
| Clean candidate artefacts | **Verified** — built without acceptance defines, scanned, installed and launch-verified on both platforms |

**Production distribution remains Phase 9**: release signing with the project lead's
keystore, the AAB path, and the Windows installer are not part of this phase and are not
claimed by it. What is claimed is that the expense engine works, end to end, on both real
clients against a real backend.

**The manual picker acceptance is worth reading rather than ticking.** It failed the first
time, on both platforms, and it failed for the reason no automated test could see: the
picker had never been implemented (D-077). `lib/` held one `AttachmentSource` —
`UnavailableAttachmentSource` — the provider defaulted to it, a comment promised a
bootstrap would replace it, and nothing ever did. Every attachment test passed throughout,
because each overrode that provider with a synthetic source; **none read what production
resolves.** D-073 therefore shipped through a full green acceptance phase with no real
picker behind it, and that fact stays in this record rather than being tidied away — it is
the strongest evidence in the project for why a boundary the harness cannot cross needs a
person to cross it.

It was fixed, re-accepted automatically on both real clients, rebuilt clean, and then
passed by hand:

* **Android** — the real system Photo Picker opened and returned the selected image to
  Krishna Imperial MIS, shown **Attached**.
* **Windows** — the real native Windows file dialog opened and returned the selected file,
  shown **Attached**.

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

**Phase 3 — Expense Engine** (implementation and automated acceptance; not formally
closed — see the top of this document).

*The document model.* Expenses as a header plus allocation lines (D-003), with every line
carrying at least one **period contribution** so there is exactly one place the money lives
and double counting is structurally unavailable rather than avoided by careful queries
(D-060). Cross-unit and cross-period splitting compose without either knowing about the
other, each behind its own capability (D-061, D-034).

*The local read model as a deliberate sibling of the server schema* (D-062) — a scoped row
cannot carry a document total, enforced by a SQLite check constraint, so the covert channel
the server projection closes cannot be reopened by a cache that stored the total anyway.
Proven by reading the **bytes** of three separate databases.

*The write path.* Atomic local create with the outbox intent in the same transaction;
idempotent delivery; `base_row_version` on every mutation; response-loss recovery; terminal
`Rejected` distinct from `Conflict`.

*The surfaces.* Android entry, the Windows ledger with its complete filter surface and
keyset paging, the detail panel, cross-period and cross-unit editors, the audit
presentation, **expense edit** (D-072a) and **void**.

*Attachments end to end* (D-073a): staging, hashing, ordered upload, registration in
Postgres, hash verification, durable retry, and read authorisation that gives a scoped
manager neither the object nor its metadata row (D-063).

*Retention on revocation* (D-070, D-074): a confirmed revocation takes the revoked
property's synced figures out of the browsable cache, keeping the actor's own unsent work —
and keeping it *theirs*.

*The server boundary.* `authenticated` holds **no `SELECT` on `public.expenses`**; the read
path is the `expense_document` projection, which withholds the header total from a
unit-scoped caller because on a two-property bill `total − own share` is the other share.
Every financial write goes through a reviewed `SECURITY DEFINER` RPC — `expense_create`,
`expense_update`, `expense_void`, `expense_correct_business_date`, `attachment_register` —
each re-checking capability, unit scope, period lock, edit window and `base_row_version`
server-side, and each on the declared API surface the migration invariant asserts in both
directions (D-044).

*Transaction numbering* is **server-issued**: the client generates the UUID v7 identity
offline (D-008) and the server assigns the human-readable `KI-EXP-…` number when it accepts
the document. An edit returns only `row_version`, so reconciliation leaves fields the server
did not restate alone — writing them all back erased the number on every edit until D-072a
caught it.

*Attachments* carry an eight-state client lifecycle (`staged` → `waitingForExpense` →
`pendingUpload` → `uploading` → `uploaded` → `stagingReclaimed`, with `retryNeeded` and a
terminal `rejected`), a private Supabase Storage bucket at a deterministic path, and
`attachment_register` as the **only** writer of `expense_attachments` — so Postgres, not a
bucket listing, is the record of what evidence exists (`ARCHITECTURE.md` §16).

*The pickers* (D-077): Android's system Photo Picker and the Storage Access Framework;
Windows' native `IFileOpenDialog`. No storage permission is declared or requested, and
`CAMERA` is deliberately not declared.

*Acceptance hygiene.* Two defects in the suite itself were found and fixed rather than
worked around: a missed tap that reported as a sync defect (D-075), and a two-device chain
keyed on a fixed primary key that could pass exactly once, because a void does not free a
key (D-076).

## Verified

Labels used exactly as defined: **Implemented / Tested / Partially tested / Not tested /
Blocked.**

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean (145 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **674 tests, all passing** |
| Secret scan — tree and git history | **Tested** | clean; the scan proves its own controls on every run (D-069) |
| Secret scan — rebuilt clean binaries | **Tested** | tree, git history and built artefacts all clean, with the scanner's controls passing |
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
| Secret scan — tree and git history | **Tested** | clean; the scanner's own controls pass on every run (D-069) |
| Secret scan — **rebuilt clean** APK, extracted APK tree, Windows Release bundle | **Tested** | clean; also verified by a direct byte search of `kernel_blob.bin` (89.6 MB) and `app.so` (9.4 MB) for each development password — nil in both |
| Android cross-period entry through the UI | **Tested** | `cross-period`: ₹60,000 → May ₹30,000 / June ₹30,000, plus an odd-paise split reconciling exactly |
| Attachments end to end — stage, upload, register, verify, retry | **Tested** | `attachment-staging` + `attachment-upload` on both real clients, against real Supabase Storage (D-073a) |
| Attachment read authorisation — a scoped manager refused (D-063) | **Tested** | `attachment-scope`, both platforms: the object, the metadata row **and** the right to attach |
| Production picker **wiring**, both platforms | **Tested** | 6 host tests asserting what production resolves; the assertion that was missing while the picker did not exist (D-077) |
| The OS file / photo picker itself, Android | **Tested — manual, PASS** | 2026-08-31, real Galaxy A06 5G: the system Photo Picker opened and returned the image, shown **Attached**. Failed the first attempt — see D-077 |
| The OS file / photo picker itself, Windows | **Tested — manual, PASS** | 2026-08-31, real `krishna_mis.exe`: the native file dialog opened and returned the file, shown **Attached**. Failed the first attempt — see D-077 |
| Windows ledger: the complete filter surface, keyset paging, scoped detail caption | **Tested** | `windows-ledger`, incl. the filter-dependency rule and a scoped share never captioned `TOTAL` |
| Two-device Android ⇄ Windows expense propagation | **Tested** | `propagate-expense-a…e`: create with a bill, correct, stale edit conflicts, void, evidence still there |
| Expense **edit** through the UI | **Tested** | `expense-edit` on both real clients: identity kept, version advanced, D+7/D+8, stale → Conflict (D-072a) |
| D-070/D-074 financial cache retention and ownership | **Tested** | `d068-switch` + `d068-revoke`, 3 on the real APK and 3 inside the real `.exe`, the Windows ones against a database that had accumulated across runs |
| Client and server agree on a business date at one instant | **Tested** | 10 host tests reading migration 0033's own assertion table |
| Payment-date accrual through the application | **Tested** | `payment-accrual`: ₹80,000 to June, ₹0 to July, paid 5 July |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | 674 | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | all passing — re-run in full |
| Live expense suite against `krishna-mis-dev` (opt-in) | 16 | all passing — re-run in full |
| Android Phase 2 device acceptance (real APK) | 19 | all passing |
| Windows Phase 2 acceptance (real executable) | 18 | all passing |
| Windows shell (real executable) | 15 | all passing |
| Encryption on device — Android 8, Windows 8 | 16 | all passing |
| **Core expense acceptance, Windows** (`expense-simple`, `-offline`, `-shared`, `-refusals`) | **4** | **all passing** |
| **Core expense acceptance, Android** (the same four) | **4** | **all passing** |
| **Expense edit, Windows** (`expense-edit`) | **3** | **all passing** |
| **Expense edit, Android** (`expense-edit`) | **3** | **all passing** |
| **Offline edit** (`expense-edit-offline`, both platforms) | **2** | **all passing** |
| **Edit refusals** (`expense-edit-refused`, both platforms) | **4** | **all passing** |
| **Scoped-share edit security** (`expense-edit-shared`, both platforms) | **2** | **all passing** |
| **Windows ledger** (`windows-ledger`) | **1** | **all passing** |
| **Attachment staging** (`attachment-staging`, both platforms) | **2** | **all passing** |
| **Attachment upload** (`attachment-upload`, both platforms) | **4** | **all passing** |
| **Attachment scope security** (`attachment-scope`, both platforms) | **2** | **all passing** |
| **D-070 retention** (`d068-switch`, `d068-revoke`, both platforms) | **6** | **all passing** |
| **Android cross-period** (`cross-period`) | **2** | **all passing** |
| **Payment-date accrual** (`payment-accrual`) | **1** | **all passing** |
| **Two-device propagation** (`propagate-expense-a…e`) | **5** | **all passing** |
| **Acceptance fixture reversal** (`expense-cleanup`, both platforms) | **2** | **all passing** — 162 accumulated documents voided, then `reversed 0 of 0` on the second platform |
| **Development fixture restoration** (`propagate-restore`) | **1** | **all passing** |
| *(Phase 3 acceptance subtotal — the bold rows above, not an extra suite)* | *48* | *all passing* |
| **Total** | **819** | **0 failing, 0 skipped-and-counted** |

Each acceptance phase is **one process launch of the real application** against
`krishna-mis-dev`. A phase reports its own tests as passing and every other phase as
skipped; **only the phase that ran contributes**, so nothing in this total is a phase that
did not execute.

**Everything in this table was run at this checkpoint.** Nothing is carried forward — the
two live suites that were carried forward last time (19 backend, 16 expense) were re-run
in full, and the live backend suite's seven phases were driven with their real
administrative acts in between (revoke, restore, grant, revoke) rather than skipped.

**What is *not* in this total, and why.** The two native-picker smoke tests. They cannot
be automated — the OS picker is a separate activity — and a manual test nobody has run is
not a passing test. They are recorded as **MANUAL — PENDING SHOYEB CONFIRMATION** and
counted nowhere.

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
7. **A retained document was handed to whoever signed in next** (D-074). Restoring
   browsability tested scope and not ownership, so on a shared workstation the previous
   user's unsent work became browsable to the next person whose scope happened to overlap.
   Ownership is now part of the predicate, via `sync_outbox.actor_user_id`. Found only on
   the Windows machine, because its database persists between runs and the emulator's does
   not.
8. **Sign-out did not fail closed.** `purgeAllScopedCache()` was called unguarded. It was
   not in fact throwing — the D-074 hypothesis was wrong — but a cleanup failure must not
   leave the previous user's figures readable, so it now falls back to quarantining every
   document: nothing browsable, nothing destroyed, and the original error still propagates.
9. **The v10 attachment-state migration recreated the table before rewriting its values**,
   which only failed on the machine that had real v9 rows to migrate. Fixed with a
   `columnTransformer`, and pinned by a v9→v10 test.
10. **An attachment-metadata policy was vacuously true for scoped users.** It searched for
    rows that RLS had already hidden from it, so it could neither permit nor refuse
    anything. The same shape as D-068's classification guard and D-071's cleanup: *a rule
    that nothing evaluates is a comment.* Fixed in migration 0036.
11. **A missed tap was reported thirty seconds later as a sync defect** (D-075). Flutter
    treats a tap that lands on nothing as a warning; the test carried on and failed on the
    outbox intent the un-pressed button never produced. Missed taps are now fatal in the
    acceptance suite, and taps wait for hit-testability rather than for *enabled*.
12. **The attachment picker was never implemented, on either platform** (D-077). The only
    `AttachmentSource` in `lib/` was `UnavailableAttachmentSource`; the provider defaulted
    to it and the promised bootstrap override was never written. Found by the project
    lead's manual test, after the automated attachment acceptance had reported the
    pipeline complete on both real clients — because every one of those tests overrode the
    provider and none read what production resolves.


## Acceptance still outstanding

**A phase that has not run is not a phase that passed**, and a phase that failed is
reported as failed rather than re-run until it is convenient.

### Closed since the last checkpoint

| Surface | Status | Evidence |
|---|---|---|
| Attachment staging to the picker boundary | **Tested** | `attachment-staging`, both platforms |
| Attachment **upload**, registration and hash confirmation | **Tested** | `attachment-upload`, both platforms, against real Supabase Storage |
| Idempotent redelivery — one object, one metadata row | **Tested** | inside `attachment-upload` |
| Transient failure: expense stays `Synced`, bill says Retry needed | **Tested** | inside `attachment-upload`, both platforms |
| Attachment read authorisation (D-063) | **Tested** | `attachment-scope`: object, metadata row and the right to attach, all refused |
| Windows ledger — the complete V1 filter surface | **Tested** | `windows-ledger`, incl. the dependency rule and paging |
| Two-device propagation, Android ⇄ Windows | **Tested** | `propagate-expense-a…e`: create, correct, stale conflict, void, evidence intact |
| Payment-date accrual | **Tested** | `payment-accrual`, re-run at this checkpoint rather than carried forward |

### Still outstanding

**Nothing.** The manual native-picker smoke tests were the last item and both passed on
2026-08-31 (Android **PASS**, Windows **PASS**). Their first attempt is recorded as
**FAILED** above and in D-077, and stays recorded: it is the finding that justifies the
whole practice of keeping a manual gate for a boundary the harness cannot drive.

## Revenue tax configuration baseline (Phase 4 — one item pending)

Business evidence and project-lead confirmations, recorded **as verified configuration
facts**. **Nothing here is yet a tax rule in the system.** No rate, basis or date below has
been written into a migration, a seed, a fixture or a line of code, and none will be until
the effective-from dates are confirmed (D-043, D-084).

The distinction this table keeps is the one D-088 exists for: *what a source invoice shows*
and *what the management figure means* are two different facts, and knowing the first does
not establish the second.

| Category | Rate / treatment | Management input basis | Effective from | Status |
|---|---|---|---|---|
| **Restaurant** (Crystal Canopy Rooftop) | **Verified 5%** — CGST 2.5% + SGST 2.5%, bill of 01/09/2026 | **Verified** `inclusive_total` | **Pending** | Date only |
| **Nandbhog** (Crystal Canopy Rooftop) | **Verified 5%** — confirmed 2026-09-01; Nandbhog is restaurant revenue (D-089) | **Verified** `inclusive_total` | **Pending** | Date only |
| **Room** (Hotel Krishna Imperial) | **Observed 5%** — invoice for the stay from 31/08/2026: base ₹2,239.00, CGST ₹55.98 + SGST ₹55.98, ₹2,350.96 before rounding | **Verified** `inclusive_total` | **Pending** | Date only |
| **Banquet** (Hotel Krishna Imperial) | **Verified `none`** — no GST; confirmed 2026-09-01, matching the invoice of 30/08/2026 (₹40,343, taxes ₹0) (D-091) | **Verified** `inclusive_total` | **Pending** | Date only |

**Management input basis, all four: `inclusive_total`** (D-090). The figure a manager
records is the final customer-billed amount including GST where GST applies. This states
what the operator means, not how any invoice presents its tax.

### What each of these is, and is not

**Restaurant and Nandbhog share a treatment; they do not share a rule.** Both 5% inclusive,
and still two independent rule rows with no inheritance and no shared row (D-089). A future
change to one must not move the other's Net Sales, and separate reportability is why
Nandbhog is a category at all (spec §4).

**Banquet has exactly one rule, and its treatment is `none`** (D-091). The earlier
observation that 5% is sometimes applied is closed **as an observation**: *"customer asks
for GST → 5%"* is not encoded, is not a rule dimension, and is not a dormant second row. A
GST-bearing banquet supply, if it is ever needed, arrives as a separately approved rule or
supply subtype after its accounting treatment is verified — an explicit decision, not
something found already switched on. Two active Banquet rules would make resolution
ambiguous, which D-084 refuses, and the refusal would present as a mysterious blocked save
rather than as the configuration question it is.

**One room invoice is one room invoice.** It shows a 5% treatment in current use at a
₹2,239 tariff. It does not establish that every room transaction uses the same rule at
every tariff, and the conditional architecture (D-079, D-081) is retained precisely so a
second band can be configured later without a redesign.

**Confirming a rate does not confirm a date.** Evidence dated 30/08–01/09/2026 shows what
is true now and says nothing about when it started. Defaulting to 01/04/2026 because it is
the start of the financial year would be inventing a business fact, and it would silently
determine how every prior month is restated if history is ever imported.

### Still required — one item

**Effective-from dates**, for all four verified treatments: Restaurant 5%, Nandbhog 5%,
Room 5%, Banquet `none`.

*"These have applied since the start of FY 2026–27"* is a perfectly good answer, and so is
a different date per category. What cannot happen is the software choosing one. Once these
are supplied, Phase 4 has no remaining business blocker.

## Known issues

1. **`flutter_secure_storage` pinned to 9.2.4.** 11.x requires `compileSdk 37`; this
   toolchain has Android SDK 36 (D-031). Revisit when the SDK moves.
2. **`riverpod_lint` / `custom_lint` deferred** — analyzer conflict with `drift_dev`
   (D-032). Checked again at the end of Phase 3 and still unresolved upstream; revisit at
   Phase 5.
3. **The Windows Overview placeholder names both properties in its description copy.** A
   scoped Manager therefore sees the words "Hotel Krishna Imperial" on a screen that holds
   none of that property's data. Not a data leak — business unit names are not secret — but
   it is a small scope-hygiene wrinkle, and it briefly confused an acceptance assertion.
   Worth revisiting when the Overview becomes a real dashboard in Phase 6.
4. **Windows local-key protection relies on user-scoped DPAPI**, not hardware (D-036).
   Accepted for V1, mitigated as recorded.
5. **The host widget suite does not yet make a missed tap fatal.** The acceptance suite
   now does (D-075), and the setting is one line. It is not applied to `test/` in this
   change because doing so at the end of a phase would surface an unknown number of latent
   misses with no time to judge them, and a rushed judgement about a financial widget test
   is worse than a recorded follow-up. Worth doing at the start of Phase 4, when there is
   room to look at whatever it finds.
6. **The host machine's network path to `krishna-mis-dev` drops intermittently.** Measured
   with `curl`, no application involved: seven requests at ~0.13 s, then a 15-second
   connect, then two outright failures. It caused four acceptance phases to fail during
   this checkpoint and all four passed on re-run. Not a product issue and not a test
   issue — recorded so the next person who sees a phase fail at sign-in checks the network
   before rewriting a test (D-075).

## Blockers

**None.** The backend is provisioned, the migrations are applied and committed, and both
platforms run against it. The one item that is not done — the manual picker smoke tests —
needs the project lead at a machine, and is listed under *Project lead actions required*
rather than here, because nothing is blocked from proceeding by it except the formal
declaration that Phase 3 is closed.

## Deferred (by design)

- Approval workflow — modelled in the schema, disabled in V1 (spec §26).
- Partial payments / payables ageing (spec §5.4).
- Input tax credit and any statutory GST support (spec §6.1).
- Snapshot-based sync pull cursor (`ARCHITECTURE.md` §5.2).
- Historical Excel/CSV import — separate controlled workflow (spec §32).
- Bundled licensed fonts — the type scale is fixed; the family is a one-line swap.
- The period-close console. Enforcement is built into the write path; the console is a
  later phase.
- **Other Income** — out of V1 scope (spec §28/§29); revenue V1 is Restaurant, Nandbhog,
  Room and Banquet only.
- **The P&L and reporting engines** — Phase 5. Phase 4 defines and populates
  `revenue_period_contributions` and builds no reporting (D-087).

## Next exact task

**Wait for the revenue tax and billing configuration.** Phase 4's architecture is approved
and recorded (`ARCHITECTURE.md` §17, `DATABASE_SCHEMA.md` §6.1, D-078 … D-087); its
implementation is **not started** and must not start before that configuration arrives.

The dependency is genuine rather than procedural. The tax model's *shape* is settled, but
its dimensions were chosen to fit real treatments — value bands for Room, supply subtypes
for Banquet, a premises status for Restaurant. Building the resolver, the entry surfaces
and the acceptance suite against imagined rules would mean discovering at acceptance that
the real configuration needs a dimension nobody planned for, which is the expensive way to
find out.

What *could* proceed without it, if the project lead wants Phase 4 started in parallel: the
schema, the RPC boundary, the outbox and gateway wiring, and the ledger surfaces are all
independent of which rates exist. The entry form and every tax assertion are not. That is a
decision for him, not one to be taken by starting.

## Open questions for the project lead

**None for Phase 3.** All were answered and implemented: revoked-scope financial retention
(D-070), the expense edit surface (D-072a), and attachment upload (D-073a).

**One for Phase 4**, and it is a business fact rather than a design choice: the
**effective-from dates** for the four verified treatments. Confirmations through
2026-09-01 answered everything else — see the *Revenue tax configuration baseline*.
**Phase 4 implementation stays blocked on it**, and no date will be inferred from an
invoice date or defaulted to the start of the financial year (D-043, D-084).

## Project lead actions required

1. ~~Two manual picker smoke tests.~~ **Done, 2026-08-31 — both PASS.**
2. **One remaining answer, and Phase 4 can start: the effective-from dates.**

   Your confirmations through 2026-09-01 settled everything else — Restaurant 5%,
   Nandbhog 5%, Room 5%, Banquet no GST, and all four recording the tax-inclusive customer
   total. What is left is *from when* each treatment applies.

   *"All four have applied since the start of FY 2026–27"* is a perfectly good answer, and
   so is a different date per category if that is the truth. What cannot happen is the
   software choosing one: an effective-from date silently determines how every prior month
   is restated if history is ever imported, so it is a business fact rather than a default.

   Until the dates are supplied, the rules cannot be configured, the categories show
   *"No rule configured"*, and revenue entry refuses (D-084) — the approved behaviour, not
   a defect.

3. **Optional decision:** whether archiving should also offer a *confirmed* cascade for a
   whole subtree (D-039).

No production credentials are ever requested. **You will never be asked to paste a
password, service-role key, database password, private key or signing password into chat.**

## Build status

| Target | Status |
|---|---|
| Android (debug, dev flavour) | **Built clean, installed and launch-verified** — `app-dev-debug.apk`, arm64-v8a/armeabi-v7a/x86_64, debug-key signed |
| Android (release APK / AAB) | Not attempted — Phase 9, needs the project lead's keystore |
| Windows (debug) | **Built, launched, and driven against the real backend** |
| Windows (release) | **Built clean and launch-verified** — complete bundle at `build/windows/x64/runner/Release/` |
| Windows installer | Not attempted — Phase 9 |
| Clean Phase 3 candidate artefacts | **Built and scanned clean** — no acceptance identity defines; both launch to the normal login screen |

**Clean Phase 3 candidate artefacts (2026-08-31, rebuilt with the picker).** Built with
the environment config only — **no acceptance identity defines** — then scanned and
launch-verified:

| | |
|---|---|
| Android | `build/app/outputs/flutter-apk/app-dev-debug.apk` — `in.krishnaimperial.mis.dev`, versionCode 1, versionName `1.0.0-dev`, debug-key signed, arm64-v8a + armeabi-v7a + x86_64. Installed on the project lead's Galaxy A06 5G **as an update**: `firstInstallTime` unchanged, so no data was lost |
| Windows | `build/windows/x64/runner/Release/` — `krishna_mis.exe` with every plugin DLL beside it, now including `file_selector_windows_plugin.dll`. **No installer exists yet** (Phase 9); run the executable from inside that folder |

Both launch to the **normal sign-in screen with empty fields**. Direct byte searches of
`kernel_blob.bin` (90.1 MB) and `app.so` (10.5 MB) find **zero** development passwords and
do find `AndroidAttachmentSource`, `WindowsAttachmentSource` and `useAndroidPhotoPicker` —
so the adapters are demonstrably compiled in rather than assumed to be.

An acceptance run rebuilds the APK **with** the identity defines, so the clean build is
made after the last acceptance phase and re-scanned; the ordering is deliberate, and the
artefact that went to the phone is the post-acceptance clean one.

**Acceptance builds are not distributable.** Driving the acceptance suite compiles the
development identity passwords into `kernel_blob.bin`; the scanner proves it, and proved it
again this phase. The artefacts that survive a run are rebuilt without the identity defines
and re-scanned before anything is called distributable. **The binaries currently on this
machine are acceptance builds and are not distributable**, which is why the clean rebuild
is listed above as not done rather than quietly assumed: there is nothing to be gained from
rebuilding and scanning artefacts that will be rebuilt again after the picker tests.

## Database migration status

**Local Drift schema v10.** v1 `app_meta` and `sync_outbox`; v2 masters and period locks;
v3–v4 the Phase 2 master refinements; v5 makes `vendors.default_business_unit_id` and
`default_category_id` soft pointers rather than foreign keys, because a per-user cache
legitimately holds a vendor whose usual property is one this user cannot see (D-049); v6
adds `sync_outbox.actor_user_id` (D-050); v7 adds the four expense tables; v8 makes
`expense_allocations.business_unit_id` a soft pointer for the same reason v5 existed —
the scope purge legitimately removes a unit while synced history stays, and the foreign key
made sign-out throw (D-068); v9 adds `expenses.scope_revoked_at`, because a confirmed
revocation purges synced financial cache (D-070) and a document still carrying the actor's
own unsent intent needs somewhere to say it is retained for that reason and is not
browsable financial data; **v10 widens the attachment upload state** from three values to
the eight the real lifecycle has (D-073), and adds the constraint that a `rejected` bill
carries no `nextAttemptAt` — a null there once meant "due now", so a terminal refusal
retried for ever.

The v10 migration rewrites the existing values during the table copy rather than after it,
using a `columnTransformer`. That distinction only mattered on Windows, whose database
held real v9 rows; the Android emulator reinstalls each run and would never have caught
it — the same asymmetry that hid D-074. A v9→v10 test now pins it.

The local database sets `PRAGMA secure_delete = ON`, so a purge does not leave the revoked
property's figures legible in freed pages, and `PRAGMA foreign_keys = ON`.

**Postgres: 35 migrations, all applied to `krishna-mis-dev` and all committed.** 0033
measures the edit window under the property's business date (D-067). 0034 adds
`attachment_register` — the only writer of `expense_attachments`, verifying the size and
SHA-256 against the stored object. 0035 restates the reviewed API surface to include it,
which the invariant refused to let me skip (D-044). 0036 fixes an attachment-metadata
policy that was **vacuously true** for scoped users: it hunted for rows that RLS had
already hidden from it, so it could neither permit nor refuse anything. The live suite
asserts the repository and the server agree (D-056).

## Last important decision

**D-074 — a retained document belongs to whoever queued it.** D-070 established that a
confirmed revocation takes the revoked property's synced figures out of the browsable
cache, keeping only the actor's own unsent work because it exists nowhere else. That is a
statement about *whose* a document is. The code that gave a document back tested only
*where* it was.

So when a user signed out and the next one signed in, every retained document whose
business units fell inside the incoming user's scope was un-hidden for them — including
documents queued by somebody else, on a shared workstation, which is the exact machine
D-054 added the sign-out control for. Ownership is now part of the predicate, established
through `sync_outbox.actor_user_id` (D-050). An org-wide grant covers every unit by
construction and is therefore no evidence of authorship, so it is tested identically.

Two things fell out of it, and both are the more general lesson.

**The first hypothesis was wrong, and checking it is what found the cause.** The previous
checkpoint recorded, plausibly, that the sign-out purge was throwing. A diagnostic run on
the real Windows installation showed the purge completing correctly and stamping all
twelve documents — the exposure was one step later, in the opposite direction. Had the
"fix" been applied to the hypothesis instead of to the evidence, the symptom would have
disappeared on a freshly installed device and the defect would have shipped.

**A test whose fixture is recreated every run cannot see a defect that needs history.**
Android reinstalls the app each run and passed throughout. Windows keeps its database and
failed. The persistent installation was the honest one.

## Master Spec version

**1.2** — bumped 2026-09-01 for the revenue model amendment only (spec §8, D-092).
