#!/usr/bin/env bash
# Phase 8 Slice 2 — load a D-313 dataset class into the local D-186 harness.
#
#   synth.sh scale     SCALE : 100,000 contribution rows in FY 2026-27
#   synth.sh stress    STRESS: 500,000 contribution rows over FY 2022-23 … FY 2026-27
#
# D-313's default split is 50/50 revenue/expense contribution rows. Voided share 10%,
# 10% of expenses split across both properties, 10% of lines split across two periods.
# Always starts from a freshly replayed schema (localpg.sh schema), so the two classes
# never mix and a re-run gives the same rows for the same seed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${KRISHNA_PERF_PG:-${TEMP:-/tmp}/krishna_mis_perf_pg}"
PGBIN="${PGBIN:-/c/Program Files/PostgreSQL/17/bin}"
SOCK="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"
SEED="${SEED:-d186}"

case "${1:-}" in
  scale)  years=(2026);                         per_year=100000 ;;
  stress) years=(2022 2023 2024 2025 2026);     per_year=100000 ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac

bash "$HERE/localpg.sh" schema
for fy in "${years[@]}"; do
  PAGER= "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$SOCK" -p 55432 -U postgres -d krishna_perf \
    -v fy="$fy" -v exp_rows=$((per_year / 2)) -v rev_rows=$((per_year / 2)) -v seed="$SEED" \
    -v void_pm=100 -v split_u_pct=10 -v split_p_pct=10 \
    -f "$(cygpath -w "$HERE/synth.sql" 2>/dev/null || echo "$HERE/synth.sql")" </dev/null
  echo "loaded FY $fy-$((fy + 1))"
done
PAGER= "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$SOCK" -p 55432 -U postgres -d krishna_perf \
  -c "vacuum analyze" </dev/null
PAGER= "$PGBIN/psql" -X -A -P pager=off -h "$SOCK" -p 55432 -U postgres -d krishna_perf </dev/null -c "
select 'expenses' t, count(*) n, count(*) filter (where voided_at is not null) voided from public.expenses
union all select 'expense_allocations', count(*), null from public.expense_allocations
union all select 'expense_period_allocations', count(*), null from public.expense_period_allocations
union all select 'revenue_entries', count(*), count(*) filter (where voided_at is not null) from public.revenue_entries
union all select 'revenue_components', count(*), null from public.revenue_components"
