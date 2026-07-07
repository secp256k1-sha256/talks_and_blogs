================================================================================
MY DISHONEST BENCHMARK -- reproduction pack
pgbench commands + SQL/text files used
================================================================================
Host   : Intel Core i7-13700 (16c/24t), 63.8 GB RAM, Samsung SSD 980 NVMe
DB     : PostgreSQL 18.4 (x86_64), Windows 11
Driver : pgbench 18.4
Load   : 32 clients / 8 threads, 120 s measured per test
Conn   : -h localhost -U postgres -d pgbench_darkside   (env: PGPASSWORD=6174316)
Data   : 100 branches, 1,000,000 accounts (balance 100000); bench_audit pre-seeded
         with a 200,000-row recent backlog.

--------------------------------------------------------------------------------
FILE MANIFEST
--------------------------------------------------------------------------------
reset_settings.sql            honest baseline server config (ALTER SYSTEM)
sql/schema_load.sql           create tables + load 1M accounts + 200k audit seed + VACUUM ANALYZE + CHECKPOINT
sql/setup_objects.sql         PL/pgSQL procedures (bench_txn, bench_txn_megabatch) + UNLOGGED tables
sql/create_sqlfn.sql          LANGUAGE sql functions (bench_txn_sqlfn, bench_txn_batch_sqlfn)
sql/honest-ish.sql            the indexed baseline transaction (read+update+2 inserts+trim)
sql/less_work.sql             Cheat 3: fewer statements (update + ledger insert only)
sql/unlogged.sql              Cheat 4: writes to UNLOGGED ledger/audit
sql/procedure.sql             Cheat 5: CALL bench_txn(:aid,:delta)   (PL/pgSQL)
sql/honest-ish-pipeline.sql   pipelined variant (run but excluded from the blog/PDF)
sql/batch.sql                 Cheat 6: 8 accounts per transaction (client IN-list)
sql/batch32.sql               32 accounts per transaction (client IN-list)
sql/sqlfunction.sql           SELECT bench_txn_sqlfn(:aid,:delta)    (LANGUAGE sql)
sql/batch32_sqlfn.sql         SELECT bench_txn_batch_sqlfn(ARRAY[32 ids], :delta)  (server-side batch)
sql/megabatch.sql             CALL bench_txn_megabatch(1000)  (run but excluded from the blog/PDF)
runners/*.ps1                 the PowerShell harness that orchestrated everything

--------------------------------------------------------------------------------
PER-TEST PROTOCOL (identical initial conditions for every test)
--------------------------------------------------------------------------------
Before EVERY test the harness does, in order:
  1. revert toggled settings to reset_settings.sql values (ALTER SYSTEM + pg_reload_conf)
  2. psql -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
     psql -d postgres -c "CREATE DATABASE pgbench_darkside;"
  3. psql -d pgbench_darkside -f sql/schema_load.sql      (data + indexes + VACUUM ANALYZE + CHECKPOINT)
     psql -d pgbench_darkside -f sql/setup_objects.sql    (procs + unlogged tables)
     psql -d pgbench_darkside -f sql/create_sqlfn.sql     (sql functions; only needed by fn tests)
  4. apply that test's "cheat" (the Pre step below), if any
  5. psql -d pgbench_darkside -c "VACUUM (ANALYZE);"
     psql -d pgbench_darkside -c "CHECKPOINT;"
  6. run the pgbench command
Restart params (wal_buffers, io_workers, io_method, shared_buffers, max_connections,
io_max_concurrency) were applied once via ALTER SYSTEM + a service restart:
     Restart-Service postgresql-x64-18 -Force

Global warm-up (once, before the suite):
  pgbench -n -c 32 -j 8 -T 15 -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside

--------------------------------------------------------------------------------
PGBENCH COMMANDS (one per test; all use -n -c 32 -j 8 -T 120)
Connection suffix on every line: -h localhost -U postgres -d pgbench_darkside
--------------------------------------------------------------------------------

# 1. Case 0: bad code / missing index
#    Pre: DROP INDEX IF EXISTS bench_audit_created_at_audit_id_idx; DROP INDEX IF EXISTS ix_bench_audit_created;
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 2. Indexed baseline
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 3. synchronous_commit=off
#    Pre: ALTER SYSTEM SET synchronous_commit=off; SELECT pg_reload_conf();
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 4. full_page_writes=off
#    Pre: ALTER SYSTEM SET full_page_writes=off; SELECT pg_reload_conf();
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 5. fsync=off
#    Pre: ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 6. checkpoint tuning
#    Pre: ALTER SYSTEM SET max_wal_size='64GB'; ALTER SYSTEM SET checkpoint_timeout='30min'; SELECT pg_reload_conf();
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 7. all durability off
#    Pre: ALTER SYSTEM SET synchronous_commit=off; ALTER SYSTEM SET full_page_writes=off; ALTER SYSTEM SET fsync=off; SELECT pg_reload_conf();
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 8. less work (drop FK/SELECT/audit)
#    Pre: ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/less_work.sql           -h localhost -U postgres -d pgbench_darkside

# 9. UNLOGGED ledger/audit
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/unlogged.sql            -h localhost -U postgres -d pgbench_darkside

# 10. stored procedure (PL/pgSQL)
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/procedure.sql           -h localhost -U postgres -d pgbench_darkside

# 11. prepared protocol
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish.sql          -h localhost -U postgres -d pgbench_darkside

# 12. prepared + pipelined            (RUN, but excluded from the blog/PDF)
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish-pipeline.sql -h localhost -U postgres -d pgbench_darkside

# 13. batching x8
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/batch.sql               -h localhost -U postgres -d pgbench_darkside

# 14. batching x32
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/batch32.sql             -h localhost -U postgres -d pgbench_darkside

# 15. stored proc + prepared
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/procedure.sql           -h localhost -U postgres -d pgbench_darkside

# 16. all cheats + batch x32 (client-side IN-list)
#    Pre: sync/fpw/fsync=off; max_wal_size='64GB'; checkpoint_timeout='30min'; SELECT pg_reload_conf();
#         + ALTER TABLE bench_accounts DROP CONSTRAINT ... (drop FK)
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32.sql             -h localhost -U postgres -d pgbench_darkside

# 17. all cheats + mega-batch x1000   (RUN, but excluded from the blog/PDF)
#    Pre: all cheats (as #16) + drop FK
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/megabatch.sql           -h localhost -U postgres -d pgbench_darkside

# 18. stored function (SQL)
pgbench -n -c 32 -j 8 -T 120 -M simple   -f sql/sqlfunction.sql         -h localhost -U postgres -d pgbench_darkside

# 19. sql function + prepared
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/sqlfunction.sql         -h localhost -U postgres -d pgbench_darkside

# 20. all cheats + batch x32 (SQL fn)   <-- the grand finale
#    Pre: all cheats (as #16) + drop FK
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32_sqlfn.sql       -h localhost -U postgres -d pgbench_darkside

--------------------------------------------------------------------------------
NOTES
--------------------------------------------------------------------------------
* "reported OPS" = tps x operations-per-transaction (8/32/1000 for batched/mega;
  1 otherwise). Batched tests are counted in operations/second; all others in TPS.
* Tests 12 (prepared+pipelined) and 17 (mega-batch) were executed and are present
  in results_final.csv, but are intentionally NOT shown in the completed blog/PDF.
* To reproduce the whole suite end-to-end, run runners/run_all.ps1 (it chains
  run_final.ps1 -> run_sqlfn.ps1 -> run_sqlfn_finale.ps1). Paths inside those
  scripts point at the original ...\dishonest_benchmark folder.
================================================================================
