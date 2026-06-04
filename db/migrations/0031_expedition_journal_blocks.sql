-- Migration 0031: journal_blocks storage + save_expedition_journal RPC

-- ── 1. 新增欄位 ────────────────────────────────────────────────────
ALTER TABLE expeditions
  ADD COLUMN IF NOT EXISTS journal_blocks jsonb NOT NULL DEFAULT '[]'::jsonb;

-- ── 2. save_expedition_journal ─────────────────────────────────────
-- 允許 approved leader 或 can_edit=true 的成員，以及 staff 儲存圖文
CREATE OR REPLACE FUNCTION save_expedition_journal(
  p_expedition_id bigint,
  p_blocks        jsonb
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
      SELECT 1 FROM expedition_members
      WHERE expedition_id = p_expedition_id
        AND user_id = auth.uid()
        AND can_edit = true
        AND status = 'approved'
    ) OR EXISTS (
      SELECT 1 FROM user_profiles
      WHERE user_id = auth.uid() AND role = 'staff'
    )
  ) THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  UPDATE expeditions
  SET journal_blocks = p_blocks
  WHERE id = p_expedition_id;
END;
$$;
