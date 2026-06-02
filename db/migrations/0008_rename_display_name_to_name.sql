-- Renames user_profiles.display_name to name for clarity.

alter table public.user_profiles
  rename column display_name to name;

insert into public.schema_migrations (version)
values ('0008_rename_display_name_to_name')
on conflict (version) do nothing;
