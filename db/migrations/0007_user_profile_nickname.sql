-- Adds a nullable nickname column to user_profiles.
-- display_name holds the real name (from OAuth or staff-assigned).
-- nickname is user-chosen and shown in UI where informality is appropriate.

alter table public.user_profiles
  add column if not exists nickname text;

-- Record migration
insert into public.schema_migrations (version)
values ('0007_user_profile_nickname')
on conflict (version) do nothing;
