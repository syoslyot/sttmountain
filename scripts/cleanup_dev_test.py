"""
Reset Supabase expedition data and storage before a full Google Drive resync.

Usage:
  python3 scripts/cleanup_dev_test.py --dry-run
  python3 scripts/cleanup_dev_test.py --yes --target dev
  python3 scripts/cleanup_dev_test.py --yes --target prod

Environment:
  SUPABASE_URL
  SUPABASE_SERVICE_KEY
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

EPOCH = "1970-01-01T00:00:00+00:00"
DATA_TABLES = [
    "records",
    "map_files",
    "gpx_files",
    "expedition_counties",
    "expeditions",
    "expedition_groups",
]
STORAGE_BUCKETS = ["records", "maps", "gpx", "previews"]
LOCAL_CACHE_DIRS = [
    Path("data/raw/xlsx"),
    Path("data/raw/txt"),
    Path("app/static/gpx"),
    Path("app/static/maps"),
    Path("app/static/previews"),
]


def env_project_ref(url: str) -> str:
    return url.removeprefix("https://").split(".")[0]


def load_env(env_file: str) -> None:
    load_dotenv()
    load_dotenv(env_file, override=True)


def require_client():
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY are required")
    return create_client(url, key), url


def count_table(sb, table: str) -> int:
    res = sb.table(table).select("*", count="exact").limit(0).execute()
    return res.count or 0


def clear_table(sb, table: str, dry_run: bool) -> None:
    count = count_table(sb, table)
    print(f"  {table}: {count} rows")
    if dry_run or count == 0:
        return
    if table == "sync_state":
        sb.table(table).delete().neq("key", "").execute()
    else:
        sb.table(table).delete().gt("id", 0).execute()


def list_bucket_paths(storage, bucket: str, prefix: str = "") -> list[str]:
    try:
        items = storage.from_(bucket).list(prefix)
    except Exception as e:
        print(f"  {bucket}: cannot list ({e})")
        return []

    paths: list[str] = []
    for item in items:
        name = item.get("name")
        if not name:
            continue
        path = f"{prefix}/{name}" if prefix else name
        if item.get("id") is None:
            paths.extend(list_bucket_paths(storage, bucket, path))
        else:
            paths.append(path)
    return paths


def remove_bucket_paths(storage, bucket: str, paths: list[str], dry_run: bool) -> None:
    print(f"  {bucket}: {len(paths)} objects")
    if dry_run:
        return
    for i in range(0, len(paths), 100):
        chunk = paths[i:i + 100]
        if chunk:
            storage.from_(bucket).remove(chunk)


def clear_local_cache(dry_run: bool) -> None:
    print("\n=== Local cache ===")
    for base in LOCAL_CACHE_DIRS:
        if not base.exists():
            print(f"  {base}: missing")
            continue
        paths = [p for p in base.iterdir() if p.name != ".gitkeep"]
        print(f"  {base}: {len(paths)} entries")
        if dry_run:
            continue
        for path in paths:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()


def reset_sync_state(sb, dry_run: bool) -> None:
    print("\n=== Sync state ===")
    print(f"  last_synced_at -> {EPOCH}")
    if dry_run:
        return
    sb.table("sync_state").upsert(
        {"key": "last_synced_at", "value": EPOCH},
        on_conflict="key",
    ).execute()


def cleanup(target: str, env_file: str, dry_run: bool, yes: bool, local_cache: bool) -> None:
    load_env(env_file)
    sb, url = require_client()
    project_ref = env_project_ref(url)

    print(f"Target: {target}")
    print(f"Env file: {env_file}")
    print(f"Supabase project: {project_ref}")
    print(f"Mode: {'dry-run' if dry_run else 'DELETE'}")
    if not dry_run and not yes:
        raise SystemExit("Refusing to delete without --yes")

    print("\n=== Storage ===")
    for bucket in STORAGE_BUCKETS:
        paths = list_bucket_paths(sb.storage, bucket)
        remove_bucket_paths(sb.storage, bucket, paths, dry_run)

    print("\n=== Data tables ===")
    for table in DATA_TABLES:
        clear_table(sb, table, dry_run)

    print("\n=== Sync logs ===")
    clear_table(sb, "sync_logs", dry_run)
    reset_sync_state(sb, dry_run)

    if local_cache:
        clear_local_cache(dry_run)

    print("\nDone")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=["dev", "prod"], required=True)
    parser.add_argument("--env-file", required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--local-cache", action="store_true")
    args = parser.parse_args()
    cleanup(
        target=args.target,
        env_file=args.env_file,
        dry_run=args.dry_run,
        yes=args.yes,
        local_cache=args.local_cache,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"cleanup failed: {e}", file=sys.stderr)
        sys.exit(1)
