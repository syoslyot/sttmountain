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

## 資料流程（Data Ingestion）

### Google Drive 同步（`scripts/sync_drive.py`）

每日透過 Service Account 讀取 Drive，下載至本機：

| 類型 | 下載至 |
|---|---|
| xlsx | `data/raw/xlsx/{出隊名}_{drive_filename}.xlsx` |
| GPX / KML | `app/static/gpx/{出隊名}_{drive_filename}`（支援多檔） |
| PDF | `app/static/maps/{出隊名}_{drive_filename}`（支援多檔） |
| txt / md / docx | `data/raw/txt/{出隊名}_{filename}`（扁平，無子資料夾） |
| Google 文件 | 匯出為 `data/raw/txt/{出隊名}_{name}.txt` |

**冪等保護：** 目標檔案已存在時直接跳過，不重複下載。

---

### 正規化入庫（`scripts/normalize.py`）

預設掃描 `data/raw/xlsx/`，也可傳指定檔案路徑：

```bash
python3 scripts/normalize.py                         # 掃描全部
python3 scripts/normalize.py data/raw/xlsx/foo.xlsx  # 指定檔案
```

**處理步驟：**

```
讀取 xlsx
  ↓
解析 P1 sheet（直企P1(列印) 或 直企列印 P1）
  → 出隊名稱、出發日、回程日、入山地點（縣市＋鄉鎮）、出山地點（縣市＋鄉鎮）
  ↓
解析 P2 sheet（直企P2(列印) 或 直企列印 P2）
  → 留守資料（M/N 欄）→ description
  ↓
查詢 Supabase：是否已存在同名＋同日期的出隊？
  ├─ 已存在 → 補掃靜態檔案後結束
  └─ 不存在 → INSERT expeditions + expedition_counties + members
              ↓
              scan_static_files
              ↓
              生成截圖預覽（P1 PNG）→ 上傳 Storage previews bucket
              ↓
              UPDATE expeditions SET preview_image = '{id}.png'
```

**scan_static_files 行為：**

| 資源 | 本地來源 | Supabase Storage | DB 寫入 |
|---|---|---|---|
| GPX / KML | `app/static/gpx/{id}/` | `gpx` bucket，路徑 `{id}/{filename}` | `gpx_files` |
| PDF | `app/static/maps/{id}/` | `maps` bucket，路徑 `{id}/{filename}` | `map_files` |
| txt / md / docx | `data/raw/txt/{id}/` | 不上傳（內容存 DB） | `records.content` |

每種資源均支援多檔；`.docx` 透過 `python-docx` 提取純文字後存入 `records.content`。

**重複執行（idempotency）：**
- 查詢 Supabase 確認已存在 → 跳過
- Storage 上傳使用 `upsert: true`，覆蓋舊檔不報錯

---

### 截圖生成邏輯

1. 擷取 P1 範圍（`A2:G27`）→ LibreOffice 轉 PDF → PyMuPDF 轉 PNG（2× 解析度）
2. `trim_whitespace()`：裁切空白邊框，保留 15px padding
3. `build_a4_preview()`：目標寬 1240px，超過 A4 高度等比縮小
4. 輸出 PNG → 上傳 Supabase Storage `previews/{id}.png`

---

## 本機開發

```bash
# 複製環境變數範本
cp .env.example .env
# 填入 SUPABASE_URL 和 SUPABASE_SERVICE_KEY

pip install -r requirements.txt
python3 scripts/normalize.py data/raw/xlsx/foo.xlsx
```

**環境變數（`.env` 或 GitHub Secrets）：**

| 變數 | 用途 |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | service_role key（寫入 DB + Storage） |
| `GDRIVE_CREDENTIALS_JSON` | Google Drive Service Account JSON |
| `GDRIVE_ROOT_FOLDER_ID` | 「所有出隊資料夾」的 Drive folder ID |

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
