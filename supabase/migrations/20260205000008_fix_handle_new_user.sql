-- Migration: Fix handle_new_user trigger to support invitations
-- Date: 2026-02-05

-- 1. Redefine the function to be smarter about metadata
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id uuid;
    full_name_from_meta text;
    role_from_meta text;
    company_name_from_meta text;
    company_slug text;
BEGIN
    -- 1. Try to get data from metadata (Invitation/Admin Flow)
    -- We use raw_user_meta_data which is passed during auth.admin.createUser
    new_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    role_from_meta := COALESCE(new.raw_user_meta_data->>'role', 'owner');
    full_name_from_meta := COALESCE(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1));

    -- 2. If no company_id, it's a new Signup Flow
    IF new_company_id IS NULL THEN
        company_name_from_meta := COALESCE(new.raw_user_meta_data->>'company_name', split_part(new.email, '@', 1));
        company_slug := lower(regexp_replace(company_name_from_meta, '[^a-zA-Z0-9]', '-', 'g')) || '-' || substring(new.id::text, 1, 8);
        
        INSERT INTO public.companies (name, slug)
        VALUES (company_name_from_meta, company_slug)
        RETURNING id INTO new_company_id;
        
        role_from_meta := 'owner'; -- Signup user is always owner
    END IF;

    -- 3. Create the public.users record
    INSERT INTO public.users (id, company_id, full_name, role, status)
    VALUES (new.id, new_company_id, full_name_from_meta, role_from_meta, 'active')
    ON CONFLICT (id) DO UPDATE 
    SET company_id = EXCLUDED.company_id,
        full_name = EXCLUDED.full_name,
        role = EXCLUDED.role;

    -- 4. Sync metadata back to auth.users (Ensures JWT reflects the role/company correctly)
    UPDATE auth.users 
    SET raw_user_meta_data = raw_user_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta),
        raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', role_from_meta)
    WHERE id = new.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Cleanup Script: Fix users incorrectly created as owners of their own companies
-- This part identifies users who were added as 'owner' in the last hour but exist in meta as something else
-- OR simply allows manual correction if needed.
-- For safety, we just provide the query to find them:
/*
SELECT u.id, u.full_name, u.company_id, c.name as company_name
FROM public.users u
JOIN public.companies c ON u.company_id = c.id
WHERE u.role = 'owner' 
AND u.created_at > (now() - interval '1 hour');
*/
