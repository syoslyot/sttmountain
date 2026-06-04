-- Migration 0036: enforce one row per (expedition_id, user_id) in expedition_members
-- First, remove duplicate rows, keeping the leader row if present, else the earliest row.

DELETE FROM expedition_members
WHERE id NOT IN (
  SELECT DISTINCT ON (expedition_id, user_id) id
  FROM expedition_members
  ORDER BY
    expedition_id,
    user_id,
    CASE role WHEN 'leader' THEN 0 ELSE 1 END,
    created_at ASC
);

-- Now add the constraint to prevent future duplicates.
ALTER TABLE expedition_members
  ADD CONSTRAINT expedition_members_expedition_user_unique
  UNIQUE (expedition_id, user_id);
