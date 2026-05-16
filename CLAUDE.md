# sttmount — 山社出隊紀錄網站

## 專案目的
NCKU 山社的出隊紀錄展示網站。無會員系統，純資料展示。
幹部照舊把資料上傳至 Google Drive，系統每日自動同步並更新網站。

---

## 技術棧

| 層級 | 選擇 |
|---|---|
| Backend | Python 3.12 + FastAPI + Jinja2（SSR） |
| Database | SQLite（`db/sttmount.db`） |
| Frontend | HTML + Tailwind CSS（CDN）+ Vanilla JS |
| 地圖 | Leaflet.js + leaflet-omnivore（GPX/KML）|
| 地圖底圖 | NLSC 通用電子地圖（預設）/ OpenTopoMap / OSM / NLSC 正射影像 + 等高線 overlay |
| 高度剖面 | @raruto/leaflet-elevation（GPX 軌跡高度圖）|
| 部署 | Docker Compose + Nginx，跑在 Windows 筆電（學校固定 IP，內網） |
| 自動更新 | Watchtower（監聽 GHCR，自動 pull 新 image） |
| CI/CD | GitHub Actions：每日同步 Drive → build image → push GHCR |

---

## 資料來源（Google Drive）

```
所有出隊資料夾/
  {出隊名稱}/
    *.xlsx                 → data/raw/xlsx/{出隊名}.xlsx（normalize 後改名為 {id}.xlsx）
    地圖資料夾/
      *.gpx, *.kml         → app/static/gpx/{出隊名}.gpx（normalize 後改名為 {id}.gpx）
      *.pdf                → app/static/maps/{出隊名}.pdf（normalize 後改名為 {id}.pdf）
    紀錄資料夾/
      *.txt                → data/raw/txt/{出隊名}/{filename}.txt（normalize 後資料夾改名為 {id}/，並批次 INSERT records）
```

環境變數（GitHub Actions Secrets）：
- `GDRIVE_CREDENTIALS_JSON` — Service Account JSON
- `GDRIVE_ROOT_FOLDER_ID` — 「所有出隊資料夾」的 Drive folder ID

---

## 專案結構

```
sttmount/
├── app/
│   ├── main.py            # FastAPI 入口
│   ├── models.py          # SQLite schema + get_conn()
│   ├── routes/
│   │   ├── region.py      # / 和 /region/{county}/{region}
│   │   ├── date.py        # /date
│   │   ├── search.py      # /search
│   │   └── expedition.py  # /expedition/{id}
│   ├── static/
│   │   ├── gpx/           # GPX/KML 檔案（依出隊名分子資料夾）
│   │   └── maps/          # PDF/圖片（依出隊名分子資料夾）
│   └── templates/
│       ├── base.html
│       ├── index.html         # 首頁（D3.js SVG 地圖 / 日期 / 搜尋 + 動態結果）
│       ├── region.html        # 縣市內子地區列表
│       ├── expedition_list.html
│       ├── expedition.html    # 出隊詳細頁（地圖、PDF、紀錄、隊員）
│       ├── date.html
│       └── search.html
├── scripts/
│   ├── sync_drive.py      # Google Drive → 本機（已實作）
│   ├── normalize.py       # Excel → SQLite（待 Excel 範例後實作）
│   ├── seed.py            # 200 筆假資料（開發測試用）
│   └── gen_gpx.py         # 產生假 GPX 軌跡檔（配合 seed.py）
├── db/
│   └── sttmount.db        # SQLite（gitignore）
├── data/raw/
│   ├── xlsx/              # Drive 下載的 xlsx（{出隊名}.xlsx → normalize 後改名為 {id}.xlsx）（gitignore）
│   └── txt/               # Drive 下載的紀錄 txt（{出隊名}/ → normalize 後改名為 {id}/）（gitignore）
├── .github/workflows/
│   ├── sync.yml           # 每日定時同步（待實作）
│   └── deploy.yml         # push main 時 build & push image（待實作）
├── Dockerfile
├── docker-compose.yml     # app + nginx + watchtower
├── nginx.conf
└── requirements.txt
```

---

## DB Schema

```sql
expeditions  (id, name, date_start, date_end, county, region, description)
members      (id, expedition_id, name, role, department, experience)
gpx_files    (id, expedition_id, filename, file_path)
map_files    (id, expedition_id, filename, file_path, file_type)
records      (id, expedition_id, filename, content)
```

---

## 功能現況

| 功能 | 狀態 |
|---|---|
| 首頁（左右分割：縣市格 / 日期 / 搜尋 + 動態結果） | ✅ 完成 |
| 地區查詢（縣市格 → 子地區列表 → 出隊列表） | ✅ 完成 |
| 日期查詢 | ✅ 完成 |
| 文字搜尋 | ✅ 完成 |
| 出隊詳細頁（左右分割：地圖 + 資訊） | ✅ 完成 |
| Leaflet 地圖（NLSC EMAP 預設、底圖切換、等高線 overlay） | ✅ 完成 |
| GPX 高度剖面圖（leaflet-elevation） | ✅ 完成 |
| GPX / KML 顯示 + 下載 | ✅ 完成 |
| PDF / 圖片嵌入 + 下載 | ✅ 完成 |
| 成員紀錄（txt）顯示 | ✅ 完成 |
| Google Drive 同步腳本 | ✅ 完成（sync_drive.py） |
| 假資料種子腳本 | ✅ 完成（seed.py + gen_gpx.py） |
| GitHub Actions CI/CD | ✅ 完成（`.github/workflows/ci.yml`，Node.js 24） |
| Excel 正規化腳本 | ⏳ 待 Excel 範例 |
| 台灣 SVG 地圖（D3.js + Canvas hit-testing） | ✅ 完成 |
| Server 部署文件 | ⏳ 待實作 |

---

## 本機開發

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 -c "from app.models import init_db; init_db()"
python3 scripts/seed.py      # 插入 200 筆假資料
python3 scripts/gen_gpx.py   # 產生假 GPX 軌跡檔
uvicorn app.main:app --reload
# 開啟 http://localhost:8000
```

**DB 縣市欄規則**：一律存 17 個顯示名稱（"台北"、"南投" 等），
normalize.py 負責將 Excel 的 "臺北市"、"台北市" 等變體統一對應。

---

## Git Flow

```
main      ← 穩定版，只接受來自 develop 或 hotfix/* 的 merge
develop   ← 日常開發整合，feature/* 都 merge 到這裡
feature/* ← 每個功能一條分支，從 develop 切出
hotfix/*  ← 緊急修正，從 main 切出，merge 回 main 和 develop
```

日常流程：
```bash
git checkout develop
git checkout -b feature/xxx
# ... 開發、commit ...
git checkout develop
git merge --no-ff feature/xxx
# 穩定後：
git checkout main
git merge --no-ff develop
git push origin main develop
```

---

## 待確認

- Excel 檔案結構（欄位、分頁名稱）→ normalize.py 依此設計
- 另一個地圖格式（目前支援 GPX + KML，其他之後補）
