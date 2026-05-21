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
  content        text
);

create table if not exists sync_state (
  key        text primary key,
  value      text not null,
  updated_at timestamptz default now()
);

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

-- ── Storage Buckets ──────────────────────────────────────────
-- 在 Supabase Dashboard → Storage 手動建立以下三個 public bucket：
--   gpx      — GPX / KML 軌跡檔
--   maps     — 地圖檔（PDF、docx、圖片）
--   previews — 出隊計畫書預覽圖

-- ── RPC Functions ────────────────────────────────────────────

create or replace function list_expeditions(
  p_q         text    default null,
  p_county    text    default null,
  p_counties  text[]  default null,
  p_start     date    default null,
  p_end       date    default null,
  p_page      int     default 1,
  p_page_size int     default 20
)
returns json
language plpgsql
as $$
declare
  v_offset   int    := (p_page - 1) * p_page_size;
  v_total    int;
  v_rows     json;
  v_q        text   := nullif(trim(p_q),      '');
  v_county   text   := nullif(trim(p_county), '');
  v_start    date   := p_start;
  v_end      date   := p_end;
  v_counties text[] := case when cardinality(p_counties) = 0 then null else p_counties end;
begin
  select count(*) into v_total
  from expeditions e
  where
    (v_q is null or e.name ilike '%' || v_q || '%')
    and (v_county is null or exists (
          select 1 from expedition_counties ec
          where ec.expedition_id = e.id and ec.county = v_county
        ))
    and (v_counties is null or exists (
          select 1 from expedition_counties ec
          where ec.expedition_id = e.id and ec.county = any(v_counties)
        ))
    and (v_start is null or e.date_start >= v_start)
    and (v_end   is null or e.date_start <= v_end);

  select json_agg(row_to_json(r)) into v_rows
  from (
    select e.*
    from expeditions e
    where
      (v_q is null or e.name ilike '%' || v_q || '%')
      and (v_county is null or exists (
            select 1 from expedition_counties ec
            where ec.expedition_id = e.id and ec.county = v_county
          ))
      and (v_counties is null or exists (
            select 1 from expedition_counties ec
            where ec.expedition_id = e.id and ec.county = any(v_counties)
          ))
      and (v_start is null or e.date_start >= v_start)
      and (v_end   is null or e.date_start <= v_end)
    order by e.date_start desc
    limit p_page_size offset v_offset
  ) r;

  return json_build_object(
    'expeditions', coalesce(v_rows, '[]'::json),
    'total',       v_total,
    'page',        p_page,
    'pageSize',    p_page_size
  );
end;
$$;

create or replace function get_expedition_dates()
returns json
language sql
as $$
  select json_build_object(
    'min_date', min(date_start),
    'max_date', max(date_start)
  )
  from expeditions;
$$;
