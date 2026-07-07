# ============================================================================
# run_final.ps1  --  "My Dishonest Benchmark" (fresh, fully-isolated run)
#
# STRONGEST isolation: every test DROPs and CREATEs the database from scratch,
# so each measurement starts from byte-for-byte identical initial conditions:
#   1. settings reverted to the documented baseline (admin conn -> postgres);
#   2. DROP DATABASE ... WITH (FORCE);  CREATE DATABASE;   (blog "Option A")
#   3. schema_load.sql  -> 100 branches, 1,000,000 accounts, 200k audit backlog;
#   4. setup_objects.sql -> PL/pgSQL procs + UNLOGGED tables;
#   5. VACUUM ANALYZE   (the "vacuum analyze after generating data");
#   6. CHECKPOINT       (each measured window starts from a fresh checkpoint).
# Only then is the per-test "cheat" applied and pgbench run for 120 s.
# ============================================================================
$ErrorActionPreference = 'Stop'
$env:PGPASSWORD = '6174316'
$env:PATH = "C:\Program Files\PostgreSQL\18\bin;$env:PATH"
$d = "C:\Users\mayuresh.bagayatkar\Downloads\dishonest_benchmark"
$ADMIN = @('-h','localhost','-U','postgres','-d','postgres')          # never dropped
$BENCH = @('-h','localhost','-U','postgres','-d','pgbench_darkside')   # recreated each test
$DUR  = 120         # measured seconds per test (2 minutes)
$WARM = 15          # server warm-up seconds (spins up IO workers / bgwriter)
$C = 32; $J = 8     # clients / threads

function RunAdmin([string]$sql) { ($sql | & psql @ADMIN -X -q -t -A -v ON_ERROR_STOP=1) -join "`n" }
function RunBench([string]$sql) { ($sql | & psql @BENCH -X -q -t -A -v ON_ERROR_STOP=1) -join "`n" }
function RunBenchFile([string]$f) { & psql @BENCH -X -q -v ON_ERROR_STOP=1 -f $f | Out-Null }
function WalLsn() { (RunAdmin "SELECT pg_current_wal_lsn();").Trim() }              # cluster-wide
function WalDiff($a,$b) { [int64]((RunAdmin "SELECT pg_wal_lsn_diff('$b'::pg_lsn,'$a'::pg_lsn);").Trim()) }

# --- documented baseline (reloadable subset of the blog's reset_settings.sql) --
function ApplyBaseline {
    RunAdmin @"
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
SELECT pg_reload_conf();
"@ | Out-Null
    Start-Sleep -Milliseconds 500
}

# Revert only the knobs individual tests toggle, back to baseline.
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

# DROP + CREATE the whole database (blog "Option A"). WITH (FORCE) evicts any
# stray autovacuum / leftover session so the drop always succeeds.
function RecreateDatabase {
    RunAdmin "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);" | Out-Null
    RunAdmin "CREATE DATABASE pgbench_darkside;" | Out-Null
}
function BuildSchema {
    RunBenchFile "$d\schema_load.sql"     # tables + indexes + 1M accounts + 200k audit seed
    RunBenchFile "$d\setup_objects.sql"   # PL/pgSQL procs + UNLOGGED tables
}
function DropFK { RunBench "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;" | Out-Null }
function VacuumAnalyze { RunBench "VACUUM (ANALYZE);" | Out-Null }

$ALL_DUR_OFF = "ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();"
$CKPT        = "ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"
$ALL_CHEATS  = "ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();"

$tests = @(
  # --- the honest part -----------------------------------------------------
  @{ Name='Case 0: bad code / missing index'; Script='honest-ish.sql';
     Pre="DROP INDEX IF EXISTS bench_audit_created_at_audit_id_idx; DROP INDEX IF EXISTS ix_bench_audit_created;" }
  @{ Name='Indexed baseline';                 Script='honest-ish.sql' }
  # --- durability / WAL settings cheats ------------------------------------
  @{ Name='synchronous_commit=off'; Script='honest-ish.sql'; Pre="ALTER SYSTEM SET synchronous_commit=off; SELECT pg_reload_conf();" }
  @{ Name='full_page_writes=off';   Script='honest-ish.sql'; Pre="ALTER SYSTEM SET full_page_writes=off; SELECT pg_reload_conf();" }
  @{ Name='fsync=off';              Script='honest-ish.sql'; Pre="ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();" }
  @{ Name='checkpoint tuning';      Script='honest-ish.sql'; Pre=$CKPT }
  @{ Name='all durability off';     Script='honest-ish.sql'; Pre=$ALL_DUR_OFF }
  # --- schema / storage / workload cheats ----------------------------------
  @{ Name='less work (drop FK/SELECT/audit)'; Script='less_work.sql'; FK='drop' }
  @{ Name='UNLOGGED ledger/audit';            Script='unlogged.sql' }
  # --- execution-shape cheats ----------------------------------------------
  @{ Name='stored procedure';       Script='procedure.sql' }
  @{ Name='prepared protocol';      Script='honest-ish.sql';          Protocol='prepared' }
  @{ Name='prepared + pipelined';   Script='honest-ish-pipeline.sql'; Protocol='prepared' }
  # --- unit-of-measurement cheats ------------------------------------------
  @{ Name='batching x8';            Script='batch.sql';   Ops=8 }
  @{ Name='batching x32';           Script='batch32.sql'; Ops=32 }
  # --- combination cheat (plpgsql + protocol) ------------------------------
  @{ Name='stored proc + prepared'; Script='procedure.sql'; Protocol='prepared' }
  # --- stacked finales: every cheat at once, two ways ----------------------
  #   batch x32 wins ops/second (cheap IN-list); mega-batch wins ops/transaction.
  @{ Name='all cheats + batch x32'; Script='batch32.sql'; Protocol='prepared'; FK='drop'; Ops=32;  Pre=$ALL_CHEATS }
  @{ Name='all cheats + mega-batch x1000'; Script='megabatch.sql'; Protocol='prepared'; FK='drop'; Ops=1000; Pre=$ALL_CHEATS }
)

Write-Host "=== setup: baseline ===" -ForegroundColor Yellow
ApplyBaseline

Write-Host "=== server warm-up ($WARM s) ===" -ForegroundColor DarkGray
RestoreSettings; RecreateDatabase; BuildSchema; VacuumAnalyze
& pgbench -n -c $C -j $J -T $WARM -f "$d\honest-ish.sql" @BENCH *> $null

$results = @()
$i = 0
foreach ($t in $tests) {
    $i++
    $script = $t.Script
    $proto  = if ($t.Protocol) { $t.Protocol } else { 'simple' }
    $ops    = if ($t.Ops) { [int]$t.Ops } else { 1 }
    Write-Host ("[{0,2}/{1}] >>> {2}  ({3}, {4})" -f $i,$tests.Count,$t.Name,$script,$proto) -ForegroundColor Cyan

    RestoreSettings
    RecreateDatabase
    BuildSchema
    if ($t.FK -eq 'drop') { DropFK }
    VacuumAnalyze
    if ($t.Pre) { RunBench $t.Pre | Out-Null; Start-Sleep -Milliseconds 800 }
    RunBench "CHECKPOINT;" | Out-Null

    $lsnA = WalLsn
    $out  = & pgbench -n -c $C -j $J -T $DUR -M $proto -f "$d\$script" @BENCH 2>&1 | Out-String
    $lsnB = WalLsn
    $wal  = WalDiff $lsnA $lsnB

    $tps = if ($out -match 'tps = ([\d.]+) \(without initial') { [double]$Matches[1] } elseif ($out -match 'tps = ([\d.]+)') { [double]$Matches[1] } else { 0 }
    $lat = if ($out -match 'latency average = ([\d.]+) ms') { [double]$Matches[1] } else { 0 }
    $ntx = if ($out -match 'number of transactions actually processed: (\d+)') { [int64]$Matches[1] } else { 0 }
    $walpt = if ($ntx -gt 0) { [math]::Round($wal/$ntx,1) } else { 0 }
    Write-Host ("        tps={0:N0}  ops/s={1:N0}  lat={2}ms  wal/tx={3}B" -f $tps,($tps*$ops),$lat,$walpt) -ForegroundColor Green

    $results += [pscustomobject]@{
        idx=$i; method=$t.Name; script=$script; protocol=$proto
        tps=[math]::Round($tps,2); ops_per_txn=$ops; ops_per_sec=[math]::Round($tps*$ops,2)
        lat_ms=$lat; wal_bytes=$wal; wal_per_tx=$walpt; txns=$ntx
    }
}

# --- final cleanup: leave a clean, documented baseline database --------------
RestoreSettings; RecreateDatabase; BuildSchema; VacuumAnalyze

# --- derive the two "x improvement" columns ---------------------------------
$case0 = ($results | Where-Object { $_.method -like 'Case 0*' }).tps
$base  = ($results | Where-Object { $_.method -eq 'Indexed baseline' }).tps
foreach ($r in $results) {
    $r | Add-Member -NotePropertyName x_vs_baseline -NotePropertyValue ([math]::Round($r.ops_per_sec / $base, 2))
    $r | Add-Member -NotePropertyName x_vs_case0    -NotePropertyValue ([math]::Round($r.ops_per_sec / $case0, 2))
}

$results | Export-Csv -Path "$d\results_final.csv" -NoTypeInformation -Encoding UTF8
$results | Format-Table idx,method,protocol,tps,ops_per_sec,lat_ms,wal_per_tx,x_vs_baseline,x_vs_case0 -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "DONE -> $d\results_final.csv" -ForegroundColor Yellow
