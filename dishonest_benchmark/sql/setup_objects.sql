-- ============================================================================
-- setup_objects.sql
-- Idempotent creation of the server-side objects the benchmark needs:
--   * bench_txn            -> blog "Cheat 5" (hide round trips in PL/pgSQL)
--   * bench_txn_megabatch  -> NEW test B (set-based server-side mega-batch)
--   * UNLOGGED ledger/audit tables (+ index) -> blog "Cheat 4"
-- Safe to run before every test; nothing here mutates account data.
-- ============================================================================

-- Cheat 5: one CALL replaces the SELECT/UPDATE/INSERT/INSERT/DELETE round trips.
CREATE OR REPLACE PROCEDURE bench_txn(_aid bigint, _delta int)
LANGUAGE plpgsql
AS $$
DECLARE
    _balance bigint;
BEGIN
    SELECT balance INTO _balance
    FROM bench_accounts
    WHERE account_id = _aid;

    UPDATE bench_accounts
    SET balance = balance + _delta
    WHERE account_id = _aid;

    INSERT INTO bench_ledger(account_id, branch_id, amount)
    SELECT account_id, branch_id, _delta
    FROM bench_accounts
    WHERE account_id = _aid;

    INSERT INTO bench_audit(account_id, action)
    VALUES (_aid, 'debit_credit');

    DELETE FROM bench_audit
    WHERE audit_id IN (
        SELECT audit_id
        FROM bench_audit
        WHERE created_at < now() - interval '10 minutes'
        ORDER BY created_at
        LIMIT 1
    );
END;
$$;

-- NEW test B: one CALL applies _n genuine random debit/credits set-based.
-- Real work (every op updates an account + writes a ledger + audit row), but
-- the whole thing commits as ONE transaction -> ops/sec headline is _n x TPS.
CREATE OR REPLACE PROCEDURE bench_txn_megabatch(_n int)
LANGUAGE plpgsql
AS $$
BEGIN
    WITH raw AS (
        SELECT (1 + floor(random() * 1000000))::bigint AS account_id,
               (floor(random() * 1001) - 500)::int      AS delta
        FROM generate_series(1, _n)
    ),
    picks AS (                       -- dedup so UPDATE ... FROM has unique targets
        SELECT account_id, sum(delta)::int AS delta
        FROM raw
        GROUP BY account_id
    ),
    upd AS (
        UPDATE bench_accounts a
        SET balance = balance + p.delta
        FROM picks p
        WHERE a.account_id = p.account_id
        RETURNING a.account_id, a.branch_id, p.delta
    ),
    led AS (
        INSERT INTO bench_ledger(account_id, branch_id, amount)
        SELECT account_id, branch_id, delta FROM upd
    )
    INSERT INTO bench_audit(account_id, action)
    SELECT account_id, 'debit_credit' FROM upd;
END;
$$;

-- Cheat 4: non-crash-safe storage for the high-churn ledger/audit tables.
CREATE UNLOGGED TABLE IF NOT EXISTS bench_ledger_unlogged
(
    ledger_id   bigserial PRIMARY KEY,
    account_id  bigint NOT NULL,
    branch_id   int NOT NULL,
    amount      int NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE UNLOGGED TABLE IF NOT EXISTS bench_audit_unlogged
(
    audit_id    bigserial PRIMARY KEY,
    account_id  bigint NOT NULL,
    action      text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS ix_bench_audit_unlogged_created
ON bench_audit_unlogged(created_at, audit_id);
