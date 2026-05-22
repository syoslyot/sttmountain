"""
一次性補填既有紀錄的 file_path。

查詢 file_path IS NULL 的 records，從 Google Drive 重新下載並上傳到 Storage bucket
`records`，然後更新 DB 的 file_path 欄位。

用法：
  python scripts/backfill_record_files.py            # 實際執行
  python scripts/backfill_record_files.py --dry-run  # 只列出待處理項目，不做任何寫入
"""
import sys
import io
import tempfile
import argparse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from normalize import supabase, storage_upload, storage_safe_name, CONTENT_TYPE_MAP
from sync_drive import build_service, download_file


def backfill(dry_run: bool = False) -> None:
    result = supabase.table("records") \
        .select("id, filename, drive_file_id, expedition_id") \
        .is_("file_path", "null") \
        .execute()

    rows = result.data or []
    print(f"待補填筆數：{len(rows)}")
    if not rows:
        return

    service = None if dry_run else build_service()

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        for row in rows:
            rec_id       = row["id"]
            filename     = row["filename"]
            drive_id     = row["drive_file_id"]
            exp_id       = row["expedition_id"]
            ext          = Path(filename).suffix.lower()
            safe         = storage_safe_name(filename)
            storage_path = f"{exp_id}/{safe}"
            content_type = CONTENT_TYPE_MAP.get(ext, "application/octet-stream")

            print(f"  [{rec_id}] {filename}  →  records/{storage_path}")
            if dry_run:
                continue

            dest = tmp / safe
            try:
                download_file(service, drive_id, dest)
                data = dest.read_bytes()
                supabase.storage.from_("records").upload(
                    storage_path, data,
                    file_options={"content-type": content_type, "upsert": "true"},
                )
                supabase.table("records") \
                    .update({"file_path": storage_path}) \
                    .eq("id", rec_id) \
                    .execute()
                print(f"    ✓")
            except Exception as e:
                print(f"    ✗ {e}")

    print("完成")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只列出待處理項目，不寫入")
    args = parser.parse_args()
    backfill(dry_run=args.dry_run)
