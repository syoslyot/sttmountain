-- RPC for the edit page. Caller must be the approved leader or staff.

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
  p_participants         integer     default null
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
    participants         = p_participants
  where id = p_id;
end;
$$;

grant execute on function public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer)
to authenticated;

insert into public.schema_migrations (version)
values ('0025_update_expedition_rpc')
on conflict (version) do nothing;
