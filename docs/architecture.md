# Architecture

`sttmountain` owns the data pipeline and database contract. It ingests raw Google Drive files, normalizes them, writes Supabase DB/Storage, and exposes RPC used by frontend consumers.

## System Flow

```text
Google Drive
  -> scripts/sync_drive.py
  -> data/raw/sync_meta.json
  -> scripts/normalize.py
  -> Supabase DB + Storage
  -> sttmountaincrazy frontend
```

The local FastAPI app remains available for legacy SSR views and import checks, but the production user-facing frontend is `sttmountaincrazy`.

## Repositories

| Repo | Owns |
| --- | --- |
| `sttmountain` | sync scripts, normalize scripts, DB schema, migrations, RPC, storage writes |
| `sttmountaincrazy` | Next.js UI, map interaction, API redirect routes, frontend deployment |

## Directory Guide

| Path | Purpose |
| --- | --- |
| `app/` | FastAPI/Jinja app and legacy routes |
| `scripts/sync_drive.py` | Google Drive metadata scan and raw file download |
| `scripts/normalize.py` | Parse downloaded files and upsert Supabase rows |
| `scripts/cleanup_dev_test.py` | Explicit reset/resync helper for dev/prod |
| `db/schema.sql` | Full current schema for fresh DB setup |
| `db/migrations/` | Ordered SQL changes for existing DBs |
| `docs/database.md` | DB workflow and frontend RPC contract |

## Environments

| Context | Env file | Target |
| --- | --- | --- |
| Local dev | `.env.local` | dev Supabase |
| Local prod operation | `.env` | prod Supabase |
| GitHub Actions manual/scheduled sync | GitHub Secrets | dev or prod based on workflow input |

Use `ENV_FILE` explicitly when running scripts locally.

## Data Contract

The frontend depends on public RPC and public Storage URLs. Schema and RPC changes must be implemented here first, applied manually in Supabase, then consumed by frontend code.
