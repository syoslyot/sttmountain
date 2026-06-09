-- Store full OAuth provider metadata on user_profiles.
-- Adds provider_meta jsonb to capture everything Google returns
-- (full_name, picture, email, sub/google-id, email_verified, etc.)
-- and updates handle_new_user to persist it.

alter table public.user_profiles
  add column if not exists provider_meta jsonb;

-- Rebuild trigger function to also store raw provider metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  _name       text;
  _avatar_url text;
begin
  _name       := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
  _avatar_url := coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture');

  insert into public.user_profiles (user_id, role, name, avatar_url, joined_at, provider_meta)
  values (new.id, 'newcomer', _name, _avatar_url, current_date, new.raw_user_meta_data)
  on conflict (user_id) do update set
    name          = coalesce(public.user_profiles.name,          excluded.name),
    avatar_url    = coalesce(public.user_profiles.avatar_url,    excluded.avatar_url),
    provider_meta = coalesce(public.user_profiles.provider_meta, excluded.provider_meta);

  return new;
end;
$$;

insert into public.schema_migrations (version)
values ('0041_store_google_provider_meta')
on conflict (version) do nothing;
