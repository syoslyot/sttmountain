-- Adds membership system: member_role enum, user_profiles table, and RLS policies.
-- Supabase Auth handles authentication; this migration only manages profile/role storage.
-- Apply to dev first, verify UI login flow, then apply to prod.
--
-- After applying, manually insert the first staff account via Supabase Dashboard
-- or service role, since no staff record exists to satisfy the staff-only INSERT policy.

-- ── 1. Enum ───────────────────────────────────────────────────────────────────

do $$ begin
  create type public.member_role as enum (
    'staff',     -- 資料組管理員
    'member',    -- 山協隊員（通過隊員考試）
    'newcomer',  -- 山協新生
    'partner'    -- 校外夥伴
  );
exception
  when duplicate_object then null;
end $$;

-- ── 2. Table ──────────────────────────────────────────────────────────────────

create table if not exists public.user_profiles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  role         public.member_role not null,
  display_name text,
  created_at   timestamptz not null default now()
);

-- ── 3. RLS ────────────────────────────────────────────────────────────────────

alter table public.user_profiles enable row level security;

-- 每位登入使用者可讀自己的 profile
do $$ begin
  drop policy if exists "select own profile" on public.user_profiles;
end $$;
create policy "select own profile" on public.user_profiles
  for select
  using (auth.uid() = user_id);

-- staff 可讀所有 profile（需要管理清單）
do $$ begin
  drop policy if exists "staff select all" on public.user_profiles;
end $$;
create policy "staff select all" on public.user_profiles
  for select
  using (
    exists (
      select 1 from public.user_profiles up
      where up.user_id = auth.uid()
        and up.role = 'staff'
    )
  );

-- 只有 staff 可新增 profile
do $$ begin
  drop policy if exists "staff insert" on public.user_profiles;
end $$;
create policy "staff insert" on public.user_profiles
  for insert
  with check (
    exists (
      select 1 from public.user_profiles up
      where up.user_id = auth.uid()
        and up.role = 'staff'
    )
  );

-- 只有 staff 可修改 profile（包括指派 role）
do $$ begin
  drop policy if exists "staff update" on public.user_profiles;
end $$;
create policy "staff update" on public.user_profiles
  for update
  using (
    exists (
      select 1 from public.user_profiles up
      where up.user_id = auth.uid()
        and up.role = 'staff'
    )
  );

-- ── 4. Grants ─────────────────────────────────────────────────────────────────

-- anon 不需存取 user_profiles（公開頁面不依賴會員資料）
-- authenticated 透過 RLS 自行讀取
grant select, insert, update on public.user_profiles to authenticated;

-- ── 5. Index ──────────────────────────────────────────────────────────────────

create index if not exists user_profiles_user_id_idx
  on public.user_profiles (user_id);

-- ── 6. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0005_membership')
on conflict (version) do nothing;
