-- Migration 0032: fix edit RPCs — add set search_path, grant execute, use my_role()

-- ── get_expedition_members ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_expedition_members(p_expedition_id bigint)
RETURNS TABLE (
  user_id         uuid,
  role            text,
  expedition_role text,
  can_edit        boolean,
  name            text,
  nickname        text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    em.user_id,
    em.role,
    em.expedition_role,
    em.can_edit,
    up.name,
    up.nickname
  FROM expedition_members em
  LEFT JOIN user_profiles up ON up.user_id = em.user_id
  WHERE em.expedition_id = p_expedition_id
    AND em.status = 'approved'
  ORDER BY em.role DESC, em.created_at;
$$;

GRANT EXECUTE ON FUNCTION get_expedition_members(bigint) TO authenticated, anon;

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

GRANT EXECUTE ON FUNCTION sync_expedition_members(bigint, jsonb) TO authenticated;

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

GRANT EXECUTE ON FUNCTION save_expedition_journal(bigint, jsonb) TO authenticated;
