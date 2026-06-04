-- Adds contact and joined_at to user_profiles.
-- Also adds RLS policy allowing users to update their own name/nickname/contact.

-- ── 1. New columns ────────────────────────────────────────────────────────────

alter table public.user_profiles
  add column if not exists contact   text,
  add column if not exists joined_at date;

-- ── 2. RLS: user can update own profile (excludes role — staff-only) ──────────

drop policy if exists "user update own profile" on public.user_profiles;
create policy "user update own profile" on public.user_profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── 3. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0010_user_profile_contact_joined')
on conflict (version) do nothing;
