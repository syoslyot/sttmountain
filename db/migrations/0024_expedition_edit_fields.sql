-- Adds editable fields to expeditions that the leader can fill in via the edit page.

alter table public.expeditions
  add column if not exists transport    text,
  add column if not exists keeper       text,
  add column if not exists participants integer;

insert into public.schema_migrations (version)
values ('0024_expedition_edit_fields')
on conflict (version) do nothing;
