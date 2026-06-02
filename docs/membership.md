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
  display_name text,
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
insert into public.user_profiles (user_id, role, display_name)
values ('<uuid>', 'staff', '資料組');
```

## 認證方式

使用 Supabase 內建 Auth（Email + Password）。`sttmountain` 無需額外設定；
Supabase 本身管理 `auth.users`，本 migration 只新增 `public.user_profiles`。

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
