# sttmount — 成大山協出隊紀錄網站

NCKU 山協出隊資料展示平台。幹部照舊把資料上傳至 Google Drive，系統每日自動同步並更新網站，無需手動操作資料庫或伺服器。

---

## 技術棧

| 層級 | 選擇 |
|---|---|
| Backend | Python 3.12 + FastAPI + Jinja2（SSR） |
| Database | SQLite |
| Frontend | HTML + Tailwind CSS（CDN）+ Vanilla JS |
| 地圖 | Leaflet.js + leaflet-omnivore（GPX/KML）|
| 地圖底圖 | NLSC 通用電子地圖 / OpenTopoMap / OSM / NLSC 正射影像 + 等高線 overlay |
| 高度剖面 | @raruto/leaflet-elevation |
| 部署 | Docker Compose + Nginx |
| 自動更新 | Watchtower（監聽 GHCR，自動 pull 新 image） |
| CI/CD | GitHub Actions（每日同步 Drive → build image → push GHCR） |

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
- xlsx 需包含「直企P1(列印)」與「直企P2(列印)」兩個 sheet
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
解析 直企P1(列印) sheet
  → 出隊名稱、出發日、回程日、入山地點（縣市＋鄉鎮）、出山地點（縣市＋鄉鎮）
  ↓
解析 直企P2(列印) sheet
  → 留守資料（M/N 欄）、Garmin 追蹤連結、注意事項 → 合為 description
  → 領隊姓名 → expeditions.leader
  ↓
查詢 DB：是否已存在同名＋同日期的出隊？
  ├─ 已存在 → 補掃靜態檔案後結束
  └─ 不存在 → INSERT expeditions + expedition_counties
              ↓
              rename xlsx：{出隊名}_{drive_filename}.xlsx → {id}_{drive_filename}.xlsx
              ↓
              scan_static_files
              ↓
              生成截圖預覽（P1 + P2 合併為 A4 PNG）
              ↓
              UPDATE expeditions SET preview_image
```

**scan_static_files 行為：**

以 P1 解析出的出隊名稱（`name`）為前綴，glob 掃描各目錄，將 `{出隊名}_{original}` 改名為 `{id}_{original}` 並寫入 DB：

| 資源 | 來源（glob） | 目的地 | DB 寫入 |
|---|---|---|---|
| GPX / KML | `app/static/gpx/{出隊名}_*` | `app/static/gpx/{id}_{original}` | `gpx_files` |
| PDF | `app/static/maps/{出隊名}_*` | `app/static/maps/{id}_{original}` | `map_files` |
| txt / md / docx | `data/raw/txt/{出隊名}_*`（扁平） | `data/raw/txt/{id}_{original}` | `records`（逐檔 INSERT） |

每種資源均支援多檔；`.docx` 透過 `python-docx` 提取純文字後存入 `records.content`。

**重複執行（idempotency）：**
- 目標路徑已存在 → 略過 rename
- `INSERT OR IGNORE` 保護不重複寫 DB
- records 以 `(expedition_id, filename)` 查 DB，已存在則跳過

---

### 截圖生成邏輯

1. 擷取 P1 範圍（`A2:G27`）→ LibreOffice 轉 PDF → PyMuPDF 轉 PNG（2× 解析度）
2. 擷取 P2 範圍（`B2:O11`）→ 同上
3. `trim_whitespace()`：裁切空白邊框，保留 15px padding
4. `build_a4_preview()`：目標寬 1240px，兩張垂直排列（16px gap），超過 A4 高度等比縮小
5. 輸出：`app/static/previews/{id}.png`

---

## 網頁 UX 流程

### 首頁（`/`）

**版面：** 左右分割，各佔 50% 視窗高度，獨立捲動。

#### 左半：篩選區（三種模式）

| 模式 | Tab | 行為 |
|---|---|---|
| 地區 | 地圖圖示 | 台灣縣市格狀地圖，點選縣市 |
| 日期 | 日曆圖示 | 快速預設（1個月／半年／1年／3年）＋自訂日期區間 |
| 關鍵字 | 搜尋圖示 | 即時搜尋（300ms debounce），清空自動恢復預設列表 |

切換 Tab 時，若離開地區模式，縣市格選取狀態自動清除。

#### 右半：結果列表

- 初始：`/fragment/recent`，以結束日期排序（最近的在上方）
- 每頁 20 筆，捲動到底部 200px 前自動載入下一頁（Infinite Scroll）

| 觸發 | Fragment API |
|---|---|
| 點選縣市 | `GET /fragment/county/{name}` |
| 日期變更 | `GET /fragment/date?date_from=&date_to=` |
| 關鍵字輸入 | `GET /fragment/search?q=` |
| 關鍵字清空 | `GET /fragment/recent` |

所有端點共用 `?offset=N` 參數（LIMIT 21，多一筆用於判斷是否有下一頁）。

日期模式：頁面載入時預設為今天；`date-from` 或 `date-to` 任一空白不觸發查詢。

---

### 出隊詳細頁（`/expedition/{id}`）

**版面：** 左地圖右資訊，各自獨立捲動。

#### 左半：互動地圖

- 預設底圖：NLSC 通用電子地圖
- 可切換：OpenTopoMap、OpenStreetMap、NLSC 正射影像
- 可疊加 overlay：NLSC 等高線
- 初始中心：依 `county` 對應縣市座標；無縣市資料則顯示台灣全島（zoom 8）
- 有 GPX：底部固定 140px 高度剖面圖，懸停游標對應地圖位置
- 有 KML：omnivore 載入，自動 fitBounds

#### 右半：出隊資訊（由上至下）

1. **截圖預覽**（P1 + P2 合併圖）— 有才顯示
2. **紀錄文章**（每份 txt/docx 各一個 `<details>`，預設**展開**）— 有才顯示；`<pre>` 保留原始格式

#### Navbar 下載按鈕

- 有 GPX → 顯示 GPX 下載按鈕，按鈕文字為 DB 中的實際檔名（如 `210_水山霞山_薰慈.gpx`）
- 有 PDF → 顯示 PDF 下載按鈕，按鈕文字為 DB 中的實際檔名
- 兩者皆無 → 不顯示任何下載元素

---

## DB Schema

```
expeditions         id, name, date_start, date_end, county, region, region_exit,
                    leader, description, preview_image, created_at
gpx_files           id, expedition_id, file_path       （如 "210_水山霞山_薰慈.gpx"）
map_files           id, expedition_id, file_path       （如 "209_茶茶牙頓出西都驕溪.pdf"）
records             id, expedition_id, filename, content
expedition_counties expedition_id, county              （入山＋出山各一筆，UNIQUE）
```

**縣市正規化規則：** 一律存 17 個顯示簡稱（「台北」「南投」等）。
`normalize.py` 負責將 Excel 的官方名稱（「臺北市」「台北市」「南投縣」）統一轉換。

所有子表設 `ON DELETE CASCADE`，刪除出隊資料時自動清除關聯紀錄。

---

## CI/CD 自動化流程

```
每日定時觸發（或手動）
  ↓
sync_drive.py   ← 從 Google Drive 下載新資料
  ↓
normalize.py    ← 解析 xlsx → 寫入 DB → 改名靜態檔 → 生成截圖
  ↓
Build Docker image（含更新後的 DB 和靜態檔案）
  ↓
Push to GHCR
  ↓
Watchtower（部署伺服器）自動偵測新 image → 重啟容器
```

**環境變數（GitHub Actions Secrets）：**
- `GDRIVE_CREDENTIALS_JSON` — Service Account JSON
- `GDRIVE_ROOT_FOLDER_ID` — 「所有出隊資料夾」的 Drive folder ID

---

## 待辦事項

- [ ] 出隊詳細頁：多 GPX 檔選擇（目前全部同時載入，需加選擇 UI）
- [ ] 出隊詳細頁：多筆紀錄文章選擇（目前全部展開，需加選擇 UI）

---

## 開發流程

`main` 和 `develop` 受 GitHub branch ruleset 保護（設定日期：2025-05-20）：不可直接 push，必須走 PR，CI（`CI - Sync, Build, Deploy`）須通過，force push 被擋。

```
feature/<desc>  →  develop  →  main
fix/<desc>      →  develop
hotfix/<desc>   →  main + develop（緊急修正）
```

---

## 本機開發

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 -c "from app.models import init_db; init_db()"
python3 scripts/seed.py      # 插入假資料
python3 scripts/gen_gpx.py   # 產生假 GPX 軌跡檔
uvicorn app.main:app --reload
# 開啟 http://localhost:8000
```
