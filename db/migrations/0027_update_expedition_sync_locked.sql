-- Extend update_expedition to carry sync_locked.
-- Non-staff callers always lock (p_sync_locked defaults to true).
-- Only staff may pass false to re-enable Google Drive sync for a row.

drop function if exists public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer);

create or replace function public.update_expedition(
  p_id                   integer,
  p_name                 text,
  p_grade                text,
  p_date_start           date,
  p_date_end             date        default null,
  p_region_entry_county  text        default null,
  p_region_entry_town    text        default null,
  p_region_exit_county   text        default null,
  p_region_exit_town     text        default null,
  p_leader_display       text        default null,
  p_transport            text        default null,
  p_keeper               text        default null,
  p_participants         integer     default null,
  p_sync_locked          bool        default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.expedition_members em
    where em.expedition_id = p_id
      and em.user_id = auth.uid()
      and em.role = 'leader'
      and em.status = 'approved'
  ) and public.my_role() <> 'staff' then
    raise exception 'insufficient privileges';
  end if;

  if not p_sync_locked and public.my_role() <> 'staff' then
    raise exception 'only staff may unlock sync';
  end if;

  update public.expeditions set
    name                 = p_name,
    grade                = p_grade,
    date_start           = p_date_start,
    date_end             = p_date_end,
    region_entry_county  = p_region_entry_county,
    region_entry_town    = p_region_entry_town,
    region_exit_county   = p_region_exit_county,
    region_exit_town     = p_region_exit_town,
    leader_display       = p_leader_display,
    transport            = p_transport,
    keeper               = p_keeper,
    participants         = p_participants,
    sync_locked          = p_sync_locked
  where id = p_id;
end;
$$;

grant execute on function public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer,bool)
to authenticated;

insert into public.schema_migrations (version)
values ('0027_update_expedition_sync_locked')
on conflict (version) do nothing;
