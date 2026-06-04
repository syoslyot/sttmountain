-- Migration 0039: add NULL uid guards to RPCs missed by 0033.
--
-- Vulnerability: in PL/pgSQL, `IF bool AND NULL` evaluates to NULL, which is
-- treated as FALSE, so the IF body is skipped. This means:
--   - update_expedition: IF NOT EXISTS(...) AND my_role() <> 'staff' → NULL → skips RAISE
--     → caller with NULL uid can update any expedition.
--   - review_expedition_claim: IF my_role() <> 'staff' → NULL → skips RAISE
--     → caller with NULL uid can approve/reject any claim.
--   - list_pending_claims: CASE WHEN my_role() <> 'staff' THEN '[]' →
--     NULL falls through to ELSE → returns all pending claims.
--
-- All three are mitigated in practice by `grant execute to authenticated`
-- (anon role can't call them), but defense-in-depth: add explicit NULL checks
-- consistent with what 0033 did for sync_expedition_members/save_expedition_journal.

-- ── update_expedition ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_expedition(
  p_id                   integer,
  p_name                 text,
  p_grade                text,
  p_date_start           date,
  p_date_end             date        DEFAULT NULL,
  p_region_entry_county  text        DEFAULT NULL,
  p_region_entry_town    text        DEFAULT NULL,
  p_region_exit_county   text        DEFAULT NULL,
  p_region_exit_town     text        DEFAULT NULL,
  p_leader_display       text        DEFAULT NULL,
  p_transport            text        DEFAULT NULL,
  p_keeper               text        DEFAULT NULL,
  p_participants         integer     DEFAULT NULL,
  p_sync_locked          bool        DEFAULT TRUE
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

  IF NOT EXISTS (
    SELECT 1 FROM public.expedition_members em
    WHERE em.expedition_id = p_id
      AND em.user_id = auth.uid()
      AND em.role = 'leader'
      AND em.status = 'approved'
  ) AND public.my_role() <> 'staff' THEN
    RAISE EXCEPTION 'insufficient privileges';
  END IF;

  IF NOT p_sync_locked AND public.my_role() <> 'staff' THEN
    RAISE EXCEPTION 'only staff may unlock sync';
  END IF;

  UPDATE public.expeditions SET
    name                 = p_name,
    grade                = p_grade,
    date_start           = p_date_start,
    date_end             = p_date_end,
    region_entry_county  = p_region_entry_county,
    region_entry_town    = p_region_entry_town,
    region_exit_county   = p_region_exit_county,
    region_exit_town     = p_region_exit_town,
    leader_display       = p_leader_display,
    transport            = p_transport,
    keeper               = p_keeper,
    participants         = p_participants,
    sync_locked          = p_sync_locked
  WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer,bool)
TO authenticated;

-- ── review_expedition_claim ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.review_expedition_claim(
  p_claim_id bigint,
  p_action   text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expedition_id bigint;
  v_leader_name   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  IF public.my_role() <> 'staff' THEN
    RAISE EXCEPTION 'insufficient privileges';
  END IF;

  IF p_action NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid action: %', p_action;
  END IF;

  SELECT expedition_id INTO v_expedition_id
  FROM public.expedition_members
  WHERE id = p_claim_id AND role = 'leader' AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'claim not found or already processed';
  END IF;

  UPDATE public.expedition_members
  SET status = p_action
  WHERE id = p_claim_id;

  IF p_action = 'approved' THEN
    SELECT COALESCE(up.name, up.nickname, SPLIT_PART(au.email, '@', 1))
    INTO v_leader_name
    FROM public.expedition_members em
    JOIN public.user_profiles up ON up.user_id = em.user_id
    JOIN auth.users au ON au.id = em.user_id
    WHERE em.id = p_claim_id;

    UPDATE public.expeditions
    SET leader_display = v_leader_name
    WHERE id = v_expedition_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.review_expedition_claim(bigint, text)
TO authenticated;

-- ── list_pending_claims ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.list_pending_claims()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.my_role() <> 'staff' THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',              em.id,
          'expedition_id',   em.expedition_id,
          'expedition_name', e.name,
          'date_start',      e.date_start,
          'grade',           e.grade,
          'evidence',        em.evidence,
          'claimant_name',   COALESCE(up.nickname, up.name, ''),
          'created_at',      em.created_at
        )
        ORDER BY em.created_at ASC
      )
      FROM public.expedition_members em
      JOIN public.expeditions e ON e.id = em.expedition_id
      LEFT JOIN public.user_profiles up ON up.user_id = em.user_id
      WHERE em.role = 'leader' AND em.status = 'pending'
    ),
    '[]'::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_pending_claims()
TO authenticated;

-- ── submit_expedition_claim (add NULL uid guard) ───────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_expedition_claim(
  p_expedition_id integer,
  p_evidence      text DEFAULT NULL
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

  INSERT INTO public.expedition_members (expedition_id, user_id, role, status, evidence)
  VALUES (p_expedition_id, auth.uid(), 'leader', 'pending', p_evidence)
  ON CONFLICT (expedition_id, user_id)
  DO UPDATE SET
    status   = CASE
                 WHEN expedition_members.status = 'rejected' THEN 'pending'
                 ELSE expedition_members.status
               END,
    evidence = CASE
                 WHEN expedition_members.status = 'rejected' THEN excluded.evidence
                 ELSE expedition_members.evidence
               END
  WHERE expedition_members.status = 'rejected';
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_expedition_claim(integer, text)
TO authenticated;

-- ── record migration ───────────────────────────────────────────────────────────

INSERT INTO public.schema_migrations (version)
VALUES ('0039_fix_null_uid_remaining_rpcs')
ON CONFLICT (version) DO NOTHING;
