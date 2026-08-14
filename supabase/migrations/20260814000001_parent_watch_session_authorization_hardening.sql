-- ============================================================================
-- Migration: 20260814000001_parent_watch_session_authorization_hardening.sql
-- Description: CRIT-17 & CRIT-18 Security Hardening
--              - CRIT-17: Strict Role Validation on Parent-Child Links (No Admin Bypass)
--                + Trigger check to guarantee child_id profile role = 'child'
--              - CRIT-18: Server-Side Shared Authorization Policy & Secure
--                start_watch_session() with Active Session Deduplication
-- ============================================================================

-- ============================================================================
-- 1. INTERNAL HELPER: check_child_video_play_policy (CRIT-18)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_child_video_play_policy(
  p_user_id UUID,
  p_video_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_role TEXT := 'guest';
  v_video RECORD;
  v_settings RECORD;
  v_has_settings BOOLEAN := FALSE;
  v_now_time_str TEXT;
  v_today_watched_seconds BIGINT := 0;
  v_today_start TIMESTAMPTZ;
BEGIN
  -- 1. Check video existence
  IF p_video_id IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'VIDEO_NOT_FOUND',
      'message', 'Video kimliği belirtilmedi.'
    );
  END IF;

  SELECT id, title, category_id, is_deleted INTO v_video
  FROM public.videos
  WHERE id = p_video_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'VIDEO_NOT_FOUND',
      'message', 'İstenen video sistemde bulunamadı.'
    );
  END IF;

  IF v_video.is_deleted = TRUE THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'VIDEO_DELETED',
      'message', 'Bu video artık yayında değil.'
    );
  END IF;

  -- If guest (unauthenticated), allow public video viewing unless login is enforced
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- 2. Check user role
  SELECT role INTO v_user_role FROM public.profiles WHERE id = p_user_id;

  IF v_user_role IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'NOT_AUTHENTICATED',
      'message', 'Kullanıcı profili bulunamadı.'
    );
  END IF;

  -- Parents and Admins have unrestricted access
  IF v_user_role IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- Publishers cannot watch on behalf of child or bypass rules
  IF v_user_role = 'publisher' THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- 3. Locate parental settings for this child
  -- Strategy A: From linked parent in parent_children
  SELECT ps.* INTO v_settings
  FROM public.parent_settings ps
  JOIN public.parent_children pc ON pc.parent_id = ps.user_id
  WHERE pc.child_id = p_user_id
  ORDER BY ps.updated_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_has_settings := TRUE;
  ELSE
    -- Strategy B: Shared account / single profile fallback
    SELECT * INTO v_settings
    FROM public.parent_settings
    WHERE user_id = p_user_id;

    IF FOUND THEN
      v_has_settings := TRUE;
    END IF;
  END IF;

  -- If settings exist, enforce rules strictly
  IF v_has_settings THEN
    -- A) Category Restriction Check
    IF v_settings.allowed_categories IS NOT NULL AND array_length(v_settings.allowed_categories, 1) > 0 THEN
      IF v_video.category_id IS NULL OR NOT (v_video.category_id = ANY(v_settings.allowed_categories)) THEN
        RETURN jsonb_build_object(
          'allowed', FALSE,
          'reason', 'CATEGORY_RESTRICTED',
          'message', 'Bu video kategorisi ebeveyniniz tarafından kısıtlanmıştır.'
        );
      END IF;
    END IF;

    -- B) Bedtime Restriction Check (Europe/Istanbul or local time format HH:MI)
    IF v_settings.bedtime_start IS NOT NULL AND v_settings.bedtime_end IS NOT NULL
       AND TRIM(v_settings.bedtime_start) != '' AND TRIM(v_settings.bedtime_end) != '' THEN
      v_now_time_str := to_char(NOW() AT TIME ZONE 'Europe/Istanbul', 'HH24:MI');

      -- Check if current time falls in bedtime range (supports overnight wrap e.g. 21:00 - 07:00)
      IF v_settings.bedtime_start <= v_settings.bedtime_end THEN
        IF v_now_time_str >= v_settings.bedtime_start AND v_now_time_str < v_settings.bedtime_end THEN
          RETURN jsonb_build_object(
            'allowed', FALSE,
            'reason', 'BEDTIME',
            'message', '😴 Uyku vakti geldi (' || v_settings.bedtime_start || ' - ' || v_settings.bedtime_end || ')! Ahmet Egemen dinleniyor.'
          );
        END IF;
      ELSE
        -- Overnight wrap: e.g. 21:00 to 07:00
        IF v_now_time_str >= v_settings.bedtime_start OR v_now_time_str < v_settings.bedtime_end THEN
          RETURN jsonb_build_object(
            'allowed', FALSE,
            'reason', 'BEDTIME',
            'message', '😴 Uyku vakti geldi (' || v_settings.bedtime_start || ' - ' || v_settings.bedtime_end || ')! Ahmet Egemen dinleniyor.'
          );
        END IF;
      END IF;
    END IF;

    -- C) Daily Limit Check (Using real watch_history_sessions)
    IF v_settings.daily_time_limit_minutes IS NOT NULL AND v_settings.daily_time_limit_minutes > 0 THEN
      v_today_start := DATE_TRUNC('day', NOW() AT TIME ZONE 'Europe/Istanbul');

      SELECT COALESCE(SUM(watched_seconds), 0) INTO v_today_watched_seconds
      FROM public.watch_history_sessions
      WHERE user_id = p_user_id
        AND started_at >= v_today_start;

      IF v_today_watched_seconds >= (v_settings.daily_time_limit_minutes * 60) THEN
        RETURN jsonb_build_object(
          'allowed', FALSE,
          'reason', 'DAILY_LIMIT',
          'message', '⏰ Günlük izleme süreniz doldu (' || v_settings.daily_time_limit_minutes || ' dakika)! Yarın tekrar görüşmek üzere.'
        );
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
END;
$$;


-- ============================================================================
-- 2. REVISE RPC: authorize_child_video_play (CRIT-18 delegation to helper)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.authorize_child_video_play(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.check_child_video_play_policy(auth.uid(), p_video_id);
END;
$$;


-- ============================================================================
-- 3. REVISE RPC: start_watch_session (CRIT-18 Server-Side Policy & Deduplication)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.start_watch_session(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_auth_result JSONB;
  v_active_session_id UUID;
  v_session_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'allowed', FALSE,
      'reason', 'NOT_AUTHENTICATED',
      'error', 'Kimlik doğrulaması yapılmadı.'
    );
  END IF;

  -- 1. Server-Side Parental Authorization Enforcement (CRIT-18)
  v_auth_result := public.check_child_video_play_policy(v_user_id, p_video_id);

  IF v_auth_result IS NULL OR (v_auth_result->>'allowed')::BOOLEAN IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'allowed', FALSE,
      'reason', COALESCE(v_auth_result->>'reason', 'AUTHORIZATION_ERROR'),
      'error', COALESCE(v_auth_result->>'message', 'İzleme yetkilendirmesi reddedildi.')
    );
  END IF;

  -- 2. Concurrency & Deduplication: Check if there's already an active (unfinalized)
  --    session for this user and video created in the last 12 hours
  SELECT id INTO v_active_session_id
  FROM public.watch_history_sessions
  WHERE user_id = v_user_id
    AND video_id = p_video_id
    AND ended_at IS NULL
    AND started_at >= NOW() - INTERVAL '12 hours'
  ORDER BY started_at DESC
  LIMIT 1;

  IF v_active_session_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', TRUE,
      'allowed', TRUE,
      'session_id', v_active_session_id,
      'reused', TRUE
    );
  END IF;

  -- 3. Create new watch session
  INSERT INTO public.watch_history_sessions (user_id, video_id, started_at)
  VALUES (v_user_id, p_video_id, NOW())
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'allowed', TRUE,
    'session_id', v_session_id,
    'reused', FALSE
  );
END;
$$;


-- ============================================================================
-- 4. REVISE RPC: create_parent_child_link (CRIT-17 No Admin Bypass on Target Role)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_parent_child_link(p_child_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_child_role TEXT;
  v_link_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  IF p_child_id IS NULL OR v_caller_id = p_child_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz çocuk hesabı.');
  END IF;

  -- Verify caller role (must be parent or admin)
  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca ebeveynler çocuk hesabı bağlayabilir.');
  END IF;

  -- Verify target profile existence and STRICT role check
  SELECT role INTO v_child_role FROM public.profiles WHERE id = p_child_id;
  IF v_child_role IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk profili bulunamadı.');
  END IF;

  -- STRICT: target MUST have role = 'child' (NO ADMIN BYPASS)
  IF v_child_role != 'child' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca çocuk rolündeki hesaplar bağlanabilir.');
  END IF;

  -- Insert link
  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_caller_id, p_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING
  RETURNING id INTO v_link_id;

  IF v_link_id IS NULL THEN
    -- If already linked, fetch existing id
    SELECT id INTO v_link_id FROM public.parent_children
    WHERE parent_id = v_caller_id AND child_id = p_child_id;
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'link_id', v_link_id);
END;
$$;


-- ============================================================================
-- 5. DB DATA INTEGRITY TRIGGER: validate_parent_child_roles (CRIT-17 Second Line of Defense)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_parent_child_roles_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parent_role TEXT;
  v_child_role TEXT;
BEGIN
  IF NEW.parent_id = NEW.child_id THEN
    RAISE EXCEPTION 'parent_id and child_id cannot be identical';
  END IF;

  SELECT role INTO v_parent_role FROM public.profiles WHERE id = NEW.parent_id;
  IF v_parent_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Parent must have role parent or admin, got %', v_parent_role;
  END IF;

  SELECT role INTO v_child_role FROM public.profiles WHERE id = NEW.child_id;
  IF v_child_role != 'child' THEN
    RAISE EXCEPTION 'Child must have role child, got %', v_child_role;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_parent_child_roles ON public.parent_children;
CREATE TRIGGER trg_validate_parent_child_roles
  BEFORE INSERT OR UPDATE ON public.parent_children
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_parent_child_roles_trigger();


-- ============================================================================
-- 6. PERMISSIONS & DCL GRANTS/REVOKES
-- ============================================================================
-- Internal helper is revoked from public execution
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- Public & Authenticated API grants
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated, anon;
