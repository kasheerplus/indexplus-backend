-- Tenant Quotas and Usage Tracking

CREATE TABLE IF NOT EXISTS tenant_quotas (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    monthly_message_limit INTEGER DEFAULT 1000,
    monthly_customer_limit INTEGER DEFAULT 500,
    storage_limit_mb INTEGER DEFAULT 100,
    current_message_count INTEGER DEFAULT 0,
    current_customer_count INTEGER DEFAULT 0,
    last_reset_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Function to check and increment message quota
CREATE OR REPLACE FUNCTION check_message_quota(company_id_param UUID)
RETURNS BOOLEAN AS $$
DECLARE
    quota_record RECORD;
BEGIN
    SELECT * INTO quota_record FROM tenant_quotas WHERE company_id = company_id_param;
    
    -- If no quota record, create one (Basic plan defaults)
    IF NOT FOUND THEN
        INSERT INTO tenant_quotas (company_id) VALUES (company_id_param) RETURNING * INTO quota_record;
    END IF;

    -- Check if reset is needed (monthly)
    IF quota_record.last_reset_at < (NOW() - INTERVAL '30 days') THEN
        UPDATE tenant_quotas 
        SET current_message_count = 1, last_reset_at = NOW()
        WHERE company_id = company_id_param;
        RETURN TRUE;
    END IF;

    -- Check if over limit
    IF quota_record.current_message_count >= quota_record.monthly_message_limit THEN
        RETURN FALSE;
    END IF;

    -- Increment count
    UPDATE tenant_quotas 
    SET current_message_count = current_message_count + 1, updated_at = NOW()
    WHERE company_id = company_id_param;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable RLS
ALTER TABLE tenant_quotas ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'quotas_isolation_policy' 
        AND polrelid = 'tenant_quotas'::regclass
    ) THEN
        CREATE POLICY quotas_isolation_policy ON tenant_quotas
            FOR SELECT
            USING (company_id = get_auth_company_id());
    END IF;
END
$$;
