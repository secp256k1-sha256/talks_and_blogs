-- Fair counterpart to the PL/pgSQL procedure bench_txn, but written as a
-- LANGUAGE sql function. Same five statements (read + update + 2 inserts +
-- trim) so the only variable is procedure(plpgsql) vs function(sql).
-- Non-final SELECTs in a SQL function are executed and their results discarded.
CREATE OR REPLACE FUNCTION bench_txn_sqlfn(_aid bigint, _delta int)
RETURNS void
LANGUAGE sql
AS $$
    SELECT balance
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
$$;

-- Batched (x32) counterpart, still a plain LANGUAGE sql function (NO CTEs):
-- takes the 32 account ids as an array so one SELECT does the whole batch
-- server-side. Used by the "all cheats + batch x32 (SQL fn)" finale.
CREATE OR REPLACE FUNCTION bench_txn_batch_sqlfn(_aids bigint[], _delta int)
RETURNS void
LANGUAGE sql
AS $$
    UPDATE bench_accounts
    SET balance = balance + _delta
    WHERE account_id = ANY(_aids);

    INSERT INTO bench_ledger(account_id, branch_id, amount)
    SELECT account_id, branch_id, _delta
    FROM bench_accounts
    WHERE account_id = ANY(_aids);

    INSERT INTO bench_audit(account_id, action)
    SELECT account_id, 'debit_credit'
    FROM bench_accounts
    WHERE account_id = ANY(_aids);
$$;
