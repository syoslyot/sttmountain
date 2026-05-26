# sttmount — 成大山協小甜甜

---

## 技術棧

| 層級 | 選擇 |
|---|---|
| Backend | Python 3.12 + FastAPI + Jinja2（SSR） |
| Database | Supabase（PostgreSQL + Storage） |
| Frontend | HTML + Tailwind CSS（CDN）+ Vanilla JS |
| 地圖 | Leaflet.js + leaflet-omnivore（GPX/KML）|
| 地圖底圖 | NLSC 通用電子地圖 / OpenTopoMap / OSM / NLSC 正射影像 + 等高線 overlay |
| 高度剖面 | @raruto/leaflet-elevation |
| 部署 | Docker Compose + Nginx，跑在學校固定 IP 的 Windows 筆電 |
| 自動更新 | Watchtower（監聽 GHCR，自動 pull 新 image） |
| CI/CD | GitHub Actions（每日同步 Drive → normalize → push Supabase） |

---

## 幹部：如何上傳資料

在 Google Drive 的「所有出隊資料夾」內，按出隊類型建立資料夾：

### 一般出隊（solo）

```
所有出隊資料夾/
  {出隊名稱}/
    {日期}_{名稱}_直企.xlsx    ← 直企（必填，檔名須含「直企」）
    地圖/                      ← pdf、docx、jpg、png、jpeg
    航跡/                      ← gpx、kml
    上繳紀錄/                  ← txt、md、docx、pdf、Google 文件
```

### 大眾化活動（多隊）

```
所有出隊資料夾/
  {活動名稱}/
    {隊伍名稱A}/
      {日期}_{名稱}_直企.xlsx
      地圖/
      航跡/
      上繳紀錄/
    {隊伍名稱B}/
      ...
```

**注意：**
- 子資料夾名稱需精確符合：`地圖`、`航跡`、`上繳紀錄`
- 只同步 **2026-05-01 以後**建立的資料夾
- 每日 CI 自動同步；也可至 GitHub Actions 手動觸發

---

## 完整同步流程

### Step 1：CI 環境準備

GitHub 開一台全新 Ubuntu 機器，安裝：
- Python 套件（`requirements.txt`）
- LibreOffice headless（xlsx → PDF 截圖）
- `fonts-noto-cjk`（中文字型，避免截圖亂碼）

---

### Step 2：`scripts/sync_drive.py`

用 Service Account JSON 向 Google Drive 認證，掃描根目錄下所有子資料夾。

**資料夾分類邏輯：**
- 根目錄直接有 `*直企.xlsx` → **solo**
- 根目錄內有子資料夾，各自含 `*直企.xlsx` → **大眾化（group）**
- 其他 → 跳過

**同步策略：**
- 只處理 `createdTime >= 2026-05-01` 的資料夾
- 從 Supabase `sync_state` 讀取 `last_synced_at`；`createdTime > last_synced_at` 的視為新資料夾，全量下載；舊資料夾只下載 `modifiedTime` 有更新的檔案
- 下載結果寫入 `data/raw/sync_meta.json`，作為 normalize.py 的輸入

---

### Step 3：`scripts/normalize.py`

讀取 `sync_meta.json`，對每筆出隊跑完整流程：

**讀取直企 P1 sheet**

| 儲存格 | 內容 |
|---|---|
| `D2` | 出隊名稱 |
| `D3` | 出發日（民國年，轉成 `YYYY-MM-DD`） |
| `D4` | 回程日 |
| `F3` | 入山地點（抓縣市 + 鄉鎮） |
| `F4` | 出山地點 |
| `C17` | 領隊姓名 |

**截圖預覽（僅新資料夾）**
- P1：自動偵測內容範圍截圖
- P2：固定範圍 `B2:O12` 截圖
- 兩張垂直合併，縮放至寬 1240px，上傳 Supabase Storage `previews` bucket

**Upsert 策略（以 `drive_folder_id` 為唯一鍵）**
- 大眾化活動：先 upsert `expedition_groups`，各隊共享同一 `group_id`
- solo：自動建立獨立 group（group = 出隊本身）
- `gpx_files`、`map_files`、`records`：以 `drive_file_id` 為唯一鍵，upsert

---

跑完後 CI 機器銷毀，網站下次請求時直接從 Supabase 讀取更新後的資料。

---

## 系統連線關係

```
                        ┌─────────────────┐
                        │   Google Drive  │
                        └────────┬────────┘
                                 │ 下載原始檔、讀取 metadata
                                 ▼
                    ┌────────────────────────┐
                    │      本機後端          │
                    │   (sttmountain         │
                    │    sync script)        │
                    │                        │
                    │  ENV_FILE=.env.local   │
                    │    → dev DB / Storage  │
                    │  ENV_FILE=.env         │
                    │    → prod DB / Storage │
                    └────────┬───────────────┘
                             │ upsert records / upload files
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
  ┌───────────────────┐         ┌───────────────────┐
  │     dev DB        │         │     prod DB        │
  │  (Supabase)       │         │  (Supabase)        │
  │  dev Storage      │         │  prod Storage      │
  └─────────┬─────────┘         └─────────┬──────────┘
            │ 讀 DB / Storage              │ 讀 DB / Storage
            ▼                             ▼
  ┌───────────────────┐         ┌───────────────────┐
  │    本機前端       │         │   Render 部署      │
  │  (sttmountaincrazy│         │  (sttmountaincrazy │
  │   .env.local)     │         │   Render env vars) │
  └─────────┬─────────┘         └─────────┬──────────┘
            │                             │
            ▼                             ▼
     localhost:3000               線上的網頁
```

| 情境 | 本機後端指向 | 本機前端指向 |
|---|---|---|
| 日常開發 | dev DB（`ENV_FILE=.env.local`） | dev DB（前端 repo 的 `.env.local`） |
| 對 prod 操作 | prod DB（`ENV_FILE=.env`） | prod DB（前端 repo 的 `.env` 或部署 env） |
| Render / 線上 | — | 永遠是 prod DB（Render env vars） |

---

## 本機開發

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 填入 Supabase 連線資訊（不可 commit）
cp .env.example .env.local
# 編輯 .env.local：SUPABASE_URL、SUPABASE_ANON_KEY、SUPABASE_SERVICE_KEY

uvicorn app.main:app --reload
# 開啟 http://localhost:8000
```

**環境變數說明：**

| 從哪裡 | 連到哪裡 | 變數 | 存放位置 |
|---|---|---|---|
| GitHub Actions | Google Drive | `GDRIVE_CREDENTIALS_JSON`、`GDRIVE_ROOT_FOLDER_ID` | GitHub Secrets |
| GitHub Actions | Supabase | `SUPABASE_URL`、`SUPABASE_SERVICE_KEY` | GitHub Secrets |
| 本機 dev DB | Supabase | `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_KEY` | `.env.local`（gitignore） |
| 本機 prod DB | Supabase | `SUPABASE_URL`、`SUPABASE_SERVICE_KEY` | `.env`（gitignore） |

**Supabase 值的取得位置：** Dashboard → Settings → API

| 變數 | 對應欄位 |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_KEY` | Project API keys → `service_role` |
| `SUPABASE_ANON_KEY` | Project API keys → `anon` / `public` |

> `service_role` 有完整資料庫權限，絕不可放進前端程式碼或 repo。

本機腳本切換 DB 時，使用 `ENV_FILE` 明確指定：

```bash
ENV_FILE=.env.local python3 scripts/sync_drive.py
ENV_FILE=.env.local python3 scripts/normalize.py

ENV_FILE=.env python3 scripts/sync_drive.py
ENV_FILE=.env python3 scripts/normalize.py
```

---

## DB Schema（Supabase PostgreSQL）

DB schema and migration workflow are documented in [`docs/database.md`](docs/database.md).
`sttmountain` is the source of truth for Supabase SQL. Frontend projects such as
`sttmountaincrazy` should depend on the RPC contract here, not keep their own SQL
copies.

新增或修改 DB 結構時，請新增 `db/migrations/*.sql`，先套 dev DB、驗證，再套同一份 SQL 到 prod DB。
不要只在 prod 手動補 SQL。

```
expedition_groups   id, name, drive_folder_id (unique), created_at
expeditions         id, group_id, drive_folder_id (unique),
                    name, date_start, date_end,
                    region_entry_county, region_entry_town,
                    region_exit_county, region_exit_town,
                    leader, grade, preview_image, created_at
expedition_counties id, expedition_id, county            （入山＋出山各一筆，UNIQUE）
gpx_files           id, expedition_id, drive_file_id (unique), filename, file_path
map_files           id, expedition_id, drive_file_id (unique), filename, file_path
records             id, expedition_id, drive_file_id (unique), filename, content, file_path
sync_state          key, value, updated_at               （存 last_synced_at）
sync_logs           synced_at, trigger, status, counts, errors, log_text
schema_migrations   version, applied_at                  （記錄已套用的 migration）
```

**Storage Buckets（Public）：**

| Bucket | 存放內容 |
|---|---|
| `gpx` | GPX / KML 軌跡檔 |
| `maps` | 地圖 PDF / 圖片 |
| `previews` | 出隊計畫書預覽圖（`{id}.png`） |
| `records` | 上繳紀錄原始檔（`{expedition_id}/{safe_filename}`） |

**RLS：** 所有 table 啟用。公開列表透過 `SECURITY DEFINER` RPC 讀取，`service_role` 有完整寫入權限。

**RPC 函式：**
- `list_expeditions(p_q, p_county, p_counties[], p_start, p_end, p_page, p_page_size, p_grade, p_sort)` → `{expeditions, total, page, pageSize}`，每筆 expedition 會包含 `gpx_count`、`map_count`、`rec_count`
- `get_expedition_dates()` → `{min_date, max_date}`
- `get_expedition_years()` → 實際有出隊資料的年份陣列，例如 `[2026, 2024]`

`grade` 由 DB trigger 從隊伍名稱 prefix 自動解析，例如 `[5C活]` 會寫入 `C`。

---

## CI/CD

### PR 驗證（目標分支為 `main`）

| 驗證 | 指令 |
|---|---|
| Python import 檢查 | `python -c "from app.main import app"` |

### 每日同步（UTC 20:00，台灣時間凌晨 4:00）

```
sync_drive.py  →  data/raw/sync_meta.json
     ↓
normalize.py   →  Supabase DB + Storage
     ↓
Build Docker image → Push GHCR → Watchtower 自動重啟
```

---

## 開發流程

`main` 和 `develop` 受 branch protection 保護：禁止直接 push，必須走 PR，CI 須通過。

```
feature/<desc>  →  develop  →  main
fix/<desc>      →  develop
hotfix/<desc>   →  main + develop（緊急修正）
```
