-- Auto-creates a user_profiles row (role = 'newcomer') for every new auth.users entry.
-- Covers both email/password sign-up and OAuth (Google, Facebook, etc.).
-- Staff can later update the role via the staff-only UPDATE policy.
--
-- SECURITY DEFINER means the function runs as its owner (postgres/service role),
-- bypassing RLS to perform the INSERT regardless of who triggered it.

-- ── 1. Handler function ───────────────────────────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (user_id, role, display_name)
  values (
    new.id,
    'newcomer',
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1)
    )
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- ── 2. Trigger ────────────────────────────────────────────────────────────────

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ── 3. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0006_auth_trigger')
on conflict (version) do nothing;
