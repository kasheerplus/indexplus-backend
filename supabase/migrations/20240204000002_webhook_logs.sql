-- Webhook Logs table for Idempotency and Reliability

CREATE TABLE IF NOT EXISTS webhook_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL, -- 'meta', 'stripe', etc.
    external_id TEXT,       -- ID from the external platform for idempotency
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'failed')),
    error_message TEXT,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure we don't process the same external event multiple times for the same platform
    UNIQUE(platform, external_id)
);

-- Update Messages table to support delivery lifecycle
ALTER TABLE messages 
    ADD COLUMN IF NOT EXISTS delivery_status TEXT NOT NULL DEFAULT 'sent' CHECK (delivery_status IN ('sent', 'delivered', 'read', 'failed')),
    ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

-- Enable RLS for webhook_logs
ALTER TABLE webhook_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'webhook_logs_isolation_policy' 
        AND polrelid = 'webhook_logs'::regclass
    ) THEN
        CREATE POLICY webhook_logs_isolation_policy ON webhook_logs
            FOR ALL
            USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;
END
$$;
