-- Migration 0038: tighten expedition_members INSERT RLS
--
-- VULNERABILITY: The original "user insert own membership" policy only checked
-- auth.uid() = user_id, allowing any authenticated user to directly INSERT a row
-- with role='leader', status='approved', can_edit=true — bypassing the entire
-- claim + staff review flow and granting themselves edit access to any expedition.
--
-- FIX: Restrict direct inserts to leader-claim submissions only
-- (role='leader', status='pending', can_edit=false).
-- Member additions go through sync_expedition_members (SECURITY DEFINER),
-- and claim submissions go through submit_expedition_claim (SECURITY DEFINER),
-- both of which bypass RLS and are unaffected by this change.

DROP POLICY IF EXISTS "user insert own membership" ON public.expedition_members;

CREATE POLICY "user insert own membership" ON public.expedition_members
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND role = 'leader'
    AND status = 'pending'
    AND can_edit = false
  );

INSERT INTO public.schema_migrations (version)
VALUES ('0038_fix_member_insert_rls')
ON CONFLICT (version) DO NOTHING;
