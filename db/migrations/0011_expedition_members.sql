-- Creates expedition_members table: links users to expeditions with a role and approval status.
-- Used for 帶隊/紀錄 counts on the member page, and for claim/edit access control.

-- ── 1. Table ──────────────────────────────────────────────────────────────────

create table if not exists public.expedition_members (
  id             bigserial primary key,
  expedition_id  bigint not null references public.expeditions(id) on delete cascade,
  user_id        uuid   not null references auth.users(id) on delete cascade,
  role           text   not null default 'member',  -- 'leader' | 'member'
  status         text   not null default 'pending', -- 'pending' | 'approved' | 'rejected'
  created_at     timestamptz not null default now(),
  unique (expedition_id, user_id)
);

-- ── 2. RLS ────────────────────────────────────────────────────────────────────

alter table public.expedition_members enable row level security;

-- 每位登入使用者可讀自己的 expedition_members 紀錄
create policy "select own memberships" on public.expedition_members
  for select
  using (auth.uid() = user_id);

-- staff 可讀所有
create policy "staff select all memberships" on public.expedition_members
  for select
  using (public.my_role() = 'staff');

-- 登入使用者可建立自己的 membership（認領）
create policy "user insert own membership" on public.expedition_members
  for insert
  with check (auth.uid() = user_id);

-- 只有 staff 可修改 status（審核）
create policy "staff update membership" on public.expedition_members
  for update
  using (public.my_role() = 'staff');

-- 使用者可刪除自己的 pending membership（撤回認領）
create policy "user delete own pending membership" on public.expedition_members
  for delete
  using (auth.uid() = user_id and status = 'pending');

-- ── 3. Grants ─────────────────────────────────────────────────────────────────

grant select, insert, delete on public.expedition_members to authenticated;
grant update on public.expedition_members to authenticated;

-- ── 4. Indexes ────────────────────────────────────────────────────────────────

create index if not exists expedition_members_user_id_idx
  on public.expedition_members (user_id);

create index if not exists expedition_members_expedition_id_idx
  on public.expedition_members (expedition_id);

-- ── 5. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0011_expedition_members')
on conflict (version) do nothing;
