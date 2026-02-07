-- Migration: Fix RLS Policies Circular Dependency
-- Date: 2026-02-05
-- Issue: RLS policies on users table were causing 500 errors due to circular dependencies
-- Solution: Use security definer function to bypass RLS when checking permissions

-- 1. Drop all existing problematic policies
drop policy if exists "Users can view team members in their company" on public.users;
drop policy if exists "Admins can insert team members" on public.users;
drop policy if exists "Admins can update team members" on public.users;
drop policy if exists "Owners can delete team members" on public.users;
drop policy if exists "Users can view their own data" on public.users;
drop policy if exists "Users can view company members" on public.users;
drop policy if exists "Owners and admins can add members" on public.users;
drop policy if exists "Owners and admins can update members" on public.users;
drop policy if exists "Owners can delete members" on public.users;
drop policy if exists "Users can update their own profile" on public.users;

-- 2. Create a security definer function to get current user's company and role
-- This function runs with elevated privileges and bypasses RLS to avoid circular dependencies
create or replace function public.get_current_user_info()
returns table(user_company_id uuid, user_role text)
language sql
security definer
stable
as $$
    select company_id, role 
    from public.users 
    where id = auth.uid()
    limit 1;
$$;

-- Grant execute permission to authenticated users
grant execute on function public.get_current_user_info() to authenticated;

-- 3. Create new, non-circular policies using the security definer function

-- Allow users to view their own record
create policy "Users can view their own data"
    on public.users for select
    using (id = auth.uid());

-- Allow users to view other users in same company
create policy "Users can view company members"
    on public.users for select
    using (
        company_id = (select user_company_id from public.get_current_user_info())
    );

-- Allow owners and admins to insert new team members in their company
create policy "Owners and admins can add members"
    on public.users for insert
    with check (
        (select user_role from public.get_current_user_info()) in ('owner', 'admin')
        and company_id = (select user_company_id from public.get_current_user_info())
    );

-- Allow owners and admins to update team members in their company
create policy "Owners and admins can update members"
    on public.users for update
    using (
        (select user_role from public.get_current_user_info()) in ('owner', 'admin')
        and company_id = (select user_company_id from public.get_current_user_info())
    );

-- Allow users to update their own profile
create policy "Users can update their own profile"
    on public.users for update
    using (id = auth.uid());

-- Allow owners to delete team members in their company
create policy "Owners can delete members"
    on public.users for delete
    using (
        (select user_role from public.get_current_user_info()) = 'owner'
        and company_id = (select user_company_id from public.get_current_user_info())
    );
