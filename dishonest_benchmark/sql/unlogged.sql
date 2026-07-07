\set aid random(1, 1000000)
\set delta random(-500, 500)

BEGIN;

UPDATE bench_accounts
SET balance = balance + :delta
WHERE account_id = :aid;

INSERT INTO bench_ledger_unlogged(account_id, branch_id, amount)
SELECT account_id, branch_id, :delta
FROM bench_accounts
WHERE account_id = :aid;

INSERT INTO bench_audit_unlogged(account_id, action)
VALUES (:aid, 'debit_credit');

COMMIT;
