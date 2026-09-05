# Project Status

Directive: SHOYEB-HOSPITALITY-MIS · **Master Spec v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Last updated: **2026-09-05** — Phase 4 Slice 10 closed, and three correctives done and
accepted (D-136 … D-146). **All five mandatory financial reasons** now reject whitespace-only
values, revenue records its business-date provenance, and the reason constraints validate in
clean environments. **Slice 11 is not started.**

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
| `dart format --set-exit-if-changed` | **Tested** | clean (175 files) |
| `flutter analyze` | **Tested** | **No issues found** |
| Host test suite | **Tested** | **1,101 tests, all passing** (1,067 + 34 across three correctives) |
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
| Windows ledger: the complete filter surface, keyset paging, scoped detail caption | **Tested** | `windows-ledger`, incl. the filter-dependency rule and a scoped share never captioned `TOTAL` |
| Two-device Android ⇄ Windows expense propagation | **Tested** | `propagate-expense-a…e`: create with a bill, correct, stale edit conflicts, void, evidence still there |
| Expense **edit** through the UI | **Tested** | `expense-edit` on both real clients: identity kept, version advanced, D+7/D+8, stale → Conflict (D-072a) |
| D-070/D-074 financial cache retention and ownership | **Tested** | `d068-switch` + `d068-revoke`, 3 on the real APK and 3 inside the real `.exe`, the Windows ones against a database that had accumulated across runs |
| Client and server agree on a business date at one instant | **Tested** | 10 host tests reading migration 0033's own assertion table |
| Payment-date accrual through the application | **Tested** | `payment-accrual`: ₹80,000 to June, ₹0 to July, paid 5 July |

### Test totals

| Suite | Count | Result |
|---|---|---|
| Host (`flutter test`) | **1,101** | all passing |
| Live backend against `krishna-mis-dev` (opt-in) | 19 | the phases this change touches re-run at the corrective checkpoint (`drift`, `conflict`, and the revenue chain, twice in succession); the four scope phases need administrative grant changes between them and were **not** re-run |
| Live expense suite against `krishna-mis-dev` (opt-in) | **50** | all passing — re-run in full at the final pre-Slice-11 checkpoint |
| Live revenue boundary suite (opt-in) | **49** | all passing, 1 deliberately skipped |
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

**Slice 11 — attachments, reusing D-073a unchanged.** All three correctives that stood in
front of it are **done, tested and accepted**, and the one open product question they raised
has been answered and built (D-143). Nothing blocks Slice 11, and it has **not** been
started.

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
