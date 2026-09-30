#!/usr/bin/env bash
# Phase 8 Slice 2 — the disposable local PostgreSQL 17 cluster for D-186 (E-LOCALPG, D-313).
#
#   localpg.sh init       create a fresh cluster in a scratch directory
#   localpg.sh start      start it with NO TCP listener: one Unix-domain socket inside
#                         the scratch directory (55432 names the socket file)
#   localpg.sh schema     create krishna_perf, the Supabase shim, then every migration
#   localpg.sh stop       stop it
#   localpg.sh destroy    stop it and delete the scratch directory
#
# It never touches the machine's installed PostgreSQL service (postgresql-x64-17) or any
# database in it: it runs its own `initdb` into its own directory, opens no TCP port at
# all, and is reachable only through a socket file inside that directory. No credential for the installed service
# is needed or read. Synthetic data never leaves this cluster and never reaches
# krishna-mis-dev.
#
# The server settings mirror krishna-mis-dev as read on 2026-09-29 (D-313): jit off,
# shared_buffers 224MB, work_mem 2184kB, random_page_cost 1.1, effective_cache_size
# 384MB, max_parallel_workers_per_gather 1.
set -euo pipefail

PGBIN="${PGBIN:-/c/Program Files/PostgreSQL/17/bin}"
ROOT="${KRISHNA_PERF_PG:-${TEMP:-/tmp}/krishna_mis_perf_pg}"
PORT=55432
DB=krishna_perf
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

winpath() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
# The socket directory, as the server and psql both want it: forward slashes, no drive magic.
sockdir() { winpath "$ROOT" | tr '\\' '/'; }
psql_() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$(sockdir)" -p "$PORT" -U postgres "$@"; }

case "${1:-}" in
  init)
    if [ -e "$ROOT/data" ]; then echo "exists: $ROOT/data (destroy first)"; exit 1; fi
    mkdir -p "$ROOT"
    "$PGBIN/initdb" -D "$(winpath "$ROOT/data")" -U postgres -A trust -E UTF8 \
      --locale=C --no-instructions >/dev/null
    cat >> "$ROOT/data/postgresql.conf" <<EOF

# --- krishna perf harness (mirrors krishna-mis-dev, D-313) ---
listen_addresses = ''
unix_socket_directories = '$(sockdir)'
port = $PORT
jit = off
shared_buffers = 224MB
work_mem = 2184kB
random_page_cost = 1.1
effective_cache_size = 384MB
max_parallel_workers_per_gather = 1
fsync = off
synchronous_commit = off
full_page_writes = off
EOF
    echo "initialised $ROOT/data"
    ;;
  start)
    "$PGBIN/pg_ctl" -D "$(winpath "$ROOT/data")" -l "$(winpath "$ROOT/server.log")" -w start >/dev/null
    echo "started: socket in $(sockdir), no TCP listener"
    ;;
  stop)
    "$PGBIN/pg_ctl" -D "$(winpath "$ROOT/data")" -m fast -w stop >/dev/null || true
    ;;
  destroy)
    "$PGBIN/pg_ctl" -D "$(winpath "$ROOT/data")" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$ROOT"
    echo "destroyed $ROOT"
    ;;
  schema)
    psql_ -d postgres -c "drop database if exists $DB" -c "create database $DB"
    psql_ -d "$DB" -f "$(winpath "$HERE/supabase_shim.sql")"
    # Ledger order, not filename order. The committed files replay in filename order with
    # one exception, found by this harness (D-317): `20260829090500_api_surface_invariant`
    # is the ledger's `api_surface_invariant_v5` (20260829133240), which the server applied
    # AFTER `20260829100000_usage_and_attachment_storage` (ledger 20260829132925 …133621),
    # because it names two functions that file creates. Filename order fails on it.
    early="$REPO/supabase/migrations/20260829090500_api_surface_invariant.sql"
    anchor="$REPO/supabase/migrations/20260829100000_usage_and_attachment_storage.sql"
    files=()
    for f in "$REPO"/supabase/migrations/*.sql; do
      [ "$f" = "$early" ] && continue
      files+=("$f")
      [ "$f" = "$anchor" ] && files+=("$early")
    done
    n=0
    for f in "${files[@]}"; do
      # The revenue baseline refuses to install without an owner to attribute it to; on
      # the server that was the development owner, bootstrapped by hand in Phase 2.
      case "$(basename "$f")" in
        20260901132225_*)
          psql_ -d "$DB" -f "$(winpath "$HERE/bootstrap_identities.sql")" >/dev/null ;;
      esac
      # The D-320 equivalence harness keeps the pre-redesign read paths beside the new ones:
      # captured once, just before the first migration after 20260912100000.
      if [ -z "${captured:-}" ] && [[ "$(basename "$f")" > "20260912100000_zzz" ]]; then
        psql_ -d "$DB" -f "$(winpath "$HERE/capture_old.sql")" >/dev/null
        captured=1
      fi
      if ! psql_ -d "$DB" -f "$(winpath "$f")" >/dev/null 2>"$ROOT/last_error.txt"; then
        echo "FAILED at $(basename "$f")"; cat "$ROOT/last_error.txt"; exit 1
      fi
      n=$((n+1))
    done
    echo "applied $n migrations"
    ;;
  *)
    sed -n '2,12p' "$0"; exit 2 ;;
esac
