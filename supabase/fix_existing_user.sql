-- Run this SQL to fix an existing user account that doesn't have a company link

DO $$
DECLARE
  target_user_id UUID := 'REPLACE_WITH_YOUR_USER_ID'; -- You can find this in Supabase Auth Users
  target_company_name TEXT := 'اسم شركتك';
  new_company_id UUID;
BEGIN
  -- 1. Create Company if not exists
  INSERT INTO public.companies (name, slug)
  VALUES (target_company_name, LOWER(REPLACE(target_company_name, ' ', '-')) || '-' || (floor(random()*10000))::text)
  RETURNING id INTO new_company_id;

  -- 2. Create Public User record
  INSERT INTO public.users (id, company_id, full_name, role, status)
  VALUES (target_user_id, new_company_id, 'المالك', 'owner', 'active')
  ON CONFLICT (id) DO UPDATE SET company_id = new_company_id, role = 'owner';

  -- 3. Update Auth Metadata
  UPDATE auth.users 
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'owner'),
      raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'owner')
  WHERE id = target_user_id;

  RAISE NOTICE 'User % has been linked to company %', target_user_id, new_company_id;
END $$;
