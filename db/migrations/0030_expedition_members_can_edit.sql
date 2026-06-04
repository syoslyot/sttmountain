-- Migration 0030: expedition_members — add expedition_role, can_edit; add RPCs

-- ── 1. 新增欄位 ────────────────────────────────────────────────────
ALTER TABLE expedition_members
  ADD COLUMN IF NOT EXISTS expedition_role text,
  ADD COLUMN IF NOT EXISTS can_edit boolean NOT NULL DEFAULT false;

-- ── 2. get_expedition_members ──────────────────────────────────────
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
SECURITY DEFINER
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

-- ── 3. sync_expedition_members ─────────────────────────────────────
-- 取代所有非 leader 成員；只有 approved leader 或 staff 可呼叫
CREATE OR REPLACE FUNCTION sync_expedition_members(
  p_expedition_id bigint,
  p_members       jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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
      SELECT 1 FROM user_profiles
      WHERE user_id = auth.uid() AND role = 'staff'
    )
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
