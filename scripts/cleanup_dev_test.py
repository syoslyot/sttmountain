"""
清空 dev DB 所有出隊資料、Storage 檔案，並重置 sync_state.last_synced_at。

用法：
  python scripts/cleanup_dev_test.py            # 實際執行
  python scripts/cleanup_dev_test.py --dry-run  # 只列出待清除項目，不寫入
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from normalize import supabase

PREV_SYNCED_AT = "2026-05-21T12:19:16.860363+00:00"
STORAGE_BUCKETS_BY_TABLE = {
    "records":   "records",
    "gpx_files": "gpx",
    "map_files":  "maps",
}


def list_storage_paths(exp_id: int) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for table, bucket in STORAGE_BUCKETS_BY_TABLE.items():
        rows = supabase.table(table).select("file_path").eq("expedition_id", exp_id).execute()
        paths = [r["file_path"] for r in rows.data if r.get("file_path")]
        if paths:
            result[bucket] = paths
    exp = supabase.table("expeditions").select("preview_image").eq("id", exp_id).execute()
    if exp.data and exp.data[0].get("preview_image"):
        result.setdefault("previews", []).append(exp.data[0]["preview_image"])
    return result


def cleanup(dry_run: bool = False) -> None:
    all_rows = supabase.table("expeditions").select("id, name, group_id").execute()

    if not all_rows.data:
        print("dev DB 已是空的。")
        if not dry_run:
            supabase.table("sync_state").update({"value": PREV_SYNCED_AT}).eq("key", "last_synced_at").execute()
            print(f"  reset sync_state.last_synced_at → {PREV_SYNCED_AT}")
        return

    exp_ids = [r["id"] for r in all_rows.data]
    group_ids = list({r["group_id"] for r in all_rows.data if r.get("group_id")})

    print("=== 待清除項目 ===")
    for r in all_rows.data:
        print(f"  expedition id={r['id']}  name={r['name']}  group_id={r['group_id']}")

    # Storage 檔案
    all_storage: dict[str, list[str]] = {}
    for exp_id in exp_ids:
        for bucket, paths in list_storage_paths(exp_id).items():
            all_storage.setdefault(bucket, []).extend(paths)

    print("\n=== Storage 檔案 ===")
    for bucket, paths in all_storage.items():
        for p in paths:
            print(f"  {bucket}/{p}")

    print(f"\n=== sync_state.last_synced_at → {PREV_SYNCED_AT} ===")

    if dry_run:
        print("\n[dry-run] 不執行任何刪除")
        return

    # 刪 Storage
    for bucket, paths in all_storage.items():
        supabase.storage.from_(bucket).remove(paths)
        print(f"  deleted storage {bucket}: {len(paths)} 個檔案")

    # 刪 DB children
    for table in STORAGE_BUCKETS_BY_TABLE:
        supabase.table(table).delete().in_("expedition_id", exp_ids).execute()
    supabase.table("expedition_counties").delete().in_("expedition_id", exp_ids).execute()

    # 刪 expeditions
    supabase.table("expeditions").delete().in_("id", exp_ids).execute()
    print(f"  deleted expeditions: {exp_ids}")

    # 刪所有 expedition_groups
    for gid in group_ids:
        supabase.table("expedition_groups").delete().eq("id", gid).execute()
    print(f"  deleted expedition_groups: {group_ids}")

    # 重置 sync_state
    supabase.table("sync_state").update({"value": PREV_SYNCED_AT}).eq("key", "last_synced_at").execute()
    print(f"  reset sync_state.last_synced_at → {PREV_SYNCED_AT}")

    print("\n清除完成")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    cleanup(dry_run=args.dry_run)
