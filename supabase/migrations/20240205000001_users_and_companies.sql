-- Create companies table
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    slug text unique not null,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Create users table (extends auth.users)
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

-- Enable RLS
alter table public.companies enable row level security;
alter table public.users enable row level security;

-- RLS Policies for companies
create policy "Users can view their own company"
    on public.companies for select
    using (
        id in (
            select company_id from public.users where id = auth.uid()
        )
    );

create policy "Owners can update their company"
    on public.companies for update
    using (
        id in (
            select company_id from public.users 
            where id = auth.uid() and role = 'owner'
        )
    );

-- RLS Policies for users
create policy "Users can view team members in their company"
    on public.users for select
    using (
        company_id in (
            select company_id from public.users where id = auth.uid()
        )
    );

create policy "Admins can insert team members"
    on public.users for insert
    with check (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role in ('owner', 'admin')
        )
    );

create policy "Admins can update team members"
    on public.users for update
    using (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role in ('owner', 'admin')
        )
    );

create policy "Owners can delete team members"
    on public.users for delete
    using (
        company_id in (
            select company_id from public.users 
            where id = auth.uid() and role = 'owner'
        )
    );

-- Indexes for performance
create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_users_role on public.users(role);
create index if not exists idx_users_status on public.users(status);
create index if not exists idx_companies_slug on public.companies(slug);

-- Function to automatically update updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

-- Triggers for updated_at
create trigger set_updated_at_companies
    before update on public.companies
    for each row execute function public.handle_updated_at();

create trigger set_updated_at_users
    before update on public.users
    for each row execute function public.handle_updated_at();
