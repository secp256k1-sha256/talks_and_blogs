# Test 17: All cheats + mega-batch x1000 (excluded from blog/PDF)
# 2-minute run. Usage (from anywhere):  pwsh simple_tests\windows\17_all_cheats_megabatch_x1000.ps1
# psql and pgbench must be on PATH (e.g. C:\Program Files\PostgreSQL\18\bin).

if (-not $env:PGPASSWORD) { $env:PGPASSWORD = '6174316' }
Set-Location (Join-Path $PSScriptRoot '..\..')    # repo root

# 1. Reset: honest baseline settings + a brand-new database
psql -h localhost -U postgres -d postgres -f reset_settings.sql
psql -h localhost -U postgres -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
psql -h localhost -U postgres -d postgres -c "CREATE DATABASE pgbench_darkside;"
psql -h localhost -U postgres -d pgbench_darkside -f sql/schema_load.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/setup_objects.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/create_sqlfn.sql
psql -h localhost -U postgres -d pgbench_darkside -c "VACUUM (ANALYZE);"

# 2. The cheat for this test
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET synchronous_commit = off;" -c "ALTER SYSTEM SET full_page_writes = off;" -c "ALTER SYSTEM SET fsync = off;" -c "ALTER SYSTEM SET max_wal_size = '64GB';" -c "ALTER SYSTEM SET checkpoint_timeout = '30min';" -c "SELECT pg_reload_conf();"
psql -h localhost -U postgres -d pgbench_darkside -c "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;"

# 3. Start the measured window from a fresh checkpoint
psql -h localhost -U postgres -d pgbench_darkside -c "CHECKPOINT;"

# 4. Measured run: 2 minutes (-T 120)
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/megabatch.sql -h localhost -U postgres -d pgbench_darkside

# 5. Put the honest settings back
psql -h localhost -U postgres -d postgres -f reset_settings.sql

# Reported ops/sec = tps x 1000  (one transaction does 1000 operations)
