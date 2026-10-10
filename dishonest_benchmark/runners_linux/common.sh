#!/usr/bin/env bash
# ============================================================================
# common.sh  --  shared helpers for the Linux runners (sourced, not executed).
# Bash port of the helper functions duplicated across runners/*.ps1.
# Every knob can be overridden from the environment, e.g.
#   DUR=30 CLIENTS=16 THREADS=4 bash runners_linux/run_all.sh
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SQL="$ROOT/sql"
RESULTS="${RESULTS:-$ROOT/results_final.csv}"

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-6174316}"
BENCH_DB="${BENCH_DB:-pgbench_darkside}"   # recreated each test
ADMIN_DB="${ADMIN_DB:-postgres}"           # never dropped

DUR="${DUR:-120}"          # measured seconds per test (2 minutes)
WARM="${WARM:-15}"         # server warm-up seconds (spins up IO workers / bgwriter)
CLIENTS="${CLIENTS:-32}"
THREADS="${THREADS:-8}"

CSV_HEADER='"idx","method","script","protocol","tps","ops_per_txn","ops_per_sec","lat_ms","wal_bytes","wal_per_tx","txns","x_vs_baseline","x_vs_case0"'

for bin in psql pgbench awk sed; do
    command -v "$bin" >/dev/null || { echo "ERROR: '$bin' not found on PATH" >&2; exit 1; }
done

# SQL goes through stdin (not -c) so psql splits statements: ALTER SYSTEM,
# VACUUM and DROP DATABASE refuse to run inside a multi-statement -c string.
run_admin() { psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$ADMIN_DB" <<<"$1"; }
run_bench() { psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$BENCH_DB" <<<"$1"; }
run_bench_file() { psql -X -q -v ON_ERROR_STOP=1 -d "$BENCH_DB" -f "$1" >/dev/null; }
wal_lsn() { run_admin "SELECT pg_current_wal_lsn();"; }                   # cluster-wide
wal_diff() { run_admin "SELECT pg_wal_lsn_diff('$2'::pg_lsn,'$1'::pg_lsn)::bigint;"; }

# --- documented baseline (reloadable subset of reset_settings.sql) -----------
apply_baseline() {
    run_admin "
ALTER SYSTEM SET jit = off;
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET max_connections = 1000;
ALTER SYSTEM SET max_parallel_workers_per_gather = 0;
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '64MB';
ALTER SYSTEM SET default_statistics_target = 300;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET io_method = 'worker';
ALTER SYSTEM SET io_workers = 10;
ALTER SYSTEM SET effective_io_concurrency = 256;
ALTER SYSTEM SET io_max_concurrency = 128;
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET wal_compression = 'lz4';
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET full_page_writes = on;
ALTER SYSTEM SET fsync = on;
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET checkpoint_timeout = '10min';
ALTER SYSTEM RESET commit_delay;
SELECT pg_reload_conf();" >/dev/null
    sleep 0.5
    local pending
    pending=$(run_admin "SELECT string_agg(name, ', ') FROM pg_settings WHERE pending_restart;")
    if [[ -n $pending ]]; then
        echo "WARNING: restart-only settings not active yet: $pending" >&2
        echo "         run 'sudo systemctl restart postgresql@18-main' and re-run." >&2
    fi
}

# Revert only the knobs individual tests toggle, back to baseline.
restore_settings() {
    run_admin "
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET full_page_writes = on;
ALTER SYSTEM SET fsync = on;
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET checkpoint_timeout = '10min';
ALTER SYSTEM SET wal_compression = 'lz4';
ALTER SYSTEM RESET commit_delay;
SELECT pg_reload_conf();" >/dev/null
    sleep 0.4
}

# DROP + CREATE the whole database (blog "Option A"). WITH (FORCE) evicts any
# stray autovacuum / leftover session so the drop always succeeds.
recreate_database() {
    run_admin "DROP DATABASE IF EXISTS $BENCH_DB WITH (FORCE);" >/dev/null
    run_admin "CREATE DATABASE $BENCH_DB;" >/dev/null
}
build_schema() {
    run_bench_file "$SQL/schema_load.sql"     # tables + indexes + 1M accounts + 200k audit seed
    run_bench_file "$SQL/setup_objects.sql"   # PL/pgSQL procs + UNLOGGED tables
}
drop_fk() { run_bench "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;" >/dev/null; }
vacuum_analyze() { run_bench "VACUUM (ANALYZE);" >/dev/null; }
checkpoint() { run_bench "CHECKPOINT;" >/dev/null; }

warm_up() {
    pgbench -n -c "$CLIENTS" -j "$THREADS" -T "$WARM" -f "$SQL/honest-ish.sql" -d "$BENCH_DB" >/dev/null 2>&1 || true
}

# Parse pgbench output (stdin) into TPS LAT NTX.
parse_pgbench() {
    local out
    out=$(cat)
    TPS=$(sed -nE 's/^tps = ([0-9.]+) \(without initial.*/\1/p' <<<"$out" | head -n1)
    [[ -n $TPS ]] || TPS=$(sed -nE 's/^tps = ([0-9.]+).*/\1/p' <<<"$out" | head -n1)
    LAT=$(sed -nE 's/^latency average = ([0-9.]+) ms.*/\1/p' <<<"$out" | head -n1)
    NTX=$(sed -nE 's/^number of transactions actually processed: ([0-9]+).*/\1/p' <<<"$out" | head -n1)
    TPS=${TPS:-0}; LAT=${LAT:-0}; NTX=${NTX:-0}
}

# One measured pgbench run. Args: script protocol. Sets TPS LAT NTX WAL WALPT.
measure() {
    local script=$1 proto=$2 out rc=0 lsn_a lsn_b
    lsn_a=$(wal_lsn)
    out=$(pgbench -n -c "$CLIENTS" -j "$THREADS" -T "$DUR" -M "$proto" -f "$SQL/$script" -d "$BENCH_DB" 2>&1) || rc=$?
    lsn_b=$(wal_lsn)
    if (( rc != 0 )); then
        echo "WARNING: pgbench exited with $rc; last output lines:" >&2
        tail -n 15 <<<"$out" >&2
    fi
    WAL=$(wal_diff "$lsn_a" "$lsn_b")
    parse_pgbench <<<"$out"
    WALPT=$(awk -v w="$WAL" -v n="$NTX" 'BEGIN { if (n > 0) printf "%.1f", w / n; else print 0 }')
}

# Float helpers (bash has integer math only).
calc() { awk "BEGIN { printf \"%.2f\", $1 }"; }               # calc "a * b"
ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print 0 }'; }

# Quote every field like PowerShell Export-Csv does.
csv_line() {
    local line="" f
    for f in "$@"; do line+="${line:+,}\"${f//\"/\"\"}\""; done
    printf '%s\n' "$line"
}

# Read one column of the row whose method matches. Args: method column.
# A trailing '*' in method means prefix match (e.g. 'Case 0*').
csv_get() {
    awk -v m="$1" -v c="$2" '
        BEGIN { FS = "\",\""; pre = (m ~ /\*$/); if (pre) m = substr(m, 1, length(m) - 1) }
        { sub(/\r$/, ""); sub(/^"/, ""); sub(/"$/, "") }
        NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        (pre ? index($h["method"], m) == 1 : $h["method"] == m) { print $h[c]; exit }
    ' "$RESULTS"
}

# Drop rows whose method is in the given list (idempotent re-runs).
csv_drop_methods() {
    local tmp names
    tmp=$(mktemp)
    names=$(printf '%s\n' "$@")
    awk -v names="$names" '
        BEGIN { FS = "\",\""; n = split(names, a, "\n"); for (i = 1; i <= n; i++) skip[a[i]] = 1 }
        { line = $0; sub(/\r$/, ""); sub(/^"/, ""); sub(/"$/, "") }
        NR == 1 || !($2 in skip) { print line }
    ' "$RESULTS" >"$tmp"
    mv "$tmp" "$RESULTS"
}

csv_max_idx() {
    awk 'BEGIN { FS = "\",\""; max = 0 } NR > 1 { sub(/^"/, ""); if ($1 + 0 > max) max = $1 + 0 } END { print max }' "$RESULTS"
}

require_results() {
    [[ -f $RESULTS ]] || { echo "ERROR: $RESULTS not found -- run run_final.sh first." >&2; exit 1; }
}

banner() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }   # banner <ansi-color> <text>
