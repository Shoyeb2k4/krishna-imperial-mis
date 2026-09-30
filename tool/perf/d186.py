#!/usr/bin/env python3
"""Phase 8 Slice 2 — D-186 profiling driver (D-313 measurement contract).

Builds the measured workload matrix and wraps each workload in the probe
(`d186_probe.sql`). It never connects to Supabase itself:

  emit       prints one SQL batch for one principal. The batch is a single transaction
             that ends in ROLLBACK, sets nothing beyond the transaction, and writes
             nothing. On krishna-mis-dev it is executed through the reviewed SQL tool.
  run-local  executes the same batch against the disposable local cluster only
             (see localpg.sh), refusing any other host, port or database.
  summarize  prints a result file as the D-313 report table.

The workloads are the queries the product actually issues — reporting_primitives and
reporting_snapshot exactly as the clients call them — plus the underlying projection and
row-security reads, so that where the time goes can be seen and not only how much.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROBE = (HERE / "d186_probe.sql").read_text(encoding="utf-8")

# The harness cluster opens no TCP port: psql reaches it through the socket file in its
# own scratch directory (localpg.sh). Port 55432 names that socket.
LOCAL_SOCKET_DIR = os.environ.get(
    "KRISHNA_PERF_PG",
    os.path.join(os.environ.get("TEMP", "/tmp"), "krishna_mis_perf_pg")).replace("\\", "/")
LOCAL_PORT = 55432
LOCAL_DB = "krishna_perf"


def lit(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def arr(units: list[str]) -> str:
    return "array[" + ", ".join(lit(u) + "::uuid" for u in units) + "]"


def paged_loop(units: list[str], years: list[int], since: int, page: int) -> str:
    """The whole paged run (D-320) as one statement: each recursive step is one call of
    reporting_snapshot_page with the previous page's cursor, exactly as the client walks
    it. Returns the page count and the documents delivered, so the result is checkable."""
    ys = "array[" + ", ".join(str(y) for y in years) + "]::int[]"
    call = (f"public.reporting_snapshot_page({arr(units)}, {ys}, {since}, {since}, "
            "{rs}, {ri}, {es}, {ei}, " + str(page) + ")")
    first = call.format(rs="null", ri="null", es="null", ei="null")
    nxt = call.format(rs="pg.rs", ri="pg.ri", es="pg.es", ei="pg.ei")
    step = ("(s.x->'revenue_documents'->-1->>'seq')::bigint as rs, "
            "(s.x->'revenue_documents'->-1->>'id')::uuid as ri, "
            "(s.x->'expense_documents'->-1->>'seq')::bigint as es, "
            "(s.x->'expense_documents'->-1->>'id')::uuid as ei, "
            "coalesce((s.x->>'revenue_has_more')::boolean, false) "
            "or coalesce((s.x->>'expense_has_more')::boolean, false) as more, "
            "jsonb_array_length(s.x->'revenue_documents') "
            "+ jsonb_array_length(s.x->'expense_documents') as docs, "
            "jsonb_array_length(s.x->'revenue') + jsonb_array_length(s.x->'expense') as rows")
    return (
        "with recursive pg(n, rs, ri, es, ei, more, docs, rows) as ("
        f"select 1, v.* from (select {first} as x) s, lateral (select {step}) v "
        "union all "
        "select pg.n + 1, coalesce(v.rs, pg.rs), coalesce(v.ri, pg.ri), "
        "coalesce(v.es, pg.es), coalesce(v.ei, pg.ei), v.more, v.docs, v.rows "
        f"from pg cross join lateral (select {nxt} as x) s, lateral (select {step}) v "
        "where pg.more) "
        "select count(*) as pages, sum(docs) as documents, sum(rows) as rows from pg"
    )


def workloads(p: dict, old: bool = False) -> list[tuple[str, str]]:
    """(label, sql) for one principal. `p` holds the dataset's units and dates.

    With `old`, the same reads are also issued against `perf_old` — the pre-redesign
    projections and functions captured by capture_old.sql — so before and after are
    measured on identical data, in the same session (D-318 performance acceptance)."""
    unit = p["unit"]                     # the primary property this principal reports on
    units = p["units"]                   # every property the principal is offered
    both = p["both"]                     # both properties: the consolidated request
    m0, m1 = p["month"]
    f0, f1 = p["fy"]
    since = p["since"]
    fy_start = int(f0[:4])
    fy_years = p.get("retained_years") or [fy_start - 1, fy_start]
    years = "array[" + ", ".join(str(y) for y in fy_years) + "]::int[]"
    epc = ("select business_unit_id, count(*), sum(amount_minor) "
           "from public.expense_period_contributions "
           "where voided_at is null and txn_number is not null "
           "and pnl_date >= {a} and pnl_date <= {b} {u} group by business_unit_id")
    epc_bd = ("select business_unit_id, department_id, section_id, category_id, count(*), "
              "sum(amount_minor) from public.expense_period_contributions "
              "where voided_at is null and txn_number is not null "
              "and pnl_date >= {a} and pnl_date <= {b} "
              "group by business_unit_id, department_id, section_id, category_id")
    one = f"and business_unit_id = {lit(unit)}::uuid"
    items = [
        ("epc.month.unit", epc.format(a=lit(m0), b=lit(m1), u=one)),
        ("epc.fy.unit", epc.format(a=lit(f0), b=lit(f1), u=one)),
        ("epc.fy.all.breakdown", epc_bd.format(a=lit(f0), b=lit(f1))),
        ("rp.month.unit",
         f"select public.reporting_primitives({arr([unit])}, {lit(m0)}, {lit(m1)}, false)"),
        ("rp.fy.unit",
         f"select public.reporting_primitives({arr([unit])}, {lit(f0)}, {lit(f1)}, false)"),
        ("rp.month.both.breakdown",
         f"select public.reporting_primitives({arr(both)}, {lit(m0)}, {lit(m1)}, true)"),
        ("rp.fy.both.breakdown",
         f"select public.reporting_primitives({arr(both)}, {lit(f0)}, {lit(f1)}, true)"),
        # The paged transport (D-320). Retention is the current and previous financial
        # year; the first page is what a device's first request costs, the loop what the
        # whole bootstrap costs, the delta what an ordinary refresh costs.
        ("rsp.first",
         f"select public.reporting_snapshot_page({arr(units)}, {years}, 0, 0, "
         f"null, null, null, null, 1000)"),
        ("rsp.delta",
         f"select public.reporting_snapshot_page({arr(units)}, {years}, {since}, {since}, "
         f"null, null, null, null, 1000)"),
        ("rsp.bootstrap.all", paged_loop(units, fy_years, 0, 1000)),
        # With `history_years`, the bootstrap over every year the dataset holds: D-320 has
        # no retention cutoff, so the whole history must page without a size limit.
        *([("rsp.bootstrap.history", paged_loop(units, p["history_years"], 0, 1000))]
          if p.get("history_years") else []),
        ("rls.epa.month",
         "select count(*) from public.expense_period_allocations "
         f"where pnl_date >= {lit(m0)} and pnl_date <= {lit(m1)}"),
        ("doc.month",
         "select count(*), sum(visible_amount_minor) from public.expense_document "
         f"where business_date >= {lit(m0)} and business_date <= {lit(m1)}"),
    ]
    if not old:
        return items
    before = [
        ("old.epc.month.unit", epc.format(a=lit(m0), b=lit(m1), u=one)),
        ("old.epc.fy.unit", epc.format(a=lit(f0), b=lit(f1), u=one)),
        ("old.epc.fy.all.breakdown", epc_bd.format(a=lit(f0), b=lit(f1))),
        ("old.rp.month.unit",
         f"select perf_old.reporting_primitives({arr([unit])}, {lit(m0)}, {lit(m1)}, false)"),
        ("old.rp.fy.unit",
         f"select perf_old.reporting_primitives({arr([unit])}, {lit(f0)}, {lit(f1)}, false)"),
        ("old.rp.month.both.breakdown",
         f"select perf_old.reporting_primitives({arr(both)}, {lit(m0)}, {lit(m1)}, true)"),
        ("old.rp.fy.both.breakdown",
         f"select perf_old.reporting_primitives({arr(both)}, {lit(f0)}, {lit(f1)}, true)"),
        ("old.rs.delta",
         f"select perf_old.reporting_snapshot({arr(units)}, {since}, {since})"),
    ]
    before = [(label, sql.replace("public.expense_period_contributions",
                                  "perf_old.expense_period_contributions"))
              for label, sql in before]
    return items + before


def baseline(p: dict) -> list[tuple[str, str]]:
    """The same reads with no authorization layer, run as the session role (which bypasses
    RLS on both targets). The difference to the principal's figure is the cost of
    authorization, which is the question D-186 asks."""
    m0, m1 = p["month"]
    f0, f1 = p["fy"]
    unit = p["unit"]
    base = ("select p.business_unit_id, count(*), sum(p.amount_minor) "
            "from public.expense_period_allocations p "
            "join public.expense_allocations a on a.id = p.allocation_id "
            "join public.expenses e on e.id = p.expense_id "
            "where e.voided_at is null and e.txn_number is not null "
            "and p.pnl_date >= {a} and p.pnl_date <= {b} {u} group by p.business_unit_id")
    one = f"and p.business_unit_id = {lit(unit)}::uuid"
    return [
        ("base.month.unit", base.format(a=lit(m0), b=lit(m1), u=one)),
        ("base.fy.unit", base.format(a=lit(f0), b=lit(f1), u=one)),
        ("base.fy.all", base.format(a=lit(f0), b=lit(f1), u="")),
    ]


def is_heavy(label: str) -> bool:
    """Whole-financial-year and snapshot workloads. At STRESS a single run of these takes
    tens of seconds, so --heavy-runs may lower their repetitions; the result records the
    run count it actually used, so the deviation from D-313's five runs is never hidden."""
    return (".fy." in label or label.startswith("rs.") or label.startswith("old.rs.")
            or label.startswith("rsp.bootstrap."))


def batch(p: dict, principal: str | None, runs: int, only: list[str] | None,
          heavy_runs: int | None = None, old: bool = False) -> str:
    items = baseline(p) if principal is None else workloads(p, old)
    if only:
        items = [w for w in items if w[0] in only]
    out = ["begin;", "set local track_functions = 'all';",
           "select set_config('bench.out', '[]', true);", PROBE]
    for label, sql in items:
        n = heavy_runs if heavy_runs is not None and is_heavy(label) else runs
        out.append(f"select pg_temp.d186_probe({lit(label)}, {lit(principal or '')}, "
                   f"{lit(sql)}, {n});")
    out += ["select current_setting('bench.out')::jsonb as out;", "rollback;"]
    return "\n".join(out)


def load_params(path: str) -> dict:
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def principal_params(params: dict, name: str) -> tuple[str | None, dict]:
    if name == "baseline":
        return None, params["baseline"]
    pr = params["principals"][name]
    return pr["id"], pr


def run_local(sql: str, psql: str) -> str:
    # The only connection this tool ever opens: the harness's own socket and database —
    # never a service the machine already runs, and never a network host.
    cmd = [psql, "-X", "-q", "-t", "-A", "-P", "pager=off", "-v", "ON_ERROR_STOP=1",
           "-h", LOCAL_SOCKET_DIR, "-p", str(LOCAL_PORT), "-U", "postgres", "-d", LOCAL_DB]
    res = subprocess.run(cmd, input=sql, capture_output=True, text=True, encoding="utf-8",
                         env={**os.environ, "PAGER": ""})
    if res.returncode != 0:
        sys.exit(res.stderr)
    lines = [l for l in res.stdout.splitlines() if l.startswith("[")]
    return lines[-1]


def summarize(results: list[dict]) -> str:
    rows = ["| workload | runs | median ms | min-max ms | plain ms | rows | shared hit/read | may_read_expense calls | has_capability calls |",
            "|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        calls = r.get("calls") or {}
        rows.append(
            f"| {r['label']} | {len(r['exec_ms'])} | {float(r['median_ms']):.1f} | "
            f"{float(r['min_ms']):.1f}-{float(r['max_ms']):.1f} | {float(r['plain_ms']):.1f} | "
            f"{r.get('rows')} | {r.get('shared_hit')}/{r.get('shared_read')} | "
            f"{calls.get('may_read_expense', 0)} | {calls.get('has_capability', 0)} |")
    return "\n".join(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("emit", "run-local"):
        s = sub.add_parser(name)
        s.add_argument("--params", required=True)
        s.add_argument("--principal", required=True)
        s.add_argument("--runs", type=int, default=5)
        s.add_argument("--heavy-runs", type=int)
        s.add_argument("--only", nargs="*")
        s.add_argument("--old", action="store_true",
                       help="also measure the perf_old (pre-redesign) reads, same data")
        s.add_argument("--out")
        s.add_argument("--psql", default=r"C:\Program Files\PostgreSQL\17\bin\psql.exe")
    s = sub.add_parser("summarize")
    s.add_argument("files", nargs="+")
    a = ap.parse_args()

    if a.cmd == "summarize":
        for f in a.files:
            print(f"\n{f}\n")
            print(summarize(json.loads(pathlib.Path(f).read_text(encoding="utf-8"))))
        return

    params = load_params(a.params)
    who, p = principal_params(params, a.principal)
    sql = batch(p, who, a.runs, a.only, a.heavy_runs, a.old)
    if a.cmd == "emit":
        print(sql)
        return
    if params.get("target") != "local":
        sys.exit("run-local refuses a parameter file whose target is not 'local'")
    raw = run_local(sql, a.psql)
    result = json.loads(raw)
    if a.out:
        pathlib.Path(a.out).write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(summarize(result))


if __name__ == "__main__":
    main()
