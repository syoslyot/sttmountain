-- Migration 0033: fix NULL uid bypassing auth check in edit RPCs
-- When auth.uid() IS NULL, plpgsql treats IF NOT (... OR NULL) as IF NULL → skips RAISE.
-- Fix: explicitly check uid IS NULL first.

-- ── sync_expedition_members ────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_expedition_members(
  p_expedition_id bigint,
  p_members       jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1 FROM expedition_members
      WHERE expedition_id = p_expedition_id
        AND user_id = auth.uid()
        AND role = 'leader'
        AND status = 'approved'
    ) OR public.my_role() = 'staff'
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  DELETE FROM expedition_members
  WHERE expedition_id = p_expedition_id AND role = 'member';

  INSERT INTO expedition_members
    (expedition_id, user_id, role, expedition_role, can_edit, status)
  SELECT
    p_expedition_id,
    (m->>'user_id')::uuid,
    'member',
    m->>'expedition_role',
    (m->>'can_edit')::boolean,
    'approved'
  FROM jsonb_array_elements(p_members) m
  WHERE m->>'user_id' IS NOT NULL;
END;
$$;

-- ── save_expedition_journal ────────────────────────────────────────
CREATE OR REPLACE FUNCTION save_expedition_journal(
  p_expedition_id bigint,
  p_blocks        jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1 FROM expedition_members
      WHERE expedition_id = p_expedition_id
        AND user_id = auth.uid()
        AND role = 'leader'
        AND status = 'approved'
    ) OR EXISTS (
      SELECT 1 FROM expedition_members
      WHERE expedition_id = p_expedition_id
        AND user_id = auth.uid()
        AND can_edit = true
        AND status = 'approved'
    ) OR public.my_role() = 'staff'
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  UPDATE expeditions
  SET journal_blocks = p_blocks
  WHERE id = p_expedition_id;
END;
$$;
