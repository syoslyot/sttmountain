-- ============================================================
-- sttmountain Supabase Schema
-- 適用於正式環境與開發環境（在 Supabase SQL Editor 執行）
-- ============================================================

-- ── Tables ──────────────────────────────────────────────────

create table if not exists expeditions (
  id            bigserial primary key,
  name          text not null,
  date_start    date not null,
  date_end      date,
  county        text,
  region        text,
  region_exit   text,
  leader        text,
  description   text,
  preview_image text,
  created_at    timestamptz default now()
);

create table if not exists expedition_counties (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  county         text not null,
  unique (expedition_id, county)
);

create table if not exists members (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  name           text not null,
  role           text,
  department     text,
  experience     text
);

create table if not exists gpx_files (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  filename       text not null,
  file_path      text not null
);

create table if not exists map_files (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  filename       text not null,
  file_path      text not null
);

create table if not exists records (
  id             bigserial primary key,
  expedition_id  bigint not null references expeditions(id) on delete cascade,
  filename       text not null,
  content        text
);

-- ── RLS ─────────────────────────────────────────────────────

alter table expeditions        enable row level security;
alter table expedition_counties enable row level security;
alter table members            enable row level security;
alter table gpx_files          enable row level security;
alter table map_files          enable row level security;
alter table records            enable row level security;

-- anon 只能 SELECT
create policy "anon select" on expeditions         for select to anon using (true);
create policy "anon select" on expedition_counties for select to anon using (true);
create policy "anon select" on members             for select to anon using (true);
create policy "anon select" on gpx_files           for select to anon using (true);
create policy "anon select" on map_files           for select to anon using (true);
create policy "anon select" on records             for select to anon using (true);

-- ── Storage Buckets ──────────────────────────────────────────
-- 在 Supabase Dashboard → Storage 手動建立以下三個 public bucket：
--   gpx      — GPX / KML 軌跡檔
--   maps     — 地圖 PDF
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
  v_offset int := (p_page - 1) * p_page_size;
  v_total  int;
  v_rows   json;
begin
  select count(*) into v_total
  from expeditions e
  where
    (p_q is null or e.name ilike '%' || p_q || '%')
    and (p_county is null or e.county = p_county
         or exists (
           select 1 from expedition_counties ec
           where ec.expedition_id = e.id and ec.county = p_county
         ))
    and (p_counties is null or exists (
           select 1 from expedition_counties ec
           where ec.expedition_id = e.id and ec.county = any(p_counties)
         ))
    and (p_start is null or e.date_start >= p_start)
    and (p_end   is null or e.date_start <= p_end);

  select json_agg(row_to_json(r)) into v_rows
  from (
    select e.*
    from expeditions e
    where
      (p_q is null or e.name ilike '%' || p_q || '%')
      and (p_county is null or e.county = p_county
           or exists (
             select 1 from expedition_counties ec
             where ec.expedition_id = e.id and ec.county = p_county
           ))
      and (p_counties is null or exists (
             select 1 from expedition_counties ec
             where ec.expedition_id = e.id and ec.county = any(p_counties)
           ))
      and (p_start is null or e.date_start >= p_start)
      and (p_end   is null or e.date_start <= p_end)
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
