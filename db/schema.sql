-- ============================================================
-- sttmountain Supabase Schema
-- 適用於正式環境與開發環境（在 Supabase SQL Editor 執行）
-- ============================================================

-- ── Tables ──────────────────────────────────────────────────

create table if not exists expedition_groups (
  id              bigserial primary key,
  name            text not null,
  drive_folder_id text unique not null,
  created_at      timestamptz default now()
);

create table if not exists expeditions (
  id                   bigserial primary key,
  group_id             bigint not null references expedition_groups(id),
  drive_folder_id      text unique not null,
  name                 text not null,
  date_start           date not null,
  date_end             date,
  region_entry_county  text,
  region_entry_town    text,
  region_exit_county   text,
  region_exit_town     text,
  leader               text,
  grade                text,
  preview_image        text,
  created_at           timestamptz default now()
);

create table if not exists expedition_counties (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  county         text not null,
  unique (expedition_id, county)
);

create table if not exists gpx_files (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  drive_file_id  text unique not null,
  filename       text not null,
  file_path      text not null
);

create table if not exists map_files (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  drive_file_id  text unique not null,
  filename       text not null,
  file_path      text not null
);

create table if not exists records (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  drive_file_id  text unique not null,
  filename       text not null,
  content        text,
  file_path      text
);

create table if not exists sync_state (
  key        text primary key,
  value      text not null,
  updated_at timestamptz default now()
);

create table if not exists sync_logs (
  id             bigserial primary key,
  synced_at      timestamptz not null default now(),
  trigger        text,
  status         text not null default 'success',
  new_count      integer not null default 0,
  existing_count integer not null default 0,
  skipped_count  integer not null default 0,
  error_count    integer not null default 0,
  errors         jsonb not null default '[]'::jsonb,
  log_text       text,
  created_at     timestamptz not null default now()
);

create table if not exists schema_migrations (
  version    text primary key,
  applied_at timestamptz not null default now()
);

alter table expeditions add column if not exists grade text;
alter table records add column if not exists file_path text;

insert into schema_migrations (version)
values ('0001_baseline')
on conflict (version) do nothing;

-- 初始化 last_synced_at（若尚未存在）
insert into sync_state (key, value) values ('last_synced_at', '1970-01-01T00:00:00+00:00')
  on conflict (key) do nothing;

-- ── RLS ─────────────────────────────────────────────────────

alter table expedition_groups  enable row level security;
alter table expeditions        enable row level security;
alter table expedition_counties enable row level security;
alter table gpx_files          enable row level security;
alter table map_files          enable row level security;
alter table records            enable row level security;
alter table sync_state         enable row level security;
alter table sync_logs          enable row level security;

do $$ begin
  drop policy if exists "anon select" on expedition_groups;
  drop policy if exists "anon select" on expeditions;
  drop policy if exists "anon select" on expedition_counties;
  drop policy if exists "anon select" on gpx_files;
  drop policy if exists "anon select" on map_files;
  drop policy if exists "anon select" on records;
end $$;

create policy "anon select" on expedition_groups  for select to anon using (true);
create policy "anon select" on expeditions        for select to anon using (true);
create policy "anon select" on expedition_counties for select to anon using (true);
create policy "anon select" on gpx_files          for select to anon using (true);
create policy "anon select" on map_files          for select to anon using (true);
create policy "anon select" on records            for select to anon using (true);
-- sync_state：anon 不可讀（only service_role）
-- sync_logs：anon 不可讀（only service_role）

-- service_role 需要對所有 table 有完整權限（CI sync 腳本使用）
grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- ── Storage Buckets ──────────────────────────────────────────
-- 在 Supabase Dashboard → Storage 手動建立以下三個 public bucket：
--   gpx      — GPX / KML 軌跡檔
--   maps     — 地圖檔（PDF、docx、圖片）
--   previews — 出隊計畫書預覽圖

-- ── RPC Functions ────────────────────────────────────────────

create or replace function expedition_grade_from_name(p_name text)
returns text
language sql
immutable
as $$
  select nullif(upper(substring(coalesce(p_name, '') from '^[\[\［][0-9]+([A-Da-d])')), '')
$$;

update expeditions
set grade = expedition_grade_from_name(name)
where grade is null
  and expedition_grade_from_name(name) is not null;

create or replace function set_expedition_grade()
returns trigger
language plpgsql
as $$
begin
  new.grade := expedition_grade_from_name(new.name);
  return new;
end;
$$;

drop trigger if exists expeditions_set_grade on expeditions;
create trigger expeditions_set_grade
before insert or update of name on expeditions
for each row
execute function set_expedition_grade();

create index if not exists expeditions_grade_idx
on expeditions (grade);

create index if not exists expeditions_date_start_idx
on expeditions (date_start);

create index if not exists expeditions_date_end_idx
on expeditions (date_end);

create index if not exists expedition_counties_county_expedition_id_idx
on expedition_counties (county, expedition_id);

create index if not exists gpx_files_expedition_id_idx
on gpx_files (expedition_id);

create index if not exists map_files_expedition_id_idx
on map_files (expedition_id);

create index if not exists records_expedition_id_idx
on records (expedition_id);

drop function if exists list_expeditions(text, text, text[], date, date, integer, integer);
drop function if exists list_expeditions(text, text, text[], text, date, date, integer, integer);
drop function if exists list_expeditions(text, text, text[], date, date, integer, integer, text, text);

create or replace function list_expeditions(
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

create or replace function get_expedition_dates()
returns json
language sql
security definer
as $$
  select json_build_object(
    'min_date', min(date_start),
    'max_date', max(date_start)
  )
  from expeditions;
$$;

create or replace function get_expedition_years()
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
    where date_start is not null
  ) years;
$$;

grant execute on function list_expeditions(text, text, text[], date, date, integer, integer, text, text) to anon, authenticated;
grant execute on function get_expedition_dates() to anon, authenticated;
grant execute on function get_expedition_years() to anon, authenticated;
