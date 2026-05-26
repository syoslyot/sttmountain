# Contributing to sttmountain

這份文件是 DB/source repo 的協作入口。這個 repo 會影響 Supabase schema、資料同步與前端 contract，因此變更需要比一般前端改動更保守。

## Environment

需求：

- Python 3.12
- pip
- Supabase dev/prod credentials

安裝：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`.env.local` 指向 dev DB，`.env` 指向 prod DB。兩者都不可 commit。

## Workflow

`main` 和 `develop` 都受 GitHub branch ruleset 保護，不可直接 push。

| 任務 | 分支 | 來源 | PR 目標 |
| --- | --- | --- | --- |
| 新功能 | `feature/<scope>-<desc>` | `develop` | `develop` |
| 修 bug | `fix/<scope>-<desc>` | `develop` | `develop` |
| 文件 | `docs/<desc>` | `develop` | `develop` |
| release | `release/v<version>` | `develop` | `main` and `develop` |
| hotfix | `hotfix/<desc>` | `main` | `main` and `develop` |

DB migration 不會自動部署到 Supabase。PR 內必須提醒 DB 管理者手動執行 SQL，先 dev 後 prod。

## Commit Format

使用 Conventional Commits：

```text
<type>(<scope>): <subject>
```

範例：

```text
feat(db): add expedition years rpc
fix(sync): skip deleted drive files
docs(db): clarify migration workflow
```

## Before Opening a PR

最基本驗證：

```bash
SUPABASE_URL=https://placeholder.supabase.co \
SUPABASE_ANON_KEY=placeholder \
python3 -c "from app.main import app; print('Import OK')"
```

若修改同步或 normalize：

```bash
ENV_FILE=.env.local python3 scripts/sync_drive.py
ENV_FILE=.env.local python3 scripts/normalize.py
```

若修改 DB：

- migration 必須可重複執行或清楚說明不能重複的原因。
- `db/schema.sql` 要同步更新。
- `docs/database.md` 要更新 contract。
- PR body 要提醒 DB 管理者手動在 Supabase 執行 SQL。

## Prohibited

- 不 commit `.env`、`.env.local`、service role key 或 Google credentials。
- 不只修 prod DB；dev 和 prod 必須使用同一份 migration。
- 不在 frontend repo 複製 SQL migration。
- 不直接 push 到 `main` 或 `develop`。
