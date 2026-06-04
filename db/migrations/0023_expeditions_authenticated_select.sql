-- Allows authenticated users to read public expeditions.
-- The existing "anon select" policy only covers the anon role; authenticated
-- users (logged-in members) were being blocked by RLS when joining expeditions
-- from expedition_members, causing expedition data to return null.

create policy "authenticated select public expeditions"
  on public.expeditions
  for select
  to authenticated
  using (is_public is true);

insert into public.schema_migrations (version)
values ('0023_expeditions_authenticated_select')
on conflict (version) do nothing;
