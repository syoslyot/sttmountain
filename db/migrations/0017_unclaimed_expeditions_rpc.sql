-- RPC: returns public expeditions that have no approved leader in expedition_members.
-- These are the expeditions available for claiming.

create or replace function public.list_unclaimed_expeditions(
  p_q     text    default '',
  p_grade text    default ''
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id',                  e.id,
      'name',                e.name,
      'grade',               e.grade,
      'date_start',          e.date_start,
      'date_end',            e.date_end,
      'leader_display',      e.leader_display,
      'region_entry_county', e.region_entry_county,
      'region_entry_town',   e.region_entry_town,
      'region_exit_county',  e.region_exit_county,
      'region_exit_town',    e.region_exit_town
    )
    order by e.date_start desc
  ),
  '[]'::jsonb
)
from public.expeditions e
where
  e.is_public is true
  and not exists (
    select 1 from public.expedition_members em
    where em.expedition_id = e.id
      and em.role = 'leader'
      and em.status = 'approved'
  )
  and (coalesce(p_q, '') = ''
    or e.name ilike '%' || p_q || '%'
    or e.leader_display ilike '%' || p_q || '%'
    or e.region_entry_county ilike '%' || p_q || '%'
    or e.region_entry_town ilike '%' || p_q || '%')
  and (coalesce(p_grade, '') = '' or e.grade = upper(p_grade));
$$;

grant execute on function public.list_unclaimed_expeditions(text, text)
to authenticated;

insert into public.schema_migrations (version)
values ('0017_unclaimed_expeditions_rpc')
on conflict (version) do nothing;
