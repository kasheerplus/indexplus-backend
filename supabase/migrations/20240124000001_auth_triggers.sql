-- triggers for automatic multi-tenant setup upon auth signup

-- 1. Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  company_name_from_meta TEXT;
  full_name_from_meta TEXT;
BEGIN
  -- Extract names from user_metadata (provided by SignupForm)
  company_name_from_meta := COALESCE(new.raw_user_meta_data->>'company_name', 'شركتي الجديدة');
  full_name_from_meta := COALESCE(new.raw_user_meta_data->>'full_name', 'مستخدم جديد');

  -- 2. Create the Company record
  INSERT INTO public.companies (name, slug)
  VALUES (
    company_name_from_meta, 
    LOWER(REPLACE(REPLACE(company_name_from_meta, ' ', '-'), '.', '')) || '-' || (floor(random() * 90000) + 10000)::text
  )
  RETURNING id INTO new_company_id;

  -- 3. Create the User record in the public schema
  INSERT INTO public.users (id, company_id, full_name, role, status)
  VALUES (
    new.id,
    new_company_id,
    full_name_from_meta,
    'owner',
    'active'
  );

  -- 4. Create an initial Subscription record
  INSERT INTO public.subscriptions (company_id, plan_id, status)
  VALUES (new_company_id, 'pro', 'pending');

  -- 5. Link the company_id back to user metadata for fast RLS and middleware checks
  -- Note: We use jsonb_set to update the metadata in the auth.users table
  -- We include both user_metadata (client side) and app_metadata (server side)
  UPDATE auth.users 
  SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id),
      raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'owner')
  WHERE id = new.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Attach the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
