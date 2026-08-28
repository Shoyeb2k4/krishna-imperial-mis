# Backend — development

Directive: SHOYEB-HOSPITALITY-MIS · Spec v1.1 · Phase 2

Postgres is the system of record. The local encrypted SQLite database is a cache, a write
buffer and the default reporting engine — never the authority (`docs/ARCHITECTURE.md` §1).

**Only `krishna-mis-dev` is touched during this phase.** No staging project, no production
project, and no credential from either is reused here.

---

## What is in here

| Migration | What it establishes |
|---|---|
| `…090000_conventions.sql` | The private `app` schema, the global change sequence, the shared `updated_at` / `row_version` / `change_seq` trigger, the append-only guard, and the refusal vocabulary |
| `…090100_identity.sql` | Organisation, profiles, roles, the 27-capability catalogue, org settings |
| `…090200_masters.sql` | Business units, departments, sections, expense categories, revenue categories, vendors, payment methods — with the composite foreign-key ladder (D-040) |
| `…090300_master_integrity.sql` | Immutable codes, no cross-property moves, D-039 archiving, no orphaned restores |
| `…090400_user_roles.sql` | Role grants with mandatory business-unit scope (D-025) |
| `…090500_period_control.sql` | Period locks and their append-only event history |
| `…090600_tax_rules.sql` | Date-effective tax rules with a `daterange` exclusion constraint (D-017) |
| `…090700_audit_and_usage.sql` | Audit trail, the idempotency ledger, maintained usage counters (D-041) |
| `…090800_authorization.sql` | `has_capability`, `period_state`, version and idempotency helpers |
| `…090900_rls.sql` | RLS on every table, deny by default, no client write grant anywhere |
| `…091000_master_rpcs.sql` | `master_create` · `master_rename` · `master_archive` · `master_restore` · `master_usage` |
| `…091100_vendor_tax_period_rpcs.sql` | Vendors, tax rules, period close and reopen |
| `…091200_seed.sql` | Sanitised development seed — business structure only, no financial data |
| `…091300_owner_bootstrap.sql` | The one-time owner bootstrap, and ordinary role administration |

## Privileged access is developer-only, and never in the app

Applying migrations needs privileges the application must never hold. That access lives in
**developer tooling on a developer machine** and is never bundled:

* the Supabase **dashboard** (SQL editor, Authentication), authenticated by the owner's
  dashboard session; or
* the Supabase **CLI** (`npx supabase …`), authenticated by a personal access token held
  in the developer's own credential store.

Neither ever appears in `pubspec.yaml`, in `config/*.json`, in an Android or Windows
resource, in a test fixture, or in a build log. The application only ever receives the
project URL and the publishable/anon key, both of which are powerless without a matching
RLS policy. `dart run tool/check_no_client_secrets.dart --history` enforces that
mechanically over the working tree and every blob ever committed.

## Applying the migrations

```bash
npx supabase login                              # opens a browser; token stays on this machine
npx supabase link --project-ref <project-ref>   # the ref from https://<ref>.supabase.co
npx supabase db push
```

`link` will ask for the database password. That is entered into the CLI prompt on the
developer machine — never pasted into chat, never written to a file in this repository.

To verify afterwards:

```bash
npx supabase migration list
```

## Creating the first Owner

There is deliberately **no client-callable path** that grants ownership. `app.bootstrap_owner`
has `EXECUTE` revoked from `public`, `anon` and `authenticated`, so a modified APK, a
rebuilt `.exe` and a stolen anon key are all equally powerless against it — the grant they
would need does not exist. It runs only from a privileged database session.

Two steps, both in the Supabase dashboard for `krishna-mis-dev`:

1. **Authentication → Users → Add user.** Enter the owner's email and a password.
   Nothing in this repository can create an account or set a password, and nobody should
   ever be asked to share one.

2. **SQL Editor**, run exactly this, substituting the same email:

   ```sql
   select app.bootstrap_owner('owner@example.com', 'Shoyeb Akhtar');
   ```

   It creates the `profiles` row, grants the unscoped Owner role, and writes an audit
   entry. It is idempotent, and it refuses to mint a second owner unless asked explicitly
   (`p_allow_additional => true`).

Every subsequent grant is ordinary administration through `public.user_role_grant`, which
is capability-gated like everything else. Manager, Accountant and Data Entry grants **must**
name a business unit; the database refuses otherwise (D-025).

## Errors the client will see

Refusals raise with a distinct `SQLSTATE` and a JSON `DETAIL`, so the UI can state the real
reason instead of a generic failure. A closed period must never look like a permissions
problem, and a stale version must never look like a closed period.

| SQLSTATE | `code` | Meaning |
|---|---|---|
| `KM001` | `missing_capability` | No permission at all |
| `KM002` | `out_of_unit_scope` | Permission, but not for this property |
| `KM003` | `version_conflict` | The record changed since it was read |
| `KM004` | `period_closed` | The period is closed; the Owner must reopen it |
| `KM005` | `has_active_children` | D-039 — archive the records underneath first |
| `KM006` | `archived_master` / `archived_parent` | Archived, and not usable for this |
| `KM007` | `tax_period_overlap` and friends | A tax period collision or an invalid range |
| `KM008` | `reason_required` | Reopening a period demands a reason |
| `KM009` | `immutable_code` / `invalid_code` | A permanent code cannot change |
| `KM010` | `hierarchy_violation` | The structure asked for cannot exist |
| `KM011` | `not_authenticated` | Not signed in, or deactivated |
| `KM012` | `duplicate_name` / `name_required` | |
| `KM015` | `unknown_entity` | |
| `KM016` | `append_only` | Audit and event rows are never amended |
| `KM017` | `acknowledgement_required` | D-038 — the rename affects recorded history |

## What is deliberately not here

* **No financial transaction tables.** Expenses, allocations, revenue entries and their
  period allocations belong to Phase 3 and are not created early merely because they are
  known future requirements.
* **No seeded tax rate.** Spec §8.1 forbids a hard-coded rate anywhere, and a rate
  committed to a migration is a rate nobody chose. The timeline starts empty and the
  domain already treats a missing rule as a visible configuration gap rather than a silent
  zero. The owner supplies the first rule per revenue category.
* **No production or staging anything.**

## Two advisor findings that are the design, not defects

`get_advisors(type: security)` reports these on every run. Both are expected. They are
recorded here because the obvious "fix" for each would break something real.

**INFO · `rls_enabled_no_policy` on `master_usage_counters` and `processed_mutations`.**
RLS is enabled and there is deliberately no policy, which is what makes both tables
unreadable by any client. The usage counter is served through `master_usage()` so the
figure arrives labelled with its authority (D-041); the mutation ledger is internal to
idempotency and has no reason to leave the database. **Do not add a SELECT policy** to
silence this.

**WARN · `authenticated_security_definer_function_executable` on the 18 RPCs.**
That is the whole architecture. Clients hold no write grant on any table, so every
administrative mutation has to run with the definer's rights — and each one independently
re-checks capability, business-unit scope, record state and row version before it touches
anything (D-037). The advisor flags the pattern, not a flaw in any particular function.
**Do not revoke these grants** or switch them to `SECURITY INVOKER`: the first breaks the
application, the second breaks the enforcement.

There are no ERROR-level advisories.
