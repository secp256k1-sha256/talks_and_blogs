#!/usr/bin/env bash
# Warm-up: run ONCE before the first test (15 s, not measured).
# Usage (from anywhere):  bash simple_tests/linux/00_warmup.sh

export PGPASSWORD="${PGPASSWORD:-6174316}"
cd "$(dirname "$0")/../.."    # repo root

psql -h localhost -U postgres -d postgres -f reset_settings.sql
psql -h localhost -U postgres -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
psql -h localhost -U postgres -d postgres -c "CREATE DATABASE pgbench_darkside;"
psql -h localhost -U postgres -d pgbench_darkside -f sql/schema_load.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/setup_objects.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/create_sqlfn.sql
psql -h localhost -U postgres -d pgbench_darkside -c "VACUUM (ANALYZE);"

# Warm-up run (not measured)
pgbench -n -c 32 -j 8 -T 15 -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
