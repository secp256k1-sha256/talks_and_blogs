#!/usr/bin/env bash
# Test 2: Indexed baseline
# 2-minute run. Usage (from anywhere):  bash simple_tests/linux/02_indexed_baseline.sh

export PGPASSWORD="${PGPASSWORD:-6174316}"
cd "$(dirname "$0")/../.."    # repo root

# 1. Reset: honest baseline settings + a brand-new database
psql -h localhost -U postgres -d postgres -f reset_settings.sql
psql -h localhost -U postgres -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
psql -h localhost -U postgres -d postgres -c "CREATE DATABASE pgbench_darkside;"
psql -h localhost -U postgres -d pgbench_darkside -f sql/schema_load.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/setup_objects.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/create_sqlfn.sql
psql -h localhost -U postgres -d pgbench_darkside -c "VACUUM (ANALYZE);"

# 2. Make sure the index exists (test 1 drops it)
psql -h localhost -U postgres -d pgbench_darkside -c "CREATE INDEX IF NOT EXISTS bench_audit_created_at_audit_id_idx ON bench_audit(created_at, audit_id);"

# 3. Start the measured window from a fresh checkpoint
psql -h localhost -U postgres -d pgbench_darkside -c "CHECKPOINT;"

# 4. Measured run: 2 minutes (-T 120)
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside

# 5. Put the honest settings back
psql -h localhost -U postgres -d postgres -f reset_settings.sql
