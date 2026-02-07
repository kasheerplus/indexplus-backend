-- Interactive Conversational Flows (Menu Builder) - Updated with Advanced Triggers

CREATE TABLE IF NOT EXISTS interactive_flows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    trigger_type TEXT NOT NULL DEFAULT 'keyword' CHECK (trigger_type IN ('keyword', 'post_link', 'main_menu', 'all')),
    trigger_keyword TEXT, -- Optional keyword to trigger the flow
    trigger_post_link TEXT, -- Optional post link to trigger the flow
    is_main_menu BOOLEAN DEFAULT FALSE,
    flow_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}', -- ReactFlow or custom structure
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Allow unique combinations of trigger and content for a company
    CONSTRAINT unique_trigger_keyword UNIQUE(company_id, trigger_keyword),
    CONSTRAINT unique_trigger_post_link UNIQUE(company_id, trigger_post_link),
    -- Ensure only one active main menu per company
    CONSTRAINT unique_active_main_menu EXCLUDE (company_id WITH =) WHERE (is_main_menu = TRUE AND is_active = TRUE)
);

-- Index for faster lookup by company and activity status
CREATE INDEX IF NOT EXISTS idx_interactive_flows_company_active ON interactive_flows(company_id, is_active);

-- Enable RLS
ALTER TABLE interactive_flows ENABLE ROW LEVEL SECURITY;

-- Add company isolation policy
DO $$
BEGIN
    DROP POLICY IF EXISTS interactive_flows_isolation_policy ON interactive_flows;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'interactive_flows_isolation_policy' 
        AND polrelid = 'interactive_flows'::regclass
    ) THEN
        CREATE POLICY interactive_flows_isolation_policy ON interactive_flows
            FOR ALL
            USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;
END
$$;
