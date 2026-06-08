-- Replaces the open "user update own profile" RLS policy with a SECURITY DEFINER
-- function that only allows updating name, nickname, and contact.
-- This prevents users from escalating their own role via direct REST API calls.

-- ── 1. Remove the open RLS update policy ──────────────────────────────────────

drop policy if exists "user update own profile" on public.user_profiles;

-- ── 2. SECURITY DEFINER function: only exposes safe fields ────────────────────

create or replace function public.update_own_profile(
  p_name     text,
  p_nickname text,
  p_contact  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_profiles
  set
    name     = p_name,
    nickname = p_nickname,
    contact  = p_contact
  where user_id = auth.uid();
end;
$$;

grant execute on function public.update_own_profile(text, text, text) to authenticated;

-- ── 3. SECURITY DEFINER function: avatar update ───────────────────────────────
-- Storage SDK handles the file upload; this only writes the resulting public URL.

create or replace function public.update_own_avatar(p_avatar_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_profiles
  set avatar_url = p_avatar_url
  where user_id = auth.uid();
end;
$$;

grant execute on function public.update_own_avatar(text) to authenticated;

-- ── 4. Record migration ───────────────────────────────────────────────────────

insert into public.schema_migrations (version)
values ('0015_secure_profile_update')
on conflict (version) do nothing;
