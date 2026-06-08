-- =============================================================================
-- 0040_prod_catchup.sql
-- 將 prod DB 從 0004 狀態一次補齊到 0039 的最終正確狀態。
-- 非冪等操作（RENAME 欄位/表）均加上 IF 防護。
-- 中間被取代的函式版本直接跳過，只套用最終版。
-- =============================================================================

-- ── 0005: member_role enum + user_profiles ────────────────────────────────────

do $$ begin
  create type public.member_role as enum (
    'staff', 'member', 'newcomer', 'partner'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.user_profiles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  role         public.member_role not null,
  display_name text,
  created_at   timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

drop policy if exists "select own profile" on public.user_profiles;
create policy "select own profile" on public.user_profiles
  for select using (auth.uid() = user_id);

drop policy if exists "staff select all" on public.user_profiles;
drop policy if exists "staff insert" on public.user_profiles;
drop policy if exists "staff update" on public.user_profiles;
-- 先建暫用版（my_role() 尚未存在），0009 段會重建正確版
create policy "staff select all" on public.user_profiles
  for select using (
    exists (select 1 from public.user_profiles up where up.user_id = auth.uid() and up.role = 'staff')
  );
create policy "staff insert" on public.user_profiles
  for insert with check (
    exists (select 1 from public.user_profiles up where up.user_id = auth.uid() and up.role = 'staff')
  );
create policy "staff update" on public.user_profiles
  for update using (
    exists (select 1 from public.user_profiles up where up.user_id = auth.uid() and up.role = 'staff')
  );

grant select, insert, update on public.user_profiles to authenticated;

create index if not exists user_profiles_user_id_idx on public.user_profiles (user_id);

insert into public.schema_migrations (version) values ('0005_membership') on conflict (version) do nothing;

-- ── 0007: nickname ────────────────────────────────────────────────────────────

alter table public.user_profiles add column if not exists nickname text;

insert into public.schema_migrations (version) values ('0007_user_profile_nickname') on conflict (version) do nothing;

-- ── 0008: rename display_name → name (guarded) ───────────────────────────────

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'display_name'
  ) then
    alter table public.user_profiles rename column display_name to name;
  end if;
end $$;

insert into public.schema_migrations (version) values ('0008_rename_display_name_to_name') on conflict (version) do nothing;

-- ── 0009: my_role() + fix RLS recursion ──────────────────────────────────────

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role::text from public.user_profiles where user_id = auth.uid()
$$;

drop policy if exists "staff select all" on public.user_profiles;
create policy "staff select all" on public.user_profiles for select using (public.my_role() = 'staff');

drop policy if exists "staff insert" on public.user_profiles;
create policy "staff insert" on public.user_profiles for insert with check (public.my_role() = 'staff');

drop policy if exists "staff update" on public.user_profiles;
create policy "staff update" on public.user_profiles for update using (public.my_role() = 'staff');

insert into public.schema_migrations (version) values ('0009_fix_rls_recursion') on conflict (version) do nothing;

-- ── 0010: contact + joined_at ─────────────────────────────────────────────────

alter table public.user_profiles
  add column if not exists contact   text,
  add column if not exists joined_at date;

drop policy if exists "user update own profile" on public.user_profiles;
create policy "user update own profile" on public.user_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into public.schema_migrations (version) values ('0010_user_profile_contact_joined') on conflict (version) do nothing;

-- ── 0011: expedition_members ──────────────────────────────────────────────────

create table if not exists public.expedition_members (
  id             bigserial primary key,
  expedition_id  bigint not null references public.expeditions(id) on delete cascade,
  user_id        uuid   not null references auth.users(id) on delete cascade,
  role           text   not null default 'member',
  status         text   not null default 'pending',
  created_at     timestamptz not null default now()
);

alter table public.expedition_members enable row level security;

drop policy if exists "select own memberships" on public.expedition_members;
create policy "select own memberships" on public.expedition_members for select using (auth.uid() = user_id);

drop policy if exists "staff select all memberships" on public.expedition_members;
create policy "staff select all memberships" on public.expedition_members for select using (public.my_role() = 'staff');

drop policy if exists "user insert own membership" on public.expedition_members;
create policy "user insert own membership" on public.expedition_members
  for insert with check (auth.uid() = user_id);

drop policy if exists "staff update membership" on public.expedition_members;
create policy "staff update membership" on public.expedition_members for update using (public.my_role() = 'staff');

drop policy if exists "user delete own pending membership" on public.expedition_members;
create policy "user delete own pending membership" on public.expedition_members
  for delete using (auth.uid() = user_id and status = 'pending');

grant select, insert, delete on public.expedition_members to authenticated;
grant update on public.expedition_members to authenticated;

create index if not exists expedition_members_user_id_idx on public.expedition_members (user_id);
create index if not exists expedition_members_expedition_id_idx on public.expedition_members (expedition_id);

insert into public.schema_migrations (version) values ('0011_expedition_members') on conflict (version) do nothing;

-- ── 0012 / 0013 / 0014: handle_new_user (最終版，含 avatar) ──────────────────

alter table public.user_profiles add column if not exists avatar_url text;

alter table public.user_profiles alter column joined_at set default current_date;

update public.user_profiles set joined_at = created_at::date where joined_at is null;

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;

drop policy if exists "avatars public read"   on storage.objects;
drop policy if exists "avatars user insert"   on storage.objects;
drop policy if exists "avatars user update"   on storage.objects;
drop policy if exists "avatars user delete"   on storage.objects;
create policy "avatars public read"   on storage.objects for select using (bucket_id = 'avatars');
create policy "avatars user insert"   on storage.objects for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatars user update"   on storage.objects for update using  (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatars user delete"   on storage.objects for delete using  (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop trigger if exists on_auth_user_created on auth.users;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  _name       text;
  _avatar_url text;
begin
  _name := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
  _avatar_url := coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture');
  insert into public.user_profiles (user_id, role, name, avatar_url, joined_at)
  values (new.id, 'newcomer', _name, _avatar_url, current_date)
  on conflict (user_id) do update set
    name       = coalesce(public.user_profiles.name, excluded.name),
    avatar_url = coalesce(public.user_profiles.avatar_url, excluded.avatar_url);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

insert into public.schema_migrations (version) values ('0006_auth_trigger')        on conflict (version) do nothing;
insert into public.schema_migrations (version) values ('0012_fix_trigger_name_column') on conflict (version) do nothing;
insert into public.schema_migrations (version) values ('0013_joined_at_default')    on conflict (version) do nothing;
insert into public.schema_migrations (version) values ('0014_avatar')               on conflict (version) do nothing;

-- ── 0015: secure profile update ───────────────────────────────────────────────

drop policy if exists "user update own profile" on public.user_profiles;

create or replace function public.update_own_profile(p_name text, p_nickname text, p_contact text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.user_profiles set name = p_name, nickname = p_nickname, contact = p_contact where user_id = auth.uid();
end;
$$;
grant execute on function public.update_own_profile(text, text, text) to authenticated;

create or replace function public.update_own_avatar(p_avatar_url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.user_profiles set avatar_url = p_avatar_url where user_id = auth.uid();
end;
$$;
grant execute on function public.update_own_avatar(text) to authenticated;

insert into public.schema_migrations (version) values ('0015_secure_profile_update') on conflict (version) do nothing;

-- ── 0016: rename expeditions.leader → leader_display (guarded) ───────────────

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'expeditions' and column_name = 'leader'
  ) then
    alter table public.expeditions rename column leader to leader_display;
  end if;
end $$;

insert into public.schema_migrations (version) values ('0016_rename_leader_display') on conflict (version) do nothing;

-- ── 0017: list_unclaimed_expeditions (intermediate, superseded by 0020) ──────

insert into public.schema_migrations (version) values ('0017_unclaimed_expeditions_rpc') on conflict (version) do nothing;

-- ── 0018: evidence column ─────────────────────────────────────────────────────

alter table public.expedition_members add column if not exists evidence text;

insert into public.schema_migrations (version) values ('0018_expedition_claim_rpc') on conflict (version) do nothing;

-- ── 0019: rename records → record_files (guarded) ────────────────────────────

do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'records'
  ) then
    alter table public.records rename to record_files;
  end if;
end $$;

insert into public.schema_migrations (version) values ('0019_rename_records_to_record_files') on conflict (version) do nothing;

-- ── 0020: list_unclaimed_expeditions (最終版，含 claim_status) ────────────────

create or replace function public.list_unclaimed_expeditions(p_q text default '', p_grade text default '')
returns jsonb language sql stable security definer set search_path = public as $$
select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', e.id, 'name', e.name, 'grade', e.grade,
      'date_start', e.date_start, 'date_end', e.date_end,
      'leader_display', e.leader_display,
      'region_entry_county', e.region_entry_county, 'region_entry_town', e.region_entry_town,
      'region_exit_county', e.region_exit_county, 'region_exit_town', e.region_exit_town,
      'claim_status', case
        when exists (select 1 from public.expedition_members em where em.expedition_id = e.id and em.role = 'leader' and em.status = 'pending') then 'pending'
        else 'unclaimed'
      end
    )
    order by e.date_start desc
  ),
  '[]'::jsonb
)
from public.expeditions e
where e.is_public is true
  and not exists (select 1 from public.expedition_members em where em.expedition_id = e.id and em.role = 'leader' and em.status = 'approved')
  and (coalesce(p_q, '') = '' or e.name ilike '%' || p_q || '%' or e.leader_display ilike '%' || p_q || '%' or e.region_entry_county ilike '%' || p_q || '%' or e.region_entry_town ilike '%' || p_q || '%')
  and (coalesce(p_grade, '') = '' or e.grade = upper(p_grade));
$$;
grant execute on function public.list_unclaimed_expeditions(text, text) to authenticated;

insert into public.schema_migrations (version) values ('0020_claim_status_in_unclaimed_rpc') on conflict (version) do nothing;

-- ── 0021 / 0022 / 0028 / 0039: review_expedition_claim + list_pending_claims (最終版) ──

-- list_pending_claims 最終版（0039）
create or replace function public.list_pending_claims()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or public.my_role() <> 'staff' then return '[]'::jsonb; end if;
  return coalesce(
    (select jsonb_agg(jsonb_build_object(
        'id', em.id, 'expedition_id', em.expedition_id, 'expedition_name', e.name,
        'date_start', e.date_start, 'grade', e.grade, 'evidence', em.evidence,
        'claimant_name', coalesce(up.nickname, up.name, ''), 'created_at', em.created_at
      ) order by em.created_at asc)
     from public.expedition_members em
     join public.expeditions e on e.id = em.expedition_id
     left join public.user_profiles up on up.user_id = em.user_id
     where em.role = 'leader' and em.status = 'pending'),
    '[]'::jsonb
  );
end;
$$;
grant execute on function public.list_pending_claims() to authenticated;

-- review_expedition_claim 最終版（0039）
create or replace function public.review_expedition_claim(p_claim_id bigint, p_action text)
returns void language plpgsql security definer set search_path = public as $$
declare v_expedition_id bigint; v_leader_name text;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if public.my_role() <> 'staff' then raise exception 'insufficient privileges'; end if;
  if p_action not in ('approved', 'rejected') then raise exception 'invalid action: %', p_action; end if;
  select expedition_id into v_expedition_id from public.expedition_members
    where id = p_claim_id and role = 'leader' and status = 'pending';
  if not found then raise exception 'claim not found or already processed'; end if;
  update public.expedition_members set status = p_action where id = p_claim_id;
  if p_action = 'approved' then
    select coalesce(up.name, up.nickname, split_part(au.email, '@', 1)) into v_leader_name
    from public.expedition_members em
    join public.user_profiles up on up.user_id = em.user_id
    join auth.users au on au.id = em.user_id
    where em.id = p_claim_id;
    update public.expeditions set leader_display = v_leader_name where id = v_expedition_id;
  end if;
end;
$$;
grant execute on function public.review_expedition_claim(bigint, text) to authenticated;

insert into public.schema_migrations (version) values ('0021_claim_review_rpcs')          on conflict (version) do nothing;

-- ── 0022: list_expeditions (最終版，含 approved leader 過濾) ──────────────────

drop function if exists public.list_expeditions(text,text,text[],date,date,integer,integer,text,text);

create or replace function public.list_expeditions(
  p_q text default '', p_county text default '', p_counties text[] default '{}'::text[],
  p_start date default null, p_end date default null,
  p_page integer default 1, p_page_size integer default 20,
  p_grade text default '', p_sort text default 'latest'
)
returns jsonb language sql stable security definer set search_path = public as $$
with filtered as (
  select e.* from public.expeditions e
  where e.is_public is true
    and exists (select 1 from public.expedition_members em where em.expedition_id = e.id and em.role = 'leader' and em.status = 'approved')
    and (coalesce(p_q, '') = '' or e.name ilike '%' || p_q || '%' or e.leader_display ilike '%' || p_q || '%')
    and (coalesce(p_grade, '') = '' or e.grade = upper(p_grade))
    and (p_start is null or coalesce(e.date_end, e.date_start) >= p_start)
    and (p_end is null or e.date_start <= p_end)
    and (coalesce(p_county, '') = '' or exists (select 1 from public.expedition_counties ec where ec.expedition_id = e.id and ec.county = p_county))
    and (coalesce(array_length(p_counties, 1), 0) = 0 or exists (select 1 from public.expedition_counties ec where ec.expedition_id = e.id and ec.county = any(p_counties)))
),
page_rows as (
  select * from filtered
  order by
    case when p_sort = 'oldest' then coalesce(date_end, date_start) end asc nulls last,
    case when p_sort <> 'oldest' then coalesce(date_end, date_start) end desc nulls last,
    id desc
  limit greatest(p_page_size, 1)
  offset greatest(p_page - 1, 0) * greatest(p_page_size, 1)
),
counts as (
  select p.id,
    (select count(*) from public.gpx_files    gf where gf.expedition_id = p.id)::int as gpx_count,
    (select count(*) from public.map_files    mf where mf.expedition_id = p.id)::int as map_count,
    (select count(*) from public.record_files rf where rf.expedition_id = p.id)::int as rec_count
  from page_rows p
)
select jsonb_build_object(
  'expeditions', coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('gpx_count', c.gpx_count, 'map_count', c.map_count, 'rec_count', c.rec_count)
    order by case when p_sort = 'oldest' then coalesce(p.date_end, p.date_start) end asc nulls last,
             case when p_sort <> 'oldest' then coalesce(p.date_end, p.date_start) end desc nulls last, p.id desc), '[]'::jsonb),
  'total', (select count(*) from filtered),
  'page', greatest(p_page, 1),
  'pageSize', greatest(p_page_size, 1)
)
from page_rows p left join counts c on c.id = p.id;
$$;

insert into public.schema_migrations (version) values ('0022_list_expeditions_require_approved_leader') on conflict (version) do nothing;

-- ── 0023: authenticated select public expeditions ─────────────────────────────

drop policy if exists "authenticated select public expeditions" on public.expeditions;
create policy "authenticated select public expeditions" on public.expeditions
  for select to authenticated using (is_public is true);

insert into public.schema_migrations (version) values ('0023_expeditions_authenticated_select') on conflict (version) do nothing;

-- ── 0024: transport, keeper, participants ─────────────────────────────────────

alter table public.expeditions
  add column if not exists transport    text,
  add column if not exists keeper       text,
  add column if not exists participants integer;

insert into public.schema_migrations (version) values ('0024_expedition_edit_fields') on conflict (version) do nothing;

-- ── 0025 / 0026 / 0027 / 0039: update_expedition (最終版) ────────────────────

alter table public.expeditions add column if not exists sync_locked bool not null default false;

drop function if exists public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer);

create or replace function public.update_expedition(
  p_id integer, p_name text, p_grade text, p_date_start date,
  p_date_end date default null, p_region_entry_county text default null, p_region_entry_town text default null,
  p_region_exit_county text default null, p_region_exit_town text default null,
  p_leader_display text default null, p_transport text default null,
  p_keeper text default null, p_participants integer default null, p_sync_locked bool default true
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if not exists (select 1 from public.expedition_members em where em.expedition_id = p_id and em.user_id = auth.uid() and em.role = 'leader' and em.status = 'approved')
    and public.my_role() <> 'staff' then
    raise exception 'insufficient privileges';
  end if;
  if not p_sync_locked and public.my_role() <> 'staff' then raise exception 'only staff may unlock sync'; end if;
  update public.expeditions set
    name = p_name, grade = p_grade, date_start = p_date_start, date_end = p_date_end,
    region_entry_county = p_region_entry_county, region_entry_town = p_region_entry_town,
    region_exit_county = p_region_exit_county, region_exit_town = p_region_exit_town,
    leader_display = p_leader_display, transport = p_transport, keeper = p_keeper,
    participants = p_participants, sync_locked = p_sync_locked
  where id = p_id;
end;
$$;
grant execute on function public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer,bool) to authenticated;

insert into public.schema_migrations (version) values ('0025_update_expedition_rpc')      on conflict (version) do nothing;
insert into public.schema_migrations (version) values ('0026_sync_locked_field')           on conflict (version) do nothing;
insert into public.schema_migrations (version) values ('0027_update_expedition_sync_locked') on conflict (version) do nothing;

-- ── 0028: review_expedition_claim (已在 0021 段套用最終版) ───────────────────

insert into public.schema_migrations (version) values ('0028_review_claim_update_leader') on conflict (version) do nothing;

-- ── 0029: list_member_profiles ────────────────────────────────────────────────

create or replace function public.list_member_profiles()
returns jsonb language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then '[]'::jsonb
    when public.my_role() = 'staff' or exists (select 1 from public.expedition_members where user_id = auth.uid() and role = 'leader' and status = 'approved')
    then (select coalesce(jsonb_agg(jsonb_build_object('user_id', user_id, 'name', name, 'nickname', nickname) order by name nulls last), '[]'::jsonb) from public.user_profiles)
    else '[]'::jsonb
  end
$$;
grant execute on function public.list_member_profiles() to authenticated;

insert into public.schema_migrations (version) values ('0029_list_member_profiles') on conflict (version) do nothing;

-- ── 0030: expedition_role, can_edit ───────────────────────────────────────────

alter table public.expedition_members
  add column if not exists expedition_role text,
  add column if not exists can_edit boolean not null default false;

-- ── 0031: journal_blocks ──────────────────────────────────────────────────────

alter table public.expeditions add column if not exists journal_blocks jsonb not null default '[]'::jsonb;

-- ── 0032 / 0033 / 0034: get_expedition_members, sync_expedition_members, save_expedition_journal (最終版) ──

-- get_expedition_members 最終版（0034）
create or replace function get_expedition_members(p_expedition_id bigint)
returns table (user_id uuid, role text, expedition_role text, can_edit boolean, name text, nickname text)
language sql stable security definer set search_path = public as $$
  select em.user_id, em.role, em.expedition_role, em.can_edit, up.name, up.nickname
  from expedition_members em
  left join user_profiles up on up.user_id = em.user_id
  where em.expedition_id = p_expedition_id and em.status = 'approved'
  order by
    case em.role when 'leader' then 0 else 1 end,
    case em.expedition_role when '嚮導' then 0 when '隊員' then 1 when '新生' then 2 else 3 end,
    em.created_at;
$$;
grant execute on function get_expedition_members(bigint) to authenticated, anon;

-- sync_expedition_members 最終版（0033）
create or replace function sync_expedition_members(p_expedition_id bigint, p_members jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if not (exists (select 1 from expedition_members where expedition_id = p_expedition_id and user_id = auth.uid() and role = 'leader' and status = 'approved') or public.my_role() = 'staff') then
    raise exception 'unauthorized';
  end if;
  delete from expedition_members where expedition_id = p_expedition_id and role = 'member';
  insert into expedition_members (expedition_id, user_id, role, expedition_role, can_edit, status)
  select p_expedition_id, (m->>'user_id')::uuid, 'member', m->>'expedition_role', (m->>'can_edit')::boolean, 'approved'
  from jsonb_array_elements(p_members) m where m->>'user_id' is not null;
end;
$$;
grant execute on function sync_expedition_members(bigint, jsonb) to authenticated;

-- save_expedition_journal 最終版（0033）
create or replace function save_expedition_journal(p_expedition_id bigint, p_blocks jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  if not (
    exists (select 1 from expedition_members where expedition_id = p_expedition_id and user_id = auth.uid() and role = 'leader' and status = 'approved') or
    exists (select 1 from expedition_members where expedition_id = p_expedition_id and user_id = auth.uid() and can_edit = true and status = 'approved') or
    public.my_role() = 'staff'
  ) then raise exception 'unauthorized'; end if;
  update expeditions set journal_blocks = p_blocks where id = p_expedition_id;
end;
$$;
grant execute on function save_expedition_journal(bigint, jsonb) to authenticated;

-- ── 0035: soft delete columns ─────────────────────────────────────────────────

alter table gpx_files    add column if not exists deleted_at timestamptz default null, add column if not exists deleted_by uuid default null;
alter table map_files    add column if not exists deleted_at timestamptz default null, add column if not exists deleted_by uuid default null;
alter table record_files add column if not exists deleted_at timestamptz default null, add column if not exists deleted_by uuid default null;

create index if not exists idx_gpx_files_deleted_at    on gpx_files    (deleted_at) where deleted_at is not null;
create index if not exists idx_map_files_deleted_at    on map_files    (deleted_at) where deleted_at is not null;
create index if not exists idx_record_files_deleted_at on record_files (deleted_at) where deleted_at is not null;

-- ── 0036: unique constraint on expedition_members ────────────────────────────

-- 先清重複列（idempotent：有重複才刪）
delete from expedition_members
where id not in (
  select distinct on (expedition_id, user_id) id
  from expedition_members
  order by expedition_id, user_id,
    case role when 'leader' then 0 else 1 end,
    created_at asc
);

-- 加 UNIQUE constraint（加防護避免已存在時噴錯）
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_schema = 'public' and table_name = 'expedition_members'
      and constraint_name = 'expedition_members_expedition_user_unique'
  ) then
    alter table expedition_members add constraint expedition_members_expedition_user_unique unique (expedition_id, user_id);
  end if;
end $$;

-- ── 0037 / 0039: submit_expedition_claim (最終版，含 NULL uid guard) ──────────

create or replace function public.submit_expedition_claim(p_expedition_id integer, p_evidence text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  insert into public.expedition_members (expedition_id, user_id, role, status, evidence)
  values (p_expedition_id, auth.uid(), 'leader', 'pending', p_evidence)
  on conflict (expedition_id, user_id) do update set
    status   = case when expedition_members.status = 'rejected' then 'pending' else expedition_members.status end,
    evidence = case when expedition_members.status = 'rejected' then excluded.evidence else expedition_members.evidence end
  where expedition_members.status = 'rejected';
end;
$$;
grant execute on function public.submit_expedition_claim(integer, text) to authenticated;

insert into public.schema_migrations (version) values ('0037_fix_claim_upsert') on conflict (version) do nothing;

-- ── 0038: tighten expedition_members INSERT RLS ───────────────────────────────

drop policy if exists "user insert own membership" on public.expedition_members;
create policy "user insert own membership" on public.expedition_members
  for insert with check (
    auth.uid() = user_id and role = 'leader' and status = 'pending' and can_edit = false
  );

insert into public.schema_migrations (version) values ('0038_fix_member_insert_rls') on conflict (version) do nothing;

-- ── 0039: 已在各函式最終版套用，補記錄 ────────────────────────────────────────

insert into public.schema_migrations (version) values ('0039_fix_null_uid_remaining_rpcs') on conflict (version) do nothing;

-- ── 0040: 本 catchup 本身 ─────────────────────────────────────────────────────

insert into public.schema_migrations (version) values ('0040_prod_catchup') on conflict (version) do nothing;
