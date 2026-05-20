# 跨系統連線說明

## 為什麼需要「祕密連線」

本質上：**兩個完全獨立的服務要互相溝通，必須先證明身份。**

GitHub Actions 是一台 GitHub 提供的機器，跑完任務就消失。Supabase 不認識這台機器，所以要給它一把「鑰匙」，才能進去寫資料。這把鑰匙不能寫在程式碼裡（會被公開看見），所以存在 Secrets 裡，只有 CI 執行時才注入為環境變數。

---

## 所有跨系統連線整理

| 從哪裡 | 連到哪裡 | 需要什麼 | 存在哪裡 |
|---|---|---|---|
| GitHub Actions（CI） | Google Drive | `GDRIVE_CREDENTIALS_JSON`（Service Account）、`GDRIVE_ROOT_FOLDER_ID` | GitHub Secrets |
| GitHub Actions（CI） | Supabase | `SUPABASE_URL`、`SUPABASE_SERVICE_KEY` | GitHub Secrets |
| Render（前端） | Supabase | `SUPABASE_URL`、`SUPABASE_ANON_KEY` | Render 環境變數 |

---

## 規律

每一條連線都由兩個東西組成：

- **要連到哪裡**（URL / ID）— 地址
- **憑什麼進去**（key / JSON）— 鑰匙

存放位置依照「誰在執行」決定：

| 執行環境 | 存放位置 |
|---|---|
| CI（GitHub Actions） | GitHub repo → Settings → Secrets |
| 部署伺服器（Render） | Render Dashboard → Environment Variables |
| 本機開發 | `.env.local`（不可 commit） |

---

## 取得 Supabase 的值

Supabase Dashboard → 左側選單 → **Settings（齒輪）→ API**

| 名稱 | 對應欄位 |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_KEY` | Project API keys → `service_role` |
| `SUPABASE_ANON_KEY` | Project API keys → `anon` / `public` |

> `service_role` 有完整資料庫權限，只能放在伺服器端（CI、Render），絕不可放進前端程式碼或公開 repo。
