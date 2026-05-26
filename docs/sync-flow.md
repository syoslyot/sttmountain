# Sync Flow

同步流程分成兩段：先下載/記錄 Google Drive metadata，再解析資料並寫入 Supabase。

## Step 1: `scripts/sync_drive.py`

`sync_drive.py` 使用 Google Service Account 掃描根目錄。

Classification:

- 根目錄直接有 `*直企.xlsx`：solo expedition。
- 根目錄底下有子資料夾，各自含 `*直企.xlsx`：group activity。
- 其他資料夾：skip。

Output:

```text
data/raw/sync_meta.json
```

Sync strategy:

- 只處理 `createdTime >= 2026-05-01` 的資料夾。
- 從 Supabase `sync_state` 讀取 `last_synced_at`。
- 新資料夾全量下載。
- 舊資料夾只下載 `modifiedTime` 更新的檔案。

## Step 2: `scripts/normalize.py`

`normalize.py` 讀取 `sync_meta.json`，解析直企與相關檔案。

直企 P1 sheet contract:

| Cell | Meaning |
| --- | --- |
| `D2` | expedition name |
| `D3` | start date, ROC year converted to `YYYY-MM-DD` |
| `D4` | end date |
| `F3` | entry location, parsed into county/town |
| `F4` | exit location, parsed into county/town |
| `C17` | leader |

Preview generation:

- P1: detect content range.
- P2: fixed range `B2:O12`.
- Combine vertically, resize to width 1240px, upload to `previews`.

Upsert strategy:

- `expedition_groups`: group activities share one `group_id`; solo expeditions get an independent group.
- `expeditions`: unique by `drive_folder_id`.
- `gpx_files`, `map_files`, `records`: unique by `drive_file_id`.

## Local Commands

Dev:

```bash
ENV_FILE=.env.local python3 scripts/sync_drive.py
ENV_FILE=.env.local python3 scripts/normalize.py
```

Prod:

```bash
ENV_FILE=.env python3 scripts/sync_drive.py
ENV_FILE=.env python3 scripts/normalize.py
```

Prod operations should be deliberate. Prefer testing on dev first.
