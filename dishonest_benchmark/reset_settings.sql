-- reset_settings.sql  --  the honest baseline server configuration.
ALTER SYSTEM SET jit = off;
ALTER SYSTEM SET shared_buffers = '1GB';                 -- (restart)
ALTER SYSTEM SET max_connections = 1000;                 -- (restart)
ALTER SYSTEM SET max_parallel_workers_per_gather = 0;
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '64MB';                   -- (restart)
ALTER SYSTEM SET default_statistics_target = 300;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET io_method = 'worker';                   -- (restart)
ALTER SYSTEM SET io_workers = 10;                        -- (restart)
ALTER SYSTEM SET effective_io_concurrency = 256;
ALTER SYSTEM SET io_max_concurrency = 128;               -- (restart)
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET full_page_writes = on;
ALTER SYSTEM SET fsync = on;
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET checkpoint_timeout = '10min';
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET wal_compression = 'LZ4';

SELECT pg_reload_conf();
