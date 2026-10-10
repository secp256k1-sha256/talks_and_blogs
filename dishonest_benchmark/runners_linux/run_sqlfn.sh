#!/usr/bin/env bash
# ============================================================================
# run_sqlfn.sh  --  isolated LANGUAGE sql vs LANGUAGE plpgsql comparison.
# Linux port of runners/run_sqlfn.ps1.
# Two extra tests, each fully isolated (drop/create DB, 1M accounts + 200k audit
# seed, VACUUM ANALYZE, CHECKPOINT, $DUR s), appended to $RESULTS:
#   * stored function (SQL)   -> compare vs 'stored procedure' (simple proto)
#   * sql function + prepared -> compare vs 'stored proc + prepared'
# RUN ONLY AFTER the main suite; never concurrently.
# ============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_results

# name | script | protocol
TESTS=(
  "stored function (SQL)|sqlfunction.sql|simple"
  "sql function + prepared|sqlfunction.sql|prepared"
)

declare -A NEW_TPS
NEW_ROWS=()
for t in "${TESTS[@]}"; do
    IFS='|' read -r name script proto <<<"$t"
    banner 36 ">>> $name  ($script, $proto)"
    restore_settings
    recreate_database
    build_schema
    run_bench_file "$SQL/create_sqlfn.sql"
    vacuum_analyze
    checkpoint

    measure "$script" "$proto"
    banner 32 "    tps=$TPS  lat=${LAT}ms"
    NEW_TPS[$name]=$TPS
    NEW_ROWS+=("$name|$script|$proto|$TPS|$LAT|$WAL|$WALPT|$NTX")
done

# --- append to results (recompute x columns from that file) ------------------
base=$(csv_get "Indexed baseline" tps)
case0=$(csv_get "Case 0*" tps)
proc=$(csv_get "stored procedure" tps)
procp=$(csv_get "stored proc + prepared" tps)
csv_drop_methods "stored function (SQL)" "sql function + prepared"   # idempotent re-run
idx=$(csv_max_idx)
for r in "${NEW_ROWS[@]}"; do
    IFS='|' read -r name script proto tps lat wal walpt ntx <<<"$r"
    idx=$((idx + 1))
    csv_line "$idx" "$name" "$script" "$proto" "$(calc "$tps")" 1 "$(calc "$tps")" \
             "$lat" "$wal" "$walpt" "$ntx" "$(ratio "$tps" "$base")" "$(ratio "$tps" "$case0")" >>"$RESULTS"
done

fn=${NEW_TPS["stored function (SQL)"]}
fnp=${NEW_TPS["sql function + prepared"]}
faster() { awk -v a="$1" -v b="$2" 'BEGIN { print (a > b) ? "FUNCTION faster" : "PROCEDURE faster" }'; }
banner 33 "==================== proc vs fn ===================="
echo "simple   : procedure ${proc:-?} tps   vs   function $fn tps  -> $(faster "$fn" "${proc:-0}")"
echo "prepared : proc+prep  ${procp:-?} tps   vs   fn+prep   $fnp tps  -> $(faster "$fnp" "${procp:-0}")"
banner 33 "appended -> $RESULTS"
