-- Adds public visibility control for expeditions and ensures public-facing
-- RPCs/tables only expose visible expeditions.
-- Apply to dev first, verify, then apply the same file to prod.

create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);

alter table public.schema_migrations enable row level security;

alter table public.expeditions
add column if not exists is_public boolean not null default true;

create index if not exists expeditions_is_public_idx
on public.expeditions (is_public);

do $$ begin
  drop policy if exists "anon select" on public.expedition_groups;
  drop policy if exists "anon select" on public.expeditions;
  drop policy if exists "anon select" on public.expedition_counties;
  drop policy if exists "anon select" on public.gpx_files;
  drop policy if exists "anon select" on public.map_files;
  drop policy if exists "anon select" on public.records;
end $$;

create policy "anon select" on public.expedition_groups for select to anon using (
  exists (
    select 1
    from public.expeditions e
    where e.group_id = expedition_groups.id
      and e.is_public is true
  )
);
create policy "anon select" on public.expeditions for select to anon using (is_public is true);
create policy "anon select" on public.expedition_counties for select to anon using (
  exists (
    select 1
    from public.expeditions e
    where e.id = expedition_counties.expedition_id
      and e.is_public is true
  )
);
create policy "anon select" on public.gpx_files for select to anon using (
  exists (
    select 1
    from public.expeditions e
    where e.id = gpx_files.expedition_id
      and e.is_public is true
  )
);
create policy "anon select" on public.map_files for select to anon using (
  exists (
    select 1
    from public.expeditions e
    where e.id = map_files.expedition_id
      and e.is_public is true
  )
);
create policy "anon select" on public.records for select to anon using (
  exists (
    select 1
    from public.expeditions e
    where e.id = records.expedition_id
      and e.is_public is true
  )
);

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
    e.is_public is true
    and (coalesce(p_q, '') = ''
      or e.name ilike '%' || p_q || '%'
      or e.leader ilike '%' || p_q || '%')
    and (coalesce(p_grade, '') = '' or e.grade = upper(p_grade))
    and (p_start is null or coalesce(e.date_end, e.date_start) >= p_start)
    and (p_end is null or e.date_start <= p_end)
    and (
      coalesce(p_county, '') = ''
      or exists (
        select 1
        from public.expedition_counties ec
        where ec.expedition_id = e.id
          and ec.county = p_county
      )
    )
    and (
      coalesce(array_length(p_counties, 1), 0) = 0
      or exists (
        select 1
        from public.expedition_counties ec
        where ec.expedition_id = e.id
          and ec.county = any(p_counties)
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
    (select count(*) from public.gpx_files gf where gf.expedition_id = p.id)::int as gpx_count,
    (select count(*) from public.map_files mf where mf.expedition_id = p.id)::int as map_count,
    (select count(*) from public.records rf where rf.expedition_id = p.id)::int as rec_count
  from page_rows p
)
select jsonb_build_object(
  'expeditions',
  coalesce(
    jsonb_agg(
      to_jsonb(p)
      || jsonb_build_object(
        'gpx_count', c.gpx_count,
        'map_count', c.map_count,
        'rec_count', c.rec_count
      )
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

create or replace function public.get_expedition_dates()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'min_date', min(date_start),
    'max_date', max(date_start)
  )
  from public.expeditions
  where is_public is true;
$$;

create or replace function public.get_expedition_years()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(json_agg(year order by year desc), '[]'::json)
  from (
    select distinct extract(year from date_start)::int as year
    from public.expeditions
    where is_public is true
      and date_start is not null
  ) years;
$$;

grant execute on function public.list_expeditions(text, text, text[], date, date, integer, integer, text, text)
to anon, authenticated;
grant execute on function public.get_expedition_dates()
to anon, authenticated;
grant execute on function public.get_expedition_years()
to anon, authenticated;

insert into public.schema_migrations (version)
values ('0004_expedition_public_visibility')
on conflict (version) do nothing;
