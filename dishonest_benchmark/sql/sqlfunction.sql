\set aid random(1, 1000000)
\set delta random(-500, 500)

SELECT bench_txn_sqlfn(:aid, :delta);
