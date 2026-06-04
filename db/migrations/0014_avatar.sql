-- Adds avatar_url to user_profiles and creates the avatars storage bucket with RLS.

-- ── 1. Column ─────────────────────────────────────────────────────────────────

alter table public.user_profiles
  add column if not exists avatar_url text;

-- ── 2. Storage bucket ─────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- ── 3. Storage RLS ────────────────────────────────────────────────────────────

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars user insert" on storage.objects;
create policy "avatars user insert" on storage.objects
  for insert with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars user update" on storage.objects;
create policy "avatars user update" on storage.objects
  for update using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars user delete" on storage.objects;
create policy "avatars user delete" on storage.objects
  for delete using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ── 4. Update trigger to capture Google avatar ────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _name       text;
  _avatar_url text;
begin
  _name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email, '@', 1)
  );
  _avatar_url := coalesce(
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'picture'
  );

  insert into public.user_profiles (user_id, role, name, avatar_url, joined_at)
  values (new.id, 'newcomer', _name, _avatar_url, current_date)
  on conflict (user_id) do update
    set
      name       = coalesce(public.user_profiles.name, excluded.name),
      avatar_url = coalesce(public.user_profiles.avatar_url, excluded.avatar_url);

  return new;
end;
$$;

-- ── 5. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0014_avatar')
on conflict (version) do nothing;
