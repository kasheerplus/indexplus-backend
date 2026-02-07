-- Function to automatically create company and owner user on signup
create or replace function public.handle_new_user()
returns trigger as $$
declare
    new_company_id uuid;
    user_email text;
    company_name text;
    company_slug text;
begin
    -- Get user email
    user_email := new.email;
    
    -- Generate company name from email (before @)
    company_name := split_part(user_email, '@', 1);
    
    -- Generate unique slug
    company_slug := lower(regexp_replace(company_name, '[^a-zA-Z0-9]', '-', 'g'));
    
    -- Make sure slug is unique
    company_slug := company_slug || '-' || substring(new.id::text, 1, 8);
    
    -- Create company
    insert into public.companies (name, slug)
    values (company_name, company_slug)
    returning id into new_company_id;
    
    -- Create owner user
    insert into public.users (id, company_id, full_name, role, status)
    values (
        new.id,
        new_company_id,
        coalesce(new.raw_user_meta_data->>'full_name', company_name),
        'owner',
        'active'
    );
    
    return new;
end;
$$ language plpgsql security definer;

-- Trigger to run after user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Also create a manual function to add existing users
create or replace function public.setup_existing_user()
returns void as $$
declare
    current_user_id uuid;
    new_company_id uuid;
    user_email text;
    company_name text;
    company_slug text;
begin
    -- Get current user
    current_user_id := auth.uid();
    
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    
    -- Check if user already exists in public.users
    if exists (select 1 from public.users where id = current_user_id) then
        raise notice 'User already exists in public.users';
        return;
    end if;
    
    -- Get user email from auth.users
    select email into user_email from auth.users where id = current_user_id;
    
    -- Generate company name from email
    company_name := split_part(user_email, '@', 1);
    company_slug := lower(regexp_replace(company_name, '[^a-zA-Z0-9]', '-', 'g'));
    company_slug := company_slug || '-' || substring(current_user_id::text, 1, 8);
    
    -- Create company
    insert into public.companies (name, slug)
    values (company_name, company_slug)
    returning id into new_company_id;
    
    -- Create owner user
    insert into public.users (id, company_id, full_name, role, status)
    values (
        current_user_id,
        new_company_id,
        company_name,
        'owner',
        'active'
    );
    
    raise notice 'User setup complete! Company ID: %, User ID: %', new_company_id, current_user_id;
end;
$$ language plpgsql security definer;
