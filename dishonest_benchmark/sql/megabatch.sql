-- NEW test B: the unit trick, industrialized.
-- One CALL performs 1000 genuine random debit/credits (update account + ledger
-- + audit) entirely server-side, committed as a SINGLE transaction. pgbench
-- counts 1 transaction; the marketing chart counts 1000 "operations".
CALL bench_txn_megabatch(1000);
