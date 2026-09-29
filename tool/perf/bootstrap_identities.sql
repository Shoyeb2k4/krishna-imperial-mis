-- Phase 8 Slice 2 — synthetic identities for the local D-186 harness.
--
-- Run by localpg.sh immediately before 20260901132225_revenue_verified_baseline_fy2627,
-- which refuses to install without an owner profile to attribute it to — on the server
-- that profile was the real development owner, bootstrapped by hand in Phase 2.
--
-- Five synthetic principals, each defined by the capability bundle it holds and never by
-- anything a role name implies. The accounts exist only in this throwaway cluster, carry
-- `.invalid` addresses (RFC 2606: can never resolve), and have no password anywhere.
--
--   owner       Owner, unscoped                          (app.bootstrap_owner)
--   ccr_manager Manager, Crystal Canopy only             (user_provision + user_role_grant,
--   hki_manager Manager, Hotel Krishna only               called AS the owner, through the
--   accountant  Accountant, Crystal Canopy only           same reviewed RPCs production uses)
--   data_entry  Data Entry, Crystal Canopy only — the expense.view.own principal
insert into auth.users (id, email) values
  ('a0000000-0000-4000-8000-000000000001', 'perf.owner@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000002', 'perf.ccr.manager@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000003', 'perf.hki.manager@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000004', 'perf.accountant@krishna-perf.invalid'),
  ('a0000000-0000-4000-8000-000000000005', 'perf.data.entry@krishna-perf.invalid');

select app.bootstrap_owner('perf.owner@krishna-perf.invalid', 'Perf Owner', false);
select app.seed_id('bu:CCR') as ccr, app.seed_id('bu:HKI') as hki \gset

begin;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.user_provision('perf.ccr.manager@krishna-perf.invalid', 'Perf CCR Manager');
select public.user_provision('perf.hki.manager@krishna-perf.invalid', 'Perf HKI Manager');
select public.user_provision('perf.accountant@krishna-perf.invalid',  'Perf Accountant');
select public.user_provision('perf.data.entry@krishna-perf.invalid',  'Perf Data Entry');
select public.user_role_grant('a0000000-0000-4000-8000-000000000002', 'manager',    :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000003', 'manager',    :'hki');
select public.user_role_grant('a0000000-0000-4000-8000-000000000004', 'accountant', :'ccr');
select public.user_role_grant('a0000000-0000-4000-8000-000000000005', 'data_entry', :'ccr');
commit;
