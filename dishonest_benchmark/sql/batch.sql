\set aid1 random(1, 1000000)
\set aid2 random(1, 1000000)
\set aid3 random(1, 1000000)
\set aid4 random(1, 1000000)
\set aid5 random(1, 1000000)
\set aid6 random(1, 1000000)
\set aid7 random(1, 1000000)
\set aid8 random(1, 1000000)
\set delta random(-500, 500)

BEGIN;

UPDATE bench_accounts
SET balance = balance + :delta
WHERE account_id IN (:aid1, :aid2, :aid3, :aid4, :aid5, :aid6, :aid7, :aid8);

INSERT INTO bench_ledger(account_id, branch_id, amount)
SELECT account_id, branch_id, :delta
FROM bench_accounts
WHERE account_id IN (:aid1, :aid2, :aid3, :aid4, :aid5, :aid6, :aid7, :aid8);

INSERT INTO bench_audit(account_id, action)
VALUES
(:aid1, 'debit_credit'),
(:aid2, 'debit_credit'),
(:aid3, 'debit_credit'),
(:aid4, 'debit_credit'),
(:aid5, 'debit_credit'),
(:aid6, 'debit_credit'),
(:aid7, 'debit_credit'),
(:aid8, 'debit_credit');

COMMIT;
