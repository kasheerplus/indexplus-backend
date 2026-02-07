-- Channels Table for Meta/WhatsApp integration storage

CREATE TABLE IF NOT EXISTS channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('whatsapp', 'facebook', 'instagram', 'tiktok', 'kasheer_plus')),
    token TEXT,
    verify_token TEXT,
    platform_id TEXT, -- ID from the external platform
    status TEXT NOT NULL DEFAULT 'disconnected' CHECK (status IN ('connected', 'disconnected', 'pending')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;

-- Add company isolation policy
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'channels_isolation_policy' 
        AND polrelid = 'channels'::regclass
    ) THEN
        CREATE POLICY channels_isolation_policy ON channels
            FOR ALL
            USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;
END
$$;
