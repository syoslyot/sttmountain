-- Rename member_role enum values to better reflect club terminology.
--
-- partner  → associate  (繳費的基本會員)
-- newcomer → cadet      (在訓、尚未通過隊員考試)
-- member   → ranger     (通過考試的正式隊員)
-- staff    → curator    (資料組，負責維護記錄與審核)

-- ── Step 1: Rename enum values ────────────────────────────────────────────────
-- Existing rows in user_profiles.role are automatically updated by PostgreSQL.

ALTER TYPE public.member_role RENAME VALUE 'partner'  TO 'associate';
ALTER TYPE public.member_role RENAME VALUE 'newcomer' TO 'cadet';
ALTER TYPE public.member_role RENAME VALUE 'member'   TO 'ranger';
ALTER TYPE public.member_role RENAME VALUE 'staff'    TO 'curator';

-- ── Step 2: Recreate RLS policies that reference old role strings ──────────────

-- user_profiles
DROP POLICY IF EXISTS "staff select all" ON public.user_profiles;
CREATE POLICY "curator select all" ON public.user_profiles
  FOR SELECT USING (public.my_role() = 'curator');

DROP POLICY IF EXISTS "staff insert" ON public.user_profiles;
CREATE POLICY "curator insert" ON public.user_profiles
  FOR INSERT WITH CHECK (public.my_role() = 'curator');

DROP POLICY IF EXISTS "staff update" ON public.user_profiles;
CREATE POLICY "curator update" ON public.user_profiles
  FOR UPDATE USING (public.my_role() = 'curator');

-- expedition_members
DROP POLICY IF EXISTS "staff select all memberships" ON public.expedition_members;
CREATE POLICY "curator select all memberships" ON public.expedition_members
  FOR SELECT USING (public.my_role() = 'curator');

DROP POLICY IF EXISTS "staff update membership" ON public.expedition_members;
CREATE POLICY "curator update membership" ON public.expedition_members
  FOR UPDATE USING (public.my_role() = 'curator');

-- ── Step 3: Recreate functions that reference old role strings ─────────────────

-- handle_new_user: newcomer → cadet (latest version from 0041)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _name       text;
  _avatar_url text;
BEGIN
  _name       := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
  _avatar_url := coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture');
  INSERT INTO public.user_profiles (user_id, role, name, avatar_url, email, joined_at, provider_meta)
  VALUES (new.id, 'cadet', _name, _avatar_url, new.email, current_date, new.raw_user_meta_data)
  ON CONFLICT (user_id) DO UPDATE SET
    name          = coalesce(public.user_profiles.name,          excluded.name),
    avatar_url    = coalesce(public.user_profiles.avatar_url,    excluded.avatar_url),
    email         = coalesce(public.user_profiles.email,         excluded.email),
    provider_meta = coalesce(public.user_profiles.provider_meta, excluded.provider_meta);
  RETURN new;
END;
$$;

-- update_expedition: staff → curator (latest from 0039)
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
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.expedition_members em
    WHERE em.expedition_id = p_id AND em.user_id = auth.uid()
      AND em.role = 'leader' AND em.status = 'approved'
  ) AND public.my_role() <> 'curator' THEN
    RAISE EXCEPTION 'insufficient privileges';
  END IF;
  IF NOT p_sync_locked AND public.my_role() <> 'curator' THEN
    RAISE EXCEPTION 'only curator may unlock sync';
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
GRANT EXECUTE ON FUNCTION public.update_expedition(integer,text,text,date,date,text,text,text,text,text,text,text,integer,bool) TO authenticated;

-- review_expedition_claim: staff → curator (latest from 0039)
CREATE OR REPLACE FUNCTION public.review_expedition_claim(p_claim_id bigint, p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_expedition_id bigint;
  v_leader_name   text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF public.my_role() <> 'curator' THEN RAISE EXCEPTION 'insufficient privileges'; END IF;
  IF p_action NOT IN ('approved', 'rejected') THEN RAISE EXCEPTION 'invalid action: %', p_action; END IF;
  SELECT expedition_id INTO v_expedition_id
  FROM public.expedition_members
  WHERE id = p_claim_id AND role = 'leader' AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'claim not found or already processed'; END IF;
  UPDATE public.expedition_members SET status = p_action WHERE id = p_claim_id;
  IF p_action = 'approved' THEN
    SELECT COALESCE(up.name, up.nickname, SPLIT_PART(au.email, '@', 1))
    INTO v_leader_name
    FROM public.expedition_members em
    JOIN public.user_profiles up ON up.user_id = em.user_id
    JOIN auth.users au ON au.id = em.user_id
    WHERE em.id = p_claim_id;
    UPDATE public.expeditions SET leader_display = v_leader_name WHERE id = v_expedition_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.review_expedition_claim(bigint, text) TO authenticated;

-- list_pending_claims: staff → curator (latest from 0039)
CREATE OR REPLACE FUNCTION public.list_pending_claims()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR public.my_role() <> 'curator' THEN RETURN '[]'::jsonb; END IF;
  RETURN COALESCE(
    (SELECT jsonb_agg(jsonb_build_object(
        'id',              em.id,
        'expedition_id',   em.expedition_id,
        'expedition_name', e.name,
        'date_start',      e.date_start,
        'grade',           e.grade,
        'evidence',        em.evidence,
        'claimant_name',   COALESCE(up.nickname, up.name, ''),
        'created_at',      em.created_at
      ) ORDER BY em.created_at ASC)
    FROM public.expedition_members em
    JOIN public.expeditions e ON e.id = em.expedition_id
    LEFT JOIN public.user_profiles up ON up.user_id = em.user_id
    WHERE em.role = 'leader' AND em.status = 'pending'),
    '[]'::jsonb
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_pending_claims() TO authenticated;

-- list_member_profiles: staff → curator (from 0040)
CREATE OR REPLACE FUNCTION public.list_member_profiles()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN '[]'::jsonb
    WHEN public.my_role() = 'curator' OR EXISTS (
      SELECT 1 FROM public.expedition_members
      WHERE user_id = auth.uid() AND role = 'leader' AND status = 'approved'
    )
    THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id', user_id, 'name', name, 'nickname', nickname) ORDER BY name NULLS LAST), '[]'::jsonb) FROM public.user_profiles)
    ELSE '[]'::jsonb
  END
$$;
GRANT EXECUTE ON FUNCTION public.list_member_profiles() TO authenticated;

-- sync_expedition_members: staff → curator (from 0040)
CREATE OR REPLACE FUNCTION sync_expedition_members(p_expedition_id bigint, p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (
    EXISTS (SELECT 1 FROM expedition_members WHERE expedition_id = p_expedition_id AND user_id = auth.uid() AND role = 'leader' AND status = 'approved')
    OR public.my_role() = 'curator'
  ) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  DELETE FROM expedition_members WHERE expedition_id = p_expedition_id AND role = 'member';
  INSERT INTO expedition_members (expedition_id, user_id, role, expedition_role, can_edit, status)
  SELECT p_expedition_id, (m->>'user_id')::uuid, 'member', m->>'expedition_role', (m->>'can_edit')::boolean, 'approved'
  FROM jsonb_array_elements(p_members) m WHERE m->>'user_id' IS NOT NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION sync_expedition_members(bigint, jsonb) TO authenticated;

-- save_expedition_journal: staff → curator (from 0040)
CREATE OR REPLACE FUNCTION save_expedition_journal(p_expedition_id bigint, p_blocks jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (
    EXISTS (SELECT 1 FROM expedition_members WHERE expedition_id = p_expedition_id AND user_id = auth.uid() AND role = 'leader' AND status = 'approved') OR
    EXISTS (SELECT 1 FROM expedition_members WHERE expedition_id = p_expedition_id AND user_id = auth.uid() AND can_edit = true AND status = 'approved') OR
    public.my_role() = 'curator'
  ) THEN RAISE EXCEPTION 'unauthorized'; END IF;
  UPDATE expeditions SET journal_blocks = p_blocks WHERE id = p_expedition_id;
END;
$$;
GRANT EXECUTE ON FUNCTION save_expedition_journal(bigint, jsonb) TO authenticated;

-- ── Record migration ───────────────────────────────────────────────────────────

INSERT INTO public.schema_migrations (version)
VALUES ('0042_rename_member_roles')
ON CONFLICT (version) DO NOTHING;
