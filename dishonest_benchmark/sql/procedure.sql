\set aid random(1, 1000000)
\set delta random(-500, 500)

CALL bench_txn(:aid, :delta);
