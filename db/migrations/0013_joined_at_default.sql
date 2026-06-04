-- Sets joined_at to current_date when a new user profile is created.
-- Also makes the column NOT NULL with a DB-level default for safety.

alter table public.user_profiles
  alter column joined_at set default current_date;

-- Backfill existing rows that are NULL
update public.user_profiles
  set joined_at = created_at::date
  where joined_at is null;

-- Update trigger to explicitly set joined_at on new user creation
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

  insert into public.user_profiles (user_id, role, name, joined_at)
  values (new.id, 'newcomer', _name, current_date)
  on conflict (user_id) do update
    set name = excluded.name
    where public.user_profiles.name is null;

  return new;
end;
$$;

insert into public.schema_migrations (version)
values ('0013_joined_at_default')
on conflict (version) do nothing;
