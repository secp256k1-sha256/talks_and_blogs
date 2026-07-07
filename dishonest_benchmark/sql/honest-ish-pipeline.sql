\set aid random(1, 1000000)
\set delta random(-500, 500)

\startpipeline
BEGIN;
SELECT balance FROM bench_accounts WHERE account_id = :aid;
UPDATE bench_accounts SET balance = balance + :delta WHERE account_id = :aid;
INSERT INTO bench_ledger(account_id, branch_id, amount)
SELECT account_id, branch_id, :delta FROM bench_accounts WHERE account_id = :aid;
INSERT INTO bench_audit(account_id, action) VALUES (:aid, 'debit_credit');
DELETE FROM bench_audit WHERE audit_id IN (
    SELECT audit_id FROM bench_audit WHERE created_at < now() - interval '10 minutes' LIMIT 1);
COMMIT;
\endpipeline
