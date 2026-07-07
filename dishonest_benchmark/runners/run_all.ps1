# Runs the whole redo in sequence (never concurrent): main 17-test suite, then
# the SQL-function comparisons, then the SQL-function finale. Each writes/appends
# to results_final.csv. Stops immediately if any stage fails.
$ErrorActionPreference = 'Stop'
$d = "C:\Users\mayuresh.bagayatkar\Downloads\dishonest_benchmark"
foreach ($s in @('run_final.ps1','run_sqlfn.ps1','run_sqlfn_finale.ps1')) {
    Write-Host ("=" * 70) -ForegroundColor Magenta
    Write-Host "RUNNING $s" -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta
    & pwsh -NoProfile -ExecutionPolicy Bypass -File "$d\$s"
    if ($LASTEXITCODE -ne 0) { throw "$s FAILED (exit $LASTEXITCODE)" }
}
Write-Host "ALL RUNS DONE" -ForegroundColor Green
