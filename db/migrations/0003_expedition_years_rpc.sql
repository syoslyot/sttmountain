create table if not exists public.schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);

create or replace function public.get_expedition_years()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(json_agg(year order by year desc), '[]'::json)
  from (
    select distinct extract(year from date_start)::int as year
    from public.expeditions
    where date_start is not null
  ) years;
$$;

grant execute on function public.get_expedition_years()
to anon, authenticated;

insert into public.schema_migrations (version)
values ('0003_expedition_years_rpc')
on conflict (version) do nothing;
