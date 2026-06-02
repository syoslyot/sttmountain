# Membership System

`sttmountain` 負責 DB schema 與 migration。前端邏輯（React context、登入 UI）由 `sttmountaincrazy` 負責；前端 contract 說明見 `sttmountaincrazy/docs/membership.md`。

## Migration

`db/migrations/0005_membership.sql`

套用順序：dev → 驗證 → prod（同 `docs/database.md` 標準流程）。

## 角色定義

| Role value | 中文名稱 | 說明 |
| --- | --- | --- |
| `staff` | 資料組管理員 | 可讀寫所有 user_profiles，負責指派角色 |
| `member` | 山協隊員 | 通過隊員考試的社員 |
| `newcomer` | 山協新生 | 尚未通過隊員考試的社員 |
| `partner` | 校外夥伴 | 非成大山協社員的外部合作者 |

> 角色名稱刻意避開 `admin`，以免與 Supabase service role 或其他系統的 admin 概念混淆。

## user_profiles 表

```sql
create table public.user_profiles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  role         public.member_role not null,
  name text,
  created_at   timestamptz not null default now()
);
```

### RLS 政策摘要

| 政策 | 操作 | 說明 |
| --- | --- | --- |
| `select own profile` | SELECT | 登入使用者讀自己的 profile |
| `staff select all` | SELECT | staff 讀所有 profile |
| `staff insert` | INSERT | 只有 staff 可新增 |
| `staff update` | UPDATE | 只有 staff 可修改 role |

### 初始化第一個 staff 帳號

第一個 staff 需由 Supabase Dashboard（Table Editor）或 service role 手動插入，
因為尚無任何 staff 紀錄可觸發 INSERT policy。

```sql
-- 先在 Auth > Users 建立帳號，取得 user_id，再執行：
insert into public.user_profiles (user_id, role, name)
values ('<uuid>', 'staff', '資料組');
```

## 認證方式

支援三種登入方式（均由 Supabase Auth 管理）：

| 方式 | 說明 |
| --- | --- |
| Email + Password | 傳統帳號密碼登入 |
| Google OAuth | 以 Google 帳號登入 |
| Facebook OAuth | 以 Facebook 帳號登入 |

OAuth 在 Supabase Dashboard > Authentication > Providers 啟用，不需額外 SQL。
首次登入時，`auth.users` 中會自動建立一筆記錄；`0006_auth_trigger.sql` 中的 trigger 再自動建立對應的 `user_profiles`（role 預設為 `newcomer`）。

### `user_id` 說明

`user_profiles.user_id` 是 Supabase Auth 在 `auth.users` 為每個帳號指派的 UUID。
同一個人無論用 Email 或 OAuth 登入，只要是同一個 provider identity，就共用同一個 `user_id`。
前端可透過 `auth.uid()` 取得當前登入者的 `user_id`。

## Auto-create trigger（0006_auth_trigger.sql）

任何新帳號（Email 或 OAuth）在 `auth.users` 建立時，trigger 自動在 `user_profiles` 插入一筆 `newcomer` 的 profile。
`name` 優先取 OAuth 帶回的 `full_name` / `name`，否則用 Email 前綴。
若同一 `user_id` 已存在（重複執行 migration 或少見重建情境），`ON CONFLICT DO NOTHING` 保持冪等。

Staff 之後可透過 `UPDATE` 政策修改 role。

## 與現有 expedition 資料的關係

`user_profiles` 和現有的 `expeditions.leader`（字串欄位）無直接關聯。
「領隊」欄位記錄的是出隊紀錄的文字資訊，與會員系統的 `role` 無關。
未來認領隊伍時（`expedition_claims`，尚未實作），才會建立 user_id → expedition_id 的連結。

## 環境變數（sttmountaincrazy 側需補）

前端需要 browser-exposed 版本的 Supabase URL 和 anon key：

```env
NEXT_PUBLIC_SUPABASE_URL=<同 SUPABASE_URL>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<同 SUPABASE_ANON_KEY>
```

Render 部署時也需補上這兩個變數。
