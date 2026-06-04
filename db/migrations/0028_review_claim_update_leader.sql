-- When a claim is approved, also update expeditions.leader_display
-- to the claimant's name (name → nickname → email prefix fallback).

create or replace function public.review_expedition_claim(
  p_claim_id bigint,
  p_action   text  -- 'approved' | 'rejected'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expedition_id bigint;
  v_leader_name   text;
begin
  if public.my_role() <> 'staff' then
    raise exception 'insufficient privileges';
  end if;

  if p_action not in ('approved', 'rejected') then
    raise exception 'invalid action: %', p_action;
  end if;

  select expedition_id into v_expedition_id
  from public.expedition_members
  where id = p_claim_id and role = 'leader' and status = 'pending';

  if not found then
    raise exception 'claim not found or already processed';
  end if;

  update public.expedition_members
  set status = p_action
  where id = p_claim_id;

  if p_action = 'approved' then
    select coalesce(up.name, up.nickname, split_part(au.email, '@', 1))
    into v_leader_name
    from public.expedition_members em
    join public.user_profiles up on up.user_id = em.user_id
    join auth.users au on au.id = em.user_id
    where em.id = p_claim_id;

    update public.expeditions
    set leader_display = v_leader_name
    where id = v_expedition_id;
  end if;
end;
$$;

grant execute on function public.review_expedition_claim(bigint, text)
to authenticated;

insert into public.schema_migrations (version)
values ('0028_review_claim_update_leader')
on conflict (version) do nothing;
