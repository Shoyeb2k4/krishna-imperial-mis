# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-10-03** — **PHASE 9 SLICE 3 — PRE-RELEASE UX WORDING: COMPLETE** (D-348, D-349): the six named surfaces (Masters on both shells, Tax rates, Vendors, the Revenue ledger, the Expense save failure) now show one plain sentence and, for reads, a Try again that genuinely reads again; the exception goes to the developer log only. The Administration destination states the approved V1 sentence instead of a Phase 2 promise. The Windows staging data identity is approved (D-349) and is built when staging is first exercised. Host suite **3,248 passed**. Presentation only: no schema, server, authority or storage change. **Slice 4 is not started.** See *Phase 9 Slice 3* at the end of this file.

Previously: **2026-10-03** — **PHASE 9 SLICE 2 — RELEASE-BUILD HARDENING: COMPLETE** (D-346, D-347): all six D-335 blockers fixed. `INTERNET` is in the production manifest; Android release builds are signed only with the upload key from a git-ignored `android/key.properties` and stop without it (no debug fallback); R8 runs with an existing, empty rules file; a production build with no backend, with the dev backend, or with a mismatched flavour refuses to start; and production keeps its local data in `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production` with key `krishna_mis.db_key.prod.v1` (its own DPAPI key file on Windows), never the D-247 folder. Host suite **3,223 passed**. No schema, migration, server or Supabase change. **Slice 3 is not started.** See *Phase 9 Slice 2* at the end of this file.

Previously: **2026-10-03** — **PHASE 9 — PRODUCTION RELEASE, DEPLOYMENT & GO-LIVE: STARTED. Slice 1 (governance and production inputs) is complete** (D-334 … D-345): the release contract, six verified release blockers for Slice 2, the authoritative replay contract (98 committed migration files), the read-only production smoke policy, the product-lead input register, the secrets register and the runbook skeleton (`docs/PRODUCTION_RUNBOOK.md`). Documentation only: no code, schema, server, signing or build change. **Slice 2 is not started.** See *PHASE 9* at the end of this file.

Previously: **2026-10-03** — **PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: COMPLETE AND FORMALLY CLOSED at Slice 9 (D-333).** Slices 1–9 are closed. The Revenue ledger sync-state defect was fixed before Slice 8 (D-331) and accepted in it; no known V1 correctness defect is carried out of Phase 8. Windows and the Galaxy A06 PASS; the Android emulator was NOT EXECUTED and is waived for closure by the project lead. D-248 stays unconfirmed with its diagnostic; D-247 stays preserved and unresolved. Host suite **3,154 passed** at `1a4dd12`. Local schema v22; ledger 105; API 57. The production 50:50 ownership effective-from date is still unknown. The closure record is *PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: COMPLETE AND CLOSED* at the end of this file. **Phase 9 — Distribution: not started.**

Previously: **2026-10-03** — **PHASE 8 SLICE 8 — WINDOWS AND GALAXY A06 ACCEPTANCE: COMPLETE (D-332).** Every Slice 8 phase passes in the real Windows executable and on the Galaxy A06: the recovery screens, the v21 → v22 upgrade on a production-shaped copy, the Revenue ledger's sync-state paging (D-331), the double Save press (D-326), Save As and Print through the native dialogs, and the phone share with a live capability loss and a user switch (D-310). Three acceptance-harness defects were found and fixed; no product code changed. Host suite **3,154 passed**. `krishna-mis-dev` ends exactly at its pre-Slice-8 baseline. **Slice 9 (closure) is not started.**

Previously: **2026-10-02** — **REVENUE LEDGER SYNC-STATE REMEDIATION: DONE (D-331).** A sync-state filter on the Revenue ledger now finds every matching sale, not just those among the newest 50; it is decided in SQL before the page is cut. No schema, server or UX change.

Previously: **2026-10-02** — **PHASE 8 SLICE 7 — STRESS, FAILURE & RECOVERY: COMPLETE (D-328 … D-330).** If the app cannot open its data it now says why in plain words and offers *Try again*; only for data that truly cannot be opened or upgraded does it offer *Reset local data and download again*, after stating what would be lost and a typed RESET. The data is moved aside, never deleted. An interrupted upgrade now changes nothing instead of leaving the data unopenable for ever; a missing key no longer writes a new one; a lock is no longer reported as damage. Host suite **3,134 passed**; Windows restart smoke PASS. No schema or server change. **Slice 8 is not started.**

Previously: **2026-10-01** — **PHASE 8 SLICE 6 — CLOSED on the Galaxy A06 (D-327 A06).** On the reference phone, the first realistic P&L PDF of a session takes about 0.56 s, including the font load, and later ones about 0.06 s. Both are far inside the 2-second limit, and on a debug build. The shared PDF opens the Android share sheet; Back cancels it; sign-out removes the file. The Dashboard smoke passes. The clean dev APK is installed with a matching hash. Not exercised on the device: the accountant capability-loss step and the user-switch half of D-310, because the capability change was refused by this session's permissions (host tests cover both). **Slice 7 is not started.**

Previously: **2026-10-01** — **PHASE 8 SLICE 6 — EXPORT PERFORMANCE: MEASURED, NO CHANGE (D-327).** On the real Windows executable (debug build) every normal export, PDF or Excel, finishes in under 160 ms including the one-off font load. That is far inside T2's 1 s, so nothing was optimised. A deliberately huge P&L (640 lines, 17 pages) takes 205 ms. The Galaxy A06 half of T2 is **not tested**: no device was attached, and the same harness runs there in Slice 8. One finding is recorded and not fixed: a P&L PDF with more than about 840 category lines hits the `pdf` package's 20-page limit and is reported as "could not be made". **Slice 7 is not started.** See *Phase 8 Slice 6* at the end of this file.

Previously: **2026-10-01** — **D-326 FIXED.** A second Save press before the button rebuilds now returns at once on Revenue and Expense entry, and a failed save releases the form for a retry. Host suite **3,068 passed, 0 skipped**. No schema or server change. **Slice 6 is next.**

Previously: **2026-10-01** — **PHASE 8 SLICE 5 — GLOBAL MISSED-TAP TEST HARDENING: COMPLETE
(D-325).** A tap that misses its target now fails the test, everywhere in the host suite, by one
global test config that re-asserts the rule before every test and fails any test that turns it
off. Turning it on failed nothing: the suite was already clean. The one exception the suite
carried was dead code — the revenue "double tap" test never pressed twice — and pressing twice
for real exposed **D-326**: a double press before the next frame reaches the revenue save twice;
the database still keeps one sale, but the second attempt escapes as an unhandled error. It is
**reported, not fixed**, with a one-line fix proposed, and its test is skipped until the project
lead rules. No product, schema or server change. **Slice 6 is not started.** See *Phase 8
Slice 5* at the end of this file.

Previously: **2026-10-01** — **PHASE 8 SLICE 4 — EXPENSE LEDGER PROFILING, PAGINATION
AND READ-PATH HARDENING: COMPLETE (D-323, D-324).** The Expense ledger now reaches every
matching expense. It used to show the newest 100 and stop, and it filtered by sync state only
inside those 100 — a device with 4,500 conflicted expenses showed one. Every filter now runs
before the page is cut, "Load more" adds 50 at a time and says when more exist, the order is
total, and a page costs 4 statements instead of 154. Local schema **v22** adds four indexes (no
table or row change): on the real encrypted Windows database at five years of data a page went
from 17.0 s to 2.3 ms. LIMIT/OFFSET is kept; keyset was not needed. The server expense-read
residual was measured on the reads production actually issues — one document each, 0.5–4 ms —
and **no server change** was made. Raw error text is gone from the expense entry, ledger and
detail screens. **Slice 5 is not started.** See *Phase 8 Slice 4* at the end of this file.

Previously: **2026-10-01** — **PHASE 8 SLICE 3 — RETRY AND HANG HARDENING: COMPLETE
(D-322).** A refresh no longer looks idle or frozen while what it needs retries. Riverpod 3.4.2
retries a failed provider for 38 s, holds an awaited `.future` pending throughout, and never
re-runs a provider nothing watches — so a P&L or dashboard refresh whose inputs could not be read
sat idle for 38–76 s or for ever, a local failure after it started left it "running" for good,
and the owner-settlement refresh stayed "synchronising" permanently. Refreshes now read their
inputs once, are running before they await anything, and publish a plain failure at once;
derived, lock-held and font providers answer once; Try again reaches the failed input. No
schema, server, paging, finance or authorisation change. D-248 stays unconfirmed and its
diagnostic stays. **Slice 4 is not started.** See *Phase 8 Slice 3* at the end of this file.

Previously: **2026-09-30** — **PHASE 8 — THE D-318 REDESIGN: BUILT, PROVEN AND MEASURED;
D-318 CLOSED (D-320, D-321).** Reporting no longer evaluates a per-row authority predicate,
a one-property report reads only its property, and synchronisation is paged with no
historical cutoff. Row identity is proven exactly (238 of 238 checks, 1,833,274 rows, every
control red). At STRESS no page exceeds 3.1 s against the 8 s timeout, and a whole five-year
first sync takes about 30 s where the first paged body took 19–32 minutes. Four server
migrations, no local schema change. **Slice 3 is not started.** See *The D-318 redesign* at the
end of this file.

Previously: **2026-09-29** — **PHASE 8 SLICE 2 — D-186 SERVER PROFILING: MEASURED, STOPPED
AT THE APPROVAL GATE.** The expense reporting predicate costs ~0.335 ms per expense row on
krishna-mis-dev. At CURRENT volume every reporting path is under 1.1 s. At SCALE a financial-year
report and every reporting sync exceed the 8 s `authenticated` statement timeout (demonstrated);
at STRESS a first full sync exceeds PostgreSQL's 256 MB `jsonb` limit (demonstrated). A server
change is justified; **none was made** — the redesign in D-318 awaits the project lead. The
harness is `tool/perf/` (D-319). The Expense ledger pagination ruling for Slice 4 is recorded
(D-317). **Slice 3 is not started.** See *Phase 8 Slice 2* at the end of this file.

Previously: **2026-09-29** — **PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: STARTED.**
Slice 1 (governance and baseline harnesses) is complete: the project lead's rulings (D-312), the
measurement contract (D-313, `ARCHITECTURE.md` §52), the paging documentation corrected to
LIMIT/OFFSET (D-314), D-223 disposed of without a schema change (D-315), and the unbuilt
damaged-database recovery recorded (D-316). No schema, index, server or behaviour change.

Previously: **2026-09-28** — **PHASE 7 — EXPORT, PDF & PRINTING: COMPLETE AND FORMALLY CLOSED
at Slice 11** (D-311). Slices 1–11 are closed; the project lead's U.4 manual review passed.
Phase 7 added no schema, migration, RPC or reporting-cache change. The closure record, evidence
and carry-forwards are *PHASE 7 — EXPORT, PDF & PRINTING: COMPLETE AND CLOSED* at the end of
this file. **Phase 8 — Production Hardening: not started.**

Previously: **2026-09-28** — **PHASE 7 SLICE 10 — FULL LOCAL ACCEPTANCE: COMPLETE.** Every
gate passed in the real applications:
- Windows export, authority and print phases in the real executable;
- the Galaxy A06 share phase over USB;
- Microsoft Excel and PDF review;
- host suite **2,974 passed**;
- clean artefacts scanned.

Three product defects were found and fixed, each in its own commit:
- a file open in Excel was reported as a refused folder (`2839b52`);
- **printing froze the next Save As** (D-308, `99f0177`);
- **a print went through after `reports.print` was withdrawn** (D-309, `c91d188`).

**Slice 11 (closure) is not started.** See *Phase 7 Slice 10* at the end of this file.

Previously: **2026-09-25** — **PHASE 7 — EXPORT, PDF & PRINTING: IN PROGRESS.** Slices 1–9
are complete (D-290 … D-307):
- the Windows Export Centre with Save As;
- Windows printing;
- the Android P&L PDF share;
- the three analysis exports.

**Slice 10 (full acceptance) is not started.** It waits for the project lead's review of the
Slice 6–9 checkpoint. The export contract is `ARCHITECTURE.md` §51. See *PHASE 7 — EXPORT, PDF
& PRINTING* at the end of this file.

Previously: **2026-09-25** — Slices 1–5 complete; 6–9 next.

Previously: **2026-09-25** — **PHASE 7 — EXPORT, PDF & PRINTING: STARTED.** Slice 1
(governance) is complete.

Previously: **2026-09-25** — **PHASE 6 — DASHBOARD & ANALYTICS: COMPLETE AND FORMALLY CLOSED at
Slice 11** (D-289). Slices 1–11 are closed. The feature inventory, decision dispositions,
evidence, backend baseline and carry-forwards A–F are in *PHASE 6 — DASHBOARD & ANALYTICS:
COMPLETE AND CLOSED* at the end of this file. **Phase 7 — Export & Printing: not started.**

Previously: **2026-09-25** — **PHASE 6 SLICE 10 — FULL ACCEPTANCE: CLOSED.** Every gate passes:
- Windows, emulator and live acceptance;
- `p6-android-dashboard` and `p6-android-authority` on the physical Galaxy A06;
- the 20-item manual checklist (§S.3), **20/20 PASS**, reported by the project lead;
- builds and secret scans.

The backend is exactly at baseline. Money never shrinks to fit (D-286), and the layout test
now measures the real empty line. The phone's USB/ADB problems were acceptance
infrastructure (D-288). **Slice 11 (Phase 6 closure) is not started.** See *Phase 6
Slice 10* at the end of this file.

Previously: **2026-09-24** — **PHASE 6 SLICE 10 — AUTOMATED GATES DONE, NOT FORMALLY
COMPLETE**. The A06 phases and §S.3 were outstanding.

Previously: **2026-09-23** — **PHASE 6 SLICE 9 — DRILL-DOWN INTEGRATION: COMPLETE**.

* Dashboard and analytics figures now open the existing Phase 5 read-only drill-down, or the
  existing P&L.
* One shared adapter serves Windows and Android. It hands over canonical ids and the exact
  resolved range, never a figure, and the destination re-checks authority (D-281 … D-285).
* The D-280 Overview fixture is corrected.
* **One point is flagged for the project lead:** a hand-off replaces the P&L's current selection
  with a Custom range.
* Slices 1–9 of Phase 6 are done. Slice 10 (full acceptance) is not started.
* **The physical Android pass remains PENDING** for Slice 10 (D-230, checklist §R.2).

See *Phase 6 Slice 9* at the end of this file.

Previously: **2026-09-23** — **PHASE 6 SLICE 8 — WINDOWS ANALYTICS SECTIONS: COMPLETE**
(D-277 … D-280).

Previously: **2026-09-23** — **PHASE 6 SLICE 7 — ANDROID HOME DASHBOARD: COMPLETE**, with one
real layout defect found by rendering at a raised font scale (D-276).

Previously: **2026-09-22** — **PHASE 6 SLICE 6 — WINDOWS OVERVIEW DASHBOARD: COMPLETE**,
with D-269 resolved by the project lead in favour of the composed ranked lists.

Previously: **2026-09-17** — **PHASE 5 — P&L / MIS REPORTING: COMPLETE AND FORMALLY
CLOSED at Slice 12**, with Owner Accounts OA-1 … OA-3 inside it. Slices 1–11 are closed, the
physical Galaxy A06 acceptance is done — automated phases by the suite, the ten manual checks
by the project lead on 17 September 2026 — and Slice 12 carries one approved code change, the
acceptance database-key isolation (D-249). **PHASE 6 — DASHBOARD & ANALYTICS: STARTED
(2026-09-17).** Slices 1 (governance) and 2 (exact comparison domain rules) are complete;
see *PHASE 6* at the end of this file.

**Read the *end* of this file first.** It holds the Phase 5 closure record: the feature
inventory, the slice and OA table, every total, the backend baseline, and the carry-forward
classification that says which later phase owns each remaining item. Everything above that
record is running history, in the order it was written, and **a statement in it describes the
moment it was made, not today** — where an older section disagrees with the closure record,
the closure record wins.

Phase 0 … Phase 4 are closed; Phase 4 closed at `96fc4ed`. Phase 5 delivered the canonical
calculation specification, both reporting engines and their parity, the canonical reporting
cache and its cross-device delta, the server reporting boundary, freshness and as-of
semantics, the reporting capability model, the Windows and Android P&L surfaces, read-only
drill-down, and the Owner Accounts ledger, settlement engine and preview surface.

> A new session should be able to read this file and know exactly where work stopped.
> This file — not chat history — is the checkpoint.

---

## Current phase

**Phase 9 — Production Release, Deployment & Go-Live: IN PROGRESS (started 2026-10-03).** Slices 1
(governance and production inputs), 2 (release-build hardening, D-346, D-347) and 3 (pre-release
UX wording, D-348, D-349) are complete; Slices 4–9 are not started. Its record is *PHASE 9* at the
**end** of this file. *(This read "Slice 1 is complete; Slices 2–9 are not started" until Slice 2,
and "Slices 3–9 are not started" until Slice 3.)*

**Phase 8 — Performance, Hardening & Recovery: COMPLETE and formally closed (2026-10-03, Slice 9,
D-333).** Its authoritative record is *PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: COMPLETE AND
CLOSED* at the **end** of this file. **Phase 9 — Distribution: not started.** *(Superseded wording,
kept:)* Phase 8 — Performance, Hardening & Recovery: IN PROGRESS (started 2026-09-29). Slices 1 and 2
are complete, with the approved D-318 redesign built and D-318 closed (D-320, D-321); Slice 3
(retry and hang hardening, D-322), Slice 4 (the Expense ledger, D-323, D-324) and Slice 5
(global missed-tap hardening, D-325) are complete; D-326 is fixed; Slice 6 (export performance, D-327) is closed on Windows and the Galaxy A06; Slice 7 (stress, failure and recovery, D-328 … D-330) is complete; Slice 8 (Windows and Galaxy A06 acceptance, D-332) is complete. Slice 9 is not started. Its record is
*PHASE 8* at the **end** of this file. *(This paragraph read "Slice 1 is complete; Slices 2–9
are not started" until Slice 2, "Slices 3–9 are not started" until Slice 3, "Slices 4–9 are not
started" until Slice 4, and "Slices 5–9 are not started" until Slice 5.)*

**Phase 7 — Export, PDF & Printing: COMPLETE and formally closed (2026-09-28, Slice 11,
D-311).** Its authoritative record is *PHASE 7 — EXPORT, PDF & PRINTING: COMPLETE AND CLOSED* at
the **end** of this file. **Phase 8 is not started.** *(Superseded wording, kept:)* Slices 1–10
were complete; Slice 10 (full local acceptance) closed on 2026-09-28. Slice 11 (closure) was not
started. *(This paragraph read "Slice 10 waits for the project lead's review" until Slice 10.)*
*(Earlier wording, kept:)* Slices 1–5 are
complete through Slice 9. Slice 10 (full acceptance) waits for the project lead's review.
*(This paragraph read "Slices 1–5 complete; 6–9 wait for review" until Slice 9, and "Slice 1
… complete; Slice 2 is next" until Slice 4.)* Its record is *PHASE 7 — EXPORT, PDF & PRINTING* at the **end** of this
file. *(This paragraph read "NOT STARTED" at the Phase 6 closure; that statement is superseded.)*

**Phase 6 — Dashboard & Analytics: COMPLETE and formally closed (2026-09-25, Slice 11).** Its
authoritative record is *PHASE 6 — DASHBOARD & ANALYTICS: COMPLETE AND CLOSED* at the **end**
of this file. *(This paragraph read "IN PROGRESS … Slice 3 is next" from 2026-09-17 until the
closure; that statement is superseded.)*

**Phase 5 — P&L / MIS Reporting: COMPLETE and formally closed (2026-09-17).** Its
authoritative record is *PHASE 5 — COMPLETE AND CLOSED*, just before the Phase 6 section.

*The paragraphs that follow were written while Phase 4 was the current phase and are kept as
running history.*

**Phase 4 — Revenue Engine: COMPLETE (2026-09-07).** See *PHASE 4 — REVENUE ENGINE:
COMPLETE* further down, which is the authoritative closure record for that phase. Everything
below this line up to that section is the running history of Phases 2 to 4 in the order it
was written, and **a statement in it describes the moment it was made, not today** — where
it disagrees with the closure record, the closure record wins.

**Phase 2 — Masters & Permissions: COMPLETE**, plus one acceptance addendum accepted
afterwards (D-058, D-059) that closed the single gap the completion report recorded as
*Not tested*: the Windows offline transport path. The Phase 2 commit `1ba1e3a` is not
rewritten; the addendum is its own commit.

Every gate passed, including the ones that can only be passed by running the real signed
application: the Android package on a device, and the compiled Windows executable, both
against the real `krishna-mis-dev` project, with the real development identities.

**Phase 4 — Revenue Engine: IMPLEMENTATION UNDER WAY. Slices 1–10 of 14 complete**, together with four corrective audit points closed against Slice 4 (A0 … A3).

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

**Slice 10 — revenue correction and void: COMPLETE, acceptance included.** The three
phases the first checkpoint reported as NOT RUN — §44 two-client, §45 real Android, §46 real
Windows — have now been run, and they found **two defects that every layer below them
reported as working**. Both are fixed at the owning layer, both carry a control that was
seen to fail, and both are recorded in full (D-130, D-131).

That is the whole argument for the phases existing, so it is stated first rather than
buried: Slice 10 reached a clean analyze, a green host suite, a green widget suite and a
green live boundary suite **while a conflict was unresolvable through the shipped path and
the detail panel reported `Synced` for a sale in conflict.**

**`revenue_update` is not a copy of `expense_update`, and the migration says why at the top
of the file (D-124).** Three decisions came out different. The server **re-resolves the
tax** against the entry's category and its new business date, compares the client's declared
figures and refuses `KM030` on disagreement rather than replacing them (D-114) — proven both
ways on the real server. **Both the source and the target period are checked**, because
moving an entry out of a closed month affects that month's totals as surely as moving one
in; `expense_update` checks only the target, which is recorded as a gap rather than changed
inside a revenue slice (D-127). And the **business unit and revenue category are not
parameters at all**, so a correction that moved revenue between properties is unavailable
rather than guarded — an argument that does not exist cannot be forgotten later.

**A revenue document has at most one queued intent (D-125).** The expense shape — a fresh
update intent every edit — has two reachable failure modes: a correction to a sale whose
create then fails transiently arrives first, finds no document and is refused `KM015`,
*terminal*; and two corrections before either syncs share one base version, so the second
conflicts with a version its author never saw. A correction therefore rewrites the queued
intent in place, keeping its mutation id, its actor and its creation time, so idempotency,
ownership and retention all still key on the same values. **Positive control:** with the
coalescing removed, three of the twenty-one repository tests fail.

**Nothing merges, and Review latest goes in one direction (D-126).** A stale row version and
a tax mismatch both surface as `Conflict / Attention Required`, because both are two
defensible answers with nobody entitled to overwrite the other. The only forward action
re-reads the sale, replaces the local copy — **refused while an intent may still be
delivered, permitted on a conflicted or rejected one, where the attempt survives in that
intent's own payload** — shows both sets of figures, and reopens the form on the *current*
record. The intent is never deleted, and there is no "overwrite anyway" anywhere in the
surface.

**D-130 — a correction re-applied after Review latest was refused for ever.** The
coalesced intent kept the row version it had already been refused on, so the operator's
deliberate second correction — made against the version the record now held — was refused as
stale again. Every layer was individually right: the server was right to refuse a stale
version twice, the repository was right to coalesce, the widget was right to offer Review
latest. The defect lived in the **sequence**, which needs two clients and a real server to
exist at all. A rewritten *update* now carries the base version of the correction being
written; a rewritten *create* still carries none. Not a rebase: the value comes from the
draft the form opened on, which `copyWith` cannot move.

**D-131 — the panel and the ledger derived one fact two ways.** The ledger joins the outbox
on the document's id; the detail panel joined on `pending_mutation_id`. On the accumulated
Windows database that pointer was null for a document whose correction had just been
refused, so the panel showed **Synced**, with no conflict banner and no Review latest — the
operator's one signal that their work needs attention, missing from the surface that exists
to show it. There is now one derivation, and it is a **stream**: a conflict arrives from the
sync worker, which invalidates no provider and knows about no screen, so a cached snapshot
went on being wrong indefinitely. `revenueDetailProvider` follows the same stream, and the
panel keeps its loaded content while re-reading rather than flashing a spinner — which is
how the staleness was noticed at all.

**Response loss is proven by losing a response (D-132).** `ControllableTransport` gained a
mode that sends the request, lets the server answer, drains the body and *then* throws the
platform's own `SocketException`. The server has committed; the client knows nothing.
A duplicate RPC call would have proven idempotency and nothing about recovery.

**`revenue.edit.all` gives revenue the split expenses have had since D-072a (D-128).** A
Manager corrects what they recorded; an Accountant corrects anybody's. Granted to exactly
the roles holding `expense.edit.all`. The catalogue row is a literal rather than a select
from `revenue.edit`, because the parity assertion refused the select form — a reviewer has
to be able to read the category where it is written.

**The edit window is proven in both directions**, which is the half that is easy to skip: a
manager corrects their own entry from yesterday (permitted), their own from June (refused
`KM021`), and the Owner then corrects the same June entry under
`transaction.correct.beyond_window`. A test asserting only the refusal cannot tell *"the
window works"* from *"the manager can never correct anything"*.

**Two documented surfaces that do not exist, surfaced and not silently fixed (D-127).**
`expense_correct_business_date` is named by three canonical documents as one of the reviewed
RPCs every financial write goes through — and there is no such function in the repository,
in `lib/`, or on `krishna-mis-dev`. The capability is not missing (both update RPCs take a
business date and re-check the period and window when it moves); the separately named
endpoint is. And `transaction.correct.business_date` is a capability granted to two roles
and **evaluated by nothing** anywhere in `public` or `app`. Both are about expenses, so
neither is changed inside a revenue slice.

**Two corrections found by writing the tests (D-129).** `voidLocally` threw where it should
refuse — a blank reason, an already-voided sale and a sale whose create is still queued are
all things a person can act on, and an exception reaching a widget is either a crash or a
message nobody can use. And the detail panel took its sync state from whichever ledger query
happened to have run, which on Android is none, so a phone would have reported `Synced` for
everything.

**Slice 10 ships no attachment control and no reporting.** Those are Slices 11 and 12, and a
test asserts the detail surface offers neither.

**Slice 9 — Windows revenue ledger: complete.** Sales sit beside Expenses under
Transactions, chosen by a segmented control, which is the desktop information architecture
spec §19 lays out. Both ledgers stay mounted, so a filter a finance user spent a minute
assembling survives a glance at the other tab. **63 new host tests**, 1,014 in total.

**Filtering, ordering and paging all happen in SQL (D-121).** `RevenueRepository.query`
takes an interface the presentation implements, so the data layer never learns a filter bar
exists. Ordering is `business_date desc, captured_at desc, id desc` — the third term is not
decoration, because two sales in the same second have no defined order without it, and an
undefined order across a page boundary is how a row gets shown twice or skipped. Dates
filter on the **business date**, never the capture instant: a sale rung up at 02:00 belongs
to the previous trading day, and filtering on `captured_at` because it is convenient for
SQL would put it in the wrong month of somebody's report.

**Scope is authority, applied in SQL, and is not a filter.** `Clear filters` deliberately
cannot drop it. Quarantined work is excluded by the *first* predicate in the builder,
before any filter is considered, and tests assert that no status filter, no search and no
include-voided toggle can surface a retained attempt — while its own actor still reaches it
through the dedicated workflow (D-070, D-074).

**The detail panel explains a sale from the sale (D-122).** Nothing re-queries today's tax
configuration; every rate, treatment, basis and band comes from the component's own
snapshot. Proven by deleting every rule and finding the panel unchanged. `none` and a
configured `0%` both give ₹0 and are shown differently — **No GST** against **GST at 0%** —
because one is a treatment somebody chose and the other a rate somebody set. Multiple
components are listed separately with their own bands and rates, then the document totals;
two tariff bands are never flattened into one rate that was applied to nothing.

**Two layout defects, both of the family Slice 8 recorded (D-123).** A filter dropdown
overflowed by 221 pixels because `DropdownButtonFormField` lays its selected item out at
natural width. And the table's minimum width had been written down as `940` beside columns
summing to `1204`, so the header overflowed by 211 pixels on an ordinary laptop — it is now
derived from the column widths, so the two cannot disagree again. The widget suite renders
the ledger at three window sizes **in every sync state**, because the states differ in
width and the dangerous one is the one an operator most needs to read.

**Real Windows acceptance, in the compiled `krishna_mis.exe` against `krishna-mis-dev`.**
All four verified categories recorded through the shipped desktop screen, synced, given
distinct `KI-REV-…` numbers at exactly the parity paise, and reconciled onto the same rows
rather than new ones; filtering and paging asserted against the repository; the Banquet
panel showing **No GST** and the Restaurant panel **GST at 5%**; and a sale recorded with
the transport offline that syncs once on reconnect with no number invented. The D-070 and
D-074 regressions and the Windows expense ledger phase were re-run on the accumulated
Windows database — the persistent installation that exposed D-074 in the first place, and
the honest one. Fixtures reversed by void; the verified four-rule baseline verified pristine
with zero bands, subtypes and statuses.

**Slice 9 ships no correction, no void UI, no attachment control and no reporting.** Those
are Slices 10 to 12, and a test asserts the detail panel offers none of them.

**Slice 8 — Android revenue entry: complete.** The evening workflow is four taps and a
number: property → category → amount → Save. It is built on the Slice 7 repository and
adds no second calculation path, no direct Supabase call from a widget, and no tax
arithmetic in the interface — every figure in the live breakdown comes from
`TaxRule.compute`, which is the call the repository makes when it writes and the one
`app.revenue_compute` is proven equal to. **63 new host tests**, 951 in total.

**The form's shape is read from the configuration, not written in code (D-118).** The
screen asks the resolved rule set which value bands apply for this category on this
business date. None gives one plain amount field — which is every verified category today
— and two give two labelled fields carrying the band identities the operator states. A
second Room band is therefore a configuration change and a sync, not a release, and that is
asserted rather than claimed. No threshold is a constant anywhere in the widget layer, and
nothing compares an amount against a band's bounds (D-094).

**Banquet is never told it contains GST.** The amount label takes the treatment as well as
the basis (D-097), so an untaxed category reads *"Amount billed to the customer"* and the
breakdown says **No GST** rather than "GST ₹0" — the first is the statement the
configuration makes, the second reads like an amount that happened to come out at nothing.
Proven on the real Android client, not only in a widget test.

**D-112 has a user experience, and it distinguishes three things.** Fresh configuration
warns about nothing. Expired configuration refuses new sales and offers a refresh, because
"connect and try again" is only worth saying when trying again might work. A device clock
that cannot measure the age says so in its own words. A test asserts that no refusal
message contains `KM0`, `D-112`, `snapshot`, `SQL`, an exception name or a table name.

**Three defects the surface exposed, none of them visible below it (D-119).** An infinite
rebuild loop, found as a `pumpAndSettle` timeout rather than by reading — on a phone it
would have presented as heat and a flickering form. A five-pixel overflow on a 430pt screen
in the conflict state, which is the one an operator most needs to read, and which a
screenshot would have shown as correct because the money still fitted. And a screen that
called `Navigator.pop` unconditionally, which is true in production and asserts the moment
the page is not pushed.

**And one duplicated rule removed rather than kept in step.** `RevenueRepository` mapped
outbox status to a user-visible state with its own `switch`, and the copy had already
drifted — it called a `blocked` queue a failure where the canonical
`OutboxStatus.userVisibleState` calls it pending, because a queue paused on an
authentication problem has not failed at anything. Two surfaces describing one entry
differently is not a risk worth carrying for a `switch` statement.

**Real Android acceptance, on the emulator against `krishna-mis-dev`.** All four verified
categories recorded through the shipped screen and controller, synced, and given distinct
`KI-REV-…` numbers at exactly the parity-vector paise; Banquet's label and its **No GST**
line proven on the device; and a sale recorded with the transport offline, shown as not
yet synced, pushed once with no number invented, then reconciled to a single canonical row
on reconnect. Fixtures reversed by void; the verified four-rule baseline verified pristine
with zero bands, subtypes and statuses.

**Slice 8 ships no Windows revenue ledger, no edit or void surface, no attachment control
and no reporting.** Those are Slices 9 to 12, and a test asserts the entry surface does not
grow into them.

**Slice 7 — revenue create workflow: complete.** Draft → eligibility → deterministic
local resolution → one atomic write → outbox → `revenue_create` → reconciliation, working
online, offline within the D-112 window, after restart, after response loss and under
repeated retry. Revenue is a **registered mutation type in the existing transport** — one
outbox, one worker, one backoff clock, one actor filter — not a second sync engine.
**65 new host tests**, 888 in total.

**D-112 is answered and implemented.** The project lead set the window at **24 hours from
the server-confirmed timestamp**, inclusive at the boundary, per user and per business
unit, with no Owner or Accountant override — it is a tax-correctness gate, not a privilege
gate. A device clock reading materially *earlier* than the server's own confirmation fails
closed with its own reason, because a backwards clock would otherwise make every snapshot
look newly fresh. Expiry touches nothing that already exists: an attempt created at 10
hours and still pending at 30 is submitted unchanged, carrying its own snapshot, and the
server decides.

**Revenue is checked before it is written (D-113).** Unlike an expense — whose correctness
does not depend on configuration the device might lack — a revenue figure's does, so the
whole contract is evaluated before anything is persisted: authority, unit, category under
that unit, open period, complete and fresh configuration, exactly one resolvable rule per
component, every required conditional fact. Seventeen structured refusal reasons, each
naming a different thing to do about it, and a test asserting no refusal message contains
an exception, a SQL state, a table name or a refusal code.

**The client declares what it showed the operator; the server refuses if it disagrees
(D-114).** `revenue_create` always computed its own figures and ignored the caller's — and
returned nothing about the money, so a client could not learn that its own differed. An
entry prepared under a rule that had since changed would have been accepted while the
operator's approved figure quietly became something else. Optional `declared_*` values are
now **compared, never used**, and a mismatch is `KM030` — surfaced as a **conflict** a
person resolves, exactly as a stale row version is, because two defensible answers exist
and neither may overwrite the other silently.

**Two Slice 4 defects, both found the first time something exercised the path.**

* **D-115 — `revenue_create` had never successfully created a revenue entry.**
  `app.next_revenue_number` declared an OUT parameter named `financial_year`, which
  collides with the column in its own `on conflict` target: *column reference
  "financial_year" is ambiguous*. Every call failed after all validation and after the
  inserts, at the point a number is issued; the transaction rolled back, so nothing was
  corrupted and nothing worked. It survived Slice 4's thirteen live tests because those
  proved the **boundary** and never called the function whose job is to record revenue.
* **D-116 — the revenue projections named a capability no role holds.**
  `revenue_document`, `revenue_component_detail` and the `revenue_entries` read policy all
  required `revenue.view.all`, which does not exist; the catalogue holds `revenue.view`.
  The only sanctioned way to read revenue returned nothing to anybody, including the Owner.
  The same defect D-110 recorded for the premises-status policy, in three more places,
  invisible because empty datasets make *"a scoped user sees less than the Owner"* pass
  when both see zero. **The class is now closed by a general assertion** that every
  capability named by a revenue policy or projection is actually granted to some role — and
  it earned that on its first run, refusing the fix until the policy it had missed was
  corrected too.

**Live acceptance ran the real repository and worker**, not the RPC directly: all four
verified categories recorded, synced, and received distinct `KI-REV-…` numbers at exactly
the parity-vector paise; a redelivery of the same intent replayed to the same number with
one canonical row; and the mismatch contract refused with a sentence carrying no
implementation detail. Fixtures reversed by void, and the verified baseline verified
pristine afterwards.

**Slice 6 — revenue ReferenceSync: complete.** The proven Phase 2 sync is extended, not
duplicated: the same authority-first ordering, the same purge, the same one-transaction
write, the same freshness vocabulary. It gains three datasets — value bands, supply
subtypes, premises tax statuses — and **the four v1.2 rule columns it had never carried**,
which was a defect rather than an omission: `input_basis` is NOT NULL on the server since
A1, so a sync that dropped it produced a rule the resolver classifies as `incompleteRule`
and refused every revenue entry, on a device whose configuration had in fact arrived
intact. No sync error, no failed request. **27 new host tests**, 823 in total.

**The completeness marker was rebuilt before any transport was written (D-108).** Slice 5's
single global `app_meta` key claimed the whole organisation's configuration was
authoritative. Local schema **v12** replaces it with `revenue_config_snapshots`, keyed
`(user, business unit)` and naming the datasets proven present, the server generation and
the server-confirmed time. Synchronising Crystal Canopy no longer vouches for Hotel
Krishna; one person's sync no longer vouches for the next person on a shared workstation;
and tax rules arriving no longer vouches for bands, subtypes and statuses. A revocation
**downgrades** the record rather than deleting it, which is what makes D-106's `revoked`
gap reachable at all — in Slice 5 both call sites hard-coded `neverSynchronised`, so that
distinction lived in the type and never in the behaviour.

**A complete snapshot is defined**, and the marker is written **last, inside the same
transaction** as the writes: a run that fails anywhere rolls back the claim with the data.
Zero bands, zero subtypes and zero statuses is a legitimate synchronised answer — the
verified baseline has exactly that — and stays distinguishable from never having asked,
which is why the record stores a dataset list rather than counting rows.

**Three latent defects in Slice 4's read boundary (D-110), found by auditing it before
synchronising through it.** `business_unit_tax_statuses_read` required `revenue.view.all`,
a capability **no role holds**, so it could never be satisfied by anybody — the moment a
premises status were configured it would be unreachable by every client. The band and
subtype policies were organisation-wide, so a Crystal Canopy manager could read Hotel
Krishna's configuration. All three now say what the tax-rule policy says, and the migration
asserts the capability they name is actually held by somebody.

**And one defect this slice introduced and caught (D-109).** The first fix pointed those
policies at a helper in `app`, which `authenticated` cannot execute — a policy runs with
the caller's privileges — so every band and subtype read failed and took the whole pull
down with it. **This is D-045 exactly**, and the invariant added at the time did not catch
it because it matched the schema name in a policy expression rather than asking whether a
policy could actually be evaluated. Found by the live sync writing an empty database, not
by review. The helper is published, the API surface is restated, and the assertion is now
the general one.

**A stale claim is withdrawn on every confirmed pull (D-111).** The purge diffs against the
previously stored authority, which is correctly per user — so on a shared installation
`A syncs, B syncs, A syncs narrower` produced no diff and left A claiming a property A no
longer held. A confirmed pull needs no diff: `pullAll` asks for everything and RLS decides,
so the units it returns *are* the current scope. A **failed** pull still withdraws nothing.

**D-112 is answered.** Slice 6 raised the question and did not default it; the project lead set the window at **24 hours**, and Slice 7 implements it.

**Slice 5 — offline revenue tax resolution from cached configuration: complete.**
`RevenueTaxRepository` is an adapter, not a second engine: it reads the Drift cache,
reconstructs the domain model and hands the decision to the resolver Slice 2 already
proved. No tax semantics are expressed in SQL and nothing is defaulted on the way through.
**33 new host tests**, and the cache is asserted read-only by counting rows either side of
every resolution rather than by reading the code.

**The distinction the slice exists for.** An empty rule query means two different things —
the configuration is synchronised and has no rule for these facts, or this device has never
received one — and collapsing them is how an empty cache starts telling a manager that
their company's tax is not configured. `configurationUnavailable` is now a first-class
outcome decided **before** the cache is queried, evidenced by a synchronisation marker
rather than a row count, and carrying whether the gap is `neverSynchronised` or `revoked`
(D-106). A confirmed revocation therefore stops new offline revenue outright; an
already-recorded component is untouched, because it carries its own snapshot and consults
no cache — proven by deleting every rule and reading the component back.

**A real production defect, found by writing the suite (D-104).** `EnteredBasis` was
persisted and parsed through Dart's `.name` (`inclusiveTotal`) while both schemas store
`inclusive_total`, verified against the four live rules. Every rule carrying a basis would
have thrown on read — which, since A1 made the column NOT NULL, is every rule that exists.
It survived Slices 2 to 4 because nothing had yet read a rule out of a database into the
domain model: the Slice 2 tests built `TaxRule` objects directly and were checking Dart
against itself. The stored form is now stated explicitly and pinned in two places that
cannot be edited to agree with each other — a host test on the exact strings, and a live
test that reads the real column.

**Three engines, thirteen vectors, exact paise (D-105).** The vectors live once, in
`20260901144002_revenue_arithmetic_parity.sql`, which asserts them against
`app.revenue_compute` and **fails the deploy** rather than warning — the pattern migration
0033 established for the business-date rule. The Dart suite parses that same table, so
neither side can be edited alone, and refuses to run on fewer than ten vectors because a
parity suite that silently checks nothing reports success. They are chosen where rounding
decides something: one paisa, seven paise, thirty-three paise, an amount past 32-bit, a
configured 0% beside a treatment of `none`, and both exclusive cases. **13 of 13 agree
exactly and all 13 reconcile.** Positive control: the same assertion with one figure moved
by a single paisa raises.

**Slice 4 audit corrections (A0 … A3), all four closed.**

* **A0 — migration ledger parity.** The Slice 4 report claimed "seven migrations, all
  committed" while the repository held two files for seven ledger versions. Split into
  seven files with `supabase/migrations/LEDGER.md` accounting for all 49 applied versions —
  and then made **mechanical**, because a hand-maintained table drifts exactly as the API
  surface list did (D-102). It immediately caught two things: the A1 and A2 migrations had
  been applied and never committed, and the parity file was named for the version I
  intended rather than the one Supabase assigned.
* **A1 — legacy write paths could create an unusable rule.** Proven by probe: a successor
  inserted without `input_basis` was accepted, after which the resolver refused every entry
  against it. No legacy rows existed (4 live, 0 null), so the honest expression is NOT NULL
  with no exception to explain; the two Phase 2 creators now refuse with KM029 naming their
  replacement.
* **A2 — premises status was not deterministic.** Proven by probe: two open-ended rows
  starting on different dates were **both** applicable on 2026-08-01. Resolving that by
  "latest start wins" would be the ranking D-094 forbids. Fixed with `effective_to` and an
  `EXCLUDE USING gist` constraint — which fully models it here, unlike the tax rules,
  because a status has no wildcard discriminators.
* **A3 — local/server band lifecycle parity.** `superseded_by_band_id` was already local;
  the status table gained `effective_to` and `archived_at` to match the server.

**Slice 4 — authoritative Postgres schema, RLS, RPC boundary and the verified baseline:
complete.** Applied to `krishna-mis-dev` as seven migrations, all committed. Five tables,
the `revenue_document` / `revenue_component_detail` projections, four reviewed RPCs, the
server resolver with integer half-up arithmetic proven equal to Dart's, KI-REV numbering
on its own FY-reset sequence, and the **verified FY 2026-27 baseline** — Restaurant 5%,
Nandbhog 5% (independent), Room 5% generic with **no invented band**, Banquet `none` —
resolved by canonical codes with no environment UUID and failing loudly on an ambiguous or
misplaced master. **13 live revenue tests** (11 at the Slice 4 checkpoint, plus the two
parity tests D-104 and D-105 added), 789 host tests.

**The concurrency work is the substance of this slice.** D-095 predicted that one
exclusion constraint could not enforce the doctrine, and it was right: `=` treats two
NULLs as non-conflicting, which is the opposite of what a wildcard means. The
implementation is a collision function comparing **tariff ranges rather than band ids**, a
validating trigger, and a transaction-level advisory lock keyed deterministically on
`(org, category)` with `hashtextextended` — taken on the **trigger**, so no write path can
skip it, proven by a direct table write being refused.

The mandated **two-session test** runs two genuine concurrent PostgREST calls and asserts
that exactly one wins and the database never holds two rules that could both match, over
five rounds. Its **positive control** ran against transient scaffolding reproducing the
same read-validate-write shape with and without the lock: **without it 2 rows were
written, with it 1**. The scaffolding was dropped immediately — a permanently callable
lock-bypassing function would be a backdoor, so the control now self-skips and says why.

Three defects, all caught by assertions rather than by reading:

* **D-100** — the Slice 3 band model let boundaries be edited in place, which would have
  retroactively redefined what every effective-dated rule referencing that band applied
  to, for dates already recorded. Corrected in Slice 3's schema **before** it was mirrored
  to Postgres, exactly as the brief required. Bands are now write-once and superseded.
* **D-101 §1** — four new `app` functions were left executable by client roles, because
  Postgres grants EXECUTE to PUBLIC and the explicit revokes covered only the helpers that
  were front of mind. The API-surface invariant refused the migration and named all four.
  The same finding as D-044, one phase later.
* **D-101 §2** — `revenue_document` was first written `security_invoker`, so it ran with
  the caller's privileges against tables the caller deliberately cannot read: every
  authorised read failed. The proven pattern — `security_barrier` with its own predicate —
  was already in the repository.

**Slice 3 — local Drift schema v11: complete.** `revenue_entries` and
`revenue_components`, plus the three reference caches the conditional model needs —
`revenue_value_bands`, `revenue_supply_subtypes`, `business_unit_tax_statuses` — **all
shipping empty**. `revenue_tax_rates` gains `input_basis` and the three discriminators,
**none backfilled**: a pre-v11 rule has no authoritative answer for them, and writing
`inclusive_total` because every verified category happens to use it would be inventing a
business fact. Revenue reuses D-070 and D-074 rather than getting a second lifecycle; the
purge, the retention stamp, the ownership predicate and the fail-closed quarantine all
extend to it. **751 host tests** (720 + 31).

**Header totals are not stored.** `revenue_entry_totals` derives gross, tax and net from
the components, so there is no second copy to drift — SQLite has no deferred constraint
trigger, and a maintaining trigger would still leave a column a future writer could set
wrongly. A test asserts the header amount columns do not exist.

Two architecture contradictions surfaced, both asked for and both real:

* **D-098** — a value band needs its own master. Rule identity cannot serve as band
  identity, because rules are superseded by date and a band is not: the same band would
  have different ids in different periods, fragmenting reporting at every rate change and
  making the entry form's choices vanish when a rule is end-dated.
* **D-099** — the **local** unique index `ux_tax_rates_live_period` is D-093 mirrored. Two
  live rules for one category from one date is exactly what two value bands are, so the
  index would have refused configuration the server had accepted — surfacing as a sync
  failure rather than as anything a person could act on. v11 drops it, and does not
  replace it with a wider unique index, because uniqueness cannot express the doctrine
  either.

One Phase 3 fixture was completed rather than worked around: the v9→v10 attachment
migration test built a database containing only the attachments table, which no real v9
device resembles. It now carries the rule cache too.

**Slice 2 — revenue domain model and conditional tax resolver: complete.** Pure domain,
no Drift, no Supabase, no schema change. `RevenueEntry` / `RevenueComponent` and their
drafts; `EnteredBasis` beside `TaxTreatment`; and `RevenueTaxRuleSet.resolve` returning a
sealed result — resolved · noApplicableRule · ambiguous · missingFact · incompleteRule — so
the financially different failures stay different. The arithmetic is the **existing**
`TaxRule.compute`; no second tax calculation was written. **720 host tests** (674 + 46).

**Slice 2 corrective (D-097).** The project lead asked for the Banquet combination —
`inclusive_total` + treatment `none` — to be verified before Slice 3. **It already
worked**, and is now proven by four verified-configuration tests plus a positive control
that couples basis to treatment and fails five of them. Basis and treatment answer
different questions and are deliberately not coupled: `none` accepts either basis, because
with no tax the customer total and the pre-tax amount are the same number.

Two things came out of that review. `EnteredBasis.none` is **removed** — it described
nothing the other two values do not, and existed only because `TaxTreatment` has a value of
the same name. And the amount field's label now takes the **treatment** as well as the
basis, which fixed a real defect: Banquet would have been labelled *"Customer total (incl.
GST)"* on a figure carrying no GST, and nothing in the domain would have objected.

Two project-lead corrections landed before the code was written, and one of them would
have produced wrong money:

* **No most-specific-match, anywhere** (D-094). Zero or exactly one rule may match; more
  than one is refused. A `null` discriminator matches *every* value, so a wildcard rule
  **collides** with a specific one rather than losing to it. All five documents now carry
  one doctrine instead of two phrasings of nearly the same idea.
* **A value band is selected, not calculated** (D-094). The earlier design compared a
  component's amount against a rule's band bounds. A day's aggregate room revenue is not a
  per-room-per-night tariff — forty ₹1,800 rooms and five ₹8,400 rooms can report the same
  daily total — so that comparison would have chosen a rate by arithmetic that means
  nothing. **`RevenueTaxFacts` now carries no monetary field at all**, which makes the
  mistake unavailable rather than merely discouraged.

And two design records for Slice 4: **D-095**, that one PostgreSQL exclusion constraint
cannot enforce the doctrine — `=` treats two NULLs as non-conflicting, which is the
opposite of what is required — so Slice 4 combines a validating trigger with a
`(org, category)` advisory lock against the concurrent write-skew a trigger cannot see; and
**D-096**, the project lead's decision that the initial verified configuration ships as a
committed migration.

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
| ~~1~~ | ~~Spec and governance~~ **done** | Spec §8 amended, v1.2, `CLAUDE.md` and five docs, D-092, D-093, this plan | docs consistency, secret scan |
| 2 | Domain model and resolver | `RevenueEntry` / `RevenueComponent`; `entered_basis`; conditional `TaxRuleSet.resolve(facts)`; discriminator-aware `refusalFor` (D-093); reconciliation | unit tests incl. the five D-093 rows and the refusals |
| ~~3~~ | ~~Local schema~~ **done** | Drift v11: `revenue_entries`, `revenue_components`, extended rule cache, subtype and premises-status caches | migration test v10→v11, `CacheClassification` completeness |
| ~~4~~ | ~~Server schema, RLS, RPC boundary~~ **done** | tables, the **replaced** exclusion constraint, `revenue_document` projection, `revenue_create/update/void`, KI-REV sequence, audit, usage | migration audit, API-surface invariant, allow **and** deny tests |
| 5 | Offline resolution and refusal | resolver over cached config; refuse-and-queue-nothing (D-086) | repository tests |
| 6 | Sync, outbox, gateway | `RevenueGateway`, `RevenueMutationEndpoint`, `RevenuePull` | idempotency, response-loss, stale-version tests |
| 7 | Create workflow | atomic local write + outbox in one transaction | rollback-at-each-boundary tests |
| 8 | Android entry surface | unit → category → band field(s) → live gross/GST/net → save | widget + draft-model tests |
| 9 | Windows ledger and detail | dense ledger, filters, component breakdown, rule snapshot | widget tests |
| ~~10~~ | ~~Correction and void~~ **done, acceptance pending** | `revenue_update`, `revenue.edit.all`, one-intent coalescing, Review latest, void with a mandatory reason | server + local + widget tests done; §44–§46 **not run** |
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
paging (*corrected 2026-09-29, D-314: LIMIT/OFFSET, not keyset*), the detail panel, cross-period and cross-unit editors, the audit
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
`expense_update`, `expense_void`, `attachment_register` —
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
| `dart format --set-exit-if-changed` | **Tested** | clean (192 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **1,147 tests, all passing** (1,101 + 46 for Slice 11) |
| Secret scan — tree and git history | **Tested** | clean; the scan proves its own controls on every run (D-069) |
| Secret scan — rebuilt clean binaries | **Tested** | tree, git history and built artefacts all clean, with the scanner's controls passing |
| Migration audit (search_path, API surface, policy boundary) | **Tested** | 14 host tests |
| Backend schema parity (migrations vs the claims made about them) | **Tested** | 18 host tests |
| Live backend suite against `krishna-mis-dev` | **Tested** | **19 tests** across 7 phases — **re-run in the documented sequence at this checkpoint**, with the grant fixture restored to baseline afterwards (D-107) |
| Live expense suite against `krishna-mis-dev` | **Tested** | **30 tests, re-run in full at the corrective checkpoint**: reconciliation, scoped raw-cache security, period locks, the 7-day boundary, usage semantics, and the 14-case business-date correction matrix |
| Live revenue suite against `krishna-mis-dev` | **Tested** | **27 tests** (13 + 14 for Slice 10), 1 deliberately skipped: the D-095 write-skew positive control, whose lock-bypassing scaffolding was dropped rather than left permanently callable |
| Live two-client acceptance against `krishna-mis-dev` | **Tested** | **10 tests** — §44, §A3, §D, §E, §F, through the real repositories and workers |
| Revenue arithmetic parity — Dart, Drift and Postgres | **Tested** | 13 vectors, exact paise, asserted in migration `20260901144002` and read back by the Dart suite (D-105) |
| Offline revenue tax resolution from the cache | **Tested** | 33 host tests, incl. the `configurationUnavailable` distinction and a read-only census (D-106) |
| Revenue ReferenceSync — datasets, atomicity, per-scope completeness | **Tested** | 27 host tests, incl. malformed-payload rejection and the retained known-good snapshot |
| Real revenue configuration sync against `krishna-mis-dev` | **Tested** | the four verified rules with `input_basis`, 0 bands / 0 subtypes / 0 statuses, both units marked complete |
| Offline resolution after a real sync, in a fresh process | **Tested** | Restaurant, Nandbhog, Room and Banquet resolved to exact paise with no network call made |
| Revenue create — eligibility, atomic write, refusals, D-112 | **Tested** | 47 host tests, incl. the 24-hour boundary, backwards-clock fail-closed and rollback |
| Android revenue draft model — scope, filtering, cascade, preview | **Tested** | 36 host tests, incl. the two-band form shape and the untaxed label |
| Android revenue surfaces — entry, breakdown, recent list | **Tested** | 27 widget tests against the real repository and providers |
| Android revenue acceptance on the emulator, real backend | **Tested** | 3 phases: four categories numbered, the Banquet label, offline → reconnect |
| Windows revenue ledger — SQL filtering, paging, ordering, scope | **Tested** | 40 host tests, incl. no row duplicated or skipped across pages |
| Windows revenue surfaces — table, filters, detail panel, layout | **Tested** | 23 widget tests at three window sizes in every sync state |
| Windows revenue acceptance in the real `krishna_mis.exe` | **Tested** | 2 phases: four categories numbered and explained, offline → reconnect |
| D-070/D-074 and the Windows ledger on the accumulated database | **Tested** | `d068-switch`, `d068-revoke`, `windows-ledger` re-run green |
| Revenue acceptance fixture reversal | **Tested** | voided through the real API; baseline verified pristine (4 rules, 0 bands, 0 subtypes, 0 statuses) |
| Revenue transport — idempotency, response loss, restart, retry classification | **Tested** | 18 host tests against a fake server that loses a response after committing |
| Live revenue create against `krishna-mis-dev` | **Tested** | 4 categories through the real repository and worker; replay returns the same KI-REV number; KM030 refused |
| Revenue correction and void — local, outbox, coalescing | **Tested** | 21 host tests, incl. the positive control that fails three of them without the discipline |
| Revenue correction and void surfaces, both platforms | **Tested** | 14 widget tests, incl. capability-only availability and a voided sale offering nothing |
| Revenue update/void transport — dispatch, idempotency, response loss, classification | **Tested** | 12 host tests against a fake gateway, driving the real endpoint |
| Live `revenue_update` / `revenue_void` against `krishna-mis-dev` | **Tested** | 14 tests: re-resolution, KM030, KM003 both ways, KM020, KM021 with its positive control, manager refusals, replay |
| Two-client stale edit, stale void, and the voided-then-edited inverse | **Tested** | §44 — 10 live tests, two independent sessions/databases/outboxes against `krishna-mis-dev`; **found D-130** |
| Update and void response loss, against the real server | **Tested** | §A3, §E — the transport sends, the server commits, the answer is dropped on the wire (D-132) |
| Offline create → corrected twice → restart → sync | **Tested** | §D, with a control that fails in D-125's own failure mode |
| D+7 / D+8, beyond-window, closed **source** and target period | **Tested** | §F — 4 live tests, business dates under D-067 |
| Slice 10 acceptance on the real Android emulator | **Tested** | §45 — 5 phases: edit, untaxed edit, conflict, void + manager refusal, user switch |
| Slice 10 acceptance in the real `krishna_mis.exe` | **Tested** | §46 — 3 phases: edit, void with include-voided, conflict and Review latest; **found D-131** |
| D-070/D-074 and the Windows ledger, re-run on the accumulated database | **Tested** | `d068-switch`, `d068-revoke`, `windows-ledger` green after the Slice 10 changes |
| Slice 10 fixture reversal and baseline verification | **Tested** | voided through the real API; 4 rules, 0 bands, 0 subtypes, 0 statuses, 0 open revenue |
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
| Windows ledger: the complete filter surface, paging (*LIMIT/OFFSET, not keyset — corrected 2026-09-29, D-314*), scoped detail caption | **Tested** | `windows-ledger`, incl. the filter-dependency rule and a scoped share never captioned `TOTAL` |
| Two-device Android ⇄ Windows expense propagation | **Tested** | `propagate-expense-a…e`: create with a bill, correct, stale edit conflicts, void, evidence still there |
| Expense **edit** through the UI | **Tested** | `expense-edit` on both real clients: identity kept, version advanced, D+7/D+8, stale → Conflict (D-072a) |
| D-070/D-074 financial cache retention and ownership | **Tested** | `d068-switch` + `d068-revoke`, 3 on the real APK and 3 inside the real `.exe`, the Windows ones against a database that had accumulated across runs |
| Client and server agree on a business date at one instant | **Tested** | 10 host tests reading migration 0033's own assertion table |
| Payment-date accrual through the application | **Tested** | `payment-accrual`: ₹80,000 to June, ₹0 to July, paid 5 July |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | **1,147** | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | the phases this change touches re-run at the corrective checkpoint (`drift`, `conflict`, and the revenue chain, twice in succession); the four scope phases need administrative grant changes between them and were **not** re-run |
| Live expense suite against `krishna-mis-dev` (opt-in) | **50** | all passing — re-run in full at the final pre-Slice-11 checkpoint |
| Live revenue boundary suite (opt-in) | **61** | all passing, 1 deliberately skipped |
| Live two-client acceptance (opt-in) | 10 | all passing |
| **Slice 10 Android acceptance** (`revenue-edit`, `-edit-banquet`, `-conflict`, `-void`, `-user-switch`) | **5** | **all passing** |
| **Slice 10 Windows acceptance** (`windows-revenue-edit`, `-void`, `-conflict`) | **3** | **all passing** |
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

**Nothing for Slice 10.** All three phases ran and pass; the two defects they found are
fixed, regressed and controlled.

| Phase | Result |
|---|---|
| §44 two-client stale edit chain, live | **PASS** — and it found D-130 |
| §44 two-client stale void, and the voided-then-edited inverse | **PASS** |
| §A3 void response loss | **PASS** |
| §E update response loss | **PASS** |
| §D offline create → corrected twice → restart → sync | **PASS**, with a control that fails |
| §F D+7 / D+8, beyond-window, closed source **and** target period | **PASS** |
| §45 Android — edit, untaxed edit, conflict, void, manager refusal, user switch | **PASS** |
| §46 Windows — edit, void with include-voided, conflict and Review latest | **PASS** — and it found D-131 |

**From Phase 3, still nothing outstanding.**

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

---

## Phase 3 corrective — expense business date and period protection

**Recorded 2026-09-05. Audited, then APPROVED and IMPLEMENTED the same day — see
*Phase 3 corrective — expense business-date and closed-period integrity: DONE* further down,
and D-136 … D-139. The audit below is left exactly as it was written, because it is the
evidence the fix was built from, and this file records what was found as well as what was
done.**

Found while auditing the correction path before extending it for revenue (D-127), and
deliberately not touched inside a revenue slice: quietly altering the expense write path
there is how a reviewed scope stops being reviewable.

### What the audit found, each with its evidence

Evidence is the **shipped function bodies on `krishna-mis-dev`**, read directly, plus the
repository and the binding spec. Nothing below is inferred from documentation.

**1 · `expense_update` protects the target period and not the source.**

```
        expense_update                     calls require_period_open   NO
        app.validate_expense_allocations   calls require_period_open   YES
        app.validate_expense_allocations   reads expense_period_allocations  NO
        expense_void                       calls require_period_open   YES
        revenue_update                     calls require_period_open   YES  (both periods)
```

The validator only ever sees the periods in the **incoming payload**. It never reads the
contributions the expense currently has, so it cannot know where the amount is being taken
*from*. `replace_expense_allocations` then deletes those rows and writes the new ones.

An expense sitting in a **closed** month can therefore be moved to an open one, and the
closed month's Total Expenses and Operating Profit change with nobody's permission.

Spec §13.4 is explicit, and the operative word is *affecting*:

> every create, edit, void and business-date correction **affecting that period** is
> rejected server-side

Removing an amount from a closed month affects it as surely as adding one. `expense_void`
already understands this — it checks the period the expense is in.

**2 · `expense_correct_business_date` does not exist.** `PROJECT_STATUS.md`,
`ARCHITECTURE.md` (including §5.3's concurrency table, where it has its own row) and
`DATABASE_SCHEMA.md` all name it. The server exposes exactly six financial RPCs:

```
        expense_create   expense_update   expense_void
        revenue_create   revenue_update   revenue_void
```

The **capability** is not missing — `expense_update` takes `p_business_date`, the edit form
offers a date row, and a moved date re-checks the window. The separately named endpoint is.

**3 · `transaction.correct.business_date` is evaluated by nothing.** Granted to the
accountant and owner bundles; named by **0** functions and **0** policies in `public` or
`app`; no client code reads it. For contrast, `transaction.correct.beyond_window` is named
by 2 functions and works. *A rule that nothing evaluates is a comment* (D-068, D-071,
D-077), arriving as a grant rather than as a check.

**4 · A corrected business date is not marked as corrected.** `expenses.business_date_source`
exists and `expense_create` sets it. `expense_update` never writes it, so an expense whose
date has been moved still reads `derived`. Every row in the development project says
`derived`, including ones the acceptance suite moved. D-019 requires the record to note
whether the date was `derived`, `manual` or `corrected`, and spec §9 requires every
correction to be audited **with a reason** — which `expense_update` does not collect.

Finding 4 is the one that decides the shape of the fix, so it is listed last rather than
first: it is what makes a business-date correction a distinct *act* rather than just
another edited field.

### The two candidate contracts

**A · the correction lives inside `expense_update`.** This is what production already does
and what the client already offers, and it is what `revenue_update` does (D-124).

**B · a dedicated `expense_correct_business_date`.** This is what three canonical documents
describe, and it is the only shape in which the correction naturally carries its own
mandatory reason and its own audit action.

### Recommendation — A, with the correction made a first-class act inside it

One RPC, because two write paths for one document is the thing this project keeps paying
for; and revenue would otherwise need a matching second endpoint, doubling the divergence
surface rather than halving it. But the *act* stops being an ordinary field edit:

1. **Check both periods.** The source periods are read from the expense's existing
   contributions before they are replaced, and each is required open — the rule
   `revenue_update` already applies, and the one `expense_void` already applies.
2. **Require a reason when the date actually moves**, and only then. An ordinary amount
   correction is unaffected, so the fast path does not grow a field.
3. **Set `business_date_source = 'corrected'`** on that branch, which is what D-019 asks
   for and what makes a moved date visible in the record rather than only in the audit.
4. **Emit a distinct audit action** for it, so "which dates were moved, by whom, and why"
   is answerable without diffing every `edited` row's before/after state.
5. **Gate it on `transaction.correct.business_date`**, which gives finding 3 its evaluator
   instead of withdrawing a capability the project lead granted deliberately.
6. **Correct the three documents** to describe one contract: no
   `expense_correct_business_date`, and `ARCHITECTURE.md` §5.3's row restated as
   *"business-date correction — inside `expense_update` / `revenue_update`, requires
   `base_row_version`"*. There must be one authoritative contract, not documentation
   promising one API while production implements another.
7. **Mirror 1–5 into `revenue_update`** where they are not already there. It checks both
   periods and takes no reason; it should collect one on the same branch, so the two
   engines agree about what a business-date correction is.

### What must be proven, and in what order

* A **failing** live test first: an expense in a closed month is moved out and the move
  succeeds. That is the defect, demonstrated before anything is changed — the standard A1
  and A2 set. Then the same test passing after the fix, with a control that fails without
  it.
* D+7 / D+8 and the beyond-window capability unchanged; a closed **target** period still
  refused, so the fix adds a rule rather than moving one.
* Cross-period allocations (D-034): every period a line contributes to, on both sides.
* The audit shows one correction, with its reason, and `business_date_source` reads
  `corrected` afterwards.
* The three migration invariants and the ledger parity check on the new migration, and the
  documentation change in the same commit as the code, so they cannot disagree again.

### Scope, stated so it cannot creep

This is a **Phase 3 financial-integrity hotfix**. It does not build a period-close console,
does not change the edit window, does not touch revenue's create path, and does not add a
new client screen — the date row already exists and gains a reason field on the branch that
needs one.

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
   **Resolved by Phase 6 Slice 6 (2026-09-22).** The placeholder was replaced by the real
   Overview, which names only the properties in the reader's own P&L authority. A reader
   without authority sees the neutral sentence and no property name (D-259, D-267), as the
   authority phases prove on Windows, the emulator and the Galaxy A06.
4. **Windows local-key protection relies on user-scoped DPAPI**, not hardware (D-036).
   Accepted for V1, mitigated as recorded.
5. **The host widget suite does not yet make a missed tap fatal.** The acceptance suite
   now does (D-075), and the setting is one line. It is not applied to `test/` in this
   change because doing so at the end of a phase would surface an unknown number of latent
   misses with no time to judge them, and a rushed judgement about a financial widget test
   is worse than a recorded follow-up. Worth doing at the start of Phase 4, when there is
   room to look at whatever it finds.
   **Resolved by Phase 8 Slice 5 (2026-10-01, D-325):** missed taps are fatal across the host
   suite through `test/flutter_test_config.dart`.
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

---

## Phase 3 corrective — expense business-date and closed-period integrity: **DONE**

Approved by the project lead as **Option A** — `expense_update` stays the one Expense
correction contract, and no `expense_correct_business_date` is created merely because stale
documentation named one. Recorded as D-136 … D-139; the bounded revenue parity audit it
required is D-140, and three acceptance defects it surfaced are D-141.

### The defect, proven red before anything changed

A probe against the shipped `expense_update` on `krishna-mis-dev`, with no new parameter
involved:

```
        contributions BEFORE   {2026-03: 4500000}
        2026-03 closed for Crystal Canopy
        expense_update -> business_date 2026-04-10, as the Accountant
        applied                {status: applied, row_version: 3}
        refused                null
        contributions AFTER    {2026-04: 4500000}
        document AFTER         business_date_source: derived
        audit actions          [expense_edited (reason null), expense_created]
```

₹45,000 left a **closed** month through an ordinary edit. All four findings of the audit
are visible in that one run: the source period unprotected, the move ungated, no reason
collected, and the provenance still reading `derived`.

The permanent control that replaces it fails **14 of 14** against the unfixed server and
passes 14 of 14 against the fixed one.

### What the contract is now

| | |
|---|---|
| **Authoritative RPC** | `public.expense_update` — ordinary edits *and* business-date corrections |
| **Date move detected** | server-side, `p_business_date is distinct from e.business_date`; never a client flag |
| **Source periods** | every `pnl_period_key` in `expense_period_allocations` must be open |
| **Target periods** | unchanged — inside `app.validate_expense_allocations`, shared with create |
| **Capability** | `transaction.correct.business_date`, per property the document charges |
| **Reason** | required on the move branch only, non-blank after **all** whitespace |
| **Provenance** | `business_date_source = 'corrected'` on that branch and only there |
| **Audit** | a distinct `expense_business_date_corrected` action, with both dates and the reason |
| **Unchanged** | edit window under the property's date (D-067), `base_row_version`, `mutation_id` replay, the transaction number |

Closed source → refused. Closed target → refused. Both open → the ordinary checks continue.
No role and no capability reopens a period; the Owner is refused and the same correction is
accepted only after a deliberate, reasoned, audited reopen.

### The client surface that exists today

The Expense edit form has always had a business-date row, so this is a change to an existing
control and not a new screen:

* **new expense** — the date row is editable exactly as before (`manual`, not a correction);
* **edit, without the capability** — the date is shown and does not open;
* **edit, with it** — the date opens, and the moment it differs from the one the form was
  loaded with a reason field appears and Save waits for a non-blank one.

The loaded date is captured once and `copyWith` cannot move it, exactly as `baseRowVersion`
cannot. The reason travels in the outbox payload, so an authorised correction queued offline
still carries it when it is delivered.

**The Revenue client offers no business-date control at all**, on either platform, and none
was built here.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 190 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,088 tests, all passing** (1,067 + 21 new) |
| Secret scan — tree and git history | **Tested** | clean, with the scanner's own controls passing |
| Migration audit, incl. the two new invariants | **Tested** | 19 host tests |
| Live expense suite | **Tested** | **30 tests** (16 + 14 new), all passing |
| Live revenue boundary suite | **Tested** | **33 tests** (27 + 6 new), 1 deliberately skipped |
| Live two-client acceptance | **Tested** | 10 tests, all passing |
| Live `drift` phase — repository ↔ server migration parity (D-056) | **Tested** | every applied migration has a committed file |
| Live `conflict` phase | **Tested** | 4 tests |
| Live revenue phase chain (`revenue-sync` → `-offline` → `-create` → `-cleanup`) | **Tested** | run **twice in succession**, green both times |
| Development fixtures reversed | **Tested** | **0** open expenses created this session remain; 0 open revenue |
| Verified tax baseline after the run | **Tested** | 4 live rules, 0 bands, 0 subtypes, 0 statuses, 0 closed periods |

### The live matrix, in full

| Case | Result |
|---|---|
| Ordinary edit, date unmoved, by Data Entry — no capability, no reason needed | **PASS** |
| Permitted correction: new date canonical, `corrected`, reason audited, KI-EXP preserved | **PASS** |
| Date moved without `transaction.correct.business_date` | **PASS** — refused |
| Blank reason | **PASS** — refused KM008 |
| Whitespace-only reason (incl. a bare tab) | **PASS** — refused KM008 |
| **Closed source, open target** | **PASS** — refused KM004, contributions unchanged |
| Open source, closed target | **PASS** — refused KM004 |
| Both closed | **PASS** — refused KM004 |
| Owner does not bypass the period lock, and succeeds after a reopen | **PASS** |
| The two correction capabilities compose | **PASS** |
| Stale `base_row_version` | **PASS** — Conflict, nothing applied |
| Idempotent replay | **PASS** — one version step, one audit row |
| Response loss, then retry (`ControllableTransport`, D-132) | **PASS** — replayed, same number |
| Cross-period bill protected on **every** month it contributes to | **PASS** |

The contribution regression is asserted on the **figures**, before and after, not on the RPC
status: a refusal that still moved the rows would be no protection, and the amounts asserted
are the ones Phase 5 will aggregate.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260905141738 | `expense_business_date_correction` |
| 20260905142059 | `correction_reason_rejects_all_whitespace` |
| 20260905144151 | `revenue_business_date_correction_governance` |

Three versions, three committed files, each verified **byte-for-byte by hash** against
`supabase_migrations.schema_migrations.statements` rather than by resemblance (D-056). The
second exists because the first's own live test found a defect **in the fix** — `btrim(text)`
strips spaces and not tabs — and the applied file is not rewritten to look like something
that never ran.

---

## Phase 4 corrective — revenue business-date correction governance: **DONE**

The bounded parity audit was run against the shipped `revenue_update`, and **four of the
seven** requirements were already met and were left alone: both periods checked, tax
re-resolved against the new date, `KI-REV` preserved, `base_row_version` enforced (D-124).

**Three were missing**, proven by probe rather than by reading. A Manager holding
`revenue.edit` and no correction capability moved a sale from 2026-09-04 to 2026-09-03:
`status: updated`, no capability asked for, no reason collected, one `edited` audit row with
a null reason. Spec §9 and §14 are not scoped to expenses, so the gap is real.

`revenue_update` now detects the move **by date rather than by period key** — 15 June to
20 June is the ordinary correction and stays inside one period — requires
`transaction.correct.business_date` for the property, requires a non-blank reason, and
writes a distinct `business_date_corrected` audit action. **Six new live tests**, including
the control that the same manager may still correct the *figure*, so the refusal means "the
capability binds" rather than "nobody can correct anything".

**No `business_date_source` column was added to revenue.** See the open question below.

---

## Open questions for the project lead

~~**One, and it blocks nothing.** Should a revenue entry record how its business date was
arrived at, the way an expense does?~~ **Answered 2026-09-05: yes** — `derived` and
`corrected`, server-owned, built and tested (D-143). Spec §8.0 is amended, and
`DATABASE_SCHEMA.md` turned out to have listed the column twice all along. The question as
it was put:

`expenses.business_date_source ∈ {derived, manual, corrected}` exists and, since this
corrective, is written on the branch where a date actually moves (D-019). `revenue_entries`
has no such column and never has. The two binding readings disagree:

* **spec §8.0** enumerates what a revenue entry carries and does **not** include it;
* **spec §9** says the record notes whether a date was `derived`, `manual` or `corrected`,
  and is written generally rather than about expenses.

Adding a column to the revenue document because the expense document has one would be
settling a product question by symmetry, which is exactly what the corrective brief
forbade — so it was not done, and the audit trail carries the correction meanwhile
(`business_date_corrected`, with both dates, the actor and the reason). If the answer is
yes, it is a small migration plus a value written by `revenue_create`; if no, spec §8.0
should say so explicitly.

**Also recorded, not asked:** `expense_void` and `revenue_void` check their mandatory
reasons with one-argument `btrim`, so a single tab satisfies both — the same defect D-138
fixed in the correction path, in two functions outside this corrective's reviewed scope. It
is reported rather than fixed in passing (D-127).

---

---

## Pre-Slice-11 corrective — two approved items: **DONE**

Approved and scoped to exactly two items. Nothing else was changed, and the adjacent
findings are recorded rather than fixed.

### 1 · A mandatory financial reason rejects every whitespace-only value (D-142)

**Proven red first, on both engines.** One-argument `btrim`/`trim` strips spaces alone:

```
        expense_void(p_reason => E'\t')   applied, row_version 3, audit reason "\t"
        revenue_void(p_reason => E'\t')   applied, row_version 2, void_reason "\t"
```

Two documents permanently voided, with a tab as the only record of why.

`app.stated_reason` is now the one rule — internal, immutable, revoked from every client
role, and **not** on the reviewed API surface. Both voids call it, and so does the
business-date correction reason, so the three cannot drift. The **normalised** value is
stored, which is the project's existing trimming convention; internal spacing is content
and is untouched.

Both `void_has_reason` CHECKs are tightened to the same expression and added `NOT VALID` —
because the two probe fixtures **cannot be repaired**: `app.refuse_voided_mutation` refuses
every update to a voided document, including one issued as the table owner, and it was
right to (D-006). Enforcing forward while leaving the evidence is the correct trade, and it
is two guarantees holding at once rather than a compromise.

### 2 · Revenue records how its business date was established (D-143)

An approved V1 requirement, settling what D-140 raised. `revenue_entries.business_date_source`,
two values — `derived` and `corrected` — server-owned end to end:

| | |
|---|---|
| create | `derived`, stated by `revenue_create`, which takes **no** provenance argument |
| correction | `corrected`, only on the branch the server has established moved the date |
| ordinary edit | preserved — once corrected, it stays corrected |
| every refusal | leaves it untouched; all of them happen before the write |
| backfill | `derived` for all 307 existing rows, inferred from nothing |
| audit | unchanged and still authoritative; the column is present-state provenance |
| UI | none — it is provenance, not operator input |

**The enum is shared and its wire names are now explicit.** `BusinessDateSource` is reused
rather than duplicated, and its stored form is stated on the enum and pinned by a host test
instead of being `.name` — the D-104 trap, closed before it could be walked into.

`DATABASE_SCHEMA.md` listed this column **twice** and Slice 4 shipped without it, so what
looked like an open §8.0-versus-§9 question was partly an unrecorded implementation gap.
Spec §8.0 is amended; the change log records that the version does not move, because this
states what §9 already required of every financial row.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 191 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,099 tests, all passing** (1,088 + 11) |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Void whitespace **positive control** | **Tested** | the shared helper degraded to `btrim`; the tab case turned **RED on both engines**, then green after restore |
| Expense void matrix | **Tested** | 10 live tests: empty, spaces, tab, newline, CR, mixed — all refused; ordinary reason voids and is stored trimmed |
| Revenue void matrix | **Tested** | 10 live tests, the same matrix, plus the Slice 10 contract unchanged |
| Revenue provenance matrix | **Tested** | 7 live tests: create, ordinary edit, correction, edit-after-correction, second correction, every refusal, response-loss replay |
| Drift v12 → v13 migration | **Tested** | a pre-migration row becomes `derived`; number, year, version, dates, void state, components and tax snapshot all intact |
| Fresh database | **Tested** | born with the column, NOT NULL, defaulting to `derived` |
| Live expense suite | **Tested** | **40 tests** (30 + 10) |
| Live revenue boundary suite | **Tested** | **49 tests** (33 + 16), 1 deliberately skipped |
| Live two-client acceptance | **Tested** | 10 tests |
| Live `drift`, `conflict`, revenue phase chain | **Tested** | all green |
| Migration ledger parity (A0 / D-056) | **Tested** | every applied version has a committed file |
| API-surface and PUBLIC-execute invariants | **Tested** | asserted in both migrations; `app.stated_reason` unreachable by any client role |
| Baseline pristine | **Tested** | 0 closed periods, 4 live rules, 0 bands/subtypes/statuses, **0 open revenue**, 0 open expenses from this session, 0 rows with a provenance outside the approved set |

### Not rerun, and why

**`phase-a`, `phase-b`, `phase-c`, `multi-scope-a`, `multi-scope-b` — not rerun,
unaffected by this corrective.** Nothing here touches authority caching, grants, scope
resolution or purge semantics. They are **not** claimed as freshly passing.

**The Android and Windows acceptance suites — not rerun.** No controller or UI behaviour
changed: no surface was added for the provenance field, and the void surfaces call the same
repository methods with the same signatures. The domain shape gained one field with a
default, and the widget and draft suites cover it through the host run.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260905185903 | `financial_reasons_reject_all_whitespace` |
| 20260905190229 | `revenue_business_date_provenance` |

Both verified **byte-for-byte by hash** against `supabase_migrations.schema_migrations.statements`.

### Recorded, and deliberately not fixed

**`period_reopen` has the same whitespace defect.** It normalises its mandatory reason
(D-026) with `btrim(coalesce(p_reason, ''))`, and `period_lock_events` carries the same
spaces-only CHECK, so a lone tab satisfies both. It is **outside the two approved items**,
which name the Expense and Revenue *void* boundaries. `app.stated_reason` is shaped so that
closing it later is one call per site.

**A migration-ordering defect this work introduced and caught (D-144).** The v13 step was
written `if (from < 13)` and failed from v9 with `duplicate column name`: `revenue_entries`
is created at v11 from the *current* table definition, which already includes the column.
The guard is now `from >= 11 && from < 13`. Found by the v9 attachment fixture — the same
fixture, the same class of defect, two phases after D-073a.

**A restore that silently did not happen.** The first attempt to undo the positive control
batched the `create or replace` with an assertion whose literal was mis-escaped; the raise
aborted the transaction and left the **degraded** helper installed. Caught by reading the
state back rather than trusting the statement. *A restore is not restored until it has been
read back.*

---

---

## Final pre-Slice-11 corrective — the last mandatory financial reason: **DONE**

One approved item, and the constraint-architecture correction it forced.

### The defect, proven red first

`period_reopen` normalised its mandatory reason with `btrim(coalesce(p_reason, ''))`,
which strips spaces and nothing else. Against the shipped function:

```
period 2026-05 / Crystal Canopy · lock 6fce38ca-9a3d-4ec7-b2ce-e157199c38df
closed legitimately                  state: closed, row_version 1
period_reopen(p_reason => E'\t')     APPLIED, state: open, row_version 2
refusal                              none
period_lock_events                   {action: reopen, reason: "\t"}
audit_logs                           {action: period_reopened, reason: "\t"}
period_locks.reopen_reason           "\t"
actor                                the Owner
```

A closed financial period was reopened — the act spec §13.4 reserves to the Owner and
requires to carry a mandatory reason — with a tab as the whole justification.

### The five mandatory financial reasons, audited in full

| Operation | Rule |
|---|---|
| `expense_void` | `app.stated_reason` (D-142) |
| `revenue_void` | `app.stated_reason` (D-142) |
| `revenue_update` — business-date correction | `app.stated_reason` (D-143) |
| `expense_update` — business-date correction | the identical expression, inlined |
| `period_reopen` | `app.stated_reason` (this corrective) |

**There is no sixth.** The list is produced by searching the catalogue for every function
that can raise `reason_required`, not by remembering. `expense_update` predates the helper
by one migration and carries the same expression rather than the call — identical
semantics, reported rather than refactored. `expense_attachments_removal_has_reason` also
trims spaces only and is **not** one of the five: nothing raises `reason_required` for it
and V1 ships no destructive attachment removal (D-072a), so it has no writer.

### Constraint state, per environment (D-146)

| Environment | `expenses` | `revenue_entries` | `period_lock_events` |
|---|---|---|---|
| `krishna-mis-dev` | NOT VALID, 1 blocking row | NOT VALID, 1 | NOT VALID, 1 |
| fresh replay / staging / production | **validated** | **validated** | **validated** |

D-142 wrote `NOT VALID` into the migration, which would have handed staging and production
an unvalidated schema for a reason that exists only in one development database's history.
The migration now installs each constraint `NOT VALID` and then **counts** the rows that
would violate it: zero validates, more than zero is left unvalidated with a notice naming
the constraint and the count. No environment is named, no fixture id is hardcoded, nothing
is deleted, and D-006 is untouched.

The three blocking rows are the probes that proved the three defects, one per table, each
in a table that correctly refuses to be rewritten. They are evidence, not damage.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,101 tests, all passing** (1,099 + 2 invariants) |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Live reopen matrix | **Tested** | 10 tests: null, empty, spaces, tab, newline, CR, mixed all refused `KM008` with the period left **closed**; a real reason reopens and is stored trimmed; internal spacing preserved |
| Positive control | **Tested** | the shared helper degraded to `btrim`; **both** the void tab case and the reopen tab case turned RED, then green after restore — with the helper read back rather than assumed (D-142) |
| Other reopen protections | **Tested** | capability refused before the reason; not-closed refusal; idempotent replay writes one append-only event |
| Clean-environment constraint replay | **Tested** | identical constraints and identical validation block against a throwaway schema: all three `convalidated = true`, and a tab-only reopen reason refused on insert |
| Canonical-reason invariant | **Tested** | asserted at deploy and at host level, as a **search** over every `reason_required` function; proven to fail when `btrim` is put back |
| Live expense suite | **Tested** | **50 tests** (40 + 10) |
| Migration ledger parity (A0 / D-056) | **Tested** | every applied version has a committed file, verified byte-for-byte |
| Period fixtures | **Tested** | 2026-05 left **open**; 0 closed periods across the project |

### Not rerun, and why

**`phase-a`, `phase-b`, `phase-c`, `multi-scope-a`, `multi-scope-b` — not rerun,**
**unaffected.** No authority caching, grant, scope-resolution or purge code changed. They
are **not** claimed as freshly passing.

**Android and Windows acceptance — not rerun.** No controller or UI path changed; this
corrective is one server function and its backstop.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260905202325 | `period_reopen_uses_canonical_reason` |

Verified byte-for-byte against `supabase_migrations.schema_migrations.statements`.

### Open, and worth doing once

**A full migration-chain replay against a genuinely fresh Postgres** has not been run: it
needs a provisioned database (a Supabase branch), which is a paid resource and was not
created unilaterally. The property in question — that the reason constraints install and
validate on clean data — is proven by the throwaway-schema replay above. A branch replay
is worth running once before the first staging deploy.

## Next exact task

**Phase 5 — P&L / MIS Reporting, Slice 1.** Superseded as a planning note: Phase 5 is
started, its decisions are ratified (D-163 … D-173) and its twelve-slice plan is recorded in
*PHASE 5 — P&L / MIS REPORTING* at the end of this file, which is where the current state
lives. Note that the handoff contract's *"no revenue pull"* is corrected by D-173: there is
no **expense** reporting pull either.

### Superseded — the Slice 13 entry

**Slice 13 — live and device acceptance: both platforms, real backend, two-device.**
Slices 11 and 12 are both formally closed (`bcf6f19`, `d6f0851`) and the Slice 11 manual
picker gate is passed (D-156).

One question is open and should be answered before Slice 13's acceptance is designed:
which build and environment the manual picker runs used, since `krishna-mis-dev` holds no
artefact of them — see **Open questions for the project lead**.

### Superseded — the Slice 12 entry

**Slice 12 — reporting contributions: `revenue_period_contributions` populated (D-087).**
Slice 11 is done, tested and accepted, and it deliberately built no reporting: a test
asserts the revenue detail surface names no P&L, Net Sales, Operating Profit or Export.
Nothing blocks Slice 12, and it has **not** been started.

Slice 12 defines and **populates** the reporting interface. It does not build the P&L or
the engines — those are Phase 5, with the parity suite D-020 requires.

---

### Superseded — the Phase 4 entry blocker, closed 2026-09-01

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

~~**One for Phase 4** … the effective-from dates.~~ **Answered 2026-09-01: 2026-04-01 for
all four treatments.** Configured as a committed migration (D-096) and now synchronising
to devices (Slice 6).

~~**One open, raised by Slice 6 (D-112)**~~ **Answered 2026-09-02: 24 hours**, from the
server-confirmed timestamp, per user and per business unit, inclusive at the boundary, with
no Owner or Accountant override — a tax-correctness gate rather than a privilege one.
Implemented in Slice 7 and tested at the boundary, one second past it, and against a
backwards device clock.

~~**One open: approval for the Phase 3 corrective**~~ **Approved and implemented
2026-09-05.** All four findings below are closed and proven against `krishna-mis-dev`; the
evidence is under *Phase 3 corrective — expense business-date and closed-period integrity:
DONE*, and the reasoning is D-136 … D-139. The four findings, as they were put:

1. **`expense_update` protects the target period and not the source**, so an expense can be
   moved *out* of a closed month and that month's Operating Profit changes with nobody's
   permission. Spec §13.4 says every edit **affecting** a closed period is rejected.
2. **`expense_correct_business_date` is named by three canonical documents and does not
   exist.** The capability is not missing; the separately named endpoint is.
3. **`transaction.correct.business_date` is granted to two roles and evaluated by nothing.**
4. **A corrected business date is not marked as corrected** — `expense_update` never writes
   `business_date_source`, which D-019 requires, and collects no reason, which spec §9
   requires.

The recommendation was **one contract**: keep the correction inside `expense_update`, and
make it a first-class act there — both periods checked, a reason required when the date
actually moves, `business_date_source = 'corrected'`, its own audit action, gated on the
capability that evaluated to nothing — then correct the documents to describe what
production does. **That is what was approved, and that is what was built.** The one item
deliberately left open is whether *revenue* should carry the same date provenance, which is
a product decision and is asked under **Open questions for the project lead** above.

## Open questions for the project lead

**One, and it blocks nothing.** Which build and environment did the manual revenue
native-picker runs use?

Both platforms are reported PASS on 2026-09-06 and Slice 11 is closed on that. The picker
itself leaves no server trace, so there is nothing to corroborate and nothing to doubt. The
**save-and-sync leg** does leave one, and `krishna-mis-dev` has none: all 96 revenue
attachment rows are accounted for by automated suites, every registration in the
append-only audit trail is an automated run, and the KI-REV sequence has 752 numbers and
752 rows, so nothing was created and removed.

The likely answers are benign — a dev build with no backend configured, or the picker
checked to the point where the file appears on the form, which is the substance of the
gate. Knowing which lets the record say so exactly, and stops a later reader taking the
automated `synthetic-receipt.jpg` rows as evidence of this line (D-156).

If the sync leg *was* meant to be exercised against `krishna-mis-dev`, it is worth one more
short run, because that is the half a person is uniquely able to prove end to end.

## Project lead actions required

1. ~~Two manual picker smoke tests.~~ **Done, 2026-08-31 — both PASS.**
2. ~~The effective-from dates.~~ **Done, 2026-09-01 — 2026-04-01 for all four.**
3. ~~A maximum age for cached revenue tax configuration (D-112).~~ **Done, 2026-09-02 —
   24 hours.**
4. **Optional decision:** whether archiving should also offer a *confirmed* cascade for a
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

**Local Drift schema v17.** v17 adds the canonical reporting cache —
`reporting_revenue_contributions`, `reporting_expense_contributions` and
`reporting_coverage_markers`, every key and index leading with `owner_user_id` (D-171,
D-074). They arrive **empty and uncertified**: a migration synchronises nothing, and a
device that upgrades reports `notDownloaded` until it has asked the server (D-108). Full
shape in `DATABASE_SCHEMA.md` §13. v16 adds the `expense_period_contributions` view and its
index; v15 adds `revenue_period_contributions` and `ix_revenue_entries_reporting`; v14 adds
`revenue_attachments`; v13 adds `revenue_entries.business_date_source`.

**Local Drift schema v12.** v12 adds `revenue_config_snapshots` — per user, per business
unit, naming the datasets proven present, the server generation and the server-confirmed
time (D-108) — and **deletes** the superseded global `revenue.configuration.synced_at`
key rather than translating it, because there is no honest way to decide retroactively
which user held which scope when it was written.

**Local Drift schema v11.** v11 adds the revenue read model — `revenue_entries`,
`revenue_components` — and three reference caches that ship empty: `revenue_value_bands`
(D-098), `revenue_supply_subtypes` (D-083) and `business_unit_tax_statuses` (D-082).
`revenue_tax_rates` gains `input_basis`, `value_band_id`, `supply_subtype_id` and
`premises_status_code`, **all nullable and none backfilled**. The unique index
`ux_tax_rates_live_period` is **dropped** (D-099). Revenue header totals are derived by the
`revenue_entry_totals` view, never stored.

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

**Postgres: 60 applied ledger versions, every one accounted for by a committed file.**
`supabase/migrations/LEDGER.md` maps them, and a host test enforces the mapping rather than
describing it (D-102) — which is how the two uncommitted audit migrations were found. 0033
measures the edit window under the property's business date (D-067). 0034 adds
`attachment_register` — the only writer of `expense_attachments`, verifying the size and
SHA-256 against the stored object. 0035 restates the reviewed API surface to include it,
which the invariant refused to let me skip (D-044). 0036 fixes an attachment-metadata
policy that was **vacuously true** for scoped users: it hunted for rows that RLS had
already hidden from it, so it could neither permit nor refuse anything. The live suite
asserts the repository and the server agree (D-056). `20260904144542` adds the correction
boundary — `revenue_update`, `revenue.edit.all` and `app.revenue_window_today` — and
`20260904150814` restates the reviewed API surface to include it, which the invariant again
refused to let me skip.

## Last important decision

**D-125 — a revenue document has at most one queued intent, and a correction rewrites it.**
The expense engine queues a fresh update intent on every edit, and two of its consequences
are reachable rather than theoretical: a correction to a sale whose create then fails
transiently arrives first, finds no document, and is refused `KM015` — *terminal*, so a
legitimate correction becomes a rejection; and two corrections made before either syncs
carry the same base version, so the second conflicts with a version its author never saw.

A revenue correction therefore rewrites whatever is already queued, in place. A create stays
a create — the server has never seen the document, and sending an update for it would be
asking to correct something that does not exist. Nothing is deleted and no attribution moves:
the entry keeps its own mutation id, its actor and its creation time, so idempotency (D-004),
ownership (D-050) and retention (D-074) all still key on the same values. Only the payload
changes, and the payload is the operator's current intent.

**The control is what makes it a claim.** With the queued-intent lookup forced to find
nothing — which is exactly the expense shape — three of the twenty-one repository tests fail.
The first control written for this did *not* fail, because `null ?? expr` still evaluates
`expr`; it was caught by expecting red and finding green, which is the same trap D-094's note
records and the fourth time this project has walked into it.

Recorded beside it, because it is the other half of an honest checkpoint: **the three Slice 10
acceptance phases have not been run**, and are reported as NOT RUN rather than carried
forward (D-107).

---

**D-104 — the stored form of a tax basis was never actually read, and was wrong.**
`EnteredBasis` was persisted and parsed through Dart's `.name`, which is `inclusiveTotal`.
Both databases store `inclusive_total`. Every rule carrying a basis would have thrown on
read — and since A1 made that column NOT NULL, that is every rule that exists.

It passed three slices of review, a clean analyze and a green suite, because **nothing had
yet read a rule out of a database into the domain model**. The Slice 2 tests constructed
`TaxRule` objects directly, so they were checking Dart against itself; the Slice 4 live
tests read the column as raw JSON and never parsed it. Two correct halves, and no test
crossing the boundary between them.

The same shape of gap as D-059's actor filter and D-068's classification guard, arriving in
a new place: not a rule nothing evaluated, but a **conversion nothing exercised**. The fix
states the wire form explicitly and pins it on both sides — a host test on the exact
strings, and a live test that reads the real column and requires the client to parse it —
so neither can be edited into agreement with the other.

Recorded beside it, because it is the same lesson about evidence: **the live backend suite
had been failing since Slice 4 and was carried forward rather than run** (D-107). Its
`phase-a` still asserted that no tax rule is configured, which the verified baseline made
false. Carried-forward is not re-verified, and this is what that distinction is for.

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

---

## Phase 4 Slice 11 — Revenue attachments: **COMPLETE**

Evidence for a sale, built on the Phase 3 attachment architecture rather than beside it.
Decisions D-147 … D-152; `ARCHITECTURE.md` §25; `DATABASE_SCHEMA.md` gains the Slice 11
section.

**The whole of the design decision is what was *shared* rather than copied.** The audit
found the split cleanly: the picker, the staging service, the optimiser, the accepted-type
table and the eight-state lifecycle were never about expenses, and were reused as they
stood. What was named for expenses and only that — a file record, two policy constants, a
directory parameter, and the worker's typed queries — moved into `domain/attachments/`,
with `ExpenseAttachment` left as a typedef so no expense call site changed.

**One worker, not two.** `AttachmentUploadWorker` drives both tables through one internal
descriptor: one backoff clock, one definition of `uploaded`, one recovery pass, one
reclamation policy. Two would have been two of each, agreeing only until somebody edited
one — D-119 for a duplicated `switch`, D-131 for a duplicated join, both already drifted
when found. **The evidence that the refactor is neutral is the existing suite:** all 73
expense attachment tests pass over the rewritten worker unchanged.

**A revenue entry is never partly visible, so its predicate is not the expense one
(D-148).** D-063 makes an expense attachment complete-document-only because a shared
invoice states the whole total and an expense *can* be partly visible. A revenue entry
names one business unit on its header, has no allocation lines and no scoped projection —
so `may_read_revenue_attachments` asks what the revenue projection already asks, and
reproduces none of the allocation arithmetic. Copying it would have been cargo cult.

**One bucket, two prefixes, two policies (D-149).** `org/{org}/revenue/{entry}/…` beside
`org/{org}/expenses/{expense}/…`, decided by separate policy sets over one private bucket.
A second bucket would duplicate the size limit, the MIME list and four policies, all then
kept in step by hand. The two path parsers are asserted mutually exclusive at deploy time
and again from a client.

**Attaching is not editing (D-150).** `attachLocally` takes no `base_row_version`, queues
no outbox intent, advances no row version, and changes no amount, tax figure, business
date or transaction number. A test captures a sale's whole financial state before evidence
is attached and compares it after attach, upload, failure, retry, reclamation and restart;
the same comparison runs against `revenue_document` on the real server. The local schema is
asserted to carry no money-shaped column at all, so the mistake is unavailable rather than
avoided — the move D-094 made for `RevenueTaxFacts`.

**No removal, determined rather than assumed (D-151).** Spec §15 describes capture, storage
and access control; §28 lists attachments and says nothing about removing one; D-072a
states V1 offers none. `expense_attachments` carries the removal trio with **no writer
anywhere in the product**, which is why D-145 excluded its constraint from the five
mandatory reasons. `revenue_attachments` therefore has no removal columns, and the
migration asserts their absence. A second unwritable constraint is not a feature.

**No download RPC, no signed-URL issuer, no viewer.** Phase 3 built none — reading an
object back is Storage's own authenticated download under the read policy — so revenue got
the same and nothing more (§32 of the brief: reuse what exists, and existing behaviour is
"no viewer").

### The client surface

| | |
|---|---|
| Android entry | `More details` → the shared strip. Four taps and a number is unchanged; nothing about evidence appears until asked for |
| Detail, both shells | an `EVIDENCE` section on the one panel both platforms use, with an attach control for a recorded sale |
| A voided sale | shows its evidence, offers no control, and says why rather than leaving a button missing |
| Wording | file name, size and lifecycle state; **no storage key, no bucket, no path** |
| Taking a file back out | offered only while `staged` — a draft nobody has recorded, which is not removal |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 192 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,147 tests, all passing** (1,101 + 46) |
| Revenue evidence — repository, lifecycle, limits, revocation, user switch | **Tested** | 32 host tests |
| Revenue evidence surfaces, both shells | **Tested** | 13 widget tests at three window sizes |
| Expense attachment suite over the rewritten worker | **Tested** | 73 tests, unchanged except parameter names |
| Migration audit, incl. the Slice 11 table scope | **Tested** | 21 host tests |
| Live revenue boundary suite | **Tested** | **61 tests** (49 + 12), 1 deliberately skipped |
| Migration ledger parity (A0 / D-056) | **Tested** | both versions verified **byte-for-byte by hash** |
| API-surface and PUBLIC-execute invariants | **Tested** | restated in full; three additions named |
| Secret scan — tree, git history and **rebuilt clean artefacts** | **Tested** | clean, with the scanner's own controls passing |
| Android acceptance, real dev APK on the emulator | **Tested** | `revenue-attachment`, `revenue-attachment-offline` |
| Windows acceptance, real `krishna_mis.exe` | **Tested** | the same two phases |
| Acceptance fixture reversal | **Tested** | 0 open revenue of any kind; baseline pristine |

### Real device acceptance

Both phases on both platforms, against `krishna-mis-dev`, through the shipped screens.

| Phase | Android | Windows |
|---|---|---|
| `revenue-attachment` — form → save → number → upload → detail | **PASS** | **PASS** |
| `revenue-attachment-offline` — offline create + attach → restart → reconnect | **PASS** | **PASS** |

The online phase proves the durable consequence: one metadata row, one object, the content
hash matching what the device staged, and nine `revenue_document` fields unchanged by any
of it. The **offline** phase is where the ordering rule is observable — the sale has no
number, so the file provably cannot upload — and it proves the staged bytes and the queued
intent both outlive a process kill, that the attachment identity is stable across it, and
that a reconnect yields exactly one sale, one attachment row and one object.

### Live fixture and storage state, stated rather than called pristine

| | |
|---|---|
| Live tax rules | **4** — the verified baseline, untouched |
| Value bands / supply subtypes / premises statuses | **0 / 0 / 0** |
| Closed periods | **0** |
| Open revenue, of any kind | **0** — every acceptance sale voided through the real API |
| Authority grants | **5**, the development baseline; the revocation test's restore **read back** |
| `revenue_attachments` rows | **47**, every one on a **voided** sale |
| Objects under `org/…/revenue/` | **55**, of which **8** carry no metadata row |

**The rows are not cleaned up, and that is the correct outcome.** They are evidence for
voided documents, which D-006 keeps: a void excludes a sale from reporting and destroys
nothing. No client role holds DELETE on the bucket (D-063), and granting one for a test's
convenience would be a backdoor — so the objects stay and the run says how many rather
than claiming a pristine bucket (§43).

**The eight objects without a metadata row are the security tests working.** Each is an
upload whose `revenue_attachment_register` was then refused — `KM009` for the same id with
different bytes, `KM010` for a path belonging to another sale, and the wrong-property and
revoked attempts. Postgres is the record of what evidence exists; the bucket is where bytes
live, and the two disagreeing in exactly this direction is what the design intends
(spec §23).

### The live security matrix, in full (§36)

| Case | Result |
|---|---|
| Authorised actor attaches; metadata row **and** object read back | **PASS** |
| Attaching moves no figure on `revenue_document` | **PASS** — nine fields compared |
| Redelivery: one object, one row, replayed answer | **PASS** |
| Same attachment id, different bytes, fresh mutation id | **PASS** — refused `KM009` |
| A storage path belonging to another sale | **PASS** — refused `KM010` |
| Voided sale keeps evidence and accepts none | **PASS** — refused `KM020` |
| Wrong-property manager: metadata not enumerable, object refused, registration refused | **PASS** |
| The property's own manager reads both halves | **PASS** |
| **Revoked** user loses both, and regains them on restore | **PASS** — grant genuinely withdrawn, restoration **read back** |
| Anonymous: no rows, no object, no RPC | **PASS** |
| The two storage prefixes decide separately | **PASS** |
| No unauthenticated URL serves an object | **PASS** — the fetch, not the configuration, says so |

### Positive controls, each seen to fail

| Control | Result |
|---|---|
| Purge without `revenue_attachments` | **RED** — the D-070 revocation test fails |
| Ordering degraded to "uploadable at once" | **RED** |
| Identity dedup removed | **RED** — 3 of 32 fail; restored and read back |

### Two acceptance findings (D-152)

Neither is a product defect, and both were assertions about the wrong thing.

**The online phase asserted that the product is slow.** It checked that a freshly saved
sale's evidence had *not* yet uploaded, to demonstrate the D-073 §2 ordering rule. Against
a real server the whole chain — save, push, number, promote, upload — finishes inside the
same two-second pump, so it failed on a run in which everything worked. It now asserts the
durable consequence, and the ordering rule is proven in the **offline** phase where no
number can arrive and the upload provably cannot start. Slice 8 records the identical
lesson for *"no number yet"*.

**A widget test cannot await real file I/O without saying so.** A `testWidgets` body runs
inside the fake-async zone: `pumpAndSettle` returns before a staging copy completes, and an
await on real I/O in the body never completes at all — which presents as a hung suite
rather than a failed one. Both are handled with `tester.runAsync` in a named helper.

**And the first version of that helper was a wall-clock race.** It yielded a fixed twelve
turns — 240 ms of real time — which passed the file alone and failed intermittently under
the full suite: three tests one run, six the next, none the third. A count of turns is a
bet on how busy the machine is, not a wait. It now waits for **the staged file to appear**
and fails with a sentence if it does not. **Three consecutive full host runs, green.**

**A document invariant caught a line-ending rewrite (D-153).** Appending the Slice 11
sections with a text-mode write turned all four canonical documents from LF to CRLF in
every line. D-137's assertion — that `ARCHITECTURE.md` states in as many words that there
is no `expense_correct_business_date` — matches a phrase spanning a line break, so it went
red. Restored to LF; the diffs are additions plus the intended restatements and nothing
else.

### Recorded, and deliberately not changed

**An un-uploaded file on an already-synced sale is destroyed by a confirmed revocation**,
for both document kinds. That is the shipped D-070 behaviour and it is **correct rather
than a gap**: the property has been withdrawn, the Storage policy would refuse the upload
from that moment anyway, and retaining bytes for a property the user has lost is the thing
D-070 exists to prevent. Stated here because it looks like a gap until the reasoning is
written down.

**The expense detail panel's attachment status switch is stale.** It matches `'failed'`,
which the v10 lifecycle replaced with `retryNeeded` / `rejected` (D-073a), so a bill
needing attention reads *"Pending upload"* there. Cosmetic, on the expense surface, and
outside a revenue slice's reviewed scope (D-127). The revenue surface takes its words from
the enum itself, so it cannot drift the same way.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260905210226 | `revenue_attachments` |
| 20260905210332 | `api_surface_invariant_revenue_attachments` |

Both verified **byte-for-byte by hash** against
`supabase_migrations.schema_migrations.statements`.

### Local schema

**Drift v14** adds `revenue_attachments`, mirroring `expense_attachments` with the parent
pointer changed and the removal columns absent. Two narrow tables rather than one
polymorphic table: the foreign key that makes an orphan impossible is what a cascade and a
purge both rely on. The v14 step needs no version floor — unlike v13 (D-144) it creates a
table rather than adding a column to one a later step builds.

---

## Phase 4 Slice 11 closure — the upload lifecycle after the bytes land: **DONE, except one manual gate**

Two questions were put: audit the eight Storage objects that carried no metadata row, and
run a native-picker smoke test for revenue on each platform. The first found a production
defect. The second has **not been run** and is not claimed.

### 1 · The eight objects were not what the Slice 11 report said (D-154)

The report attributed them to KM009, KM010 and the wrong-property and revoked probes.
Against the actual rows, **three of those four attributions are wrong**: KM009 re-uploads
to the *same* path and strands nothing, and the wrong-property and revoked probes are
refused by the Storage write policy so no bytes are ever written.

They are four pairs, one per suite run:

| Class | Count | Production-reachable? |
|---|---|---|
| KM010 — a deliberately forged storage path | 4 | **No** — the client derives the path it sends |
| **KM020 — a voided parent** | **4** | **Yes**, through the ordinary path with no seam involved |

And the expense side showed the same shape: 50 objects, 46 rows, all four orphans with a
voided parent — latent since D-073a.

**The sequence, all of it ordinary:** a sale is recorded with a till photo and numbered; the
upload fails transiently and goes on the backoff clock; the accountant voids the sale; the
backoff elapses; **Storage accepts the bytes**, because its write policy asks only whether
the caller may *read* the sale; the register RPC refuses `KM020`; the worker marks the row
terminally `rejected`. The object then sits in a private bucket for ever, named by no
metadata row, invisible to the ledger, counted against no limit.

**Proven red before anything changed.** Seven new live tests against the shipped server:
**4 failed**, including one showing that a competing upload replaces canonical evidence
before the RPC refuses it. All seven pass against the fixed server.

### 2 · The fix, in three layers (D-154, D-155)

| | |
|---|---|
| Write authority | `may_attach_to_expense` / `may_attach_to_revenue` — the read predicate, plus `attachment.upload`, plus a parent that is **not voided**. Decides every INSERT and UPDATE |
| Read authority | **unchanged** — a voided document keeps its evidence (D-006), asserted at deploy so a later change cannot take it away |
| Reclamation | a narrow Storage `delete` policy per kind: this bucket, this caller's own bytes, a parent they may read, and **only while no metadata row names the path** |
| Overwrite | the UPDATE policies carry the same guard, so registered evidence can no longer be replaced |
| Lost response | the worker asks whether the registration committed **before** it re-uploads, and reconciles to `uploaded` when it has |

Both document kinds, deliberately: Slice 11 made one worker and one store serve both
(D-147), so there is no revenue-only form of this fix that does not first fork them.

### 3 · The bucket reconciles, and the run now says so rather than reporting residue

The Slice 11 teardown printed what it left. It now reclaims what nothing names — through
the ordinary policy, not through any privilege a test has and a person does not — and then
asserts there is nothing left, over both prefixes.

| | Before | After |
|---|---|---|
| Revenue objects / metadata rows | 55 / 47 | **79 / 79** |
| Expense objects / metadata rows | 50 / 46 | **46 / 46** |
| Stranded objects | 8 (+8 more from the red and green runs) | **0** |

**16 stranded objects reclaimed.** Registered evidence was untouched, including on voided
sales, which is the half the policy exists to guarantee.

### 4 · The native picker smoke for revenue: **NOT RUN** (D-156)

**Android PENDING · Windows PENDING.** Neither is claimed, and Slice 11 is therefore not
formally closed on this one line.

*What is closed:* the wiring. `attachment_source_wiring_test.dart` reads what production
resolves per platform, and the revenue entry form and sale detail panel are now each
rendered **without** the injected source and asserted not to show *"Attaching a file is not
available on this device yet."* — the exact sentence two real devices displayed for a whole
phase (D-077). A revenue surface cannot silently resolve a picker the expense surface does
not.

*What is not:* the native interaction. The OS picker is a separate activity no harness
opens; it needs a person to open one **from a sale** on each platform. This session had no
way to perform a human interaction on the project lead's device, and driving an emulator's
picker with synthetic input events would be a different test on a different machine reported
under the same name — which is the substitution D-077 exists to forbid. The exact steps for
each platform are in `RELEASE_CHECKLIST.md` §L, as a second manual line beside the expense
one; running the expense gate does not discharge it.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 195 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,154 tests, all passing** (1,147 + 7) |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Live Slice 11 boundary group | **Tested** | **20 tests** (13 + 7), all passing; **4 of the 7 new ones failed against the unfixed server** |
| Host control — the retry pre-check | **Tested** | degraded, 2 repository tests turned RED, restored and **read back** (D-142) |
| Migration ledger parity (A0 / D-056) | **Tested** | both versions verified **byte-for-byte by hash** |
| API-surface and PUBLIC-execute invariants | **Tested** | restated in full; three additions named |
| Migration audit | **Tested** | 21 host tests, after widening a parser that could not see the new predicates at all |
| Bucket census | **Tested** | 0 stranded objects across both prefixes |
| Baseline | **Tested** | 4 live rules, 0 bands/subtypes/statuses, 0 closed periods, 0 open acceptance revenue |

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260906121007 | `attachment_upload_lifecycle` |
| 20260906121034 | `api_surface_invariant_attachment_lifecycle` |

Both verified **byte-for-byte by hash** against `supabase_migrations.schema_migrations.statements`.

### Recorded, and deliberately not fixed here

**`attachment_register` does not verify the stored object**, contrary to what
`ARCHITECTURE.md` §16.3 has claimed since D-073a. Neither register RPC reads
`storage.objects`; the size and hash are taken on trust from the caller, and it is the
*worker* that verifies the hash before calling an upload confirmed. The document is
corrected; adding the server-side read is a change to a reviewed financial boundary and
belongs in its own scope (D-127).

**A guard keyed on an incidental convention, for the third time.** The migration audit's
function parser matched only a bare `$$` body tag, so three new `security definer`
predicates were invisible to every assertion in that group — including the `search_path`
one, which is the direction that fails quietly. Widened. D-103, D-134, and now this.

---

## Phase 4 Slice 12 — Revenue reporting contributions: **COMPLETE**

The interface Phase 5 will aggregate, defined and exposed. **No P&L, no dashboard, no
export, no margin** — a test asserts the repository grew no such method, because a slice
boundary nothing evaluates is a comment (D-087).

### The design decision, and it came from reading the expense side rather than mirroring it

The brief asked whether the binding schema requires a *physical*
`revenue_period_contributions` table. It does not, and the reason is in what the two sides
actually are:

| | |
|---|---|
| `expense_period_allocations` | a **table**, because a cross-period split is a decision a person made and exists nowhere else (D-034, D-060) |
| `expense_period_contributions` | a **view** over it — and this is what `DATABASE_SCHEMA.md` calls the revenue projection *"the mirror of"* |
| `revenue_period_contributions` | a **view**, because a revenue contribution carries no decision: its period is the entry's stored `pnl_period_key` under a CHECK, its money the component's stored gross/tax/net (D-157) |

**What a stored copy would buy is nothing; what it would cost is a lifecycle.** Every
hazard the brief lists — a correction moving a period, an edit replacing figures, a void
removing an effect, a replay applying twice — is a hazard of *maintaining a second copy*.
Derived, the correction moves the period because the entry moved, and the replay has
nothing to insert twice. None of it is a rule anybody has to remember, and this project's
record is that the rules people have to remember stop being applied (D-059, D-068, D-071,
D-077).

**Two sides, one shape.** The same view exists in Postgres (`security_barrier`, scoped by
`revenue.view` per unit, base tables ungranted) and in SQLite at local schema **v15**,
column for column. Neither is writable, and no UI or client can edit a contribution amount
because there is nothing to edit.

### What contributes, and what merely exists (D-158)

Three exclusions, applied before any filter, in one shared predicate so they cannot be
present in one query and forgotten in the next:

| | |
|---|---|
| `voided_at IS NULL` | a voided sale contributes nothing and stays inspectable (D-006) |
| `scope_revoked_at IS NULL` | a retained unsent attempt over a lost property is nobody's revenue (D-070, D-074) |
| `txn_number IS NOT NULL` | **canonical only** — an unaccepted sale is an attempt, not revenue |

**Slice 12 invents no provisional model.** A labelled *"local — including N unsynced"*
operational figure is a real idea and is what §6.4's freshness vocabulary is for; it is a
Phase 5 decision nobody has approved, and shipping one here would be a second, softer
definition of revenue with nobody's name on it.

### The paisa the component grain protects

Two Restaurant days of ₹76,450 and ₹81,200:

```
        summed at the component   364048 + 386667  = 750715   <- what is reported
        the rate re-applied       15765000 x 5/105 = 750714   <- one paisa less
```

The acceptance asserts **both** figures side by side, so the difference is stated rather
than discovered. Rounding happens once, at the component; aggregates sum stored paise
(spec §6.5, D-017).

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 197 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,185 tests, all passing** (1,154 + 31) |
| Revenue contributions — figures, periods, exclusions, scope, aggregation | **Tested** | 31 host tests, incl. the v14→v15 migration and the slice-boundary assertion |
| Positive controls | **Tested** | dropping the canonical-only predicate turns 2 tests RED; dropping the void exclusion turns 1 RED; restored and **read back** (D-142) |
| Live revenue boundary suite | **Tested** | **81 tests** (61 + 8 attachment closure + 12 Slice 12), 1 deliberately skipped |
| Live two-client acceptance | **Tested** | 10 tests, incl. a contribution assertion on the §E response-loss replay |
| Live expense suite | **Tested** | **50 tests**, re-run after the shared attachment change |
| Migration ledger parity (A0 / D-056) | **Tested** | verified **byte-for-byte by hash** |
| Migration audit | **Tested** | 21 host tests |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Baseline / fixtures | **Tested** | 0 open acceptance revenue, 4 live rules, 0 bands/subtypes/statuses, 0 closed periods, 0 stranded storage objects |

### The live matrix, against `krishna-mis-dev`, through the real RPC boundary

| Case | Result |
|---|---|
| Restaurant / Nandbhog / Room / Banquet, exact gross, tax and net | **PASS** |
| Banquet reports treatment `none`, permanently distinct from a configured 0% | **PASS** |
| Multi-component document: two contributions, reconciling to `revenue_document` | **PASS** |
| An accepted edit **replaces** the contribution, not appends | **PASS** |
| A business-date correction across two open periods moves it, and one period holds it | **PASS** — `business_date_source` reads `corrected`, `KI-REV` unchanged, figures unchanged |
| A void removes the active effect and destroys nothing | **PASS** — the row remains, carrying `voided_at` |
| Create, correction and void each replayed: one contribution effect | **PASS** |
| Response-loss replay (`ControllableTransport`, D-132): one contribution | **PASS** — §E |
| Attaching evidence moves no figure | **PASS** — seven fields compared |
| A month by property and category, exact paise, consolidated | **PASS** |
| A wrong-property manager sees no contribution, by RLS | **PASS** |
| The base tables stay unreadable | **PASS** |
| An anonymous caller sees nothing | **PASS** |
| Configuration a sale was not recorded under cannot restate it | **PASS** — and the destructive form of that control (delete every rule) runs in the host suite, where the fixture is disposable rather than the approved baseline |

### Performance

`revenue_entries_reporting_idx (org_id, pnl_period_key, business_unit_id,
revenue_category_id) where voided_at is null` on the server, and
`ix_revenue_entries_reporting` locally. Filtering, scoping and the aggregate all happen in
**SQL**: a month of a property's revenue is one row off the database rather than every
component folded in Dart, which is what spec §27 asks for and what the expense side does
not yet do. No materialised aggregate: nothing has been measured that needs one.

### Expense compatibility, demonstrated rather than assumed (B30)

Phase 5 sums one shape per side of the P&L. Both projections are named
`*_period_contributions`, both are views, and both carry `org_id`, `business_unit_id`, a
`pnl_period_key` in `YYYY-MM`, integer minor units and `voided_at` with the same meaning —
the row stays, the aggregate excludes. **No second financial-date or period model is
required.** Revenue and expenses are deliberately **not** combined into a P&L table here;
the binding architecture puts that in Phase 5.

### Recorded, and deliberately not built

**There is no revenue pull.** `RevenueGateway` reads one document back for reconciliation
and nothing else, so a device's local cache holds only what that device recorded. The local
projection is therefore honest about this device and is **not** a complete reporting cache;
the server projection is the authoritative one. That is the shipped state after Slice 11
rather than something this slice changed, and it is stated so Phase 5 plans for it instead
of discovering that a manager's dashboard is empty on a new installation (D-158).

### Three fixture defects the existing suite caught (D-159)

`downgradeToV10` dropped `revenue_entry_totals` and not the new view, so a v10→v11 test
failed with `no such table: main.revenue_components` — a fixture that claims to be an older
schema has to actually be one (D-144, again). A Slice 11 test asserted
`db.schemaVersion == 14`, hard-coded, written *after* D-144 recorded the identical
correction twice. And the reporting index was added to the upgrade step and not to
`onCreate`, so a fresh database lacked it — caught by the fresh-database test.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260906124407 | `revenue_period_contributions` |

Verified **byte-for-byte by hash** against `supabase_migrations.schema_migrations.statements`.

### Local schema

**Drift v15** adds the `revenue_period_contributions` view and
`ix_revenue_entries_reporting`. No table. The upgrade step carries the D-144 range guard
`from >= 11 && from < 15`, because `revenue_entries` and `revenue_components` are created at
v11 and a view over tables that do not exist cannot be created.

### Not rerun, and why

**`phase-a`, `phase-b`, `phase-c`, `multi-scope-a`, `multi-scope-b` — not rerun.** Nothing
here touches authority caching, grants, scope resolution or purge semantics. They are **not**
claimed as freshly passing.

**The Android and Windows device acceptance suites — not rerun.** Slice 12 adds no
controller, no widget and no screen; the surfaces are untouched and a test asserts they
stay that way. The reporting query API is covered by the host and live suites.

---

## Phase 4 Slice 11 — formally closed (2026-09-06)

| | |
|---|---|
| Implementation | `ba4ffd2` |
| Corrective — the upload lifecycle after the bytes land | `bcf6f19` |
| Manual native-picker acceptance | reported by the project lead, 2026-09-06 |

### The manual gate, as reported

**Android Revenue native picker: PASS · Windows Revenue native picker: PASS**, reported by
the project lead on 2026-09-06 and recorded here as his result. This is the D-077 gate
applied to a **sale**, and it is a manual gate precisely because no harness opens an OS
picker: the observation is his, and this record says so rather than implying the suite made
it.

He states the runs exercised the real Android OS-backed picker, the real native Windows
file dialog, the shipped revenue attachment composition path, the file returning to the
revenue form and detail, and the attachment remaining associated after save and
synchronisation.

### What this repository can and cannot corroborate, stated rather than glossed

Two of those five are machine-checkable from here, and they check out:

| Claim | Status |
|---|---|
| the shipped revenue attachment composition path | **Verified** — the revenue entry form and sale detail panel use the shared `AttachmentStrip` over `attachmentSourceProvider`, and are rendered in the widget suite **without** the injected source, asserted not to show *"Attaching a file is not available on this device yet."* (D-156) |
| production resolves a real picker per platform | **Verified** — `attachment_source_wiring_test.dart`, both shipped platforms |
| the picker opened and returned a file | **Project lead's observation.** Unverifiable from here by construction — this is what a manual gate is |
| the file appeared on the revenue form / detail | **Project lead's observation** |
| the attachment remained associated **after save and synchronisation** | **Reported, not corroborated — see below** |

**`krishna-mis-dev` holds no artefact of a manual run**, and that is stated because the
record's job is to say what was verified. Checked four ways:

```
        revenue attachment rows            96  = 89 `z-report.jpg`      (automated live suites)
                                              +  7 `synthetic-receipt.jpg` (automated device
                                                   acceptance, which injects at the picker
                                                   boundary and says so in the file name)
        revenue attachment registrations   every one in the APPEND-ONLY audit trail is
                                           `giridhar@hki.com`, in four hour buckets that
                                           match the automated runs exactly
        KI-REV numbers issued              752, rows holding one 752, missing 0
        newest revenue entry               KI-REV-26-27-000546, 07:50 UTC,
                                           "Device acceptance slice11 offline evidence"
```

Nothing was created and removed: the number sequence has no gap, and `audit_logs` is
append-only by trigger.

**This is not a contradiction of the picker result**, which leaves no server trace at all
and is entirely the project lead's to report. It bears only on the **save-and-sync leg**,
and the ordinary explanations are benign — a build with no backend configured runs the
whole surface against the local seed (D-052); a picker checked to the point of the file
appearing on the form is the gate's substance and needs no save; a device that never
reconnected keeps the sale local. It is recorded so that nobody later mistakes the
automated `synthetic-receipt.jpg` rows for the manual run, and it is the one open question
under **Open questions for the project lead**.

**Slice 11 is closed on the project lead's ratification of the manual gate**, which is his
to give. The evidence state above is recorded beside it rather than instead of it.

### Cleanup and verification after the manual acceptance

| Required | Result |
|---|---|
| Void any manual test revenue through the legitimate workflow | **No-op — there is none.** 0 active revenue entries of any kind; every acceptance sale was already reversed through `revenue_void` by its own suite |
| Reconcile manual attachment objects through the normal lifecycle | **No-op — nothing stranded.** The reconciliation sweep ran and reported `0 kept, 0 reclaimed, 0 still stranded` |
| 4 verified revenue tax rules | **4** |
| 0 test bands / subtypes / premises statuses | **0 / 0 / 0** |
| 0 closed periods | **0** |
| 0 active manual acceptance revenue | **0** |
| 0 stranded Storage objects | **0** |
| Metadata ↔ object reconciliation exact | **Exact, both directions** — 96 revenue rows ↔ 96 revenue objects, 46 expense rows ↔ 46 expense objects, 0 rows without an object, 0 objects without a row |
| The three historical whitespace-reason evidence rows | **Untouched** — 1 expense, 1 revenue, 1 period reopen (D-146) |

### The proportionate closure gate

No implementation code changed for this closure, so the gate is the proportionate one:

| Item | Result |
|---|---|
| Attachment wiring and revenue attachment suites | **110 tests, all passing** |
| Storage reconciliation assertion, live | **PASS** — `0 kept, 0 reclaimed, 0 still stranded` |
| Migration ledger guard (A0 / D-056) | **PASS** — 21 migration-audit tests |
| Secret scan — tree and git history | **Clean**, controls passing |
| Clean working tree | **Clean** |

**Slice 11 COMPLETE** — `ba4ffd2` (implementation) · `bcf6f19` (corrective) · manual
acceptance reported 2026-09-06.

---

## Phase 4 Slice 12 — ratified (2026-09-06)

Implemented and committed at **`d6f0851`**; history is not rewritten or squashed.

Confirmed green after the Slice 11 closure, with nothing changed between them:

| Item | Result |
|---|---|
| Revenue contribution suite | **31 tests, all passing** |
| Attachment, wiring and migration-audit suites | **110 tests, all passing** |
| Live storage reconciliation | **PASS** |
| Migration ledger parity | **PASS**, byte-for-byte |
| Secret scan | **Clean** |
| Working tree | **Clean** |
| Baseline | 4 rules, 0 bands, 0 subtypes, 0 statuses, 0 closed periods, 0 active revenue, 0 stranded objects |

**Slice 12 COMPLETE** — `d6f0851`.

### Phase 4 completion

**12 of 14 slices complete.** Slices 1–12 are done; **Slice 13 (live and device
acceptance) and Slice 14 (closure) are not started**, and Slice 13 is not started
automatically.

---

## Phase 4 Slice 13 — full Revenue Engine acceptance: **COMPLETE**

The final integrated acceptance of the Revenue Engine, run against the current code rather
than carried forward. **One product defect found and fixed** (D-160), and two requirements
that cannot be met against the approved baseline are recorded rather than substituted
(D-161).

### The acceptance environment, stated exactly

| | |
|---|---|
| Backend | `krishna-mis-dev` only. No staging, no production |
| Android | the real dev-flavour build on the emulator (`sdk gphone16k x86_64`, Android 17 / API 37), `flutter test integration_test/device_acceptance_test.dart -d emulator-5554 --flavor dev`, `SUPABASE_URL` / `SUPABASE_ANON_KEY` from `config/dev.json` |
| Windows | the compiled `krishna_mis.exe`, `flutter test integration_test/device_acceptance_test.dart -d windows`, same configuration, on the **accumulated** local database |
| Composition | the normal application root. No test-only repository, no local-seed-only mode, no fake gateway. Identity passwords come from the git-ignored development file, exactly as every earlier acceptance |

**The ambiguity the manual picker run left is removed:** every end-to-end claim below comes
from a build explicitly configured for `krishna-mis-dev`, and each phase is one process
launch of the real application.

### The verified business baseline, read from the backend

Asserted from `krishna-mis-dev` before anything was run, not inferred from the local seed:

| Unit | Category | Rate | Treatment | Basis | Effective from | Discriminators |
|---|---|---|---|---|---|---|
| Crystal Canopy Rooftop | Restaurant | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null |
| Crystal Canopy Rooftop | Nandbhog | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null |
| Hotel Krishna Imperial | Room | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null |
| Hotel Krishna Imperial | Banquet | 0 bp | **`none`** | `inclusive_total` | 2026-04-01 | all null |

Four independent rule rows with four distinct ids — Restaurant and Nandbhog reference
nothing of each other (D-089). **0 value bands, 0 supply subtypes, 0 premises statuses.**

### The defect this slice existed to find (D-160)

`windows-revenue-edit` failed **deterministically, three runs of three**, on the accumulated
Windows database. A correction reached the server, the outbox was `done`, the repository
said `synced` — and the ledger row went on reporting `Syncing` indefinitely.

Two defects, one hiding the other:

* the assertion was `visible('Synced')`, and the Windows ledger renders its chip **compact**
  — an icon, no text. It had been passing on text belonging to the detail panel, which
  happened still to be mounted. **It had proved nothing about the ledger since Slice 10.**
* underneath it, `filteredRevenueProvider` was a `FutureProvider`. A sync state arrives from
  the **worker**, which invalidates no provider and knows about no screen — so the row kept
  whatever the query saw. That is D-131 exactly, fixed for the detail panel and left
  standing on the ledger.

Fixed at the owning layer: `RevenueRepository.watchQuery` is the same statement as `query`
(one builder, one mapper, so they cannot drift) delivered as a Drift stream over
`revenue_entries`, `revenue_components` and `sync_outbox`; the three ledger providers are
`StreamProvider`s. The acceptance now reads the **chip's own state** and waits for it to
settle. Two repository regressions, one of which is the shape of the defect.

**The cost was D-135's**, paid a second time: a streamed read model leaves a pending Drift
timer, and the Android revenue UI suite hung until it used the `uiTest` wrapper that exists
for exactly this.

### What was freshly rerun on the current checkpoint

Nothing is carried forward. Every line below ran after the final `lib/` change.

| Suite | Result |
|---|---|
| Android device chain — `revenue-entry`, `-banquet-label`, `-edit`, `-edit-banquet`, `-conflict`, `-void`, `-user-switch`, `-offline`, `-attachment`, `-attachment-offline`, `d068-switch`, `d068-revoke` | **12 phases, all PASS** |
| Windows chain — `windows-revenue`, `-edit`, `-void`, `-conflict`, `-offline`, `windows-ledger`, `revenue-attachment`, `-attachment-offline`, `d068-switch`, `d068-revoke` | **10 phases, all PASS** |
| Live backend phase chain — `drift`, `conflict`, `revenue-sync`, `revenue-sync-offline`, `revenue-create`, `revenue-cleanup` | **all PASS** |
| Live revenue boundary suite | **81 tests**, 1 deliberately skipped |
| Live two-client acceptance | **10 tests** |
| Live expense suite | **50 tests** |
| Host suite | **1,192 tests** |

`revenue-user-switch` is an Android-only phase — it opens the entry screen from the phone's
central add action, which the desktop shell does not have. Windows user-switch coverage is
`d068-switch`, run on the accumulated database.

### The acceptance matrix

| Requirement | Result |
|---|---|
| Four verified categories, create → sync → `KI-REV` → detail → exact contribution | **PASS**, both platforms |
| Restaurant inclusive extraction, exact paise | **PASS** — ₹1,00,000 → gross 10000000, tax 476190, net 9523810 |
| Nandbhog independent, never merged into Restaurant | **PASS** — separate rule id, separate contribution line |
| Room on the current generic rule, no invented band selector | **PASS** — one plain amount field, `value_band_id` null |
| Banquet: *Amount billed to the customer*, **No GST**, tax 0, net = gross | **PASS** |
| Edit → exact recalculation, same `KI-REV`, contribution changes exactly once | **PASS** |
| Void → active contribution zero, evidence and history still explainable | **PASS** |
| Offline create → visible pending, no invented number → restart → reconnect → one sale, one number, one contribution | **PASS**, both platforms |
| D-112 freshness: 24 h window, boundary, expiry, backwards clock; a pending attempt still syncs | **PASS** (live `revenue-create`, host boundary tests) |
| Business-date cut-off through the integrated revenue path | **PASS** — 01:00 IST lands on the previous trading day; 04:59 and 05:00 on 1 July fall in **June and July** respectively, and each period totals accordingly |
| Business-date correction: reason required, `corrected`, same `KI-REV`, both periods enforced, no double count, audited | **PASS** |
| Closed period: edit, move-out and void all refused; Owner does not bypass; reopen with a real reason; period left open | **PASS** |
| Two-client stale edit → conflict → Review latest → deliberate correction accepted | **PASS** |
| Two-client stale void → conflict; voided-then-edited refused | **PASS** |
| KM030 tax-configuration mismatch → conflict, nothing applied | **PASS** (see D-161) |
| Multi-component, explicit band identity, no amount inference, rates never blended | **PASS** (see D-161) |
| Historical tax stability — configuration change cannot restate a recorded figure | **PASS** |
| D-070 confirmed revocation; a failed refresh purges nothing | **PASS**, both platforms |
| D-074 user switch on an accumulated database | **PASS**, both platforms |
| ReferenceSync — both units complete, empty datasets distinguishable from unavailable, restart, offline resolver | **PASS** |
| Reporting contributions, four categories + synthetic month + consolidated | **PASS** |
| Attachment lifecycle and security; storage reconciliation | **PASS** |
| Response-loss matrix — create, update, void, attachment register | **PASS** |
| Accumulated database — Windows ledger, detail, reporting, user switch | **PASS** |
| Layout at 1366, resized and maximised, in every sync state | **PASS** |
| Server security — anonymous, wrong unit, scoped manager, Owner | **PASS** |

### Performance sanity (item 29)

Not a benchmark. What was inspected:

* the ledger filters, orders, pages and scopes **in SQL**, with one `LIMIT ? OFFSET ?`;
* the contribution aggregation is one `SUM` row off the database, never a fold in Dart;
* the row mapper performs **no** per-row `await` — no N+1;
* on the real server, a monthly aggregation plans as
  `Index Scan using revenue_entries_reporting_idx … Index Cond: (org_id, pnl_period_key)`
  then an index scan on `revenue_components_entry_idx` — no sequential scan of components.

No actionable regression. No materialised aggregate added: nothing has been measured that
needs one.

### Clean artefacts (item 31)

Rebuilt **without** acceptance identity defines, then scanned:

| | |
|---|---|
| Android | `build/app/outputs/flutter-apk/app-dev-debug.apk`, dev flavour, `config/dev.json` only |
| Windows | `build/windows/x64/runner/Release/`, release, same configuration |

The scan **found a stale acceptance intermediate first** — a Windows *Debug* bundle whose
`kernel_blob.bin` still carried a development identity password from the acceptance runs.
It was removed and the scan re-run. That is the scanner doing its job (D-069), and it is why
"build clean, then scan the actual artefacts" is a step rather than an assumption.

Afterwards: **tree, git history and built artefacts all clean.** The production adapters and
the revenue surfaces are demonstrably compiled in — `AndroidAttachmentSource`,
`WindowsAttachmentSource`, `useAndroidPhotoPicker`, `RevenueEntryPage`, `RevenueLedgerPage`
and `revenue_period_contributions` all present in the APK payload, and the Windows AOT
image carrying its own platform's adapter and the same surfaces.

### Fresh-migration provisioning gate (item 30)

**Not run, and deliberately not provisioned.** A full migration-chain replay against a
genuinely fresh Postgres needs a Supabase branch, which is a paid resource and was not
created unilaterally. What *is* green: migration ledger parity byte-for-byte, repository
provenance (every applied version accounted for by a committed file), the local fresh-schema
and upgrade tests, and both API-surface invariants.

**Recorded as a staging-setup gate:** run the branch replay once before the first staging
deploy, together with the reason-constraint validation D-146 records.

### Live cleanup and baseline (item 32)

Every acceptance sale reversed through the real `revenue_void`; expense fixtures reversed;
development grant fixtures restored; storage reconciled through the ordinary reclamation
policy.

| Required | Result |
|---|---|
| Verified live revenue rules | **4** |
| Test bands / subtypes / premises statuses | **0 / 0 / 0** |
| Closed periods | **0** |
| Active acceptance revenue | **0** |
| Active acceptance expenses | **0** |
| Stranded Storage objects | **0** |
| Metadata ↔ Storage | **Exact both ways** — 118 revenue rows ↔ 118 objects, 46 expense rows ↔ 46 objects |
| Authority fixture | **Restored** — 5 grants, the development baseline |
| The three immutable whitespace-reason evidence rows | **Untouched** (1 expense, 1 revenue, 1 reopen) |

### No new features

No P&L, no dashboard, no export, no tax administration, no attachment removal, no new
revenue category, no production domain routing. The only `lib/` change is D-160's fix, and a
test asserts the reporting layer still names no P&L, Net Sales, Operating Profit or Export.

**No product gap was found.** Everything the acceptance exercised exists; what it found was
one defect and one dishonest assertion.

---

# PHASE 4 — REVENUE ENGINE: COMPLETE

Closed 2026-09-07. Slices 1–14. Master Spec **v1.2**.

Phase 4 built the revenue half of the MIS: a document-with-components model, conditional
tax resolution over five bounded dimensions, offline creation with a freshness gate,
correction and void under governed capability, evidence, and the reporting interface Phase 5
will aggregate. **It builds no P&L**, by design (D-087).

## 1 · The final domain, as shipped

| | |
|---|---|
| Business units | Crystal Canopy Rooftop · Hotel Krishna Imperial |
| Revenue categories | CCR: **Restaurant**, **Nandbhog** · HKI: **Room**, **Banquet** |
| Other Income | **not in V1** (spec §28/§29) |
| Model | Revenue Entry → 1..n Revenue Components → contributions **derived** from accepted components |
| Header totals | not stored, on either side — derived by `revenue_document` and `revenue_entry_totals` |

### The verified configuration, read from `krishna-mis-dev` at closure

| Unit | Category | Rate | Treatment | Basis | Effective from | Discriminators |
|---|---|---|---|---|---|---|
| CCR | Restaurant | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null |
| CCR | Nandbhog | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null |
| HKI | Room | 500 bp | `inclusive` | `inclusive_total` | 2026-04-01 | all null — **no Room band configured** |
| HKI | Banquet | 0 bp | **`none`** | `inclusive_total` | 2026-04-01 | all null |

**Four independent rule rows with four distinct ids.** Restaurant and Nandbhog reference
nothing of each other (D-089). **Banquet's treatment is `none`, which is not a configured
0%** — one is a decision somebody made, the other a rate somebody set, and reporting carries
the treatment so Phase 5 can tell them apart (D-091).

**0 value bands · 0 supply subtypes · 0 premises statuses.**

## 2 · Financial semantics

Integer paise only; no binary floating point touches a stored or computed amount. Tax is
extracted **half-up, once, at the component**, and stored; aggregates sum stored paise and
never re-apply a rate to a total.

```
        Restaurant, ₹1,00,000 billed to the customer, inclusive 5%

        entered_amount    10000000 paise   (the customer total, entered_basis inclusive_total)
        tax   = round_half_up(10000000 × 500 ÷ 10500)  =   476190
        gross = entered                                 = 10000000
        net   = gross − tax                             =  9523810      ₹95,238.10

        Banquet, ₹40,343, treatment `none`
        tax = 0 · gross = net = 4034300
```

**And the paisa the component grain protects.** Two Restaurant days of ₹76,450 and ₹81,200:

```
        summed at the component   364048 + 386667  = 750715   ← what is reported
        the rate re-applied       15765000 × 5/105 = 750714   ← one paisa less
```

Both figures are asserted side by side in the suite, so the difference is stated rather than
discovered. `net = gross − tax` is a database CHECK on every component, and no historical
figure is ever re-rated: every rate, treatment, basis and band on a contribution is the
snapshot the component recorded when the server accepted it.

## 3 · Business date and period

`business_date` is derived under the property's IANA timezone and cut-off — currently
**05:00** local, configurable per unit — never the raw device clock and never the database
session's calendar date (D-019, D-067). It is **persisted**, and `pnl_period_key` is tied to
it by a CHECK. Reporting reads the stored date; no document implies the device calendar
decides anything financial.

A correction requires `transaction.correct.business_date`, a non-whitespace reason, and
**both the source and the target period open**. It writes `business_date_source =
'corrected'` — revenue has exactly two values, `derived` and `corrected`, because no revenue
surface offers a trading day at entry (D-143). A closed period rejects every create, edit,
void and correction affecting it; only the Owner reopens, with a stated reason, audited.

## 4 · Correction and concurrency

`revenue_update` is the one contract. **There is no `revenue_correct_business_date` and no
fourth revenue RPC** — the phantom endpoints three documents once named are gone from the
documents as well as absent from the server (D-127, D-137).

`KI-REV` is stable across every correction. `base_row_version` on update and void; a stale
version is a **Conflict** a person resolves — no auto-merge, no silent rebase, no silent
repricing. The server re-resolves the tax and **compares** the client's declared figures,
refusing `KM030` on disagreement rather than replacing them (D-114). Redelivery of the same
`mutation_id` replays; a lost response recovers by redelivering the same intent. A voided
document accepts no edit.

## 5 · Void

Capability only, a **mandatory reason that is refused when it is whitespace of any kind**,
an open period, a matching row version. The document, its number, its components and their
snapshots all remain; the active reporting contribution goes; attachments are retained as
evidence; replay is idempotent.

The whitespace rule is one rule for all five mandatory financial reasons — expense void,
revenue void, both business-date corrections, and period reopen — stated in spec §14.1 as a
requirement. **The mechanism is deliberately not in the spec**: `app.stated_reason` is an
implementation detail recorded in `ARCHITECTURE.md` and the decision log, and a sixth act
carrying a mandatory reason joins the rule rather than inventing its own (D-142, D-145).

## 6 · Offline

New revenue may be created offline only when **all** of these hold: the local authority
permits it, a complete authoritative configuration snapshot exists for that user and unit,
D-112 freshness permits, exactly one rule resolves per component, and every required
conditional fact is present. Otherwise the save is **refused and nothing is queued** —
unlike an expense, whose correctness does not depend on configuration the device may lack
(D-086, D-113).

**D-112, final values:** a snapshot may support new offline creation for **24 hours** from
its server-confirmed timestamp, **inclusive at the boundary**; past that, new offline
revenue is refused. A device clock reading **more than five minutes earlier** than that
confirmation reports `clockUnreliable` rather than `expired`, because "your clock is wrong"
sends somebody to fix a different thing (D-117).

**Existing pending work survives expiry.** An attempt created while fresh and still queued
at thirty hours is submitted unchanged, carrying its own snapshot; the server decides.
**D-112 is not a general master-data TTL** and must not be restated as one.

## 7 · Reference configuration

Completeness is recorded **per user, per business unit**, naming the datasets proven
present, the server generation and the server-confirmed time (D-108). The snapshot is
categories + tax rules + value bands + supply subtypes + premises statuses — all of them or
none, because the resolver consults all of them.

**Zero rows in an optional dataset is a valid synchronised answer** — the verified baseline
has exactly that — and stays distinguishable from never having asked. Completeness is never
inferred from a row count, and `configurationUnavailable` is decided *before* the cache is
queried (D-106).

## 8 · The Room conditional architecture

Dimensions: category · effective/business date · value band · supply subtype · premises tax
status. **Zero matches refuses, exactly one resolves, more than one is refused** — no
specificity ranking, and a null discriminator is a wildcard that *collides* with a specific
rule rather than losing to it (D-079, D-094).

**An amount never chooses a band.** `RevenueTaxFacts` carries no monetary field at all, so
the mistake is unavailable rather than discouraged. A band's boundaries are write-once;
supersession creates a **new band identity** pointing back at the old one (D-100).

**The live Room baseline remains generic, with no band configured.**

## 9 · Attachments

Shared with expenses — one lifecycle, one worker, one backoff clock, one private bucket
under two path prefixes decided by two policies (D-147, D-149). Offline staging with a
stable client-generated identity; ordered upload that cannot precede its parent's
acceptance; idempotent registration; response-loss recovery; **canonical evidence cannot be
overwritten**; **no upload to a voided parent**, refused at the object write *and* at
registration; bytes a terminal refusal strands are reclaimed by their uploader, and an
object a metadata row names cannot be touched (D-154, D-155).

Attaching is **not editing**: no `base_row_version`, no outbox intent, no row-version
advance, and no amount, tax figure, date or number changes. D-070 and D-074 apply to
evidence exactly as to the document. **V1 ships no attachment removal for either kind**, and
`revenue_attachments` carries no removal columns at all.

**The two acceptance claims are kept apart, and must stay apart:**

| | |
|---|---|
| **A · the OS picker itself** | manual, per platform, on real devices — **Android PASS · Windows PASS**, reported by the project lead 2026-09-06. No harness opens an OS picker |
| **B · the backend lifecycle** | automated, through the real configured app against `krishna-mis-dev` — staging, ordering, upload, registration, retry, restart, security |

Neither is the other, and the record does not collapse them (D-077, D-156).

## 10 · Reporting contributions

`revenue_period_contributions` is a **derived view** on both sides — a
`security_barrier` view in Postgres, a view in SQLite — and never a second writable
financial truth source. **Canonical truth is the revenue components plus the parent
document's state.**

One row per component, carrying business unit, revenue category, business date, `pnl_date`,
`pnl_period_key`, gross/tax/net in paise, and the rule snapshot. A correction moves the
period because the entry moved; a void removes the effect because the entry is voided; an
edit replaces the figures because the components were replaced; a replay has nothing to
insert twice. Pending, rejected and conflicted attempts are excluded — an unaccepted sale is
an attempt, not revenue (D-157, D-158).

## 11 · Security and authority

RLS on every table in `public`, default-deny. **No client role holds INSERT, UPDATE, DELETE
or TRUNCATE on anything in `public`** — restated over all four privileges at closure, after
the audit found TRUNCATE surviving a three-word revoke on four financial tables (D-162).
`authenticated` holds no `SELECT` on `expenses`, `revenue_entries` or `revenue_components`;
the projections are the only way in.

Every `SECURITY DEFINER` function pins its `search_path`; nothing in `public` is callable by
`anon`; nothing in `app` is callable by any client role; no RLS policy references the `app`
schema. Permission is decided before existence is revealed. Authority is capability plus
business-unit scope — **no role name appears in financial logic**. D-070 confirmed
revocation and D-074 user-switch isolation are proven on both platforms against an
accumulated database, and the distinction between canonical scoped history and retained
actor-owned work holds.

Storage: private bucket, no signed-URL issuer and none required, read authority from the
parent document, **write authority strictly narrower than read** (a voided parent is
readable and accepts nothing), and metadata ↔ object reconciliation exact.

## 12 · D-146 — the fresh-branch gate, NOT run

**A full migration-chain replay against a genuinely provisioned fresh Supabase branch has
not been run, and is not claimed.** It needs a separately provisioned paid resource and one
was not created unilaterally.

**Recorded as a mandatory staging-provisioning gate before the first staging deployment.**
At that gate, require: the full chain from zero; the reason constraints **validate** on
clean history; every API function exists exactly once; RLS and Storage policies install;
bucket policies install; the baseline configuration applies; and no development-only
historical evidence contaminates staging.

**This does not block Phase 4 code closure.** What is proven meanwhile: ledger parity
byte-for-byte, repository provenance, the throwaway-schema constraint replay, the local
fresh-schema and upgrade tests, and both API-surface invariants.

## 13 · D-161 — synthetic versus live acceptance evidence

Preserved exactly, because the distinction is the evidence:

* **Generic live Room baseline** — accepted end to end against `krishna-mis-dev`.
* **Multi-band semantics** — proven **synthetically** at host level, with two bands at
  different rates. A live Room band would require end-dating the approved baseline rule
  (D-093, D-096), and `revenue_tax_rule_end_date` offers no path back.
* **Configuration-change / KM030 semantics** — proven with governed synthetic fixtures and,
  on the real server, through declared figures that disagree with the configured rate. The
  variant where the rule itself moves underneath the client is **not** run live.

**No document claims that live production-like Room tariff band acceptance passed against
the approved baseline**, because it did not.

## 14 · Development historical evidence rows

Three rows in `krishna-mis-dev` carry a whitespace-only mandatory reason. Each was created
deliberately to prove a defect before it was fixed, and each lives in a table that correctly
refuses to be rewritten (D-006):

| Table | Row |
|---|---|
| `expenses` | the void probe |
| `revenue_entries` | the void probe |
| `period_lock_events` | the reopen probe |

They are **not damage and are not to be modified or deleted.** The corresponding CHECK
constraints are `NOT VALID` **on this database only**: the migration installs each one and
then counts the rows that would violate it, so a clean environment validates fully and
`krishna-mis-dev` stays unvalidated and says why (D-146). **Future writes are protected
either way** — the constraint is enforced on every new row, and the boundary refuses a
whitespace reason before the constraint is ever reached.

## 15 · Material Phase 4 defects found and fixed

Every one passed review, a clean analyze and a green suite before it was found.

| | Defect | Found by |
|---|---|---|
| A0, D-102 | migration ledger provenance gap — seven ledger versions, two committed files; then two migrations applied and never committed | making the ledger mechanical |
| A1 | a legacy write path could create a rule with no `input_basis`, which the resolver then refused for ever | probing the boundary |
| A2 | premises status was **not deterministic** — two open-ended rows both applicable on one date | probing the boundary |
| D-093 | the shipped exclusion constraint **forbade the approved Room feature** | auditing the tree before writing Phase 4 code |
| D-100 | value-band boundaries were editable in place, retroactively redefining what every rule referencing them applied to | auditing Slice 3 before mirroring it |
| D-101 | four `app` functions left executable by client roles; the read projection unusable by every authorised user | the deploy invariants |
| D-104 | `EnteredBasis` written and read through Dart's `.name` while both schemas store `inclusive_total` — every rule would have thrown on read | the first test to cross the boundary |
| D-115 | **`revenue_create` had never successfully created an entry** — an ambiguous column in its own `on conflict` target | the first test to call it rather than the boundary around it |
| D-116 | three revenue read rules required `revenue.view.all`, **a capability no role holds** | the same |
| D-130 | a conflict was **unresolvable through the shipped path** — a re-applied correction carried the version it had already been refused on | the two-client acceptance |
| D-131 | the detail panel and the ledger derived one fact two ways; the panel reported `Synced` for a sale in conflict | the Windows acceptance |
| D-136 … D-139 | an expense could be moved **out of a closed month**; `transaction.correct.business_date` was granted and evaluated by nothing; a corrected date was not marked corrected | auditing the correction path |
| D-142, D-145 | a single tab satisfied every mandatory financial reason — two documents voided and a closed period reopened with nothing on the record | probing all five acts |
| D-154, D-155 | Storage accepted bytes for a voided parent the register RPC would refuse, stranding objects for ever; registered evidence could be overwritten | auditing the eight orphan objects instead of labelling them |
| D-160 | the Windows ledger showed a **stale sync state indefinitely**, hidden since Slice 10 by an assertion reading a different surface | the Slice 13 acceptance |
| D-162 | **TRUNCATE** survived a three-word revoke on four financial base tables | the Slice 14 closure audit |

The pattern worth carrying forward: **most of these were found by asking what a rule
actually evaluates to, not by reading it.** D-068, D-071, D-077, D-103, D-134, D-139, D-160
and D-162 are all one family — a check that passed for a reason other than the one it
stated.

## 16 · Open defects at closure

**None.** No known revenue correctness defect and no known revenue security defect remains.

Not defects, and not counted as such: the D-146 staging-provisioning gate, the D-161
synthetic/live evidence distinction, and the undefined Phase 6–8 scope. These are follow-up
and governance items.

## 17 · Release artefact status

| | |
|---|---|
| Android | `build/app/outputs/flutter-apk/app-dev-debug.apk` — dev flavour, application id `in.krishnaimperial.mis.dev`, `config/dev.json` only, debug-key signed |
| Windows | `build/windows/x64/runner/Release/` — `krishna_mis.exe` with its plugin DLLs and `data/app.so` |

Both rebuilt **without acceptance identity defines** and scanned clean, with the production
attachment adapters and the revenue surfaces verified present in the compiled payloads.

**These are development acceptance artefacts. They are not production releases.** Phase 9
owns production signing, the Android AAB and Play distribution, the Windows installer, the
production endpoint and configuration, and production release hardening.

## 18 · Domain note

`hotelkrishnaimperial.in` exists and may later serve branded support and deployment
endpoints — privacy and support pages, Windows downloads, app and deep-link metadata, or
branded production backend routing where supported. **No Phase 4 architecture depends on
it**, and none should: this belongs to the later deployment roadmap, not to revenue
financial logic.

## 19 · Phase 5 handoff contract

**Phase 5 may treat these as stable.**

*Revenue* — the canonical accepted revenue components, and `revenue_period_contributions`
with exact `business_unit_id`, `revenue_category_id`, `pnl_period_key`, `gross_minor`,
`tax_minor` and `net_minor` in integer paise, one row per component, plus `voided_at`.

*Expenses* — the existing `expense_period_contributions` architecture, unchanged.

Both projections share one vocabulary: `org_id`, `business_unit_id`, a `pnl_period_key` in
`YYYY-MM`, integer minor units, and `voided_at` with the same meaning — the row stays, the
aggregate excludes. **No second financial-date or period model is required.**

**Phase 5 must not:** re-run tax rules; infer GST from revenue totals; include pending,
rejected or conflicted attempts; reinterpret the business date; or mutate closed history.

**And one thing Phase 5 will need that Phase 4 did not build:** there is **no revenue
pull**. A device's local cache holds only what that device recorded, so the local projection
is honest about this device and is not a complete reporting cache; the server projection is
the authoritative one. A dashboard that must be correct offline on a fresh installation
needs a pull first (D-158).

### The aggregation, conceptually

```
        Crystal Canopy Rooftop, one period
          Restaurant gross + Nandbhog gross   = Total Sales
          Restaurant tax   + Nandbhog tax     = GST
          Restaurant net   + Nandbhog net     = Net Sales

        Hotel Krishna Imperial, the same over Room + Banquet

        Net Sales − canonical Expense contributions = Operating Profit
```

Summed from stored paise, never by re-applying a rate to a total. **Phase 4 implements none
of this**, and no calculation screen exists.

## 20 · Roadmap after Phase 4

| Phase | Status |
|---|---|
| 4 — Revenue Engine | **COMPLETE** |
| 5 — Ledger & Reporting Engine (P&L / MIS reporting) | next; named in spec §34, not yet planned in slices |
| 6 — Dashboard & Analytics | **named in spec §34 only. To be formally planned** |
| 7 — Export & Printing | **named in spec §34 only. To be formally planned** |
| 8 — Production Hardening | **named in spec §34 only. To be formally planned** |
| 9 — Distribution | responsibilities already documented (signing, AAB, installer, production configuration) |

Phases 6–8 have headline names and **no recorded scope or slice plan**. Nothing here invents
one. A roadmap-planning session may follow this closure.

## 21 · Closure verification

| Item | Result |
|---|---|
| `dart format --set-exit-if-changed` | clean, 197 files |
| `flutter analyze` | **No issues found** |
| Host suite | **1,192 tests, all passing** |
| Live revenue boundary suite | **81**, 1 deliberately skipped |
| Live expense suite | **50** |
| Live two-client acceptance | **10** |
| Live backend phase chain | 6 phases |
| Android device phases (Slice 13, current code) | **12** |
| Windows device phases (Slice 13, current code) | **10** |
| Migration audit and schema parity | **38** host tests |
| Secret scan — tree, git history, built artefacts | clean, controls passing |
| Applied migrations / committed files | **72 / 65**, every version accounted for (A0) |
| Working tree | clean |

**Freshly rerun for this slice:** the full host suite, the migration and API-surface guards,
the live revenue and live expense suites (after the D-162 revoke, to prove no read path
broke), and the secret scan over tree, history and rebuilt artefacts. The Android and
Windows device phases were run at Slice 13 on this same code; Slice 14 changed no
application code, so they are reported with their Slice 13 provenance rather than re-claimed.

### Final baseline on `krishna-mis-dev`

4 live rules · 0 bands · 0 subtypes · 0 premises statuses · 0 closed periods · 0 active
revenue · 0 active acceptance expenses · 0 stranded objects · metadata ↔ storage exact
(132/132 revenue, 46/46 expense) · 5 authority grants restored · the three historical
whitespace evidence rows untouched.

---

# PHASE 5 — P&L / MIS REPORTING: STARTED (2026-09-07)

Phase 4 closed at `96fc4ed`. Phase 5 turns the two accepted transaction engines into
management P&L. It was planned by an audit of the shipped code and the live
`krishna-mis-dev` schema, not from the roadmap headline, and the project lead ratified the
result. **Phase 5 builds no dashboard, no charts, no PDF and no Excel** — those are Phases
6 and 7.

## The ratified decisions

Recorded in full as **D-163 … D-173**. In brief:

| | |
|---|---|
| **D-163** | A P&L **refuses** rather than rendering one side against a zero it cannot see |
| **D-164** | Unit P&L needs `reports.view` ∩ `revenue.view` ∩ `expense.view.all`; consolidated needs all three unscoped. `expense.view.own` does not qualify |
| **D-165** | A reporting week is **Monday–Sunday** on the **business date** |
| **D-166** | Phase 5 includes **read-only** transaction drill-down; charts stay Phase 6 |
| **D-167** | **No provisional P&L** in V1 — canonical accepted facts only |
| **D-168** | Pending expense attempts contribute **zero** (closes finding E2) |
| **D-169** | `expense.view.own` means **own** (closes finding E1) |
| **D-170** | Retention is current + previous FY; *not downloaded* is **not** zero |
| **D-171** | The reporting cache is its **own authority class**, not rows in the transaction tables |
| **D-172** | A delta watermark is **proven**, not assumed — on both engines |
| **D-173** | The remote-reporting gap is **both engines** |

**Offline P&L was not put to the project lead as a decision**, because it is not one:
`CLAUDE.md`'s hard constraints and spec §21.2 / §21.4 already require that reporting is
never gated on the network and that every figure carries a freshness state.

## Handoff correction — the pull gap is both engines (D-173)

**Phase 4's history is not rewritten.** This is a Phase 5 planning correction to the
handoff contract recorded in *PHASE 4 — REVENUE ENGINE: COMPLETE* §19.

That contract states, correctly, that there is no revenue pull — and states it as a
revenue-only fact. **Expenses have no reporting synchronisation either.**
`ExpensePull.pullOne(expenseId)` fetches one document by id, and its only production caller
is the Review-latest path in `edit_launcher.dart`. That is conflict resolution, not
reporting.

So a device can report only the transactions **it recorded itself**, on both engines. The
server side is not the gap: both contribution projections are `SELECT`-granted to
`authenticated` and reachable, with the base tables ungranted. Slice 4 therefore carries
**two** pulls and proves remote propagation for expenses as well as revenue.

## The reporting architecture, as approved

```
        canonical contribution synchronisation      (the grain a P&L sums)
      + scoped delta snapshot                       (one watermark, proven — D-172)
      + a DEDICATED canonical reporting cache       (its own authority class — D-171)
      + LocalReportingEngine   (default on every screen, works offline)
      + RemoteReportingEngine  (parity-proven, build-failing — D-020, spec §21.3)
```

All derived arithmetic — Net Sales, Operating Profit, margin — lives once in
`lib/domain/finance/`, which **does not yet exist** and is Slice 2's first act. Engines
return summed paise and perform no business arithmetic (spec §21.2).

## The approved slice plan

Twelve slices, sequenced so financial correctness and remote completeness are proven before
any surface exists. **One slice at a time**, each with its own acceptance evidence; slices
are not merged because they could be implemented quickly.

| # | Slice | State |
|---|---|---|
| 1 | Source parity and the canonical-only correction (E1–E4) | **COMPLETE** |
| 2 | `domain/finance` — the canonical calculation specification | **COMPLETE** |
| 3 | `LocalReportingEngine` | **COMPLETE** |
| 4 | Canonical reporting cache + synchronisation completeness (D-171, D-172, D-173) | **COMPLETE** |
| 5 | Server reporting boundary + `RemoteReportingEngine` parity | **COMPLETE** |
| 6 | Freshness, as-of and closed periods | **COMPLETE** |
| 7 | The reporting capability model (D-163, D-164) | **COMPLETE** (D-220…D-222) |
| 8 | Windows P&L surface | **COMPLETE** (D-223…D-227) |
| 9 | Android P&L surface | **COMPLETE** (D-228…D-232; emulator acceptance, physical-device pass pending — *superseded: physical pass done 2026-09-17, §O.2*) |
| 10 | Breakdowns + read-only transaction drill-down (D-166) | **COMPLETE** (D-233…D-239; emulator acceptance, physical-device pass pending — *superseded: physical pass done 2026-09-17, §P.2*) |
| 11 | Full live / device / two-client acceptance | not started |
| 12 | Closure | not started |

## The four findings Slice 1 owns

Found by the planning audit, proven against `krishna-mis-dev` and the shipped test suite:

| | |
|---|---|
| **E1** | `expense.view.own` grants unit-wide expense visibility — no read path applies a `created_by` predicate (D-169) |
| **E2** | The expense reporting total counts **pending, never-accepted** documents while revenue's excludes them (D-168) |
| **E3** | The shipped expense reporting aggregate folds financial rows in Dart; revenue aggregates in SQL |
| **E4** | `DATABASE_SCHEMA.md` §11 names `v_expense_period_lines` and `v_revenue_lines` as *"THE reporting surface"* — **neither exists**, and the documented SQL references columns that do not exist |

---

## Phase 5 Slice 1 — source parity and the canonical-only correction: **COMPLETE**

Four findings from the planning audit, each proven red before it was fixed. Slice 1 builds
**no P&L, no engine, no cache, no pull and no surface** — those are Slices 2 to 5, and
nothing here anticipates them.

Decisions: D-168 (canonical-only), D-169 (`expense.view.own`), and D-174, which this slice
introduced and caught.

### E1 · `expense.view.own` granted the property, not the author

The catalogue describes it as *"View expenses this user created"*. No read path anywhere
applied a `created_by` predicate — verified by exhaustive search of every policy, view and
function in `public` and `app`. Read as the development Data Entry identity, which holds
`expense.view.own` on Crystal Canopy and nothing else:

| Surface | RED | GREEN |
|---|---|---|
| `expense_document` | 787 rows, **724 other people's** | **63**, 0 |
| `expense_period_contributions` | 865 rows, **802 other people's** | **63**, 0 |
| `expense_allocations` | 787 rows, **724 other people's** | **63**, 0 |

It included every expense the Owner and both managers had recorded.

**Ownership is a property of a document, and a set of unit ids cannot express "mine".** So
`expense_visible_units()` is unchanged and keeps answering *whose lines*, and a new
`public.may_read_expense(uuid)` answers *whether this document at all*. The document
predicate is `AND`-ed into every expense read path — it has to be every one, because
`expense_allocations_read` is line-level and would otherwise go on handing a `view.own`
holder another author's rows through the child table.

**Every consumer was enumerated before the shared predicate moved**, as the brief required:
the two child-table read policies, the `expenses` policy, four expressions inside
`expense_document`, `expense_period_contributions`, `expense_attachments_read`,
`may_read_expense_attachments`, and through it `may_attach_to_expense` and the three
Storage policies. A deploy-time invariant now enumerates those paths **from the catalogue**
rather than from a list, so the next read path added cannot escape it.

**It can only narrow.** For a pure `view.all` holder the own-branch is unreachable and the
predicate reduces to exactly the old one.

### The live authorization matrix

Through the real PostgREST client, as a permanent test rather than a probe:

| Identity | Documents | Foreign-document probe |
|---|---|---|
| Owner — unscoped `view.all` | 787 | visible |
| CCR manager — `view.all` CCR | 787 | visible |
| HKI manager — `view.all` HKI | 121 | visible |
| Accountant — `view.all` CCR | 787 | visible |
| **Data Entry — `view.own` CCR** | **63, none another author's** | **invisible** |

Non-enumeration is asserted in both directions: the colleague's document is absent from a
listing **and** unreachable by naming its id, which matters because seeded ids are
derivable (D-040, D-046). The child tables and the reporting projection are asserted to
agree with the document projection, so an aggregate cannot total rows whose documents the
reader cannot open.

**One behavioural consequence, stated rather than discovered later:** a Data Entry user can
now attach evidence only to documents they recorded. Attaching to a manager's expense was
never a designed workflow; it followed from the defect.

### D-174 · the regression the E1 migration introduced, and the guard for it

`expense_view_own_means_own` rebuilt `expense_attachments_read` from the migration that
first **created** it rather than the one that last **replaced** it, reinstating an inline
read of `public.expenses` inside a policy expression. A policy runs with the querying
user's privileges and no client role may read that table, so `expense_attachments` became
unreadable by **everybody, the Owner included**:

```
        select count(*) from public.expense_attachments
          -> 42501: permission denied for table expenses
```

Fail-closed rather than a leak, and still a defect. Found by widening the probe rather than
by review, fixed in its own migration, and now guarded generally: no RLS policy on a
financial relation may read a financial base table inline. Owner reads 46 attachment rows
again; Data Entry reads 0, which is correct — it recorded none.

### E2 · the two engines disagreed about what counts

`RevenueRepository` applied three exclusions — voided, scope-revoked and **canonical-only**.
`ExpenseRepository` applied the first two. Combined into a P&L that subtracts costs the
server has never accepted from sales it has: **Operating Profit understated, silently,
always in the same direction.**

Proven by the shipped suite rather than by reading it. `expense_repository_test:328` called
`save()` → `createLocally` alone, never synced, `txn_number` NULL, and asserted a figure.

Exact before and after, from the fixtures that turned red:

| Fixture | Before | After |
|---|---|---|
| simple expense, one period | ₹2,000 | **₹0** |
| shared + cross-period, per unit | ₹12,500 | **₹0** |
| odd amount split three ways | ₹1,000.01 | **₹0** |
| June salary paid 5 July | ₹80,000 | **₹0** |

Six existing assertions failed on the figures — the change the project lead ratified. Each
fixture now records what the reporting rule is about: an **accepted** expense.

**The canonical reporting predicate, one rule on both engines:**

```
        contributes  ⟺  txn_number IS NOT NULL      -- server-accepted
                    AND  voided_at IS NULL           -- D-006
                    AND  scope_revoked_at IS NULL    -- D-070, D-074
```

Canonical acceptance is read from the authoritative document state, never inferred from
sync UI text. `txn_number` is issued by the server on acceptance and by nothing else, tied
to `financial_year` by a check constraint, and no client can invent one (D-008, D-085).

**Positive control, seen to fail:** with the canonical clause removed from the shared
predicate, 3 of the new tests turn red. Restored and read back (D-142).

### E3 · reporting aggregates in SQL, over a named projection

The shipped expense reporting path folded financial rows in Dart and took only a period
key. It now reads `expense_period_contributions` — a named projection on both sides — and
aggregates in SQL: `contributions`, `contributionTotals` and `contributionTotalsByCategory`
over **one shared predicate**, mirroring revenue exactly.

The range filters `pnl_date`, never the business date: a June salary paid on 5 July is a
June cost, and filtering the operational date would put it in July (D-016, spec §5.3).

**Local schema v16** adds the projection and `ix_expense_contributions_reporting`. No
version floor, and that is a claim rather than an oversight — the expense tables arrive at
v7 and `scope_revoked_at` at v9, and the v9 step runs before this one in source order. A
test holds that ordering, because a step that only ever ran against a fresh database would
not notice it being reordered (D-144).

### E4 · a documented reporting surface that never existed

`DATABASE_SCHEMA.md` §11 named `v_expense_period_lines` and `v_revenue_lines` and called
the first *"THE expense reporting surface"*. **Neither has ever existed** — not on
`krishna-mis-dev`, not in any migration, not in `lib/` — and the SQL sketched for the first
referenced `expense_allocation_id` (the real column is `allocation_id`) and
`a.status = 'active'` on a table with no status column, so it could not have run. §11 now
documents the two projections that are real, the vocabulary they share, where they
legitimately differ, and what is still missing.

### Three fixture defects the existing suite caught

Three hand-built migration fixtures stamped `user_version` 9, 12 and 14 while omitting the
expense tables every real database of those versions carries — they arrive at v7. Harmless
until a later step read them, and then it failed in three files at once. Completed rather
than worked around, with the DDL in one place: the third time (D-073a, D-159, this). One
more hard-coded schema version was replaced with a lower bound, for the same reason, also
the third time.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 197 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,206 tests, all passing** (1,192 + 14) |
| Canonical-only reporting, both engines | **Tested** | 9 host tests + a control that turns 3 red |
| Local v15 → v16 migration and fresh schema | **Tested** | 5 host tests |
| Migration audit and backend schema parity | **Tested** | 38 host tests |
| Live expense suite against `krishna-mis-dev` | **Tested** | **56 tests** (50 + 6 new) |
| Live D-169 authorization matrix | **Tested** | 5 identities, through the real client |
| Migration ledger parity (A0 / D-056) | **Tested** | three versions verified **byte-for-byte by hash** |
| API-surface and PUBLIC-execute invariants | **Tested** | restated in full; `may_read_expense` named |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Live fixtures reversed | **Tested** | 0 open of 2 created |

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260907030228 | `expense_view_own_means_own` |
| 20260907030255 | `api_surface_invariant_expense_view_own` |
| 20260907030443 | `attachment_metadata_policy_restored_and_guarded` |

All three verified byte-for-byte by hash against
`supabase_migrations.schema_migrations.statements`.

### Not rerun, and why

**The Android and Windows device acceptance suites — not rerun.** No controller, widget or
screen changed. The four acceptance call sites that used the old reporting API were
migrated and compile, and each asserts a figure only after `syncAndAwaitNumber`, so the
documents they read are canonical. They are **not** claimed as freshly passing; Slice 11
owns device acceptance.

**`phase-a` … `multi-scope-b` — not rerun.** Nothing here touches authority caching,
grants, scope resolution or purge semantics.

### Recorded, and deliberately not changed

**`public.expense_sees_whole_org()` is on the reviewed API surface, granted to
`authenticated`, and called by nothing** — no policy, no view, no function, no client code.
A fifth instance of the family D-068, D-071, D-077, D-103 and D-116 record. Removing it
changes the reviewed surface and it is outside this slice's four approved findings, so it is
reported rather than removed in passing (D-127).

**`reports.view` still has no evaluator**, and D-139's exemption entry stands. That is
Slice 7's, deliberately, and D-163 / D-164 are recorded so it needs no further approval.

---

## Phase 5 Slice 2 — `domain/finance`, the canonical calculation specification: **COMPLETE**

Pure Dart. **No Drift migration, no Supabase migration, no RPC, no pull, no screen** — and
a test asserts the directory imports none of those things. Decisions D-175 and D-176.

The directory `CLAUDE.md` and spec §21.1 have mandated since Phase 0 now exists. It did
not before this slice, which is why the Phase 5 audit listed creating it as Slice 2's
first act.

### What was created

| File | |
|---|---|
| `lib/domain/finance/pnl.dart` | the calculator, the result, the breakdown lines, and the unavailable-vs-zero types |
| `lib/domain/finance/reporting_period.dart` | the five period kinds, normalised to one inclusive `ReportRange` |
| `lib/domain/finance/operating_margin.dart` | the exact ratio, and `MarginNotApplicable` |
| `test/support/pnl_reference.dart` | the independent oracle §6.3 requires — **not shipped** |

### What was reused rather than rebuilt

`Money` (integer paise, D-002), `BusinessDate` (D-019, D-067), **`FinancialYear`** from
`domain/expenses/expense_number.dart`, `TaxTreatment`, and — as the calculator's input —
`RevenueTotals` and `ExpenseTotals`, which are already the primitive summed-paise shapes
both repositories return. No parallel money type, no second FY algorithm, no new
transaction model (D-176).

### The identities, and the control that keeps them honest

```
        Gross Sales      = Σ accepted revenue gross       summed, never Net + GST
        GST              = Σ accepted revenue tax
        Net Sales        = Σ accepted revenue net
        Gross Sales      = GST + Net Sales                exactly, asserted
        Expenses         = Σ accepted expense contributions
        Operating Profit = Net Sales − Expenses           may be negative
```

**Nothing is re-rated, and it cannot be:** the calculator is handed `tax` and is never
handed a rate. Two accepted Restaurant days sum to **750715** paise, where re-applying
5/105 to the aggregate 15765000 would give **750714**. The test asserts the first and
computes the second beside it.

### The worked controls, exact

| | Gross | GST | Net |
|---|---|---|---|
| Restaurant | 10000000 | 476190 | 9523810 |
| Nandbhog | 870000 | 41429 | 828571 |
| **Crystal Canopy Rooftop** | **10870000** | **517619** | **10352381** |
| Room | 5200000 | 247619 | 4952381 |
| Banquet (`none`) | 4034300 | 0 | 4034300 |
| **Hotel Krishna Imperial** | **9234300** | **247619** | **8986681** |
| **Consolidated** | **20104300** | **765238** | **19339062** |

With CCR expenses of 4500000, Operating Profit is **5852381**. Every figure reconciles, and
the independent oracle agrees on all of them.

**Banquet's `none` is carried as a treatment**, never as a configured 0%. The arithmetic
cannot tell them apart and does not need to; the breakdown must, because one is a decision
somebody made about a supply and the other a rate somebody set (D-091, D-122).

### Three things that are not each other

| | |
|---|---|
| **zero** | real trade that netted nothing. `SideAvailable` carrying zeroes; computes normally |
| **negative** | expenses exceeded net sales. Reported as it is, never clamped |
| **unavailable** | nobody knows. A sealed `SideUnavailable` variant, and the report is **refused** (D-163) |

Both sides of `Pnl.compute` are required and non-nullable, and the refusal is an exhaustive
switch over both at once — the compiler, not a reviewer, answers every combination.

### Periods

One inclusive `ReportRange` for all five kinds, so the engines get one boundary contract.
`ReportRange` has no public constructor: a reversed custom range is **rejected**, not
swapped, and the invalid case cannot be built and left unchecked. Same-day is valid.

**Monday to Sunday, on the business date (D-165)** — proven with a real
`BusinessDate.fromInstant` in `Asia/Kolkata`: 19:30 UTC on Sunday 21 June is 01:00 IST on
Monday 22 June, carries a business date of Sunday, and lands in the week that is closing.

**`FinancialYear` reused**, with both boundaries asserted: 31 March 2027 is FY 26-27 and
1 April 2027 is FY 27-28.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,276 tests, all passing** (1,206 + 70) |
| — P&L arithmetic, controls, consolidation, margin, refusals, matrix | **Tested** | 37 |
| — period normalisation, week, month, FY, ranges | **Tested** | 24 |
| — purity, no-`double`, oracle independence | **Tested** | 9 |
| Purity guard **positive control** | **Tested** | a `double` and a `/` added to the margin; the guard turned RED, then restored and **read back** (D-142) |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Working tree | **Tested** | clean |
| Drift migrations added | **None** — local schema stays at v16 |
| Supabase migrations added | **None** — ledger unchanged at 20260907030443 |

### Carried forward, deliberately

**`public.expense_sees_whole_org()`** is on the reviewed API surface, granted to
`authenticated`, and called by nothing. Untouched in Slice 2 — a pure-finance commit is not
where dead-API cleanup belongs — and **carried to Slice 7**, which owns the reporting
capability model and the API-surface audit.

**`reports.view` still has no evaluator** and D-139's exemption entry stands. Slice 7's.

---

## Phase 5 Slice 3 — `LocalReportingEngine`: **COMPLETE**

Canonical local facts → exact SQL aggregates → `Pnl.compute` → `PnlResult`. **No Supabase
migration, no Drift migration, no RPC, no pull, no reporting cache, no screen** — the schema
stays at v16 and the migration ledger is unchanged.

### What was created

| File | |
|---|---|
| `lib/domain/finance/reporting_source.dart` | the port: `ReportingCoverage`, `ReportingScope`, `ReportRequest`, `UnitReportingFacts`, `LocalReportingSource` |
| `lib/data/reporting/local_reporting_engine.dart` | `LocalReportingEngine`, `ReportEnvelope` |
| `lib/data/reporting/drift_reporting_source.dart` | `DriftReportingSource`, `ReportingCoverageOracle`, `NoCanonicalCoverage` |

Added to Slice 2's domain: `ReportRange.wholeMonthKey` and
`PnlRefusal.noPermittedBusinessUnit`.

### The constraint that shaped the slice

**A device holds only what it recorded** (D-173). Rows being present proves nothing about
whether a range is complete, so an engine that reported them as the hotel's June would be
wrong in a way no reader could detect from the figure.

Coverage is therefore a first-class answer carried with the figures, and the production
wiring — `NoCanonicalCoverage` — answers `notDownloaded` for every range, so **the engine
refuses**. That is the honest state until Slice 4, not a placeholder. The first test group
asserts it before any other group assumes otherwise.

Two coverage values, **deliberately not three**: nothing could produce a third today, and a
value no code constructs is the gap D-108 had to reopen.

### Results, through real SQLite

| | Gross | GST | Net | Expenses | Operating Profit |
|---|---|---|---|---|---|
| Crystal Canopy | 10870000 | 517619 | 10352381 | 4500000 | **5852381** |
| Hotel Krishna | 9234300 | 247619 | 8986681 | 3000000 | 5986681 |
| **Consolidated** | **20104300** | **765238** | **19339062** | **7500000** | **11839062** |

`Σ per-unit == consolidated` for every primitive. The independent Slice 2 oracle, folding
the same six rows, agrees on all five figures.

**One-paisa control, through the engine:** two Restaurant days sum to **750715** paise where
re-applying 5/105 to the aggregate would give 750714. The engine never sees a rate.

### Proven

| | |
|---|---|
| complete-zero vs unavailable | a known-complete empty range is a real zero P&L (margin not applicable); an unproven range refuses |
| half-P&L | one property with unproven coverage refuses the whole consolidated report |
| canonical only | pending revenue and pending expenses change nothing; voided rows leave the aggregate and stay in the table; scope-revoked contributes nothing |
| accrual | a June salary paid 5 July stays in June; an accrual recorded 3 July for June reports in June |
| cut-off | a sale whose stored trading day is 30 June reports in June, not July — the engine reads the stored date and recomputes nothing |
| corrections | a revenue business-date correction moves June → July, **exactly once**; an expense accrual correction moves with its contribution |
| scope | CCR-only contains no HKI figure and vice versa; an empty scope is refused, not zeroed |
| range mapping | a month via `pnl_period_key` equals the same days via a date range; the path is a property of the range, not a caller choice |
| periods | single day, Monday–Sunday week, month, financial year, custom, same-day, month-spanning, FY-spanning; a reversed range refuses and carries **no** range |

### The control the schema made impossible, and where the guarantee moved

The behavioural control for *"the engine does not compute `net = gross − tax`"* cannot be
written: the local schema holds a CHECK that a component reconciles, so a deliberately
non-reconciling fixture is refused before any engine sees it. That is the right place for
the guarantee, and it is now asserted rather than assumed. The engine's own freedom from
derived arithmetic is proven by the one-paisa control and by the structural guard.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,318 tests, all passing** (1,276 + 42) |
| — engine, through real SQLite | **Tested** | 34 |
| — structural guard | **Tested** | 6 |
| — the Slice 2 purity guard, over the new port file | **Tested** | 2 |
| Structural guard **positive control** | **Tested** | an added `grossSales.paise - gst.paise` turned it RED; restored and **read back** |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Drift migrations added | **None** — v16 |
| Supabase migrations added | **None** |
| Working tree | **Tested** | clean |

### Performance

Measured on a two-year fixture — 2,920 revenue components, 244 expense contributions:

| Query | Plan | Time |
|---|---|---|
| revenue month (period key) | `SEARCH ix_revenue_entries_day` → `SEARCH ix_revenue_components_entry` | 0.42 ms |
| revenue FY (date range) | the same two indexes | 0.58 ms |
| expense month (period key) | `SCAN expense_period_allocations` → indexed joins | 0.07 ms |
| expense FY (date range) | the same | 0.12 ms |

One aggregate query per side per property, one row back, no N+1, no history in Dart.

**Recorded, not fixed:** `ix_expense_contributions_reporting` leads with `org_id`, which the
local reporting queries never constrain — a device holds one organisation — so it is
unusable on this path and the expense side scans. 0.07 ms over the whole fixture, so no
index is measurably required and the schema stays at v16. Recorded because an index nothing
can use is the same family as a rule nothing evaluates; Slice 8 owns performance hardening.

### Two mechanical defects found in my own work

**Literal backspace bytes inside a regex.** A shell heredoc turned `\b` into control
character 0x08, so the guard's SQL-detection pattern was silently corrupted and could never
match. Caught by reading the file back rather than trusting the write — D-162's rule, and
the second time this session a write mechanism has quietly mangled its own content. Every
Slice 3 file is now scanned for control characters.

**Three fixtures refused by the schema's own CHECK constraints** — a paid expense with no
payment method, a voided document with no actor or reason, and the non-reconciling component
above. All three are the local schema working, and all three were fixed in the fixture
rather than worked around.

### Carried forward, untouched

**`public.expense_sees_whole_org()`** — on the reviewed API surface, called by nothing.
Explicitly carried to **Slice 7**, which owns the reporting capability model and the
API-surface audit. Not touched here: a pure reporting-engine commit is not where dead-API
cleanup belongs (D-127).

**`reports.view`** still has no evaluator and D-139's exemption entry stands. Slice 7's.

---

## Phase 5 Slice 4 — canonical reporting cache and cross-device synchronisation: **COMPLETE**

The gap D-173 recorded is closed. Before this slice **neither** engine had a reporting
pull, so a device could report only what it had itself recorded — and the failure had no
symptom: a manager's second phone, a fresh installation, or a property whose sales somebody
else enters all produce a query that returns rows, sums them exactly, and reports a number
that is not the hotel's.

Decisions D-178 … D-182. `ARCHITECTURE.md` §30. `DATABASE_SCHEMA.md` §13. Local schema
**v17**. No Postgres migration: the projections gained `change_seq` in the approved
`20260907121017`, and nothing else on the server changed.

### What shipped

| | |
|---|---|
| Local schema **v17** | `reporting_revenue_contributions`, `reporting_expense_contributions`, `reporting_coverage_markers` — server-owned, read-only, every key and index leading with `owner_user_id` |
| Transport | `ReportingGateway` over the two contribution projections. No RPC, no new relation, no new grant |
| Engine | `ReportingSync` — document-grain delta, year-bounded replacement, marker written last inside the same transaction |
| Retention | `ReportingRetention` — current + previous FY, plus whatever was fetched on demand |
| Read path | `CachedReportingSource` + `MarkerCoverage`, wired into production and asserted |
| Purge | the reporting cache goes with a revoked property, marker first |

### The three decisions that carry the slice

**The delta asks for changed documents, never for a period (D-178).** A sale corrected from
30 June to 1 July leaves **no June row at all**, so a June-filtered delta returns nothing
for it and the stale June figure sits in the cache for ever — wrong, stable, and reconciling
against itself. The document is therefore the unit of replacement, bounded by the financial
year so a two-year document does not lose one of its years.

**A void is visible only because the projection carries it (D-179).** Both projections carry
`voided_at` rather than filtering it, decided for audit — and that is the only reason a
delta can learn about a void, because a filtered projection would make a voided document
vanish with nothing left to name it. The synchroniser drops voided rows on the way in, so
the cache holds the active effect and no reporting query needs the canonical-only predicate
Slice 1 found applied on one engine and forgotten on the other (D-168).

**The watermark is the lowest scope's, never the highest (D-180).** Taking the highest would
ask for changes since a point a newly granted property never reached, miss every document
below it, and then certify that property complete — a gap that writes its own alibi. The
safety overlap *hides* this until the generations are further apart than the overlap, so the
regression places them 5,000 apart and models RLS so the first sync provably cannot have
cached the second property by accident.

### Verified — host

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 217 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,366 tests, all passing** |
| v17 schema and migration | **Tested** | 10 tests: fresh database, v16→v17 on an accumulated device, v15 through both steps in order, the closed dataset vocabulary, two people holding one contribution independently |
| One writer for the cache | **Tested** | a scan over `lib/` — the rule that makes the canonical predicate unnecessary rather than remembered |
| Synchronisation | **Tested** | 24 tests over a real SQLite database, the real cache and the real synchroniser |
| Revocation of the reporting cache | **Tested** | 3 tests, marker deleted first, a failed refresh purging nothing |
| Production wiring | **Tested** | 5 tests reading what `localReportingSourceProvider` actually returns |
| Composition-root parity (D-134) | **Tested** | the guard **refused the change** until the acceptance harness matched `main()` |

### Positive controls, each seen to fail and each restored and read back (D-142)

| Control | Result |
|---|---|
| Document replacement disabled | **RED** — 4 tests: the correction, the business-date move, the void, the re-apportioned bill |
| The delete not bounded by the financial year | **RED** — the two-year document loses its other year |
| Voided rows stored rather than dropped | **RED** — the void test |
| The watermark takes the highest rather than the lowest | **RED** — the newly granted property |
| `_purgeReportingCache` removed from the purge | **RED** — 2 of the 3 revocation tests |

The fourth needed two attempts. Written first with the generations a hundred apart it
**passed** against the deliberate defect, because the safety overlap covered the gap — the
fifth time this project has had to find a control by expecting red and getting green
(D-071, D-074, D-094, D-139).

### Verified — live, against `krishna-mis-dev`

**13 of 13 passing**, through the real projections, the real gateway, the real cache and
the real synchroniser. Four facts about Postgres that nothing local can establish:

| Case | Result |
|---|---|
| `change_seq` advances on a revenue correction | **PASS** — the property the D-172 corrective added, exercised |
| A void comes back carrying `voided_at` rather than vanishing | **PASS** |
| Cached paise equal the server's own aggregate, both sides, both properties | **PASS** — exact integers, no tolerance |
| Banquet keeps treatment `none` and rate 0, distinct from a configured zero | **PASS** |
| A device that recorded nothing reports the sale another device recorded | **PASS** — D-173, closed |
| A correction reaches the second device and changes the figure exactly once | **PASS** |
| A business-date correction moves the money out of November and into December | **PASS** |
| A void removes the effect on every device, and the row is not stored | **PASS** |
| A shared bill attributed to both properties, then re-apportioned wholly to one | **PASS** — no residue on the other |
| Offline after a successful sync: the P&L is produced with the transport gone | **PASS** — §33 |
| A Crystal Canopy manager caches nothing of Hotel Krishna, **and does cache Crystal Canopy** | **PASS** — the control that separates "scoping works" from "the query is broken" (D-116) |
| An anonymous caller reads no contribution | **PASS** |
| The base tables stay unreadable | **PASS** |

### Fixture state after the run

Reversed through `revenue_void` and `expense_void` with a stated reason naming the run —
never by deleting a row (D-006, D-066).

| | |
|---|---|
| Documents created by this slice | 26 revenue, 6 expense |
| Still open | **0 / 0** |
| Live tax rules | **4** — the verified baseline, untouched |
| Value bands / supply subtypes / premises statuses | **0 / 0 / 0** |
| Closed periods | **0** |
| Open revenue of any kind | **0** |

The sweep runs **before** the fixtures as well as after them, keyed on the marker in the
notes, because a suite that depends on its own teardown having succeeded can pass exactly
once (D-071, D-076). The first run proved it: it failed partway on fixture defects of its
own and left sales open, and the sweep reversed them.

**61 open expenses exist on the project and are not this slice's.** All predate this
session (newest 2026-09-03) and are left untouched.

### Four defects in the live suite itself, all found by running it

None is a product defect; each is an assertion or a call about the wrong thing. It read
`revenue_entries`, which no client role may SELECT — the projection is the only way in
(D-062, D-162). It called `expense_update` and `expense_void` with `p_expense_id` where
both take `p_id`. And it matched `PnlResult` where the outcome is `PnlComputed`.

### Three files moved, because the Slice 3 guard was right (D-182)

The assertion that *no management formula lives in an engine* refused three new files, and
each was fixed by moving the file rather than widening the check — the D-103 anti-pattern.
The cache is a repository and lives with them; the synchroniser is transport and lives with
the sync engine; and *"which financial years does this range touch"* is period math and now
lives in `domain/finance`, where the engine, the coverage oracle and retention read one
answer. A guard written against a property rather than a naming convention found a real
design error while looking for arithmetic.

### Recorded, and deliberately not done here

**Coverage is one value per property**, so a scope missing only its expense side refuses as
`bothSidesUnavailable` rather than naming the absent half. The rule D-163 states is
satisfied — it refuses — and the finer message belongs to **Slice 5**, which owns what a
manager is told.

**`public.expense_sees_whole_org()`** — on the reviewed API surface, called by nothing.
Still carried to **Slice 7**, untouched.

**`reports.view`** still has no evaluator and D-139's exemption entry stands. Slice 7's.

**No device or two-client UI acceptance.** There is no reporting surface yet — Slices 8 and
9 own those — so the cross-device evidence above is two independent local databases
synchronising against the real server through the real production classes, which is the
whole of what exists to exercise. It is reported as that rather than as a device phase.

### Commits

| | |
|---|---|
| `6680bf8` | `app.stamp_change_seq()` and the revenue generation corrective (D-177), approved |
| `69e1936` | the projections carry the document generation, approved |
| `1bd0d16` | local v17 reporting cache, classification and purge |
| `93aeb34` | transport, synchroniser, retention and the production wiring |
| `f20a37f` | live cross-device acceptance |

**Slice 5 is not started**, and is not started automatically.

---

## Phase 5 Slice 5 — the server reporting boundary and D-020 parity: **COMPLETE**

The question the slice existed to answer, and it is now answered against the real backend:

> Given the same authorised scope and the same `ReportRange`, do the offline canonical
> reporting engine and an authoritative server calculation produce **exactly** the same
> management financial result?

Decisions D-183 … D-186. `ARCHITECTURE.md` §31. `DATABASE_SCHEMA.md` §11. Three migrations.
**No P&L screen, no export, no chart, no freshness presentation, no drill-down, no
`reports.view` evaluator** — Slices 6 to 10 own those.

### 1 · The Slice 4 handoff, verified mechanically before anything was built

Ten items, each read from the tree rather than from the closure record:

| | |
|---|---|
| Drift v17 reporting cache | `schemaVersion => 17`, three tables in `reporting_tables.dart` |
| Revenue + expense canonical caches | `reporting_revenue_contributions`, `reporting_expense_contributions` |
| Dataset / FY coverage markers | `reporting_coverage_markers`, keyed `(owner, unit, dataset, year)` |
| Marker-backed production oracle | `MarkerCoverage`, wired through `localReportingSourceProvider` |
| Current + previous FY retention | `ReportingRetention.retainedAt` |
| Reporting synchronisation, both engines | `ReportingSync.synchronise` over both `ReportingDataset` values |
| D-070 purge of the reporting cache | `_purgeReportingCache`, markers deleted first |
| D-074 owner isolation | every primary key and index leads with `owner_user_id` |
| Effective document generation | `change_seq` on both projections (`20260907121017`) |

**No discrepancy.** Nothing was rebuilt and nothing was re-litigated.

### 2 · The coverage collapse, corrected (D-183)

Slice 4 stored markers **per dataset** and then collapsed them into one value per property,
so a scope whose expenses were complete and whose revenue had never arrived refused as
`bothSidesUnavailable` — naming neither half. Slice 4's own test recorded that limitation
and pointed at Slice 5; it now asserts the corrected behaviour instead.

```
        revenue missing, expenses complete   ->  revenueUnavailable
        expenses missing, revenue complete   ->  expensesUnavailable
        both missing                         ->  bothSidesUnavailable
        both complete, no trade              ->  a real ₹0 report
```

`ReportingCoverage` gains `notAuthorised` beside `notDownloaded`, because the remote source
can produce it and *"synchronise this"* and *"ask for a grant"* are different instructions.

**Positive control, seen to fail:** reverting the engine to hand `weakestCoverage` to both
sides turns **5** tests red — the three refusal cases and the two remote-authority ones,
including Data Entry. Restored and read back (D-142).

### 3 · The server primitive contract

```
public.reporting_primitives(p_business_unit_ids uuid[], p_from date, p_to date,
                            p_breakdown boolean default false) returns jsonb
        language sql · stable · SECURITY INVOKER · set search_path = public, pg_temp
```

Per requested property: `revenue_authorised`, `expense_authorised`,
`revenue {gross_minor, tax_minor, net_minor, contributions}`,
`expense {amount_minor, contributions}`, and — when asked — `revenue_by_category` carrying
`tax_treatment`, and `expense_by_hierarchy` carrying department, section and category.

It **derives nothing**: no tax rule, no rate, no business date, no accounting period, no Net
Sales, Operating Profit or margin. Every sum is cast to `bigint`; invariants refuse a body
naming `float`, `real`, `double precision`, a rate, or a date basis other than `pnl_date`.

### 4 · One snapshot, proven rather than asserted

Both sides are read in **one SQL statement**, so under MVCC they come from one snapshot. A
deploy invariant refuses a body with more than one statement or a `plpgsql` rewrite, where
two statements under READ COMMITTED would take two.

The live control drives the interleaving itself — read revenue, void both documents, read
expenses — with **no sleep and no race**, and produces `(R, 0)`: a pair that was never true
of the hotel at any instant. The RPC, asked at any moment, returns one of the three states
that were.

### 5 · Authorization — the half this report first got wrong (D-184, corrected by D-187)

**As first written, this section claimed a complete authorization story and did not have
one.** It said `SECURITY INVOKER` was *"the whole of its safety"*, that the boundary
enforced *"D-164's data half"*, and that the absence of a `reports.view` check *"creates no
exposure"*. The first clause is true about **data access** and was the wrong test to apply:
D-164 is the approved reporting **authorization contract**, it names three capabilities, and
a client-callable P&L endpoint enforcing two of them is under-authorized against it however
little it can expose. The project lead ruled accordingly, and **Slice 5 is closed on the
corrective below rather than on the first report.**

Proven red first, with a capability-based fixture and never a role name: a principal holding
`revenue.view` and `expense.view.all` for Crystal Canopy and **no** `reports.view` received
**₹2,28,086.02** of that property's cost base over 63 contributions. No existing development
identity could have shown it — every holder of the two data capabilities also holds
`reports.view` — so the fixture was built, used, removed and the removal read back.

The boundary now enforces D-164 in full, and the same probe returns
`revenue: null, expense: null`. What is still true, and was worth keeping, is the
`SECURITY INVOKER` property: it grants **no new data access**, and two invariants assert
`prosecdef = false`. See *Phase 5 Slice 5 corrective* at the end of this file.

### 6 · `RemoteReportingEngine`, and local/remote independence

One port, two adapters, one orchestration (D-185). The remote engine **writes nothing** — no
cache, no marker, no local row — and a guard forbids the words that would let it; a remote
read that synchronised on the way past would make the two sources agree because one had just
overwritten the other. The local engine holds no reference to the remote one and answers
with the transport removed.

### 7 · D-020 parity — the results

**Host: 22 tests.** One fixture set feeds both the cache and the server model, and the two
reports are compared to the paisa: per-unit, consolidated, every period shape, categories,
hierarchy, zero range, authority mapping, retry, offline, and the permitted asymmetry.

**Live against `krishna-mis-dev`: 24 tests, all passing.** Context A records; context B has
no copy of any of it, synchronises the reporting cache, and is asked the same question as
the server.

| | |
|---|---|
| Four verified categories, cross-device | **PASS** — CCR 10870000 / 517619 / 10352381, HKI 9234300 / 247619 / 8986681 |
| Categories independent, `none` distinguishable | **PASS** — four lines, Banquet `none` at ₹0 tax |
| Expense hierarchy at its grain | **PASS** |
| Amount correction | **PASS** |
| Business date June → July, both months | **PASS** — source keeps no row, target holds one |
| Expense accounting-period correction | **PASS** |
| Void, both engines to zero, nothing destroyed | **PASS** |
| Shared expense CCR + HKI + consolidated, then re-apportioned | **PASS** — no residue |
| Closed period readable; reopened correction moves both | **PASS** |
| Zero range | **PASS** — a real ₹0, coverage complete |
| notDownloaded vs remote answering, then agreeing | **PASS** |
| Retry × 3 | **PASS** |
| Remote fills no cache, moves no marker | **PASS** |
| Local answers with no network | **PASS** |
| One snapshot | **PASS** — the two-call control reproduces the impossible pair |
| Every period shape, cross-device | **PASS** |

**Two controls give the comparison teeth**, both seen to fail: a zero-valued ghost row fails
on the **count** alone, and a re-rated aggregate returning `750714` where the truth is
`750715` fails on **one paisa**.

### 8 · Security matrix (§34), live

| Identity | Result |
|---|---|
| Owner (unscoped) | both properties |
| CCR manager | HKI refused, both sides `notAuthorised`; **own property answers** (the D-116 control) |
| HKI manager | the converse |
| **Data Entry** (`expense.view.own`, no `revenue.view`) | **refused** — and the raw payload carries `revenue: null`, `expense: null`, so there was never a figure to render |
| Anonymous | RPC refused, projections refused |
| Null unit set | `units: []` — no branch widens to the organisation |
| `expenses`, `revenue_entries`, `revenue_components` | still unreadable by any client |

### 9 · Performance (§33), measured

| | |
|---|---|
| revenue FY aggregate | **0.3 ms**, `Index Scan using revenue_entries_reporting_idx` |
| expense FY aggregate | **368.7 ms**, dominated by `Filter: may_read_expense(expense_id)` over 1,094 rows |
| FY consolidated + breakdown | **774 ms → 398.6 ms** after D-186 |
| FY consolidated, no breakdown | **368.7 ms** |
| one month, one property | **39 ms** server-side; 98–185 ms end to end to Mumbai |

The first version scanned the expense projection **twice** when a breakdown was asked for.
Each side is now grouped once and the headline rolls up from those subtotals — the same
integer, since integer addition is associative. **No materialised view, no aggregate table.**

**Recorded, not fixed:** `may_read_expense` evaluated once per candidate row is the whole
remaining cost. It is a reviewed authority predicate; making it cheaper belongs to Slice 7
or Slice 8, not to a parity slice (D-127).

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,397 tests, all passing** |
| Host parity + remote engine | **Tested** | 22 tests, incl. two controls seen to fail |
| Side-specific coverage | **Tested** | 5 tests + a control that turns 5 red |
| Structural guard over `lib/data/reporting` | **Tested** | 11 tests, incl. "the remote engine cannot write" |
| Live D-020 parity against `krishna-mis-dev` | **Tested** | **24 tests, all passing** |
| Live revenue boundary suite | **Tested** | **81 tests**, 1 deliberately skipped |
| Live expense suite | **Tested** | **56 tests** |
| Live two-client acceptance | **Tested** | **10 tests** |
| Live `drift` migration provenance | **Tested** | every applied version has a committed file |
| Migration audit + backend schema parity | **Tested** | 38 host tests |
| Migration ledger parity (A0 / D-056) | **Tested** | all three verified **byte-for-byte by hash** |
| API-surface and PUBLIC-execute invariants | **Tested** | restated in full; `reporting_primitives` named |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Working tree | **Tested** | clean |

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260907201332 | `reporting_primitives_boundary` |
| 20260907201539 | `api_surface_invariant_reporting_primitives` |
| 20260907204444 | `reporting_primitives_reads_each_side_once` |

All three verified byte-for-byte by SHA-256 against
`supabase_migrations.schema_migrations.statements`.

### Live fixture state after the run

Every document created by the parity suite was reversed through `revenue_void` /
`expense_void` with a stated reason naming the run (D-066, D-071) — never by deleting a row.

| | |
|---|---|
| Open documents created by this slice | **0** |
| Closed periods | **0** — the fixture period was reopened |
| Live tax rules | **4**, the verified baseline, untouched |
| Value bands / supply subtypes / premises statuses | **0 / 0 / 0** |
| Storage reconciliation | exact — 188 revenue objects ↔ 188 rows, 46 expense ↔ 46, **0 stranded** |

### One suite finding, recorded rather than fixed

**The Slice 11 bucket-reconciliation assertion now exceeds the default per-test timeout.**
`the bucket holds no object that nothing names` sweeps the whole bucket over HTTP and takes
**about four minutes** against 234 objects, so `flutter test` kills it at 30 seconds and
reports two failures that are not defects. With `--timeout=10x` the suite is **81 passing,
1 skipped**, and the bucket reconciles exactly.

It is the D-076 family — an assertion whose cost grows with a fixture that never shrinks,
because financial evidence is kept rather than deleted (D-006). It is a characteristic of a
reviewed Slice 11 acceptance suite and is **not changed inside a parity slice** (D-127);
the live revenue suite needs `--timeout=10x` until it is.

### Not rerun, and why

**`phase-a` … `multi-scope-b` — not rerun.** Nothing here touches authority caching, grants,
scope resolution or purge semantics. They are **not** claimed as freshly passing.

**The Android and Windows device acceptance suites — not rerun.** Slice 5 adds no
controller, widget or screen, and a guard asserts the reporting layer still names no P&L
surface. Device acceptance is Slice 11's.

### What Slice 5 deliberately did not build

No P&L page on either platform, no report filters, no freshness banner, no dashboard card,
no chart, no export, no transaction drill-down, no production release infrastructure. No
`reports.view` evaluator, and no change to `public.expense_sees_whole_org()` — both still
carried to **Slice 7**.

*(The `reports.view` half of that sentence is superseded by the corrective below: the
evaluator shipped. `expense_sees_whole_org()` is untouched and still Slice 7's.)*

---

## Phase 5 Slice 5 corrective — the reporting boundary enforces `reports.view`: **DONE**

One mandatory security gate, ruled by the project lead after the Slice 5 report was
substantively approved. Recorded as **D-187**, which corrects D-184. **Slice 5 is formally
closed on this corrective, not on the first report.**

### The gate, in one sentence

`public.reporting_primitives` is an ordinary authenticated client-callable P&L RPC.
`SECURITY INVOKER` correctly prevents it returning any financial row the caller could not
already select — and that is a statement about **data access**, not about the approved
reporting **authorization contract**. D-164 names three capabilities per business unit.
The boundary enforced two.

### Proven RED first, by capability and never by role name

No existing development identity could prove the gap: every principal holding
`revenue.view` and `expense.view.all` also holds `reports.view`. A controlled authority
fixture was therefore built — a role carrying exactly the two data capabilities, granted
scoped to Crystal Canopy — so the proof does not depend on today's role templates and would
still be the proof if they changed.

```
        reports.view      false
        revenue.view      true
        expense.view.all  true

        reporting_primitives(CCR, FY 2026-27)
          expense.amount_minor  22808602        <- Rs 2,28,086.02
          contributions         63
          revenue_authorised    true
          expense_authorised    true
```

A property's cost base, returned to a principal the approved contract does not permit to
read a report at all.

### The corrected contract, and the same probe GREEN

```
        reporting_ok(unit) = has_capability('reports.view', unit)
                             AND (one property requested OR unscoped reporting authority)

        revenue_authorised = reporting_ok AND has_capability('revenue.view', unit)
        expense_authorised = reporting_ok AND has_capability('expense.view.all', unit)

        the same probe  ->  revenue: null, expense: null,
                            reports_authorised: false
```

**Missing authority is never zero**, and a missing `reports.view` removes **both** sides
together — so no combination of absent capabilities can produce half a P&L (D-163). The
payload gained `reports_authorised` for diagnostic honesty. `expense.view.own` is named
nowhere and cannot qualify; nothing branches on a role code, and a deploy invariant refuses
a body that names one.

### The client needed no change, which is the design working

`RemoteReportingSource` already maps a null side to `ReportingCoverage.notAuthorised`, and
`ReportingEngine` already maps that to a refusal. **No authorization logic was added to
`Pnl.compute`**, which stays a pure calculator that is handed two sides and never asks who
is looking. Authorization belongs outside the finance domain and stayed outside it.

### Consolidated authority (D-164), proven in both directions

A request naming more than one property is the **organisation** report and needs the
**unscoped** form of all three capabilities. Two scoped grants do not add up to it.

| Principal | CCR alone | HKI alone | Both together |
|---|---|---|---|
| scoped to CCR **and** HKI | authorised | authorised | **refused**, both sides null |
| unscoped Owner | authorised | authorised | **authorised** |

The second row is the control that separates *"the unscoped rule binds"* from
*"consolidated never works"*. The scoped fixture is made and withdrawn through the real
administrative RPCs inside the live suite, and the withdrawal is **read back** (D-142).

**Positive control, seen to fail:** with the consolidated condition removed from the shipped
body, the live regression turns **RED** on exactly that assertion. Restored, and the restore
read back before anything else was claimed.

### The live security matrix, under the corrected rule

| Identity | CCR | HKI | Consolidated | Payload for a refused unit |
|---|---|---|---|---|
| Owner, unscoped | authorised | authorised | **authorised** | — |
| Crystal Canopy manager | authorised | refused | refused | `revenue: null, expense: null` |
| Hotel Krishna manager | refused | authorised | refused | `revenue: null, expense: null` |
| Accountant, CCR | authorised | refused | refused | `revenue: null, expense: null` |
| Data Entry (`expense.view.own`) | refused | refused | refused | `revenue: null, expense: null` |
| **probe: no `reports.view`** | **refused** | refused | refused | `revenue: null, expense: null` |
| Anonymous | RPC refused | — | — | — |
| null unit set | `units: []` — no branch widens to the organisation | | | |
| `expenses`, `revenue_entries`, `revenue_components` | unreadable by any client role | | | |

### D-139's exemption machinery, updated in the same corrective

`reports.view` was exempt because *"the surface it governs does not exist yet"*. Slice 5
granted a client-callable P&L endpoint to `authenticated`, so that sentence stopped being
true. Its line is gone; `reports.export`, `reports.print` and `settings.manage` stay,
because those surfaces are Phase 7 and genuinely do not exist.

A third assertion states the requirement **positively** — `reports.view` must be granted to
some role *and* named by the boundary — because the two existing assertions would both pass
if it were simply granted to nobody, which is the D-139 defect in reverse.

**Two host guards had to be corrected before they could see any of it**, and both are the
family this file keeps recording:

* the exemption list was read with `firstMatch` over every migration, so a later
  restatement was invisible; it reads the **last** declaration now;
* the evaluator extraction matched only a bare `$$` function body, and
  `reporting_primitives` — the evaluator the list now depends on — is quoted `$fn$`, so with
  the exemption removed the test would have reported `reports.view` as dead. The body tag is
  captured now. D-155's finding in a new file, and the third instance of D-103.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,397 tests, all passing** |
| Migration audit, incl. the corrected D-139 machinery | **Tested** | 21 tests; the two guards proven to read the right thing |
| Live D-020 parity against `krishna-mis-dev` | **Tested** | **25 tests** (24 + the consolidated-authority regression) |
| Consolidated-rule **positive control** | **Tested** | condition removed → **RED**; restored and read back |
| RED → GREEN probe on the shipped boundary | **Tested** | ₹2,28,086.02 → `revenue: null, expense: null` |
| Live revenue boundary suite | **Tested** | **81 tests**, 1 deliberately skipped (`--timeout=10x`) |
| Live expense suite | **Tested** | **56 tests** |
| Migration ledger parity (A0 / D-056) | **Tested** | verified **byte-for-byte by SHA-256** |
| API-surface and PUBLIC-execute invariants | **Tested** | restated over the replacement; `anon` executes nothing |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Working tree | **Tested** | clean |

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260908050614 | `reporting_primitives_requires_reports_view` |

Verified byte-for-byte by SHA-256 against
`supabase_migrations.schema_migrations.statements`.

### Fixtures removed, and the removal read back

| | |
|---|---|
| `reporting_gap_probe` role | **removed** |
| its `role_capabilities` rows | **removed** |
| its scoped CCR grant | **removed** |
| the `profiles` row created for it | **removed** |
| Active authority grants | **5** — the development baseline |
| Roles | **4** — owner, manager, accountant, data_entry |
| The consolidated-authority second grant | made and withdrawn inside the live test, withdrawal asserted |
| Live tax rules / bands / subtypes / statuses | **4 / 0 / 0 / 0** |
| Closed periods | **0** |

### Slice 7 is still Slice 7

The capability boundary moved forward by exactly one evaluator at exactly one boundary.
**Not done here, and still Slice 7's:**

* the comprehensive reporting capability audit and the reporting-role template review;
* the accumulated-state and security acceptance for reporting;
* `public.expense_sees_whole_org()` — on the reviewed API surface, called by nothing,
  **untouched** (D-127);
* `reports.export` and `reports.print` evaluators — Phase 7, and still exempt;
* all reporting-security UI and provider work;
* making `may_read_expense` cheaper (D-186), which is Slice 7's or Slice 8's.

### Not rerun, and why

**`phase-a` … `multi-scope-b` — not rerun.** Nothing here touches authority caching, grants,
scope resolution or purge semantics. They are **not** claimed as freshly passing.

**The Android and Windows device acceptance suites — not rerun.** No controller, widget or
screen changed; the only client-visible consequence is a refusal the engine already knew how
to produce. Device acceptance is Slice 11's.

**PHASE 5 SLICE 5 — COMPLETE.** Slice 6 follows, and its record is below.

---

## Phase 5 Slice 6 — freshness, as-of semantics and closed periods: **COMPLETE**

Slice 6 was told to prove local as-of coherence **before** implementing any freshness. The
audit found it could not be proved, so the slice opens with a corrective and the general
work is built on top of it. Decisions **D-188**; `ARCHITECTURE.md` §32 and the §6.4
amendment; spec §21.4 amended; local schema **v18**; three migrations.

**No P&L surface, no chart, no export, no printing, no drill-down and no Slice 7 work.**

### 1 · The corrective — one report is one snapshot (D-188)

Proven against the tree and against `krishna-mis-dev` before anything was changed:

| | |
|---|---|
| `generation` | `max(change_seq)` **over the rows the delta happened to return** — data-derived, not a boundary. Measured live: revenue max 19981, expense max 19658, head 19981, from one run, with nothing wrong |
| the two datasets | **two HTTP calls**, therefore two MVCC snapshots under READ COMMITTED |
| `server_confirmed_at` | on the marker since Slice 4, and **written by no reporting call site** |

```
        t0  revenue certified to 19981
        t1  a sale accepted         19990
        t2  an expense accepted     19991
        t3  expense certified to 19991

        there is NO generation G at which this cache equals the server's state
```

Both halves canonical; the pair a P&L of a moment that never existed. Under D-163 the two
sides are subtracted from one another, so the error lands in Operating Profit — and every
figure still reconciles, which is why nothing would have raised.

**The corrective, in the shape the project lead ruled:**

* `public.reporting_snapshot` returns both datasets, `pg_current_snapshot()` as an opaque
  identity and `now()` as the server's own time **in one SQL statement**, so they are one
  MVCC snapshot by construction. A deploy invariant refuses a body of more than one
  statement or a `plpgsql` rewrite. Never a second `select now()`, never `DateTime.now()`.
* Authority is the Slice 5 boundary **unchanged** — `reports.view` ∩ `revenue.view` ∩
  `expense.view.all` per unit, `security invoker`, no base table, no role name — and
  `reports.export` / `reports.print` are deliberately **not** required.
* **Snapshot identity and the delta cursor stay separate.** A `change_seq` is allocated at
  write and visible at commit, so it orders work and dates nothing; the safety overlap
  (D-180) remains required exactly as it was.
* Local **v18**: `reporting_coverage_markers.snapshot_id`, nullable, because a marker
  written before the corrective cannot prove membership of anything.
* One local transaction, in the mandated order, **snapshot evidence written last** — so a
  failed run leaves no evidence and no half-certified side.

### 2 · What a report may claim

Every required segment — every property, **both** datasets, every financial year the range
touches — must carry the **same** evidence. Otherwise the report is produced with **no**
freshness claim: figures canonical, availability unchanged, not a paisa moved. Null is not
a third state.

| | |
|---|---|
| `Synchronized as of T` | the cache represents the complete authoritative snapshot successfully synchronized at server-confirmed T. It does **not** claim nothing changed since, so an offline device stays here truthfully |
| `Server has newer canonical changes` | only from an authoritative answer about **reporting** data |
| ~~`Local — current, includes N unsynced`~~ | **superseded for P&L** by D-167 and not preserved as an arm no valid report can construct |

Availability (`complete` / `notDownloaded` / `notAuthorised`) answers a different question
and is never a monetary zero. **There is no reporting TTL**, and D-112 is not reused.

### 3 · `min(generation)` is prohibited, and the prohibition is installed

Not written down — **installed**, two ways, both seen to fail:

* a behavioural regression certifies two properties to the **identical** generation from
  two runs and requires the freshness claim to be withheld;
* a structural guard fails if any file in `lib/data/reporting` so much as names a
  generation, paired with a positive assertion that the coherence comparison still exists —
  because the guard alone would pass if coherence were deleted (D-139 in reverse).

### 4 · Closed periods

Reporting is a **reader**. A closed month reports exactly what it reported the day before
it closed; there is no frozen copy and no hidden month. A guard asserts the reporting layer
names no period lock, close or reopen, and the reporting cache carries no period state to
be wrong about.

Proven live, in sequence: create → sync → close → figures unchanged on both engines →
**the close does not mark the report newer** (it is not reporting data) → a correction into
the closed period **refused** → Owner reopen **with a stated reason** → correction accepted
→ head check now true → sync → local == remote → the figure moved **once**, by exactly what
changed → `period_lock_events` holds the close and the reopen, and the reopen carries its
reason.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 227 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,415 tests, all passing** (1,397 + 18) |
| Coherence regressions | **Tested** | 5 tests: one run one snapshot · two runs cannot be one · an identical cursor is not evidence · a range crossing 1 April · a marker from before the corrective |
| Freshness | **Tested** | 7 tests: offline readable · no elapsed time makes it stale · server-newer moves no figure · an unrelated change marks nothing · a transport failure destroys nothing · losing authority is not staleness · another person's freshness is not this reader's |
| Closed periods | **Tested** | 3 tests, incl. the structural reader guard |
| Structural guards | **Tested** | no generation in the reporting layer · no report expires · the coherence rule exists |
| **Six positive controls** | **Tested** | **all six RED**, each restored and read back |
| Live reporting parity + Slice 6, `krishna-mis-dev` | **Tested** | **29 tests** (25 + 4) |
| Live Slice 4 reporting suite | **Tested** | **13 tests**, re-run after the corrective |
| Migration ledger parity (A0 / D-056) | **Tested** | all three verified **byte-for-byte by SHA-256** |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Working tree | **Tested** | clean |

### The six positive controls, each seen to fail

| Control | Result |
|---|---|
| Two independent snapshots accepted as coherent | **RED** — 3 coherence tests |
| `min(generation)` used as coherence | **RED** — the structural guard |
| The device clock used as server evidence | **RED** — the no-TTL test |
| An unrelated change marking a report newer | **RED** — the scope-relevance test |
| A network failure invalidating a valid report | **RED** — the transport-failure test |
| A closed period disappearing from a report | **RED** — the closed-period test |

**The sixth was written first as a comparison of a report with itself and stayed green**
against its own sabotage, because a month that vanished on both sides satisfies an equality
assertion perfectly. It now names the figures. That is the sixth time this project has had
to find a control by expecting red and getting green (D-071, D-074, D-094, D-139, D-180),
and it is recorded rather than quietly corrected.

### One finding about the evidence itself, recorded because it changed a test

`pg_current_snapshot()` is `xmin:xmax:xip_list`, so **two reads of a database on which
nothing has committed carry the same identity** — the first live assertion expected them to
differ and was wrong to. That is correct behaviour and is the useful half: the identity is
meaningful under **equality**, not uniqueness, and two runs that saw the same MVCC view
really do describe one moment. The live test now asserts what the mechanism promises — the
identity moves once a transaction has committed — rather than a coincidence.

### Migration ledger

| Ledger version | Name |
|---|---|
| 20260908122910 | `reporting_snapshot_transport` |
| 20260908123059 | `api_surface_invariant_reporting_snapshot` |
| 20260908124127 | `reporting_primitives_states_server_time` |

All three verified byte-for-byte by SHA-256 against
`supabase_migrations.schema_migrations.statements`.

### Live fixture state after the run

Every document created by the run was reversed through `revenue_void` / `expense_void` with
a stated reason naming it (D-066, D-071); the teardown asserts **0 stranded documents** and
**0 closed periods**, and it sweeps before the fixtures as well as after them, because a
suite that depends on its own teardown having succeeded can pass exactly once (D-076).

### Not rerun, and why

**The Android and Windows device acceptance suites — not rerun.** Slice 6 adds no
controller, no widget and no screen; the P&L surfaces are Slices 8 and 9 and do not exist.
They are **not** claimed as freshly passing; device acceptance is Slice 11's.

**`phase-a` … `multi-scope-b` — not rerun.** Nothing here touches authority caching,
grants, scope resolution or purge semantics.

### Carried to Slice 7, unchanged

* the comprehensive reporting capability audit and the reporting-role template review;
* the **local** consolidated-unscoped reporting rule, which is still unenforced on the
  device — the server enforces it (D-187) and the local engine does not;
* `public.expense_sees_whole_org()` — on the reviewed API surface, called by nothing,
  **untouched** (D-127);
* `reports.export` and `reports.print` evaluators — Phase 7, still exempt;
* making `may_read_expense` cheaper (D-186);
* accumulated-state and security acceptance for reporting.

**PHASE 5 SLICE 6 — COMPLETE.** **Slice 7 is not started**, and is not started
automatically.


---

# PHASE 5 OA-1 — OWNER ACCOUNTS FOUNDATION: **COMPLETE**

A newly discovered real business requirement, audited before it was built and approved with
eleven binding decisions — **OA-D1 … OA-D11**, recorded as **D-189 … D-199**. OA-1 is the
foundation: owners, ownership shares, family members, the owner ledger and its movements,
the capability namespace, the server boundary and the local schema.

**It builds no settlement calculation, no statement, no owner reporting surface and no
client screen.** Those are OA-2 and OA-3, and a structural guard asserts the owner layer
computes no balance and no entitlement, because a slice boundary nothing evaluates is a
comment.

**And it corrects nothing that was accepted.** `Pnl.compute` is not edited, no contribution
projection changes, and the accepted P&L, Revenue, Expense and reporting semantics of
Phases 3 to 5 are untouched — proven behaviourally rather than argued (§40, §41 below).

## 1 · What shipped

| | |
|---|---|
| Local schema | **Drift v19** — `owners`, `ownership_shares`, `owner_family_members`, `owner_ledger_entries`, plus four indexes |
| Server schema | five tables, all RLS-enabled and **default deny**; exclusion constraints on share and family-link ranges; the `KI-OWN` sequence |
| Boundary | nine reviewed `SECURITY DEFINER` RPCs — `owner_create`, `owner_share_set`, `owner_family_member_create`, `owner_family_member_end`, `owner_movement_create`, `owner_movement_update`, `owner_movement_void`, and the two read helpers |
| Capabilities | eight, under `owner_masters.*` and `owner_ledger.*` (OA-D11 / D-199) |
| Domain | `Owner`, `OwnershipShareSet`, `FamilyOwnerMapping`, `OwnerLedgerEntry`, `OwnerLedgerTotals` — pure Dart, integer paise, basis points |
| Data layer | `OwnerLedgerRepository`, `OwnerLedgerGateway`, `OwnerLedgerMutationEndpoint`, wired into the existing outbox as a fourth routing arm |
| Expense guard | a trigger refusing an expense category named for an owner movement, `KM032`, proven at deploy time against real rows with a positive control beside it |

**Nothing is seeded.** No owner, no ownership share, no opening balance and no family
member exists in production data, and the live suite asserts that no ownership share exists
for any owner outside its own two synthetic fixtures. The 50:50 ratio is a business fact;
the real identities and the inception date are bootstrap data nobody has supplied (D-189).

## 2 · The five movement types, and what each one is

| Type | Direction | |
|---|---|---|
| `opening_balance` | **stated** | the one type that may be either, because an owner's opening position can be (D-191) |
| `withdrawal` | debit | money an owner took; a family member may be recorded as who collected it, and the debit stays with the owner |
| `nc_consumption` | debit | non-chargeable consumption at the **full printed bill value** (D-194); never revenue, and it cannot become revenue |
| `settlement_paid` | debit | discharge of a computed entitlement, kept distinct from a withdrawal (D-192) |
| `manual_adjustment` | **stated** | requires a non-whitespace reason, and is the one type the Accountant bundle does **not** hold |

Amounts are positive integers and **the type decides the sign** — a negative amount is
refused rather than reinterpreted. `KI-OWN` numbers are server-issued on acceptance; a
replayed `mutation_id` returns the same number rather than a second movement.

## 3 · Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 239 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,530 tests, all passing** (1,415 + 115 for the addendum) |
| Owner-accounts domain | **Tested** | 43 host tests |
| Local schema v19, constraints, v18 → v19 upgrade, cache classification | **Tested** | 22 host tests |
| `OwnerLedgerRepository` — evaluate, create, correct, void, coalescing, D-130 base version | **Tested** | 32 host tests |
| Structural guards — capability namespace, purity, slice boundary, non-interference, the Expense guard, the forward-only timeline | **Tested** | 18 host tests, with a positive control seen to fail |
| Live owner-accounts suite against `krishna-mis-dev` | **Tested** | **27 tests**, run **three times in succession, green each time** |
| Migration audit and backend schema parity | **Tested** | 38 host tests |
| Migration ledger parity (A0 / D-056) | **Tested** | every applied version has a committed file; executable-SQL identity checked mechanically (D-203) |
| Secret scan — tree and git history | **Tested** | clean, controls passing |

## 4 · The live matrix, against `krishna-mis-dev`

| Case | Result |
|---|---|
| Both synthetic owners created through the real RPC | **PASS** |
| No ownership share exists for any real owner | **PASS** |
| A mid-month ownership date is refused with a sentence | **PASS** — `KM031` |
| 5000 + 5000 configures and totals exactly 10000 | **PASS** |
| Re-setting a share closes the open one — no gap, no overlap, history not restated | **PASS** |
| A backdated share is refused with a sentence, not a constraint name | **PASS** — the defect the second run found (D-201) |
| A withdrawal is numbered on its own `KI-OWN` sequence | **PASS** |
| A replayed mutation id returns the same number, not a second movement | **PASS** |
| An NC bill derives its owner from the family link | **PASS** |
| A declared owner that disagrees is refused, never re-attributed | **PASS** |
| An agreeing declared owner is accepted | **PASS** — the control that separates "the comparison binds" from "declaration never works" |
| An opening balance and an adjustment must state a direction | **PASS** |
| An adjustment with a whitespace-only reason is refused | **PASS** |
| A negative amount is refused; the type decides the sign | **PASS** |
| An unknown movement type is refused rather than defaulted | **PASS** |
| A stale `base_row_version` is a conflict, and nothing is applied | **PASS** |
| A correction moves the amount by exactly the difference | **PASS** |
| A void with a whitespace-only reason is refused, in every shape | **PASS** |
| A voided movement accepts no correction | **PASS** |
| `change_seq` advances on every mutation | **PASS** — D-177's invariant, exercised |
| Anonymous reads nothing and calls nothing | **PASS** |
| Data Entry sees no owner ledger and cannot record one | **PASS** |
| A unit-scoped Manager holds nothing in this domain in V1 | **PASS** |
| The Accountant records and reads, and cannot adjust | **PASS** — and this is what found D-200 |
| The base tables are never writable by any client role | **PASS** |
| An expense category named for an owner movement is refused, with `KM032` | **PASS** |
| Recording owner movements moves **no** expense or revenue contribution | **PASS** |

## 5 · Non-interference, proven twice (§40, §41)

**Behaviourally**, on the real server: the expense and revenue contribution totals are read
before and after a run that records ten owner movements, and compared exactly. **No paisa
moves.**

**Structurally**, over the tree: the finance domain names no owner concept, the reporting
engines are untouched by this slice, the owner write path names no expense or revenue table,
and nothing in the owner layer computes a balance or an entitlement. Each is a scan, so it
holds for files nobody has written yet.

## 6 · Defects found, each recorded

| | |
|---|---|
| **D-200** | `owner_ledger.view` was gated on `has_unscoped_capability`, which D-025 makes satisfiable by the Owner alone — so the Accountant could record, correct and void a movement and read nothing. **The third instance of D-110 / D-116**, found by the live authorization matrix |
| **D-201** | `owner_share_set` left a backdated or duplicate ownership date to the exclusion constraint, so a caller met `23P01` and a constraint name. **Found by the suite's second run**, which is the only run that could have found it (D-076) |
| **D-202** | the local manual-adjustment reason CHECK used one-argument `trim()`, which strips spaces only, so a tab satisfied it — **D-138 and D-142's defect in SQLite** |
| D-044 / D-101, third instance | two new trigger functions were left `PUBLIC EXECUTE`; the API-surface invariant refused the migration |
| **D-203** | the ledger's "verified byte-for-byte" wording has never been literally true, for any migration; the executable-SQL identity that *is* true is now checked mechanically |

**Recorded and deliberately not fixed:** the shipped local revenue and expense void CHECKs
carry D-202's weakness. Outside OA-1's reviewed scope (D-127), and the server refuses a
whitespace reason before either constraint is reached.

## 7 · Migration ledger

| Ledger version | Name |
|---|---|
| 20260909105555 | `owner_accounts_capabilities` |
| 20260909110038 | `owner_accounts_schema` |
| 20260909110608 | `owner_ledger_rpcs` |
| 20260909110912 | `expense_categories_refuse_owner_drawings` |
| 20260909111051 | `owner_trigger_functions_revoked` |
| 20260909111136 | `api_surface_invariant_owner_accounts` |
| 20260909112045 | `owner_ledger_view_is_grantable` |
| 20260910161035 | `owner_share_set_refuses_backdating` |

Executable-SQL identity verified against `supabase_migrations.schema_migrations.statements`
for all eight (D-203).

## 8 · What OA-1 deliberately did not build

No settlement calculation and no entitlement. No settlement statement, no Draft/Finalized
state machine, no recalculation. No owner reporting surface, no P&L change, no export, no
chart. **No client screen on either platform** — no Android surface, no Windows surface, no
provider wiring beyond the repository and the sync endpoint. No `owner_settlement.view`
capability, because a capability granted and evaluated by nothing is the family this log
keeps recording (D-197).

**No Petpooja integration, and no claim that automatic POS reconciliation exists.** A guard
asserts the repository still contains no POS integration. Whether a non-chargeable bill can
be distinguished from a paid one in the POS is an operational question, answered today by
the operator workflow and recorded as an open question rather than pretended away with a
rule that cannot see it.

**Statutory GST treatment of a non-chargeable supply is NOT settled by this feature.**

## 9 · Not rerun, and why

**The Android and Windows device acceptance suites — not rerun.** OA-1 adds no controller,
no widget and no screen, and a guard asserts it stays that way. They are **not** claimed as
freshly passing.

**`phase-a` … `multi-scope-b` — not rerun.** Nothing here touches authority caching, grants,
scope resolution or purge semantics.

## 10 · The V1 ownership ruling (D-204), proven 2026-09-10

The project lead ruled after OA-1 closed: **V1 ownership is fixed at 50:50 between exactly
two owners**, and no general variable-ownership settlement logic is designed for V1. The
authoritative vector must resolve to exactly `[5000, 5000]`; 60/40, 70/30, a third owner,
unequal ownership, a partial total and a total above 100% are all refused.

**Proven red first.** The shipped resolver accepted every one of those shapes, and each
totals exactly 10000 — so the total check that existed could never have seen them.

Enforced twice: `resolveV1For` refuses to **infer** a ratio nobody approved, and
`owner_share_set` refuses to **accept** one (`KM033`). A host guard pins the two numbers to
each other. `resolveFor` is untouched, so historical records stay readable, and the
`ownership_shares` CHECK was **not** narrowed — the deploy asserts that, because encoding a
business rule on the column would make an authorised future ratio a migration of history.

| | Property | Result |
|---|---|---|
| 1 | exactly two active shares resolve for a settlement date | **PASS** — domain and live |
| 2 | both equal 5000 bp | **PASS** — domain and live |
| 3 | total equals 10000 bp | **PASS** — domain and live |
| 4 | one missing owner refuses | **PASS** — both arms |
| 5 | any non-5000 share refuses | **PASS** — five splits in the domain, five values live |
| 6 | more than two active shares refuses | **PASS** — including 4000/3000/3000, which totals 10000 |
| 7 | historical records remain readable | **PASS** — a 60/40 period still resolves under the general rule |
| 8 | no P&L / Revenue / Expense semantics change | **PASS** — structural guards and the live contribution comparison |

Migrations `20260910171751 owner_share_set_enforces_the_v1_vector` and
`20260910172611 owner_share_refusal_promises_no_unavailable_act` — the second correcting a
refusal that told an administrator to end an owner's share when **no API can do that**
(D-205). Live owner-accounts suite **31 tests, run three times in succession**.

**Still required before real settlement data is entered: the effective-from date of the
50:50 ownership.** Not guessed.

## 11 · Next

**OA-2 followed** — see *PHASE 5 OA-2 — OWNER SETTLEMENT ENGINE* at the end of this file.
The old Phase 5 Slice 7 is still not started.

---

# PHASE 5 OA-2 — OWNER SETTLEMENT ENGINE: **COMPLETE**

The calculation and reporting architecture for owner settlement. **No settlement screen, no
card, no payout button, no export** — OA-3 owns presentation and its security boundary, and
a guard asserts the feature tree names none of it (§45).

Decisions **D-206 … D-211**.

## 1 · The audit came first, and it found more than expected

§18 required proving what canonical owner data another device can obtain **before** any
settlement arithmetic was written. Run against `krishna-mis-dev` with a fresh device, it
found **two** gaps:

| | |
|---|---|
| **The ledger** | Device A recorded a withdrawal, the server accepted and numbered it. Device B — authorised, online, the same person — saw **nothing** |
| **The masters** | Device B saw **no owners, no ownership shares, no family links**. `ownershipShares()` reads a local table nothing in production writes, so the V1 vector resolves to *no share configured* on every real device. OA-1 did not report this half |

**The gap was entirely client-side.** The same session was handed the movement, and all
three masters, by the server — so the fix is a caller, not a boundary (D-173's finding, in a
second domain). The audit is a permanent test, and a later group in the same file runs the
synchroniser and asks the same questions again.

## 2 · The chosen data source (§19), and why

**Option A — a full canonical Owner Ledger pull.** The ledger is small; a projection or
cache would be a second financial truth (§19, §26) needing its own correction and void
propagation, and a server settlement query would need the capability OA-3 reserves (§44).

A full replace makes a correction arrive corrected, a void arrive carrying `voided_at`, and
a withdrawn movement simply cease to exist — with no watermark, no safety overlap and no
document-grain replacement (D-178, D-180). One `language sql` statement returns movements,
owners and shares together with the server's snapshot identity and transaction time, so
every dataset belongs to one MVCC snapshot (D-188). Local commit order puts the coverage
evidence **last**, inside the transaction.

## 3 · The engine

```
        closing = opening
                + profit entitlement            (signed; a loss reduces it)
                - withdrawals - NC - settlement paid
                + adjustment credits - adjustment debits
```

**Nothing is stored.** No balance column, no settlement table. The opening position is
derived from history before the period (§23), which is why corrections and voids need no
propagation machinery. **Operating Profit is consumed, never recreated** (§33) — a guard
fails the build if the settlement directory names `netSales`, `grossSales` or `Pnl.compute`.

**Entitlement is cumulative** (§8, §38): two months of one paisa allocate both paise, where
the naive monthly floor allocates neither. The remainder belongs to neither owner, resolves
by itself, and is never persisted as a movement.

## 4 · Verified

| Item | Status | Evidence |
|---|---|---|
| Host suite | **Tested** | **1,605 tests, all passing** (1,543 + 62) |
| `dart format --set-exit-if-changed` | **Tested** | clean, 249 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Settlement domain — the brief's reference controls §34…§43 | **Tested** | 33 host tests, incl. a 2,001-value sweep against an independent oracle |
| Settlement structural guards §26, §32, §33, §45 | **Tested** | 13 host tests, with a positive control seen to fail |
| Canonical owner sync and cache §18…§20, §27, §28 | **Tested** | 16 host tests over real SQLite |
| Remote completeness audit **and its closure** | **Tested** | **8 live tests** against `krishna-mis-dev` |
| Local schema v19 → v20 | **Tested** | classification completeness guard green |
| Migration ledger parity (A0 / D-056) | **Tested** | executable-SQL identity verified for both migrations |

## 5 · Schema and migrations

Local **Drift v20**: `canonical_owner_movements`, `canonical_ownership_shares`,
`canonical_owners`, `owner_settlement_coverage` — all owner-keyed, all
`canonicalReportingCache`, all purged on a confirmed revocation with the coverage row
removed first.

| Ledger version | Name |
|---|---|
| 20260910180630 | `owner_ledger_snapshot_transport` |
| 20260910180836 | `api_surface_invariant_owner_snapshot` |

**No `owner_settlement.view` capability was created** — OA-3's boundary, and a deploy
assertion fails if it appears (§44).

## 6 · A latent exposure the audit surfaced (D-208)

OA-1 classified the owner masters `organizationGlobal`, which **survives a user switch**.
That was safe only because nothing wrote them. Filling them would leave the ownership ratio
readable by whoever signs in next on a shared workstation — against OA-1 §31.

So the settlement reads an **owner-keyed** copy instead. The three OA-1 tables stay empty and
stay as they are, so the exposure is latent rather than live; the consequence is that OA-1's
client-side NC pre-check still cannot run on a real device, which is **stated rather than
fixed here** (D-127). OA-3 owns the choice.

## 7 · What OA-2 deliberately did not build

No settlement screen, card, statement, export or payout control. No stored settlement
snapshot. No provisional settlement (§17). No treasury or cash-availability logic (§15). No
automatic trigger for the owner pull — and that is deliberate: `ReferenceSync` runs for every
signed-in person, and certifying *complete canonical owner history* to a principal entitled
to read none of it would be a claim worse than none. The trigger belongs with the surface
that holds the capability, which is OA-3's.

## 8 · Next

**OA-3 is not started, and is not started automatically.**

---

# PHASE 5 OA-3 — OWNER SETTLEMENT UI / SECURITY SURFACE: **COMPLETE**

The Owner Profit & Settlement Statement **preview**, on its own screen on both platforms,
behind a server boundary that decides who may see it. Decisions **D-212 … D-219**;
`ARCHITECTURE.md` §35; `DATABASE_SCHEMA.md` *Phase 5 OA-3*; `RELEASE_CHECKLIST.md` §N.

**It is a preview.** No finalize, reopen, lock, approval or statement versioning exists, by
ruling (Q3). **The Finalized Statement slice and the old Phase 5 Slice 7 are not started**,
and neither starts automatically.

## 1 · What the project lead decided (D-212)

| | Ruling |
|---|---|
| **Q1** | One date: *"50:50 ownership and owner settlement begin from this date."* No separate inception date, never guessed; set under `owner_masters.manage`, audited. **The production date is still outstanding.** |
| **Q2** | `owner_settlement.view` for the **Owner only**; enforced by capability; no partial settlement for a scoped reader |
| **Q3** | **Preview only** |
| **Q4** | A **separate screen** named "Owner Settlement" on Windows and Android, shown only with `owner_settlement.view`; monthly picker; no charts |

## 2 · What was found and fixed on the way

| | |
|---|---|
| **D-213** | The Accountant — who records owner movements — was handed the whole settlement by the snapshot: **159 movements, 3 owners, 34 shares, 2 family links**. Proven red, closed on the server: now `settlement_authorised: false` with every dataset null, while ledger RLS still serves the Accountant |
| **D-214** | D-070 purged on a lost **property**; the owner cache is not scoped by property, so losing `owner_settlement.view` with both properties kept would have removed nothing. A confirmed capability loss now purges it |
| **D-215** | OA-1's `owner_ledger_entries` was **classified purged and never purged** — a user switch left synced owner movements readable. Fixed, mirroring revenue |
| **D-216** | D-208 resolved by **option B**: the OA-1 master tables stay unwritten, with a permanent no-writer guard. Option A would have required recorders to hold settlement visibility |
| **D-217** | Two live-suite findings: a count compared across two live reads is not idempotence; and the owner live suites share one ledger, so they run with `--concurrency=1` |
| **D-219** | A PowerShell text-cmdlet restore corrupted a UTF-8 source file into mojibake. Repaired and verified; every later control restored by byte copy and `cmp` |

## 3 · Verified

Labels used exactly as defined: **Implemented / Tested / Partially tested / Not tested /
Blocked.**

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 261 files, 0 changed |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **1,692 tests, all passing** (1,605 + 87) |
| Sync contract, schema v21, capability-loss purge | **Tested** | 26 + 3 + 16 host tests |
| Preview service and refresher | **Tested** | 17 + 5 host tests |
| D-208 no-writer guard | **Tested** | 3 host tests, incl. a pattern self-test |
| UI, both shells | **Tested** | 23 widget tests, incl. every state named in the ruling |
| OA-3 boundary guards | **Tested** | 17 host tests: preview only, no arithmetic, no OA-1 master reads |
| Server gate RED → GREEN | **Tested** | Accountant: 159/3/34/2 → `settlement_authorised: false`, nulls |
| Live OA-3 suite against `krishna-mis-dev` | **Tested** | **20 tests**, green in three runs: the first **20/20** with the not-configured case live, the next two **19 + 1 skipped** once the fixture date existed. Two further runs beside the OA-1 suite failed on the shared ledger and are recorded in D-217 |
| Live owner suites together, serially | **Tested** | **58 passed + 1 skipped** — OA-1 31, OA-2 audit 8, OA-3 19 |
| Live reporting suites | **Tested** | **13** + parity **29**, re-run after OA-3 |
| Migration ledger parity (A0 / D-056, D-203) | **Tested** | executable-SQL identity for all four versions |
| API surface | **Tested** | **58** functions, repository list = live catalogue |
| Secret scan — tree, git history, built artefacts | **Tested** | clean, controls passing |
| Clean Windows release bundle | **Tested** | built without acceptance defines; the settlement page, the snapshot call and "Owner Settlement" present in `app.so` |
| Android build | **Not tested** | not built in OA-3 |
| Windows / Android device acceptance of the settlement screen | **Not tested** | no device phase was written or run; the surface is proven by widget tests and the live service suite, not by driving a real client |

### Positive controls, each seen RED and restored byte-identical

| Control | Result |
|---|---|
| Sync `_withdraw` removed | RED |
| Capability-loss purge disabled | **6** RED |
| Restore-authorship predicate removed | **1** RED (the D-074 case) |
| v21 range guard removed | RED — duplicate column |
| An OA-1 master writer planted | RED — the D-216 guard |
| Preview: settlement check, consolidated check, before-period profit | RED each |
| Refresher: not-authorised stop, on-demand years | RED each |
| UI: `.paise` planted, a finalize identifier planted, sidebar gate removed, closing label ignoring the sign | RED each |
| **Live**: the refresher's reporting pull disabled | **4** RED, each `reportingNotDownloaded`, never ₹0 |

## 4 · Commits

| | |
|---|---|
| `6d0c4a6` | the server boundary: capability, start date, snapshot gate, API surface |
| `2982153` | sync contract, local schema v21, capability-loss purge |
| `e4a9d29` | preview service, refresher, production wiring, D-208 guard |
| `571f35c` | the preview on both shells |
| `3322434` | the live security suite against `krishna-mis-dev` |

## 5 · Migration ledger

| Ledger version | Name |
|---|---|
| 20260911130948 | `owner_settlement_view_capability` |
| 20260911131042 | `owner_settlement_start_date` |
| 20260911131130 | `owner_ledger_snapshot_requires_settlement_view` |
| 20260911131228 | `api_surface_invariant_owner_settlement` |

**100** applied versions on `krishna-mis-dev`. Local Drift schema **v21**.

## 6 · The development project after OA-3

| | |
|---|---|
| Open OA-3 fixtures (sales, owner movements) | **0** — voided through the real APIs |
| Open revenue / open owner movements, any | **0 / 0** |
| Live tax rules · bands/subtypes/statuses · closed periods | **4 · 0/0/0 · 0** |
| Role grants · roles | **7 · owner, manager, accountant, data_entry** — unchanged by OA-3 |
| `owner_settlement.view` holders | **owner** only |
| `owner_settlement_settings` | **`2026-05-01` — a DEVELOPMENT FIXTURE, not the production date.** Restoring "not configured" needs an administrative removal, which was not performed in this session (D-217) |

## 7 · Recorded and deliberately not changed (D-218)

The OA-1 owner-ledger outbox transport is **not wired in `bootstrap`** (latent: no surface
creates an owner movement). No administrative screen sets the start date (the reviewed RPC
does). No per-family-member breakdown of non-chargeable consumption.

## 8 · Open for the project lead

1. **The production 50:50 start date.** Nothing real can be settled without it.
2. **Whether to remove the development fixture start date** from `krishna-mis-dev`, so the
   development project shows "Settlement start date not configured" again.

## 9 · Next

**Stop.** OA-3 is complete. The Finalized Statement slice and the old Phase 5 Slice 7 wait
for the project lead.

---

# PHASE 5 SLICE 7 — REPORTING SECURITY / AUTHORIZATION CLOSURE: COMPLETE

Verified 2026-09-12/13. This entry supersedes the earlier "Slice 7 not started" handoff.
Full capability matrix, audit boundaries, RED/GREEN evidence and baseline details:
`SLICE7_SECURITY_AUDIT.md`; architecture §36; decisions D-220…D-222.

## Security corrections

- Canonical local P&L reads now enforce current capabilities and unscoped consolidation.
- Direct owner-settlement repository reads independently refuse missing authority.
- Confirmed reporting-capability loss purges facts and coverage even with units retained.
- Sign-out removes reporting-only cache/evidence even without unit master rows.
- Dead `expense_sees_whole_org()` removed through migration `20260912100000`.

No arithmetic, business facts, role-name authorisation, new schema version, UI, export,
print or finalized-statement behaviour was added. Local schema remains v21.

## Closure evidence

| Gate | Status | Result |
|---|---|---|
| D2 unit and unscoped consolidated authority | Tested | Live independently altered capability fixtures; both unit positives and two-scope consolidated refusal |
| Local half-P&L / direct owner repository | Tested | Production-wiring regressions refuse retained unauthorised cache |
| D-070 / D-074 | Tested | Capability-loss, unavailable-network, pending-work and shared-device tests green; live owner isolation green |
| Host suite | Tested | **1,711 passed** |
| Relevant live suites, serial (`--concurrency=1`) | Tested | **101 passed, zero skipped**: 13 reporting + 29 parity + 31 OA-1 + 8 completeness + 20 OA-3 |
| Format / analyze | Tested | 263 files, 0 changes; no issues |
| Live security catalogue | Tested | 57 reviewed APIs; PUBLIC/anon EXECUTE 0; anon reads 0; client writes 0; all public base tables RLS; no public overloads |
| D-139 guard | Tested | Latest exemption, comments/DO exclusion and named-dollar-tag positive controls; live dead non-exempt grants 0 |
| Migration provenance | Tested | 101 ledger entries match; applied migration SQL equals repository after LF normalisation |
| Credential scan | Tested | Working tree and Git history clean |
| New builds/device acceptance | Not tested | No release/device claim added by this security-only slice |

## Development baseline restored

`owner_settlement_settings`: **0 rows**, "Settlement start date not configured". The
`2026-05-01` disposable fixture was removed administratively before and after acceptance.
Open revenue / owner movements / reporting acceptance expenses: **0 / 0 / 0**.
Role-grant rows remain **7**, of which **5** active; same four bundles. Historical voids,
ownership fixtures and audit records remain. The production start date remains outstanding.

## Next — stop at the boundary

Implementation commits: `460980b4e17d62c0a42a695c34dc1d8ebea127f6` (security and
coupled regression/constructor tests), `989846a60545e5d7568f9835434affef5115e96a`
(API migration and structural guards), `c384af63fce20b9036708e0d1f1cca2892c13939`
(administrative acceptance teardown). The documentation closure is the following commit.

The Slice 7 security gate is closed. **Slice 8 is safe to scope and begin from this
foundation, but has not been started.** It still requires its own binding-document handoff
and acceptance plan. Finalized Owner Statements and Phase 7 exports/printing remain outside
this slice. There is no pending Slice 7 corrective; the production start date is still a
project-lead business decision, not a licence to reuse the dev fixture.

---

# PHASE 5 SLICE 8 — WINDOWS P&L SURFACE: COMPLETE

Verified 2026-09-13 against `krishna-mis-dev` only (`loratzmactetjbqolwri`). Starting HEAD
`a085e48`. Decisions **D-223…D-227**; `ARCHITECTURE.md` §37. No schema change, no migration;
local Drift schema **v21**, ledger **101** versions.

## What shipped

* **Analytics → Profit & Loss** on the desktop router (`ProfitAndLossPage`); Android keeps its
  Reports placeholder (Slice 9).
* Providers: `pnlScopeOptionsProvider`, `pnlSelectionProvider`, `pnlViewProvider`,
  `pnlPresetAvailabilityProvider`, `pnlSyncProvider`, `businessDayRulesProvider`,
  `reportingClockProvider`, `pnlReportingLockProvider`.
* Domain: `PnlAuthority`, `RelativePreset` / `resolvePresetForUnits`, `BusinessDayRule`,
  `PnlResult.breakdownReconciles`, `OperatingMargin.displayTwoDecimals`.
* Headline (Gross Sales, GST, Net Sales, Expenses, Operating Profit/Loss, Operating Margin),
  revenue by category (gross/GST/net) and expense by category, each reconciling exactly.

## Behaviour

| | |
|---|---|
| Authorization | a property only with `reports.view` ∩ `revenue.view` ∩ `expense.view.all`; consolidated only all three unscoped; direct reads refused before any cache read |
| Periods | presets resolved per property; consolidated disables/refuses disagreeing ranges and directs to Custom; unreadable rules refuse; reversed Custom refused |
| Margin | 2 decimals, symmetric half-away-from-zero, N/A at zero Net Sales |
| Older years | Not downloaded → Download required data (on demand, every missing FY) → computed only when all covered; failure stays not downloaded; offline explains a connection is required |
| Freshness | synchronised at server time · server has newer (confirmed head check only) · no freshness evidence; offline complete reports stay readable |
| Coherence | report reads and syncs serialised by one lock (D-227) |

## Verification

| Gate | Status | Evidence |
|---|---|---|
| `dart format` | Tested | lib/test clean; acceptance file formatted |
| `flutter analyze` | Tested | No issues found |
| Host suite | Tested | **1,850 passed** (1,711 + 139) |
| Widget suite | Tested | every required state; three Windows sizes × 8 states without overflow |
| Positive controls | Tested | 8 sabotages all seen RED (lock, authority, presets, GST reconciliation, margin sign, server-has-newer, surface guard, older-year download), restored byte-identical by `cmp` |
| Real `krishna_mis.exe` acceptance | Tested | `windows-pnl` (sale + 2 expenses via RPCs, consolidated and CCR parity to the paisa with `reporting_primitives`, void + resync, offline cached read, older-FY download) and `windows-pnl-scope` (capability-asserted principal: CCR opens; HKI and consolidated refused on device, withheld by server) |
| Windows shell | Tested | `windows_shell_test` 15 passed in the real executable |
| Live suites, `--concurrency=1` | Tested | **101 passed, zero skipped** — reporting 13, parity 29, owner accounts 31, completeness 8, settlement 20 |
| Windows release build | Tested | built with `config/dev.json` only; P&L strings present in `app.so`; 0 identity passwords in release and debug binaries |
| Secret scan | Tested | working tree, Git history and built artefacts clean |
| Android build / device acceptance | Not tested | Slice 9 |

## Defects found and fixed while building

1. An enum value shadowed by a parameter named `today` in `periodFor` — compile error, fixed.
2. Riverpod `CircularDependencyError`: the sync controller invalidated the view that watches it
   — removed; the view re-reads via source invalidation inside the lock.
3. The surface guard missed imports because it blanked strings first — caught by its own
   self-test, fixed.
4. The page declared a `double` constant — caught by the guard, fixed.
5. Design hazard: a sync could land between a report's cache queries (mixed snapshots) —
   prevented by `ReportingCacheLock`, with a regression whose no-op-lock control goes red.

No pre-existing product defect was found; Slice 7 was not reopened.

## Backend baseline after acceptance

Fixtures: 1 sale and 2 expenses created, all voided. Settings rows **0** (the owner suite's
`2026-05-01` fixture removed with `owner_settlement_dev_fixture_cleanup.sql`). Open revenue
**0**, open owner movements **0**, open acceptance expenses **0**, open expenses **61**
(pre-existing), role grants **7** (5 active), roles **4**, closed periods **0**, dead helper
absent, ledger **101**. Process note: one secret-scan `dart run` overlapped the Windows shell
test; both completed normally.

## Carried forward

* Phase 8: `may_read_expense` per-row reporting cost; `org_id`-leading local expense index
  (D-223). Historical "Slice 8 performance hardening" references mean Phase 8.
* The OA-3 settlement refresher does not share the P&L lock (D-227, not demonstrated).
* The production 50:50 start date remains a project-lead decision.

**Slice 9 — Android P&L Surface is safe to scope from this foundation and has not been
started.**

---

# PHASE 5 SLICE 9 — ANDROID P&L SURFACE: COMPLETE

Verified 2026-09-13/14 against `krishna-mis-dev` only (`loratzmactetjbqolwri`). Starting HEAD
`dea929b`. Decisions **D-228…D-232**; `ARCHITECTURE.md` §38; `RELEASE_CHECKLIST.md` §O. No schema
change, no migration; local Drift schema **v21**, ledger **101** versions.

**Acceptance was on the local `Pixel_8` emulator. A physical Android device pass (Galaxy A06 or
another approved target) is still required before Phase 5 closes, and is not claimed (D-230).**

## What shipped

* The Android **Reports** tab opens directly to Profit & Loss (`MobileProfitAndLossPage`), with no
  reports menu (D-228). Owner Settlement stays separate. Windows keeps P&L under Analytics.
* A portrait-first phone layout over the **same** Slice 8 providers, engine, cache, lock,
  synchroniser, coverage and freshness: title and freshness, property in a bottom sheet, preset
  chips in a horizontal strip, Custom through a calendar-only picker (D-229), headline card,
  revenue by category, expense by category, state messages, pull-to-refresh, and clearance for the
  docked [ + ]. It computes no figure and decides no authority.
* `pnl_presentation.dart`: one set of P&L wording, range/instant formatting and category ordering
  shared by both surfaces (D-232). The Windows page was rewired onto it with every Slice 8 key and
  sentence unchanged.
* Session isolation (D-231): views and scope options carry `viewerUserId`; both surfaces show them
  only through `pnlViewShownTo` / `pnlScopeOptionsShownTo`, and a sync started for one person
  cannot write its outcome into the next person's status.

## Defects found and fixed

| | Defect | Found by |
|---|---|---|
| D-231 | After a user switch, **both** P&L surfaces kept showing the previous person's report while a sync held the lock (the Owner's consolidated ₹11,040.00 shown to a Crystal Canopy-only principal) | a session-switch regression, proven RED on the shipped Slice 8 code |
| D-232 | Slice 8's "Android keeps its Reports placeholder" guard sliced one line of the router and **could never fail** | replacing it; the new guard was seen RED |
| D-232 | Acceptance helper scrolled a month grid (`NeverScrollableScrollPhysics`) instead of the picker's month list | first `android-pnl` emulator run; reproduced on host by two new picker tests |
| D-232 | Acceptance helper waited for a refresh control the lazy page had not built | second `android-pnl` emulator run |

None of the four is a financial-calculation defect. Both harness defects were fixed in the harness;
each failed run's fixtures were voided by its own `finally` sweep (0 open of 3, 0 open of 6).

## Verification

| Gate | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | Tested | 281 files, 0 changed |
| `flutter analyze` | Tested | No issues found |
| Host suite | Tested | **1,953 passed** (run 2). Run 1 had **one** failure: `financial_cache_retention_test.dart` "…the revoked share is not left legible in the database file" timed out at 30 s under load and could not delete its temp database (file in use). It passed in 3 isolated reruns and in the full run 2. No Slice 9 code is on its path; recorded as a load-related timeout, not hidden |
| P&L suites together (phone UI, session switch, surface guard, wiring, routing smoke, Windows UI, providers) | Tested | **196 passed** |
| Positive controls | Tested | display rule disabled → session-switch RED on both surfaces; Reports pointed back at a placeholder → routing guard RED; guard self-tests with planted violations; each restored byte-identical |
| Emulator acceptance, `sdk gphone16k x86_64`, `emulator-5554`, Android 17 / API 37 | Tested (emulator) | `android-pnl` **PASS** (143 s), `android-pnl-scope` **PASS** (119 s), `android-pnl-switch` **PASS** (123 s), on the final acceptance file |
| Physical Android device acceptance | **Not tested** | PENDING before Phase 5 closure (D-230, checklist §O) |
| Live suites, `--concurrency=1` | Tested | **101 passed** — reporting 13, parity 29, owner accounts 31, completeness 8, settlement 20 |
| Android dev debug build | Tested | clean rebuild with `config/dev.json` only, `app-dev-debug.apk` 242,939,162 bytes; `kernel_blob.bin` contains `MobileProfitAndLossPage`, `pnlViewShownTo`, the picker label and `pnl-scope-selector`; 0 of 6 identity passwords |
| Secret scan | Tested | working tree + git history clean; working tree + extracted APK (558 entries) clean |
| Windows build / device acceptance | Not tested | not touched by Slice 9 beyond the rewired page, which the Slice 8 Windows widget suite covers unmodified |

## Backend baseline after acceptance

Slice 9 fixtures **0 open of 9**. Settings rows **0** (the owner suite's `2026-05-01` fixture removed
with `owner_settlement_dev_fixture_cleanup.sql`). Open revenue **0**, open owner movements **0**, open
acceptance expenses **0**, open expenses **61** (pre-existing), role grants **7** (5 active), roles
**4**, closed periods **0**, dead helper absent, ledger **101**.

## Carried forward

* **Physical-device P&L pass** before Phase 5 closure (D-230).
* **D-229 wording point:** the picker is Flutter's Material `showDateRangePicker` in calendar-only
  mode, not the Android OS `MaterialDatePicker` through a platform channel. If the latter was meant,
  it needs its own approval.
* **D-227:** the owner-settlement refresher does not take the P&L lock (not demonstrated).
* **D-231 note:** a `ReportingSync` still running at sign-out keeps its owner id and could write
  owner-keyed rows after the purge (not demonstrated; for Slice 11).
* Phase 8: `may_read_expense` per-row cost; `org_id`-leading local expense index (D-223).
* The production 50:50 start date remains a project-lead decision.

**Slice 10 — breakdowns and read-only drill-down — is safe to scope from this foundation and has
not been started.**

---

# PHASE 5 SLICE 10 — REPORTING BREAKDOWN + READ-ONLY TRANSACTION DRILL-DOWN: COMPLETE

Verified 2026-09-14 against `krishna-mis-dev` only (`loratzmactetjbqolwri`). Starting HEAD
`8c1d9e9`. Decisions **D-233…D-239**; `ARCHITECTURE.md` §39; `RELEASE_CHECKLIST.md` §P.

**No schema change and no migration.** Local Drift schema stays **v21**, and the migration
ledger stays at **101** versions.

**Acceptance was a Windows real-app run and an Android emulator run. A physical Android device
pass is still required before Phase 5 closes, and is not claimed (D-230, §O.2, §P.2).**

## What shipped

**Paths** (D-235):

```
        Expenses   P&L → Expenses → Department → Section → Category → Documents → Detail
        Revenue    P&L → Revenue → Revenue Category → Documents → Detail
```

* An expense category line on the P&L is a shortcut to its exact Department + Section +
  Category bucket.
* Revenue has no entry-kind, value-band or supply-subtype level; components are shown inside
  the detail.

**Rows.** Document rows come from the canonical reporting cache, grouped by document, for the
viewer, the scope and the `pnl_date` range. A row is that document's **contribution to the
bucket**: a ₹58,000 bill shared with Hotel Krishna shows ₹25,000 under Crystal Canopy's
Kirana bucket, and says so.

**Detail** (D-233). `ReportDocumentReader` calls only the gateways' `fetch*` reads and holds
the answer in memory. Nothing is written: no transaction row, no outbox item, no reporting
cache row, no marker. `ExpensePull.pullOne` and `applyServerDocument` are not on this path.

**Bodies** (D-234). `RevenueDocumentBody` and `ExpenseDocumentBody` are immutable and own no
action. The ledger panels compose them with their actions; the drill-down uses the body alone.

**Platforms.**
* Windows: a breadcrumb, the level list, and the document in a 420 px pane on the right.
* Android: a pushed page per level on the Reports branch, native back, and bottom clearance
  for the docked [ + ].

## Rules

**Exact reconciliation** (D-236). Before any child row is shown, the children must equal the
displayed parent in integer paise, with no tolerance, and the counts must match.
* Revenue proves gross, GST and net separately; expenses prove amount.
* There is no Other, Unallocated or rounding bucket.
* On failure: "Transactions not shown — amounts do not add up exactly. Refresh."

**Stale detail** (D-236). A fetched document must explain its cached row, or the surface
says "This transaction changed since the report was synchronised. Refresh the report to
open current detail." Refresh goes through the existing synchroniser, and the report on
screen is never altered in place.

**Every open is a fetch** (D-239). Opening a document row discards any copy still held
from the last time it was open.

**Authority.** Each property needs `reports.view`, `revenue.view` and `expense.view.all`.
Consolidated needs all three unscoped. `expense.view.own` never qualifies, and no role name
is read.
* A fetch is only for a line contained in the currently authorised bucket, never a free-form
  id.
* A withheld document says "Not available to you".
* A scoped reader sees "Your allocation" (D-062).

**Scope and period.** Drill state is anchored to viewer, scope and range; changing any of
them resets it.

**Offline and older years.**
* Hierarchy, rows and amounts come from the cache and work offline.
* Detail needs a connection: "Detail not downloaded — connect to open this document."
* A report that is not downloaded, including an older financial year, offers no drill-down.

## Defects found

| | Defect | Found by |
|---|---|---|
| D-239 | Re-opening a document reused the copy still held in memory and never asked the server, so offline showed a document instead of "not downloaded" | `windows-pnl-drill` in the real executable. A diagnostic proved no request was made; two host regressions were seen RED before the fix |
| D-238 | A live authority probe asked about both properties in one call, which is the consolidated question, so a scoped manager was correctly refused | the first live run; the test was fixed, no product code changed |

**Recorded, not a defect.** One full host run reported 396 failures in 37 seconds. It had run
at the same time as an Android build. The failing files passed on their own, and the full
suite then passed alone (2,057). The cause was contention over the shared native build step,
not the code.

## Verification

| Gate | Status | Evidence |
|---|---|---|
| `dart format` | Tested | clean, 0 files changed |
| `flutter analyze` | Tested | No issues found |
| Host suite | Tested | **2,057 passed**, run alone after the D-239 fix |
| Drill-down UI, guards, session switch | Tested | 88 passed together after the fix |
| Positive controls | Tested | 10 sabotages seen RED and restored byte-identical (D-236 list), plus both D-239 regressions RED before the fix |
| Live suites, `--concurrency=1` | Tested | **106 passed**: drill-down 5, reporting 13, parity 29, owner accounts 31, completeness 8, settlement 20 |
| `windows-pnl-drill`, real `krishna_mis.exe` | Tested | **PASS** after D-239; the two runs before it failed on the offline re-open, and a diagnostic run found the cause |
| `android-pnl-drill`, emulator `emulator-5554`, Android 17 / API 37 | Tested (emulator) | **PASS**, 45 s |
| Physical Android device | **Not tested** | PENDING before Phase 5 closes (§O.2, §P.2) |
| Clean artefacts and artefact secret scan | Tested | acceptance Debug bundle removed first; `app-dev-debug.apk` (243,021,115 bytes) and the Windows Release bundle rebuilt with `config/dev.json` only; tree, git history and built artefacts scanned clean |
| Secret scan, tree and git history | Tested | clean |

## Backend after acceptance

* Drill fixtures: 5 sales and 5 expenses created by the device runs, **0 open**.
* Live suite fixtures: 6 sales and 8 expenses, **0 open**.
* Settings rows **0**; open revenue **0**; open owner movements **0**.
* Open expenses **61**, all pre-existing.
* Role grants **7** (5 active); roles **4**; closed periods **0**.
* Dead helper absent; ledger **101**.

## Carried forward, unchanged

* **Physical Android pass** for the P&L and the drill-down, before Phase 5 closes (D-230).
* **D-227:** the owner-settlement refresher does not take the P&L lock.
* **D-231:** a reporting sync still running at sign-out keeps its owner id.
* **D-229:** the calendar picker is Flutter's Material picker, not the OS dialog.
* The production 50:50 start date remains a project-lead decision.
* Phase 8: the `may_read_expense` per-row cost and the `org_id`-leading local expense index.

**Not built, and still out of scope:** owner settlement drill-down, charts, trends,
comparisons, export, printing, editing from reports, and finalized owner statements.

**Slice 11 — full live, device and two-client acceptance — is safe to scope from this
foundation and has not been started.**

---

# PHASE 5 SLICE 11 — FULL REPORTING / OWNER ACCOUNTS ACCEPTANCE: **AUTOMATED GATES COMPLETE — MANUAL PHONE PASS PENDING**

Verified 2026-09-16/17 against `krishna-mis-dev` only (`loratzmactetjbqolwri`). Decisions
**D-240 … D-248**. No schema change and no migration: local Drift schema stays **v21**, the
ledger stays at **101** versions.

**Slice 11 is NOT closed.** Every automated gate below has run and passed; the physical-device
**manual** checklist (§Q.2, ten items) is with the project lead and is recorded as **NOT
TESTED** until he reports each line. Slice 12 is not started.

## 1 · Physical Android device acceptance — the first in this project

Galaxy A06, **SM-A066B**, serial `R9ZY50M3GVX`, **Android 16 / API 36**, dev flavour against
`krishna-mis-dev`. The Pixel_8 emulator was shut down first and `adb devices` showed exactly
one target for every run; no emulator and physical run overlapped (D-230).

| Phase | Result |
|---|---|
| `android-pnl` | **PASS** |
| `android-pnl-scope` | **PASS** |
| `android-pnl-switch` | **PASS** |
| `android-pnl-drill` | **PASS** |
| `android-owner-settlement` | **PASS** |
| `slice11-shared-device` | **PASS** |
| `slice11-lifecycle` | **PASS** |

**Two failures came first and are reported as failures, not re-run into silence.** The first
run failed at sign-in with `Failed host lookup … errno = 7`: the phone has no SIM and its
Wi-Fi had dropped with the screen off, so nothing reached the backend. The second reached the
P&L and timed out in pull-to-refresh; that one is **unexplained**, a diagnostic was built to
tell its three possible causes apart, and it printed nothing across all seven later phases
(D-248).

## 2 · Windows acceptance

| Phase | Result |
|---|---|
| `windows-owner-settlement` | **PASS** |
| `slice11-shared-device` | **PASS** |
| `slice11-lifecycle` | **PASS** |
| `slice11-restart-a` / `-b` | **PASS** — re-proven on the D-246 session store, with **zero** session-recovery warnings in the log |
| `slice11-revocation` (host-coordinated, D-243) | **PASS**, 5 m 29 s |

The revocation phase ran the full handshake: five capabilities removed one at a time —
`manager` losing `reports.view`, `revenue.view` and `expense.view.all`, then `owner` losing
`owner_settlement.view` and `reports.view` — each observed through a real authority refresh and
each **restored exactly**, with the role-capability hash read back as `c1b4870f…` after every
single restore.

## 3 · Verified

| Gate | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | clean, 307 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,097 passed** |
| Live suites, `--concurrency=1` | **Tested** | **106 passed** — reporting 13, parity 29, owner accounts 31, settlement 20, drill-down 5, owner completeness audit 8 |
| Physical Android phases | **Tested** | 7 phases, above |
| Windows phases | **Tested** | 7 phases, above |
| Secret scan — tree, git history, built artefacts | **Tested** | clean, controls passing |
| Clean Android dev build | **Tested** | rebuilt with `config/dev.json` only and installed on the phone; **0 of 6** identity passwords in it |
| Physical Android **manual** checklist (§Q.2) | **NOT TESTED** | ten items, with the project lead |

**The artefact scan earned its keep again.** It first refused: the Windows **Debug** bundle and
`build/flutter_assets` — both acceptance intermediates — still carried a development identity
password. Both were removed and the scan re-run clean, which is the Slice 13 lesson repeating
(D-069): build clean, then scan the artefacts rather than assuming them.

## 4 · The development project afterwards

Compared against a fingerprint captured **before** the first run, not against memory:

| | |
|---|---|
| `owner_settlement_settings` | **0 rows** — "Settlement start date not configured". The disposable `2026-05-01` fixture was removed through the administrator teardown asset **three times**: after the phone's settlement phase, after the Windows one, and after the live suites |
| Open revenue · owner movements | **0 · 0** |
| Open expenses | **61**, every one pre-existing |
| Role grants | **7 rows, 5 active**, ids unchanged; the revocation phase's two temporary grants were revoked by the phase and their rows removed by the host (D-243) |
| Role capabilities | **80 rows**, hash `c1b4870f…` — identical to the pre-run capture |
| Closed periods · live tax rules · bands / subtypes / statuses | **0 · 4 · 0 / 0 / 0** |
| Migration ledger | **101** |

**One fingerprint moved and is not being restored.** `user_roles` row `aa7c36ee…` — the Hotel
Krishna grant the D-187 consolidated-authority regression makes and withdraws inside the live
parity suite — carries today's `granted_at` and `revoked_at` instead of 2026-09-13. The row,
its id and its revoked state are unchanged, and rewriting a timestamp to make a hash match
would be falsifying the record rather than restoring it.

## 5 · Still outstanding before Slice 12

1. **The §Q.2 manual physical-device checklist**, ten items, performed by the project lead on
   the Galaxy A06 with the clean build now installed. Item 7 — the app still signed in after a
   force-stop — is the first real test of session restore on a phone, because the emulator
   reinstalls the application on every run (D-244).
2. Slice 11 closure and the Slice 12 documentation pass, **not started**.

Carried forward unchanged: the D-146 fresh-branch migration replay before the first staging
deploy; D-229's wording point about the Material picker; and the production 50:50 settlement
start date, which remains a project-lead business decision.

---

# PHASE 5 — P&L / MIS REPORTING: **COMPLETE AND CLOSED**

Closed 2026-09-17 at Slice 12. Master Spec **v1.2**, unchanged: Phase 5 added no financial
semantics. Local Drift schema **v21**; migration ledger **101** versions. Decisions
**D-163 … D-250**.

## 1 · What Phase 5 built

| | |
|---|---|
| Calculation | `domain/finance` — the one canonical specification: period math, Net Sales, Operating Profit, margin as an exact ratio, refusals as types |
| Engines | `LocalReportingEngine` and `RemoteReportingEngine`, one orchestration over two sources, parity proven to the paisa |
| Cache | canonical reporting cache, owner-keyed, with document-grain delta, coverage markers and one-snapshot evidence |
| Server | `reporting_primitives` and `reporting_snapshot`, `security invoker`, one statement each |
| Authority | `reports.view` ∩ `revenue.view` ∩ `expense.view.all` per property; all three unscoped for consolidated; `expense.view.own` never qualifies |
| Surfaces | Windows P&L, Android P&L, and read-only drill-down to a document on both |
| Owner Accounts | OA-1 ledger and masters, OA-2 settlement engine, OA-3 preview surface behind its own capability |

**Not built, by design:** charts, exports, printing, finalized owner statements, performance
optimisation, production deployment.

## 2 · Slices and Owner Accounts

| | | |
|---|---|---|
| 1 | source parity and the canonical-only correction | **COMPLETE** |
| 2 | `domain/finance` | **COMPLETE** |
| 3 | `LocalReportingEngine` | **COMPLETE** |
| 4 | canonical reporting cache and delta | **COMPLETE** |
| 5 | server boundary and D-020 parity, with the `reports.view` corrective | **COMPLETE** |
| 6 | freshness, as-of and closed periods, with the one-snapshot corrective | **COMPLETE** |
| 7 | reporting security closure | **COMPLETE** |
| 8 | Windows P&L surface | **COMPLETE** |
| 9 | Android P&L surface | **COMPLETE** |
| 10 | breakdown and read-only drill-down | **COMPLETE** |
| 11 | full reporting / Owner Accounts acceptance | **COMPLETE** |
| 12 | closure | **COMPLETE** |
| OA-1 | owner accounts foundation | **COMPLETE** |
| OA-2 | owner settlement engine | **COMPLETE** |
| OA-3 | owner settlement preview and its boundary | **COMPLETE** |

## 3 · Closure evidence

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | clean |
| `flutter analyze` | **No issues found** |
| Host suite | **2,107 passed** |
| Live suites, `--concurrency=1` | **106 passed** — reporting 13, parity 29, owner accounts 31, settlement 20, drill-down 5, owner completeness audit 8 |
| Windows acceptance | `windows-owner-settlement`, `slice11-shared-device`, `slice11-lifecycle`, `slice11-restart-a`/`-b`, `slice11-revocation` — **all PASS** |
| Android emulator acceptance | the Slice 9 and Slice 10 phases, recorded in their own sections |
| **Physical Galaxy A06** | `android-pnl`, `-scope`, `-switch`, `-drill`, `android-owner-settlement`, `slice11-shared-device`, `slice11-lifecycle` — **all PASS**; the ten §Q.2 manual checks **PASS**, reported by the project lead on 17 September 2026 |
| Windows release build | rebuilt from this HEAD; `data/app.so` current |
| Android dev build | rebuilt from this HEAD, `config/dev.json` only |
| Secret scan | tree, git history and rebuilt artefacts **clean** |
| Backend baseline | at the captured fingerprint (§5) |

**The artefact scan refused twice before it passed, and both times it was right.** Acceptance
runs compile the identity passwords into the Windows **Debug** bundle and
`build/flutter_assets`; each was removed and the scan re-run. Build clean, *then* scan the
artefacts — the Slice 13 lesson, twice more (D-069).

## 4 · The defects Slice 11 carried, and their final disposition

| | |
|---|---|
| **D-227** | **Closed by D-241.** One `CanonicalCacheLock` in the data layer; the P&L, the drill-down and the settlement refresh and preview all take it |
| **D-231** | **Closed by D-240.** A cache authority generation, advanced inside the purge's own transaction and re-checked inside the writing transaction; a superseded run rolls back and reports itself abandoned |
| **D-246** | Implemented, and completed by **D-249**: the session has its own DPAPI file, and an acceptance run now has its own database key, selected by the data folder. **Android unchanged** |
| **D-247** | The 31 August real-installation database stays untouched — not deleted, not recovered, not migrated, never a fixture. No disposal decision is required for closure |
| **D-229** | **Closed by D-250**: Flutter's Material date-range picker is approved for Android V1; "native picker" meant a calendar interaction rather than typed desktop entry. No rework, no new dependency |

## 5 · `krishna-mis-dev` at closure

| | |
|---|---|
| Open acceptance revenue · owner movements | **0 · 0** |
| Open expenses | **61**, all pre-existing; nothing acceptance created remains |
| Disposable settlement start date | **removed** — `owner_settlement_settings` holds **0 rows** |
| Closed-period fixtures | **0** |
| Grants · roles | **7 rows, 5 active** · **4 roles**, no temporary role or capability |
| Role capabilities | **80 rows**, hash `c1b4870f…`, identical to the pre-run capture |
| Tax configuration | **4** live rules · **0** bands · **0** subtypes · **0** premises statuses |
| Attachments ↔ storage | **265 rows ↔ 265 objects**, 0 stranded |
| Reviewed API · anon execute · client writes · tables without RLS | **57 · 0 · 0 · 0** |
| Dead helper `expense_sees_whole_org` | **absent** |
| Migration ledger | **101** |

One fingerprint moved and is deliberately not rewritten: `user_roles` row `aa7c36ee…`, the
grant the D-187 regression makes and withdraws inside the live parity suite, carries today's
timestamps. Same row, same id, same revoked state — falsifying a timestamp to make a hash
match would not be restoring anything.

## 6 · Carry-forwards, classified

Nothing is left as "later".

| Item | Owner |
|---|---|
| Charts, trends, period-over-period, dashboard analytics | **A — Phase 6** |
| Excel export, PDF, printing, and the `reports.export` / `reports.print` evaluators | **B — Phase 7** |
| `may_read_expense` per-row reporting cost; the `org_id`-leading local expense index; any materialised aggregate | **C — Phase 8** |
| Production signing, AAB, Play distribution, Windows installer, production Supabase configuration, and the D-146 fresh-branch migration replay before the first staging deploy | **D — Phase 9** |
| **The production 50:50 ownership effective-from date.** Production Owner Settlement remains intentionally unconfigured until the project lead supplies the real effective-from date. Never guessed | **E — Product/business** |
| Disposal of the D-247 forensic database — no decision required for Phase 5 | **E — Product/business** |
| Finalized Owner Statements and their Draft/Finalized model (D-193); a per-family-member breakdown of non-chargeable consumption; wiring the owner-ledger outbox transport (D-218); OA-1's client-side NC pre-check (D-208, D-216) | **F — Owner Accounts extension** |

## 7 · Open defects at closure

**None.** One recorded unknown remains a question rather than a defect: **D-248**, a single
pull-to-refresh timeout on the phone, with a diagnostic left armed that has printed nothing in
every run since.

## 8 · Phase 6 handoff

Phase 6 may treat as stable: `domain/finance` and its result types; both engines and the port
between them; the canonical reporting cache, its coverage vocabulary and its one-snapshot
evidence; the reporting capability model; the two P&L surfaces and the presentation vocabulary
they share; and the Owner Accounts boundary.

Phase 6 **must not**: re-run tax rules, infer GST from totals, include pending, rejected or
conflicted attempts, reinterpret the business date, mutate closed history, compute a second
P&L, or render a chart from anything but a `PnlResult` the engines produced.

---

# PHASE 6 — DASHBOARD & ANALYTICS: STARTED (2026-09-17)

Phase 5 closed at `b2a161d`. Phase 6 was scoped by an audit of the shipped code; the project
lead ruled on its eight questions, and the rulings are recorded as **D-251 … D-261**.

**The principle:** Phase 6 creates no second financial calculation model. Every dashboard
figure is a field of a `PnlResult` the Phase 5 engines produced, or a comparison of two of them
computed once in `domain/finance`. No widget recomputes a P&L, no GST is re-derived, no pending
or conflicted attempt is counted, no transaction table is queried for a chart, no second
reporting cache is created, and authorization stays `PnlAuthority`.

## The approved slice plan

| # | Slice | State |
|---|---|---|
| 1 | Governance and decisions | **COMPLETE** |
| 2 | Exact comparison domain rules | **COMPLETE** |
| 3 | Dashboard engine, and the performance gate | **COMPLETE** |
| 4 | Authority and providers | **COMPLETE** |
| 5 | Chart foundation (`fl_chart`, pinned, with a no-arithmetic guard) | **COMPLETE** |
| 6 | Windows Overview dashboard | **COMPLETE** |
| 7 | Android Home dashboard | **COMPLETE** |
| 8 | Windows Analytics sections | **COMPLETE** |
| 9 | Drill-down integration | **COMPLETE** |
| 10 | Full acceptance | **CLOSED** (2026-09-25) |
| 11 | Closure | **CLOSED** (2026-09-25, D-289) |

**Performance gate (D-261):** before Slice 3 closes, trend series built from ordinary
repeated reports are measured on financial-year-sized data. If they are too slow, work stops and
the measurements are reported. No server analytics function, materialised aggregate, index or
second cache is added without a separate decision.

## Phase 6 Slice 1 — governance: **COMPLETE**

* `DECISIONS.md` — D-251 … D-261.
* `SHOYEB_MASTER_SPEC.md` — §17 amended with the dashboard period and comparison semantics,
  change-log entry, **version unchanged at 1.2**: it defines what §17 already named and moves no
  figure.
* `ARCHITECTURE.md` — §41.
* This section.

## Phase 6 Slice 2 — exact comparison domain rules: **COMPLETE**

Pure Dart in `lib/domain/finance/`. **No schema change, no migration, no dependency, no
surface.** Local Drift schema stays **v21**; migration ledger stays **101**.

| File | What it decides |
|---|---|
| `dashboard_periods.dart` | the dashboard periods — Today so far, Week to date, Month to date, Financial year to date, Custom — and each one's comparator; the calendar-edge caps; the consolidated both-sides agreement check (D-251, D-252, D-254) |
| `pnl_comparison.dart` | rupee change, percentage change, the Operating Profit rules, the sign-change wording, and the margin movement in percentage points — exact, over paise, `BigInt` where a cross product can pass 2^63 (D-253, D-256) |
| `dashboard_analytics.dart` | trend buckets and which measure each grain may carry; best and worst day on daily Net Sales only; Top N + Others after exact reconciliation (D-255, D-258) |

The Phase 5 P&L presets (`reporting_presets.dart`) are untouched: the P&L screen keeps its
whole-month and whole-year semantics (D-252).

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean |
| `flutter analyze` | **Tested** | **No issues found** |
| New domain tests | **Tested** | **91**: periods 34 (including a sweep of every day 2026–2029), comparison 34, analytics 23 |
| Finance purity guard over the three new files | **Tested** | 6 checks: no storage, network, Flutter or floating-point |
| Host suite | **Tested** | **2,204 passed** (2,107 + 91 + 6) |
| Positive controls | **Tested** | 11 sabotages, **each failed on behaviour, not compilation**, each file restored byte-identical and compared: month cap (4 red), leap-day cap (2), custom comparator overlap (3), D-254 comparison check (1), previous-zero rule (24), sign-change rule (2), margin movement from rounded margins (1), unavailable side turned to zero (3), Top-N reconciliation (3), grain permission (2), silent tie-break (1) |
| Live, device and build gates | **Not tested** | nothing in Slice 2 touches a surface, the server or a build |

### ~~Recorded for the project lead~~ — all three answered 2026-09-20

1. ~~**D-256 — pending confirmation.**~~ **Answered: the rule is wider than the guess.** An
   ordinary figure shows a percentage only when `previous > 0 && current >= 0`; a negative
   **current** value now suppresses it too, and the rupee movement is shown in every case.
2. ~~**D-255 — open: the trend grain for a Custom range.**~~ **Answered (D-263):** Net Sales
   daily to 31 days, weekly to 180, monthly beyond; Expenses and Operating Profit monthly only
   and withheld below two buckets; a missing bucket is a gap, never zero.
3. ~~**D-253 — a consequence of "exact".**~~ **Answered (D-264):** the **displayed** movement
   is the difference of the two displayed margins, so the three figures on screen reconcile.
   The exact movement stays canonical and is not replaced.

**Every approved dashboard analytic is representable on the Phase 5 foundation.** Nothing in
Slice 2 needed a new server function, cache dimension or schema change.

## Phase 6 Slice 2 closure — the three pending rulings: **DONE** (2026-09-20)

Pure Dart in `lib/domain/finance/`. **No schema change, no migration, no dependency, no
surface.** Local Drift schema stays **v21**; migration ledger stays **101**.

| Ruling | What changed |
|---|---|
| **D-256, final** | `currentNegative` joins the reasons; `_ordinary` shows a percentage only for `previous > 0 && current >= 0`; `eitherSideNegative` is derived once for a surface's wording. Operating Profit untouched |
| **D-263** | `netSalesGrainForCustom` (31 / 180 day thresholds), `offersMonthlyCostTrend`, `grainsFor` now takes the measure and — for custom — the range; `TrendSeries` / `TrendValue` / `TrendGap` make "never zero, never interpolated" a type |
| **D-264** | `displayedPointsScaled` and the display string it feeds; `pointsScaled` stays the canonical exact figure, `exactDisplayTwoDecimals` formats it |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test` | **Tested** | clean, 307 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,242 passed** (2,204 + 38) |
| Finance domain suites | **Tested** | 277 passed, incl. the 60,500-pair margin reconciliation sweep |
| Secret scan — tree and git history | **Tested** | clean |
| Live / device / build gates | **Not tested** | nothing here touches a surface, the server or a build |

### Positive controls, each seen RED and restored byte-identical (`cmp`)

| Control | Result |
|---|---|
| the D-256 current-negative branch removed | **2 RED** |
| `displayTwoDecimals` pointed back at the exact movement | **2 RED** |
| the custom daily threshold moved 31 → 30 | **1 RED** |
| the too-short monthly cost-trend guard removed | **1 RED** |
| a refused bucket turned into a zero `TrendValue` | **2 RED** |

### One threshold stated rather than ruled

D-263 says a monthly Expenses or Operating Profit trend is withheld when a custom range is
"too short", and the ruling set no number. The implemented threshold is **more than one
bucket** — one point shows no direction, so it is not a trend at all — and partial first and
last buckets count toward it. That is the definition of a trend rather than a business rule;
a stricter meaningfulness rule (say, one complete month) would be a separate decision.

## Phase 6 Slice 3 — dashboard engine and the performance gate: **COMPLETE** (2026-09-20)

Decisions **D-265**, **D-266**; `ARCHITECTURE.md` §42. **No schema change, no migration, no
dependency, no surface, no server function.** Local Drift schema stays **v21**; migration
ledger stays **101**.

### What shipped

`lib/data/reporting/dashboard_engine.dart` — `DashboardRequest`, `DashboardView`,
`DashboardReadStats` and the engine itself:

```
        plan        every DISTINCT range the view needs, headline first
        read        one report per range, through the Phase 5 engine,
                    all of it inside ONE CanonicalCacheLock span
        assemble    PnlComparison · DashboardTrends.series ·
                    DailyNetSalesRanking · TopN
```

It derives nothing: every figure is `domain/finance`'s, and a dedicated guard asserts both
that the delegation is present and that none of thirteen domain result types is
constructed here.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 320 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,270 passed** (2,242 + 28) |
| Dashboard engine behaviour, on the real cache | **Tested** | 12 tests — headline, comparator, trends, ranking, Top N, refusal, coverage, freshness, one span |
| Dashboard engine structural guard | **Tested** | 13 tests, four of them planted-violation self-checks |
| Host performance measurement | **Tested** | 2 tests; reads and points asserted, timings reported |
| On-device measurement, **real encrypted database** | **Tested** | Windows ×2 samples, Android emulator ×3 samples |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Physical Android device | **Not tested** | emulator only; a physical pass belongs with the Phase 6 acceptance slice (D-230) |
| Live backend | **Not exercised** | the engine issues no remote call; the download is unchanged Phase 5 `ReportingSync` |

### Positive controls, each seen RED and restored byte-identical (`cmp`)

| Control | Result |
|---|---|
| the range set degraded to a list, so a range can be read twice | **2 RED** |
| the reads moved out of the lock span | **1 RED** — and the count guard passed, which the guard now records about itself |
| the refused-headline short-circuit removed | **1 RED** |
| the freshness badge taken from the headline alone | **1 RED** |
| a read placed before the span opens | **1 RED** (the guard added for it) |

### The performance gate (D-261), discharged

Fixture: **4,380 revenue contributions, 2,920 expense contributions**, 2 financial years,
2 properties, a 2.5 MB database, all consolidated — the heavier scope.

**Windows, real encrypted database, two samples:**

| Workload | reports | points | cold | warm |
|---|---|---|---|---|
| FYTD, whole year, monthly ×3, top 5 | 14 | 36 | 119 / 134 ms | 86 / 95 ms |
| FYTD, mid-year, monthly ×3, top 5 | 8 | 18 | 49 / 49 ms | 45 / 42 ms |
| **month to date, daily + weekly, ranked, top 5** | **37** | **35** | **170 / 181 ms** | **168 / 151 ms** |
| week to date, daily, ranked | 6 | 4 | 32 / 30 ms | 25 / 31 ms |
| custom 365 days, monthly ×3 | 14 | 36 | 74 / 71 ms | 74 / 71 ms |
| custom 180 days, weekly | 28 | 26 | 120 / 123 ms | 122 / 125 ms |
| custom 31 days, daily, ranked | 33 | 31 | 153 / 157 ms | 146 / 155 ms |
| headline + comparator alone | 2 | — | 10 / 8 ms | — |

**Android emulator** (`sdk gphone16k x86_64`, Android 17 / API 37, debug build), three
samples. Run 1 was taken on a just-booted emulator and is discarded as warm-up — the
evidence is inside run 1 itself: a 28-report workload cost 29 ms cold while a 14-report one
cost 319 ms, and the heaviest cost 685 ms cold against 31 ms warm in the same run. Cost
that does not follow the work is not the work.

| Workload | run 1 cold | run 2 cold | run 3 cold | warm (runs 2–3) |
|---|---|---|---|---|
| FYTD, whole year | 319 ms | 60 ms | 67 ms | 23–24 ms |
| FYTD, mid-year | 53 ms | 13 ms | 14 ms | 10–12 ms |
| **month to date, daily + weekly, ranked** | **685 ms** | **41 ms** | **38 ms** | **31–41 ms** |
| week to date, daily, ranked | 88 ms | 6 ms | 5 ms | 5 ms |
| custom 365 days, monthly ×3 | 69 ms | 18 ms | 19 ms | 19–21 ms |
| custom 180 days, weekly | 29 ms | 28 ms | 29 ms | 25 ms |
| custom 31 days, daily, ranked | 215 ms | 24 ms | 27 ms | 24 ms |

**Cold versus warm.** On Windows they are within about 15% of each other, so there is no
material cold-start effect there. On Android the first run of a debug build is dominated by
code warm-up and the second and third agree closely; steady state is what the table's warm
column reports.

**Number of `PnlResult` requests** is the reports column: one consolidated result per
distinct range, each composed from one per-property computation per property. **Trend
points** is the points column.

**Remote / download.** Not applicable to the engine — it issues no remote call. The
download that fills the cache is the unchanged Phase 5 `ReportingSync`, already measured
live in Slice 5 (one month 39 ms server-side, 98–185 ms end to end to Mumbai; consolidated
financial year 368–398 ms). The local half of a **first full synchronisation** of this
fixture — 7,300 contributions in one transaction — measured **527–2,718 ms on Windows** and
**824–6,711 ms on the emulator**, with wide spread. That is a one-off cost on a fresh
installation, not a per-dashboard cost, and it is Phase 5 machinery.

### The conclusion, and what was therefore not added

**The existing Phase 5 foundation is sufficient. Nothing was added** — no dashboard RPC, no
second reporting cache, no materialised aggregate, no new index, no new server reporting
function.

* The worst steady-state dashboard is **168 ms**, against the 400 ms escalation trigger
  `ARCHITECTURE.md` §9 records.
* Cost is **linear in reports**, and the per-report cost is the Phase 5 engine's: 2 reports
  cost 8–10 ms on Windows and 37 cost 151–181 ms. Nothing about a dashboard is a new query
  shape.
* The grain rulings bound the work: D-263's thresholds are why a year-long custom range is
  14 reports rather than 367, and D-255 is why a financial year to date is 12 buckets
  shared by three series rather than three sets.

**One option recorded rather than taken.** Each report reads four aggregates per property,
and a trend bucket needs only two of them; suppressing the breakdown on bucket reads would
roughly halve the heaviest dashboard's query count. Not done, because the gate's
instruction was to change nothing the measurement does not require. Recorded so a future
measurement on slower hardware has an obvious first move.

### Limits of this evidence, stated

The Android figures are from the **emulator** and a **debug** build, not the project lead's
Galaxy A06 — a physical-device dashboard pass belongs with the Phase 6 acceptance slice,
exactly where D-230 placed the P&L one. The fixture is two financial years, which is the
local retention ceiling (D-170).

## Phase 6 Slice 4 — authority and providers: **COMPLETE** (2026-09-21)

Decision **D-267**; `ARCHITECTURE.md` §43. **No schema change, no migration, no server or
API change, no chart and no screen.** Local Drift schema stays **v21**; migration ledger
stays **101**.

Written **test-first**: `test/features/dashboard_providers_test.dart` was written and run
against an API that did not exist, and failed to compile, before any provider was written.

### What shipped

`lib/features/dashboard/presentation/dashboard_providers.dart` only:

| | |
|---|---|
| selection | `dashboardSelectionProvider`, keyed on `PnlAuthority.readKey` |
| scopes | **`pnlScopeOptionsProvider`, reused** — the same provider the P&L uses |
| periods | `DashboardPeriods.forUnits` / `forCustom` under each property's own rules |
| request | `dashboardRequestFor`, whose grains are `DashboardTrends.grainsFor`'s answer |
| engine | `dashboardEngineProvider` → one `DashboardEngine.build` |
| state | `DashboardState` — not authorised · period unavailable · ready, each stamped with the authority key |
| visibility | `dashboardShownTo`, comparing the **authority key**, not the person |
| presentation | `dashboardPresentation` — loading · available(+refresh failure) · unavailable(reason) |
| synchronisation | `dashboardSyncProvider`, the unchanged Phase 5 `ReportingSync` |

### The eighteen required proofs

| | Proof | Where |
|---|---|---|
| 1 | qualifying one-property authority — and it is selected automatically | ✔ |
| 2 | qualifying two-property authority; consolidated is **not** implied by two scoped grants | ✔ |
| 3 | consolidated authority, and it is the default (the existing P&L convention) | ✔ |
| 4 | `expense.view.own` never qualifies | ✔ |
| 5 | `reports.view` alone does not qualify | ✔ |
| 6 | revenue-side only does not qualify | ✔ |
| 7 | expense-side only does not qualify | ✔ |
| 8 | user A → user B cannot expose A's dashboard | ✔ |
| 9 | capability revocation invalidates the dashboard at once | ✔ |
| 10 | a selected revoked property resolves to a permitted scope, or to nothing | ✔ (two tests) |
| 11 | a stale in-flight assembly is not the visible dashboard | ✔ (real lock held) |
| 12 | a no-authority principal receives no financial result | ✔ |
| 13 | the planner's own pair, not provider arithmetic | ✔ (behavioural + guard) |
| 14 | a consolidated D-225/D-254 mismatch refuses the period | ✔ (state + availability) |
| 15 | a failed refresh retains the complete dashboard, failure reported separately | ✔ |
| 16 | missing data is unavailable, never zero | ✔ |
| 17 | freshness comes from the engine, not recomputed | ✔ (three tests + guard) |
| 18 | Owner Accounts capabilities alone grant nothing here | ✔ |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 323 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,319 passed** (2,270 + 49) |
| Dashboard providers, through the real chain | **Tested** | 34 tests |
| Dashboard surface guard | **Tested** | 15 tests, six of them planted-violation self-checks |
| Secret scan — tree and git history | **Tested** | clean, controls passing |
| Schema / migrations / server API | **Unchanged** | `git diff` over `supabase/` and `lib/data/local/` is empty |
| Chart or screen | **Not built** | asserted by the guard over the whole feature directory |
| Live backend, device acceptance | **Not exercised** | Slice 4 adds no remote call and no surface |

### Positive controls, each seen RED and restored byte-identical (`cmp`)

| Control | Result |
|---|---|
| authority identity reduced to the person alone | **3 RED** — revocation, in-flight isolation, guard |
| `expense.view.own` made to qualify, in `PnlAuthority` itself | **1 RED** — proving the dashboard depends on that rule rather than restating it |
| stale publication allowed after a switch or revocation | **4 RED** — user switch, revocation, in-flight isolation, guard |

### One deliberate divergence from the P&L, recorded

`DashboardSyncController` keys its status on the **authority**, where `PnlSyncController`
keys on the person. A status describing a scope this authority cannot read is not this
authority's status, and a person key would leave a capability change with a run stuck at
*synchronising* and the next refusing to start behind it.

**This is not a P&L defect.** `ReportingSync` abandons a run whose reporting capabilities
have moved (D-240), the controller reports it as neither success nor failure, and the P&L
re-reads under the new authority. It is recorded so the difference reads as deliberate.

### Nothing was found that the existing authority model cannot represent

The slice's stop condition — *if the Phase 5 authority model cannot represent an approved
dashboard requirement, STOP before introducing another* — was not reached. Every
requirement is expressible as `PnlAuthority` already states it, and the scope options are
the same provider rather than a parallel one.

## Phase 6 Slice 5 — chart foundation: **COMPLETE** (2026-09-21)

Decisions **D-268**, **D-269**; `ARCHITECTURE.md` §44. **No schema change, no migration, no
server or API change, and no screen.** Local Drift schema stays **v21**; migration ledger
stays **101**. Written test-first: `test/core/chart_models_test.dart` was written and run
against an API that did not exist, and failed to compile.

### The dependency

**`fl_chart: 1.2.0`, pinned exactly.** Verified against this toolchain (Flutter 3.44.9,
Dart 3.12.2) before it was added, by reading the package rather than its description: gaps
via `FlSpot.nullSpot`, negative bars via `BarChartRodData(fromY/toY)`, and tooltip callbacks
that hand back an **index** (`spotIndex`, `touchedBarGroupIndex`) — which is what lets a
tooltip state the prepared figure instead of the coordinate. It publishes no accessibility,
so the layer wraps every chart in one `Semantics` node. It brings `equatable` and nothing
else. **No STOP condition was reached**: every approved behaviour is representable, including
horizontal bars.

### What shipped

`lib/core/design/charts/` only — models, adapters, theme, frame, selection, semantics and
four widgets covering the six approved families. **Nothing is wired into a screen**, and a
guard asserts that; it is the assertion Slice 6 must deliberately change.

| | |
|---|---|
| exactness | `ChartAmount` holds the exact `Money` and the formatter's string; the coordinate is a **getter** over it, and no constructor takes a `double` |
| tooltips | looked up by the touched index, never formatted from a coordinate |
| one conversion | `ChartSelection.indexAt` — a position to a **category index**, which carries no money. A guard asserts it is the only one |
| gaps | `ChartAbsent` carries no amount; the line breaks at `FlSpot.nullSpot`, the bar draws **no rod**, and break-even draws a rod *at* zero |
| the axis | anchored at zero always; the baseline is an explicit reference line, not a grid line that happens to land there |
| never colour alone | marker shape, dash pattern, legend name, the side of the baseline, the sign on the figure, and the word — *profit*, *loss*, *break-even* |
| refusals | a refused `TopN` and an all-gap trend draw a stated reason, never an empty plot |
| animation | off, so an assertion never reads a figure on its way somewhere (D-152) |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 0 changed |
| `flutter analyze` | **Tested** | **No issues found** |
| Chart models | **Tested** | **24** tests |
| Chart widgets | **Tested** | **20** tests — rods, spots, readout text, geometry at 360dp |
| Structural guards | **Tested** | **26** tests, 8 of them planted-violation self-checks |
| Host suite | **Tested** | **2,389 passed, 0 skipped** (2,319 + 70) |
| Windows build | **Tested** | `flutter build windows --release` → `krishna_mis.exe` |
| Android build | **Tested** | `flutter build apk --debug --flavor dev` → `app-dev-debug.apk` |
| Secret scan — tree, git history and built artefacts | **Tested** | clean, the scanner's own controls passing |
| Schema / migrations / server | **Unchanged** | `git diff` over `supabase/` and `lib/data/local/` is empty |
| Live backend, device acceptance | **Not exercised** | Slice 5 adds no remote call and no surface |

### Positive controls, each seen RED and restored byte-identical (`cmp`)

| Control | Result |
|---|---|
| a `TrendGap` converted to a zero point | **10 RED** |
| a tooltip built by formatting the plotted `double` | **3 RED** — the tooltip assertion and two structural guards |
| the ranked adapter re-ranking and re-summing the domain's lines | **5 RED** — both guards, plus membership, geometry and the hover readout |
| `ChartAmount` reduced to its coordinate, with the exact source removed | **RED at compile** — 9 errors across `lib/` and the tests. That is the control working: with no exact source, the axis has nothing to build from and the label has nowhere to come from |

Each was restored with a byte copy and verified with `cmp` (D-219), and the suite was
re-run green after each.

### One number checked rather than assumed

2,389 is not 2,319 + 86, and the gap was measured rather than explained away: a worktree at
`fcd464b` confirms the Slice 4 baseline is **2,319**, and `test/core/` already held
`money_formatter_test.dart` (**16** tests). The three chart files therefore contribute
**70**, and 2,319 + 70 = 2,389. Nothing was lost.

### One implementation choice, flagged rather than buried (D-269)

The three ranked horizontal families are composed from the design system's own text and a
proportional fill rather than plotted on a rotated axis. A ranked bar chart is a **list with
a bar**, and two requirements decide it: a category reads *Crystal Canopy Rooftop · Kirana &
Pulses*, which as an axis tick at 360dp either truncates the name or takes a third of the
plot from the bars; and **money must never be truncated or wrapped**, because a truncated
amount is a wrong amount.

This is **not** a second charting library and not a rejection of fl_chart, which draws the
other three families and could draw these (`rotationQuarterTurns`). It lives in the same
layer under the same models, formatters, selection and description, and it is reversible in
one file. **For the project lead to confirm or redirect.**

### D-269 resolved (2026-09-22)

**The project lead ruled: keep the composed implementation.** Revenue mix, top expense
categories and department spending stay ranked lists with a proportional fill, and are
**not** to be replaced with rotated `fl_chart` axes in V1 — the complete category or
department name, the exact INR value, the rank, the proportional magnitude and
accessibility rank above maintaining a conventional axis. No rework, no new dependency, no
change to any domain or dashboard semantics. Recorded as **D-269 (final)**.

---

## Phase 6 Slice 6 — Windows Overview dashboard: **COMPLETE** (2026-09-22)

Implementation commit **`00a4017`**; starting HEAD `8e0699c`. Decisions **D-270 … D-273**;
`ARCHITECTURE.md` §45. **No schema change, no migration, no Supabase or server change, no
new dependency.** Local Drift schema stays **v21**; the
migration ledger stays at **101** versions.

### What shipped

The Windows Overview placeholder is replaced by the management dashboard, built entirely on
the Slice 2–5 foundation.

| | |
|---|---|
| `lib/features/dashboard/presentation/overview_page.dart` | the surface — it arranges and formats, and computes nothing |
| `lib/features/dashboard/presentation/dashboard_presentation.dart` | every word the dashboard says, shared with the Android Home before that surface exists (D-232's rule, applied early) |
| `lib/domain/finance/property_comparison.dart` | the per-property split, through `Pnl.compute` (D-270) |
| `lib/core/formatting/report_dates.dart` | one place turns a reporting date into words; the P&L delegates to it (D-271) |
| `DashboardView.propertyComparison` · `.departmentSpending` | carried by the Slice 3 engine, at **no extra read** |
| `MoneyFormatter.movement` | `+₹1,200.00` for a period-over-period change |

Content, in the approved order: header (scope · period · freshness · refresh); Net Sales,
Operating Expenses, Operating Profit/Loss and Operating Margin, with Gross Sales and GST
secondary to Net Sales; the Net Sales trend; the monthly Operating Profit trend where the
planner offers one; property comparison when consolidated; revenue mix; top expense
categories; department spending. Nothing decorative was added.

**Drill-down is Slice 9.** The sections carry selection callbacks and no route, and the
guard forbids navigation in the feature.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 343 files |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,449 passed** (2,389 + 60) |
| Windows Overview acceptance, real provider chain | **Tested** | 33 tests — the 25 required proofs, at 1366×768, 1024×700 and 1920×1080 |
| Per-property split, pure domain | **Tested** | 10 tests |
| Dashboard surface guard, narrowed for a surface | **Tested** | 29 tests, 9 of them planted-violation self-checks |
| Chart-layer guard, narrowed for a wired surface | **Tested** | 27 tests |
| Positive controls | **Tested** | **5 sabotages, each seen RED**, each restored by byte copy and `cmp` |
| Windows release build | **Tested** | `flutter build windows --release` → `krishna_mis.exe` |
| Secret scan — tree, git history, built artefacts | **Tested** | clean, the scanner's own controls passing |
| Schema / migrations / server | **Unchanged** | `git diff` over `supabase/` and `lib/data/local/` is empty; schema v21, ledger 101 |
| Android build · device acceptance | **Not tested** | Slice 6 is the Windows surface; Slice 7 is Android and Slice 10 owns cross-platform acceptance |
| Real `krishna_mis.exe` visual acceptance | **Not run** | no Overview device phase exists yet; the surface is proven by the widget and provider suites |

### The five positive controls, each seen RED and restored byte-identically

| Control | Result |
|---|---|
| an unavailable comparison rendered as ₹0.00 | **1 RED** |
| the single-property refusal removed from `PropertyComparison` | **5 RED** — 3 domain, 2 surface |
| the authority identity dropped from the display guard | **4 RED** — 3 provider, 1 guard; **and 1 more after the vacuous assertion it exposed was fixed** |
| a `TrendGap` joined up as a zero point | **11 RED** |
| the wording working out its own percentage | **3 RED** — 2 behavioural, 1 guard |

### What rendering and the controls found (D-273)

**A layout defect at 1366×768.** Four metrics across leave a ~245-pixel column, and
*Gross ₹13,23,420.00 · GST ₹6,302.00* overflowed it by 85 pixels. Money is never
ellipsised, so the pair now wraps. Found by rendering, not by review — the D-123 family at
a width nobody had rendered at.

**One of this slice's own assertions was vacuous, and a control found it.** The
authority-switch test asserted no dashboard body was on screen after the switch, and stayed
**green** with the display guard deliberately removed: at that moment the provider holds no
previous value at all, so the test measured Riverpod's reload rather than the rule. It now
exercises the rule directly and goes red under the control.

**Two guard defects, both found by running the guard.** `customSelect` matched
`customSelected`, a local on the period bar (the D-069 false-positive family); and
`dart format` reflowed a phrase assertion across two lines and turned it red for a line
break (D-153), so phrase assertions now match against whitespace-collapsed source.

### Recorded, and not staged

**A trend gap is not reachable end to end today.** Reporting coverage is recorded per
financial year, so every bucket shares its coverage with the headline: a year that is not
downloaded refuses the headline too. The gap behaviour is proven through
`dashboardTrendChartData` — the one adapter the surface uses — from a series carrying a
refused bucket, and again in the chart layer's own suite. It is stated rather than faked.

**One full-suite run reported a single failure that is not one.**
`financial_cache_retention_test.dart` — *"the revoked share is not left legible in the
database file"* — timed out at 30 s under load, as it did once in Slice 9. It passes on its
own and in the re-run; no Slice 6 code is on its path.

## Next exact task

*Superseded — Slice 7 is complete. The current record is* **Phase 6 Slice 7** *below.*

---

## Phase 6 Slice 7 — Android Home dashboard: **COMPLETE** (2026-09-23)

Starting HEAD `3f39ab5`; implementation commit `fc78d09`. Decisions **D-274 … D-276**; `ARCHITECTURE.md` §46;
`RELEASE_CHECKLIST.md` §R. **No schema change, no migration, no Supabase or server change,
no new dependency.** Local Drift schema stays **v21**; the migration ledger stays at **101**
versions.

### What shipped

The Android **Home** tab is the management dashboard. It is the Slice 6 dashboard arranged
for a phone, not a second one.

| | |
|---|---|
| `lib/features/dashboard/presentation/mobile_home_page.dart` | the phone surface — it arranges and formats, and computes nothing |
| `lib/app/routing/app_router.dart` | Home is `MobileHomePage`; `AppRouter.mobileReportsBranch` names where Reports sits |
| `dashboard_presentation.dart` | gains `dashboardConsolidatedScopeLabel`, the one sentence three sites had been writing separately |
| `dashboard_surface_guard_test.dart` | every surface rule now runs over **both** surfaces (D-275) |

Content, in the approved order (D-260): scope, period and freshness; Net Sales with Gross
Sales and GST secondary to it, Operating Expenses, Operating Profit or Loss and Operating
Margin, each with its comparison; the Net Sales trend; property comparison when the reader
holds consolidated authority; top expense categories; and *See full P&L*. **Revenue mix,
department spending and the monthly profit trend are not on the phone** — the engine still
carries them and the surface does not show them.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 345 files, 0 changed |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,486 passed** (2,449 + 28 phone acceptance + 9 guard) |
| Android Home acceptance, real provider chain in the real phone shell | **Tested** | 28 tests at 360×740, 390×844, 430×932, landscape and 1.6× text |
| Dashboard surface guard, over both surfaces | **Tested** | 38 tests, 12 of them planted-violation self-checks |
| Positive controls | **Tested** | **5 sabotages, each seen RED**, each restored by byte copy and `cmp` |
| Android dev debug build | **Tested** | `app-dev-debug.apk`, 243,844,757 bytes; `MobileHomePage`, `dashboard-home-page`, `dashboard-see-full-pnl` and `mobileReportsBranch` all present in `kernel_blob.bin` |
| Windows release build | **Tested** | rebuilt after the shared-label change; `Both properties (consolidated)` present in `data/app.so` |
| Secret scan — tree, git history, built artefacts | **Tested** | clean, the scanner's own controls passing |
| Schema / migrations / server | **Unchanged** | `git diff` over `supabase/` and `lib/data/local/` is empty; schema v21, ledger 101 |
| **Physical Android device** | **Not tested** | PENDING before Phase 6 closes (D-230, §R.2) — *superseded 2026-09-25: Galaxy A06 automated PASS and §S.3 20/20 PASS; §R.2 reconciled* |
| Live backend | **Not exercised** | Slice 7 adds no remote call |

### The five positive controls, each seen RED and restored byte-identically

| Control | Result |
|---|---|
| the Gross/GST pair back to a `Row` | **1 RED** — the raised-font-scale layout test |
| *See full P&L* pointed at branch 0 | **2 RED** — the navigation test and the surface guard |
| the freshness line replaced by a fixed sentence | **1 RED** — the server-newer test |
| a movement worded by the page instead of by `dashboardMoneyMovement` | **1 RED** — the comparison test |
| `departmentSpending` rendered on the phone | **1 RED** — the D-260 guard |

### What rendering and the guard found (D-275, D-276)

**A real layout defect.** At 360dp with the system font scale at 1.6, the Gross Sales /
GST pair overflowed its card by **56 pixels**. `_Secondary` was a `Wrap` whose comment
already promised the pair would flow onto a second line — but each pair was a `Row` inside
it, and `RenderWrap` gives a child a **bounded** main-axis constraint, so a `Row` cannot
flow. The pair is a `Wrap` of its own now: the label goes on one line and the figure on the
next, whole, because the figure is the half that may never be shortened (D-269). The
D-123 and D-273 family, a third time.

**A guard that stopped at one file.** Slice 6 bound most of its surface rules to
`overview_page.dart`, so every calculation, mutation, Owner Accounts, export, clock,
trend-gap and ranked-family rule would have stopped short of the new phone surface. The
guard iterates both surfaces now, and navigation is narrowed rather than forbidden: the
Overview has no `goBranch(`, the phone has exactly one, and a further guard parses the
router to prove the named constant is the branch Reports actually occupies.

**One sentence written three times.** *Both properties (consolidated)* was a literal in the
Overview's chip and twice more on the phone. It is `dashboardConsolidatedScopeLabel` now —
the drift D-119 and D-131 each record, caught before it drifted.

**A smoke assertion that outlived what it described.** `routing_smoke_test.dart` proved
Home was still underneath the quick-add sheet by finding the **placeholder's** caption.
With the real dashboard on that branch it failed, for the right reason, and now names the
page instead.

### Carried forward, unchanged

* **A physical Android device pass** for the Home dashboard, before Phase 6 closes (D-230).
* Phase 8: the `may_read_expense` per-row reporting cost and the `org_id`-leading local
  expense index (D-223).
* The production 50:50 ownership start date remains a project-lead decision.

## Next exact task

*Superseded — Slice 8 is complete. The current record is* **Phase 6 Slice 8** *below.*

---

## Phase 6 Slice 8 — Windows Analytics sections: **COMPLETE** (2026-09-23)

Starting HEAD `e9435bd`; implementation commit `a813220`. Decisions **D-277 … D-280**; `ARCHITECTURE.md` §47. **No schema
change, no migration, no Supabase or server change, no new dependency.** Local Drift schema
stays **v21**; the migration ledger stays at **101** versions.

### What shipped

The desktop **Analytics** destination is now a workspace with four sections behind one
segmented selector (the Transactions pattern, D-120):

| Section | What it is | Period model |
|---|---|---|
| Profit & Loss | the existing Phase 5 `ProfitAndLossPage`, embedded once, unchanged | P&L presets (whole month / whole FY, D-225) |
| Revenue Analysis | ruled Gross / GST / Net summary with comparisons; Net Sales trend at the planner's grain; revenue mix as composed ranked rows | dashboard, to date (D-251, D-252) |
| Expense & Department Analysis | ruled Operating Expenses with comparison; **monthly** expense trend or a statement of why there is none; top categories with the domain's exact Others; department spending | dashboard, to date |
| Business Comparison | ruled table per property and combined — Net Sales, Expenses, Operating Profit / Loss (in words), Margin — in id order, neutral ink; grouped chart secondary; consolidated scope only | dashboard, to date |

| File | |
|---|---|
| `lib/features/analytics/presentation/analytics_page.dart` | the page, the selector and the workspace; the one `dashboardPresentation` check |
| `analytics_navigation.dart` | `AnalyticsSection` with its `periodModel`; the section provider keyed on authority; `AnalyticsDrillIntent` for Slice 9 |
| `analytics_presentation.dart` · `analytics_widgets.dart` | the sections' own wording; the ruled summary |
| `revenue_analysis.dart` · `expense_analysis.dart` · `business_comparison.dart` | the three sections — they arrange, and compute nothing |
| `lib/features/dashboard/presentation/dashboard_widgets.dart` | the Overview's building blocks, moved so both surfaces use one copy (D-279) |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | clean, 356 files, 0 changed |
| `flutter analyze` | **Tested** | **No issues found** |
| Host suite | **Tested** | **2,554 passed** (2,486 + 38 workspace + 29 analytics guard + 1 dashboard guard) |
| Analytics workspace, real provider chain | **Tested** | 38 tests — the brief's 1 … 38, at 1366×768, 1024×700 and 1920×1080 |
| Analytics surface guard | **Tested** | 29 tests (39 … 44 and the section rules), 12 of them planted-violation self-checks |
| Overview after the building-block move | **Tested** | its widget suite passes unchanged |
| Positive controls | **Tested** | **7 sabotages, each seen RED**, each restored by byte copy and `cmp` |
| Windows release build | **Tested** | `flutter build windows --release` with `config/dev.json`; the section names and `analytics-workspace` present in `data/app.so` |
| Secret scan — tree, git history, built artefacts | **Tested** | clean |
| Schema / migrations / server | **Unchanged** | nothing under `supabase/` or `lib/data/local/` touched |
| Real `krishna_mis.exe` acceptance of the workspace | **Not tested** | no device phase for Analytics yet; belongs to the Phase 6 acceptance slice (Slice 10) |
| Physical Android device (Home dashboard) | **Not tested** | still PENDING for Slice 10 (D-230, §R.2) — not affected by this Windows slice — *superseded 2026-09-25: done in Slice 10* |

### The seven positive controls, each seen RED and restored byte-identically

| Control | Result |
|---|---|
| Net Sales calculated in the Revenue widget (`grossSales - gst`) | **2 RED** — the guard's arithmetic and canonical-sum rules |
| Business Comparison allowed in a single-property scope | **1 RED** — test 26 |
| a daily Expense trend | **2 RED** — the guard and test 20/21 |
| Others recomputed in the presentation | **2 RED** — the guard's arithmetic and Top-N rules |
| an unavailable previous period shown as ₹0 | **1 RED** — test 18 |
| "winner" wording on the comparison | **2 RED** — the guard and test 30 |
| a chart imported by the workspace page (not a permitted section) | **1 RED** — the narrowed chart guard |

### What building it found (D-279, D-280)

**A fixture described a row the database cannot hold.** The Overview suite books a Water cost
to a kitchen department Water does not live under — impossible on the server (D-040). The
embedded P&L keys category rows on that guarantee, so the impossible row produced *Duplicate
keys found*. The product is right; the analytics fixture now gives the kitchen its own section
and categories. The Overview fixture is left alone (D-127).

**A test that could pass by finding nothing.** The first "exact Others" assertion was
conditional and the fixture had no Others to check. It is now unconditional over six lines.

**Three guards narrowed deliberately, not bypassed:** the dashboard guard's scope-options rule
follows the scope bar into the shared file; the chart-layer guard admits the three analytics
section files (and only those) with a complement that each really draws; the P&L guard and the
routing smoke tests now expect the Analytics branch to be the workspace, with the P&L inside it.
The guard token lists moved to `test/support/surface_guard_tokens.dart` so the dashboard and
analytics guards enforce one set of rules.

### Flagged for the project lead (D-277, D-278)

1. **The Overview and the analysis sections share one period selection.** Choosing a period in
   Revenue Analysis also changes the Overview. That is what "no second read of a still-valid
   result" costs. A separate workspace period is possible and is a decision.
2. **No percentage share per category.** No prepared share exists, and rounded per-line shares
   would not add to 100.00% on screen (the D-264 problem). The rows show exact rupees and
   proportion as geometry.
3. **No per-category period comparison.** Not prepared by the domain; it would be new domain
   arithmetic.

### Carried forward, unchanged

* **A physical Android device pass** for the Home dashboard, in Slice 10 (D-230). Not marked
  complete.
* Real-executable acceptance of the Analytics workspace, in Slice 10.
* Phase 8: the `may_read_expense` per-row reporting cost and the `org_id`-leading local expense
  index (D-223).
* The production 50:50 ownership start date remains a project-lead decision.

## Next exact task

*Superseded — Slice 9 is complete. The current record is* **Phase 6 Slice 9** *below.*

---

## Phase 6 Slice 9 — Drill-down integration: **COMPLETE** (2026-09-23)

Starting HEAD `abe4392`; implementation commit `b8eeb1b`. Decisions **D-280 (closed) … D-285**; `ARCHITECTURE.md` §48. **No schema
change, no migration, no Supabase or server change, no financial-calculation change, no new
dependency.** Local Drift schema stays **v21**; the migration ledger stays at **101**.

### First, the D-280 fixture correction

The Overview harness no longer books a kitchen cost to a section and category that live under
another department. The kitchen has its own section and four categories. Totals and test intent
are preserved, and test 18's Others assertion is now unconditional. This was test data only, and
the Overview and dashboard-guard suites re-ran green (72).

### What shipped

| | |
|---|---|
| `dashboard_drill.dart` | the one shared adapter: `DashboardDrillTargets` (targets from canonical ids and resolved ranges), `openDashboardTarget`, the Windows `dashboardDrillProvider` |
| `dashboard_drill_view.dart` | the Windows pane: back, range, breadcrumb, level list, immutable document — all Phase 5 widgets |
| `pnl_drilldown_providers.dart` | `PnlDrillOrigin`, `PnlDrillAnchor.dashboard`, `PnlRevenueCategoriesAt`, `pnlDashboardDrillReportProvider`, the dashboard branch of the level provider (D-282) |
| `pnl_drilldown_view.dart`, `mobile_pnl_drilldown_pages.dart` | a `reportLabel` and an `onRefresh`, defaulting to Phase 5's own |
| charts | `onActivated` and the Open action — opening is not selecting (D-284) |
| surfaces | the Overview, the three analysis sections and the Android Home call the adapter; the Slice 8 `AnalyticsDrillIntent` types are retired into it |

### Navigation, as approved

| Figure | Opens |
|---|---|
| Net Sales · a Net Sales trend point | revenue categories, over the period or the exact bucket |
| Operating Expenses · a monthly expense point | departments |
| revenue mix / category row | that category's documents |
| top expense category | its Department + Section + Category documents |
| department row | that department's sections |
| Operating Profit · Operating Margin · Gross/GST · a profit trend point | the existing P&L, as an explicit Custom period (D-283) |
| a property (Overview, Home, Business Comparison) | that property's P&L for the same period |
| See full P&L (Android) | Reports, unchanged |
| Others | nothing |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | 360 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Host suite | **Tested** | **2,601 passed** (2,554 + 35 drill-down + 12 guard) |
| Slice 9 drill-down suite | **Tested** | 35 tests through both real routers: proofs 1–34, plus Gross/GST, the expense headline and monthly point, and Android Operating Profit |
| Slice 9 guard | **Tested** | 12 tests, 5 of them planted-violation self-checks |
| Existing Phase 5 drill-down, P&L and dashboard suites | **Tested** | green inside the full run, unmodified except the retired Slice 8 intent test (rewritten to the adapter) |
| Positive controls | **Tested** | 6 sabotages, each seen RED and restored byte-identical (`cmp`) |
| Windows release build | **Tested** | `flutter build windows --release` with `config/dev.json`; the drill-down pane and adapter present in `data/app.so` |
| Android dev debug build | **Tested** | `app-dev-debug.apk`, 243,895,929 bytes |
| Secret scan — tree, git history, built artefacts | **Tested** | clean |
| Schema / migrations / server | **Unchanged** | nothing under `supabase/` or `lib/data/local/` touched |
| Real-device and real-executable acceptance of drill-down | **Not tested** | Slice 10 |

### The six positive controls

| Control | Result |
|---|---|
| the clicked period rebuilt from the device's "today" instead of passed | **13 RED** (incl. the guard) |
| a display name ("Restaurant") where the category id belongs | **7 RED** |
| the destination's viewer and authority checks removed | **2 RED** (12, 22). 21 and 23 stayed green because the Slice 7 cache adapter refuses independently (D-285) |
| the ledger's `RevenueActions` composed onto the report detail | **3 RED** (27 and two guard rules) |
| the D-239 re-fetch removed from the Windows pane | **1 RED** (29) |
| a second document query planted in the adapter | **2 RED** (guard) |

### Flagged for the project lead

**A hand-off to the P&L replaces the P&L's current selection** with the Custom range it was
opened for (D-283). The presets do not change, and the P&L does not follow the dashboard
afterwards. Keeping the previous selection would need a transient second P&L selection, which is
a decision.

### Carried forward, unchanged

* Real-executable and physical-device acceptance of the dashboard and drill-down, in Slice 10
  (D-230, checklist §R.2).
* Phase 8: the `may_read_expense` per-row reporting cost and the `org_id`-leading local expense
  index (D-223).
* The production 50:50 ownership start date remains a project-lead decision.

## Next exact task

*Superseded — Slice 10 is under way. The current record is* **Phase 6 Slice 10** *below.*

---

## Phase 6 Slice 10 — Full acceptance: **CLOSED** (2026-09-25)

*The record below was written on 2026-09-24, when the A06 phases were still outstanding.
The closure record is at the end of this section.*

Decisions **D-283 (final)**, **D-286**, **D-287**; `ARCHITECTURE.md` §49; `RELEASE_CHECKLIST.md`
§S. **No schema change, no migration, no Supabase or server change.** Local Drift schema stays
**v21**; the migration ledger stays at **101**.

### The one product defect, and the correction the project lead required (D-286)

At a large system font on a phone, amounts overflowed or were drawn shrunk. The first
Slice 10 fix shrank them with `FittedBox`, and so did five places shipped earlier. The
project lead ruled that money must never shrink to fit.

* Proven RED: the guard found the mechanism in 8 files, and the phone headline was drawn at
  0.238× at 320 dp and 2.0× text.
* Fixed with one reflow primitive, `FigureReflow`. A figure moves to its own full-width line
  at full size, and the row grows taller. Ranked names are no longer cut short.
* The one case no reflow can fit — the 26 px headline at 2.0× on 320 and 360 dp — breaks
  only after a comma between digit groups, at full size. This is the project lead's ruling.
* Layout tests now measure real Roboto glyphs. The test framework's default font draws every
  glyph a full em wide.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format` · `flutter analyze` | **Tested** | clean · **No issues found** |
| Host suite | **Tested** | **2,646 passed** |
| Dashboard / chart / analytics / P&L layout suites | **Tested** | 486 passed together |
| Money layout at 320/360/411 dp × 1.0/1.6/2.0, and at 1366 / narrower / 1920 | **Tested** | every amount unshrunk, whole, on screen; [ + ] cleared |
| Positive controls | **Tested** | break removed → RED; reflow disabled → 16 RED; restored by `cmp` |
| `p6-windows-dashboard`, real exe | **Tested** | PASS after D-286 (2:08). An earlier run failed, and its error was masked by a DNS failure in its `finally` sweep; the harness no longer masks (D-287) |
| `p6-windows-authority`, real exe | **Tested** | PASS (3:11), host steps applied and restored |
| `p6-android-dashboard`, `p6-android-authority`, emulator | **Tested** (emulator, before D-286) | PASS; authority run 1 stalled with no known cause (D-287) |
| Physical Galaxy A06, automated phases | **Tested** | 2026-09-25, USB serial `R9ZY50M3GVX`, Android 16 / API 36: `p6-android-dashboard` **PASS**, `p6-android-authority` **PASS**, identity unchanged before and after each (D-288) |
| Backend baseline after the A06 phases | **Tested** | identical to the pre-run capture; 6 sales and 14 expenses created and all voided |
| Clean dev APK on the A06 | **Tested** | `config/dev.json` only; 0 of 6 identity passwords in 558 entries; scanner clean; installed byte-identical |
| D-286 layout suites, re-run after the device phases | **Tested** | 312 passed |
| Physical Galaxy A06, manual checklist §S.3 | **Not tested** | awaiting the project lead |
| Live suites, `--concurrency=1` | **Tested** | **106 passed**, serial |
| Performance, Windows | **Tested** | worst steady state 163 ms (D-266 had 168 ms) |
| Performance, Android | **Not tested** | the emulator was shut down for the A06 — *superseded: re-measured on the current engine at Slice 11, worst warm 47 ms (D-289)* |
| Windows release · Android dev APK | **Tested** | clean builds with `config/dev.json` only |
| Secret scan — tree, history, artefacts | **Tested** | clean, after the acceptance intermediates were removed |
| Backend baseline | **Tested** | 0 open acceptance revenue or expenses (61 open expenses, all pre-existing); 0 owner movements; 0 settings; 0 closed periods; 7 grant rows (5 active); 80 role capabilities, hash `bd3b6b2b…`; 4 roles; 0 stranded objects; ledger 101; dead helper absent |

The grants hash differs from the Slice 11 capture only because the live parity suite
legitimately re-grants and re-revokes row `aa7c36ee…` (D-187). Its timestamps are not
rewritten.

### Outstanding before Slice 10 can close

1. ~~Run `p6-android-dashboard` and `p6-android-authority` on the Galaxy A06.~~ **Done
   2026-09-25, both PASS**, over USB only (D-288).
2. ~~The project lead reports the 20 manual lines of §S.3.~~ **Done 2026-09-25: 20/20
   PASS.**

### Slice 10 closure record (2026-09-25)

| Gate | Status | Evidence |
|---|---|---|
| Galaxy A06 automated phases | **Tested** | `p6-android-dashboard` **PASS**, `p6-android-authority` **PASS**. SM-A066B, USB serial `R9ZY50M3GVX`, Android 16 / API 36; identity unchanged before and after each run |
| Galaxy A06 manual §S.3 | **Tested — manual, 20/20 PASS** | Performed and reported by the project lead, 25 Sep 2026, on the clean dev build |
| Manual-acceptance fixtures | **Tested** | 9 sales and 5 expenses (`S10-MANUAL-FIXTURE`) created through the RPCs as the Owner. The server's figures matched a hand calculation to the paisa. All 14 voided afterwards; none deleted (D-006) |
| D-286 layout test tightened | **Tested** | A broken figure must have been given its whole FigureReflow line, measured. The 90% sabotage turned 8 RED, where the old 60% proxy let every screen suite pass. Restored, 314 GREEN. Committed `310a2d0` |
| `dart format` / `flutter analyze` | **Tested** | 364 files unchanged / no issues |
| Host suite | **Tested** | **2,648 passed** |
| Live suites, `--concurrency=1` | **Tested** | **106 passed**, 0 skipped: reporting 13, parity 29, owner accounts 31, completeness audit 8, settlement 20, drill-down 5 |
| Windows release build | **Tested** | `config/dev.json` only. `lib/` is unchanged since `4f03b7b`, so `app.so` is current |
| Android dev APK | **Tested** | `config/dev.json` only; rebuilds byte-identical, SHA-256 `6f334b6f…9b45`, the same file installed on the phone |
| Acceptance intermediates removed | **Tested** | 546 files carried identity material: stale prod/staging debug APKs and their kernels, plus 540 cached test kernels. All removed; a re-scan of 4,843 files finds 0 |
| Secret scan — tree, history, artefacts | **Tested** | clean, self-checks passing |
| Backend baseline | **Tested** | See the table below |

**Backend at close:**

| | |
|---|---|
| Open revenue | 0 |
| Open expenses | 61, the same ID set as before the fixtures (hash `15906076…`) |
| Open owner movements | 0 |
| Settlement start date rows | 0 — the live suite's 2026-05-01 fixture removed with the committed administrator script |
| Closed periods | 0 |
| Grant rows | 7, 5 active; grant-shape hash `0cde81c5…` unchanged |
| Roles | 4 |
| Role capabilities | 80, hash `c1b4870f…` unchanged |
| Tax rules | 4 live; 0 bands, subtypes or statuses |
| Migration ledger | 101, latest `20260912100000` |
| Dead helper | absent |
| Storage | 265 objects to 265 metadata rows, 0 stranded |

**Not repeated, and why.** Real-executable Windows acceptance, emulator acceptance and the
performance measurement were run on 24 September against `4f03b7b`. Nothing under `lib/`
has changed since then: the only later commits are documentation and one test helper.
They are reported with their 24 September provenance. The host performance tests ran
again inside the 2,648.

**Phase 6 Slice 10 is CLOSED.** Slice 11 (closure) is not started.

---

# PHASE 6 — DASHBOARD & ANALYTICS: COMPLETE AND CLOSED

Closed on 2026-09-25 at Slice 11 (D-289). Master Spec **v1.2**, unchanged. Local Drift schema
**v21**; migration ledger **101**. Decisions **D-251 … D-289**. **D-262 was never allocated**,
and that gap is recorded, not filled.

Slice 11 is documentation and closure gates only: no product code, schema, migration or
server change. **Phase 7 — Export & Printing: not started.**

## 1 · What Phase 6 delivered

| Surface | Contents |
|---|---|
| **Windows Overview** (`/overview`) | Scope, the Phase 6 to-date period selector (D-251, D-252) and freshness. Net Sales (with Gross Sales and GST), Operating Expenses, Operating Profit/Loss and Operating Margin, each with its comparison. Net Sales trend and monthly Operating Profit trend. Property comparison (consolidated only), revenue mix, top expense categories and department spending |
| **Android Home** | Scope, period and freshness; the four headline figures with comparisons; Net Sales trend; top expense categories; property comparison when consolidated; *See full P&L* to the Reports branch. Revenue mix, department spending and the profit trend stay on Windows (D-260) |
| **Windows Analytics** (`/analytics`) | The existing Phase 5 Profit & Loss, on its own whole-month and whole-year presets; Revenue Analysis; Expense & Department Analysis; Business Comparison, on the dashboard's to-date periods (D-277, D-278) |
| **Drill-down** | From the dashboard and analytics into the Phase 5 read-only hierarchy, through one shared adapter. It passes canonical IDs and exact resolved ranges and never a figure. Document detail is immutable and online-only, fetched again on every open, and refused when stale. Authority is checked again at the destination (D-282, D-285). Figures with no transactions hand off to the P&L as an exact Custom period (D-283 final) |
| **Foundation** | `domain/finance` rules for periods, comparisons, trend grain, ranking, Top N and the property split. `DashboardEngine`: one plan, one lock span, one freshness claim. Authority-keyed providers. The fl_chart presentation layer, and the `FigureReflow` / `MoneyText` money layout |

## 2 · Slices

| # | Slice | Commit(s) | State |
|---|---|---|---|
| 1 | Governance | `7c91d0c` | CLOSED |
| 2 | Exact comparison domain rules | `28071b2`, `ac3803f` | CLOSED |
| 3 | Dashboard engine and performance gate | `1455eae` | CLOSED |
| 4 | Authority and providers | `fcd464b` | CLOSED |
| 5 | Chart foundation | `8e0699c` | CLOSED |
| 6 | Windows Overview | `00a4017`, `3f39ab5` | CLOSED |
| 7 | Android Home | `fc78d09`, `e9435bd` | CLOSED |
| 8 | Windows Analytics | `a813220`, `abe4392` | CLOSED |
| 9 | Drill-down integration | `b8eeb1b`, `716142e` | CLOSED |
| 10 | Full acceptance | `4f03b7b`, `8f87a9c`, `c3fd218`, `310a2d0`, `b6ebe8e` | CLOSED |
| 11 | Closure | this record | CLOSED |

## 3 · Decisions

D-289 records the final disposition of every Phase 6 decision:
- every flagged point was resolved (D-264, D-263, D-256 closed, D-281, D-280 closed, D-283 final);
- **D-286 is final**, including the clarification and the real-line test;
- **D-287 and D-288 remain acceptance-infrastructure observations**, not product defects.

## 4 · Authority and financial invariants, verified in code at closure

**Authority**
- Every dashboard and analytics decision goes through `PnlAuthority`:
  - a property needs `reports.view` ∩ `revenue.view` ∩ `expense.view.all`;
  - consolidated needs all three unscoped;
  - `expense.view.own` never qualifies;
  - no role name is read;
  - Owner Accounts capabilities grant nothing here.
- The authority key is the dashboard identity, which is how isolation holds for a user
  switch, a same-user revocation, the loss of a property, the loss of consolidated
  authority, and a stale in-flight publication. This is proven by the provider,
  drill-down and authority phases.

**Figures**
- There is no second P&L: nothing in Phase 6 calls `Pnl.compute`, and no widget does
  money arithmetic or infers GST.
- An unavailable figure is a type, never ₹0.
- Charts derive coordinates one way, from money. The only paise division is a bar-length
  fraction.

**Layout**
- No money is ellipsised or shrunk. All seven ellipsis sites are labels.

## 5 · Evidence

| Gate | Evidence |
|---|---|
| Windows, real `krishna_mis.exe` | `p6-windows-dashboard` **PASS**; `p6-windows-authority` **PASS**; at 1366×768, a narrower window and 1920×1080 |
| Android emulator | `p6-android-dashboard` **PASS**; `p6-android-authority` **PASS** (the cold-boot run, D-287) |
| Galaxy A06, automated | both phases **PASS** (SM-A066B, Android 16 / API 36, USB serial `R9ZY50M3GVX`; D-288) |
| Galaxy A06, manual §S.3 | **20/20 PASS**, reported by the project lead on 2026-09-25, including the largest system font and [ + ] clearance |
| Offline and reconnect | the dashboard stays readable, is never ₹0 and says it is offline; detail needs a connection; a refresh on reconnect succeeds (automated phases; §S.3 items 15–17) |
| Performance, Android (current engine) | worst warm **47 ms** (month to date, 37 reports), with counts identical to D-266. Not a material regression (D-289) |
| Performance, Windows | worst steady state **163 ms** (Slice 10), against D-266's 168 ms |
| Dependencies | only `fl_chart 1.2.0`, pinned, bringing `equatable` |
| Schema and server | no Phase 6 change under `supabase/` or `lib/data/local/`; v21; ledger 101 |

## 6 · Carry-forwards

Classified in D-289:
- **A — Phase 7:** export, PDF, printing, and the `reports.export` / `reports.print` evaluators.
- **B — Phase 8:** reporting performance and hardening.
- **C — Phase 9:** production configuration and distribution.
- **D — Product / business:** the production 50:50 date; the D-247 forensic database; the
  Administration placeholder copy.
- **E — Future analytics.**
- **F — Owner Accounts extension.**

## 7 · Open defects at closure

**None.**

## 8 · Closure gates (Slice 11, 2026-09-25)

Run one at a time on the closure content (`RELEASE_CHECKLIST.md` §T):

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | clean, 364 files |
| `flutter analyze` | no issues |
| Full host suite | **2,648 passed** |
| Live suites, `--concurrency=1` | **106 passed**, 0 skipped: reporting 13, parity 29, owner accounts 31, completeness audit 8, settlement 20, drill-down 5 |
| Settlement start date cleanup | the disposable 2026-05-01 row removed with the committed administrator script; 0 rows |
| Android performance, current engine | two launches on `Pixel_8` (`sdk_gphone16k_x86_64`, Android 17 / API 37): worst warm **47 ms**, counts identical to D-266 (D-289) |
| Windows release build | `config/dev.json` only; built |
| Android dev APK | `config/dev.json` only; SHA-256 `6f334b6f…9b45`, byte-identical to the build installed on the A06 |
| Identity-bearing intermediates | 0 among the 4,892 build and cache files, so nothing to remove |
| Secret scan — tree, history, artefacts | clean, self-checks passing |
| Backend baseline | see the table below |
| Schema and migration provenance | Drift v21; live ledger 101, latest `20260912100000`, the same as the latest committed file; no Phase 6 change under `supabase/` or `lib/data/local/`; no `lib/` change since `4f03b7b` |
| Working tree | clean after the closure commit |

**Backend at close** (`krishna-mis-dev`, read at 14:15 UTC):

| | |
|---|---|
| Open revenue | 0 |
| Open expenses | 61, the same pre-existing documents (ID hash `15906076…`) |
| Open owner movements | 0 |
| Settlement start date rows | 0 |
| Closed periods | 0 |
| Grant rows | 7, 5 active; grant-shape hash `0cde81c5…` |
| Roles | 4 (accountant, data_entry, manager, owner); no temporary role |
| Role capabilities | 80, hash `c1b4870f…`; no temporary capability grant |
| Tax rules | 4 live; 0 bands, subtypes or statuses |
| Storage | 265 objects to 265 metadata rows, 0 stranded |
| Dead helper | absent |
| Migration ledger | 101 |

**PHASE 6 — DASHBOARD & ANALYTICS IS FORMALLY CLOSED. Phase 7 is not started.**

---

# PHASE 7 — EXPORT, PDF & PRINTING: STARTED (2026-09-25)

Phase 6 closed at `b35611a`.

**How Phase 7 was scoped.** A read-only audit of the binding spec (§2, §5.3, §10, §16, §19,
§21.3, §28, §33), the release checklist and the shipped code produced eight questions. The
project lead ruled on all eight. His rulings are recorded as **D-290 … D-297**. **D-298**
records the dependency decision, **D-299** the export contract and **D-300** a
documentation correction.

**The principle:** Phase 7 **renders results the app has already approved**. It is not
another reporting or accounting engine.

**The contract** is `ARCHITECTURE.md` §51. In short:
- **Reporting data:** no schema change, no migration, no reporting RPC, no second cache,
  and no server change. Drift stays **v21** and the ledger stays **101**.
- **Export and print authority is decided on the device, by design** (D-291). The server's
  reporting authorization remains the confidentiality boundary.
- **Transaction-list export is deferred** (D-296).
- **No Owner Accounts export** in this phase.

## Scope, as ruled

| | Windows | Android |
|---|---|---|
| Profit & Loss | PDF · Excel · **Print** | **PDF → system share sheet** |
| Revenue Analysis | PDF · Excel | — |
| Expense & Department Analysis | PDF · Excel | — |
| Business Comparison (consolidated only) | PDF · Excel | — |

The Windows **Reports** placeholder becomes the **Export Centre** (D-297).

**Rules that apply to every export:**
- **Authority:** export needs view authority **and** `reports.export` for the exact scope;
  print needs view authority **and** `reports.print`. A consolidated scope needs the action
  capability for every property it includes.
- **Role bundles are unchanged** (D-292). A Manager can read reports but is not offered
  Export or Print.
- **Offline:** export works with no connection whenever the canonical report is complete
  locally and the user is authorised. It never triggers a sync. Missing data never becomes
  ₹0.

## The approved slice plan

| # | Slice | State |
|---|---|---|
| 1 | Governance / export contracts | **COMPLETE** |
| 2 | Export + print authorisation | **COMPLETE** |
| 3 | Canonical export document models | **COMPLETE** |
| 4 | XLSX foundation (internal OpenXML writer on `archive`) | **COMPLETE** |
| 5 | PDF foundation (`pdf` 3.13.1, bundled Noto Sans) | **COMPLETE** |
| 6 | Windows Reports → Export Centre, Save As | **COMPLETE** |
| 7 | Windows printing (`printing` 5.15.1, native dialog) | **COMPLETE** |
| 8 | Android P&L PDF share | **COMPLETE** |
| 9 | Windows analysis-section exports | **COMPLETE** |
| 10 | Full acceptance | **COMPLETE** (2026-09-28; D-308, D-309) |
| 11 | Closure | **CLOSED** (2026-09-28, D-311) |

Transaction-list export is outside this plan (D-296).

## Phase 7 Slice 1 — governance: **COMPLETE**

**What changed.** Documentation only. There is **no code, dependency, schema, migration or
server change**; `pubspec.yaml` and `pubspec.lock` are untouched. Package pinning happens in
the slice that first uses each package (D-298).

| Document | Change |
|---|---|
| `DECISIONS.md` | D-290 … D-300 |
| `ARCHITECTURE.md` | new §51, the export, PDF and printing contract; §2's Excel and PDF rows updated; §50.2's export bullet marked as superseded in part by D-291 |
| `DATABASE_SCHEMA.md` | the §2 capability catalogue restated from the shipped codes (`reports.*`, `masters.*`, `users.manage`, `roles.manage`, plus every capability added after Phase 0), with the correction recorded (D-300); §11's exemption note updated; a *Phase 7* section added |
| `RELEASE_CHECKLIST.md` | new §U, the Phase 7 gates |
| `SHOYEB_MASTER_SPEC.md` | **unchanged**, and the version stays 1.2. Phase 7 renders §16 as already written; no financial semantics move |

**One thing the documents do not claim.** `reports.export` and `reports.print` stay on
D-139's exemption list. The comments in the applied migration `20260911131228` still read
"Phase 7 · no export path exists". That migration is not rewritten (A0, D-056). D-291
records why the exemption now stays permanently: these two capabilities are evaluated on the
client by design, and nothing on the server evaluates them.

### Verified

These gates ran in a **Linux cloud container**. Flutter **3.44.9** / Dart **3.12.2** was
installed for this session, the same toolchain the project pins. Earlier phases ran their
host suite on the project lead's **Windows** machine, and that difference matters below.

| Item | Status | Evidence |
|---|---|---|
| `flutter pub get` | **Tested** | resolves with `pubspec.lock` unchanged |
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | 364 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Doc and parity invariants (`migration_audit_test`, `chart_guard_test`, `backend_schema_parity_test`) | **Tested** | **68 passed**, including D-137's ARCHITECTURE phrase and the D-139 exemption machinery |
| Full host suite, this container | **Partially tested** | **2,405 passed, 1 skipped, 9 failed**. See the next paragraph |
| Same suite, untouched `b35611a` (worktree), same container | **Tested** | **identical**: 2,405 / 1 / 9, and the same 9 tests |
| Secret scan, tree and git history | **Tested** | clean, exit 0, scanner self-test controls passing |
| Schema, migrations, server | **Unchanged** | nothing under `supabase/`, `lib/` or `test/` touched; Drift v21; ledger 101 |
| Live suites, Windows, Android | **Not run** | Slice 1 changes no code |

**The 9 failures are caused by the Linux host, not by Slice 1.** They reproduce identically
on the untouched Phase 6 closure commit in the same container. The Phase 6 total of 2,648
was measured on Windows, where none of them occur.

- **Six test files fail in `setUpAll`** (`figure_reflow`, `analytics_workspace`,
  `dashboard_mobile_home`, `dashboard_overview`, `pnl_mobile_ui`, `pnl_drilldown_ui`), so
  their tests never run.
  - The cause: `test/support/money_layout.dart` opens
    `material_fonts/roboto-regular.ttf` in lowercase, but the SDK ships
    `Roboto-Regular.ttf`.
  - Windows' case-insensitive filesystem hides this; Linux does not.
  - This accounts for the **233** tests that did not run (2,648 − 2,415).
- **Three tests assume the host is Windows or Android.** They are the D-077 production
  picker-wiring tests (`attachment_source_wiring_test`, and two in
  `revenue_attachment_ui_test`). `attachmentSourceFor('linux')` correctly resolves to
  `UnavailableAttachmentSource`.

Both are **test portability** issues, and neither is a product defect. They are recorded
here and **not fixed inside a governance slice** (D-127). The suite stays authoritative on
the Windows host, where it has always been run.

### Next

**Slice 2 — export and print authorisation (D-291, D-292), not started.** It will add a pure
`ExportAuthority` in `domain/finance`, with an allow and deny matrix, the
consolidated-coverage rule, and a guard against role names. It needs no dependency and no
server change.

## Cloud/CI portability correction (D-301): **DONE**

This is **test infrastructure, not a Phase 7 feature**. It fixes the two Linux-only failures
recorded under Slice 1, and changes no product behaviour.

- **The font helper** now finds `Roboto-Regular.ttf` regardless of filename case.
- **The three D-077 picker-wiring tests** no longer depend on the host being Windows or
  Android. Instead:
  - the provider is pinned structurally to `attachmentSourceFor(Platform.operatingSystem)`;
  - the revenue surfaces are tested against production's own resolution for an explicitly
    named shipped platform.

| Item | Status | Evidence |
|---|---|---|
| Red first | **Tested** | the eight affected files: 18 passed, 9 failed |
| Green after | **Tested** | the same files: **262 passed** |
| Full host suite, Linux | **Tested** | **2,649 passed, 1 skipped** (the Windows-only DPAPI round trip), **0 failed**. Suite total **2,650** |
| Positive controls | **Tested** | provider body degraded → structural test red; Android resolution degraded → both Android surface tests red. Each restored and checked with `cmp` |
| Windows behaviour | **Unchanged** | same font files; the runtime wiring test still requires a real picker on a Windows host |

`tool/cloud/install_flutter.sh` installs the pinned Flutter 3.44.9 on a Linux host. It is
idempotent and never changes the version. **To persist the toolchain** across cloud
sessions, add `bash tool/cloud/install_flutter.sh` to the environment's setup script, with
`/opt/flutter/bin` on `PATH`.

## Phase 7 Slice 2 — export and print authorisation: **COMPLETE**

**What was added.** `lib/domain/finance/export_authority.dart`, which is pure domain code,
plus its tests. It was built as `ARCHITECTURE.md` §51.3 describes, with **no change** to the
schema, the server, dependencies or UI.

**The rule it enforces:**
- **Export** needs view authority for the exact scope **and** `reports.export` for it.
  **Print** needs view authority **and** `reports.print`.
- **View authority** is decided by delegating to `PnlAuthority`, per property, or
  consolidated. A guard forbids restating the three-capability rule here.
- **A consolidated scope** needs the action capability for **every** included property:
  unscoped, or one scoped grant per property.
- **Business Comparison** is refused for a one-property scope.
- **Order of checks:** scope shape → view → action. A person who cannot see a report is
  told that, and is never told which action capabilities they hold.
- **No role name** appears in the rule. The seeded bundles are used in tests as data only.
  Result: the Manager is refused `noActionCapability` (D-292); a Manager explicitly granted
  `reports.export` may export and still may not print.
- **Client-side only** (D-291). The file states this and claims no server enforcement, and
  a structural test holds it to that.

| Item | Status | Evidence |
|---|---|---|
| Export-authority tests | **Tested** | **32** passed |
| Finance domain suite, including the purity guard over the new file | **Tested** | **323** passed |
| Positive controls | **Tested** | `every`→`any` on the action check: 2 red. Consolidated view as the sum of scoped grants: 2 red. The view check removed: 11 red. Each restored and checked with `cmp` |
| `dart format` / `flutter analyze` | **Tested** | clean / no issues |
| Full host suite | **Not rerun** | a new, unused module; no existing boundary changed. Rerun at the model-boundary and foundation checkpoints |

The first attempt at the second control **did not apply**: `dart format` had reflowed the
line it matched. It was caught because the suite stayed green, then re-applied, and it went
red.

## Phase 7 Slice 3 — export document models: **COMPLETE**

`lib/domain/export/` holds the models and the builders, as pure domain code (D-302,
`ARCHITECTURE.md` §51.4). There are four documents, and each has one builder that requires
an `ExportPermitted`:

| Document | Built from |
|---|---|
| **Profit & Loss** | `PnlResult`. A consolidated scope gives one statement per property (`PropertyComparison`), then the total |
| **Revenue Analysis** | `PnlResult`, `PnlComparison`, the Net Sales `TrendSeries`, the revenue-mix `TopNOutcome` |
| **Expense & Department Analysis** | the same, with the **monthly** expense series and two rankings |
| **Business Comparison** | the `PropertyComparisonReady` split, plus the total |

**The rules the models keep:**
- They copy figures and derive none.
- A refusal stays a refusal: a missing comparison, a trend gap or a refused ranking is
  never shown as ₹0.
- Freshness is three separate fields.
- No model stores an id.

**Two shared-boundary changes came with this slice:**
- `ExportPermitted` is now a proof object that only `ExportAuthority.decide` can make.
- The P&L line order moved into `domain/finance` as `PnlLineOrder`; the screens delegate to
  it and behave exactly as before.

| Item | Status | Evidence |
|---|---|---|
| Builder tests | **Tested** | **32** passed: parity with the canonical objects; the §10 consolidated shape; a loss kept negative; No GST; a breakdown that does not reconcile is absent; permit mismatches (4 kinds); the three freshness statements; refusals carried; no id leaks |
| Model guard | **Tested** | **18** passed: no arithmetic, sum, clock, storage, sort or forbidden import in the directory, with 8 planted controls. Only the builders may call `PropertyComparison.of` |
| Real-code controls | **Tested** | a subtraction planted in a builder: guard red. A wrong figure copied: 5 builder tests red. Each restored and checked with `cmp` |
| Full host suite (the shared boundary changed) | **Tested** | **2,731 passed, 1 skipped** (Windows-only DPAPI), **0 failed** |
| `dart format` / `flutter analyze` | **Tested** | 372 files, 0 changed / no issues |

## Phase 7 Slice 4 — XLSX foundation: **COMPLETE**

The internal OpenXML writer and the P&L workbook (D-303, `ARCHITECTURE.md` §51.1, §51.5).
No schema, migration or server change; Drift stays **v21** and the ledger **101**.

| Added | What it does |
|---|---|
| `lib/core/export/xlsx/xlsx_writer.dart` | packages cells into a deterministic `.xlsx`: text, number, date and blank cells; no formula cell type; styles; frozen panes; auto-filters |
| `lib/core/export/workbook/pnl_workbook.dart` | the P&L as Summary, Revenue and Expenses sheets |
| `lib/core/export/export_wording.dart` | the words and file names both file formats use |
| `MoneyFormatter.decimalLiteral`, `MarginRatio.displayedFractionLiteral` | exact paise and the screen's rounded margin, as cell literals, by integer formatting |
| `pdf` 3.13.1, `printing` 5.15.1, `archive` 4.2.0 | pinned exactly; `pub get` ran once |

**What a workbook guarantees:**
- Every numeric cell is the canonical figure, to the paisa.
- There are no formulas.
- A Total row is the headline figure, never a sum of the rows above it.
- A loss is negative and is also called a loss.
- A margin that is not applicable is "N/A".
- The three freshness statements stay separate.
- No internal id appears in any byte.

| Item | Status | Evidence |
|---|---|---|
| Writer tests | **Tested** | **18** passed: part list and order; well-formed XML; literals stored verbatim; malformed literals refused; date serials; no formula; styles and number formats; frozen pane and filter; sheet-name rules; deterministic bytes; no author or time metadata |
| P&L workbook tests | **Tested** | **21** passed: every figure read back from the file and parsed to exact paise, equal to the canonical result, for one property and for the consolidated split; result words; margin cell; header and freshness; No GST; Totals are the headline; a non-reconciling breakdown is withheld; N/A margin; no trade; file names; no id in any byte; deterministic bytes |
| Literal tests | **Tested** | decimal literal and margin fraction: fixed cases plus sweeps that read the value back |
| `lib/core/export` guard | **Tested** | **20** passed, including 12 planted violations that must fail and 2 legitimate cases that must pass |
| Real-code controls | **Tested** | Total summed from its rows: guard red. Paise unpadded: 3 red. The server-newer line always shown: 1 red. A formula written into a number cell: 3 red. Each restored and checked with `cmp` |
| Chart guard (`fl_chart` still the only charting package) | **Tested** | passed |
| Full host suite (dependencies added) | **Tested** | **2,794 passed, 1 skipped** (Windows-only DPAPI), **0 failed** |
| `dart format` / `flutter analyze` | **Tested** | 379 files, 0 changed / no issues |
| Secret scan, tree and git history | **Tested** | clean |
| Opening a generated workbook in Excel | **Not tested** | a person opening the file on Windows belongs to Slice 10 acceptance. The file is checked here by reading its XML |

## Phase 7 Slice 5 — PDF foundation: **COMPLETE**

The bundled fonts and the P&L PDF (D-304, `ARCHITECTURE.md` §51.5). No schema, migration or
server change; Drift stays **v21** and the ledger **101**.

| Added | What it does |
|---|---|
| `assets/fonts/noto_sans/` | Noto Sans Regular and Bold, with the SIL Open Font License |
| `lib/core/export/pdf/pdf_fonts.dart` | takes the font bytes; refuses a font without ₹ |
| `lib/core/export/pdf/pnl_pdf.dart` | the P&L on A4 portrait pages, with a header and footer on every page and repeating table headings |
| `test/support/pdf_text.dart` | reads the printed text back through each font's `/ToUnicode` map |

| Item | Status | Evidence |
|---|---|---|
| PDF tests | **Tested** | **20** passed. Every headline figure and line on the page equals `MoneyFormatter` of the canonical result, for one property and for the consolidated split. Also: result words; No GST; Totals are the headline figures; header and footer and page *n* of *N* on every page; table headings repeat; a fifteen-digit amount printed whole; no text below 7.5 pt; no freshness claim without evidence; the server-newer line only when confirmed; a non-reconciling breakdown withheld; N/A margin; a real ₹0; compressed by default; no information dictionary; no id in any byte, compressed or not; the fonts, their licence and the asset list |
| `lib/core/export` guard | **Tested** | **27** passed, including 16 planted violations |
| Real-code controls | **Tested** | Money printed in whole rupees: 9 red. A Total summed from its rows: guard red. Heading not repeated: 1 red. Page number on page 1 only: 1 red. A document title set: 2 red. Each restored and checked with `cmp` |
| Full host suite (Slice 5 close) | **Tested** | **2,821 passed, 1 skipped** (Windows-only DPAPI), **0 failed** |
| `dart format` / `flutter analyze` | **Tested** | 383 files, 0 changed / no issues |
| Secret scan, tree and git history | **Tested** | clean |
| A person reading and printing the PDF | **Not tested** | Slice 7 (Windows print dialog) and Slice 10 acceptance |


## Phase 7 Slice 6 — Windows Reports → Export Centre, Save As: **COMPLETE**

The Windows **Reports** destination is now the Export Centre (D-297, D-305). No schema,
migration or server change; Drift stays **v21** and the ledger **101**.

| Added | What it does |
|---|---|
| `lib/features/export/export_pipeline.dart` | the report the screen holds → identity check → `ExportAuthority.decide` → complete? → document → renderer. Reads no storage, network or clock |
| `lib/features/export/export_file_save.dart` | Save As through `file_selector` `getSaveLocation`; extension added when missing; the bytes written beside the target, then renamed over it |
| `lib/features/export/export_providers.dart` | the action controller; master-graph labels; the bundled fonts read from the app bundle |
| `lib/features/export/export_centre_page.dart` | the four reports, what each would export (scope, period, freshness — no figure), and only the actions authority allows |

**What the Export Centre does and does not do:**
- It exports the report its own screen already holds: the P&L view, or the dashboard the
  Analytics sections share. The scope and period are the ones chosen there; *Open in
  Analytics* goes to them.
- It shows no figure and holds no report state (D-297).
- It never starts a synchronisation or a download. Offline, a complete report exports; an
  incomplete one shows the screen's own sentence and offers nothing.
- Authority is decided before the button appears, before the document is built, and again
  after the Save As dialog closes. Losing `reports.export` while the dialog is open writes
  nothing.
- The analysis reports' actions are wired. Their PDF and Excel layouts arrive in Slice 9.

**A latent defect found and fixed.** The P&L and dashboard screens fall back to the zone
`UTC` when a property's rules cannot be read. The bundled IANA data names it `Etc/UTC`, so
`reportInstantLabel` threw. On screen this was reachable only with unreadable rules and a
freshness claim; in an export it would have failed every file, because the generation line
is always stated. `UTC` is now resolved directly (D-305).

| Item | Status | Evidence |
|---|---|---|
| Pipeline tests | **Tested** | **12** passed: PDF and Excel identical to the foundation renderers for the same document; Manager bundle refused `noActionCapability`; action capability alone refused `noViewAuthority`; consolidated refused when one property lacks `reports.export`; another person's report refused; an incomplete report refused; fonts loaded only for a permitted PDF; the UTC fallback |
| Save As tests | **Tested** | **13** passed, writing to a real temporary folder: suggested name and format; cancel writes nothing; exact bytes; extension added, case-insensitive; a collision the dialog never asked about is refused and the existing file untouched; a confirmed name replaced whole; a failed write and a failed rename leave no partial file; dialog failure; authority lost before the write; Windows and POSIX error classification |
| Export Centre widget tests | **Tested** | **11** passed: every action for the Owner; the Manager offered none; no report for someone who reads none; an incomplete report offers nothing and no ₹0; another person's report not offered; **no synchronisation started**; Save Excel and Save PDF write the files; cancel; `reports.export` lost while Save As is open |
| Feature guard | **Tested** | **23** passed, including 12 planted violations and 2 legitimate cases |
| Real-code controls | **Tested** | re-check before write removed: 1 red. Identity check removed: 1 red. Extension collision allowed: 1 red. A refresh planted in the Export Centre: guard red. Each restored and checked with `cmp` |
| Targeted suites (app, core, domain export, surface guards, P&L and Analytics UI, doc invariants) | **Tested** | **669** passed |
| `dart format` / `flutter analyze` | **Tested** | 392 files, 0 changed / no issues |
| Secret scan, tree and git history | **Tested** | clean |
| Real Windows Save As dialog and its overwrite prompt | **Not tested** | Slice 10, on the Windows machine |

## Phase 7 Slice 7 — Windows printing: **COMPLETE**

The P&L prints through the native Windows print dialog, from the **same PDF bytes** Save
PDF writes (D-299, §51.5). No schema, migration or server change.

```
    canonical report → document model → PDF renderer → Printing.layoutPdf → Windows dialog
```

| Added | What it does |
|---|---|
| `lib/features/export/export_print.dart` | `Printing.layoutPdf` with `onLayout: (_) async => bytes` and `dynamicLayout: false`, so the dialog's page choice never re-lays the document out |
| `ExportActionController.print` | the same pipeline as Save PDF, with `ExportAction.print`; authority decided again before the bytes are handed over |
| Export Centre | a **Print** button, offered only with view authority **and** `reports.print` for the exact scope |

Print is its own capability: Save needs `reports.export`, Print needs `reports.print`, and
either may be offered without the other. The analysis reports become printable in Slice 9,
when their PDFs exist.

| Item | Status | Evidence |
|---|---|---|
| Print widget tests | **Tested** | **8** passed: the dialog receives the bytes Save PDF writes (compared without the package's random `/ID`), and the job is named after the file; export-only offers Save and not Print; print-only offers Print and not Save; the Manager bundle offered nothing; closing the dialog is a cancel; a dialog that cannot open is stated; losing consolidated authority takes Print away; `reports.print` lost while the PDF is being made prints nothing |
| Feature guard | **Tested** | **29** passed: only the print and share files import `printing`; neither may import the PDF widgets, a renderer, a workbook or a document builder; the print file hands `bytes` to `layoutPdf` unchanged; planted violations red |
| Real-code controls | **Tested** | the in-flight authority check removed: 1 red. The renderer imported into the print file: guard red. Each restored and checked with `cmp` |
| Export, app and core-export suites | **Tested** | **250** passed |
| `dart format` / `flutter analyze` / secret scan | **Tested** | clean / no issues / clean |
| The real Windows print dialog and a printed page | **Not tested** | Slice 10, on the Windows machine. This container is Linux and cannot open it |

## Phase 7 Slice 8 — Android P&L PDF share: **COMPLETE**

The phone P&L can be shared as a PDF through the system share sheet (D-293, D-306). It is
the **same PDF** Windows saves and prints: same document model, same renderer. No schema,
migration or server change; Drift stays **v21** and the ledger **101**.

```
    phone P&L on screen → identity check → view authority AND reports.export
      → document model → PDF renderer → Printing.sharePdf → system share sheet
```

| Added | What it does |
|---|---|
| `lib/features/export/export_share.dart` | `Printing.sharePdf`; the app-private cache root; removal of this app's earlier shared exports from `<cache>/share/` |
| `lib/features/export/pnl_share_action.dart` | one **Share as PDF** icon in the Android Reports header, beside Refresh; its outcome as a snackbar |
| `ExportActionController.share` | the Save/Print pipeline with `ExportAction.export`; earlier shares cleaned first; authority decided again before the sheet opens |

**What Android does and does not offer:**
- The P&L PDF only. No Android Excel, no Android printing, and no analysis export (D-293).
- Offered only when the report on screen is complete and the person holds view authority
  **and** `reports.export` for its scope. Reading the P&L is not enough: the Manager bundle
  sees no share icon.
- It shares what the screen already holds. It starts no synchronisation, so a complete
  report shares offline.
- **No storage permission.** The file goes to the app's private cache and reaches the
  chosen app through `printing`'s own FileProvider. The manifest declares no storage or
  media permission, and a test reads the manifest to prove it.
- **Cleanup.** A file cannot be deleted the moment the sheet opens: the receiving app has
  not read it yet. Every earlier export this app shared is therefore removed from
  `<cache>/share/` before the next share, and when the phone P&L is opened. Only files
  named `KrishnaImperialMIS_*.pdf` are touched.

| Item | Status | Evidence |
|---|---|---|
| Share widget tests | **Tested** | **11** passed: the share sheet receives %PDF bytes under the readable name; print-only authority, the Manager bundle, an incomplete report and another person's report offer no share; offline sharing with no synchronisation; earlier shares removed on open and before a share, other files untouched; a sheet that cannot open is stated; `reports.export` lost mid-flight shares nothing; no storage permission in the manifest; cleanup on a cache with no share folder |
| Feature guard | **Tested** | **31** passed: `path_provider` in the share file only as `getTemporaryDirectory`; no external-storage or Downloads path; the share file writes no bytes itself; planted violations red |
| P&L surface guard | **Tested** | the phone P&L's only `features/export` import is the share action; no other P&L file reaches `features/export` |
| Real-code controls | **Tested** | cleanup before share removed: 1 red. Share offered without authority: 3 red. `getExternalStorageDirectory` in the share file: guard red. Each restored and checked with `cmp` |
| Export, P&L phone/drill-down/session suites, P&L guard, app | **Tested** | export features **86**; P&L phone, session switch, drill-down UI, surface guard and app **279** |
| `dart format` / `flutter analyze` | **Tested** | 396 files, 0 changed / no issues |
| Android APK build | **Blocked** | Three attempts; each failed downloading Kotlin Gradle plugin artifacts from Maven Central with **HTTP 429 Too Many Requests** (network rate limit in this container). Not a code failure: `flutter analyze` compiles the Dart for every target. To be built on the Android build machine in Slice 10 |
| The real share sheet on a device | **Not tested** | Slice 10, on the Galaxy A06 over USB (D-288) |

## Phase 7 Slice 9 — Windows analysis exports: **COMPLETE**

Revenue Analysis, Expense & Department Analysis and Business Comparison now save as PDF and
Excel, and print, on Windows (D-290, D-307). Each is laid out from its Slice 3 document
model and computes nothing. No schema, migration or server change; Drift stays **v21**, the
ledger **101**, and `pubspec.yaml` / `pubspec.lock` are unchanged.

| Added | What it does |
|---|---|
| `lib/core/export/pdf/pdf_page.dart` | the page furniture every PDF shares: header, footer (page *n* of *N*, synchronised-as-of, generated-on-device), opening block, table style, and the one `pw.Document` (no information dictionary). The P&L PDF now uses it |
| `lib/core/export/pdf/analysis_pdf.dart` | the three analysis PDFs, A4 portrait |
| `lib/core/export/workbook/analysis_workbook.dart` | the three analysis workbooks: Summary / Trend / rankings, and one Comparison sheet |
| `lib/core/export/export_wording.dart` | the analysis sentences, held equal to the screens' by a parity test |
| `ExportPipeline` | both formats for every report; `exportPrintable` true for all four |

**What the analysis files state:**
- Each figure is shown beside the same stretch before: this period, the previous period, the
  domain's movement, and its percentage — or "N/A" with the screen's reason.
- An unavailable comparison prints "Not available" with the sentence saying why.
- A trend point that could not be established is "Not available", never zero. A clipped
  first or last point says it is partial.
- Rankings list the domain's lines in order, then the exact Others, then the total the set
  reconciled to. A set that did not reconcile prints only why.
- Business Comparison lists each property in fixed order, then both together, with results
  in words and margins as the screen shows them. It is offered only to consolidated
  authority.
- In Excel, money is numeric with no formulas and no raw-paise column; percentage changes
  are the screen's rounded text; margins are numeric percentages; line tables are frozen
  and filtered.

| Item | Status | Evidence |
|---|---|---|
| Analysis renderer tests | **Tested** | **35** passed: every Summary money cell equals the document's figure, previous and movement to the paisa; unavailable comparisons are words, never a zero cell; the gap is "Not available" while a real ₹0 stays a number; rankings, Others and totals exact; refused rankings print no line; Business Comparison columns in fixed order with results in words and percentage margins; no formula, no "paise", no id in any byte; PDF lines read back through `/ToUnicode` equal `MoneyFormatter`'s strings; page numbers and three separate freshness statements; no information dictionary; no id compressed or not; font sizes bounded; deterministic bytes (PDF compared without the random `/ID`); readable file names |
| Pipeline tests | **Tested** | **19** passed (7 new): every analysis workbook through the pipeline is byte-identical to its renderer; every analysis PDF renders and prints from the same bytes; the analysis PDF is the analysis renderer |
| Export Centre tests | **Tested** | **26** passed (7 new): Save Excel writes each analysis workbook with its sheets; Print sends the bytes Save PDF writes, for each analysis report; an incomplete dashboard offers nothing |
| Wording parity | **Tested** | **4** passed: unavailable-comparison lines, movements and every withheld-percentage reason, measure, grain and bucket labels, compared-with and cap notes, missing-trend lines and the order note equal the screens' words |
| Core export guard | **Tested** | **30** passed: every layout file free of arithmetic, sorting, parsing and clocks; every workbook's numeric cell built from `decimalLiteral` or `displayedFractionLiteral`; every PDF prints money through `pdfMoney` and uses the one document builder |
| Real-code controls | **Tested** | a trend gap written as a zero cell: red. An unavailable previous printed as ₹0: red. The movement re-derived by subtraction: guard red. Business Comparison columns reordered: red. An analysis layout dropped from the pipeline: red. Each restored and checked with `cmp` |
| **Full host suite** | **Tested** | **2,964 passed, 1 skipped, 0 failed** |
| `dart format` / `flutter analyze` | **Tested** | 401 files, 0 changed / no issues |
| Secret scan, tree and git history | **Tested** | clean |
| Dependency and lock integrity | **Tested** | `pubspec.yaml` and `pubspec.lock` unchanged since Slice 7 |
| Schema and server | **Tested** | no change under `supabase/` or `lib/data/local/`; `schemaVersion` 21 |
| Windows build | **Not tested** | this container is Linux; Slice 10 on the Windows machine (D-298: `printing` downloads PDFium at CMake time) |
| Android build | **Blocked** | Maven Central returned HTTP 429 to Gradle three times (Slice 8); not retried |
| A person reading the analysis files in Excel and a PDF viewer | **Not tested** | Slice 10, and the project lead's review (§U.4) |

## Phase 7 Slice 10 — full local acceptance: **COMPLETE** (2026-09-28)

Run against `krishna-mis-dev` only. The Windows phases ran in the real application, built by the
acceptance harness, and the native dialogs were driven through Win32. The phone phase ran on the
Galaxy A06 over USB only (D-288).

**The release executable itself was not launched** (D-247). The machine's real installation
database has no key store, so launching the release build would touch that installation. The
release bundle is therefore verified by build, inspection and scanning.

Local schema **v21**, ledger **101**. No migration, RPC, cache or schema change.

### Defects found and fixed — each reproduced, regression-tested and committed separately

| | Defect | Fix | Proof |
|---|---|---|---|
| 1 | Saving over a workbook open in Excel said the folder was refused | the destination is probed: a sharing violation means "open in another program" (`2839b52`) | Windows host test holding the file open; `excel-lock` step in the real app now reads "That file is open in another program" |
| 2 | **Opening the print dialog once made the next Save As freeze the app** | the Windows runner holds a second COM apartment reference (**D-308**, `99f0177`) | diagnosed with WinDbg: WINSPOOL releases the main thread's apartment once and Save As deadlocks in `MTAThreadWaitForCall`. The committed runner froze four times; the fixed one passed print ×1–×3 (cancelled and to PDF) followed by Save As; host guard added |
| 3 | **Withdrawing `reports.print` while the print dialog was open still printed** | authority is decided again when Print is pressed; the dialog gets no bytes otherwise (**D-309**, `c91d188`) | host test red under control; real app now `ExportActionAbandoned`. Microsoft Print to PDF leaves an empty 0-byte file, which the project lead accepted |

### Evidence

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | 404 files, 0 changed |
| `flutter analyze` | no issues |
| Full host suite, Windows | **2,974 passed, 0 skipped, 0 failed** |
| `p7-windows-export`, real app, final code | **PASS**: 8 saves with suggested names; cancel; overwrite confirmation; a name without an extension refused rather than silently overwritten; file locked by Excel; P&L and three analysis prints through Microsoft Print to PDF, byte-equal to Save PDF; four offline saves plus an offline print with no refusal and no synchronisation; reconnect refresh; Open in Analytics |
| `p7-windows-authority`, real app | **PASS**: Owner all; Manager none, with the reason shown; Accountant three reports without Business Comparison; two scoped grants still not consolidated; export-only; print-only; `reports.export` lost during Save As → Abandoned, no file; `reports.print` lost during the print dialog → Abandoned, nothing printed |
| `p7-windows-repro`, real app | print-cancel ×2 → Save As **PASS**; print ×2 → Save As **PASS** |
| `p7-android-share`, Galaxy A06 (SM-A066B, Android 16) | **PASS**: system share sheet with the PDF; cancel returns to the app; offline share; only one file in the private cache; Manager offered no share; Accountant loses and regains the share with `reports.export`; no Excel, print or Export Centre on the phone |
| Parity | every figure in the saved PDFs, workbooks and printed PDFs equals the canonical `PnlResult` / `DashboardView` to the paisa (asserted in the real app) |
| Microsoft Excel review | all four workbooks open with no repair prompt; money is numeric; no formulas; no raw-paise column; margins as percentages; a loss is negative and stated in words; Others is exact; frozen, filtered line tables; the one-month expense trend explains why there is no chart |
| PDF review | ₹ in Noto Sans; scope, period and basis on every page; the three freshness lines separate; page *n* of *N*; the P&L is two pages with its table heading repeated; no document-information dictionary; the printed copy matches the saved PDF |
| Privacy | no UUID, marker, path, email or capability code in any produced file |
| Secret scan, tree + history + artefacts | clean, after removing the acceptance **Debug** bundle, which carries identities by design |
| Windows release | `krishna_mis.exe` SHA-256 `775DABBE…0FA7`; `data/app.so` 13,321,104 bytes, `74387A63…17DC`; Noto Sans ×2 + `OFL.txt`; `pdfium.dll` + `printing_plugin.dll` present |
| Android dev APK | *(superseded by `E230C6A0…0A92` after D-310, below)* 247,355,724 bytes, SHA-256 `1812D57A…52A3`, `config/dev.json` only. Permissions: `INTERNET` only (no storage). FileProvider `…flutter.printing`. Noto Sans ×2 + `OFL.txt`. **Installed on the A06, installed hash equal to the build** |
| Backend baseline | role capabilities 80, hash `bd3b6b2b…`; grants 7 (5 active); roles 4; settings 0; closed periods 0; tax rules 4; open owner movements 0; storage 265 ↔ 265; dead helper absent; ledger 101 |

### Recorded, not changed

- **The phone acceptance rebuilds `app-dev-debug.apk` with the identity defines.** The APK was
  rebuilt clean afterwards, reproducing the same hash, rescanned, and reinstalled. Build clean last,
  then scan: the Slice 13 lesson again.
- **The shared PDF outlived sign-out.** The project lead ruled: it is also removed when the person
  signs out or another person takes the session (**D-310**, `eee0f09`). Leaving and reopening the
  Reports tab is deliberately not a trigger.
  - Host tests: 6 new, red under control.
  - Galaxy A06 (`p7-android-share`, **PASS**): sign-out left an empty share folder. A leftover
    PDF from the previous person was removed when the next person signed in, and an unrelated
    file beside it was left untouched.
  - A clean dev APK (`E230C6A0…0A92`, 247,356,790 bytes) is installed; the installed hash equals
    the build.
- **Treatment column** on the P&L Revenue sheet is blank unless the treatment is `none` ("No GST"),
  as on the screen. The fixture has no Banquet sale, so no row shows it here; host tests cover it.
- **Excel displayed lakh grouping** (₹1,23,642.00) on this machine. That comes from the Windows
  locale reading the conventional format (D-294); the stored value is exact either way.
- **Three open sales** (`KI-REV-26-27-002509 … 002511`, business date 25 Sep, by the Owner identity,
  no notes). They were created on 25–26 September, after the Phase 6 closure and before this
  acceptance. They are not acceptance fixtures and were left untouched.
- **Not tested:** a physical printer (only Microsoft Print to PDF). The share sheet's receiving apps
  (Gmail, Drive, Messages) were not used, because sending company data to an external service needs
  the project lead. The project lead's own Excel/PDF approval (§U.4) is pending.

---

# PHASE 7 — EXPORT, PDF & PRINTING: COMPLETE AND CLOSED

Closed on 2026-09-28 at Slice 11 (D-311). Master Spec **v1.2**, unchanged: Phase 7 renders
spec §16 as written and moves no financial semantics. Local Drift schema **v21**; migration
ledger **101**. Decisions **D-290 … D-311**.

Slice 11 is documentation and closure gates only: no product code, dependency, schema, migration
or server change. **Phase 8 — Production Hardening: not started.**

## 1 · What Phase 7 delivered

| Surface | Contents |
|---|---|
| **Windows Export Centre** (`/reports`) | The four reports — Profit & Loss, Revenue Analysis, Expense & Department Analysis, Business Comparison (consolidated only) — each offered as PDF, Excel and Print as authority allows, with scope, period and freshness shown and no figure. Open in Analytics |
| **Save As** | Native Windows dialog, readable suggested names, atomic write, no silent overwrite, truthful failures (folder refused, file open in another program) |
| **Printing** | The same PDF bytes through the native Windows print dialog; authority decided again when Print is pressed (D-309); no freeze after a print (D-308) |
| **Android** | The P&L PDF through the system share sheet from the app's private cache; no new permission; removed before the next share, at sign-out and when another person signs in (D-310) |
| **Foundation** | `ExportAuthority`; immutable document models; an internal OpenXML writer; the PDF renderer with bundled Noto Sans; one shared wording file held equal to the screens |

## 2 · Slices

| # | Slice | Commit(s) | State |
|---|---|---|---|
| 1 | Governance | `5451542` (+ `a69c450`, D-301) | CLOSED |
| 2 | Export and print authorisation | `cb9cf04` | CLOSED |
| 3 | Export document models | `ad9a234` | CLOSED |
| 4 | XLSX foundation | `ebbb8c6` | CLOSED |
| 5 | PDF foundation | `5a8ccbb` | CLOSED |
| 6 | Export Centre and Save As | `0342cbc` | CLOSED |
| 7 | Windows printing | `5373148` | CLOSED |
| 8 | Android P&L PDF share | `49489f2` | CLOSED |
| 9 | Analysis exports | `b521656` | CLOSED |
| 10 | Full local acceptance | `2839b52`, `b4fa40a`, `99f0177`, `c91d188`, `a948da8`, `eee0f09`, `01f0b66` | CLOSED |
| 11 | Closure | this record | CLOSED |

## 3 · Final acceptance evidence (Slice 10, accepted by the project lead)

| Gate | Result |
|---|---|
| Windows host suite | **2,974 passed, 0 skipped, 0 failed** |
| Windows release build | PASS (`krishna_mis.exe` `775DABBE…0FA7`; Noto Sans + `OFL.txt`; PDFium) |
| Android DEV APK | PASS — **SHA-256 `E230C6A036D8A6206F39600469AC6490782B2D0C26FA35DCD873DAAA185D0A92`**, 247,356,790 bytes, `config/dev.json` only, `INTERNET` permission only |
| Galaxy A06 installation | PASS — the installed hash equals the build |
| Windows Export Centre, native Save As | PASS (real application) |
| Excel review / PDF review | PASS (real Microsoft Excel; rendered PDFs) |
| Windows Print-to-PDF | PASS (all four reports; byte-equal to Save PDF) |
| Android P&L share | PASS (Galaxy A06, USB only) |
| Private share-cache cleanup on sign-out and user switch | PASS (D-310) |
| Authorization and revocation | PASS (Owner, Manager, Accountant, export-only, print-only, loss during Save As, loss during Print) |
| Offline and reconnect | PASS |
| Screen / XLSX / PDF / print parity | PASS, to the paisa |
| Secret scans | clean (tree, history, artefacts) |
| **U.4 project-lead manual review** | **PASS** (2026-09-28) |

## 4 · What Phase 7 did not add — verified at closure against `b35611a`

- No schema migration: no change under `supabase/`. The live ledger stays at 101, latest
  `20260912100000`.
- No change to the local database: Drift **v21**.
- No reporting RPC, no second reporting cache, and no change in the reporting data layer.
- No Owner Accounts export and no transaction-list export (D-296).
- No Android Excel and no Android direct printing (D-293).

**Dependencies:** `pdf` 3.13.1, `printing` 5.15.1 and `archive` 4.2.0, pinned exactly (D-298),
plus the bundled Noto Sans assets. Nothing else changed.

## 5 · Limitations and observations carried out of Phase 7

- **Printing tested on Microsoft Print to PDF only.** A physical printer is a Phase 9 check on
  the target machine.
- **When print authority is lost during the dialog, Print to PDF may leave an empty 0-byte
  file** and still asks where to save. The project lead accepted this; removing it needs a
  `printing` plugin fork (D-309).
- **The release executable was not launched in acceptance** (D-247). It was verified by build,
  inspection and scanning.
- **The share sheet's receiving apps were not exercised.** Sending company data to an external
  service needs the project lead.
- **Excel shows lakh grouping by the Windows locale.** The stored values are exact (D-294).
- **The P&L workbook's Treatment column is blank unless "No GST"**, as on the screen.
- **Real sales `KI-REV-26-27-002509 … 002511` were preserved exactly.** They are not
  acceptance fixtures.

## 6 · Carry-forwards

Carry-forwards are recorded in D-311:
- **Phase 8:**
  - export rendering performance;
  - the `may_read_expense` per-row cost;
  - the `org_id`-leading local index;
  - the Riverpod 3 retry-default review;
  - fatal missed taps across the host suite;
  - the D-248 diagnostic.
- **Phase 9:**
  - production configuration and the D-146 migration replay;
  - signing, AAB, Play and the Windows installer;
  - a reproducible PDFium build;
  - launching the release executable;
  - a physical printer.
- **Project lead:**
  - the production 50:50 ownership effective-from date;
  - the D-247 forensic database;
  - the Administration placeholder copy;
  - whether a transaction-list export is wanted;
  - optionally, the Print-to-PDF empty-file residue.

## 7 · Open defects at closure

**None.**

**PHASE 7 — EXPORT, PDF & PRINTING IS FORMALLY CLOSED. Phase 8 is not started.**

---

# PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: STARTED (2026-09-29)

Phase 7 closed at `ba1aed7`. Phase 8 was scoped by a read-only audit; the project lead accepted
it and ruled D1 … D8, recorded as **D-312**. The measurement contract is **D-313** and
`ARCHITECTURE.md` §52.

**The principle:** Phase 8 improves robustness and performance **without changing an approved
financial semantic, authority rule or V1 feature**. Measure first; change only what a
measurement against an approved threshold requires.

## The approved slice plan

| # | Slice | State |
|---|---|---|
| 1 | Governance and baseline harnesses | **COMPLETE** |
| 2 | D-186 server profiling (E-DEV current data, E-LOCALPG at SCALE and STRESS) | **COMPLETE** — breach measured (D-318); the approved redesign is built and D-318 closed (D-320, D-321) |
| 3 | Retry and hang hardening (D7) | **COMPLETE** (D-322) |
| 4 | Local expense-ledger profiling and deterministic ordering (D5, D-314, D-315) | **COMPLETE** (D-323, D-324) |
| 5 | Global missed-tap hardening (D8) | **COMPLETE** (D-325; D-326 reported) |
| 6 | Export performance (D2, T2/T3) | **CLOSED** — inside T2 on Windows and on the Galaxy A06 (D-327) |
| 7 | Stress and recovery, including damaged-database recovery (D4, D-316) | **COMPLETE** (D-328 … D-330) |
| 8 | Windows, emulator and Galaxy A06 acceptance and regression | **COMPLETE** (D-332; emulator not run, the A06 is the reference) |
| 9 | Closure | not started |

**Gates every slice closes on:** `dart format --set-exit-if-changed`, `flutter analyze`, the
tests the slice touches, the documentation invariants, the secret scan, a clean tree and a
commit hash. A slice that measures reports in the D-313 format. A slice that changes a schema,
an index, a server function or an authorisation predicate first reports the query, the plan,
the before timing, the cost and the rollback, and waits for the project lead where D-312 says
so. Full list: `RELEASE_CHECKLIST.md` §V.

## Phase 8 Slice 1 — governance and baseline harnesses: **COMPLETE**

Documentation and code comments only. **No schema, index, migration, server function,
dependency or product behaviour changed.** Local Drift schema stays **v21**; the migration
ledger stays **101**.

| Document | Change |
|---|---|
| `DECISIONS.md` | D-312 (the rulings), D-313 (measurement contract), D-314 (paging), D-315 (D-223), D-316 (damaged-database gap) |
| `ARCHITECTURE.md` | §9 corrected (LIMIT/OFFSET; which indexes lead with `org_id`); §8.2 marks the recovery flow as not yet built; new §52, the Phase 8 measurement contract |
| `DATABASE_SCHEMA.md` | *Phase 8* section: no schema change, the D-223 disposition, the local expense index inventory |
| `RELEASE_CHECKLIST.md` | §B's "keyset pagination" corrected; new §V, the Phase 8 gates |
| `PROJECT_STATUS.md` | this section; the two "keyset paging" statements annotated |
| three code comments | `expense_repository.dart`, `expense_ledger_page.dart`, `revenue_recent_page.dart` no longer claim keyset paging. Comments only |
| `SHOYEB_MASTER_SPEC.md` | **unchanged**, version 1.2 |

### Dataset classes (D-313)

| Class | Definition |
|---|---|
| **CURRENT** | the dev dataset at measurement time; on 2026-09-28: 2,150 expenses, 2,365 expense allocations, 2,475 expense period allocations, 2,601 revenue entries, 2,613 revenue components — mostly voided acceptance fixtures |
| **SCALE** | 100,000 contribution rows in one financial year, synthetic, E-LOCALPG and device caches |
| **STRESS** | 500,000 contribution rows over five financial years, synthetic, E-LOCALPG; on a device only as a stated worst case (retention is two financial years, D-170) |

### Environments (D-313)

E-DEV (`krishna-mis-dev`, PostgreSQL 17.6) · E-LOCALPG (a disposable PostgreSQL 17 cluster the
harness initialises itself — never the machine's running `postgresql-x64-17` service) · E-WIN ·
**E-A06, the reference Android device** · E-EMU (indicative only) · E-HOST (counts and plans,
never a timing verdict).

### Thresholds (D2, D-313)

| Id | Threshold |
|---|---|
| T1 | one-month canonical P&L ≤ 400 ms on E-A06; local database ≤ 500 MB |
| T2 | normal export, model + render + write: E-WIN < 1 s, E-A06 < 2 s, dialogs excluded |
| T3 | stress export reported separately, not automatically a defect |

Paths no threshold covers (server D-186, deep ledger pages, reporting sync) use 400 ms as a
**reporting line** only.

### Baselines already in the repository — none at SCALE or STRESS

| Area | Figure | Environment · dataset · when |
|---|---|---|
| Server revenue, one financial year | 0.3 ms | E-DEV · CURRENT (then) · 2026-09-08 |
| Server expense, one financial year | 368.7 ms over 1,094 rows, dominated by `may_read_expense` | E-DEV · CURRENT (then) · 2026-09-08 |
| Server, both properties with breakdown | 774 → 398.6 ms after D-186 | E-DEV · 2026-09-08 |
| Server, one month one property | 39 ms server; 98–185 ms end to end | E-DEV · 2026-09-08 |
| Dashboard, worst warm (37 reports) | 168 ms, then 163 ms | E-WIN · 7,300-row fixture · Slices 3 and 10 |
| Dashboard, worst warm | 31–41 ms, then 47 ms | E-EMU debug · same fixture · Slice 3, Phase 6 closure |
| Local P&L queries (month / year) | 0.07–0.58 ms | E-HOST · two-year fixture · on the non-production path (D-315) |
| First full reporting sync, 7,300 rows | 527–2,718 ms · 824–6,711 ms | E-WIN · E-EMU |
| Exports, ledger listing, Owner Accounts, start-up | **never measured** | — |

The E-DEV expense-period row count has grown from 1,094 to 2,475 since D-186 was measured, so
the 368.7 ms figure is not today's.

### Findings recorded for later slices, not fixed in Slice 1

| Finding | Slice | Record |
|---|---|---|
| No keyset paging exists; every ledger is LIMIT/OFFSET | documented now | D-314 |
| Expense ledger order has no stable id tie-break | 4 | D-314 (D5) |
| Windows expense ledger requests one page of 100 and offers no next page; the sync-state filter then applies in Dart | 4, **needs a ruling** | D-314 |
| D-223 index serves only the non-production reporting path | disposed of | D-315 |
| Damaged-database recovery promised by §8.2, not built; start-up failure shows the raw exception | 7 | D-316 |
| `PnlSyncController._run` and the dashboard sync await two providers before marking the run started — a plausible, unproven D-248 cause | 3 | D-312 (D7) |

### Readiness for Slice 2

E-DEV is readable. PostgreSQL 17.11 binaries are installed on this workstation
(`C:\Program Files\PostgreSQL\17\bin`), so E-LOCALPG can initialise its own throwaway cluster
without the running service's credentials. `track_functions` is `none` on E-DEV; whether a
session may raise it is established in Slice 2.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed lib test integration_test tool` | **Tested** | 405 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Documentation invariants (`migration_audit_test`, `backend_schema_parity_test`, `chart_guard_test`) | **Tested** | 68 passed |
| Secret scan, tree and git history | **Tested** | clean, scanner controls passing |
| Schema, migrations, server, dependencies | **Unchanged** | nothing under `supabase/`, `lib/data/local` or `pubspec.*` touched |
| Full host suite | **Not run** | Slice 1 changes no executable code; the baseline is Slice 5's first act (D8) |

## Phase 8 Slice 2 — D-186 server profiling: **MEASURED — STOPPED AT THE APPROVAL GATE**

Measure-first, as D-312 (D3) requires. Decisions **D-317** (the project lead's Slice 4 pagination
ruling, recorded before Slice 2 began), **D-318** (the measurements and the proposed redesign)
and **D-319** (the harness). **No product code, schema, migration, RPC or authorisation change.**
Local Drift schema stays **v21**; the migration ledger stays **101**.

### In plain words

The check that decides whether a person may see an expense runs once for every expense row a
report touches, costs about a third of a millisecond each time, and runs on rows the report then
throws away — voided documents, the other property, and on a sync, the whole history. Today's
data is small enough that nothing is slow (the worst is a sync at about one second). At the
approved scale of 100,000 rows a year, a full-year report and every reporting sync take longer
than Supabase allows a signed-in user's request (8 seconds) and are cancelled; at five years of
that, a new device's first sync fails outright because the reply is larger than PostgreSQL can
build. **A fix is justified and is proposed in D-318; nothing was changed, because it alters how
authorisation is evaluated and needs the project lead's approval.**

### Dev dataset (CURRENT, 2026-09-29)

2,150 expenses (2,089 voided) · 2,365 expense allocations · **2,475 expense period rows** ·
2,601 revenue entries (2,598 voided) · **2,613 revenue components** · 2 properties.

### Results in brief — full tables in D-318

| | CURRENT (dev) | SCALE (99,869 rows) | STRESS (499,975 rows) |
|---|---|---|---|
| One-property month, `reporting_primitives` | ~230 ms | 2.6–2.9 s local · ~1.7 s projected | 1.35–1.41 s local |
| One-property financial year, `reporting_primitives` | ~770 ms | 35–39 s local · **~20.5 s projected — over 8 s** | 15.6–16.0 s local |
| Reporting sync, 200-generation delta | ~0.9 s | 16–36 s local · **~20.8 s projected — cancelled at 8 s (shown)** | **137 s** local |
| First full reporting sync | ~1.04 s | 31–35 s local · ~20.8 s projected | **fails: jsonb > 256 MB (shown)** |
| `may_read_expense` calls, FY report | 2,247 | 49,514 | 49,514 |
| Same aggregate, no authorisation | 0.18–0.66 ms | 83–120 ms local | 116–244 ms local |

Projections multiply exact call counts by dev's measured per-call cost; local timings varied up
to ~3× with host load (D-319).

### Answers to the slice's twelve questions

1. **Commit** — see the commit recorded for this slice.
2. **Dev dataset** — above.
3. **Dev timings** — D-318, three principals, eleven workloads each, five warm runs.
4. **Local SCALE** — D-318; four principals.
5. **Local STRESS** — D-318; Owner and CCR Manager.
6. **Plans and buffers** — an Index Scan on `expense_period_allocations_category_period_idx`
   with `Filter: may_read_expense(expense_id)` per row, before the join that removes voided and
   unnumbered rows; all shared-buffer hits on dev (e.g. FY report 29,110 hits, 0 reads).
7. **Call evidence** — exact per-workload counts from `pg_stat_xact_user_functions`, enabled
   with `SET LOCAL track_functions` inside rolled-back transactions only.
8. **400 ms risk** — T1 is the device's local engine and is not directly threatened; the
   threat is functional: at SCALE the sync that fills the device's cache stops working.
9. **Server change justified** — yes, by measurement; **not implemented**, pending approval.
10. **Harness limitations** — D-319 findings 3–5.
11. **Clean tree** — yes, after the commit.
12. **Slice 3** — independent of D-186 (Riverpod retry and hang hardening, client-only) and
    safe to begin; not started.

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | 406 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Full host suite | **Tested** | **2,987 passed**, 0 failed (includes the 7 new harness-guard tests) |
| Harness guard (`test/tool/perf_harness_guard_test.dart`) | **Tested** | 7 passed; a planted TCP listener turned it red, restored byte-identical (`cmp`) |
| Harness authorisation self-test, SCALE | **Tested** | 8/8 PASS; positive control red (32,961 rows seen vs 2,922 own); restore hash equal to dev's |
| Local ↔ dev definition fidelity | **Tested** | 36 objects: 34 byte-identical, 2 identical apart from comments |
| Dev measurements | **Tested** | 3 principals × 11 workloads + baselines, 5 warm runs, every batch rolled back |
| SCALE / STRESS measurements | **Tested** | local; heavy STRESS workloads at 1–2 runs, recorded per result |
| 8 s timeout and 256 MB failures | **Tested** | both reproduced locally at SCALE / STRESS |
| Secret scan, tree and git history | **Tested** | clean, the scanner's own controls passing |
| Schema, migrations, server, dependencies | **Unchanged** | nothing under `supabase/`, `lib/` or `pubspec.*` touched |
| Synthetic data in krishna-mis-dev | **None** | dev batches create only a temporary function and roll back |
| D-318 redesign | **Not implemented** | awaits the project lead |

### Carried forward

* **The D-318 redesign** (R1 set-based authority; R2 requested-property scan; R3 bounded, paged
  sync transport) — needs the project lead's approval; R3 is a client–server contract change.
* **D-146 replay order** (D-319 finding 1) — Phase 9's staging replay must follow the ledger.
* **The revenue projection** carries the same per-row shape, one level shallower (~0.08 ms per
  component) — within R1's scope.
* **Slice 4** starts from D-317.

## Phase 8 — the D-318 redesign (D-320, D-321): **COMPLETE — D-318 CLOSED**

Approved by the project lead with one modification: **no global historical retention
cutoff**. Built as a follow-on to Slice 2, not as Slice 3, which is not started.

### In plain words

Every report and every synchronisation used to ask "may this person see this expense?" once
per row, including rows it then discarded. That question is now answered once per request.
A report for one property reads only that property. Synchronisation arrives in bounded pages
and still delivers the whole authorised history. The result is the same rows for every
person — proven row by row, not by counting — and the paths that were cancelled at SCALE
and failed at STRESS now take milliseconds to about a second.

Accepting the transport found one more problem, fixed before it was accepted: the first
paged version sorted the whole history on every page, so a five-year first sync took 19–32
minutes. Pages now read only their own neighbourhood of an index; the same sync takes about
30 seconds.

### Server changes (krishna-mis-dev)

| Ledger version | Name | What |
|---|---|---|
| 20260929163951 | `reporting_authority_evaluated_once` | R1 authority in set form, once per statement; R2 scoped scans |
| 20260929164052 | `reporting_snapshot_paged` | R3: `reporting_snapshot` dropped, `reporting_snapshot_page` added, three indexes |
| 20260930125903 | `reporting_snapshot_page_windowed` | each page reads a bounded generation window |
| 20260930132722 | `reporting_snapshot_page_window_stops` | the window stops early and ends tight |

Ledger **105**; reviewed API **57**; executable-SQL identity checked for all four
(`LEDGER.md`). **Local Drift schema unchanged at v21.**

### Client changes

`ReportingGateway` pages; `ReportingCache` stages pages under the owner key
`<owner>#reporting-staging` and publishes a run in one transaction; `ReportingSync` resumes
an interrupted run with an identical scope and discards it on any authority, session or
scope change (D-240); the purge covers staging and resume state (D-070, D-074).

### Headline measurements (full tables in D-321)

| | Before | After |
|---|---|---|
| dev, FY report (Owner) | 769.7 ms | 9.4 ms |
| dev, full sync / first page (Owner) | 1,044 ms | 210 ms (whole first sync 419 ms, 3 pages) |
| dev, delta sync | 895 ms | 23 ms |
| SCALE, FY report | 7.6–8.1 s (cancelled under 8 s) | 227–240 ms |
| SCALE, delta sync | 7.5–8.2 s (cancelled) | 14–17 ms |
| STRESS, first full sync | fails (jsonb > 256 MB) | 30.8 s over 250 pages, largest page 3.1 s |
| STRESS, delta sync | 86–137 s | 14–22 ms |
| `may_read_expense` calls in reporting | one per expense row | 0 |

### Verified

| Item | Status | Evidence |
|---|---|---|
| Equivalence gate, exact row identity | **Tested** | 238 / 238, 1,833,274 rows, final body, fresh SCALE replay |
| Positive controls C1, C2, C3 | **Tested** | all red: +29,705 rows, +25,049 rows, 53 rows |
| STRESS page-by-page comparison with the original paged body | **Tested** | 19 pages × 2 corrected bodies, 0 mismatches |
| 8 s timeout, SCALE and STRESS | **Tested** | old paths cancelled; every new page ≤ 3.1 s |
| Dev before / after | **Tested** | three principals, five warm runs, every batch rolled back |
| Document-generation invariant | **Tested** | host guard with a planted-violation self-check |
| `dart format` / `flutter analyze` | **Tested** | 408 files, 0 changed / no issues |
| Host suite | **Tested** | **2,999 passed** |
| Live suites on dev, final body, serial | **Tested** | **163 passed**: reporting 13, parity 30 (incl. the bounded-page walk), drill-down 5, owner accounts 31, completeness audit 8, settlement 20, expense 56 |
| Live revenue suite on dev | **Partially tested** | 67 passed, 1 deliberately skipped, **1 failed**: the bucket sweep hit its own 5-minute limit (carried below); its teardown reconciled the bucket, 0 stranded |
| Dev baseline after | **Tested** | open expenses 61 (hash `15906076…`), open revenue 3 (the pre-existing real sales), owner movements 0, settings 0, closed periods 0, grants 7 (5 active), roles 4, role capabilities 80 (hash `c1b4870f…`), tax rules 4, ledger 105, API 57, anon 0, tables without RLS 0 |
| Secret scan, tree and history | **Tested** | clean |
| Android / Windows builds and device acceptance | **Not tested** | installed pre-D-320 clients cannot sync reporting until rebuilt; that rebuild is Slice 8 |

### Recorded and carried

* The expense RLS read and `expense_document` are still per row (500–740 ms a month at
  SCALE and STRESS) — Slice 4, with the Expense ledger (D-317).
* The migration-replay order finding for Phase 9's D-146 staging replay stands (D-319).
* The revenue live suite's bucket-reconciliation test exceeds five minutes against the
  accumulated bucket (a Slice 11 characteristic, D-076 family); the bucket still reconciled
  exactly (0 stranded).

## Phase 8 Slice 3 — retry and hang hardening: **COMPLETE** (2026-10-01)

Decision **D-322**; `ARCHITECTURE.md` §52.7. **No schema, migration, server, D-318 SQL, paging
contract, finance or authorisation change.** Local Drift schema stays **v21**; the migration
ledger stays **105**; reviewed API **57**.

### In plain words

When something a refresh needed could not be read on this device, the refresh used to look as
if nothing had happened — for 38 to 76 seconds, or for ever — and some failures left it saying
"refreshing" permanently. Now a refresh says it is running the moment it is tapped, and if it
cannot run it says so at once, in plain words, and Refresh or Try again tries again.

### What Riverpod 3.4.2 actually does (read from its source)

Ten retries, 200 ms doubling to 6.4 s (38.2 s); an `Error` and a `ProviderException` are not
retried; an awaited `.future` stays pending while it retries; and the retry re-runs a provider
**only while something watches it**, so a `.future` read once from an unwatched provider never
settles. No container-level override existed. Pinned by tests.

### Before and after (fake clock, 100 ms steps)

| Act | Before | After |
|---|---|---|
| P&L / dashboard refresh, input unreadable, nothing watching | idle for ever; never settled | running at once; failed within 100 ms |
| the same, screen watching | idle; threw after 37.6–75.8 s | the same |
| Owner settlement refresh, input unreadable | "synchronising" for ever | failed within 100 ms |
| A local failure after a refresh started | left running for ever; later taps ignored | failed; the next tap runs |
| Report source unreadable | cache lock held 76 s | released within 100 ms |
| Export fonts failing with an `Exception` | never settled (unwatched) | answered within 100 ms; next press tries afresh |

### Verified

| Item | Status | Evidence |
|---|---|---|
| Riverpod semantics pinned | **Tested** | 3 tests: 38.2 s / 11 builds watched, never unwatched, `Error` not retried, `noAutomaticRetry` answers once |
| Retry and hang regression suite | **Tested** | `test/features/retry_hang_test.dart`, **26 passed** |
| Export: a font failure reported at once, next press fresh | **Tested** | `export_centre_test.dart`, 1 new |
| One-shot-read guard | **Tested** | 2 passed, with a planted-violation self-check |
| Positive controls | **Tested** | 11 sabotages, **all red**, each restored byte-identically (`cmp`) |
| Targeted suites (P&L, dashboard, analytics, owner settlement, export, session switch, revocation, stale-sync, cache coherence, reporting sync, surface guards) | **Tested** | **715 passed** |
| Full host suite | **Tested** | **3,028 passed**, 0 failed |
| Documentation invariants and Phase 8 guards | **Tested** | 79 passed |
| `dart format` / `flutter analyze` | **Tested** | 410 files, 0 changed / no issues |
| Secret scan, tree and history | **Tested** | clean |
| Live suites, builds, device acceptance | **Not tested** | no server or contract change; a rebuilt client is Slice 8's (pre-D-320 builds cannot sync reporting) |

### D-248

Not reproduced on a device in this slice. A plausible contributing cause is removed; D-248
**remains unconfirmed** and its diagnostic stays in place.

### Recorded and carried

* The expense entry forms show raw error text when the master hierarchy cannot be read — a
  presentation defect outside this slice (D-322).
* Revenue live suite: 67 passed, 1 deliberately skipped, 1 failed on the bucket sweep's own
  5-minute limit, with the bucket reconciled (carried from D-321, non-blocking, unchanged here).

## Phase 8 Slice 4 — Expense ledger profiling, pagination and read-path hardening: **COMPLETE** (2026-10-01)

Decisions **D-323**, **D-324**; `ARCHITECTURE.md` §52.8 and §9; `DATABASE_SCHEMA.md` *Phase 8
Slice 4*. Local Drift schema **v22** (four indexes). **No server change**: the migration ledger
stays **105**, the reviewed API **57**.

### In plain words

The Expense ledger could only ever show the newest 100 expenses, and its "sync state" filter
looked only inside those 100. Both are fixed: every filter is applied to everything on the
device before a page is taken, "Load more" adds 50 at a time, and the ledger says plainly
whether more exist. It is also much faster — a page that took 3.5 s at one year of data and 17 s
at five years now takes 2–5 ms on the real encrypted Windows database. Nothing about money,
dates, authority or synchronisation changed.

### What shipped

| | |
|---|---|
| Repository | `query` / `watchQuery`: one statement with every filter (sync state derived in SQL from the Dart mapping), `ORDER BY business_date, captured_at, id DESC`, LIMIT/OFFSET; three batched child reads |
| Providers | `filteredExpensesProvider` is a stream of an `ExpenseLedgerWindow` (rows + whether more exist), read as one window of `pages × 50`; `expenseLedgerPagesProvider` resets on any filter, search or authority change; `expenseLedgerShownTo` refuses a window for another person or question |
| Surface | "Showing the newest N expenses. More match these filters." / "Showing all N matching expenses."; **Load 50 more**; distinct "No expenses match these filters" and "No expenses recorded yet" |
| Schema v22 | `expense_id` indexes on the three child tables; `ix_expenses_ledger` partial on browsable rows |
| Errors | entry form, ledger and detail panel: plain words + Try again; detail to the developer log |
| Tooling | `test/support/expense_ledger_workload.dart`, host and Windows measurements, `tool/perf/d186.py --single` |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | 416 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Repository paging tests | **Tested** | 11: >100 reachable, sync filter before the cut, hierarchy filters, ties, void while paging, never-browsable rows, SQL/Dart sync-state parity, unknown status, statements and plans, v22 fresh and upgrade |
| Provider and UI paging tests | **Tested** | 12: load more to the end, resets, person/authority switch, stale window refused, live sync change on page 2, empty states, plain errors on ledger, detail and entry form |
| Ledger measurement (host) | **Tested** | 2 (counts and plans asserted, timings reported) |
| Existing expense suites | **Tested** | data 82, UI 21 |
| Positive controls | **Tested** | 8, all red, every file restored byte-identically (`sha256sum -c`); C2 needed a stronger tie test first (D-323) |
| Full host suite | **Tested** | **3,053 passed**, 0 failed (3,028 + 25) |
| E-WIN measurement, encrypted DB | **Tested** | before (`41f58c5`, worktree) and after, CURRENT / SCALE / STRESS |
| E-DEV and E-LOCALPG server reads | **Tested** | four principals, five runs, every dev batch rolled back; dev baseline unchanged afterwards |
| Secret scan, tree and history | **Tested** | clean |
| Live suites | **Not run** | no server SQL changed |
| Android emulator / Galaxy A06 measurement | **Not tested** | Slice 8 |
| Windows release build | **Not tested** | Slice 8 |

### Findings recorded, not changed

* Filter matching nothing at STRESS walks the whole ledger index (540 ms, E-WIN); search is a
  full `LIKE` scan (244 ms). Both are tens of ms at SCALE.
* The Revenue ledger filters sync state after the cut, the same defect class (D-127).
* Raw `$error` remains on Masters, Vendors, the Revenue ledger and the start-up screen (D-316,
  Slice 7).
* `recentExpensesProvider` has no reader in `lib/`.
* Two v12/v14 migration fixtures lacked `expense_attachments`; completed with a shared
  `v10ExpenseAttachmentsDdl` (the fourth instance of the D-159 fixture family).
* The revenue bucket-sweep live timeout (D-321) is unrelated and stays recorded.

## Phase 8 Slice 5 — global missed-tap test hardening: **COMPLETE** (2026-10-01)

Decisions **D-325**, **D-326**; `ARCHITECTURE.md` §52.9. **Test infrastructure only**: no product
code, schema, migration or server change. Local Drift schema stays **v22**; the migration ledger
stays **105**; reviewed API **57**.

### In plain words

If a test taps something that a real finger could not reach — hidden behind a dialog, off the
screen — the test now fails at that tap instead of printing a warning and carrying on. Switching
this on everywhere found nothing broken, because the suite had already been kept clean. It did
show that one revenue test had never really tested what its name said; testing it properly found
a small product defect (D-326), which is reported for a decision and not fixed here.

### What was done

| | |
|---|---|
| Baseline (HEAD `0e0e30b`) | **3,053 passed, 0 failed, 0 skipped**; zero missed-tap warnings in the log (a planted miss confirmed the reporter prints them) |
| Mechanism | `test/flutter_test_config.dart`: fatal at start, re-asserted in a root `setUp` before every test, a root `tearDown` that fails a test leaving it off |
| First enablement | **0 newly failing tests**; classification A–G all zero |
| Removed | five per-file `setUpAll`/`tearDownAll` toggles (`dashboard_drill`, `dashboard_mobile_home`, `pnl_capability_revocation`, `pnl_drilldown_ui`, `pnl_mobile_ui`) |
| Opt-outs retained | **none**. The `revenue_ui_test` opt-out guarded an unreachable second tap |
| Guard | `test/app/missed_tap_policy_test.dart`, 12 tests, structural and behavioural |
| Product defects | **D-326**, not a hit-target defect — a double press before the next frame reaches the revenue save twice; one sale kept, unhandled exception. Proposed fix verified and reverted |

### Verified

| Item | Status | Evidence |
|---|---|---|
| Missed-tap guard | **Tested** | 12 passed |
| Positive controls C1–C5 | **Tested** | all red as designed, each restored byte-identically (`cmp`); C1 also shown to pass with only warnings when the config is removed |
| Proposed D-326 fix | **Tested, not committed** | the skipped test passes with it; `lib/` restored |
| Full host suite | **Tested** | **3,064 passed, 1 skipped** (3,053 − the skipped double-tap test + 12 guard tests) |
| Randomised order (`--test-randomize-ordering-seed=20261001`) | **Tested** | 3,064 passed, 1 skipped |
| Three shards | **Tested** | 1,024 + 1,017 + 1,023 = 3,064, 1 skipped |
| `dart format --set-exit-if-changed` | **Tested** | 418 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Phase 8 and documentation guards | **Tested** | inside the full suite |
| Secret scan, tree and history | **Tested** | clean |
| Live suites, builds, device acceptance | **Not run** | no product or server change |

### Carried forward, recorded and not changed

* **D-326** — revenue Save double press (and the same `_saving` shape in `ExpenseEntryPage`, by
  reading). Awaits the project lead.
* **Revenue ledger sync-state filter after the page is cut** — `RevenueRepository._mapLedger`
  filters sync state in Dart after LIMIT/OFFSET, the defect D-323 closed for expenses. **An
  explicit Phase 8 correctness carry-forward**; not touched in Slice 5.
* **Five-year Windows stress** (D-323): an unmatched filter ~540 ms and text search ~244 ms. Not
  optimised; re-evaluated only if target-device measurement justifies it.
* **Raw error text** remains on Masters, Vendors, the Revenue ledger and the start-up screen; the
  start-up screen is Slice 7's.
* **`integration_test/windows_shell_test.dart`** (real executable) does not set missed taps
  fatal; it is outside the host config and outside D-075's acceptance suite. Making it fatal means
  a real-executable run, belonging with Slice 8.
* **The device acceptance suite** has two `warnIfMissed: false` drags (scroll steps that may start
  outside the target); `integration_test/` is outside the guard's scope.

## D-326 remediation (2026-10-01): **DONE** — commit `69693cd`

On Revenue and Expense entry, a second Save press that lands before the button rebuilds now
returns at once, before the controller. A save that fails releases the form for a retry.
- The skipped revenue test is re-enabled.
- There are 3 new tests and 4 positive controls.
- Host suite: **3,068 passed, 0 skipped**.
- No schema, server, outbox or validation change.

## Phase 8 Slice 6 — Export performance: **COMPLETE** (2026-10-01)

Decision **D-327**. No product code, schema, migration or server change. Local Drift
schema **v22**, ledger **105**.

### In plain words

We timed every export the app makes, in each of its stages, on the real Windows program.
The slowest everyday export takes about a seventh of a second the first time, and a fiftieth
of a second after that, against a limit of one second. Nothing needed speeding up. The phone
has not been measured yet, because it was not plugged in.

### Verified

| Item | Status | Evidence |
|---|---|---|
| Export workloads, normal and stress | **Tested** | `test/support/export_workload.dart`, built from canonical domain objects |
| Completeness at size | **Tested** | 8 host tests: every P&L line reaches the PDF and the workbook; no `.part` left behind |
| Positive controls | **Tested** | PDF and workbook truncating lines: both **red**, restored (`cmp`) |
| E-WIN, real executable, debug | **Tested** | normal worst 157 ms including fonts (T2 < 1 s: inside); stress P&L PDF 205 ms (T3, reported) |
| E-A06 | **Tested** | first realistic P&L PDF about 560 ms including fonts; warm 60.5 ms (49.1–94.9); output verified on the device (D-327 A06) |
| PDF page ceiling | **Recorded** | about 840 lines / 21 pages; beyond that the export fails safely (`ExportActionError`); fix proposed, not applied |

## Phase 8 Slice 7 — Stress, failure and recovery hardening: **COMPLETE** (2026-10-02)

Decisions **D-328** (inventory and baseline), **D-329** (classification, atomic schema steps, a
lock is not damage), **D-330** (the reset flow); `ARCHITECTURE.md` §8.2 and §52.10. **No Drift
schema change** (v22) and **no server change** (ledger 105, reviewed API 57).

### In plain words

If the app cannot open its data on this device it now says why, in plain words, and offers *Try
again*. Only when the data truly cannot be opened (or updated for this version) does it also
offer *Reset local data and download again*. That option first says how many unsent entries and
bills would be lost — or that this cannot be checked — and needs RESET typed. The data is moved
aside, never deleted. Separately, an app update interrupted part-way can no longer leave the
data permanently unopenable: it now either completes or changes nothing.

### What was wrong before (reproduced first, D-328)

* A missing key with the data file present **wrote a new key**, then reported "unreadable".
* Another program holding the file was reported as **"unreadable"**.
* An interrupted upgrade kept half its steps, and every later start failed for ever.
* Every failure showed its raw exception text, including file paths.

### Verified

| Item | Status | Evidence |
|---|---|---|
| Start-up classification on real failing databases | **Tested** | `local_store_startup_failure_test.dart`, 22: damaged, key missing (no key written), wrong key, malformed key, key store unreadable/unwritable, folder blocked, lock (exclusive, released, busy timeout measured 0), interrupted upgrade (version not advanced, retry succeeds, integrity and FK checks), interrupted creation, cause-first rules, rollback wrapper |
| Recovery and quarantine | **Tested** | `local_store_recovery_test.dart`, 14: read-only assessment (file unchanged by hash), unknown never zero, moves not deletes, key kept aside and still opens the copy, record holds no key, failed move put back, key store refusal stops first, interrupted reset still safe, every table empty after reset |
| Start-up and reset screens | **Tested** | `startup_failure_app_test.dart`, 21: every kind worded, no technical text, reset only where permitted, exact RESET, failed reset says so, failed restart after reset shown |
| Full disk during a save | **Tested** | `storage_full_write_test.dart`, 1: `SQLITE_FULL` via `max_page_count`; no document without its queue entry or the reverse; retry saves once |
| Positive controls | **Tested** | 12 sabotages, **all RED**, each restored byte-identically |
| Existing upgrade, schema and encryption suites inside the new transaction | **Tested** | 187 passed |
| Interrupted writes, response loss, staged reporting, D-070/D-074/D-240 | **Tested (existing)** | already covered; listed in D-329's report; run in the full suite |
| `dart format` / `flutter analyze` | **Tested** | clean / no issues |
| Full host suite | **Tested** | **3,134 passed, 0 failed, 0 skipped** (3,068 + 66) |
| Windows smoke, real `krishna_mis.exe`, isolated acceptance folder | **Tested** | `slice11-restart-a` and `slice11-restart-b` PASS (real DPAPI key, forced open, session restored without sign-in) |
| Recovery screens in the real executable | **Not tested** | host-tested only; device acceptance is Slice 8 |
| Secret scan, tree, history, artefacts | **Tested** | clean, after removing the acceptance Debug bundle and `build/flutter_assets` |
| Genuine low disk on a device | **Not tested** | engine-level `SQLITE_FULL` proven on host; a real full disk is a Phase 9 operational check |

### D-247

Nothing in this slice read, opened, moved or modified the forensic database; every test used its
own temporary folder and in-memory key store, and the Windows smoke used the acceptance folder.
**A normal build launched on this workstation would now offer to reset it** (it has no key);
confirming would move it into quarantine, not delete it. Do not launch a normal build here until
the D-247 disposal is decided.

### Carried forward

* **To Slice 8:** the recovery screens on Windows and the Galaxy A06; the device capability-loss
  export check; the D-310 user-switch check on the device; the Windows integration-test
  missed-tap policy; the two device scroll-drag opt-outs; a v21 → v22 real-device upgrade if a
  safe path exists.
* **Proposed, not made:** a short SQLite busy timeout (D-329 §6).
* **Revenue ledger:** the sync-state filter still runs after the page is cut
  (`RevenueRepository._mapLedger`). Untouched by this slice; **must be dispositioned before
  Phase 8 closes.**
  *(Closed 2026-10-02 by D-331: the filter now runs in SQL before the page is cut.)*

## Revenue ledger sync-state remediation (D-331): **DONE** (2026-10-02)

Pre-Slice-8 correctness remediation. The Revenue ledger's sync-state filter ran in Dart after
`LIMIT/OFFSET`, so *Conflict* could read empty while older conflicts existed. It now runs in
SQL before the page is cut, from the one canonical status mapping. Page size (50), the pager,
ordering, scope and every financial figure are unchanged. Drift stays **v22**; no server
change. Evidence: D-331.

| Item | Status | Evidence |
|---|---|---|
| Defect reproduced | **Tested** | 8 of 12 new regressions red on the unfixed code |
| Regressions | **Tested** | `test/features/revenue_ledger_sync_state_paging_test.dart`, 12 |
| Positive control | **Tested** | pre-fix repository restored → 8 red; fix restored byte-identically (`cmp`) → green |
| Existing revenue ledger and Windows UI suites | **Tested** | 65 passed alongside the new 12 |
| Index or schema change | **None** | plan shape unchanged; no index needed |

## Phase 8 Slice 8 — Windows and Galaxy A06 acceptance and regression: **COMPLETE** (2026-10-03)

Decision **D-332**. **No product code, schema, migration or server change.** Local Drift schema
stays **v22**; the ledger stays **105**; reviewed API **57**. Every change is in the acceptance
harness (`integration_test/`) or the host guards.

### In plain words

Everything Phase 8 changed was run in the real applications: the Windows program and the
reference phone. Recovery screens, the database upgrade, the fixed Revenue ledger filter, the
double-press fix, saving and printing through the real Windows dialogs, and sharing from the
phone all work. Running them found three faults in the test harness, all fixed; none in the
product. The development backend was put back exactly as it was.

### Phases, final code

| Phase | Windows (real `krishna_mis.exe`) | Galaxy A06 (SM-A066B, Android 16, USB `R9ZY50M3GVX`) |
|---|---|---|
| `p8-recovery` — lock → Try again only; damaged → typed RESET; cancel changes nothing; set aside, not erased; a failed restart stays recoverable | **PASS** | **PASS** |
| `p8-migration` — a copy of the synced database taken back to v21 upgrades to v22 in the running app | **PASS** | **PASS** — 8,334 rows over 34 tables kept, integrity ok, first ledger page equal, 30 ms |
| `p8-revenue-ledger` — 75 conflicts walked page by page (D-331) | **PASS** | **PASS** |
| `p8-double-submit` — two presses before a frame: 1 local, 1 server, for a sale and an expense (D-326) | **PASS** | **PASS** |
| `p8-windows-export` — Save As ×4, cancel, Print to PDF, offline save; files equal the screen | **PASS** (2 Oct) | — |
| `p7-android-share` — share sheet online and offline; `reports.export` removed from the accountant role and restored live; a user switch cleans the shared PDF (D-310) | — | **PASS** |
| `slice11-restart-a` / `-b` | **PASS** | — |
| `expense-simple` | **PASS** | **PASS** |
| `android-pnl`, `p6-android-dashboard`, `revenue-offline` | — | **PASS** |
| `p6-windows-dashboard`, `windows-pnl`, `windows-ledger`, `windows-revenue`, `windows-revenue-offline`, `expense-offline` | **PASS** (2 Oct) | — |
| `windows_shell_test.dart` (15 tests, missed taps now fatal) | **PASS** | — |
| performance harnesses (dashboard, expense ledger, export) | **PASS** (2 Oct) | — |
| Emulator | **Not run** — its ADB session stayed unauthorised; the A06 is the reference device (D-313) | |

"2 Oct" phases ran on the code committed at `f807631` and were not re-run; nothing they exercise
changed afterwards.

### Defects found, all in the harness

| | Defect | Fix |
|---|---|---|
| 1 | `classify` tapped the expense form's "Charged to" row after the notes were typed; on a phone the lazy list had scrolled it out and disposed it (`expense-simple` and `p8-double-submit` red on the A06) | scroll back up until it is built, then tap when hittable |
| 2 | `p8-migration` opened the P&L through the Windows Analytics route, which a phone does not have | the phone opens Reports, the desktop opens Analytics |
| 3 | D-248 recurred once (`android-pnl`, 2 Oct): the diagnostic showed the run had work (the header control ran it) but the pull did not start it | wait for the previous refresh indicator to dismiss before pulling; the diagnostic stays and now records whether one was showing (D-332) |

### Verified

| Item | Status | Evidence |
|---|---|---|
| `dart format --set-exit-if-changed` | **Tested** | 431 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Host suite | **Tested** | **3,154 passed**, 0 failed |
| Windows phases, final code | **Tested** | table above |
| Galaxy A06 phases, final code | **Tested** | table above; USB identity unchanged before and after |
| Live capability round trip | **Tested** | `reports.export` removed from and restored to the accountant role; role capabilities read back 80, `c1b4870f…` |
| Fixture reversal | **Tested** | `expense-cleanup` + `revenue-cleanup`, through the real API |
| Backend after | **Tested** | role capabilities 80 `c1b4870f…`; grants 7 (5 active); roles 4; open revenue 3 (ids `2b0d6f6f…`), open expenses 61 (ids `15906076…`); owner movements 0; settings 0; closed periods 0; live tax rules 4; ledger 105 — identical to the pre-Slice-8 capture |
| Clean Android dev APK | **Tested** | `config/dev.json` only; 247,462,769 bytes; SHA-256 `ee942fb6…66b4`; installed on the A06, installed hash equal; `INTERNET` only |
| Windows release build | **Tested** | `config/dev.json` only |
| Secret scan — tree, history, artefacts | **Tested** | clean, after removing the acceptance Debug bundle and `build/flutter_assets` |

### D-247

No phase opened the forensic database: since `f807631` every real-app restart passes the
acceptance folder, and a host guard refuses any that does not. A normal (non-acceptance) build
was **not** launched on this workstation.

### Carried to Slice 9

* The 20-page PDF limit (D-327) stays as ruled.
* The Phase 9 items recorded in D-311 and D-319 are unchanged.

---

# PHASE 8 — PERFORMANCE, HARDENING & RECOVERY: COMPLETE AND CLOSED

Closed on 2026-10-03 at Slice 9 (D-333). Master Spec **v1.2**, unchanged: Phase 8 changed no
financial semantic, authority rule or V1 feature. Local Drift schema **v22**; migration ledger
**105**; reviewed API **57**. Decisions **D-312 … D-333**.

Slice 9 is documentation and closure gates only: no product code, test code, schema, migration
or server change. **Phase 9 — Distribution: not started.**

## 1 · Slices

| # | Slice | Commit(s) | State |
|---|---|---|---|
| 1 | Governance and baseline harnesses | `7972edb` | CLOSED |
| 2 | D-186 profiling, and the approved D-318 redesign | `47b13bd`; `cb43a31`, `2a75ec2`, `1bdced7`, `48c2445` | CLOSED (D-318 closed by D-320, D-321) |
| 3 | Retry and hang hardening | `6856ceb`, `41f58c5` | CLOSED |
| 4 | Expense ledger profiling, pagination, v22 indexes | `491ca4f`, `0e0e30b` | CLOSED |
| 5 | Global missed-tap hardening | `b4f2ee4`, `da77e52` | CLOSED |
| — | D-326 remediation | `69693cd` | CLOSED |
| 6 | Export performance | `71118c1`, `112b725` | CLOSED |
| 7 | Stress, failure and recovery | `5f6827b`, `6143399` | CLOSED |
| — | Revenue ledger sync-state remediation (D-331) | `34a2834` | CLOSED |
| 8 | Windows and Galaxy A06 acceptance | `f807631`, `1a4dd12` | ACCEPTED / CLOSED |
| 9 | Closure | this record | CLOSED |

## 2 · Final technical state

| Area | State |
|---|---|
| **Local database** | Drift **v22**: four Expense ledger indexes (`ix_expense_allocations_expense`, `ix_expense_period_allocations_expense`, `ix_expense_attachments_expense`, `ix_expenses_ledger`). Upgrade covered by host migration tests (v9 → v22, inside one transaction) and proven on the real phone: v21 → v22, 8,334 rows over 34 tables kept, integrity ok |
| **Server** | ledger **105**, latest `20260930132722`; reviewed API **57**; `anon` executes nothing; every public table has RLS; `reporting_snapshot` dropped, `reporting_snapshot_page` the only reporting transport; no second reporting cache; `expense_sees_whole_org` absent (read live 2026-10-03) |
| **Reporting** | Expense and revenue reporting authority evaluated once per statement (no per-row predicate); a one-property report reads only its property; bounded paged first sync and bounded paged delta; complete authorised history, **no historical cutoff**; row identity proven 238/238 (D-320, D-321) |
| **Retry / hang** | One-shot refreshes read their inputs once, are visibly running before they await anything, publish a plain failure at once, and Try again reaches the failed input (D-322) |
| **Expense ledger** | Every filter, sync state included, decided before the page is cut; Load more; total order `business_date, captured_at, id`; four statements a page; the hidden 100-row ceiling gone (D-323) |
| **Revenue ledger** | Sync state decided before the page is cut (D-331) |
| **Test infrastructure** | Missed taps fatal across the host suite, re-asserted per test, leak-checked; the Windows shell test fatal; no opt-out anywhere (D-325) |
| **Export** | Inside T2 on Windows and the Galaxy A06; the 20-page PDF boundary accepted (D-327) |
| **Recovery** | Start-up failures classified; atomic schema steps; *Try again* always; *Reset local data and download again* only for unreadable or un-upgradable data, after a stated loss and a typed RESET; data and key set aside, never deleted; a failed restart stays recoverable; no raw technical text at start-up (D-328 … D-330) |
| **D-326** | A second Save press before the button rebuilds returns at once on Revenue and Expense entry; a failed save releases the form for a retry |

## 3 · Performance, before and after

Each row compares like with like: the same environment, dataset and principal. Figures are
medians unless stated.

| Path | Environment · dataset | Before | After |
|---|---|---|---|
| FY P&L primitives, Owner | E-DEV · CURRENT | 769.7 ms | 9.4 ms |
| FY P&L primitives, Owner / CCR Manager | E-LOCALPG · SCALE | 8,127 / 7,608 ms (cancelled under the 8 s timeout cold) | 240.1 / 227.1 ms |
| first reporting sync, Owner | E-DEV · CURRENT | 1,044.1 ms (one call) | 418.6 ms whole (3 pages) |
| first reporting sync, Owner | E-LOCALPG · STRESS, 5 years | **fails** (jsonb > 256 MB) | 30.8 s over 250 pages; largest page 3.1 s |
| delta reporting sync, Owner | E-DEV · CURRENT | 895.2 ms | 23.0 ms |
| delta reporting sync, Owner | E-LOCALPG · SCALE / STRESS | 7,459 ms / 85,755 ms | 16.5 / 21.6 ms |
| `may_read_expense` calls, FY report | E-DEV | 2,247 | 0 |
| Expense ledger first page | E-WIN encrypted · CURRENT | 55.2 ms | 4.6 ms |
| Expense ledger first / second / deep page | E-WIN encrypted · SCALE (1 year) | 3,479 / 3,631 / 3,906 ms | 3.1 / 2.5 / 50.3 ms |
| Expense ledger first page | E-WIN encrypted · STRESS (5 years) | 17,034 ms | 2.3 ms |
| Expense ledger statements a page | E-WIN | 151–156 | 4 |
| Expense ledger conflict filter, rows found | E-WIN · SCALE | 1 of 900 | 50 a page, all reachable |
| normal export, worst (session's first P&L PDF incl. fonts) | E-WIN debug | not measured before | ~157 ms (T2 < 1 s) |
| normal P&L PDF, first incl. fonts / warm | E-A06 debug | not measured before | ~560 ms / 60.5 ms (T2 < 2 s) |

## 4 · Tests and acceptance

| Gate | Result |
|---|---|
| Host suite at `1a4dd12` (re-run for closure) | **3,154 passed, 0 failed** |
| Positive controls | every Phase 8 fix carries at least one control seen red and restored byte-identically: D-320 (3), D-322 (11), D-323 (8), D-325 (5), D-326 (4), D-327 (2), Slice 7 (12), D-331 (1 control, 8 red) |
| Windows real executable (Slice 8) | **PASS** — isolated acceptance data folder; shell 15 tests, missed taps fatal; recovery and start-up; v21 → v22; Revenue ledger paging; double Save; Save As ×4, cancel, Print to PDF, offline save; restart; dashboard, P&L, ledgers, offline revenue |
| Galaxy A06 (Slice 8) | **PASS** — v21 → v22 upgrade (8,334 rows, integrity ok); Dashboard; paged reporting; P&L; Expense and Revenue ledgers; share online/offline; capability loss and restoration live; D-310 cleanup; clean APK `ee942fb6…66b4` installed with equal hash |
| Android emulator | **NOT EXECUTED** — ADB unauthorised; **waived for Phase 8 closure** by the project lead |
| Migration acceptance | host v9 → v22 suites inside one transaction; real-device v21 → v22 on Windows and the A06 |
| Recovery acceptance | 22 + 14 + 21 + 1 host tests (Slice 7); `p8-recovery` on Windows and the A06 |
| Secret scan | tree and history clean at closure; artefacts clean at Slice 8 |
| Backend baseline | read live at closure: ledger 105, API 57, anon 0, tables without RLS 0, role capabilities 80, grants 7 (5 active), open revenue 3 and open expenses 61 (all pre-existing), owner movements 0, settings 0, closed periods 0 |

## 5 · Dispositions

* **Revenue ledger correctness:** fixed before Slice 8 (D-331, `34a2834`) and accepted in it.
* **D-248:** UNCONFIRMED, diagnostic retained. The production refresh passed independently; the
  pull-gesture timing is a plausible harness explanation, not proof.
* **D-247:** preserved and unresolved. **No normal build may be launched against this
  workstation's normal AppData until D-247 is dispositioned.** Phase 9 operational.
* **Accepted non-blocking limitations, classified future enhancements and Phase 9 operational
  items:** D-333.

## 6 · Product-lead inputs

1. **The production 50:50 ownership effective-from date — UNKNOWN.** Production Owner
   Settlement is blocked on it. Not guessed.
2. D-247 disposition before a normal build is installed or launched on this workstation.
3. Whether to make a small presentation pass on the remaining raw-error surfaces before go-live.
4. Carried from D-311: the Administration placeholder copy; transaction-list export (D-296);
   optionally the Print-to-PDF residue (D-309).

## 7 · Phase 9 handoff

Phase 9 — Distribution owns, in this order where order matters:

1. a production Supabase project, configuration and secrets (never in the repository or chat);
2. the D-146 fresh migration replay in **ledger** order, with the owner bootstrapped before
   `revenue_verified_baseline_fy2627` (D-319), then reason-constraint validation;
3. production security and RLS verification (API surface, anon, RLS, Storage policies);
4. Android release signing with the project lead's keystore, the AAB, Play Internal Testing;
5. the Windows production build, a reproducible PDFium source (D-298), the installer, and a
   launch of the release executable — **on a workstation where D-247 is dispositioned**;
6. a physical printer check; a genuine low-disk check where practical;
7. rebuilding every installed client (pre-D-320 builds cannot synchronise reporting);
8. production smoke tests, backup and recovery verification, the go-live runbook and final
   release acceptance.

**Phase 9 is safe to scope from this foundation. It is not started.**

---

# PHASE 9 — PRODUCTION RELEASE, DEPLOYMENT & GO-LIVE: STARTED (2026-10-03)

Phase 8 closed at `d7c7e22`. The Phase 9 audit was accepted with its nine-slice plan.
Decisions **D-334 … D-345**; `ARCHITECTURE.md` §53; `DATABASE_SCHEMA.md` *Phase 9*;
`RELEASE_CHECKLIST.md` §W; `docs/PRODUCTION_RUNBOOK.md` (skeleton).

**The principle:** Phase 9 adds no V1 feature and changes no financial semantic. It takes the
closed V1 to a production backend, signed releases on both platforms, and a go-live.

## The approved slice plan

| # | Slice | State |
|---|---|---|
| 1 | Governance and production inputs | **COMPLETE** |
| 2 | Release-build hardening | **COMPLETE** (D-346, D-347) |
| 3 | Pre-release UX wording | **COMPLETE** (D-348) |
| 4 | Authoritative migration replay and rehearsal | not started |
| 5 | Production Supabase | not started |
| 6 | Android release, AAB, Play Internal Testing | not started |
| 7 | Windows release, installer, clean-machine acceptance | not started |
| 8 | Production smoke, backup, recovery, go-live readiness | not started |
| 9 | Final V1 release closure | not started |

## Phase 9 Slice 1 — governance and production inputs: **COMPLETE**

Documentation only. **No product code, schema, migration, manifest, signing material,
dependency or server change.** Local Drift schema stays **v22**; the migration ledger on
`krishna-mis-dev` stays **105**; reviewed API **57**. No Supabase project was created, no key
generated, nothing built or signed, and D-247 was not touched.

### Release blockers recorded (D-335), all owned by Slice 2

| # | Blocker |
|---|---|
| 1 | Production Android manifest lacks `INTERNET` (only debug/profile declare it) |
| 2 | Release signing falls back to the debug key (`TODO(Phase 9)` in `build.gradle.kts`) |
| 3 | `proguard-rules.pro`, named by the minified release build, does not exist |
| 4 | A prod build without a backend seeds demo masters instead of refusing to start |
| 5 | Development and production share one Windows data identity (folder, file, key name) |
| 6 | That identity is the D-247 folder on this workstation |

### The contracts recorded

| Contract | Where |
|---|---|
| Phase 9 definition and plan | D-334 |
| Binding rulings: D-247, 50:50 date, transaction-list export, Print-to-PDF residue, error wording, Administration placeholder | D-336 |
| Production Supabase environment | D-337 |
| D-146 authoritative replay: committed ordered manifest with SHA-256, the `20260829090500` anomaly, the stop point before `20260901132225`, Owner bootstrap, fail on first error, **98** files against dev's 105 ledger rows | D-338 |
| Rehearsal mandatory; production security acceptance; **production smoke read-only** | D-339 |
| Production bootstrap sequence; administration gap (path A or B) | D-340 |
| Android release | D-341 |
| Windows release | D-342 |
| Pre-release UX scope (six files) and the proposed Administration wording | D-343 |
| Backup and recovery; physical printer; low disk | D-344 |
| Input, secrets and runbook registers; the §K.2 correction | D-345 |

**One figure corrected against the repository.** The Slice 1 direction said 99 committed
migration files; `supabase/migrations/` holds **98** `.sql` files at `d7c7e22`. The replay
contract records 98 and Slice 4's manifest is generated from the repository.

### Product-lead input register

Classified by when each is needed. **No answer is invented**; an item is closed only by the
project lead's own answer, recorded in a decision.

| # | Input | Needed | State |
|---|---|---|---|
| 1 | Supabase production plan tier (decides PITR and leaked-password protection) | REQUIRED BEFORE PRODUCTION DEPLOYMENT (Slice 5) | PENDING |
| 2 | Rehearsal target: separate staging project or Supabase branch (audit: staging project) | REQUIRED BEFORE SLICE 4 | PENDING |
| 3 | Windows production data identity (folder name and key name) | REQUIRED BEFORE SLICE 2 | **APPROVED** — `Krishna Imperial MIS Production`, `krishna_mis.db_key.prod.v1`; implemented (D-346) |
| 4 | Installer choice (audit: Inno Setup, per-user, no admin rights) | REQUIRED BEFORE SLICE 7 | PENDING |
| 5 | Windows code-signing certificate, yes or no | REQUIRED BEFORE SLICE 7 | PENDING |
| 6 | Play developer account: personal or organisation | REQUIRED BEFORE PLAY (Slice 6) | PENDING |
| 7 | Privacy-policy URL | REQUIRED BEFORE PLAY (Slice 6) | PENDING |
| 8 | App versioning scheme (current `1.0.0+1`) | REQUIRED BEFORE SLICE 6 | **SET** — semantic `versionName`, `versionCode` +1 per Play upload, stays `1.0.0+1` until an upload (D-347) |
| 9 | Production administration path, A (SQL procedure) or B (Owner-authenticated CLI; audit recommends B) | REQUIRED BEFORE SLICE 4 (so it is rehearsed) | PENDING |
| 10 | Real staff names, emails, roles and properties — supplied privately, never into git | REQUIRED BEFORE PRODUCTION DEPLOYMENT | PENDING |
| 11 | Auth Site URL | REQUIRED BEFORE PRODUCTION DEPLOYMENT | PENDING |
| 12 | SMTP, yes or no (password-reset email) | REQUIRED BEFORE PRODUCTION DEPLOYMENT | PENDING |
| 13 | Production smoke write policy | OPTIONAL / NON-BLOCKING — the read-only default (D-339) applies unless changed | DEFAULT IN FORCE |
| 14 | Target finance PC for Windows acceptance | REQUIRED BEFORE SLICE 7 | PENDING |
| 15 | Physical printer model | OPTIONAL / NON-BLOCKING — NOT EXECUTED if unavailable | PENDING |
| 16 | Confirmation of the production master structure (seeded by `20260827091200_seed.sql`) | REQUIRED BEFORE PRODUCTION DEPLOYMENT | PENDING |
| 17 | Confirmation that the four verified tax rules still hold (D-091, D-096) | REQUIRED BEFORE PRODUCTION DEPLOYMENT | PENDING |
| 18 | Go-live date | REQUIRED BEFORE SLICE 8 | PENDING |
| 19 | 50:50 ownership effective-from date | OPTIONAL / NON-BLOCKING for Phase 9 — blocks production Owner Settlement only | UNKNOWN |
| 20 | D-247 disposition | REQUIRED BEFORE any normal build runs on this workstation; NON-BLOCKING for release work done in isolation | PENDING |
| 21 | Windows staging data identity — today staging shares the development folder and key (D-346) | REQUIRED BEFORE a staging client runs on Windows (Slice 4 rehearsal) | **APPROVED** — `Krishna Imperial MIS Staging`, `krishna_mis.db_key.staging.v1` (D-349); built and guarded when staging is first exercised |

### Unresolved product-lead decisions

Rehearsal target (#2); Windows production data identity (#3); installer (#4); code signing
(#5); Play account type (#6); privacy-policy URL (#7); versioning (#8); administration path
(#9); plan tier (#1); Site URL (#11); SMTP (#12); target PC (#14); printer (#15); master
structure and tax-rule confirmations (#16, #17); go-live date (#18); the 50:50 date (#19);
D-247 (#20). **Slice 2 needs only #3**; everything else is needed later.

### Gates

| Item | Status | Evidence |
|---|---|---|
| Repository at `d7c7e22`, `origin/main` equal, tree clean, before editing | **Tested** | checked first |
| Release blockers re-read in the code | **Tested** | each cited in D-335 |
| `dart format --set-exit-if-changed` | **Tested** | clean, 432 files (the one new test file formatted before the check) |
| `flutter analyze` | **Tested** | No issues found |
| Phase 9 governance guard | **Tested** | `test/docs/phase9_governance_guard_test.dart`, **7 passed**; three planted violations (a missing runbook section, a planted secret, the stale §K.2 line) turned **3 red**, both files restored byte-identically (`cmp`) |
| Documentation invariants and existing release/config guards | **Tested** | **132 passed** with the guard: migration audit, backend schema parity, chart guard, acceptance isolation, app config, no hard-coded authority, missed-tap policy, Windows runner apartment, document-generation and `change_seq` invariants |
| Secret scan, tree and history | **Tested** | clean, after the guard's planted values were assembled at run time — the scanner first refused a planted connection-string literal, as it should |
| Builds, device acceptance, live suites | **Not run** | Slice 1 changes no executable code |

## Phase 9 Slice 2 — Release-build hardening: **COMPLETE** (2026-10-03)

Decisions **D-346**, **D-347**. Closes D-335. No schema, migration, server or Supabase change:
local Drift schema **v22**; `krishna-mis-dev` ledger **105**, reviewed API **57**; no production
or staging project created. Starting point `1da9cf9`, pushed and verified equal to
`origin/main` before any change.

### In plain words

A release build of the app can now reach the internet, is signed only with the project
lead's upload key (and refuses to build without it), shrinks its code safely, refuses to
start if production is configured wrongly, and keeps production's data on Windows in its own
folder with its own key — never the old folder that holds the D-247 database.

### What changed

| Area | Change |
|---|---|
| A | `INTERNET` in `android/app/src/main/AndroidManifest.xml` |
| B | `build.gradle.kts`: upload-key signing from `android/key.properties`; `verifyReleaseSigning` stops every release build without it; no debug fallback |
| C | `android/app/proguard-rules.pro` created (no rules needed by the measured builds) |
| D | `AppConfig`: production refuses no backend and the dev backend; unknown `APP_FLAVOR`, flavour mismatch and an undeclared release refused; `permitsOfflineSeed` guards the seed |
| E | `local_storage_location.dart` + `protected_file_secret_storage.dart`: per-environment folder and key; Windows production key in its own DPAPI file; bootstrap, recovery, session and staged bills routed through it |
| F | version convention recorded (D-347); `1.0.0+1` unchanged |

### Verified

| Item | Status | Evidence |
|---|---|---|
| Missing signing config | **Tested** | `flutter build apk --release --flavor dev` → `:app:verifyReleaseSigning` fails with the plain message, no file |
| Prod release APK, throwaway key, R8 | **Tested** | built; `in.krishnaimperial.mis`, versionCode 1, versionName 1.0.0; signer `CN=Throwaway Slice2 Test, O=NOT FOR RELEASE`; SHA-256 `6e50fc7c…5212` |
| Prod release AAB | **Tested** | built; SHA-256 `e58898f7…bc9` |
| Staging release APK | **Tested** | built; SHA-256 `2e23f232…8fc9` |
| Merged manifests | **Tested** | INTERNET + androidx's app-private DYNAMIC_RECEIVER permission only, every current variant |
| Release startup on the Galaxy A06 (USB `R9ZY50M3GVX`) | **Tested** | staging release: sign-in screen, no crash, no class-missing error in logcat. Uninstalled |
| Prod fail-closed on the Galaxy A06 | **Tested** | prod release on the dev backend: *This production build is configured with a development backend.* Uninstalled; the phone's dev install untouched |
| Release-mode sign-in and sync | **Not tested** | needs credentials this session does not type; Slice 6 |
| Debug build without signing material | **Tested** | `flutter build apk --debug --flavor dev` builds |
| Windows release, prod config on dev backend | **Tested** | built; production folder and key names present in `app.so`; **not launched** |
| Windows release, `config/dev.json` | **Tested** | built; `krishna_mis.exe` `775dabbe…0fa7`, `app.so` `0e7277c1…a30`, `pdfium.dll` `0c88ebac…abd`, `sqlite3mc.dll` `fd50815d…6ae3`; **not launched** |
| Windows production path, real host | **Tested** | computed from the real roaming folder: `…\Roaming\Krishna Imperial\Krishna Imperial MIS Production`, not the legacy path; nothing created |
| D-247 guards 1–8 | **Tested** | `test/data/local_storage_location_test.dart` |
| Positive controls | **Tested** | 9 sabotages, all RED, each restored byte-identically (D-346) |
| New tests | **Tested** | production config 19, storage location 20, release guard 23 |
| `dart format --set-exit-if-changed` | **Tested** | 437 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Full host suite | **Tested** | **3,223 passed**, 0 failed |
| Secret scan — tree, history, artefacts | **Tested** | clean; plus 0 of 6 development passwords in 1,198 artefact entries |
| Final production APK / AAB | **Not built** | needs the real upload keystore — Slice 6 |

The artefacts above are **verification builds**, not releases: throwaway-signed, against the
development backend, deleted from the phone, and never uploaded.

### D-247

Not opened, migrated, renamed, re-keyed or copied. No build was launched on this workstation.
The production code path cannot resolve the legacy folder or key, and never calls the
platform folder lookup on Windows (D-346).

### Unresolved release inputs

#1 plan tier, #2 rehearsal target, #4 installer, #5 Windows code signing, #6 Play account
type, #7 privacy-policy URL, #9 administration path, #10 staff list, #11 Site URL, #12 SMTP,
#14 target PC, #15 printer, #16 master structure, #17 tax rules, #18 go-live date, #19 the
50:50 date, #20 D-247, and new **#21 Windows staging data identity**. Signing: the real upload
keystore and `android/key.properties` exist only on the project lead's release machine, created
by the project lead (runbook §7).

## Phase 9 Slice 3 — Pre-release UX wording: **COMPLETE** (2026-10-03)

Decisions **D-348** (the error-presentation rule) and **D-349** (Windows staging identity,
input register #21 approved, not yet built). `ARCHITECTURE.md` §53.6; `RELEASE_CHECKLIST.md`
§W.3. **Presentation only.** No business logic, schema, migration, server, authority,
paging, sync, recovery, signing, manifest, storage-identity or export change. Local Drift
schema **v22**; `krishna-mis-dev` ledger **105**, reviewed API **57**, untouched.

### In plain words

When a screen cannot read its data, it now says so in a sentence anybody can act on and
offers a Try again that actually reads again. The technical cause is kept for whoever
diagnoses the device, in the developer log, and is no longer printed on screen. The
Administration page no longer says it "will be built in Phase 2"; it says who handles those
tasks in this version.

### What each surface says

| Surface | Text | Try again |
|---|---|---|
| Masters (Windows, Android) | *The property structure could not be read on this device. Try again.* | re-reads the hierarchy |
| Tax rates | *Tax configuration could not be read on this device. Try again.* | re-reads whichever input failed (new) |
| Vendors | *Suppliers could not be read on this device. Try again.* | re-reads the list for the filter on screen (new) |
| Revenue ledger | *The sales ledger could not be read* · *Try again. If this keeps happening, restart the app.* | re-reads the ledger page (new) |
| Expense save failure | *This expense could not be saved. Check Transactions before trying again.* (edit: *This edit could not be saved. Check the expense in Transactions before trying again.*) | Save stays available (D-326) |
| Administration | *Users, roles, period close and audit review are handled by the project administrator in this version.* | — |

The expense sentence no longer claims *"Nothing has been recorded"*: the expense commits
before its bills are moved on, so that claim could be false (D-348).

### Verified

| Item | Status | Evidence |
|---|---|---|
| Regression tests | **Tested** | `test/features/pre_release_wording_test.dart`, 10: Masters ×2, Tax ×3, Vendors ×2, Revenue ledger ×2 (each: plain words, no raw text, fits at 1366×768 and 360×740, Try again re-reads with automatic retry off), Administration on the real desktop router |
| Expense save failure | **Tested** | `expense_ui_test.dart` D-326 retry test now asserts the new sentence and no `StateError` / `Bad state` / exception text |
| Structural guard | **Tested** | `test/app/error_presentation_guard_test.dart`, 15, with planted controls for every detector and for false positives (comments, log calls, `Text(error.message)`) |
| Presentation controls C1–C7 (raw `$error`, `${failed.error}`, `runtimeType`, the old Phase 2 notice — one per surface) | **Tested** | each RED in its regression **and** in the guard (+13 −2); every file restored byte-identically (`cmp`) |
| No-op Try again controls (Masters, Tax, Vendors, Revenue ledger) | **Tested** | each RED (−1 / −2 / −2 / −2); restored byte-identically |
| Targeted suites (Masters, Vendors/Tax, Revenue ledger ×3, Revenue UI, Expense UI and ledger, routing, P&L wiring, surface guards, account control, docs, missed-tap, one-shot, migration audit, schema parity) | **Tested** | **389 passed** |
| Full host suite | **Tested** | **3,248 passed**, 0 failed (3,223 + 25) |
| `dart format --set-exit-if-changed` | **Tested** | 439 files, 0 changed |
| `flutter analyze` | **Tested** | No issues found |
| Live suites, device runs | **Not run** | no server or platform-specific behaviour changed |

### Recorded, not changed

* `VendorsView` sorts the provider's list in place (found by a test fixture's `const []`);
  harmless with the repository's growable list.
* Two acceptance-suite diagnostics matched the old *"was not saved"* wording and would have
  gone silent; they now match *"could not be saved"*.
* A lib-wide scan found no other surface rendering an exception.

