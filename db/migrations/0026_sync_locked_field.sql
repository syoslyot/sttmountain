-- Add sync_locked flag to expeditions.
-- When true, the daily Google Drive sync script must skip this row.

alter table public.expeditions
  add column if not exists sync_locked bool not null default false;

insert into public.schema_migrations (version)
values ('0026_sync_locked_field')
on conflict (version) do nothing;
