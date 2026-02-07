-- ========================================================
-- MIGRATION: Subscription Logic & Quotas
-- Date: 2026-02-05
-- ========================================================

-- 1. Helper function to set quotas based on plan
CREATE OR REPLACE FUNCTION update_tenant_quotas()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update if plan_id changed
    IF (TG_OP = 'UPDATE' AND OLD.plan_id = NEW.plan_id) THEN
        RETURN NEW;
    END IF;

    -- Update Quotas based on Plan
    -- Free: 50 conversations, 100 auto-messages
    -- Basic: 1000 conversations
    -- Business/Pro: Unlimited (-1)
    
    INSERT INTO public.tenant_quotas (company_id, monthly_message_limit, monthly_customer_limit)
    VALUES (NEW.company_id, 
        CASE 
            WHEN NEW.plan_id = 'free' THEN 100 
            WHEN NEW.plan_id = 'basic' THEN 1000 
            ELSE 999999 -- Unlimited
        END,
        CASE 
            WHEN NEW.plan_id = 'free' THEN 50
            ELSE 999999 -- Unlimited
        END
    )
    ON CONFLICT (company_id) DO UPDATE 
    SET monthly_message_limit = EXCLUDED.monthly_message_limit,
        monthly_customer_limit = EXCLUDED.monthly_customer_limit,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger on Subscriptions table
DROP TRIGGER IF EXISTS on_subscription_change ON subscriptions;
CREATE TRIGGER on_subscription_change
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_tenant_quotas();

-- 3. Update Default Plan for New Users (Signup Flow)
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

    -- CHANGED: Default plan is now 'free' and active
    INSERT INTO public.subscriptions (company_id, plan_id, status)
    VALUES (new_company_id, 'free', 'active');
    
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
