-- Fix submit_expedition_claim to allow re-submission after rejection.
-- Previously used plain INSERT; now uses ON CONFLICT DO UPDATE so a rejected
-- claim can be reset to pending with new evidence instead of failing.

create or replace function public.submit_expedition_claim(
  p_expedition_id integer,
  p_evidence      text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.expedition_members (expedition_id, user_id, role, status, evidence)
  values (p_expedition_id, auth.uid(), 'leader', 'pending', p_evidence)
  on conflict (expedition_id, user_id)
  do update set
    status   = case
                 when expedition_members.status = 'rejected' then 'pending'
                 else expedition_members.status  -- approved/pending 不動
               end,
    evidence = case
                 when expedition_members.status = 'rejected' then excluded.evidence
                 else expedition_members.evidence
               end
  where expedition_members.status = 'rejected';
end;
$$;

grant execute on function public.submit_expedition_claim(integer, text)
to authenticated;

insert into public.schema_migrations (version)
values ('0037_fix_claim_upsert')
on conflict (version) do nothing;
