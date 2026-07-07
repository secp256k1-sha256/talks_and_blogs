# My Dishonest Benchmark

> Reproduction pack for the **“Dishonest Benchmark”** PostgreSQL pgbench experiments.
> Includes the SQL scripts, server-setting toggles, and PowerShell runners used to reproduce the benchmark cases.

---

## Benchmark Environment

| Area            | Value                                          |
| --------------- | ---------------------------------------------- |
| Host            | Intel Core i7-13700, 16 cores / 24 threads     |
| RAM             | 63.8 GB                                        |
| Storage         | Samsung SSD 980 NVMe                           |
| OS              | Windows 11                                     |
| Database        | PostgreSQL 18.4, x86_64                        |
| Driver          | pgbench 18.4                                   |
| Test duration   | 120 seconds per measured test                  |
| Load            | 32 clients / 8 threads                         |
| Database        | `pgbench_darkside`                             |
| Connection      | `-h localhost -U postgres -d pgbench_darkside` |
| Password source | `PGPASSWORD=6174316`                           |
| Dataset         | 100 branches, 1,000,000 accounts               |
| Audit seed      | 200,000 recent rows in `bench_audit`           |

---

## What This Repo Contains

| Path                          | Purpose                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `reset_settings.sql`          | Restores the honest baseline server configuration using `ALTER SYSTEM`                           |
| `sql/schema_load.sql`         | Creates tables, loads 1M accounts, seeds 200k audit rows, runs `VACUUM ANALYZE` and `CHECKPOINT` |
| `sql/setup_objects.sql`       | Creates PL/pgSQL procedures such as `bench_txn` and `bench_txn_megabatch`                        |
| `sql/create_sqlfn.sql`        | Creates `LANGUAGE sql` functions used by SQL-function tests                                      |
| `sql/honest-ish.sql`          | Indexed baseline transaction: read, update, two inserts, trim                                    |
| `sql/less_work.sql`           | Reduced-work variant: update + ledger insert only                                                |
| `sql/unlogged.sql`            | Writes to `UNLOGGED` ledger/audit tables                                                         |
| `sql/procedure.sql`           | Calls `bench_txn(:aid, :delta)` through PL/pgSQL                                                 |
| `sql/honest-ish-pipeline.sql` | Pipelined variant, run but excluded from blog/PDF                                                |
| `sql/batch.sql`               | 8 accounts per transaction using client-side `IN` list                                           |
| `sql/batch32.sql`             | 32 accounts per transaction using client-side `IN` list                                          |
| `sql/sqlfunction.sql`         | Calls `bench_txn_sqlfn(:aid, :delta)`                                                            |
| `sql/batch32_sqlfn.sql`       | Calls `bench_txn_batch_sqlfn(...)` for server-side batch                                         |
| `sql/megabatch.sql`           | Calls `bench_txn_megabatch(1000)`, run but excluded from blog/PDF                                |
| `runners/*.ps1`               | PowerShell harness scripts that orchestrate the benchmark suite                                  |

---

## Test Protocol

Each test starts from identical initial conditions.

Before every measured run, the harness does the following:

1. Reverts toggled settings back to values from `reset_settings.sql`.
2. Reloads PostgreSQL config.
3. Drops and recreates the benchmark database.
4. Loads schema, seed data, indexes, procedures, and SQL functions.
5. Applies the test-specific cheat or optimization, if any.
6. Runs `VACUUM (ANALYZE)`.
7. Runs `CHECKPOINT`.
8. Executes the pgbench command.

```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
psql -d postgres -c "CREATE DATABASE pgbench_darkside;"

psql -d pgbench_darkside -f sql/schema_load.sql
psql -d pgbench_darkside -f sql/setup_objects.sql
psql -d pgbench_darkside -f sql/create_sqlfn.sql

psql -d pgbench_darkside -c "VACUUM (ANALYZE);"
psql -d pgbench_darkside -c "CHECKPOINT;"
```

Restart-only parameters were applied once through `ALTER SYSTEM` followed by a PostgreSQL service restart:

```powershell
Restart-Service postgresql-x64-18 -Force
```

The restart-only settings included:

```text
wal_buffers
io_workers
io_method
shared_buffers
max_connections
io_max_concurrency
```

One global warm-up was run before the full suite:

```powershell
pgbench -n -c 32 -j 8 -T 15 -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

---

## Common pgbench Shape

All measured commands use:

```text
-n -c 32 -j 8 -T 120
```

And all connect with:

```text
-h localhost -U postgres -d pgbench_darkside
```

---

## Benchmark Cases

<details>
<summary><strong>1. Bad code / missing index</strong></summary>

Pre-step:

```sql
DROP INDEX IF EXISTS bench_audit_created_at_audit_id_idx;
DROP INDEX IF EXISTS ix_bench_audit_created;
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>2. Indexed baseline</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>3. synchronous_commit = off</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET synchronous_commit = off;
SELECT pg_reload_conf();
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>4. full_page_writes = off</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET full_page_writes = off;
SELECT pg_reload_conf();
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>5. fsync = off</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET fsync = off;
SELECT pg_reload_conf();
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>6. Checkpoint tuning</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET max_wal_size = '64GB';
ALTER SYSTEM SET checkpoint_timeout = '30min';
SELECT pg_reload_conf();
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>7. All durability off</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET full_page_writes = off;
ALTER SYSTEM SET fsync = off;
SELECT pg_reload_conf();
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>8. Less work: drop FK / SELECT / audit</strong></summary>

Pre-step:

```sql
ALTER TABLE bench_accounts
DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/less_work.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>9. UNLOGGED ledger/audit</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/unlogged.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>10. Stored procedure: PL/pgSQL</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/procedure.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>11. Prepared protocol</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>12. Prepared + pipelined</strong></summary>

> Run during testing, but excluded from the final blog/PDF.

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish-pipeline.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>13. Batch x8</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/batch.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>14. Batch x32</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/batch32.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>15. Stored procedure + prepared protocol</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/procedure.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>16. All cheats + batch x32</strong></summary>

Pre-step:

```sql
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET full_page_writes = off;
ALTER SYSTEM SET fsync = off;
ALTER SYSTEM SET max_wal_size = '64GB';
ALTER SYSTEM SET checkpoint_timeout = '30min';
SELECT pg_reload_conf();

ALTER TABLE bench_accounts
DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>17. All cheats + mega-batch x1000</strong></summary>

> Run during testing, but excluded from the final blog/PDF.

Pre-step:

```sql
-- Same durability/checkpoint/FK-removal setup as case 16.
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/megabatch.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>18. Stored function: LANGUAGE sql</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/sqlfunction.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>19. SQL function + prepared protocol</strong></summary>

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/sqlfunction.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

<details>
<summary><strong>20. All cheats + batch x32 SQL function</strong></summary>

> Grand finale case.

Pre-step:

```sql
-- Same durability/checkpoint/FK-removal setup as case 16.
```

Command:

```powershell
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32_sqlfn.sql -h localhost -U postgres -d pgbench_darkside
```

</details>

---

## Result Interpretation

`reported OPS` means:

```text
TPS × operations per transaction
```

For normal tests:

```text
operations per transaction = 1
```

For batched tests:

```text
operations per transaction = 8, 32, or 1000
```

So:

| Test type         | Reported metric       |
| ----------------- | --------------------- |
| Non-batched tests | TPS                   |
| Batched tests     | Operations per second |

---

## Excluded From Blog/PDF

The following tests were executed and are present in `results_final.csv`, but were intentionally excluded from the completed blog/PDF:

| Case | Description                   |
| ---- | ----------------------------- |
| 12   | Prepared + pipelined          |
| 17   | All cheats + mega-batch x1000 |

---

## Reproduce the Full Suite

Run:

```powershell
runners/run_all.ps1
```

The full chain is:

```text
run_all.ps1
  └── run_final.ps1
        └── run_sqlfn.ps1
              └── run_sqlfn_finale.ps1
```

> Note: paths inside the scripts point to the original `...\dishonest_benchmark` folder.
> Adjust them before running on another machine.

---

## Warning

This benchmark intentionally includes unsafe and unrealistic configurations.

Settings like:

```text
fsync = off
full_page_writes = off
synchronous_commit = off
```

change PostgreSQL’s durability behavior. They can make numbers look better, but they do not preserve the same production safety contract.

That is the point of the benchmark.
