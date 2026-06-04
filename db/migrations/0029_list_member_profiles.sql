-- Returns all user profiles for staff or any approved expedition leader.
-- Used by the edit page member selector.

create or replace function public.list_member_profiles()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then '[]'::jsonb
    when public.my_role() = 'staff'
      or exists (
        select 1 from public.expedition_members
        where user_id = auth.uid()
          and role = 'leader'
          and status = 'approved'
      )
    then (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'user_id',  user_id,
            'name',     name,
            'nickname', nickname
          )
          order by name nulls last
        ),
        '[]'::jsonb
      )
      from public.user_profiles
    )
    else '[]'::jsonb
  end
$$;

grant execute on function public.list_member_profiles()
to authenticated;

insert into public.schema_migrations (version)
values ('0029_list_member_profiles')
on conflict (version) do nothing;
