-- Synced Inventory Schema from Kasheer Plus

CREATE TABLE IF NOT EXISTS synced_inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    remote_id TEXT NOT NULL, -- ID used in Kasheer Plus
    name TEXT NOT NULL,
    sku TEXT,
    category TEXT,
    price DECIMAL(10, 2) NOT NULL DEFAULT 0,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    unit TEXT DEFAULT 'piece',
    image_url TEXT,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, remote_id)
);

CREATE TABLE IF NOT EXISTS sync_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    success BOOLEAN NOT NULL,
    payload_size INTEGER,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup by remote_id
CREATE INDEX IF NOT EXISTS idx_inventory_remote_id ON synced_inventory(company_id, remote_id);

-- Enable RLS
ALTER TABLE synced_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;

-- Company Isolation Policy
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'inventory_isolation_policy' 
        AND polrelid = 'synced_inventory'::regclass
    ) THEN
        CREATE POLICY inventory_isolation_policy ON synced_inventory
            FOR ALL USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policy 
        WHERE polname = 'sync_logs_isolation_policy' 
        AND polrelid = 'sync_logs'::regclass
    ) THEN
        CREATE POLICY sync_logs_isolation_policy ON sync_logs
            FOR ALL USING (company_id = get_auth_company_id())
            WITH CHECK (company_id = get_auth_company_id());
    END IF;
END
$$;
