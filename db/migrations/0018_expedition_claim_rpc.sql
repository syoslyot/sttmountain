-- Adds evidence column to expedition_members for claim submissions,
-- and creates submit_expedition_claim RPC for the /claim page.

-- ── 1. Add evidence column ────────────────────────────────────────────────────

alter table public.expedition_members
  add column if not exists evidence text;

-- ── 2. RPC ────────────────────────────────────────────────────────────────────

-- Inserts a pending leader membership (claim) for the calling user.
-- SECURITY DEFINER ensures user_id is injected from auth.uid(), not from the caller.
create or replace function public.submit_expedition_claim(
  p_expedition_id integer,
  p_evidence      text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.expedition_members (expedition_id, user_id, role, status, evidence)
  values (p_expedition_id, auth.uid(), 'leader', 'pending', p_evidence);
end;
$$;

grant execute on function public.submit_expedition_claim(integer, text)
to authenticated;

-- ── 3. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0018_expedition_claim_rpc')
on conflict (version) do nothing;
