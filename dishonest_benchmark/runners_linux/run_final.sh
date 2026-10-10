#!/usr/bin/env bash
# ============================================================================
# run_final.sh  --  "My Dishonest Benchmark" (fresh, fully-isolated run)
# Linux port of runners/run_final.ps1 -- same 17 tests, same protocol.
#
# STRONGEST isolation: every test DROPs and CREATEs the database from scratch,
# so each measurement starts from byte-for-byte identical initial conditions:
#   1. settings reverted to the documented baseline (admin conn -> postgres);
#   2. DROP DATABASE ... WITH (FORCE);  CREATE DATABASE;   (blog "Option A")
#   3. schema_load.sql  -> 100 branches, 1,000,000 accounts, 200k audit backlog;
#   4. setup_objects.sql -> PL/pgSQL procs + UNLOGGED tables;
#   5. VACUUM ANALYZE   (the "vacuum analyze after generating data");
#   6. CHECKPOINT       (each measured window starts from a fresh checkpoint).
# Only then is the per-test "cheat" applied and pgbench run for $DUR seconds.
# Writes (overwrites) $RESULTS.
# ============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ALL_DUR_OFF="ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();"
CKPT="ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"
ALL_CHEATS="ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"

# name | script | protocol | ops per txn | fk | pre-step SQL
TESTS=(
  # --- the honest part -----------------------------------------------------
  "Case 0: bad code / missing index|honest-ish.sql|simple|1||DROP INDEX IF EXISTS bench_audit_created_at_audit_id_idx; DROP INDEX IF EXISTS ix_bench_audit_created;"
  "Indexed baseline|honest-ish.sql|simple|1||"
  # --- durability / WAL settings cheats ------------------------------------
  "synchronous_commit=off|honest-ish.sql|simple|1||ALTER SYSTEM SET synchronous_commit=off; SELECT pg_reload_conf();"
  "full_page_writes=off|honest-ish.sql|simple|1||ALTER SYSTEM SET full_page_writes=off; SELECT pg_reload_conf();"
  "fsync=off|honest-ish.sql|simple|1||ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();"
  "checkpoint tuning|honest-ish.sql|simple|1||$CKPT"
  "all durability off|honest-ish.sql|simple|1||$ALL_DUR_OFF"
  # --- schema / storage / workload cheats ----------------------------------
  "less work (drop FK/SELECT/audit)|less_work.sql|simple|1|drop|"
  "UNLOGGED ledger/audit|unlogged.sql|simple|1||"
  # --- execution-shape cheats ----------------------------------------------
  "stored procedure|procedure.sql|simple|1||"
  "prepared protocol|honest-ish.sql|prepared|1||"
  "prepared + pipelined|honest-ish-pipeline.sql|prepared|1||"
  # --- unit-of-measurement cheats ------------------------------------------
  "batching x8|batch.sql|simple|8||"
  "batching x32|batch32.sql|simple|32||"
  # --- combination cheat (plpgsql + protocol) ------------------------------
  "stored proc + prepared|procedure.sql|prepared|1||"
  # --- stacked finales: every cheat at once, two ways ----------------------
  #   batch x32 wins ops/second (cheap IN-list); mega-batch wins ops/transaction.
  "all cheats + batch x32|batch32.sql|prepared|32|drop|$ALL_CHEATS"
  "all cheats + mega-batch x1000|megabatch.sql|prepared|1000|drop|$ALL_CHEATS"
)

banner 33 "=== setup: baseline ==="
apply_baseline

banner 90 "=== server warm-up ($WARM s) ==="
restore_settings; recreate_database; build_schema; vacuum_analyze
warm_up

R_ROWS=()        # CSV fields without the two x_vs_* columns, '|'-separated
R_OPS_SEC=()
case0=0; base=0
i=0
for t in "${TESTS[@]}"; do
    i=$((i + 1))
    IFS='|' read -r name script proto ops fk pre <<<"$t"
    banner 36 "$(printf '[%2d/%d] >>> %s  (%s, %s)' "$i" "${#TESTS[@]}" "$name" "$script" "$proto")"

    restore_settings
    recreate_database
    build_schema
    if [[ $fk == drop ]]; then drop_fk; fi
    vacuum_analyze
    if [[ -n $pre ]]; then run_bench "$pre" >/dev/null; sleep 0.8; fi
    checkpoint

    measure "$script" "$proto"
    ops_sec=$(calc "$TPS * $ops")
    banner 32 "        tps=$TPS  ops/s=$ops_sec  lat=${LAT}ms  wal/tx=${WALPT}B"

    R_ROWS+=("$i|$name|$script|$proto|$(calc "$TPS")|$ops|$ops_sec|$LAT|$WAL|$WALPT|$NTX")
    R_OPS_SEC+=("$ops_sec")
    if [[ $name == "Case 0"* ]]; then case0=$TPS; fi
    if [[ $name == "Indexed baseline" ]]; then base=$TPS; fi
done

# --- final cleanup: leave a clean, documented baseline database --------------
restore_settings; recreate_database; build_schema; vacuum_analyze

# --- derive the two "x improvement" columns ---------------------------------
csv_line idx method script protocol tps ops_per_txn ops_per_sec lat_ms wal_bytes wal_per_tx txns x_vs_baseline x_vs_case0 >"$RESULTS"
printf '\n%-4s %-34s %-9s %12s %14s %9s %11s %8s %8s\n' idx method protocol tps ops_per_sec lat_ms wal_per_tx x_base x_case0
for k in "${!R_ROWS[@]}"; do
    IFS='|' read -r -a f <<<"${R_ROWS[$k]}"
    xb=$(ratio "${R_OPS_SEC[$k]}" "$base")
    xc=$(ratio "${R_OPS_SEC[$k]}" "$case0")
    csv_line "${f[@]}" "$xb" "$xc" >>"$RESULTS"
    printf '%-4s %-34s %-9s %12s %14s %9s %11s %8s %8s\n' "${f[0]}" "${f[1]}" "${f[3]}" "${f[4]}" "${f[6]}" "${f[7]}" "${f[9]}" "$xb" "$xc"
done
banner 33 "DONE -> $RESULTS"
