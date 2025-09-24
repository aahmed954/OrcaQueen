-- Create replication user for streaming replication
CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'rep_secure_pass_2025';
GRANT CONNECT ON DATABASE litellm TO replicator;
GRANT USAGE ON SCHEMA public TO replicator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
ALTER USER replicator SET search_path = public;

-- Grant replication privileges
SELECT pg_catalog.set_config('log_statement', 'all', false);  -- Log for diagnostics