# ============================================================================
# run_sqlfn_finale.ps1  --  ONE extra isolated finale:
#   "all cheats + batch x32 (SQL fn)"  = server-side LANGUAGE sql batch function
#   + prepared + all durability off + checkpoint tuning + drop FK.
# Lets us compare the client-side IN-list finale (batch32.sql) against a
# server-side SQL-function finale. Appends one row to results_final.csv.
# RUN ONLY AFTER the other runs; never concurrently.
# ============================================================================
$ErrorActionPreference = 'Stop'
$env:PGPASSWORD = '6174316'
$env:PATH = "C:\Program Files\PostgreSQL\18\bin;$env:PATH"
$d = "C:\Users\mayuresh.bagayatkar\Downloads\dishonest_benchmark"
$ADMIN = @('-h','localhost','-U','postgres','-d','postgres')
$BENCH = @('-h','localhost','-U','postgres','-d','pgbench_darkside')
$DUR = 120; $C = 32; $J = 8
$OPS = 32
$NAME = 'all cheats + batch x32 (SQL fn)'
$ALL_CHEATS = "ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"

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

Write-Host ">>> $NAME  (batch32_sqlfn.sql, prepared, all cheats)" -ForegroundColor Cyan
RestoreSettings
RunAdmin "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);" | Out-Null
RunAdmin "CREATE DATABASE pgbench_darkside;" | Out-Null
RunBenchFile "$d\schema_load.sql"
RunBenchFile "$d\setup_objects.sql"
RunBenchFile "$d\create_sqlfn.sql"
RunBench "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;" | Out-Null
RunBench "VACUUM (ANALYZE);" | Out-Null
RunBench $ALL_CHEATS | Out-Null
Start-Sleep -Milliseconds 800
RunBench "CHECKPOINT;" | Out-Null

$lsnA = WalLsn
$out  = & pgbench -n -c $C -j $J -T $DUR -M prepared -f "$d\batch32_sqlfn.sql" @BENCH 2>&1 | Out-String
$lsnB = WalLsn
$wal  = WalDiff $lsnA $lsnB
RestoreSettings
$tps = if ($out -match 'tps = ([\d.]+) \(without initial') { [double]$Matches[1] } elseif ($out -match 'tps = ([\d.]+)') { [double]$Matches[1] } else { 0 }
$lat = if ($out -match 'latency average = ([\d.]+) ms') { [double]$Matches[1] } else { 0 }
$ntx = if ($out -match 'number of transactions actually processed: (\d+)') { [int64]$Matches[1] } else { 0 }
$walpt = if ($ntx -gt 0) { [math]::Round($wal/$ntx,1) } else { 0 }
Write-Host ("    tps={0:N0}  ops/s={1:N0}  lat={2}ms" -f $tps,($tps*$OPS),$lat) -ForegroundColor Green

$rows  = @(Import-Csv "$d\results_final.csv")
$base  = [double](($rows | Where-Object { $_.method -eq 'Indexed baseline' }).tps)
$case0 = [double](($rows | Where-Object { $_.method -like 'Case 0*' }).tps)
$rows  = $rows | Where-Object { $_.method -ne $NAME }
$idx   = ((($rows | ForEach-Object { [int]$_.idx }) | Measure-Object -Maximum).Maximum) + 1
$newrow = [pscustomobject]@{
    idx=$idx; method=$NAME; script='batch32_sqlfn.sql'; protocol='prepared'
    tps=[math]::Round($tps,2); ops_per_txn=$OPS; ops_per_sec=[math]::Round($tps*$OPS,2)
    lat_ms=$lat; wal_bytes=$wal; wal_per_tx=$walpt; txns=$ntx
    x_vs_baseline=[math]::Round($tps*$OPS/$base,2); x_vs_case0=[math]::Round($tps*$OPS/$case0,2)
}
$all = @($rows) + $newrow
$all | Export-Csv -Path "$d\results_final.csv" -NoTypeInformation -Encoding UTF8

$cli = [double](($rows | Where-Object { $_.method -eq 'all cheats + batch x32' }).tps) * 32
Write-Host ("SQL-fn finale = {0:N0} ops/s   vs   client-side batch32 finale = {1:N0} ops/s" -f ($tps*$OPS),$cli) -ForegroundColor Yellow
Write-Host "appended -> $d\results_final.csv" -ForegroundColor Yellow
