# Test 8: Less work: drop FK / SELECT / audit
# 2-minute run. Usage (from anywhere):  pwsh simple_tests\windows\08_less_work.ps1
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
psql -h localhost -U postgres -d pgbench_darkside -c "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;"

# 3. Start the measured window from a fresh checkpoint
psql -h localhost -U postgres -d pgbench_darkside -c "CHECKPOINT;"

# 4. Measured run: 2 minutes (-T 120)
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/less_work.sql -h localhost -U postgres -d pgbench_darkside

# 5. Put the honest settings back
psql -h localhost -U postgres -d postgres -f reset_settings.sql
