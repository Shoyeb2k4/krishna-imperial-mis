-- Acceptance teardown, NOT a migration and NEVER a production configuration.
-- Run as the administrator only after verifying the connected project ref is
-- loratzmactetjbqolwri (krishna-mis-dev). Run before and in the finally/cleanup
-- phase after the serial owner live suites, including failed/interrupted runs.
-- The client intentionally has no DELETE privilege or reset RPC.
begin;
do $cleanup$ begin
  if exists (
    select 1 from public.owner_settlement_settings
     where org_id = '5341bd8e-65f1-5825-84d0-2c3bca9ba8fc'
       and ownership_start_date <> date '2026-05-01'
  ) then
    raise exception 'not the approved disposable fixture';
  end if;
end $cleanup$;
delete from public.owner_settlement_settings
 where org_id = '5341bd8e-65f1-5825-84d0-2c3bca9ba8fc'
   and ownership_start_date = date '2026-05-01';
commit;
select count(*) as settings_rows from public.owner_settlement_settings;
