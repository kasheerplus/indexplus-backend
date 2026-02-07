-- ========================================================
-- INDEX PLUS - FULL DATABASE SCHEMA
-- Consolidated Migration File
-- Generated on: 2026-02-04
-- ========================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ========================================================
-- 1. CORE SCHEMA (Base Tables)
-- ========================================================

-- Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscriptions Table
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('active', 'pending', 'expired')),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Users Table (Linked to auth.users)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'agent', 'supervisor')), -- Added supervisor role
    permissions JSONB DEFAULT '{}', -- Granular permissions (e.g. {"can_delete_sales": true})
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Customers Table (CRM)
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

-- Conversations Table
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

-- Messages Table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL CHECK (sender_type IN ('customer', 'agent')),
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    delivery_status TEXT NOT NULL DEFAULT 'sent' CHECK (delivery_status IN ('sent', 'delivered', 'read', 'failed')),
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Search Optimization Indexes (Arabic FTS)
CREATE INDEX IF NOT EXISTS idx_messages_content_fts ON messages USING GIN (to_tsvector('simple', content));
CREATE INDEX IF NOT EXISTS idx_customers_name_fts ON customers USING GIN (to_tsvector('simple', name));

-- Sales Records Table
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

-- Payment Proofs Table
CREATE TABLE IF NOT EXISTS payment_proofs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    proof_image_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Quick Replies Table
CREATE TABLE IF NOT EXISTS quick_replies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    shortcut TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Channels Table
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

-- ========================================================
-- 2. SECURITY & RLS POLICIES (Consolidated & Standardized)
-- ========================================================

-- Helper function to get company_id from JWT
CREATE OR REPLACE FUNCTION get_auth_company_id()
RETURNS UUID AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'company_id', ''),
    NULLIF(current_setting('request.jwt.claims', true)::json->'user_metadata'->>'company_id', '')
  )::UUID;
$$ LANGUAGE SQL STABLE;

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
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;

-- Idempotent RLS Policies with UNIQUE NAMES and CLEANUP
DO $$
BEGIN
    -- 1. Companies
    DROP POLICY IF EXISTS company_isolation_policy ON companies;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'companies_isolation_policy' AND polrelid = 'companies'::regclass) THEN
        CREATE POLICY companies_isolation_policy ON companies USING (id = get_auth_company_id());
    END IF;

    -- 2. Subscriptions
    DROP POLICY IF EXISTS company_isolation_policy ON subscriptions;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'subscriptions_isolation_policy' AND polrelid = 'subscriptions'::regclass) THEN
        CREATE POLICY subscriptions_isolation_policy ON subscriptions USING (company_id = get_auth_company_id());
    END IF;

    -- 3. Users
    DROP POLICY IF EXISTS users_isolation_policy ON users;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'users_isolation_policy' AND polrelid = 'users'::regclass) THEN
        CREATE POLICY users_isolation_policy ON users USING (company_id = get_auth_company_id() OR id = auth.uid());
    END IF;

    -- 4. Customers
    DROP POLICY IF EXISTS company_isolation_policy ON customers;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'customers_isolation_policy' AND polrelid = 'customers'::regclass) THEN
        CREATE POLICY customers_isolation_policy ON customers FOR ALL USING (company_id = get_auth_company_id());
    END IF;

    -- 5. Conversations
    DROP POLICY IF EXISTS company_isolation_policy ON conversations;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'conversations_isolation_policy' AND polrelid = 'conversations'::regclass) THEN
        CREATE POLICY conversations_isolation_policy ON conversations USING (company_id = get_auth_company_id());
    END IF;

    -- 6. Messages
    DROP POLICY IF EXISTS company_isolation_policy ON messages;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'messages_isolation_policy' AND polrelid = 'messages'::regclass) THEN
        CREATE POLICY messages_isolation_policy ON messages USING (company_id = get_auth_company_id());
    END IF;

    -- 7. Sales Records
    DROP POLICY IF EXISTS company_isolation_policy ON sales_records;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'sales_records_isolation_policy' AND polrelid = 'sales_records'::regclass) THEN
        CREATE POLICY sales_records_isolation_policy ON sales_records USING (company_id = get_auth_company_id());
    END IF;

    -- 8. Payment Proofs
    DROP POLICY IF EXISTS company_isolation_policy ON payment_proofs;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'payment_proofs_isolation_policy' AND polrelid = 'payment_proofs'::regclass) THEN
        CREATE POLICY payment_proofs_isolation_policy ON payment_proofs USING (company_id = get_auth_company_id());
    END IF;

    -- 9. Quick Replies
    DROP POLICY IF EXISTS company_isolation_policy ON quick_replies;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'quick_replies_isolation_policy' AND polrelid = 'quick_replies'::regclass) THEN
        CREATE POLICY quick_replies_isolation_policy ON quick_replies USING (company_id = get_auth_company_id());
    END IF;

    -- 10. Channels
    DROP POLICY IF EXISTS company_isolation_policy ON channels; -- Cleanup legacy
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'channels_isolation_policy' AND polrelid = 'channels'::regclass) THEN
        CREATE POLICY channels_isolation_policy ON channels FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- ========================================================
-- 3. AUTH TRIGGERS
-- ========================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  company_name_from_meta TEXT;
  full_name_from_meta TEXT;
  role_from_meta TEXT;
BEGIN
  -- 1. Check if user already has a company_id (set by Invite/Admin Flow)
  new_company_id := (new.raw_user_meta_data->>'company_id')::UUID;
  full_name_from_meta := COALESCE(new.raw_user_meta_data->>'full_name', 'مستخدم جديد');
  role_from_meta := COALESCE(new.raw_user_meta_data->>'role', 'owner');

  -- 2. If no company_id, create a new company (Signup Flow)
  IF new_company_id IS NULL THEN
    company_name_from_meta := COALESCE(new.raw_user_meta_data->>'company_name', 'شركتي الجديدة');
    
    INSERT INTO public.companies (name, slug)
    VALUES (
      company_name_from_meta, 
      LOWER(REPLACE(REPLACE(company_name_from_meta, ' ', '-'), '.', '')) || '-' || (floor(random() * 90000) + 10000)::text
    )
    RETURNING id INTO new_company_id;

    -- Create an initial Subscription record for new companies
    INSERT INTO public.subscriptions (company_id, plan_id, status)
    VALUES (new_company_id, 'pro', 'pending');
    
    role_from_meta := 'owner'; -- Force owner for signup flow
  END IF;

  -- 3. Create the User record in public.users
  INSERT INTO public.users (id, company_id, full_name, role, status)
  VALUES (new.id, new_company_id, full_name_from_meta, role_from_meta, 'active')
  ON CONFLICT (id) DO UPDATE 
  SET company_id = EXCLUDED.company_id, 
      full_name = EXCLUDED.full_name, 
      role = EXCLUDED.role;

  -- 4. Sync metadata back to auth.users (Ensures JWT is always up to date)
  UPDATE auth.users 
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta),
      raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta, 'permissions', 
        CASE WHEN role_from_meta = 'owner' THEN '{"all": true}'::jsonb ELSE '{}'::jsonb END
      )
  WHERE id = new.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ========================================================
-- 4. ANALYTICS FUNCTIONS
-- ========================================================

CREATE OR REPLACE FUNCTION get_avg_response_time(company_id_param UUID)
RETURNS NUMERIC AS $$
DECLARE
    avg_minutes NUMERIC;
BEGIN
    WITH message_pairs AS (
        SELECT 
            m1.conversation_id,
            m1.created_at as customer_time,
            MIN(m2.created_at) as agent_time
        FROM messages m1
        JOIN messages m2 ON m1.conversation_id = m2.conversation_id
        JOIN conversations c ON m1.conversation_id = c.id
        WHERE c.company_id = company_id_param
        AND m1.sender_type = 'customer'
        AND m2.sender_type = 'agent'
        AND m2.created_at > m1.created_at
        GROUP BY m1.conversation_id, m1.created_at
    )
    SELECT AVG(EXTRACT(EPOCH FROM (agent_time - customer_time)) / 60) INTO avg_minutes
    FROM message_pairs;

    RETURN ROUND(COALESCE(avg_minutes, 0), 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_peak_order_hour(company_id_param UUID)
RETURNS TEXT AS $$
DECLARE
    peak_hour INTEGER;
BEGIN
    SELECT EXTRACT(HOUR FROM created_at) INTO peak_hour
    FROM sales_records
    WHERE company_id = company_id_param
    GROUP BY EXTRACT(HOUR FROM created_at)
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    RETURN LPAD(COALESCE(peak_hour, 12)::TEXT, 2, '0') || ':00';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_business_stats(company_id_param UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_revenue', (SELECT COALESCE(SUM(amount), 0) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'total_sales', (SELECT COUNT(*) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'total_customers', (SELECT COUNT(DISTINCT customer_id) FROM sales_records WHERE company_id = company_id_param AND status = 'completed'),
        'avg_response_time', get_avg_response_time(company_id_param),
        'peak_order_hour', get_peak_order_hour(company_id_param),
        'conversion_rate', CASE 
            WHEN (SELECT COUNT(*) FROM conversations WHERE company_id = company_id_param) = 0 THEN 0
            ELSE (SELECT COUNT(DISTINCT conversation_id) FROM sales_records WHERE company_id = company_id_param)::NUMERIC / (SELECT COUNT(*) FROM conversations WHERE company_id = company_id_param) * 100
        END
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================================
-- 5. WEBHOOK LOGS & RELIABILITY
-- ========================================================

CREATE TABLE IF NOT EXISTS webhook_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    external_id TEXT,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'failed')),
    error_message TEXT,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(platform, external_id)
);

ALTER TABLE webhook_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS company_isolation_policy ON webhook_logs;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'webhook_logs_isolation_policy' AND polrelid = 'webhook_logs'::regclass) THEN
        CREATE POLICY webhook_logs_isolation_policy ON webhook_logs FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION get_failed_webhooks()
RETURNS SETOF webhook_logs AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM webhook_logs
    WHERE status = 'failed'
    AND created_at > (NOW() - INTERVAL '24 hours')
    ORDER BY created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION mark_webhook_for_retry(webhook_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE webhook_logs
    SET status = 'pending', error_message = NULL
    WHERE id = webhook_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================================
-- 6. CRM & CUSTOMER MERGING
-- ========================================================

CREATE OR REPLACE FUNCTION get_duplicate_customers(target_customer_id UUID)
RETURNS TABLE (id UUID, name TEXT, phone TEXT, email TEXT, match_reason TEXT) AS $$
DECLARE
    target_phone TEXT;
    target_email TEXT;
    target_company_id UUID;
BEGIN
    SELECT phone, email, company_id INTO target_phone, target_email, target_company_id
    FROM customers WHERE customers.id = target_customer_id;

    RETURN QUERY
    SELECT c.id, c.name, c.phone, c.email,
           CASE WHEN c.phone = target_phone THEN 'Phone Match' WHEN c.email = target_email THEN 'Email Match' ELSE 'Fuzzy Name Match' END
    FROM customers c
    WHERE c.id != target_customer_id AND c.company_id = target_company_id
    AND ((c.phone IS NOT NULL AND c.phone = target_phone) OR (c.email IS NOT NULL AND c.email = target_email));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION merge_customers(primary_id UUID, duplicate_id UUID)
RETURNS VOID AS $$
BEGIN
    IF (SELECT company_id FROM customers WHERE id = primary_id) != (SELECT company_id FROM customers WHERE id = duplicate_id) THEN
        RAISE EXCEPTION 'Cannot merge customers from different companies';
    END IF;
    UPDATE conversations SET customer_id = primary_id WHERE customer_id = duplicate_id;
    UPDATE sales_records SET customer_id = primary_id WHERE customer_id = duplicate_id;
    DELETE FROM customers WHERE id = duplicate_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================================
-- 7. TENANT QUOTAS
-- ========================================================

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

ALTER TABLE tenant_quotas ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS company_isolation_policy ON tenant_quotas;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'quotas_isolation_policy' AND polrelid = 'tenant_quotas'::regclass) THEN
        CREATE POLICY quotas_isolation_policy ON tenant_quotas FOR SELECT USING (company_id = get_auth_company_id());
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION check_message_quota(company_id_param UUID)
RETURNS BOOLEAN AS $$
DECLARE
    quota_record RECORD;
BEGIN
    SELECT * INTO quota_record FROM tenant_quotas WHERE company_id = company_id_param;
    IF NOT FOUND THEN
        INSERT INTO tenant_quotas (company_id) VALUES (company_id_param) RETURNING * INTO quota_record;
    END IF;
    IF quota_record.last_reset_at < (NOW() - INTERVAL '30 days') THEN
        UPDATE tenant_quotas SET current_message_count = 1, last_reset_at = NOW() WHERE company_id = company_id_param;
        RETURN TRUE;
    END IF;
    IF quota_record.current_message_count >= quota_record.monthly_message_limit THEN RETURN FALSE; END IF;
    UPDATE tenant_quotas SET current_message_count = current_message_count + 1, updated_at = NOW() WHERE company_id = company_id_param;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================================
-- 8. AUTOMATION RULES
-- ========================================================

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

CREATE INDEX IF NOT EXISTS idx_automation_rules_company_active ON automation_rules(company_id, is_active);
ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS company_isolation_policy ON automation_rules;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'automation_rules_isolation_policy' AND polrelid = 'automation_rules'::regclass) THEN
        CREATE POLICY automation_rules_isolation_policy ON automation_rules FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- ========================================================
-- 9. KASHEER PLUS SYNC
-- ========================================================

CREATE TABLE IF NOT EXISTS synced_inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    remote_id TEXT NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_inventory_remote_id ON synced_inventory(company_id, remote_id);
ALTER TABLE synced_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    -- DROP Legacy generic names if present
    DROP POLICY IF EXISTS company_isolation_policy ON synced_inventory;
    DROP POLICY IF EXISTS company_isolation_policy ON sync_logs;

    -- CREATE Table-specific policies
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'inventory_isolation_policy' AND polrelid = 'synced_inventory'::regclass) THEN
        CREATE POLICY inventory_isolation_policy ON synced_inventory FOR ALL USING (company_id = get_auth_company_id());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'sync_logs_isolation_policy' AND polrelid = 'sync_logs'::regclass) THEN
        CREATE POLICY sync_logs_isolation_policy ON sync_logs FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- ========================================================
-- 10. AUDIT LOGS
-- ========================================================

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS company_isolation_policy ON audit_logs;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'audit_logs_isolation_policy' AND polrelid = 'audit_logs'::regclass) THEN
        CREATE POLICY audit_logs_isolation_policy ON audit_logs FOR SELECT USING (company_id = get_auth_company_id());
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_audit_logs_company_created ON audit_logs(company_id, created_at DESC);

-- ========================================================
-- 11. PUSH NOTIFICATIONS (FCM)
-- ========================================================

CREATE TABLE IF NOT EXISTS fcm_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    device_type TEXT NOT NULL CHECK (device_type IN ('web', 'mobile')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

ALTER TABLE fcm_tokens ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'fcm_tokens_isolation_policy' AND polrelid = 'fcm_tokens'::regclass) THEN
        CREATE POLICY fcm_tokens_isolation_policy ON fcm_tokens FOR ALL USING (user_id = auth.uid());
    END IF;
END
$$;

-- ========================================================
-- 12. BILLING & INVOICES
-- ========================================================

CREATE TABLE IF NOT EXISTS billing_invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'EGP',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'cancelled')),
    provider TEXT NOT NULL CHECK (provider IN ('stripe', 'paymob', 'manual')),
    provider_id TEXT, -- External invoice/order ID
    billing_period_start TIMESTAMPTZ,
    billing_period_end TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE billing_invoices ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'billing_invoices_isolation_policy' AND polrelid = 'billing_invoices'::regclass) THEN
        CREATE POLICY billing_invoices_isolation_policy ON billing_invoices FOR SELECT USING (company_id = get_auth_company_id());
    END IF;
END
$$;
