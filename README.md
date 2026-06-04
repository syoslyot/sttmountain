# sttmountain

成大山協網站，提供資料同步、整理與資料庫維護 repo。這個 repo 是 Supabase schema、migration、RPC、Google Drive 同步腳本與 normalize 流程的 source of truth。

主要使用者介面在 [`sttmountaincrazy`](https://github.com/syoslyot/sttmountaincrazy)。本機開網站時應啟動 `sttmountaincrazy`，網址通常是 [http://localhost:3000](http://localhost:3000)。

## Legacy FastAPI App

`sttmountain` 仍保留最早期的 FastAPI/Jinja 網頁，主要用途是 legacy 檢查與匯入流程輔助，不是目前主要網站。不要把 [http://localhost:8000](http://localhost:8000) 當成正式前端入口。

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

開啟 [http://localhost:8000](http://localhost:8000) 只會看到 legacy FastAPI app。

本機需要 `.env.local`：

```text
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_KEY=...
```

## Main Responsibilities

- 從 Google Drive 同步原始資料。
- 解析直企、地圖、航跡與上繳紀錄。
- 寫入 Supabase DB 與 Storage。
- 維護 DB schema、migration、RPC 與 RLS contract。
- 保留舊版 FastAPI/Jinja SSR 介面與同步工具。

## Useful Commands

```bash
ENV_FILE=.env.local python3 scripts/sync_drive.py
ENV_FILE=.env.local python3 scripts/normalize.py

SUPABASE_URL=https://placeholder.supabase.co \
SUPABASE_ANON_KEY=placeholder \
python3 -c "from app.main import app; print('Import OK')"
```

## Documentation

| 文件 | 內容 |
| --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 開發流程、PR 規則、commit 規範 |
| [docs/architecture.md](docs/architecture.md) | 系統邊界、資料流、目錄分工 |
| [docs/upload-data.md](docs/upload-data.md) | 幹部如何在 Google Drive 上傳資料 |
| [docs/sync-flow.md](docs/sync-flow.md) | `sync_drive.py` 與 `normalize.py` 流程，含 `sync_locked` 跳過規則 |
| [docs/database.md](docs/database.md) | schema、migration、RPC、RLS、dev/prod 套用，含 `sync_locked` 欄位說明 |
| [docs/membership.md](docs/membership.md) | 會員系統、角色定義、`expedition_members` 認領流程 |
| [docs/deployment.md](docs/deployment.md) | GitHub Actions、GHCR、Watchtower、環境變數 |
| [docs/git-flow.md](docs/git-flow.md) | branch、release、hotfix 流程 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 常見問題與排查步驟 |

## Repository Boundary

`sttmountain` 擁有 DB 與資料同步邏輯。`sttmountaincrazy` 只能依賴這裡提供的 RPC contract，不應維護自己的 SQL migration copy。

任何 DB 變更都必須：

1. 新增 `db/migrations/*.sql`。
2. 由 DB 管理者手動套用 dev Supabase。
3. 驗證 sync/normalize 與 RPC。
4. 由 DB 管理者手動套用 prod Supabase。
5. 再讓 frontend 使用新的 contract。
