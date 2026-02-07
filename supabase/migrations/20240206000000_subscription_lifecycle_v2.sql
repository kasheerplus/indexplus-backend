-- ========================================================
-- MIGRATION: Subscription Lifecycle v2 (Trial & Anti-Abuse)
-- Date: 2026-02-05
-- ========================================================

-- 1. Add Device Fingerprint to Companies
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS fingerprint TEXT;
CREATE INDEX IF NOT EXISTS idx_companies_fingerprint ON public.companies(fingerprint);

-- 2. Create Trial Used Identifiers Table (Anti-Abuse)
CREATE TABLE IF NOT EXISTS public.trial_used_identifiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    identifier_type TEXT NOT NULL CHECK (identifier_type IN ('whatsapp', 'facebook', 'instagram', 'phone_number')),
    identifier_value TEXT NOT NULL,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(identifier_type, identifier_value)
);

-- 3. Update Subscriptions Status Constraint
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_status_check 
CHECK (status IN ('active', 'pending', 'expired', 'trial', 'suspended'));

-- 4. Function to check if a company is eligible for a trial
CREATE OR REPLACE FUNCTION check_trial_eligibility(company_id_param UUID, fingerprint_param TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    trial_count INTEGER;
BEGIN
    -- Check if company already had a trial
    SELECT COUNT(*) INTO trial_count 
    FROM public.subscriptions 
    WHERE company_id = company_id_param AND status IN ('trial', 'active', 'expired', 'suspended');
    
    IF trial_count > 0 THEN RETURN FALSE; END IF;

    -- Check fingerprint if provided
    IF fingerprint_param IS NOT NULL THEN
        SELECT COUNT(*) INTO trial_count 
        FROM public.companies 
        WHERE fingerprint = fingerprint_param AND id != company_id_param;
        
        IF trial_count > 0 THEN RETURN FALSE; END IF;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Modified handle_new_user to start with a 14-day trial
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  company_name_from_meta TEXT;
  full_name_from_meta TEXT;
  role_from_meta TEXT;
BEGIN
  new_company_id := (new.raw_user_meta_data->>'company_id')::UUID;
  full_name_from_meta := COALESCE(new.raw_user_meta_data->>'full_name', 'مستخدم جديد');
  role_from_meta := COALESCE(new.raw_user_meta_data->>'role', 'owner');

  IF new_company_id IS NULL THEN
    company_name_from_meta := COALESCE(new.raw_user_meta_data->>'company_name', 'شركتي الجديدة');
    
    INSERT INTO public.companies (name, slug)
    VALUES (
      company_name_from_meta, 
      LOWER(REPLACE(REPLACE(company_name_from_meta, ' ', '-'), '.', '')) || '-' || (floor(random() * 90000) + 10000)::text
    )
    RETURNING id INTO new_company_id;

    -- Default: Start with a 14-day trial on 'starter' plan
    INSERT INTO public.subscriptions (company_id, plan_id, status, starts_at, ends_at)
    VALUES (new_company_id, 'starter', 'trial', NOW(), NOW() + INTERVAL '14 days');
    
    role_from_meta := 'owner';
  END IF;

  INSERT INTO public.users (id, company_id, full_name, role, status)
  VALUES (new.id, new_company_id, full_name_from_meta, role_from_meta, 'active')
  ON CONFLICT (id) DO UPDATE 
  SET company_id = EXCLUDED.company_id, 
      full_name = EXCLUDED.full_name, 
      role = EXCLUDED.role;

  UPDATE auth.users 
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta),
      raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta, 'permissions', 
        CASE WHEN role_from_meta = 'owner' THEN '{"all": true}'::jsonb ELSE '{}'::jsonb END
      )
  WHERE id = new.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Trigger to enforce suspension on expiration (Grace Period handled in logic/view)
-- We can use a function that resets quotas if expired
CREATE OR REPLACE FUNCTION enforce_subscription_suspension()
RETURNS VOID AS $$
BEGIN
    -- For any subscription that has ended for more than 3 days and is not suspended/expired
    -- or for trials that ended more than 3 days ago.
    -- Set them to suspended and 0 quotas.
    
    UPDATE public.subscriptions
    SET status = 'suspended'
    WHERE ends_at < (NOW() - INTERVAL '3 days')
    AND status NOT IN ('suspended');

    UPDATE public.tenant_quotas
    SET monthly_message_limit = 0,
        monthly_customer_limit = 0,
        storage_limit_mb = 0
    FROM public.subscriptions
    WHERE public.tenant_quotas.company_id = public.subscriptions.company_id
    AND public.subscriptions.status = 'suspended';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
