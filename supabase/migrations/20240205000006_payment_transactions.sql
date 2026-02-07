-- ========================================================
-- MIGRATION: Payment Transactions & Integration
-- Date: 2026-02-05
-- Purpose: Support Egyptian payment methods via Paymob
-- ========================================================

-- 1. Payment Transactions Table
CREATE TABLE IF NOT EXISTS payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    order_id UUID REFERENCES sales_records(id) ON DELETE SET NULL,
    
    -- Payment Details
    amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'EGP',
    payment_method TEXT NOT NULL CHECK (payment_method IN ('fawry', 'vodafone_cash', 'orange_money', 'etisalat_cash', 'card', 'manual')),
    
    -- Gateway Integration (Paymob)
    gateway_provider TEXT DEFAULT 'paymob',
    gateway_transaction_id TEXT,
    gateway_order_id TEXT,
    gateway_payment_url TEXT,
    gateway_reference_code TEXT, -- For Fawry reference code
    
    -- Status Tracking
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'success', 'failed', 'expired', 'refunded')),
    failure_reason TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    paid_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
    
    -- Metadata (Store full gateway response)
    metadata JSONB DEFAULT '{}',
    
    -- Constraints
    UNIQUE(gateway_transaction_id)
);

-- 2. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_payment_transactions_company ON payment_transactions(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_gateway_id ON payment_transactions(gateway_transaction_id) WHERE gateway_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_transactions_customer ON payment_transactions(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_transactions_order ON payment_transactions(order_id) WHERE order_id IS NOT NULL;

-- 3. Row Level Security
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS payment_transactions_isolation_policy ON payment_transactions;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'payment_transactions_isolation_policy' AND polrelid = 'payment_transactions'::regclass) THEN
        CREATE POLICY payment_transactions_isolation_policy ON payment_transactions FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- 4. Helper Functions

-- Get payment statistics for a company
CREATE OR REPLACE FUNCTION get_payment_stats(company_id_param UUID, days_back INTEGER DEFAULT 30)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_revenue', COALESCE(SUM(amount) FILTER (WHERE status = 'success'), 0),
        'total_transactions', COUNT(*) FILTER (WHERE status = 'success'),
        'pending_amount', COALESCE(SUM(amount) FILTER (WHERE status = 'pending'), 0),
        'failed_count', COUNT(*) FILTER (WHERE status = 'failed'),
        'success_rate', CASE 
            WHEN COUNT(*) > 0 THEN ROUND((COUNT(*) FILTER (WHERE status = 'success')::NUMERIC / COUNT(*)) * 100, 2)
            ELSE 0
        END,
        'by_method', (
            SELECT jsonb_object_agg(payment_method, method_stats)
            FROM (
                SELECT 
                    payment_method,
                    jsonb_build_object(
                        'count', COUNT(*),
                        'revenue', COALESCE(SUM(amount) FILTER (WHERE status = 'success'), 0)
                    ) as method_stats
                FROM payment_transactions
                WHERE company_id = company_id_param
                AND created_at > NOW() - (days_back || ' days')::INTERVAL
                GROUP BY payment_method
            ) method_breakdown
        )
    ) INTO result
    FROM payment_transactions
    WHERE company_id = company_id_param
    AND created_at > NOW() - (days_back || ' days')::INTERVAL;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Auto-expire pending payments
CREATE OR REPLACE FUNCTION expire_pending_payments()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    UPDATE payment_transactions
    SET status = 'expired'
    WHERE status = 'pending'
    AND expires_at < NOW()
    RETURNING COUNT(*) INTO expired_count;
    
    RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Trigger to update order status on payment success
CREATE OR REPLACE FUNCTION update_order_on_payment()
RETURNS TRIGGER AS $$
BEGIN
    -- If payment succeeded and linked to an order, mark order as completed
    IF NEW.status = 'success' AND NEW.order_id IS NOT NULL THEN
        UPDATE sales_records
        SET status = 'completed'
        WHERE id = NEW.order_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_payment_success ON payment_transactions;
CREATE TRIGGER on_payment_success
  AFTER UPDATE ON payment_transactions
  FOR EACH ROW
  WHEN (OLD.status != 'success' AND NEW.status = 'success')
  EXECUTE FUNCTION update_order_on_payment();

-- 6. Payment Gateway Configuration Table
CREATE TABLE IF NOT EXISTS payment_gateway_config (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'paymob',
    
    -- Paymob Credentials (Encrypted in application layer)
    api_key_encrypted TEXT,
    integration_id_card TEXT,
    integration_id_fawry TEXT,
    integration_id_wallet TEXT,
    iframe_id TEXT,
    hmac_secret_encrypted TEXT,
    
    -- Settings
    is_sandbox BOOLEAN DEFAULT TRUE,
    enabled_methods TEXT[] DEFAULT ARRAY['fawry', 'card', 'vodafone_cash'],
    
    -- Status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended')),
    verified_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE payment_gateway_config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS payment_gateway_config_isolation_policy ON payment_gateway_config;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'payment_gateway_config_isolation_policy' AND polrelid = 'payment_gateway_config'::regclass) THEN
        CREATE POLICY payment_gateway_config_isolation_policy ON payment_gateway_config FOR ALL USING (company_id = get_auth_company_id());
    END IF;
END
$$;

-- 7. Initial Data (Optional: System-level test config)
-- Companies can add their own config via the UI
