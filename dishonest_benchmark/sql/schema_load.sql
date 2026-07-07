DROP TABLE IF EXISTS bench_audit;
DROP TABLE IF EXISTS bench_ledger;
DROP TABLE IF EXISTS bench_accounts;
DROP TABLE IF EXISTS bench_branches;


CREATE TABLE bench_branches
(
    branch_id   int PRIMARY KEY,
    balance     bigint NOT NULL DEFAULT 0
);

CREATE TABLE bench_accounts
(
    account_id  bigint PRIMARY KEY,
    branch_id   int NOT NULL REFERENCES bench_branches(branch_id),
    balance     bigint NOT NULL DEFAULT 0
) WITH (fillfactor = 100);

CREATE TABLE bench_ledger
(
    ledger_id   bigserial PRIMARY KEY,
    account_id  bigint NOT NULL,
    branch_id   int NOT NULL,
    amount      int NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE bench_audit
(
    audit_id    bigserial PRIMARY KEY,
    account_id  bigint NOT NULL,
    action      text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO bench_branches(branch_id)
SELECT g FROM generate_series(1, 100) AS g;

INSERT INTO bench_accounts(account_id, branch_id, balance)
SELECT g, 1 + (g % 100), 100000 FROM generate_series(1, 1000000) AS g;

INSERT INTO bench_audit(account_id, action, created_at)
SELECT 1 + (g % 1000000), 'seed', now() FROM generate_series(1, 200000) AS g;

CREATE INDEX ix_bench_accounts_branch            ON bench_accounts(branch_id);
CREATE INDEX bench_audit_created_at_audit_id_idx ON bench_audit(created_at, audit_id);

VACUUM ANALYZE;

CHECKPOINT;