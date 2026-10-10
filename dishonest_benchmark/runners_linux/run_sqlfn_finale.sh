#!/usr/bin/env bash
# ============================================================================
# run_sqlfn_finale.sh  --  ONE extra isolated finale:
#   "all cheats + batch x32 (SQL fn)"  = server-side LANGUAGE sql batch function
#   + prepared + all durability off + checkpoint tuning + drop FK.
# Linux port of runners/run_sqlfn_finale.ps1.
# Lets us compare the client-side IN-list finale (batch32.sql) against a
# server-side SQL-function finale. Appends one row to $RESULTS.
# RUN ONLY AFTER the other runs; never concurrently.
# ============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_results

OPS=32
NAME='all cheats + batch x32 (SQL fn)'
ALL_CHEATS="ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"

banner 36 ">>> $NAME  (batch32_sqlfn.sql, prepared, all cheats)"
restore_settings
recreate_database
build_schema
run_bench_file "$SQL/create_sqlfn.sql"
drop_fk
vacuum_analyze
run_bench "$ALL_CHEATS" >/dev/null
sleep 0.8
checkpoint

measure batch32_sqlfn.sql prepared
restore_settings
ops_sec=$(calc "$TPS * $OPS")
banner 32 "    tps=$TPS  ops/s=$ops_sec  lat=${LAT}ms"

base=$(csv_get "Indexed baseline" tps)
case0=$(csv_get "Case 0*" tps)
cli_tps=$(csv_get "all cheats + batch x32" tps)
csv_drop_methods "$NAME"   # idempotent re-run
idx=$(( $(csv_max_idx) + 1 ))
csv_line "$idx" "$NAME" batch32_sqlfn.sql prepared "$(calc "$TPS")" "$OPS" "$ops_sec" \
         "$LAT" "$WAL" "$WALPT" "$NTX" "$(ratio "$ops_sec" "$base")" "$(ratio "$ops_sec" "$case0")" >>"$RESULTS"

banner 33 "SQL-fn finale = $ops_sec ops/s   vs   client-side batch32 finale = $(calc "${cli_tps:-0} * 32") ops/s"
banner 33 "appended -> $RESULTS"
