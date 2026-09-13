# Phase 5 Slice 7 — reporting security closure

Verified 2026-09-12/13 against `krishna-mis-dev` only (`loratzmactetjbqolwri`).
Starting HEAD: `a7e74bd6962a0a3e0f1f55061e1d4315b62bb743`.
No Slice 8 screen, chart, export, print, drill-down or finalized statement was built.

## Initial audit and correctives

The server's `reports.view` evaluator already existed and was retained. The actual gaps
were local: canonical reporting reads trusted cache ownership without checking the current
principal; direct owner-settlement repository reads had the same weakness; reporting
capability loss with property access retained did not purge the P&L cache; and sign-out
could miss reporting-only units when no business-unit master rows existed.

Each defect was observed RED before its owning-layer fix. Local adapters now receive the
session principal, derive the cache owner from it, and refuse unauthorised reads. D-070
purges the affected person's reporting facts and evidence, coverage first, on confirmed
loss of any required capability. Sign-out discovers units from reporting tables too.
Existing actor-owned unsent-work preservation and property-removal doctrine are unchanged.

## Capability matrix

Role names below describe seed bundles only, never evaluator branches. Owner grants are
unscoped; Manager, Accountant and Data Entry assignments carry explicit property scopes.
No new reporting-internal capability was found or introduced.

| Capability | V1 bundles | Scope and server evaluators | Client evaluators and consumers |
|---|---|---|---|
| `reports.view` | Owner, Manager, Accountant | Per unit in `reporting_primitives`, `reporting_snapshot`, `reporting_newer_than`; unscoped for consolidated primitives. Anywhere in `owner_ledger_snapshot`. | `CachedReportingSource`, `ScopeCachePurge`, `OwnerSettlementRepository`, `OwnerSettlementPreviewService`; desktop Analytics/Reports navigation. Session-watching reporting/owner providers supply the principal. |
| `revenue.view` | Owner, Manager, Accountant | Same three reporting functions; `may_read_revenue_attachments`; tenant/capability-filtered `revenue_document`, `revenue_component_detail`, `revenue_period_contributions` and revenue RLS. | Cached reporting read, capability-loss purge, consolidated owner-preview gate. No independent reporting navigation grant. |
| `expense.view.all` | Owner, Manager, Accountant | Same three reporting functions; `expense_visible_units`, `may_read_expense`, and their expense document/allocation/contribution/attachment policy consumers. | Cached reporting read, capability-loss purge, consolidated owner-preview gate. |
| `expense.view.own` | Owner, Data Entry | `expense_visible_units`, `may_read_expense`; own authorship plus unit scope, propagated through expense policies/views and attachment readers. Does not satisfy P&L. | No P&L evaluator accepts it; catalog/template only. Operational expense visibility is server-filtered. |
| `owner_settlement.view` | Owner only | `owner_ledger_snapshot`; settings SELECT policy (alternative: `owner_masters.manage`). Anywhere for this whole-organisation dataset; no partial settlement. | Repository, preview service, owner-cache purge; desktop Owner Settlement and mobile More/masters entry. Provider/service also refuse direct access. |
| `owner_ledger.view` | Owner, Accountant | `owner_ledger_snapshot`; SELECT policies on owners, ownership shares, family members and owner ledger. `has_capability_anywhere` intentionally permits Accountant's scoped assignment to read the whole owner ledger (D-200). | Owner repository, preview service, owner-cache purge and authorised ledger restoration. Does not by itself permit settlement. |
| `reports.export`, `reports.print` | Owner, Accountant | Explicit D-139 exemptions; no shipped evaluator. | No implementation in Slice 7; Phase 7 remains deferred. |

Related configuration authority: `owner_masters.manage` gates the unscoped audited
`owner_settlement_start_set` writer and settings reads. `owner_masters.view` gates owner
and family-name reads, not shares or balances. Neither substitutes for settlement authority.

The three reporting transports use the public capability helpers, which resolve current
organisation, active profile/grants and scope. `reporting_snapshot` and `reporting_newer_than`
may transport independently authorised property caches together: that does **not** grant
permission to request a consolidated P&L. `reporting_primitives` and the local report
adapter separately enforce that stronger boundary.

Desktop navigation lives in `lib/app/shell/desktop_shell.dart`; mobile settlement entry in
`lib/features/masters/presentation/masters_page.dart`. Reporting routes remain placeholders.
The owner page consumes the preview service/refresher and repository through
`lib/app/providers.dart`. Navigation is presentation, never the financial read boundary.

## P&L and owner boundary results

| Authority | Unit P&L | Consolidated P&L |
|---|---|---|
| All three D2 capabilities for the requested unit | Allowed | Not implied |
| Missing `reports.view` | Refused; both sides unavailable | Refused |
| Missing `revenue.view` | Refused; revenue unavailable | Refused |
| Only `expense.view.own`, not full expense authority | Refused; expense unavailable | Refused |
| Wrong unit | Refused | Refused |
| Two independently scoped complete grants | Each individual unit allowed | Refused |
| All three capabilities unscoped | Allowed | Allowed |

Live administrative fixtures removed each capability independently, while retaining unit
access, exercised both units and consolidation as `authenticated`, and rolled back every
authority change. A two-scope fixture proved each single-unit positive and the consolidated
negative. Owner snapshot controls independently removed `reports.view`, `owner_ledger.view`
and `owner_settlement.view`: authority was false and movements, owners, ownership shares,
family members and start date were null. Assertions used `IS DISTINCT FROM` so missing
JSON keys cannot make a negative control pass accidentally.

Host production-wiring tests independently prove local unit positives, missing-capability
refusals, wrong-unit and consolidated refusal, plus direct owner repository refusal with
retained sensitive cache. The engine refuses missing coverage; primitive placeholder zeros
never become a partial P&L. Owner preview additionally requires unscoped consolidated P&L
authority; Accountant retains operational ledger access but cannot read settlement.

## D-070 and D-074

Confirmed capability loss purges this person's affected unit caches even when both unit
masters remain accessible. Coverage/snapshot markers are removed before contributions in
the same transaction. Another person's rows are not evidence of this capability change.
Property removal retains the established broader property-purge semantics. Network failure,
unavailable refresh and stale/offline authority are not confirmed revocations and purge
nothing. Actor-owned pending work remains protected by the existing doctrine/tests.

Sign-out now finds reporting-only unit IDs as well as master/owner-ledger IDs. Owner-keyed
P&L, freshness and settlement facts do not transfer to the next principal. OA-1 global owner
master tables remain unwritten under the existing D-216 guard. Host revocation/shared-device
tests and the live owner shared-workstation test are green. A newly authorised person must
obtain their own synchronised cache.

## API surface and provenance

Migration **20260912100000**, `remove_dead_expense_whole_org_helper`, was first executed
with ROLLBACK, then applied with its ledger row in the same administrative transaction.
Live preflight found no function or policy callers of `expense_sees_whole_org()`, and the
client search found none. Its authenticated EXECUTE grant was unnecessary. The function is
now absent, without CASCADE; the reviewed API drops from 58 to **57** functions.

The ledger stores the migration SQL itself. Its LF-normalised full-source MD5 is
`54951899d004206b58330ff683a21f18`, equal to the repository file, not merely its name.
The SQL editor introduced CRLF during transfer; normalising CR restored exact identity
before deployment. All **101** `(version, name)` ledger entries match the documented
ledger, including the previously recorded grouped-file provenance. Sorted entries joined
by LF have MD5 `c24732d3a792a8ea09ddfd1d5712a02f`.

Live catalogue checks:

- PUBLIC EXECUTE in public/app: **0**; anon EXECUTE: **0**.
- Anon SELECT on public tables/views: **0**.
- Client INSERT/UPDATE/DELETE/TRUNCATE privileges in public: **0**.
- Public base tables lacking RLS: **0**; public function overloads: **0**.
- Definer functions lacking a pinned search path: **0**.
- Three reporting functions and owner snapshot: invoker, `public, pg_temp` search path.
- Settings writer: definer, empty search path, explicit qualified references.
- Core expense/revenue document/component raw reads: **0**. The two expense allocation
  tables intentionally retain SELECT under the approved tenant/unit/authorship RLS; they
  are not an accidental unrestricted grant.
- Five financial projection views retain `security_barrier=true` and explicit tenant and
  capability predicates. Supabase's generic definer-view warnings do not mean these views
  lack an authority boundary; the definitions and live refusals were inspected.
- Owner SELECT policies preserve the distinct master, ledger and settlement capabilities.
- Latest reviewed API assertions passed on the actual post-drop catalogue, both directions.

## D-139 guard controls

The active-function scanner now handles DROP and later recreation, with a self-test.
The production capability guard still reads the latest exemption declaration, recognises
named dollar tags, and excludes line comments and DO assertions from evaluators.
Its narrow three exemptions remain export, print and settings management.

A temporary scanner-only migration planted a synthetic granted capability, an older
exemption containing it, a newer exemption omitting it, and mentions in a comment/DO
assertion. The **actual production guard failed RED** naming that capability. Adding a
`$fn$` runtime evaluator made it GREEN. The temporary file was removed, never deployed.
Live function-body/policy inspection found no non-exempt dead grant; a synthetic missing
evaluator was detected. These are structural controls, not substitutes for live behavioural
fixtures; both were used.

## Development start date and test teardown

`2026-05-01` was a disposable OA-3 fixture, not production truth. The live suite creates it
through the audited RPC. Other references were a local SQLite wiring fixture, an invalid
share test, and an unrelated expense-period device expectation. No persistent dev baseline
requires it. No migration or production date was rewritten or chosen.

The administrator removed the exact dev organisation/date row before the final serial
live run and again afterward. Final settings row count: **0** — "Settlement start date
not configured". The audit/financial histories were not deleted.

`supabase/tests/owner_settlement_dev_fixture_cleanup.sql` preserves the tested cleanup
operation. An acceptance run owns both setup and administrative teardown: verify the dev
project, establish the absent baseline, run owner suites serially, and run cleanup in the
runner/operator's finally phase even on failure. Client tests deliberately have no privileged
reset RPC or credential; do not grant them DELETE to automate teardown. A plain client-only
invocation is not the complete acceptance workflow.

Final live baseline: **0** open revenue, **0** open owner movements, **0** open reporting/OA-3
acceptance expenses; **7** role-grant rows (**5** active), same four role bundles. Voided
acceptance financial history remains auditable. Ownership-history fixtures are preserved,
including the historical non-50:50 refusal controls; this cleanup does not erase them.

## Verification and boundary

Host suite: **1,711 passed** (19 more than OA-3). Relevant live suite run with
`--concurrency=1`: **101 passed, zero skipped** — reporting 13, parity 29, owner accounts
31, owner completeness 8, settlement 20. The earlier run was 100 + 1 skipped because the
fixture already existed; the final run tested the absent baseline live.

Format: **263 files, zero changes**. Analyzer: no issues. Credential scan: working tree and
Git history clean. `git diff --check`: clean. One attempted concurrent host/live invocation
failed on a Windows SQLite DLL lock before tests; rerunning the host suite after live
completion passed. No test expectation was loosened to conceal it.

No new platform build or device-acceptance claim is made by this security-only slice.
Slice 8 may begin from this security foundation after its own scope handoff; it was not
started. Finalized Owner Statements, exports/printing and the production start-date decision
remain outside this closure.
