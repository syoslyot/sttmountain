-- Fixes handle_new_user() trigger which still referenced the old display_name column
-- (renamed to name in 0008). Also updates name on conflict if currently null,
-- so Google OAuth users get their name written even if a profile row already exists.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _name text;
begin
  _name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email, '@', 1)
  );

  insert into public.user_profiles (user_id, role, name)
  values (new.id, 'newcomer', _name)
  on conflict (user_id) do update
    set name = excluded.name
    where public.user_profiles.name is null;

  return new;
end;
$$;

insert into public.schema_migrations (version)
values ('0012_fix_trigger_name_column')
on conflict (version) do nothing;
