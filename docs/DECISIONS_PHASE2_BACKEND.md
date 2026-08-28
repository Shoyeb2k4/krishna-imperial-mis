# Decision Log — Phase 2 backend (pending verification)

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.1**

These four decisions are cited by the migrations in `supabase/migrations/`. They are
recorded here rather than appended to `docs/DECISIONS.md` because the owner's Phase 2
instruction (§20) reserves that file for the Phase 2 completion commit, and the decisions
below have **not yet been verified against an applied database**. They move into
`DECISIONS.md` unchanged when the Phase 2 acceptance gate passes — or they are amended
there if applying them proves any of them wrong.

Status: **D-040, D-041 and D-042 are proposed** — implemented in migration source, not yet
applied to a database. **D-043 is accepted**: it is an owner decision about business
treatment and does not depend on any database to be true.

---

## D-040 — The hierarchy is pinned by a composite foreign-key ladder
**Date:** 2026-08-27
**Context:** Owner requirement §4: the database must reject impossible structures even if
the client is modified — a section belonging under a Hotel Krishna department must not be
attachable to a Crystal Canopy hierarchy. The owner also warned specifically against
"duplicated denormalized parent IDs unless they materially strengthen validation and
remain transactionally consistent."

A plain parent foreign key does not achieve the requirement. `sections.department_id →
departments(id)` guarantees the department exists and says nothing about which property it
belongs to. Nothing in that constraint stops a section being re-pointed across properties.

**Decision:** Each level carries its ancestors and references its parent by the whole
tuple:

```
departments        (org_id, business_unit_id)                → business_units(org_id, id)
sections           (org_id, business_unit_id, department_id) → departments(org_id, business_unit_id, id)
expense_categories (org_id, business_unit_id, department_id, section_id)
                                                            → sections(org_id, business_unit_id, department_id, id)
```

**Why this is not the duplication the owner warned about.** The ancestor columns are not
free-floating copies kept in step by application code or by a trigger. Each is *pinned by
the same foreign key that pins the parent link*, checked at the same instant, in the same
statement. For a section to claim the wrong business unit it would have to name a
`(business_unit_id, department_id)` pair that does not exist in `departments`, and the key
refuses it. Consistency is not maintained; it is structurally unavailable to break.

**Alternatives:** a validation trigger per level (correct until someone writes a path that
skips it, and it must re-read the parents on every write); application-only validation
(explicitly insufficient — a modified client bypasses it); no ancestor columns and a
recursive check at use time (turns every Phase 3 allocation-line write into a three-join
verification).

**Consequences:**
- Re-parenting a department across properties fails while it has sections, because their
  tuples would stop resolving. A `refuse_reparent_across_units` trigger refuses the move
  outright as well, so the failure names the real problem instead of surfacing as a
  foreign-key error on a row nobody was looking at.
- A Phase 3 expense allocation line validates its entire classification with **one**
  composite foreign key against
  `expense_categories(id, section_id, department_id, business_unit_id)` — no trigger, no
  application check, no possible drift.
- Slightly wider indexes and four extra uuid columns across four tables. Accepted.

## D-041 — Master usage is a maintained counter, never a `count(*)`
**Date:** 2026-08-27
**Context:** Owner requirement §11: an authoritative server usage figure for masters, and
explicitly *"do not design an expensive `COUNT(*)` pattern that will become pathological
once financial history is large."* D-038 needs that figure before a rename dialog can
state its real impact.
**Decision:** `master_usage_counters` holds one row per master — count, earliest and latest
business date — maintained incrementally by `app.record_master_usage`, which the Phase 3
financial write path calls. `public.master_usage()` reads it by primary key, in O(1), and
labels the result `source: 'server'`.
**Alternatives:** `count(*)` over allocation lines (a full scan of financial history every
time an administrator opens a dialog that must feel instant); a materialised view (refresh
latency, and a stale count is exactly the thing that must not be relied on for an archive
decision); an approximate count (unacceptable for a decision the owner is told is safe).
**Consequences:**
- While no financial tables exist, a count of zero is **genuinely authoritative** — there
  are no transactions in the organisation at all, so nothing is approximated. That is
  different in kind from a local cache reporting zero because it has not synced, which the
  client must never promote to authoritative. `MasterUsage` already carries its source and
  keeps the two apart.
- The counter trigger wiring lands with the Phase 3 financial tables. Until then
  `record_master_usage` has no callers, which is deliberate and stated rather than
  discovered later.

## D-042 — Period locks are keyed by `period_key`, not by a start/end date pair
**Date:** 2026-08-27
**Context:** `docs/DATABASE_SCHEMA.md` §7 sketched `period_locks` with `period_start` and
`period_end` date columns. The implemented client — `BusinessDate.periodKey`, the local
SQLite `period_locks` table and `PeriodRegistry` — settled on a `'YYYY-MM'` key.
**Decision:** Postgres uses `period_key text` with a format check, matching the client and
the local mirror.
**Reason:** Two representations of the same concept must be converted at every boundary,
and a conversion is a place to be wrong. The key is also what the authoriser actually asks
for, so keying on it removes a translation step from the hot path of every financial write.
A month is the only period granularity V1 closes.
**Consequences:** `docs/DATABASE_SCHEMA.md` §7 is superseded on this point and is corrected
when Phase 2 completes. If a non-monthly close is ever needed, the change is a new column
plus a migration, not a redesign — the lock is still one row per (org, unit, period).

## D-043 — No tax rate is seeded, and none is assumed
**Date:** 2026-08-27 · **Status:** **Accepted (owner decision, 2026-08-27)**
**Context:** `docs/DATABASE_SCHEMA.md` §12 lists "initial tax configuration rows" among the
seeded data. Spec §8.1 and `CLAUDE.md` forbid a hard-coded rate anywhere, and permit a 5%
inclusive value only in **sanitised test fixtures**. Put to the owner, who confirmed it and
made the terms explicit.
**Decision (owner's words):** No GST or tax rate is seeded yet. The tax treatment for
Restaurant, Nandbhog, Room and Banquet will be supplied later, after the actual business
tax treatment has been verified. Specifically:

* no default tax rate;
* no assumed 5%;
* no assumed 18%;
* no implicit inheritance from another category, another property or another period;
* no fake production tax rule in seed data.

The Tax Rules feature carries an explicit **"No rule configured"** state. This does not
block Phase 2.

The seed therefore creates no `revenue_tax_rates` rows at all, and the timeline for each
revenue category starts empty.
**Reason:** A rate committed to a migration is a rate in source control that nobody chose,
and it would silently produce Net Sales figures the owner never approved. The domain
already treats a missing rule as a visible configuration gap rather than a silent "no tax"
that overstates Net Sales, so an empty timeline is both honest and already handled.
**Consequences:** The owner supplies the first rule per revenue category — Restaurant,
Nandbhog, Room, Banquet — through the Tax screen or `tax_rule_create`, each with its rate,
its treatment and the date it takes effect, once the real treatment is verified. Until
then:

* `TaxRuleSet.ruleFor` returns null rather than a zero-rate default, so a missing rule is a
  visible configuration gap and never a silent "no tax" that would overstate Net Sales;
* the Tax screen states *"No tax rule configured. Revenue recorded for this category will
  have no tax extracted until one is set."* in the caution colour, and shows *"No rule in
  force today"* against the category — already implemented and covered by a widget test;
* Phase 4 revenue entry must refuse, or record explicitly untaxed, rather than assume — it
  must not invent a rate from any source.

No entry in the seed, the migrations, the fixtures or the code carries a rate.

---

# Decisions arising from applying and testing the backend (2026-08-27)

These four were forced by executing the schema against the real development database.
Each is **Accepted and verified against `krishna-mis-dev`**, unlike D-040 … D-042 above,
which were proposed before anything was applied.

## D-044 — `EXECUTE` on a new function is revoked, and the revocation is asserted
**Context:** Postgres grants `EXECUTE` on every new function to `PUBLIC`. Writing
`grant execute … to authenticated` therefore restricted nothing — it restated an access
`anon` already had. All 19 RPCs were reachable by an unauthenticated caller holding only
the publishable key. Each refused, because they call `app.require_actor()` first, but
"happens to fail closed" is a different claim from "cannot be called".
**Decision:** `PUBLIC` and `anon` lose `EXECUTE` on everything in `public` and `app`;
`authenticated` is re-granted exactly one reviewed list; `alter default privileges` keeps
the next function closed; and a migration **asserts** the result, failing if anything is
reachable that should not be — or if a reviewed function has quietly stopped being
callable. The API surface is declared in one place and restated in full whenever it grows.
**Consequences:** Proven over HTTPS: an anonymous `rpc/master_create` now returns
`permission denied for function master_create` rather than reaching the function at all.

## D-045 — RLS policies call a published helper, never the internal schema
**Context:** Every policy called `app.current_org_id()`. A policy expression is evaluated
with the **querying user's** privileges, and `authenticated` has no `USAGE` on `app` — the
schema is locked down precisely so it cannot be reached. Every table returned `403` for
every signed-in user. No data was exposed; the application was simply unusable, and no
static review had shown it.
**Decision:** `public.current_org_id()` is published and granted to `authenticated`;
policies use it. `app.current_org_id()` stays for use inside `SECURITY DEFINER` functions,
which run as the owner. A migration asserts that **no policy references `app.`**.
**Alternatives:** granting `authenticated` `USAGE` on `app` would have worked and would
have eroded the boundary the schema exists to draw, and broken the D-044 invariant.
**Consequences:** The lesson is recorded in the invariant itself, which now fails in both
directions — over-exposure *and* silent under-exposure.

## D-046 — Permission is decided before existence is revealed
**Context:** Every mutation RPC loaded the target row first and refused `unknown_entity`
when it was missing, only then checking capability. Normally a weak oracle, because ids
are random — but seeded master ids are UUID v5 values derived from public code paths
(D-040), so anyone can compute them and probe.
**Decision:** The cheap organisation-wide capability check runs **before** the row is
loaded. The precise unit-scoped check still runs afterwards, because it needs to know
which property the row belongs to; an administrator can therefore still distinguish
existence, which is appropriate.
**Consequences:** The server now refuses in the same order the Dart `Authorizer` always
has — permission, then ownership, then state. The two layers give the same answer for the
same reason.

## D-047 — Onboarding a user is a first-class administrative action
**Context:** `user_role_grant` requires a profile, and nothing created one except the
owner bootstrap. Preparing the authorisation tests would have meant inserting profiles
behind the authorisation model — exactly what must not happen.
**Decision:** `public.user_provision(email, full_name)` brings an **existing**
authentication account into the organisation, gated on an organisation-wide
`users.manage`. It never creates accounts and never sets passwords: sign-up and
credentials stay entirely inside Supabase Auth. `public.user_deactivate` is its
counterpart and deletes nothing.
**Consequences:** Every development identity used in the authorisation suite was created
through the ordinary signup path and enrolled through this RPC, so the tests exercise the
real administrative mechanism rather than a shortcut around it.

## D-048 — Revoked-scope cache policy: purge server-owned reference data, on confirmed authority only
**Date:** 2026-08-28 · **Status:** **Accepted (owner decision — Option A)**
**Context:** When the server confirms a user has lost a business unit, what happens to the
reference data already cached in the device's encrypted SQLite database? Three options
were put to the owner; **A — purge on the next successful authoritative refresh** was
chosen. Encryption at rest is not a reason to retain newly unauthorised data.

**Decision.** On a **successful** authority refresh that positively establishes the user's
current scopes, locally cached *server-owned* reference data belonging exclusively to a
revoked business unit is deleted: departments, sections, expense categories, revenue
categories, unit-scoped tax rules and period locks, and the business unit itself.

**`unknown ≠ revoked`.** Nothing is purged because the network failed, a refresh timed
out, a token could not be renewed or authority is simply unknown. This is enforced by the
type system rather than by discipline: `ScopeCachePurge.applyTo` takes an
`AuthorityRefresh`, which is a sealed type whose only purging branch is
`AuthorityConfirmed`. There is no signature that lets a caller purge on a timeout.

**The outbox is never touched.** Queued, failed, rejected, conflicted and attention-
required work is the user's, not the server's. The purge deletes only from a fixed list of
server-owned tables and *asserts* the outbox count is unchanged before returning, throwing
rather than continuing if it ever is not. A mutation queued while authorised and refused
on delivery becomes `OutboxStatus.rejected` — a new, terminal state distinct from
`conflict`, never auto-retried, never marked synced, and still inspectable with the
server's own reason attached.

**Transactional and bottom-up.** One transaction, children before parents, so there is no
moment at which a section hangs off a department that is already gone and no partially
purged hierarchy if anything fails. Verified with `PRAGMA foreign_key_check`.

**One deviation from the literal instruction, and why.** D-048 lists "scoped Vendors"
among the data to purge. Vendors are classified here as **organisation-global and
retained**, because:

* server-side, `vendors_read` is organisation-level — a manager who loses Crystal Canopy
  but keeps Hotel Krishna is still returned every vendor, so purging one locally would
  delete a row the very next pull restores. That is churn, not security;
* a vendor is a supplier of the **company**, not of a property. `default_business_unit_id`
  is a pre-selection for the entry form, and treating a UI convenience as a tenancy
  boundary is how a company-wide supplier list quietly fragments;
* D-048 §4 asks for the classification to be fixed rather than for exceptions to be added
  to the purge, so it is fixed in the classification.

What *is* done: a vendor's stale `default_business_unit_id` pointing at the revoked unit is
cleared, so the picker cannot offer a property the user can no longer reach. **If vendors
should genuinely become unit-scoped, that is a change to `vendors_read` and to the vendor
model on both sides — not a client-only deletion rule — and it needs the owner's decision.**

**Re-grant.** Restoring a scope re-downloads canonical server state. Because seeded ids are
derived (D-040), the same records return under the same ids and nothing duplicates. A
previously rejected mutation is **not** resurrected: authority returning does not re-assert
an intent the server already refused.

**Consequences:** `CacheClassification` names every local table and its owner, and throws
on an unclassified one — so a new table forces a decision about what an authority change
does to it, rather than defaulting into whichever behaviour is convenient.

## D-049 — A vendor is an organisation-global master; its default business unit is a convenience
**Date:** 2026-08-28 · **Status:** **Accepted (owner decision)**
**Context:** D-048 listed "scoped Vendors" among the data to purge on scope revocation.
Raised as a deviation, and the owner settled it: vendors are organisation-global.

**Decision.** A vendor may serve Crystal Canopy, Hotel Krishna Imperial, or both, without
duplicate master records — grocery, vegetable and water suppliers, electricians,
maintenance and stationery vendors all commonly serve both properties. `vendors_read`
stays organisation-level and is **not** redesigned as unit-scoped merely because a vendor
carries a default business unit.

`default_business_unit_id` is an optional operational pre-selection. It determines
**none** of: ownership, visibility, authorisation, accounting scope. A vendor stays
visible even when its configured default is outside the current user's scope.

**The refinement that matters (§2).** Losing access to a vendor's default unit must not
mutate the canonical vendor. No NULL is written, no row version moves, no audit event is
raised, and the default is not removed because one user lost scope — the vendor has not
changed. An earlier draft cleared the cached default during the purge; that was wrong on
two counts: it made the local row disagree with the server, and the very next pull would
restore it, producing an endless pull/clear/pull/clear cycle.

Instead the constraint is **derived per user** at the point of use:

```dart
String? effectiveDefaultBusinessUnitId(Set<String>? scopedUnits)
```

inside scope → the configured default; outside scope → null for that user's picker;
scope restored → the configured default becomes usable again on its own, with nothing
written to make it so. `null` scopedUnits means an org-wide holder — no restriction.
`hasUnreachableDefault` lets the detail panel say so quietly, rather than showing an
absent default that looks like a data fault.

**Consequence — a local schema correction (v5).** `vendors.default_business_unit_id` and
`vendors.default_category_id` were modelled as foreign keys with `ON DELETE RESTRICT`.
That made the revoked-scope purge impossible: deleting the business unit failed while any
vendor named it, so the only ways forward were to rewrite canonical vendor data (forbidden
by §2) or to leave the unit cached (defeating D-048).

A foreign key asserts "the target exists in this database". On a **per-user cache** that
is simply false — a manager scoped to one property legitimately holds vendors whose usual
property is the other one. Both columns are therefore **soft pointers**, resolved at the
point of use. A dangling value is expected and harmless. The server keeps its real foreign
keys, because there the assertion is true.

## D-050 — The outbox records who queued each intent
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** A shared Windows workstation in a back office sees several people sign in and
out of one installation. The outbox was anonymous, so nothing distinguished one person's
queued work from another's.
**Decision:** `sync_outbox.actor_user_id` (local schema v6). Sync sends only entries
belonging to the signed-in user; one person's queued work is never retried by, attributed
to, or shown as another's. Rows written before the column existed are unattributed and are
never sent by anyone — surfaced for a human rather than guessed at or discarded.
**Consequences:** Signing out and switching users never deletes queued work (D-048 §2),
and now it cannot be misattributed either.

## D-051 — Authentication, session lifecycle and fail-closed authority
**Date:** 2026-08-28 · **Status:** Accepted
**Context:** `principalProvider` returned a hard-coded Owner holding every capability —
correct while no backend existed, a security defect the moment one did.
**Decision.** One `SessionState` machine drives the whole application: unauthenticated ·
authenticating · verifying · **unverified** · ready(confirmed|stale) · expired. Only
`SessionReady` yields real grants; every other state yields `Principal.anonymous`, which
holds nothing.

* **Fail closed (§8).** A user who authenticates on a device that has never received an
  authoritative snapshot gets *no* operational access — not a reduced menu, not a
  read-only view. Their permissions must never depend on whether their phone had signal.
* **Cached authority (§9).** A previously verified user works offline against permitted
  cached data, visibly stale, with privileged mutations pending rather than final. Cached
  authority is keyed by user id and `loadFor` returns nothing for anybody else, so the
  mistake cannot be made by forgetting a check.
* **Deactivation (§14).** The server declining to treat somebody as an actor is a
  *statement*, not a connectivity problem, so it never falls back to cache: the session
  becomes expired and the stored authority is cleared.
* **User switch (§16).** When a different user signs in on the same installation, the
  previous user's scoped cache is purged and their cached authority cleared **before**
  navigation opens. The outbox is untouched.
* **Session tokens** live in the platform-secure store — Android Keystore, Windows
  DPAPI — not shared preferences, because a refresh token is a bearer credential for
  company financial data (D-022).

**Enforcement:** `test/app/no_hardcoded_authority_test.dart` asserts over `lib/` that no
shipped file builds a `Principal`, references `RoleTemplates.owner`, or carries a
development identity. Test fixtures may do as they like; they are not in `lib/` and cannot
enter a build.
