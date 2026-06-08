-- Renames records table to record_files for naming consistency with gpx_files and map_files.
-- RLS policies and indexes follow the table automatically; only the RPC referencing the
-- table name needs to be re-created.

-- ── 1. Rename table ───────────────────────────────────────────────────────────

alter table public.records rename to record_files;

-- ── 2. Re-create list_expeditions RPC with updated table reference ────────────

drop function if exists public.list_expeditions(text,text,text[],date,date,integer,integer,text,text);

create or replace function public.list_expeditions(
  p_q text default '',
  p_county text default '',
  p_counties text[] default '{}'::text[],
  p_start date default null,
  p_end date default null,
  p_page integer default 1,
  p_page_size integer default 20,
  p_grade text default '',
  p_sort text default 'latest'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
with filtered as (
  select e.*
  from public.expeditions e
  where
    (coalesce(p_q, '') = ''
      or e.name ilike '%' || p_q || '%'
      or e.leader_display ilike '%' || p_q || '%')
    and (coalesce(p_grade, '') = '' or e.grade = upper(p_grade))
    and (p_start is null or coalesce(e.date_end, e.date_start) >= p_start)
    and (p_end is null or e.date_start <= p_end)
    and (
      coalesce(p_county, '') = ''
      or exists (
        select 1 from public.expedition_counties ec
        where ec.expedition_id = e.id and ec.county = p_county
      )
    )
    and (
      coalesce(array_length(p_counties, 1), 0) = 0
      or exists (
        select 1 from public.expedition_counties ec
        where ec.expedition_id = e.id and ec.county = any(p_counties)
      )
    )
),
page_rows as (
  select *
  from filtered
  order by
    case when p_sort = 'oldest' then coalesce(date_end, date_start) end asc nulls last,
    case when p_sort <> 'oldest' then coalesce(date_end, date_start) end desc nulls last,
    id desc
  limit greatest(p_page_size, 1)
  offset greatest(p_page - 1, 0) * greatest(p_page_size, 1)
),
counts as (
  select
    p.id,
    (select count(*) from public.gpx_files    gf where gf.expedition_id = p.id)::int as gpx_count,
    (select count(*) from public.map_files    mf where mf.expedition_id = p.id)::int as map_count,
    (select count(*) from public.record_files rf where rf.expedition_id = p.id)::int as rec_count
  from page_rows p
)
select jsonb_build_object(
  'expeditions',
  coalesce(
    jsonb_agg(
      to_jsonb(p)
      || jsonb_build_object('gpx_count', c.gpx_count, 'map_count', c.map_count, 'rec_count', c.rec_count)
      order by
        case when p_sort = 'oldest' then coalesce(p.date_end, p.date_start) end asc nulls last,
        case when p_sort <> 'oldest' then coalesce(p.date_end, p.date_start) end desc nulls last,
        p.id desc
    ),
    '[]'::jsonb
  ),
  'total', (select count(*) from filtered),
  'page', greatest(p_page, 1),
  'pageSize', greatest(p_page_size, 1)
)
from page_rows p
left join counts c on c.id = p.id;
$$;

-- ── 3. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0019_rename_records_to_record_files')
on conflict (version) do nothing;
