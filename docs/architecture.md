# Architecture

`sttmountain` owns the data pipeline and database contract for 成大山協網站. It ingests raw Google Drive files, normalizes them, writes Supabase DB/Storage, and exposes RPC used by frontend consumers.

## System Flow

```text
Google Drive
  -> scripts/sync_drive.py
  -> data/raw/sync_meta.json
  -> scripts/normalize.py
  -> Supabase DB + Storage
  -> sttmountaincrazy website
```

The local FastAPI app in this repo remains available for legacy SSR views and import checks only. The current user-facing website is `sttmountaincrazy`; local website work should run there, typically at `http://localhost:3000`, not this repo's `http://localhost:8000`.

## Repositories

| Repo | Owns |
| --- | --- |
| `sttmountain` | sync scripts, normalize scripts, DB schema, migrations, RPC, storage writes, legacy FastAPI app |
| `sttmountaincrazy` | Next.js user-facing website, map interaction, API redirect routes, frontend deployment |

## Directory Guide

| Path | Purpose |
| --- | --- |
| `app/` | Legacy FastAPI/Jinja app and routes |
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

The `sttmountaincrazy` website depends on public RPC and public Storage URLs. Schema and RPC changes must be implemented here first, applied manually in Supabase, then consumed by website code.

Public data is defined at the DB/RPC boundary. `expeditions.is_public = false` rows remain available to service-role maintenance scripts, but public RPCs and anon table policies must exclude them so hidden expeditions do not appear in rows, filters, or detail views.
