-- Audit Logs for tracking sensitive actions
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL, -- 'create', 'update', 'delete', 'export', etc.
    entity_type TEXT NOT NULL, -- 'sale', 'customer', 'setting', etc.
    entity_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Idempotent RLS Policy
DO $$
BEGIN
    DROP POLICY IF EXISTS company_isolation_policy ON audit_logs;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'audit_logs_isolation_policy' AND polrelid = 'audit_logs'::regclass) THEN
        CREATE POLICY audit_logs_isolation_policy ON audit_logs 
            FOR SELECT USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_audit_logs_company_created ON audit_logs(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
