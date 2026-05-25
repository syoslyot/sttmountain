-- Adds the DB contract required by sttmountaincrazy formal list pages and the
-- Google Drive sync logging scripts.
-- Apply to dev first, verify, then apply the same file to prod.

create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);

create table if not exists public.sync_state (
  key text primary key,
  value text not null,
  updated_at timestamptz default now()
);

insert into public.sync_state (key, value)
values ('last_synced_at', '1970-01-01T00:00:00+00:00')
on conflict (key) do nothing;

create table if not exists public.sync_logs (
  id bigserial primary key,
  synced_at timestamptz not null default now(),
  trigger text,
  status text not null default 'success',
  new_count integer not null default 0,
  existing_count integer not null default 0,
  skipped_count integer not null default 0,
  error_count integer not null default 0,
  errors jsonb not null default '[]'::jsonb,
  log_text text,
  created_at timestamptz not null default now()
);

alter table public.sync_logs
  add column if not exists synced_at timestamptz not null default now(),
  add column if not exists trigger text,
  add column if not exists status text not null default 'success',
  add column if not exists new_count integer not null default 0,
  add column if not exists existing_count integer not null default 0,
  add column if not exists skipped_count integer not null default 0,
  add column if not exists error_count integer not null default 0,
  add column if not exists errors jsonb not null default '[]'::jsonb,
  add column if not exists log_text text,
  add column if not exists created_at timestamptz not null default now();

alter table public.expeditions
add column if not exists grade text;

alter table public.records
add column if not exists file_path text;

create or replace function public.expedition_grade_from_name(p_name text)
returns text
language sql
immutable
as $$
  select nullif(upper(substring(coalesce(p_name, '') from '^[\[\［][0-9]+([A-Da-d])')), '')
$$;

update public.expeditions
set grade = public.expedition_grade_from_name(name)
where grade is null
  and public.expedition_grade_from_name(name) is not null;

create or replace function public.set_expedition_grade()
returns trigger
language plpgsql
as $$
begin
  new.grade := public.expedition_grade_from_name(new.name);
  return new;
end;
$$;

drop trigger if exists expeditions_set_grade on public.expeditions;
create trigger expeditions_set_grade
before insert or update of name on public.expeditions
for each row
execute function public.set_expedition_grade();

create index if not exists expeditions_grade_idx
on public.expeditions (grade);

create index if not exists expeditions_date_start_idx
on public.expeditions (date_start);

create index if not exists expeditions_date_end_idx
on public.expeditions (date_end);

create index if not exists expedition_counties_county_expedition_id_idx
on public.expedition_counties (county, expedition_id);

create index if not exists gpx_files_expedition_id_idx
on public.gpx_files (expedition_id);

create index if not exists map_files_expedition_id_idx
on public.map_files (expedition_id);

create index if not exists records_expedition_id_idx
on public.records (expedition_id);

drop function if exists public.list_expeditions(text, text, text[], date, date, integer, integer);
drop function if exists public.list_expeditions(text, text, text[], text, date, date, integer, integer);
drop function if exists public.list_expeditions(text, text, text[], date, date, integer, integer, text, text);

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
  from public.expeditions;
$$;

alter table public.sync_state enable row level security;
alter table public.sync_logs enable row level security;

grant all on table public.sync_state to service_role;
grant all on table public.sync_logs to service_role;
grant usage, select on sequence public.sync_logs_id_seq to service_role;
grant execute on function public.list_expeditions(text, text, text[], date, date, integer, integer, text, text)
to anon, authenticated;
grant execute on function public.get_expedition_dates()
to anon, authenticated;

revoke select on table public.expedition_counties from anon, authenticated;

insert into public.schema_migrations (version)
values ('0002_formal_list_rpc_and_sync_logs')
on conflict (version) do nothing;
