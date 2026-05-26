# Troubleshooting

## Migration Fails: `schema_migrations` Does Not Exist

Use a migration that bootstraps the table:

```sql
create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);

alter table public.schema_migrations enable row level security;
```

Then rerun the migration recording statement.

## Supabase Warns About RLS

Enable RLS for tables created by migrations unless there is a deliberate reason not to:

```sql
alter table public.schema_migrations enable row level security;
```

## Frontend Year Filter Only Shows ALL

Check:

- `get_expedition_years()` exists in the target DB.
- The function grant includes `anon` and `authenticated`.
- The frontend points to the expected Supabase project.
- There are expedition rows with non-null `date_start`.

## Sync Downloads Nothing

Check:

- `GDRIVE_ROOT_FOLDER_ID` points to the expected root.
- Service Account has access to the folder.
- Target folders were created after the configured cutoff date.
- `sync_state.last_synced_at` is not newer than the test folder.

## Normalize Fails on Spreadsheet

Check:

- file name contains `直企`;
- expected cells exist on P1;
- ROC dates are parseable;
- LibreOffice can open the file in headless mode.

## GitHub Actions Checkout 403

If logs show `Your account is suspended`, the runner cannot fetch the repository. This is not a Python or SQL failure. Resolve GitHub account/repository access first, then rerun the workflow.
