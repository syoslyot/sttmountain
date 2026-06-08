-- Fixes infinite recursion in user_profiles RLS policies.
-- The staff policies queried user_profiles inside user_profiles RLS, causing recursion.
-- Solution: a SECURITY DEFINER helper function that bypasses RLS when fetching the caller's role.

create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role::text from public.user_profiles where user_id = auth.uid()
$$;

-- Re-create policies using my_role() instead of a subquery on user_profiles

drop policy if exists "staff select all" on public.user_profiles;
create policy "staff select all" on public.user_profiles
  for select
  using (public.my_role() = 'staff');

drop policy if exists "staff insert" on public.user_profiles;
create policy "staff insert" on public.user_profiles
  for insert
  with check (public.my_role() = 'staff');

drop policy if exists "staff update" on public.user_profiles;
create policy "staff update" on public.user_profiles
  for update
  using (public.my_role() = 'staff');

insert into public.schema_migrations (version)
values ('0009_fix_rls_recursion')
on conflict (version) do nothing;
