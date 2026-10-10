# How to Run Every Test by Hand

Plain copy-paste commands for every benchmark case. No runner scripts needed: just `psql` and `pgbench`.

All commands are run **from the repo root** (the folder that contains `sql/`).

## Ready-made scripts: one per test, 2 minutes each

Each test below also exists as a small script containing exactly these commands. It resets to the baseline, applies the cheat, runs pgbench for 2 minutes and then restores the honest settings:

```bash
bash simple_tests/linux/00_warmup.sh              # once, before the first test
bash simple_tests/linux/07_all_durability_off.sh  # any single test
```

```powershell
pwsh simple_tests\windows\00_warmup.ps1
pwsh simple_tests\windows\07_all_durability_off.ps1
```

The script numbers match the test numbers below (`01_` … `20_`). Run them one at a time, never in parallel: every script drops and recreates `pgbench_darkside`.

---

## 0. One-time setup

### Password

Every command below connects with `-h localhost -U postgres`. Set the password once per shell:

```bash
export PGPASSWORD=********          # Linux / macOS / Git Bash
```

```powershell
$env:PGPASSWORD = '********'        # Windows PowerShell
```

### Baseline server settings

Apply the honest baseline once, then **restart** PostgreSQL, because `shared_buffers`, `max_connections`, `wal_buffers`, `io_method`, `io_workers` and `io_max_concurrency` only take effect after a restart:

```bash
psql -h localhost -U postgres -d postgres -f reset_settings.sql
```

```bash
sudo systemctl restart postgresql@18-main          # Ubuntu / Debian
sudo systemctl restart postgresql-18               # RHEL / Alma / Rocky
```

```powershell
Restart-Service postgresql-x64-18 -Force           # Windows (elevated)
```

### Warm-up (once, before the first test)

```bash
pgbench -n -c 32 -j 8 -T 15 -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

> The warm-up needs the database to exist, so run the reset block in step 1 once before it.

---

## 1. Reset block: run before EVERY test

Every test starts from the same state: baseline settings, a brand-new database, fresh data, fresh statistics and a fresh checkpoint.

```bash
psql -h localhost -U postgres -d postgres -f reset_settings.sql
psql -h localhost -U postgres -d postgres -c "DROP DATABASE IF EXISTS pgbench_darkside WITH (FORCE);"
psql -h localhost -U postgres -d postgres -c "CREATE DATABASE pgbench_darkside;"
psql -h localhost -U postgres -d pgbench_darkside -f sql/schema_load.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/setup_objects.sql
psql -h localhost -U postgres -d pgbench_darkside -f sql/create_sqlfn.sql
psql -h localhost -U postgres -d pgbench_darkside -c "VACUUM (ANALYZE);"
```

Then run the test's **pre-step** (if it has one), then:

```bash
psql -h localhost -U postgres -d pgbench_darkside -c "CHECKPOINT;"
```

and finally the test's **pgbench command**.

> `ALTER SYSTEM` cannot run inside a transaction, so the pre-steps use one `-c` per statement.
> Running `reset_settings.sql` at the start of the next test undoes any setting a pre-step changed.

---

## 2. The tests

All measured runs use `-n -c 32 -j 8 -T 120`: no vacuum, 32 clients, 8 threads, 120 seconds.

### The honest part

**1. Bad code / missing index**

```bash
psql -h localhost -U postgres -d pgbench_darkside -c "DROP INDEX IF EXISTS bench_audit_created_at_audit_id_idx;"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**2. Indexed baseline**

```bash
psql -h localhost -U postgres -d pgbench_darkside -c "CREATE INDEX IF NOT EXISTS bench_audit_created_at_audit_id_idx ON bench_audit(created_at, audit_id);"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

### Durability / WAL cheats

**3. synchronous_commit = off**

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET synchronous_commit = off;" -c "SELECT pg_reload_conf();"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**4. full_page_writes = off**

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET full_page_writes = off;" -c "SELECT pg_reload_conf();"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**5. fsync = off**

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET fsync = off;" -c "SELECT pg_reload_conf();"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**6. Checkpoint tuning**

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET max_wal_size = '64GB';" -c "ALTER SYSTEM SET checkpoint_timeout = '30min';" -c "SELECT pg_reload_conf();"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**7. All durability off**

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET synchronous_commit = off;" -c "ALTER SYSTEM SET full_page_writes = off;" -c "ALTER SYSTEM SET fsync = off;" -c "SELECT pg_reload_conf();"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

### Schema / storage / workload cheats

**8. Less work (drop FK, SELECT and audit)**

```bash
psql -h localhost -U postgres -d pgbench_darkside -c "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;"
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/less_work.sql -h localhost -U postgres -d pgbench_darkside
```

**9. UNLOGGED ledger/audit**

```bash
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/unlogged.sql -h localhost -U postgres -d pgbench_darkside
```

### Execution-shape cheats

**10. Stored procedure (PL/pgSQL)**

```bash
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/procedure.sql -h localhost -U postgres -d pgbench_darkside
```

**11. Prepared protocol**

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish.sql -h localhost -U postgres -d pgbench_darkside
```

**12. Prepared + pipelined** *(run, but excluded from the blog/PDF)*

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/honest-ish-pipeline.sql -h localhost -U postgres -d pgbench_darkside
```

### Unit-of-measurement cheats

For these, **ops/sec = TPS × ops per transaction**.

**13. Batching x8** (8 ops per transaction)

```bash
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/batch.sql -h localhost -U postgres -d pgbench_darkside
```

**14. Batching x32** (32 ops per transaction)

```bash
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/batch32.sql -h localhost -U postgres -d pgbench_darkside
```

### Combination cheat

**15. Stored proc + prepared**

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/procedure.sql -h localhost -U postgres -d pgbench_darkside
```

### Finales: every cheat at once

Tests 16, 17 and 20 share the same **"all cheats" pre-step**: every durability setting off, checkpoint tuning, and the FK dropped.

```bash
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET synchronous_commit = off;" -c "ALTER SYSTEM SET full_page_writes = off;" -c "ALTER SYSTEM SET fsync = off;" -c "ALTER SYSTEM SET max_wal_size = '64GB';" -c "ALTER SYSTEM SET checkpoint_timeout = '30min';" -c "SELECT pg_reload_conf();"
psql -h localhost -U postgres -d pgbench_darkside -c "ALTER TABLE bench_accounts DROP CONSTRAINT IF EXISTS bench_accounts_branch_id_fkey;"
```

**16. All cheats + batch x32** (32 ops per transaction)

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32.sql -h localhost -U postgres -d pgbench_darkside
```

**17. All cheats + mega-batch x1000** (1000 ops per transaction; run, but excluded from the blog/PDF)

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/megabatch.sql -h localhost -U postgres -d pgbench_darkside
```

### SQL function vs PL/pgSQL procedure

**18. Stored function (`LANGUAGE sql`)**: compare with test 10

```bash
pgbench -n -c 32 -j 8 -T 120 -M simple -f sql/sqlfunction.sql -h localhost -U postgres -d pgbench_darkside
```

**19. SQL function + prepared**: compare with test 15

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/sqlfunction.sql -h localhost -U postgres -d pgbench_darkside
```

**20. All cheats + batch x32 SQL function: the grand finale** (32 ops per transaction; uses the "all cheats" pre-step above)

```bash
pgbench -n -c 32 -j 8 -T 120 -M prepared -f sql/batch32_sqlfn.sql -h localhost -U postgres -d pgbench_darkside
```

---

## 3. When you are done

Put the honest settings back:

```bash
psql -h localhost -U postgres -d postgres -f reset_settings.sql
```

---

## 4. Read pgbench's output

The two lines that matter:

```text
latency average = 5.310 ms
tps = 6026.303880 (without initial connection time)
```

- **Non-batched tests:** report `tps`.
- **Batched tests:** report `tps × ops per transaction` (8, 32 or 1000). That multiplication *is* the cheat.

---

## 5. Things that change the numbers

**Windows: the default sync method**
On Windows, PostgreSQL's default `wal_sync_method = open_datasync` lets the SSD acknowledge a commit while the data is still in its volatile RAM cache. On a consumer NVMe drive without power-loss protection, that costs about 38 µs per commit, versus about 2 ms for a real flush. As a result, the Windows "honest" baseline already skips most of the commit-flush cost, and the durability-off cheats look small there.

For more impactful representation of durability cheats, add this to the pre-step:

```powershell
psql -h localhost -U postgres -d postgres -c "ALTER SYSTEM SET wal_sync_method = fdatasync;" -c "SELECT pg_reload_conf();"
```


**Linux kernel settings.**
With `fsync = off`, the kernel decides when data reaches the disk. On a slow disk, default dirty-page limits cause throughput to stop completely for several seconds at a time. Production-style settings:

```bash
sudo tee /etc/sysctl.d/99-postgresql.conf >/dev/null <<'EOF'
vm.overcommit_memory = 2
vm.overcommit_ratio = 100
vm.swappiness = 1
kernel.numa_balancing = 0
vm.dirty_background_ratio = 5
vm.dirty_ratio = 90
EOF
sudo sysctl -p /etc/sysctl.d/99-postgresql.conf
```

> With `vm.overcommit_memory = 2`, a machine with **no swap** (typical for cloud VMs) may refuse to start PostgreSQL with `max_connections = 1000` and `shared_buffers = 1GB`. Add swap or lower those two settings.

**WSL2.**
WSL2 stores data on a virtual disk. Each real flush costs about 3 ms, and random 8 kB writes are slow, so the durability cheats look much bigger on WSL2 than on native hardware. Compare WSL2 numbers only with other WSL2 numbers.
