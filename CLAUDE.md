# Git 工作流程

標準 Git Flow，採用 PR 審核制。

## 觸發語與對應行為

| 使用者說 | 應執行的動作 |
|---------|------------|
| `pr: merge to develop` | push feature/fix 分支 → 開 PR 目標 develop |
| `pull`（develop merge 後） | pull develop |
| `release` | 從 develop 開 `release/*` 分支（不 bump，供測試用） |
| `pr: merge to main`（無先前 `release`） | 開 `release/*` → bump 版本號 → commit → push → 開兩個 PR（release→main、release→develop） |
| `pr: merge to main`（有先前 `release`） | bump 版本號 → commit → push → 開兩個 PR（release→main、release→develop） |
| `pull`（release merge 後） | 確認兩個 PR 狀態，依情況處理（見下） |

## `pull` 後的 release 處理邏輯

| PR 狀態 | 動作 |
|--------|------|
| 兩個都 merged | tag main → pull main + develop → 刪 release 分支 |
| 只有 release→main merged | tag main → pull main → 提醒 release→develop PR 尚未 merge |
| 只有 release→develop merged | 提醒 release→main PR 尚未 merge，不貼 tag，等下次 `pull` |

## Release tag 規則

release→main merge 確認後，在 main 建立 annotated tag 並推上 remote：
```bash
git tag -a v<version> -m "v<version>"
git push origin v<version>
```

## Release 分支上的 bug 修正

測試期間發現問題，直接在 `release/*` 上修並 commit，不需回 develop。兩個 PR 都會帶著修正。

## Local / remote 分開確認

Local merge 和 push to remote 是兩個獨立步驟，有破壞性風險的動作需先確認再執行。

**不可主動執行 merge**，等使用者明確下指令才動作。

---

# DB / Migration 工作流程

`sttmountain` 是 Supabase schema、migration、sync script 的唯一來源。
`sttmountaincrazy` 是前端 consumer，不保存 SQL migration。

## 名詞

Migration 是版本化 SQL 變更檔，用來把 dev/prod DB 從同一個已知狀態升級到下一個狀態。
例如新增欄位、建立 trigger、更新 RPC function、調整 grant，都應該寫成 `db/migrations/*.sql`。

## 檔案位置

| 檔案 | 用途 |
|---|---|
| `db/schema.sql` | 目前完整 schema，給新 DB 建置用 |
| `db/migrations/*.sql` | 既有 DB 的版本化升級 SQL |
| `docs/database.md` | DB 流程、切換 dev/prod、reset/resync 指令 |
| `schema_migrations` | DB 內記錄已套用 migration 的 table |

## dev / prod 切換

不要再用改名 `.env.local` 的方式切 DB。所有腳本都要明確指定 env：

| 目標 | 指令形式 |
|---|---|
| dev DB | `ENV_FILE=.env.local python3 scripts/sync_drive.py` |
| prod DB | `ENV_FILE=.env python3 scripts/sync_drive.py` |

normalize 同理：

```bash
ENV_FILE=.env.local python3 scripts/normalize.py
ENV_FILE=.env python3 scripts/normalize.py
```

reset 工具也必須明確指定：

```bash
python3 scripts/cleanup_dev_test.py --target dev --env-file .env.local --dry-run --local-cache
python3 scripts/cleanup_dev_test.py --target prod --env-file .env --dry-run
```

真的刪除必須加 `--yes`。

## Migration 套用順序

1. 在 `db/migrations/` 新增下一個編號的 SQL，例如 `0003_add_xxx.sql`。
2. SQL 盡量寫成 idempotent：`if not exists`、`create or replace function`。
3. 最後寫入 `schema_migrations`。
4. 先在 dev Supabase SQL Editor 執行。
5. 用 dev env 跑 sync/normalize 或前端驗證。
6. 再把同一份 migration 套到 prod。
7. 用 prod env 跑驗證。
8. migration、文件、相關程式碼都要 commit 進 PR。

不要只在 prod 手動補 SQL。若緊急補了，之後也要補成 migration，並套回 dev。
