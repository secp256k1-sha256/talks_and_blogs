\set aid1 random(1, 1000000)
\set aid2 random(1, 1000000)
\set aid3 random(1, 1000000)
\set aid4 random(1, 1000000)
\set aid5 random(1, 1000000)
\set aid6 random(1, 1000000)
\set aid7 random(1, 1000000)
\set aid8 random(1, 1000000)
\set aid9 random(1, 1000000)
\set aid10 random(1, 1000000)
\set aid11 random(1, 1000000)
\set aid12 random(1, 1000000)
\set aid13 random(1, 1000000)
\set aid14 random(1, 1000000)
\set aid15 random(1, 1000000)
\set aid16 random(1, 1000000)
\set aid17 random(1, 1000000)
\set aid18 random(1, 1000000)
\set aid19 random(1, 1000000)
\set aid20 random(1, 1000000)
\set aid21 random(1, 1000000)
\set aid22 random(1, 1000000)
\set aid23 random(1, 1000000)
\set aid24 random(1, 1000000)
\set aid25 random(1, 1000000)
\set aid26 random(1, 1000000)
\set aid27 random(1, 1000000)
\set aid28 random(1, 1000000)
\set aid29 random(1, 1000000)
\set aid30 random(1, 1000000)
\set aid31 random(1, 1000000)
\set aid32 random(1, 1000000)
\set delta random(-500, 500)

BEGIN;

UPDATE bench_accounts
SET balance = balance + :delta
WHERE account_id IN (:aid1,:aid2,:aid3,:aid4,:aid5,:aid6,:aid7,:aid8,
                     :aid9,:aid10,:aid11,:aid12,:aid13,:aid14,:aid15,:aid16,
                     :aid17,:aid18,:aid19,:aid20,:aid21,:aid22,:aid23,:aid24,
                     :aid25,:aid26,:aid27,:aid28,:aid29,:aid30,:aid31,:aid32);

INSERT INTO bench_ledger(account_id, branch_id, amount)
SELECT account_id, branch_id, :delta
FROM bench_accounts
WHERE account_id IN (:aid1,:aid2,:aid3,:aid4,:aid5,:aid6,:aid7,:aid8,
                     :aid9,:aid10,:aid11,:aid12,:aid13,:aid14,:aid15,:aid16,
                     :aid17,:aid18,:aid19,:aid20,:aid21,:aid22,:aid23,:aid24,
                     :aid25,:aid26,:aid27,:aid28,:aid29,:aid30,:aid31,:aid32);

INSERT INTO bench_audit(account_id, action)
SELECT account_id, 'debit_credit'
FROM bench_accounts
WHERE account_id IN (:aid1,:aid2,:aid3,:aid4,:aid5,:aid6,:aid7,:aid8,
                     :aid9,:aid10,:aid11,:aid12,:aid13,:aid14,:aid15,:aid16,
                     :aid17,:aid18,:aid19,:aid20,:aid21,:aid22,:aid23,:aid24,
                     :aid25,:aid26,:aid27,:aid28,:aid29,:aid30,:aid31,:aid32);

COMMIT;
