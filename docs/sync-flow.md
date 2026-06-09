# Sync Flow

同步流程分成兩段：先下載/記錄 Google Drive metadata，再解析資料並寫入 Supabase。

## Step 1: `scripts/sync_drive.py`

`sync_drive.py` 使用 Google Service Account 掃描根目錄。

Classification（判斷順序）：

1. **GROUP container**：直接子資料夾中有符合隊伍格式的子資料夾，且至少一個子資料夾含有直企檔案 → group activity。父層資料夾本身是否符合命名規則不影響此判斷（會師/大眾化的外層資料夾可能沒有 `[3D活]` 前綴）。
2. **Solo**：無子隊伍資料夾，父層本身符合隊伍格式，且直接含有直企檔案 → solo expedition。
3. **Skip**：其他情況，或直企檔案尚未上傳。

隊伍資料夾格式只強制檢查：

- 左括號 `[` 或 `［`；
- 天數；
- 級數 `A` / `B` / `C` / `D`；
- 右括號 `]` 或 `］`；
- 後方隊伍名稱。

例如 `[2D活]舊古樓嘍嘍_20260418`、`［2D活］舊古樓嘍嘍20260418` 都會被視為隊伍資料夾。

**直企檔案比對規則**：格式為 GSheet / xlsx / xls / numbers，且檔名包含 `直企` 或 `AllInOne`。沒有直企的隊伍資料夾不會寫入 `sync_meta.json`。

File folders:

- 只處理隊伍資料夾下的 `上繳航跡與紀錄` 和 `地圖`。
- 兩者底下可以有子資料夾，sync 會遞迴掃描。
- `上繳航跡與紀錄` 內的 `.gpx` / `.kml` 歸為航跡，其餘支援格式歸為紀錄。
- `地圖` 內只處理地圖支援格式。

Output:

```text
data/raw/sync_meta.json
```

Sync strategy:

- 只處理 `createdTime >= 2026-05-15` 的資料夾。
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
- `expeditions`: unique by `drive_folder_id`. **Skip rows where `sync_locked = true`** — those have been manually edited and must not be overwritten by sync.
- `gpx_files`, `map_files`, `record_files`: unique by `drive_file_id`.

Sync lock check (pseudocode):

```python
existing = supabase.table('expeditions').select('sync_locked').eq('drive_folder_id', folder_id).maybe_single()
if existing and existing['sync_locked']:
    continue  # manual edit present; do not overwrite
```

Visibility:

- `expeditions.is_public` defaults to `true`.
- Public RPCs and anon table policies only expose `is_public = true` expeditions.
- Historical incomplete, canceled, or mistakenly imported expeditions can be hidden by setting `is_public = false`.

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
