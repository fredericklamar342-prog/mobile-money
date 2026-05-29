-- Parent partitioned table: partitioned by month on created_at
CREATE TABLE audit_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        admin_id UUID NOT NULL REFERENCES users(id),
        action VARCHAR(255) NOT NULL,
        resource VARCHAR(255) NOT NULL,
        resource_id VARCHAR(255),
        diff JSONB NOT NULL,
        ip_address VARCHAR(45),
        user_agent TEXT,
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

-- Create indexes on the partitioned parent (propagates to partitions)
CREATE INDEX idx_audit_logs_admin_id ON audit_logs(admin_id);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource, resource_id);

-- Helper function: create monthly partition if it does not exist
CREATE OR REPLACE FUNCTION audit_logs_create_monthly_partition()
RETURNS TRIGGER AS $$
DECLARE
    partition_name TEXT;
    start_month TIMESTAMP WITH TIME ZONE;
    end_month TIMESTAMP WITH TIME ZONE;
    sql TEXT;
BEGIN
    start_month := date_trunc('month', NEW.created_at);
    end_month := (start_month + INTERVAL '1 month');
    partition_name := format('audit_logs_%s', to_char(start_month, 'YYYYMM'));

    sql := format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs FOR VALUES FROM (''%s'') TO (''%s'')',
        partition_name,
        start_month,
        end_month
    );

    EXECUTE sql;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: ensures appropriate monthly partition exists before insert
DROP TRIGGER IF EXISTS trg_audit_logs_create_partition ON audit_logs;
CREATE TRIGGER trg_audit_logs_create_partition
BEFORE INSERT ON audit_logs
FOR EACH ROW EXECUTE FUNCTION audit_logs_create_monthly_partition();