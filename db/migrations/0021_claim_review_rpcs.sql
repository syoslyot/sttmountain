-- RPCs for staff to list pending claims and approve/reject them.

-- ── 1. list_pending_claims ────────────────────────────────────────────────────
-- Returns all pending leader claims with expedition info and claimant name.
-- Returns empty array if caller is not staff.

create or replace function public.list_pending_claims()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.my_role() <> 'staff' then '[]'::jsonb
    else coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id',              em.id,
            'expedition_id',   em.expedition_id,
            'expedition_name', e.name,
            'date_start',      e.date_start,
            'grade',           e.grade,
            'evidence',        em.evidence,
            'claimant_name',   coalesce(up.nickname, up.name, ''),
            'created_at',      em.created_at
          )
          order by em.created_at asc
        )
        from public.expedition_members em
        join public.expeditions e on e.id = em.expedition_id
        left join public.user_profiles up on up.user_id = em.user_id
        where em.role = 'leader' and em.status = 'pending'
      ),
      '[]'::jsonb
    )
  end;
$$;

grant execute on function public.list_pending_claims()
to authenticated;

-- ── 2. review_expedition_claim ────────────────────────────────────────────────
-- Sets a pending claim's status to 'approved' or 'rejected'.
-- Only callable by staff; raises exception otherwise.

create or replace function public.review_expedition_claim(
  p_claim_id bigint,
  p_action   text  -- 'approved' | 'rejected'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.my_role() <> 'staff' then
    raise exception 'insufficient privileges';
  end if;

  if p_action not in ('approved', 'rejected') then
    raise exception 'invalid action: %', p_action;
  end if;

  update public.expedition_members
  set status = p_action
  where id = p_claim_id
    and role = 'leader'
    and status = 'pending';
end;
$$;

grant execute on function public.review_expedition_claim(bigint, text)
to authenticated;

-- ── 3. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0021_claim_review_rpcs')
on conflict (version) do nothing;
