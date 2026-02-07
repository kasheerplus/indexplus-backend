-- Core Schema for Index Plus (Multi-tenant SaaS)

-- 1. Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Subscriptions Table
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('active', 'pending', 'expired')),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Users Table (Linked to auth.users)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'agent')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Customers Table (CRM)
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT,
    tags TEXT[] DEFAULT '{}',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Conversations Table
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    channel_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('whatsapp', 'facebook', 'instagram', 'tiktok')),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'pending', 'closed')),
    assigned_to UUID REFERENCES users(id),
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    unread_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Messages Table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL CHECK (sender_type IN ('customer', 'agent')),
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Sales Records Table
CREATE TABLE IF NOT EXISTS sales_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id),
    amount NUMERIC(10, 2) NOT NULL,
    items JSONB DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Payment Proofs Table
CREATE TABLE IF NOT EXISTS payment_proofs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    proof_image_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Quick Replies Table
CREATE TABLE IF NOT EXISTS quick_replies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    shortcut TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Keyword Triggers Table
CREATE TABLE IF NOT EXISTS keyword_triggers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    keyword TEXT NOT NULL,
    response TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS POLICIES (Data Isolation)

-- Enable RLS on all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_proofs ENABLE ROW LEVEL SECURITY;
ALTER TABLE quick_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyword_triggers ENABLE ROW LEVEL SECURITY;

-- Helper function to get company_id from JWT
CREATE OR REPLACE FUNCTION get_auth_company_id()
RETURNS UUID AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'company_id', ''),
    NULLIF(current_setting('request.jwt.claims', true)::json->'user_metadata'->>'company_id', '')
  )::UUID;
$$ LANGUAGE SQL STABLE;

-- Generic Policy for company isolation (Apply to most tables)
-- Example: Policy for Customers
CREATE POLICY company_isolation_policy ON customers
    FOR ALL
    USING (company_id = get_auth_company_id())
    WITH CHECK (company_id = get_auth_company_id());

-- Apply similar policies to other tables
CREATE POLICY company_isolation_policy ON companies USING (id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON subscriptions USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON users USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON conversations USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON sales_records USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON payment_proofs USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON quick_replies USING (company_id = get_auth_company_id());
CREATE POLICY company_isolation_policy ON keyword_triggers USING (company_id = get_auth_company_id());

-- Special Policy for Messages (Isolated via conversation_id which is isolated via company_id)
-- But for simplicity, we can also add company_id to messages if needed, or join. 
-- Let's keep it simple and add company_id to messages for high-performance RLS.

ALTER TABLE messages ADD COLUMN company_id UUID REFERENCES companies(id) ON DELETE CASCADE;
CREATE POLICY company_isolation_policy ON messages USING (company_id = get_auth_company_id());
