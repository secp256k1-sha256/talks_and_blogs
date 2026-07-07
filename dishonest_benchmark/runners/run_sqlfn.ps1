# ============================================================================
# run_sqlfn.ps1  --  isolated LANGUAGE sql vs LANGUAGE plpgsql comparison.
# Two extra tests, each fully isolated (drop/create DB, 1M accounts + 200k audit
# seed, VACUUM ANALYZE, CHECKPOINT, 120 s), appended to results_final.csv:
#   * stored function (SQL)   -> compare vs 'stored procedure' (simple proto)
#   * sql function + prepared -> compare vs 'stored proc + prepared'
# RUN ONLY AFTER the main suite; never concurrently.
# ============================================================================
$ErrorActionPreference = 'Stop'
$env:PGPASSWORD = '6174316'
$env:PATH = "C:\Program Files\PostgreSQL\18\bin;$env:PATH"
$d = "C:\Users\mayuresh.bagayatkar\Downloads\dishonest_benchmark"
$ADMIN = @('-h','localhost','-U','postgres','-d','postgres')
$BENCH = @('-h','localhost','-U','postgres','-d','pgbench_darkside')
$DUR = 120; $C = 32; $J = 8

function RunAdmin([string]$s) { ($s | & psql @ADMIN -X -q -t -A -v ON_ERROR_STOP=1) -join "`n" }
function RunBench([string]$s) { ($s | & psql @BENCH -X -q -t -A -v ON_ERROR_STOP=1) -join "`n" }
function RunBenchFile([string]$f) { & psql @BENCH -X -q -v ON_ERROR_STOP=1 -f $f | Out-Null }
function WalLsn() { (RunAdmin "SELECT pg_current_wal_lsn();").Trim() }
function WalDiff($a,$b) { [int64]((RunAdmin "SELECT pg_wal_lsn_diff('$b'::pg_lsn,'$a'::pg_lsn);").Trim()) }
function RestoreSettings {
    RunAdmin @"
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET full_page_writes = on;
ALTER SYSTEM SET fsync = on;
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET checkpoint_timeout = '10min';
ALTER SYSTEM SET wal_compression = 'lz4';
ALTER SYSTEM RESET commit_delay;
SELECT pg_reload_conf();
"@ | Out-Null
    Start-Sleep -Milliseconds 400
}

$tests = @(
  @{ Name='stored function (SQL)';   Script='sqlfunction.sql'; Proto='simple'   }
  @{ Name='sql function + prepared'; Script='sqlfunction.sql'; Proto='prepared' }
)

$new = @()
foreach ($t in $tests) {
    Write-Host (">>> {0}  ({1}, {2})" -f $t.Name,$t.Script,$t.Proto) -ForegroundColor Cyan
    RestoreSettings
    RunAdmin "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);" | Out-Null
    RunAdmin "CREATE DATABASE pgbench_darkside;" | Out-Null
    RunBenchFile "$d\schema_load.sql"
    RunBenchFile "$d\setup_objects.sql"
    RunBenchFile "$d\create_sqlfn.sql"
    RunBench "VACUUM (ANALYZE);" | Out-Null
    RunBench "CHECKPOINT;" | Out-Null

    $lsnA = WalLsn
    $out  = & pgbench -n -c $C -j $J -T $DUR -M $t.Proto -f "$d\$($t.Script)" @BENCH 2>&1 | Out-String
    $lsnB = WalLsn
    $wal  = WalDiff $lsnA $lsnB
    $tps = if ($out -match 'tps = ([\d.]+) \(without initial') { [double]$Matches[1] } elseif ($out -match 'tps = ([\d.]+)') { [double]$Matches[1] } else { 0 }
    $lat = if ($out -match 'latency average = ([\d.]+) ms') { [double]$Matches[1] } else { 0 }
    $ntx = if ($out -match 'number of transactions actually processed: (\d+)') { [int64]$Matches[1] } else { 0 }
    $walpt = if ($ntx -gt 0) { [math]::Round($wal/$ntx,1) } else { 0 }
    Write-Host ("    tps={0:N0}  lat={1}ms" -f $tps,$lat) -ForegroundColor Green
    $new += [pscustomobject]@{ Name=$t.Name; Script=$t.Script; Proto=$t.Proto; tps=$tps; lat=$lat; wal=$wal; walpt=$walpt; ntx=$ntx }
}

# --- append to results_final.csv (recompute x columns from that file) --------
$rows  = @(Import-Csv "$d\results_final.csv")
$base  = [double](($rows | Where-Object { $_.method -eq 'Indexed baseline' }).tps)
$case0 = [double](($rows | Where-Object { $_.method -like 'Case 0*' }).tps)
$names = $tests | ForEach-Object { $_.Name }
$rows  = $rows | Where-Object { $names -notcontains $_.method }        # idempotent re-run
$idx   = ((($rows | ForEach-Object { [int]$_.idx }) | Measure-Object -Maximum).Maximum)
$append = @()
foreach ($r in $new) {
    $idx++
    $append += [pscustomobject]@{
        idx=$idx; method=$r.Name; script=$r.Script; protocol=$r.Proto
        tps=[math]::Round($r.tps,2); ops_per_txn=1; ops_per_sec=[math]::Round($r.tps,2)
        lat_ms=$r.lat; wal_bytes=$r.wal; wal_per_tx=$r.walpt; txns=$r.ntx
        x_vs_baseline=[math]::Round($r.tps/$base,2); x_vs_case0=[math]::Round($r.tps/$case0,2)
    }
}
$all = @($rows) + $append
$all | Export-Csv -Path "$d\results_final.csv" -NoTypeInformation -Encoding UTF8

$proc  = [double](($rows | Where-Object { $_.method -eq 'stored procedure' }).tps)
$procp = [double](($rows | Where-Object { $_.method -eq 'stored proc + prepared' }).tps)
$fn    = ($new | Where-Object { $_.Name -eq 'stored function (SQL)' }).tps
$fnp   = ($new | Where-Object { $_.Name -eq 'sql function + prepared' }).tps
Write-Host "==================== proc vs fn ====================" -ForegroundColor Yellow
Write-Host ("simple   : procedure {0:N0} tps   vs   function {1:N0} tps  -> {2}" -f $proc,$fn, $(if($fn -gt $proc){"FUNCTION faster"}else{"PROCEDURE faster"}))
Write-Host ("prepared : proc+prep  {0:N0} tps   vs   fn+prep   {1:N0} tps  -> {2}" -f $procp,$fnp, $(if($fnp -gt $procp){"FUNCTION faster"}else{"PROCEDURE faster"}))
Write-Host "appended -> $d\results_final.csv" -ForegroundColor Yellow
