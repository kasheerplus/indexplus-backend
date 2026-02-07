-- Automation Rules for Keyword-based responses

CREATE TABLE IF NOT EXISTS automation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('exact', 'contains', 'starts_with')),
    keywords TEXT[] NOT NULL DEFAULT '{}',
    response_content TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for faster lookup by company and activity status
CREATE INDEX IF NOT EXISTS idx_automation_rules_company_active ON automation_rules(company_id, is_active);

-- Enable RLS
ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;

-- Add company isolation policy
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'automation_rules_isolation_policy' 
        AND polrelid = 'automation_rules'::regclass
    ) THEN
        CREATE POLICY automation_rules_isolation_policy ON automation_rules
            FOR ALL
            USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;
END
$$;
