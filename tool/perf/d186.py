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


def workloads(p: dict) -> list[tuple[str, str]]:
    """(label, sql) for one principal. `p` holds the dataset's units and dates."""
    unit = p["unit"]                     # the primary property this principal reports on
    units = p["units"]                   # every property the principal is offered
    both = p["both"]                     # both properties: the consolidated request
    m0, m1 = p["month"]
    f0, f1 = p["fy"]
    since = p["since"]
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
    return [
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
        ("rs.full", f"select public.reporting_snapshot({arr(units)}, 0, 0)"),
        ("rs.delta", f"select public.reporting_snapshot({arr(units)}, {since}, {since})"),
        ("rls.epa.month",
         "select count(*) from public.expense_period_allocations "
         f"where pnl_date >= {lit(m0)} and pnl_date <= {lit(m1)}"),
        ("doc.month",
         "select count(*), sum(visible_amount_minor) from public.expense_document "
         f"where business_date >= {lit(m0)} and business_date <= {lit(m1)}"),
    ]


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
    return ".fy." in label or label.startswith("rs.")


def batch(p: dict, principal: str | None, runs: int, only: list[str] | None,
          heavy_runs: int | None = None) -> str:
    items = baseline(p) if principal is None else workloads(p)
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
    sql = batch(p, who, a.runs, a.only, a.heavy_runs)
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
