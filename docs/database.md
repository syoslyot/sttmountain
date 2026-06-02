# Database Workflow

`sttmountain` is the source of truth for Supabase schema, migrations, and sync
scripts. `sttmountaincrazy` is a frontend consumer and should not own database
SQL.

## Terms

Migration means a versioned SQL change that moves a database from one known
schema state to the next. Example: adding `expeditions.grade`, creating
`list_expeditions()`, or changing grants.

The key point is that the same migration file is applied to dev first and prod
second, so both databases stay aligned.

## Files

| Path | Purpose |
| --- | --- |
| `db/schema.sql` | Full current schema for creating a fresh database. |
| `db/migrations/*.sql` | Ordered changes for existing databases. Apply in filename order. |
| `schema_migrations` | DB table that records which migration versions have been applied. |
| `scripts/sync_drive.py` | Downloads Google Drive files and writes `data/raw/sync_meta.json`. |
| `scripts/normalize.py` | Parses `sync_meta.json`, writes DB rows, uploads storage files. |
| `scripts/cleanup_dev_test.py` | Explicit dev/prod reset tool for DB and storage. |

## Schema Overview

| Table | Purpose |
| --- | --- |
| `expedition_groups` | Activity/group container. Group activities share one row; solo expeditions get their own group. |
| `expeditions` | Main expedition rows: name, dates, regions, leader, grade, preview image. |
| `expedition_counties` | Counties indexed for entry/exit region filtering. |
| `gpx_files` | GPX/KML Storage file metadata. |
| `map_files` | Map PDF/image Storage file metadata. |
| `records` | Submitted record metadata and extracted text/file path. |
| `sync_state` | Stores sync cursor such as `last_synced_at`. |
| `sync_logs` | Sync run status, counts, errors, and log text. |
| `schema_migrations` | Records manually applied SQL migration versions. |
| `user_profiles` | Member role and display name, linked to `auth.users`. See [membership.md](membership.md). |

## Storage Buckets

| Bucket | Contents |
| --- | --- |
| `gpx` | GPX / KML track files |
| `maps` | Map PDFs and images |
| `previews` | Expedition plan preview images |
| `records` | Original submitted record files |

## RLS and Access

All application tables should have RLS enabled. Public list reads go through `SECURITY DEFINER` RPC functions, while sync scripts use the Supabase service role key for writes.

Do not expose `SUPABASE_SERVICE_KEY` to frontend code or public logs.

## Environment files

Local convention:

| Target | Env file |
| --- | --- |
| dev Supabase | `.env.local` |
| prod Supabase | `.env` |

Both files must contain:

```text
SUPABASE_URL=...
SUPABASE_SERVICE_KEY=...
```

`SUPABASE_SERVICE_KEY` is a server-only secret. Do not put it in frontend code or
commit it to git.

## Applying migrations

1. Create a new SQL file under `db/migrations/`, using the next number:

   ```text
   db/migrations/0003_short_description.sql
   ```

2. Write idempotent SQL where possible:

   ```sql
   alter table public.records add column if not exists file_path text;
   create index if not exists records_expedition_id_idx on public.records (expedition_id);
   ```

3. Keep `schema_migrations` protected by RLS when bootstrapping a database:

   ```sql
   alter table public.schema_migrations enable row level security;
   ```

4. End the migration by recording it:

   ```sql
   insert into public.schema_migrations (version)
   values ('0003_short_description')
   on conflict (version) do nothing;
   ```

5. Apply the migration to dev in Supabase SQL Editor.

6. Verify dev:

   ```bash
   ENV_FILE=.env.local python3 scripts/sync_drive.py
   ENV_FILE=.env.local python3 scripts/normalize.py
   ```

7. Apply the same migration file to prod.

8. Verify prod:

   ```bash
   ENV_FILE=.env python3 scripts/sync_drive.py
   ENV_FILE=.env python3 scripts/normalize.py
   ```

9. Commit the migration and any matching script/frontend changes in PRs.

Check applied migrations:

```sql
select version, applied_at
from public.schema_migrations
order by version;
```

Do not patch only prod. If an emergency SQL hotfix is run in prod, add the same
SQL as a migration immediately afterward and apply it to dev.

## Reset and full resync

Dry-run first:

```bash
python3 scripts/cleanup_dev_test.py --target dev --env-file .env.local --dry-run --local-cache
python3 scripts/cleanup_dev_test.py --target prod --env-file .env --dry-run
```

Reset and resync:

```bash
python3 scripts/cleanup_dev_test.py --target dev --env-file .env.local --yes --local-cache
ENV_FILE=.env.local python3 scripts/sync_drive.py
ENV_FILE=.env.local python3 scripts/normalize.py

python3 scripts/cleanup_dev_test.py --target prod --env-file .env --yes
ENV_FILE=.env python3 scripts/sync_drive.py
ENV_FILE=.env python3 scripts/normalize.py
```

## Frontend contract

`sttmountaincrazy` depends on these public RPC contracts:

```text
list_expeditions(p_q, p_county, p_counties, p_start, p_end, p_page, p_page_size, p_grade, p_sort)
get_expedition_dates()
get_expedition_years()
```

### `list_expeditions()`

`list_expeditions()` returns:

```text
{ expeditions, total, page, pageSize }
```

Each expedition row includes:

```text
id, name, grade, date_start, date_end,
region_entry_county, region_entry_town,
region_exit_county, region_exit_town,
leader, preview_image,
gpx_count, map_count, rec_count
```

### `get_expedition_dates()`

`get_expedition_dates()` returns the available expedition date range:

```text
{ min_date, max_date }
```

### `get_expedition_years()`

`get_expedition_years()` returns only years that have at least one expedition:

```text
[2026, 2024]
```

Do not synthesize missing intermediate years in the frontend.

## Public Visibility

`expeditions.is_public` controls whether an expedition is exposed publicly.

- Default is `true`.
- `list_expeditions()`, `get_expedition_dates()`, and `get_expedition_years()` only use public expeditions.
- Anon RLS policies for expeditions and related file tables only expose rows connected to public expeditions.
- Sync and maintenance scripts use service role and may still read/write hidden rows when needed.

Use `is_public = false` for historical incomplete rows, canceled teams, or mistakenly imported expeditions that should stay in DB but disappear from public output and filters.

## Grade Normalization

`grade` is parsed from the expedition name prefix by DB trigger logic. Example:

```text
[5C活] 嘉明湖會師-布拉克桑線 20240710 -> C
```

Schema or RPC changes required by the frontend must be implemented here first,
then consumed by `sttmountaincrazy`.
