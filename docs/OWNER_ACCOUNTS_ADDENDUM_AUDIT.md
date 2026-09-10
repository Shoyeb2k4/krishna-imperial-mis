# Owner Accounts & Settlement — Architecture Addendum Audit

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2** (unamended)
Project Lead / Product Decision-Maker: Shoyeb Akhtar
Status: **AUDIT AND PROPOSAL ONLY — nothing here is binding, nothing is implemented.**
Approved 2026-09-09 and built as **Phase 5 OA-1 — Owner Accounts Foundation**. This
document is left exactly as it was written, because it is the evidence OA-1 was built
from; where it and the as-built disagree, `PROJECT_STATUS.md`, `ARCHITECTURE.md` §33 and
`DECISIONS.md` D-189 … D-203 are authoritative.
Date: 2026-09-08
Checkpoint audited: Phase 5 Slices 1–6 complete, `5262d8f` · `0a20436`, local schema **v18**

This document is not an amendment to `SHOYEB_MASTER_SPEC.md` and creates no decision in
`DECISIONS.md`. It records what the repository actually contains, what the newly stated
business model costs, and the smallest correct way to add it. Every claim about the code
below was read out of the tree or the migrations at this checkpoint.

---

## 1 · Executive conclusion

**This is additive greenfield work, not a corrective.** Nothing in the repository models an
owner, a withdrawal, a non-chargeable bill, a family member or a settlement — proven by
exhaustive search, not by recollection. No accepted architecture has to be reopened, and
**no accepted figure moves**.

Five conclusions carry the rest of the report.

1. **Owner Settlement is a second financial domain that consumes the P&L and never enters
   it.** `Pnl.compute` takes exactly two sides, both required and non-nullable, and refuses
   through an exhaustive switch over both at once (D-163). Adding a third dataset there
   would destroy the compiler-guaranteed exhaustiveness that is the whole of D-163's
   enforcement. The Owner Settlement calculator therefore takes a finished `PnlResult` as an
   **input**. §41's invariant is then structural rather than remembered.

2. **The Owner Ledger is a third contribution dataset, and the accepted reporting
   architecture already has the shape to carry one.** `reporting_coverage_markers` is keyed
   `(owner_user_id, business_unit_id, dataset, financial_year)` and `dataset` is already a
   string over a closed vocabulary with exactly two members. `reporting_snapshot` returns
   its two datasets as two `jsonb_agg` sub-selects **inside one SQL statement**; a third
   sub-select is additive and preserves the one-statement invariant the migration asserts.
   Slice 6 is not defective — it is extensible, which is a different thing (§46).

3. **There is one real risk in the existing code, and it is latent rather than live.**
   An expense document carries **no type discriminator**. `expense_categories.nature` exists
   with a four-value CHECK and is **evaluated by nothing** in any report, view or RPC. So
   nothing today structurally prevents somebody creating an expense category called "Owner
   Withdrawal" and booking ₹50,000 into it, which would reduce Operating Profit. No such
   category exists in the seed or on the server, so this is a **guard to add**, not a defect
   to fix (§5, §44).

4. **Entering an NC bill through the current Revenue path would inflate Gross Sales, GST and
   Net Sales.** Not hypothetically: Restaurant's live rule is 5% inclusive, so a ₹3,250 NC
   bill entered as Restaurant revenue would add gross 325000, tax 15476 and net 309524 paise
   to the P&L, and `revenue_period_contributions` carries no discriminator that could take it
   back out. The Owner Ledger must be the source, and NC must never be a revenue category
   (§8, §45).

5. **The old Slice 7 must be revised, and it must not run first.** Its entire subject is the
   reporting capability model. Owner Settlement adds capabilities to that same model and adds
   the most privacy-sensitive surface in the product. Building it now and again in three
   slices' time is duplicated work on the one boundary that has to be right once — and this
   repository has already paid for exactly that (D-184 → D-187, where a reporting boundary
   shipped under-authorized and had to be corrected in its own migration). **Recommendation:
   the Owner Accounts foundation and ledger land first; Slice 7 then secures P&L and Owner
   Settlement together in one pass** (§30).

**One concrete implementation trap, found by reading the migrations.** Three shipped
migrations carry a deploy-time guard:

```
    if v_src ~* '\mowner\M' or v_src ~* '\mmanager\M' or v_src ~* '\maccountant\M'
       or v_src ~* '\mdata_entry\M' then
      raise exception '% branches on a role name rather than a capability';
```

A capability literal spelled `'owner.settlement.view'` inside `reporting_snapshot` or
`reporting_primitives` **would trip that guard**, because the bare word `owner` ends at the
dot. `owner_ledger` would not, because the underscore is a word character. This is a false
positive waiting to happen against a guard that is otherwise correct and should stay strict.
The recommendation in §22 is to name the capabilities with underscored first segments
(`owner_ledger.view`, `owner_settlement.view`) and to record *why*, so nobody later tidies
them into dots and breaks a deploy for a reason nobody can find.

---

## 2 · Current repository facts

Everything in this section was read at this checkpoint. Nothing is inferred from
documentation.

### 2.1 The concepts being added do not exist

An exhaustive case-insensitive search across `lib/`, `supabase/`, `test/`,
`integration_test/` and `docs/` for `petpooja`, `non-chargeable`, `owner_account`,
`withdrawal`, `drawings`, `settlement`, `proprietor` and `partner` returns:

* the D-057 governance lines stating the project lead is **not** the proprietor;
* three unrelated uses of "withdrawal" describing an authority-grant being withdrawn in the
  live test suites;
* `Petpooja integration` appearing **once**, in spec §29, as a V1 **non-goal**;
* spec §198: *"Revenue does not carry a payment/settlement model in V1."*

There is no owner entity, no ledger, no family member, no NC concept, and no code that
would have to be changed to remove one. This is greenfield.

### 2.2 The Revenue workflow, as it actually is

Answering §8's questions from the code:

| Question | Answer, from the repository |
|---|---|
| Is CCR Restaurant revenue manually entered as a daily summary? | **Yes.** `RevenueEntryPage` — property → category → amount → Save. `RevenueEntryKind.dailySummary` is the default and the only kind the application ever constructs. |
| Is there a Petpooja API or import? | **No.** No import endpoint, no POS client, no integration code of any kind. `RevenueEntryKind.import` exists as a schema value with **no producer** anywhere in `lib/`. |
| Is the user expected to type a POS total? | **Yes** — one number per configured value band, and today every category resolves to a single generic rule, so it is one field. The label follows the basis *and* the treatment (D-097). |
| Does the Revenue model know about NC? | **No.** A revenue entry names one business unit and one revenue category; there is no chargeable/non-chargeable dimension on the header, on a component, or in the five tax dimensions. |
| Can current Revenue categories distinguish paid revenue from NC? | **No.** The four seeded categories are Restaurant and Nandbhog (CCR), Room and Banquet (HKI). |
| Would entering NC through Revenue inflate Gross Sales / GST / Net Sales? | **Yes, exactly and provably** — see §1 conclusion 4. |
| Is a separate Owner Account ledger the correct source? | **Yes**, and it is the only source that does not either inflate revenue or reduce Operating Profit. |

### 2.3 The Expense engine has no transaction-type discriminator

There is no `expense_kind`, `transaction_type` or `document_type` column anywhere, locally
or on the server. `expense_categories.nature` exists —
`check (nature in ('operating','payroll','utility','other'))`, defaulting to `'operating'` —
and is **read by nothing**: no policy, no view, no RPC, no reporting query, no Dart code
outside the seed and the master repository's create signature. It is a label.

### 2.4 The reporting architecture, and where a third dataset fits

* `ReportingDatasetSide` is an enum of two values with an explicit `wireName`
  (`revenue`, `expense`) — a closed vocabulary that is already parameterised.
* `reporting_coverage_markers` is keyed `(owner_user_id, business_unit_id, dataset,
  financial_year)`. A third dataset is a third value, not a schema change in shape.
* `reporting_snapshot(uuid[], bigint, bigint)` builds one `jsonb_build_object` containing
  `snapshot_id`, `server_time`, `units`, `revenue`, `expense` — **one SQL statement**, and
  the invariant asserts `lanname = 'sql'` and at most one semicolon. It does **not** assert
  "exactly two datasets".
* `CacheOwnership.canonicalReportingCache` already exists with `isOwnedByUser => true`, and
  `CacheClassification` is asserted against `AppDatabase.allTables` **in both directions** —
  so a new local table *cannot* be added without a deliberate ownership decision.
* A catalogue-wide invariant with **no exemption list** requires every `public` table
  carrying `change_seq` to advance it on UPDATE (D-177). A new owner-ledger table inherits
  that protection automatically.

### 2.5 Money, shares and the arithmetic already available

`Money` is integer paise with `Money.sum`. Basis points are already the project's rate
vocabulary (`rate_bp`, `taxRateBasisPoints`). Largest-remainder distribution is already the
documented rule for splitting an amount so it reconciles exactly (`ARCHITECTURE.md` §6.5).
**50% = 5000 basis points is consistent with existing convention and needs no new type.**

### 2.6 Role templates auto-grant to Owner

`RoleTemplates.owner = {...Capability.values}`. Every capability added to the enum is granted
to the application `Owner` role automatically. Manager, Accountant and Data Entry are
explicit sets and need explicit decisions (§33).

---

## 3 · Phase 1 impact — **none (pure reuse)**

| Foundation | Impact | Evidence |
|---|---|---|
| `Money`, integer paise, Indian grouping | **None** | Owner amounts are amounts. |
| `BusinessDate`, per-unit timezone and 05:00 cut-off | **None** | An NC bill and a withdrawal each have a trading day, derived by the existing rule. |
| Encrypted local database, per-platform key management | **None** | New tables live in the same encrypted database. |
| Sync states, outbox, idempotency, `row_version` | **None** | §25 reuse; `MutationOp` already has create/update/void. |
| Audit trail, `app.stated_reason` | **None** | A new mandatory reason **joins** the five (spec §14.1) rather than inventing a standard — and the `reason_required` search invariant will require it to. |
| Native platform foundations | **None** | No new plugin, no new permission. |

**Nothing in Phase 1 is rebuilt or corrected.** One new *use* of an existing mechanism:
largest-remainder distribution, already specified, applied to a profit split.

---

## 4 · Phase 2 impact — **additive addendum, not a reopening**

Two new masters and a capability block. Neither disturbs the hierarchy, the composite
foreign-key ladder (D-040), the authority snapshot, D-070 or D-074.

| Area | Impact |
|---|---|
| Business hierarchy (unit → dept → section → category) | **Unchanged.** An owner is not a node in it. |
| Master architecture (stable id, immutable code, label snapshot — D-035, D-038) | **Extended**: the Owner and Family masters follow the same three rules. |
| Capability catalogue | **Additive** — see §22. |
| RLS, `has_capability`, per-unit scoping | **Extended** with new policies in the established shape (`security definer` predicate, never an inline base-table read — D-045, D-109, D-174). |
| Authority snapshot, `ReferenceSync` | **Extended**: Owner and Family masters are reference data and synchronise the same way. |
| D-070 / D-074 | **Unchanged doctrine, extended coverage** — §21. |

This is an **addendum**, in the shape of the Phase 2 acceptance addendum (D-058, D-059):
its own commit, its own migrations, Phase 2's closure record untouched.

---

## 5 · Phase 3 impact — **documentation plus one additive guard. No corrective.**

**Owner withdrawals and NC are not business operating expenses, and the Expense Engine does
not currently misclassify them — because it has never been asked to.** No such expense exists
on `krishna-mis-dev`; no such category exists in the seed. Calling the absence of a
newly-discovered feature an old defect would be wrong, and §44 is right to forbid it.

What is true is that the engine offers **no structural resistance**. Masters are configurable
in-app by design (spec §3), so an authorised administrator can create an expense category
named "Owner Withdrawal" today, and `expense_period_contributions` would carry it straight
into Operating Profit. `nature` would not stop it, because nothing evaluates `nature`.

**Smallest correct guard, three parts, all additive:**

1. **The Owner Ledger gives the act a home.** The strongest guard is that the correct place
   to record a withdrawal exists and is easier to reach than the wrong one. Most of the risk
   closes here.
2. **A documented and asserted rule**, in the shape this project already uses: a
   deploy-time invariant asserting that no live `expense_categories` row carries a reserved
   owner-drawings code, and a host test asserting the same over the seed. Cheap, and it
   fails loudly rather than being a comment.
3. **`nature` gains a value, and — this is the point — an evaluator.** Adding
   `'owner_drawings'` to the CHECK without anything reading it would create a fifth
   instance of the family this log keeps recording (D-068, D-071, D-077, D-103, D-116). If
   it is added, `expense_period_contributions` must exclude it and a positive control must
   be seen to fail. **Recommendation: do not add it in V1.** Parts 1 and 2 close the risk;
   part 3 adds a rule that must then be maintained for a case that should not arise.

**No Phase 3 corrective. `expense_update`, `expense_void`, the allocation model and the
period contributions are untouched.**

---

## 6 · Phase 4 impact — **untouched under Scenario A; one additive control under Scenario B**

**Owner NC is not ordinary customer-paid revenue, and Revenue does not need to know it
exists** — provided operators enter chargeable sales only.

* **No change to the revenue document model, the component model, or the five tax
  dimensions.** NC is emphatically **not** a sixth dimension and **not** a fifth revenue
  category: either would put a non-revenue concept inside the tax resolver, which D-079
  bounds deliberately.
* **No change to tax architecture.** No new rule, no new band, no new subtype. The verified
  four-rule FY 2026-27 baseline stays exactly as it is.
* **No change to `revenue_period_contributions`.**

The only Phase 4-adjacent addition is the **detective control** described in §18, and it is
a control on the *entry surface*, not a change to the revenue model.

---

## 7 · Phase 5 Slices 1–6 impact

| Layer | Classification | Why |
|---|---|---|
| Slice 1 — canonical-only predicate, `may_read_expense` (D-168, D-169) | **Unchanged** | The Owner Ledger adopts the same canonical-only rule (§13); it does not alter this one. |
| Slice 2 — `domain/finance`, `Pnl.compute` (D-175, D-176) | **Unchanged** | Owner Settlement is a **new sibling file** consuming `PnlResult`. The purity guard extends over it unmodified. |
| Slice 3 — `LocalReportingEngine`, `ReportingFactsSource` port | **Extension required** | `UnitReportingFacts` gains an owner-movement side, or — preferred — a **separate** `OwnerLedgerFactsSource` port beside it (§19, §24). |
| Slice 4 — reporting cache, `ReportingSync`, delta, watermark (D-178 … D-182) | **Extension required, additive** | A third dataset in the existing vocabulary. The document-grain replacement rule, the year bound, the void-drop and the `min(generation)` watermark all apply unchanged. |
| Slice 5 — `reporting_primitives`, `RemoteReportingEngine`, D-020 parity (D-183 … D-187) | **Extension required** | Owner movements need their own authoritative aggregate and their own parity assertions. The **boundary contract is reused verbatim**: `security invoker`, one statement, per-unit capability, null-not-zero. |
| Slice 6 — coherent snapshot, freshness, closed periods (D-188) | **Extension required, additive** | A third `jsonb_agg` sub-select inside the existing single statement (§19). |

**Slice 6 is not defective.** It guarantees that the datasets it certifies belong to one
snapshot. Owner Ledger did not exist when it was built, and the mechanism it installed is
precisely the one that makes adding a third dataset safe. Labelling it defective would be
wrong and would misrepresent the record.

---

## 8 · Owner Master design

```
owners
  id                  uuid, client-generated (D-008)
  org_id              uuid
  code                text, IMMUTABLE (D-035)
  display_name        text, renameable under D-038's cosmetic-rename rule
  active              boolean
  created_by, created_at, updated_at, row_version, change_seq, voided/archived_at
```

**Ownership share is a separate, effective-dated table** — not a column on the owner. A
share is a fact about a *period*, and putting it on the owner makes every historical
settlement depend on today's value, which is the harm §37 exists to prevent.

```
ownership_shares
  id, org_id, owner_id
  share_basis_points  integer, 1..10000
  effective_from      date
  effective_to        date, nullable (open-ended)
  audit metadata
```

**Two invariants, both database-enforced:**

1. For any date, the shares of all applicable rows sum to **exactly 10000**. Enforced by a
   validating trigger plus the `(org)` advisory-lock pattern D-095 established, because a
   constraint alone cannot see a concurrent write-skew that lands two half-valid sets.
2. Periods for one owner do not overlap — `EXCLUDE USING gist`, the pattern already used
   for premises tax statuses (A2).

**Organisation-wide, not per-unit.** Recommended, with the reasoning stated: the repository
models one `org_id` with business units as children; nothing anywhere models per-unit
ownership; and the project lead's stated fact is a single 50:50. The 50:50 therefore applies
to **consolidated CCR + HKI Operating Profit** as one organisation-wide settlement. This is
recorded as a recommendation and the narrow structural question is flagged in §29 —
*whether the two properties are owned in the same proportions by the same two people* is a
business fact the repository cannot settle.

**No Owner A / Owner B enum, anywhere.** Placeholders live only in this document.

---

## 9 · Family Member design

```
owner_family_members
  id, org_id
  owner_id            the linked owner
  display_name
  relationship_label  optional, free text — a label, never a rule input
  may_use_nc          boolean
  active
  effective_from, effective_to
  audit metadata
```

**Invariants:**

* One active family member identity belongs to **exactly one owner at a time** — enforced by
  a non-overlapping-period exclusion constraint per family member, not by convention.
* **Reassignment never rewrites history.** This is guaranteed structurally rather than by
  care: every NC movement **snapshots the resolved `owner_id` at acceptance** (§10). The
  mapping is a lookup at entry, not a join at report time. This is the same discipline that
  makes a revenue component explainable after its tax rule is superseded (D-080, D-122), and
  it is the single most important line in this section.
* An owner is also a consumer. **Recommendation:** every owner gets an auto-provisioned
  self-member row rather than the NC form offering "an owner or a family member", so the NC
  entry has exactly one kind of person-reference and no branch.
* **Family members are not MIS users** (§34). `owner_family_members` has no
  `auth.users` foreign key and no login. If a family member is ever also a user, that is a
  deliberate, separate link and not an inference from a name.

---

## 10 · Owner Ledger design

One table, one grain: **one movement**.

```
owner_ledger_entries
  id                        uuid, client-generated
  org_id
  owner_id                  RESOLVED AND SNAPSHOTTED at acceptance
  movement_type             text, closed vocabulary (§15)
  business_unit_id          source attribution (§35) — required
  business_date             derived under the unit's cut-off (D-019, D-067)
  business_date_source      derived | corrected (D-143)
  amount_minor              bigint, ALWAYS POSITIVE
  txn_number                server-issued on acceptance, own FY sequence (KI-OWN-…)

  -- NC only
  family_member_id          who consumed; null for a movement with no person
  nc_bill_reference         the printed bill number

  -- withdrawal only
  payment_method_id
  collected_by_family_member_id   optional (§14) — attribution NEVER moves

  reference_number, remarks
  created_by, captured_at, created_at, updated_at
  row_version, change_seq
  voided_at, void_reason
  scope_revoked_at          local only (D-070)
```

**Three design rules worth stating explicitly.**

**Amounts are positive; direction comes from the type.** A signed amount invites a negative
withdrawal, which is nonsense, and makes every aggregate depend on remembering the sign
convention. `movement_type → direction` is a pure function in the domain layer, tested once.

**`owner_id` is snapshotted, not joined.** The whole of §11's reassignment invariant.

**`collected_by_family_member_id` is metadata and is never an attribution.** The financial
debit is always `owner_id`. A structural test asserts no aggregate ever groups by it.

**Bill-level, not item-level (§13).** Audited: nothing in the project requires item detail.
Spec §29 excludes recipe costing, inventory and POS replacement, and §6's settled valuation
rule — *the full printed bill value* — makes item detail financially irrelevant, because no
figure in the settlement is derived from it. Item detail lives in the original bill, the
POS, and the optional attachment. **Recommendation: bill-level V1.**

---

## 11 · NC workflow

```
        Business date        pre-filled from the unit cut-off, editable as today
        Business unit        Crystal Canopy Rooftop (constrained to units the actor may enter)
        Person               ONE picker — owners and family members in one list
        → linked Owner       DERIVED, never chosen, and re-derived server-side
        NC bill reference    the printed bill number
        Amount               full printed bill value (settled, §6)
        Remarks              optional
        Attachment           optional, reusing D-147's shared pipeline unchanged
        Save
```

**The operator chooses a person and never an owner.** That is §12's requirement and it is
also the security design: the family→owner mapping is itself sensitive linkage, and an
operator who must select the owner has been told which family belongs to which owner.

**The server re-derives the owner and refuses on disagreement.** The client sends the person
and *declares* the owner it displayed; the server resolves the mapping as at the business
date and refuses on mismatch. This is `revenue_create`'s D-114 contract applied unchanged,
and it exists for the same reason: an entry prepared under a mapping that has since changed
would otherwise be silently re-attributed under an operator who approved something else.

**Offline: yes** (§26). NC creation depends on the owner/family mapping and on nothing that
can go stale in a tax sense, so **D-112 does not apply and must not be reused** — it is a
tax-correctness gate for revenue, and restating it as a general TTL is exactly what D-112's
own record forbids. The mapping is reference data; if the device holds no confirmed mapping
for the chosen person, the save is **refused and nothing is queued**, in D-086/D-113's shape.

---

## 12 · Withdrawal workflow

```
        Owner                explicit — a withdrawal has no consuming person to derive from
        Business unit        the source (§35)
        Business date
        Amount
        Payment method
        Reference number     optional
        Collected by         optional family member — metadata only
        Remarks, attachment  optional
        Save
```

**Offline: yes, through the ordinary pending → canonical workflow** (§26). The local write
succeeds and is visible operationally; it contributes **zero** to canonical settlement until
the server accepts it (§13). The architecture supports this today with no change: it is what
an expense already does.

**Approval is deliberately not designed here.** Spec §26 keeps the approval framework
modular and disabled in V1; whether a withdrawal needs an Accountant or Owner counter-sign
is a Product Lead decision and is listed in §29 rather than assumed either way.

---

## 13 · Canonical-only rules

**Identical to the P&L rule, not a variant of it** (§27, D-167, D-168):

```
        contributes  ⟺  txn_number IS NOT NULL      -- server-accepted
                    AND  voided_at IS NULL           -- D-006
                    AND  scope_revoked_at IS NULL    -- D-070, D-074
```

A pending ₹50,000 withdrawal changes **nothing** in the canonical Owner Settlement. It is
visible on the operational owner-ledger surface with its sync state, which is where an
operator's attempt belongs.

**And the rule is made unnecessary rather than remembered**, exactly as Slice 4 did: the
canonical owner-ledger cache is written only by the synchroniser and holds only accepted,
non-voided movements, so the settlement query has nothing to filter. A single-writer test
over `lib/` enforces it.

**No provisional settlement in V1.** A "including pending" view is a real idea and needs its
own vocabulary and its own decision; inventing one here would ship a second, softer
definition of an owner's balance with nobody's name on it.

---

## 14 · Owner Settlement domain and formulas

A new pure file, `lib/domain/finance/owner_settlement.dart`, under the **existing** purity
guard: no Drift, no Supabase, no Flutter, no Riverpod, no `double`, no `/`.

```
        OwnerSettlement.compute(
          pnl:        PnlResult             ← already computed, already canonical
          shares:     OwnershipShareSet     ← effective-dated, sums to 10000 bp
          movements:  Iterable<OwnerMovement>
          opening:    Iterable<OwnerOpeningBalance>
        ) → OwnerSettlementOutcome
```

### The allocation, exactly

```
        entitlement(owner) = distribute(operatingProfit, sharesInBasisPoints)
```

`distribute` is **largest-remainder** over integer paise, which the project already
specifies (`ARCHITECTURE.md` §6.5) and already relies on for allocation splits.

**Why this matters and is not pedantry.** An Operating Profit of 100000001 paise split 50:50
is 50000000.5 each. Truncation loses a paisa; rounding both up invents one. Largest-remainder
gives 50000001 and 50000000, and the permanent invariant holds exactly:

```
        Σ entitlements  ==  distributable Operating Profit        (to the paisa, always)
```

Asserted, with a control that is seen to fail. **Negative Operating Profit distributes the
same way** — a loss is allocated, not clamped — and the remainder rule must be tested on the
negative side too, because rounding a signed value toward or away from zero is the D-175
distinction and getting it wrong is silent.

### The settlement

```
        closing(owner) = opening(owner)
                       + entitlement(owner)
                       − withdrawals(owner)
                       − nc_consumption(owner)          incl. all linked family members
                       − settlement_paid(owner)
```

### The worked control from §17, in paise

```
        Operating Profit                       100000000
        Owner A entitlement  5000 bp            50000000
        Owner B entitlement  5000 bp            50000000

        Owner A withdrawal                       5000000
        Owner A NC (own 800000 + spouse 700000 + son 500000)
                                                 2000000
        Owner A movements                        7000000
        Owner A closing                         43000000
        Owner B closing                         50000000

        43000000 + 50000000 + 7000000  =  100000000        ✓ exact
```

### Refusals, in `Pnl.compute`'s shape

The settlement is refused, never half-rendered, when: the underlying P&L was refused; shares
do not resolve to exactly one applicable set covering the whole range (§37); shares do not
sum to 10000; owner-movement coverage is not complete; or the report covers no permitted
owner. **A missing owner side is never an owner balance of zero** — D-163's rule, applied to
the third dataset.

---

## 15 · Period-only vs carry-forward — recommendation

**Recommended: Owner Current Account with carry-forward** — which is the project lead's
stated preference, and it is also the more honest model. §20's scenario is the argument:

> An owner may withdraw money before or after a month's profit is formally settled.

Under **period-only**, a ₹50,000 withdrawal taken in August against September's profit is
reported as August overdrawn by ₹50,000 and September fully payable. Both statements are
locally true and the pair is misleading, and neither report tells the reader that the other
exists. Under **carry-forward** the August drawing is simply an August movement and
September opens from it. That is what an owner's current account means.

**And it can be done without turning the MIS into partnership accounting** — this is the
whole of the recommendation, and it turns on one design choice.

**The closing balance is DERIVED, never stored.** No stored running balance, no month-end
posting, no roll-forward job. That removes the entire lifecycle §20 is right to be wary of:
nothing to recompute when a period reopens, nothing to insert twice on a replay, nothing to
drift. It is D-157's argument — *a contribution that carries no decision of its own is
derived, not stored* — applied to a balance.

**The one real cost, stated plainly.** A derived opening balance needs entitlement for every
prior period, which needs a P&L for every prior period, which needs coverage for every prior
period — and on a device that is a growing amount of data and, at inception, history that
does not exist.

**The fix is one ledger movement type, not a stored balance.** An explicit
`opening_balance` movement per owner, dated at the settlement inception date, states the
position the business is starting from. The report then computes from inception forward and
**refuses** if coverage is incomplete anywhere in that span, rather than silently reporting a
balance built from a gap. That is a small, auditable, correctable row — and it is the
difference between a current account and a general ledger.

---

## 16 · Settlement payment — recommendation

**Yes, `settlement_paid` is needed in V1.** §22's reasoning is correct and the failure it
predicts is real: without it, a balance that has actually been paid shows as payable for
ever, and the only way to clear it would be to record a withdrawal — which would be a false
record of what happened.

**It is a distinct movement type, not a distinct subsystem.** Same table, same workflow,
same audit; the type is what separates *"the owner drew money during the period"* from
*"the business settled a computed balance"*. They are not the same business operation and
conflating them would make the annexure unreadable at exactly the moment somebody needs it.

---

## 17 · Finalization and reopen — the smallest safe model

§21's four states can be reduced to **two stored states and one derived warning**, and the
mechanism to do it already exists.

| | |
|---|---|
| **Preview** | Not a state. Computed on demand from canonical facts; no row, nothing to invalidate. |
| **Finalized** | A stored record: the range, the owner figures, and **the snapshot evidence they were computed from** (D-188's `snapshot_id` + `server_confirmed_at` + per-dataset generations). |
| **Needs recalculation** | **Derived, never stored.** Compare the finalized record's evidence against the current canonical state; if reporting contributions in that range carry a generation above it, the finalized statement is displayed with an explicit warning. |
| **Reopened** | Not a settlement state. Reopening a *period* is the existing Owner act with its mandatory audited reason (D-026, D-145); its effect on a finalized settlement arrives through the derived warning above. |

**This is exactly §21's scenario, answered by machinery that already exists.** September P&L
finalized → settlement finalized carrying evidence → September reopened → a correction
accepted → contributions carry a new generation → the finalized statement **cannot** continue
appearing as valid, because the comparison is made every time it is read.

A stored `needs_recalculation` flag would be a second copy of a derivable fact, needing a
writer on every financial mutation path, and it would be wrong the first time somebody
forgot one. Deriving it costs one comparison and cannot be forgotten.

**Finalizing does not freeze figures into a second truth.** The stored record is evidence of
what was agreed and when; the canonical facts remain the canonical facts.

---

## 18 · Revenue / NC reconciliation model

**Scenario A — POS paid-sales total excludes NC. Recommended as the shipped workflow.**

Restaurant revenue is entered unchanged. NC is entered only in the Owner Ledger. No
subtraction, no reconciliation field, no change to Phase 4 at all. Nothing can double-count
because the two figures never meet.

**Scenario B — POS daily total includes NC.**

Do **not** put a subtraction field on the revenue entry form. An operator typing
`POS gross − NC` produces a net number with no audit link to the NC bills that justified it,
and a mistyped NC total would silently misstate revenue with nothing able to detect it.

Instead, an explicit **reconciliation record**, where the NC figure comes from the ledger
rather than from a second keystroke:

```
        POS gross (typed)                        ₹1,00,000
        less NC recorded for this unit/date        ₹3,250   ← SUMMED FROM THE OWNER LEDGER
        = chargeable management revenue           ₹96,750   ← what becomes the revenue entry
```

Refused unless it reconciles, in D-084's tradition. Because the NC total is read rather than
typed, double counting becomes **detectable** rather than merely discouraged, and the
reconciliation is explainable years later.

**Because the repository cannot settle which scenario is real, the recommendation for V1 is
Scenario A plus a detective control**: when NC exists for that unit and business date, the
revenue entry surface says so and asks the operator to confirm the figure excludes it. Not a
silent subtraction — a statement the operator answers. If Petpooja's behaviour is later
confirmed to be Scenario B, the reconciliation record above is an additive slice.

**Actual Petpooja behaviour is an operational question** (§29). The repository proves only
that no integration exists.

---

## 19 · Coherent-snapshot extension

**The extension is one sub-select inside the existing statement.**

```sql
    select jsonb_build_object(
      'snapshot_id', pg_current_snapshot()::text,
      'server_time', now(),
      'units',       …,
      'revenue',     …,
      'expense',     …,
      'owner_ledger', coalesce((                       -- ← additive
        select jsonb_agg(to_jsonb(m) order by m.change_seq)
          from public.owner_ledger_contributions m
          join authority a on … and a.owner_ledger_authorised
         where m.change_seq > coalesce(p_owner_since, 0)), '[]'::jsonb))
```

**This preserves every property Slice 6 established**, and each is checkable:

* still `language sql`, still one statement, still one `pg_current_snapshot()` and one
  `now()` — so all **three** datasets provably belong to one MVCC snapshot. The invariant
  asserts single-statement, not two-dataset; it passes unchanged.
* `reporting_coverage_markers` gains a third `dataset` value in a vocabulary that is already
  a string over a closed set. No schema reshape.
* Document-grain replacement, the financial-year bound, the void-drop and the
  `min(generation)` watermark (D-178 … D-180) apply to the third dataset unchanged.
* A settlement claims a freshness state only when **every required segment — every property,
  all three datasets, every financial year the range touches — carries the same evidence.**
  Otherwise the report is produced with **no freshness claim**, not a third state. D-188's
  rule, extended by one term.

**The naming trap from §1 applies here.** `owner_ledger` as an identifier does not trip the
role-name guard (underscore is a word character); a capability literal `'owner.ledger.view'`
would. See §22.

---

## 20 · Offline and cross-device architecture

**No new synchronisation philosophy. Every mechanism is reused as it stands.**

| Mechanism | Reuse |
|---|---|
| Client-generated UUID v7 identity | unchanged (D-008) |
| Atomic local write + outbox intent in one transaction | unchanged (D-113's shape) |
| `mutation_id` idempotency; `base_row_version` concurrency | unchanged (D-021) |
| `MutationOp` create / update / void_ | **already sufficient** — no new op |
| `entityType` routing | a fourth arm on `RoutingMutationEndpoint` |
| Response loss, restart recovery, backoff, actor filter | unchanged; `ControllableTransport` proves it the same way (D-132) |
| Conflict / Rejected / Review-latest | unchanged (D-126) |
| Server-issued numbering on its own FY sequence | the `KI-REV` pattern (D-085) |
| Canonical reporting cache, per-user keyed | extended by one dataset (D-171) |
| Encrypted local DB, `secure_delete` | unchanged |

**One recommendation carried from Slice 10, because it was learned expensively.** Adopt
**one queued intent per owner-ledger document** (D-125) from the start rather than the
expense engine's fresh-intent-per-edit. Its two failure modes — a correction to a document
whose create then fails transiently becoming a terminal rejection, and two corrections
sharing one base version — are reachable here for the same reasons.

---

## 21 · D-070 and D-074 treatment

Both doctrines apply unchanged, and one of them is the more sensitive of the two here.

**D-074 — user isolation.** The canonical owner-settlement cache is `canonicalReportingCache`
ownership, keyed with `owner_user_id` first in every primary key and index, exactly as the
existing reporting cache is. This matters more than for the P&L: an owner's drawings are the
most sensitive figures in the product, and a shared back-office workstation is the machine
this discipline exists for.

**D-070 — confirmed revocation.** A confirmed withdrawal of owner-settlement authority
**purges the cached owner financial data outright**, marker first. There is no exception to
make, for the same reason the reporting cache has none: nothing in it is anybody's unsent
attempt — every row came from the server and the server returns it when authority returns.

**The operational owner-ledger tables** (this device's own pending movements) are
`scopedFinancialHistory`: purged for a revoked unit **except** rows carrying the actor's own
unsent intent, which are retained, stamped `scope_revoked_at`, excluded from every canonical
read, and reachable only by their own actor. D-070 and D-074 in their existing shape.

**A failed refresh purges nothing.** Unknown is not revoked (D-048 §1).

**And this is enforced rather than remembered:** `CacheClassification` is asserted against
`AppDatabase.allTables` in **both directions**, so the new tables cannot be added without a
deliberate ownership decision. That guard was written after four Phase 3 tables slipped
through unclassified; it will do its job here.

---

## 22 · Security and capability architecture

**Capability-first, and no code anywhere asks whether the current user is Owner A.** §30's
visibility decision — both owners see both sides in full — is expressed as a **capability
granted to both**, never as an identity comparison. A test asserting that no file in `lib/`
compares a signed-in user against an `owners` row is the structural form of §30.

### Proposed set

| Capability | What it permits |
|---|---|
| `nc.create` | record an NC bill |
| `nc.view` | see NC bills operationally — person, bill, amount |
| `nc.edit.all` | correct anybody's NC bill |
| `nc.void` | void an NC bill, with a stated reason |
| `withdrawal.create` | record an owner withdrawal |
| `withdrawal.view` | see withdrawals operationally |
| `withdrawal.edit.all` | correct a withdrawal |
| `withdrawal.void` | void a withdrawal |
| `owner_ledger.view` | **sensitive** — the full ledger for every owner, both sides |
| `owner_settlement.view` | **sensitive** — entitlements, balances, the statement |
| `owner_settlement.finalize` | finalize a settlement |
| `owner_settlement.reopen` | reopen a finalized settlement, with a stated reason |
| `owner_masters.manage` | administer the Owner and Family masters |

**Why underscored first segments.** Three shipped migrations refuse any reporting-boundary
body matching `\mowner\M` as a role-name branch. `owner_ledger` and `owner_settlement` do not
match (the underscore is a word character); `owner.ledger.view` **does**. The naming avoids a
false positive against a guard that is otherwise correct and should stay strict. This is
recorded so nobody later "tidies" the dots back in and breaks a deploy for a reason that will
take a long time to find.

### The staff-privacy line (§31)

**`nc.create` must not imply `owner_ledger.view`, and the design must make that real rather
than declared.** A waiter recording an NC bill sees a person, a bill number and an amount.
They must not see Operating Profit, entitlements, cash withdrawals, the other owner's
activity, or any balance.

Two consequences that are easy to miss:

* **The family→owner mapping is itself sensitive linkage**, which is why §12's person-only
  picker is a security design and not only a usability one.
* **An operational NC list must not become a settlement report by accumulation.** A test
  should assert the operational surface exposes no owner subtotal.

### The settlement report boundary (§40)

**Recommended: `reports.view` AND `owner_settlement.view`, per unit, with the unscoped form
of both required for the consolidated statement.** Not the settlement capability alone.

The reasoning is D-137's, which this project already applies: **capabilities compose, and
none replaces another.** The Owner Settlement statement *contains* the P&L — Section A is
Gross Sales, GST, Net Sales, Expenses and Operating Profit — so a reader who may not read a
P&L may not read it inside a settlement statement either. Requiring only the settlement
capability would create a second route to figures the reporting boundary governs, which is
the exact shape of the D-187 correction.

The consolidated rule mirrors D-164/D-187 exactly: a request naming more than one property is
the organisation statement and needs the **unscoped** form. Two scoped grants do not add up
to an organisation-wide privilege.

### Server enforcement

The owner boundary is `security invoker` over `security_barrier` projections, one statement,
per-unit capability, base tables ungranted, **missing authority returns null and never
zero** — the D-184/D-187 contract reused verbatim rather than re-derived.

---

## 23 · Role templates (§33)

`RoleTemplates.owner = {...Capability.values}`, so the application Owner role acquires every
new capability automatically. The rest need decisions.

| Role | Recommended V1 | Confidence |
|---|---|---|
| **Owner** | everything, automatically | settled by the existing template |
| **Accountant** | `nc.*`, `withdrawal.*`, `owner_ledger.view`, `owner_settlement.view`, `owner_settlement.finalize` | recommended — the Accountant exists to correct and reconcile |
| **Manager** | `nc.create`, `nc.view` only | **needs Product Lead approval** (§29) |
| **Data Entry** | `nc.create` only, or nothing | **needs Product Lead approval** (§29) |

**Explicitly for the Product Lead, and deliberately not assumed:**

* may a Manager record an owner **withdrawal**? (recommendation: no)
* may Data Entry record NC?
* does `owner_settlement.reopen` sit with the Accountant or the Owner alone? (recommendation:
  Owner alone, mirroring `period.reopen`)
* does a withdrawal require an approval step?

**No role name appears in any conditional.** These are seed bundles, not authorization logic.

---

## 24 · Final Owner Statement result contract

A **result contract**, not UI. No PDF, no Excel, no print — Phase 7 owns those (§49).

```
OwnerSettlementResult
  range                    ReportRange
  freshness                ReportingFreshness?    ← null when segments cannot be shown coherent
  finalization             preview | finalized(evidence) | finalized_needs_recalculation

  A · businessPerformance  List<PnlResult> per unit + consolidated PnlResult
                           ← the SAME PnlResult the P&L report renders, unmodified

  B · profitAllocation     List<OwnerEntitlement>
                             ownerId, shareBasisPoints, effectiveFrom/To, entitlement: Money

  C/D · ownerMovements     List<OwnerMovementSummary>
                             ownerId
                             withdrawals, ncConsumption, settlementPaid : Money
                             ncByPerson : List<PersonNcTotal>   ← §18 family aggregation
                             byBusinessUnit : List<UnitMovementTotal>  ← §35 attribution
                             totalMovements : Money

  E · finalPosition        List<OwnerPosition>
                             opening, entitlement, movements, closing : Money
                             closing MAY BE NEGATIVE — never clamped (§19)

  F · reconciliation       Σ closing + Σ movements == distributable Operating Profit + Σ opening
                           reconciles : bool     ← asserted, not assumed

  G · annexure             List<OwnerMovementLine>
                             businessDate, ownerId, personId, movementType,
                             businessUnitId, reference, amount, remarks
```

**Section E terminology (§19):** *Owner Current Account balance*. Positive = **Due to owner**.
Negative = **Recoverable from owner**. Never "loan", never "capital deficit", never "drawings
in excess of profits" — those are statutory claims this MIS does not make.

**Recommended report name (§39): "Owner Profit & Settlement Statement".** It names both
halves — what the business earned, and how it is settled between the owners — and claims
nothing statutory. *"Owner Drawings & Settlement Statement"* is the runner-up and is
narrower: it undersells Section B, which is half the document.

---

## 25 · GST and statutory boundary

**Two things must stay apart, and this document keeps them apart.**

**A · Management-accounting treatment — settled by the Product Lead.** An NC bill is debited
to the linked owner's settlement account at the **full printed bill value**. It is neither
paid revenue nor an operating expense. Operating Profit is not reduced by an owner consuming
value. This is a management attribution rule and it is what the software implements.

**B · GST / statutory treatment — CA / TAX-POLICY CONFIRMATION REQUIRED.** The repository
proves nothing about any of the following, and nothing in this document may be read as a
position on them:

* whether NC consumption by an owner or family member is a taxable supply;
* whether output GST is payable on it, and on what value;
* whether any input tax credit is affected or must be reversed;
* how NC should appear, if at all, in a GST return;
* whether the printed NC bill's tax component has any statutory consequence once the owner
  is debited the full inclusive value.

**One specific interaction is flagged rather than buried.** If the printed NC bill carries
GST at 5%, debiting the owner the full printed value means the owner bears the tax component
too. That is an internally consistent *management* position. Its statutory counterpart is
unconfirmed.

Spec §6.1 and §29 already exclude input tax credit, a GST ledger and GST filing from V1, and
this addendum does not change that.

---

## 26 · Revised Phase 5 implementation sequence

The old twelve-slice plan is not preserved for its number. Slices 1–6 are complete; slices
7–12 are replaced by the nine below.

| # | Slice | Substance | Gate |
|---|---|---|---|
| **7** | **Owner Accounts foundation** | Owner master, ownership shares (effective-dated, sum-to-10000), Family master, owner-ledger local schema **v19**, the pure `owner_settlement.dart` domain with largest-remainder allocation. No network, no reporting, no UI. | purity guard, allocation controls incl. the negative and odd-paise cases, cache classification, migration test |
| **8** | **Owner Ledger boundary and sync** | Postgres tables, RLS, `owner_movement_create/update/void`, `KI-OWN` sequence, audit + mandatory reasons joining the canonical five, outbox, one-intent coalescing, correction, void, cross-device, response loss | live allow **and** deny, idempotency, stale-version, the §29 correction/void matrix |
| **9** | **Owner Settlement reporting** | `owner_ledger_contributions` projection, third dataset in `reporting_snapshot` and the coverage vocabulary, local cache, `OwnerSettlementResult`, local/remote D-020 parity, finalization + derived needs-recalculation | exact-paise parity, coherence, reopen scenario |
| **10** | **Reporting and Owner security** (revised Slice 7) | The complete capability model for P&L **and** Owner Settlement in one pass; `expense_sees_whole_org()` removal; the D-139 exemption review; `may_read_expense` performance | live security matrix incl. staff privacy, positive controls |
| **11** | **Windows P&L + Owner Settlement surfaces** | | widget suites at three sizes, every state |
| **12** | **Android P&L + Owner surfaces** | NC entry is a phone workflow and belongs here | |
| **13** | **Breakdowns and read-only drill-down** (D-166) | including the owner annexure | |
| **14** | **Full live / device / two-client acceptance** | the §28 matrix | |
| **15** | **Closure** | | full gate |

**Two sequencing rules worth defending.**

**7 and 8 are not merged**, although they could be. D-115 is the reason: `revenue_create` had
never successfully created an entry, and thirteen live boundary tests did not notice, because
they proved the boundary and never called the function whose job is to record revenue. A
domain slice and a boundary slice each need their own producer-side proof.

**10 comes after 9, not before.** Slice 10 must secure a surface that exists. Securing the
P&L now and the settlement later means designing the reporting capability model twice, and
D-187 is what that costs.

---

## 27 · What must precede the Windows and Android UI

The project lead's stated preference — *do not build the Owner-facing P&L screen and
immediately redesign it* — is correct, and the audit supports a specific list.

**Must be settled before slice 11:**

1. **The `OwnerSettlementResult` contract** (§24). A P&L screen that later has to grow
   Sections B–G is a redesign, not an addition.
2. **The capability model** (§22), including the staff-privacy split. A screen built before
   the boundary is a screen built against a boundary that may move — D-184 → D-187 in UI
   form, and more expensive there.
3. **The period vs carry-forward decision** (§29). Opening and closing balances are structural
   to Section E, not decoration on it.
4. **The finalization model** (§17). Whether a statement can be finalized changes its primary
   action.
5. **Whether the P&L screen and the Owner statement are one surface or two** — which follows
   directly from the privacy separation in §24 of the brief.

**Need not precede the UI:** the annexure's exact columns, family analytics, the NC
reconciliation record for Scenario B, and every export.

---

## 28 · What may wait

| | Wait until |
|---|---|
| PDF and Excel layout, printing | **Phase 7** |
| `reports.export` / `reports.print` evaluators | **Phase 7** — still legitimately on D-139's exemption list |
| Item-level NC analysis | not planned; §13 recommends bill-level permanently |
| Family-member analytics beyond per-person NC totals | later enhancement |
| `manual_adjustment`, `capital_introduced`, `personal_expense_paid_by_business` | deferred — see §15 of the brief. An adjustment type with no defined semantics is a hole, and the last of the three is a withdrawal by another name in management terms |
| Scenario B reconciliation record | until Petpooja behaviour is confirmed (§29) |
| Approval workflow on withdrawals | spec §26, unless the Product Lead requires it |
| Provisional / including-pending settlement view | needs its own vocabulary and decision (§13) |
| Mid-period ownership change apportionment | §37 recommends prohibiting it in V1 |

---

## 29 · Permanent acceptance matrix

Every row must become a permanent test. Grouped by what it protects.

**Allocation**

* Operating Profit 100000000 → 50000000 / 50000000; Σ == distributable, exactly.
* Odd paise: 100000001 → 50000001 / 50000000, reconciling exactly (largest remainder).
* Negative Operating Profit allocates and is not clamped; rounds symmetrically.
* Shares not summing to 10000 → **refused**, never normalised.

**P&L is untouched (§41 — the load-bearing group)**

* A withdrawal of ₹50,000 leaves Gross Sales, GST, Net Sales, Expenses and Operating Profit
  **byte-identical**. Compared before and after, not asserted.
* NC of ₹20,000 leaves all five identical; Restaurant revenue is not double-counted; the
  Owner Ledger does not reduce Operating Profit.
* A structural guard: `lib/domain/finance/pnl.dart` names no owner concept.
* An expense category carrying a reserved owner-drawings code cannot exist.

**Attribution**

* Owner A's spouse ₹7,000 + son ₹5,000 aggregate to Owner A; neither has an entitlement.
* A withdrawal collected by a family member debits the **owner**; no aggregate groups by
  `collected_by`.
* Reassigning a family member to another owner **does not** move historical NC.

**Combined and reconciled**

* Owner A: 50000000 − 5000000 − 2000000 = 43000000; Owner B 50000000;
  43000000 + 50000000 + 7000000 == 100000000.

**Correction and void**

* NC re-attributed A → B: Owner A restores exactly ₹5,000, Owner B reduces exactly ₹5,000,
  history preserved, **no duplication**.
* Voiding a ₹5,000 NC restores exactly ₹5,000; the row remains, carrying `voided_at`.
* Withdrawal ₹50,000 → ₹45,000 moves the position by exactly ₹5,000.
* Every correction and void carries a stated reason; whitespace-only is refused (spec §14.1).

**Sync, cache and privacy**

* Device A records a canonical movement; device B's settlement sees it after synchronisation.
* A complete cached settlement is readable **offline**, with its freshness state.
* A pending movement contributes **zero**; the operational surface shows it, the settlement
  does not.
* User switch: User B inherits none of User A's owner cache (D-074).
* Confirmed revocation of settlement authority purges the cached owner data; a **failed**
  refresh purges nothing (D-070, D-048 §1).
* A holder of `nc.create` alone sees no profit, no entitlement, no withdrawal, no balance.
* A holder of `owner_settlement.view` without `reports.view` is **refused** (§22).
* Two scoped grants do not yield the consolidated statement; the unscoped Owner does.

**Coherence, periods and history**

* A settlement uses **one** coherent snapshot across revenue, expense and owner ledger; a set
  assembled from two runs carries **no** freshness claim.
* A finalized September settlement, after September is reopened and corrected, is flagged
  **needs recalculation** and never silently valid.
* Closed-period discipline: create, correct and void into a closed period are refused; only
  the Owner reopens, with a stated reason.
* Overdrawn: movements exceeding entitlement produce a negative closing balance, unclamped.
* A future ownership ratio change does not rewrite historical 50:50 settlements.
* Mid-period ownership change → **refused** with a named reason (§37 recommendation).

---

## 30 · Genuine remaining Product Lead decisions

Only questions the repository cannot settle. The decisions in §51 of the brief are **not**
re-asked.

**Business facts**

1. **Canonical Owner A / Owner B names and identifiers** — needed before any master is seeded.
2. **Family member names, relationships, and which are authorised for NC.**
3. **Is the 50:50 one organisation-wide ratio covering CCR + HKI consolidated?** Recommended
   in §8 and consistent with the single-org structure, but it is a business fact about who
   owns what and the repository cannot establish it.
4. **Settlement inception date and opening balances per owner** — required by the
   carry-forward recommendation (§15). Without it there is no honest starting position.

**Product / architecture**

5. **Period-only vs carry-forward Owner Current Account.** Recommended: **carry-forward with
   a derived closing balance and an explicit `opening_balance` movement** (§15).
6. **Mid-period ownership change policy.** Recommended: **prohibit** — an ownership change
   takes effect on a reporting-period boundary, and a range spanning two ownership sets is
   refused. Splitting entitlement by effective date inside a period would require
   apportioning Operating Profit by date, which assumes profit accrues linearly and is a
   claim nobody can support.
7. **Is `settlement_paid` a V1 ledger type?** Recommended: **yes** (§16).
8. **Report name** — recommended: *Owner Profit & Settlement Statement* (§24).

**Authority**

9. **Who may record NC** — Manager? Data Entry? (recommendation: Manager yes, Data Entry by
   decision).
10. **Who may record Owner withdrawals** (recommendation: Accountant and Owner only).
11. **Do withdrawals require approval?** (recommendation: no in V1; spec §26 keeps the
    framework modular).
12. **Who may finalize and reopen a settlement** (recommendation: finalize — Accountant and
    Owner; reopen — Owner only, mirroring `period.reopen`).

**External**

13. **Exact Petpooja NC inclusion/exclusion behaviour** — operational question; determines
    Scenario A or B (§18).
14. **GST statutory treatment of NC — CA confirmation required** (§25).

---

## 31 · Can the old Slice 7 proceed unchanged?

**No. It must be revised, and it must not run next.**

* **Unchanged: no.** Slice 7's subject is the reporting capability model. Owner Settlement
  adds capabilities to that same model, adds the most privacy-sensitive surface in the
  product, and adds the staff-privacy split of §31 — which is an authorization requirement,
  not a UI preference.
* **Wait: yes, but not idly.** The revised Slice 7 becomes **slice 10** in §26 and secures
  P&L and Owner Settlement in one pass, once there is an owner surface to secure.
* **What it keeps:** every item currently carried to it — the reporting capability audit, the
  role-template review, `public.expense_sees_whole_org()` (on the reviewed API surface,
  called by nothing), the `reports.export` / `reports.print` exemptions, `may_read_expense`
  performance (D-186), and the accumulated-state security acceptance.
* **What it gains:** the owner capability set, the staff-privacy separation, and the
  settlement report boundary of §22.

Splitting it would mean designing the reporting authorization contract twice. This project
has already paid for that once, in the same layer, three commits ago.

---

*Prepared as an audit and proposal. Nothing above is binding until the Product Lead decides
it and it is recorded in `DECISIONS.md`.*
