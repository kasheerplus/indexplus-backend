-- ============================================
-- COMPLETE DATABASE SETUP FOR INDEX PLUS
-- Run this entire script in Supabase SQL Editor
-- ============================================

-- 1. CREATE COMPANIES TABLE
-- ============================================
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    slug text unique not null,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- 2. CREATE USERS TABLE
-- ============================================
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid references public.companies(id) on delete cascade,
    full_name text not null,
    role text not null default 'agent' check (role in ('owner', 'admin', 'agent', 'supervisor')),
    status text not null default 'active' check (status in ('active', 'suspended')),
    permissions jsonb default '{}'::jsonb,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- 3. ENABLE ROW LEVEL SECURITY
-- ============================================
alter table public.companies enable row level security;
alter table public.users enable row level security;

-- 4. RLS POLICIES FOR COMPANIES
-- ============================================
drop policy if exists "Users can view their own company" on public.companies;
create policy "Users can view their own company"
    on public.companies for select
    using (
        id in (
            select company_id from public.users where id = auth.uid()
        )
    );

drop policy if exists "Owners can update their company" on public.companies;
create policy "Owners can update their company"
    on public.companies for update
    using (
        id in (
            select company_id from public.users 
            where id = auth.uid() and role = 'owner'
        )
    );

-- 5. RLS POLICIES FOR USERS
-- ============================================
drop policy if exists "Users can view team members in their company" on public.users;
create policy "Users can view team members in their company"
    on public.users for select
    using (
        company_id in (
            select company_id from public.users where id = auth.uid()
        )
    );

drop policy if exists "Admins can insert team members" on public.users;
create policy "Admins can insert team members"
    on public.users for insert
    with check (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role in ('owner', 'admin')
        )
    );

drop policy if exists "Admins can update team members" on public.users;
create policy "Admins can update team members"
    on public.users for update
    using (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role in ('owner', 'admin')
        )
    );

drop policy if exists "Owners can delete team members" on public.users;
create policy "Owners can delete team members"
    on public.users for delete
    using (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role = 'owner'
        )
    );

-- 6. CREATE INDEXES
-- ============================================
create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_users_role on public.users(role);
create index if not exists idx_users_status on public.users(status);
create index if not exists idx_companies_slug on public.companies(slug);

-- 7. AUTO-UPDATE TIMESTAMP FUNCTION
-- ============================================
create or replace function public.handle_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

-- 8. TRIGGERS FOR AUTO-UPDATE
-- ============================================
drop trigger if exists set_updated_at_companies on public.companies;
create trigger set_updated_at_companies
    before update on public.companies
    for each row execute function public.handle_updated_at();

drop trigger if exists set_updated_at_users on public.users;
create trigger set_updated_at_users
    before update on public.users
    for each row execute function public.handle_updated_at();

-- 9. AUTO-CREATE OWNER ON SIGNUP
-- ============================================
create or replace function public.handle_new_user()
returns trigger as $$
declare
    new_company_id uuid;
    user_email text;
    company_name text;
    company_slug text;
begin
    user_email := new.email;
    company_name := split_part(user_email, '@', 1);
    company_slug := lower(regexp_replace(company_name, '[^a-zA-Z0-9]', '-', 'g'));
    company_slug := company_slug || '-' || substring(new.id::text, 1, 8);
    
    insert into public.companies (name, slug)
    values (company_name, company_slug)
    returning id into new_company_id;
    
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- 10. SETUP FUNCTION FOR EXISTING USERS (MANUAL)
-- ============================================
create or replace function public.setup_user_manually(user_id uuid)
returns void as $$
declare
    new_company_id uuid;
    user_email text;
    company_name text;
    company_slug text;
begin
    if user_id is null then
        raise exception 'User ID cannot be null';
    end if;
    
    if exists (select 1 from public.users where id = user_id) then
        raise notice 'User already exists in public.users';
        return;
    end if;
    
    select email into user_email from auth.users where id = user_id;
    
    if user_email is null then
        raise exception 'User not found in auth.users';
    end if;
    
    company_name := split_part(user_email, '@', 1);
    company_slug := lower(regexp_replace(company_name, '[^a-zA-Z0-9]', '-', 'g'));
    company_slug := company_slug || '-' || substring(user_id::text, 1, 8);
    
    insert into public.companies (name, slug)
    values (company_name, company_slug)
    returning id into new_company_id;
    
    insert into public.users (id, company_id, full_name, role, status)
    values (
        user_id,
        new_company_id,
        company_name,
        'owner',
        'active'
    );
    
    raise notice 'User setup complete! Company ID: %, User ID: %', new_company_id, user_id;
end;
$$ language plpgsql security definer;

-- ============================================
-- SETUP COMPLETE!
-- 
-- To add yourself as owner, first get your user ID:
-- SELECT id, email FROM auth.users;
-- 
-- Then run (replace with your actual user ID):
-- SELECT public.setup_user_manually('your-user-id-here');
-- ============================================
