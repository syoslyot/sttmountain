-- Migration 0034: fix get_expedition_members sort order → 領隊 > 嚮導 > 隊員 > 新生

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
  ORDER BY
    CASE em.role WHEN 'leader' THEN 0 ELSE 1 END,
    CASE em.expedition_role
      WHEN '嚮導' THEN 0
      WHEN '隊員' THEN 1
      WHEN '新生' THEN 2
      ELSE 3
    END,
    em.created_at;
$$;

GRANT EXECUTE ON FUNCTION get_expedition_members(bigint) TO authenticated, anon;
