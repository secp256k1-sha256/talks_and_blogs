#!/usr/bin/env bash
# Runs the whole redo in sequence (never concurrent): main 17-test suite, then
# the SQL-function comparisons, then the SQL-function finale. Each writes/appends
# to results_final.csv. Stops immediately if any stage fails.
# Linux port of runners/run_all.ps1.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
line=$(printf '=%.0s' {1..70})
for s in run_final.sh run_sqlfn.sh run_sqlfn_finale.sh; do
    printf '\033[35m%s\nRUNNING %s\n%s\033[0m\n' "$line" "$s" "$line"
    bash "$HERE/$s" || { echo "$s FAILED (exit $?)" >&2; exit 1; }
done
printf '\033[32mALL RUNS DONE\033[0m\n'
