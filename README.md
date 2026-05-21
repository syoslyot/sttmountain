# sttmount — 成大山協出隊紀錄網站

NCKU 山協出隊資料展示平台。幹部照舊把資料上傳至 Google Drive，系統每日自動同步並更新網站，無需手動操作資料庫或伺服器。

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
| 部署 | Docker Compose + Nginx |
| 自動更新 | Watchtower（監聽 GHCR，自動 pull 新 image） |
| CI/CD | GitHub Actions（每日同步 Drive → normalize → push Supabase） |

---

## 幹部：如何上傳資料

在 Google Drive 的「所有出隊資料夾」內，為每次出隊建立一個子資料夾，命名即為出隊名稱：

```
所有出隊資料夾/
  {出隊名稱}/
    出隊計畫書.xlsx          ← 直企格式（必填）
    地圖資料夾/              ← 也可命名為「地圖」「map」「maps」
      軌跡.gpx 或 .kml      ← GPX 軌跡（選填，可多份）
      地圖.pdf              ← 地圖 PDF（選填，可多份）
    紀錄資料夾/              ← 也可命名為「紀錄」「record」「records」
      成員A紀錄.txt         ← 隊員紀錄文章，可多份（選填）
      成員B紀錄.docx        ← Word 文件亦可
      成員C紀錄（Google 文件）← Google 文件亦可（自動匯出為 txt）
```

**注意：**
- xlsx 需包含 `直企P1(列印)` 或 `直企列印 P1` sheet（兩種命名均支援）
- 每日 CI 自動同步，上傳後隔日生效；也可手動觸發 GitHub Actions

---

## 完整同步流程（按下 Run workflow 後發生的事）

### Step 1：CI 機器環境準備

GitHub 開一台全新 Ubuntu 機器，clone repo，安裝：
- Python 套件（`pip install -r requirements.txt`）
- LibreOffice headless — 截圖用，把 xlsx 轉成 PDF
- `fonts-noto-cjk` — 中文字型，不裝的話截圖會出現亂碼方塊

---

### Step 2：`scripts/sync_drive.py`

用 Service Account JSON 向 Google Drive 認證，列出「所有出隊資料夾」根目錄下每個子資料夾（每個子資料夾 = 一次出隊），對每次出隊分三類下載：

**xlsx（直企）**
比對 Drive 回傳的 `modifiedTime` 和本機 mtime，Drive 比較新才重新下載，存到 `data/raw/xlsx/{出隊名稱}_{檔名}.xlsx`。本機不存在也會下載。

**地圖資料夾**（名稱符合「地圖資料夾／地圖／map／maps」）
- `.gpx` / `.kml` → 比對時間後下載到 `app/static/gpx/{出隊名稱}/`
- `.pdf` → 下載到 `app/static/maps/{出隊名稱}/`

**紀錄資料夾**（名稱符合「紀錄資料夾／紀錄／record／records」）
- Google 文件 → Drive API export 成純文字，存到 `data/raw/txt/{出隊名稱}/`
- `.txt` / `.md` / `.docx` → 比對時間後下載

> modifiedTime 比對規則：Drive 檔案的 `modifiedTime`（UTC）> 本機 mtime → 重新下載；否則跳過。

---

### Step 3：`scripts/normalize.py`

掃描 `data/raw/xlsx/` 下所有 xlsx，每個檔案跑一次完整流程：

**讀取 P1 sheet**（sheet 名稱為「直企P1(列印)」或「直企列印 P1」）

| 儲存格 | 內容 |
|---|---|
| `D2` | 出隊名稱 |
| `C3` | 出發日（民國年，轉成 `YYYY-MM-DD`） |
| `C4` | 回程日 |
| `F3` | 入山地點（抓縣市 + 鄉鎮，「臺南市」→「台南」） |
| `F4` | 出山地點 |

**讀取 P2 sheet**（sheet 名稱為「直企P2(列印)」或「直企列印 P2」）
- M/N 欄第 3～11 列 → 留守資料，拼成 `description`
- `D10` → 若有 Garmin 追蹤連結一併附上
- 第 15 列起往下掃隊員：A 欄「領／嚮／隊／新」判斷角色，B 欄系所，D 欄姓名，F 欄山歷

**查重複**
以出隊名稱 + 出發日查 `expeditions` 表：
- 已存在 → 只跑 `scan_static_files` 補掃靜態檔，結束
- 不存在 → 依序 INSERT `expeditions`、`members`、`expedition_counties`

**`scan_static_files`**

目錄名優先用 `{id}/`，若還是 `{出隊名稱}/` 自動改名。掃三個位置：

| 來源目錄 | 處理 | 目的地 |
|---|---|---|
| `app/static/gpx/{id}/` | 算 storage 安全路徑 → 查重 → INSERT → upsert 上傳 | Supabase Storage `gpx` bucket |
| `app/static/maps/{id}/` | 同上 | Supabase Storage `maps` bucket |
| `data/raw/txt/{id}/` | 讀內容（docx 用 python-docx、pdf 用 PyMuPDF、其他直接讀 utf-8）→ 查重 → INSERT | `records.content`（不上傳 Storage） |

Storage 路徑命名規則（`storage_safe_name()`）：中文或特殊字元檔名 → 取 SHA1 前 12 碼 + 副檔名；純 ASCII 檔名 → 清除特殊字元後直接用。`filename` 欄位保留原始中文名供前端顯示。

**截圖預覽**
1. P1 sheet 的列印範圍設為 `A2:G27`，其他 sheet 刪掉，另存暫時 xlsx
2. LibreOffice headless 把暫時 xlsx 轉成 PDF
3. PyMuPDF 把 PDF 第一頁渲染成 2× 解析度 PNG
4. `trim_whitespace()` — 裁掉白邊，保留 15px padding
5. `build_a4_preview()` — 縮放到寬 1240px，超過 A4 高度（1754px）等比縮小
6. 上傳 `previews/{id}.png` → UPDATE `expeditions.preview_image`

---

跑完後 CI 機器銷毀，網站下次請求時直接從 Supabase 讀取更新後的資料。

---

## 本機開發

```bash
# 複製環境變數範本
cp .env.example .env
# 填入 SUPABASE_URL 和 SUPABASE_SERVICE_KEY

pip install -r requirements.txt
python3 scripts/normalize.py data/raw/xlsx/foo.xlsx
```

**環境變數與跨系統連線：**

本專案涉及三個獨立服務互相溝通，每條連線都需要「地址」和「鑰匙」。鑰匙不能寫進程式碼，依執行環境分別存放：

| 從哪裡 | 連到哪裡 | 變數 | 存放位置 |
|---|---|---|---|
| GitHub Actions（CI） | Google Drive | `GDRIVE_CREDENTIALS_JSON`、`GDRIVE_ROOT_FOLDER_ID` | GitHub repo → Settings → Secrets |
| GitHub Actions（CI） | Supabase | `SUPABASE_URL`、`SUPABASE_SERVICE_KEY` | GitHub repo → Settings → Secrets |
| Render（前端） | Supabase | `SUPABASE_URL`、`SUPABASE_ANON_KEY` | Render Dashboard → Environment Variables |
| 本機開發 | Supabase | `SUPABASE_URL`、`SUPABASE_SERVICE_KEY` | `.env.local`（不可 commit） |

**Supabase 值的取得位置：** Dashboard → Settings（齒輪）→ API

| 變數 | 對應欄位 |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_KEY` | Project API keys → `service_role`（不是 anon） |
| `SUPABASE_ANON_KEY` | Project API keys → `anon` / `public` |

> `service_role` 有完整資料庫權限，只能放在伺服器端，絕不可放進前端程式碼或公開 repo。

---

## DB Schema（Supabase PostgreSQL）

```
expeditions         id, name, date_start, date_end, county, region, region_exit,
                    leader, description, preview_image, created_at
gpx_files           id, expedition_id, filename, file_path   （如 "203/route.gpx"）
map_files           id, expedition_id, filename, file_path   （如 "203/map.pdf"）
records             id, expedition_id, filename, content
expedition_counties id, expedition_id, county                 （入山＋出山各一筆，UNIQUE）
members             id, expedition_id, name, role, department, experience
```

**縣市正規化規則：** 一律存 17 個顯示簡稱（「台北」「南投」等）。

**Storage Buckets（Public）：**

| Bucket | 路徑格式 | 存放內容 |
|---|---|---|
| `gpx` | `{id}/{filename}` | GPX / KML 軌跡檔 |
| `maps` | `{id}/{filename}` | 地圖 PDF |
| `previews` | `{id}.png` | 出隊計畫書預覽圖 |

**RLS：** 所有 table 啟用，`anon` 只能 SELECT，`service_role` 有完整寫入權限。

**RPC 函式：**
- `list_expeditions(p_q, p_county, p_counties[], p_start, p_end, p_page, p_page_size)` → `{expeditions, total, page, pageSize}`
- `get_expedition_dates()` → `{min_date, max_date}`

---

## CI/CD 自動化流程

### PR 驗證（`pull_request: main`）

| 驗證 | 指令 | 抓什麼問題 |
|------|------|-----------|
| Python import 檢查 | `python -c "from app.main import app"` | 語法錯誤、循環 import、缺少套件 |

### 部署流程（每日定時觸發）

```
sync_drive.py   ← 從 Google Drive 下載新資料
  ↓
normalize.py    ← 解析 xlsx → 寫入 Supabase DB → 上傳 Storage → 生成截圖
  ↓
Build Docker image（純 app 程式碼，不含資料）
  ↓
Push to GHCR
  ↓
Watchtower 自動偵測新 image → 重啟容器
```

---

## 開發流程

`main` 和 `develop` 受 GitHub branch ruleset 保護（設定日期：2025-05-20）：不可直接 push，必須走 PR，CI 須通過，force push 被擋。

```
feature/<desc>  →  develop  →  main
fix/<desc>      →  develop
hotfix/<desc>   →  main + develop（緊急修正）
```

---

## 待辦事項

- [ ] 出隊詳細頁：多 GPX 檔選擇（目前全部同時載入）
- [ ] 出隊詳細頁：多筆紀錄文章選擇（目前全部展開）
