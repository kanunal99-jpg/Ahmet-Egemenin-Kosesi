-- ============================================================================
-- Migration: 20260814000002_daily_limit_publisher_policy_hardening.sql
-- Description: CRIT-19 & CRIT-20 Security Hardening
--              - CRIT-19: Atomic Daily Limit Enforcement with Effective Watch
--                Calculation (Finalized + Active Session Elapsed Time) and
--                User-Level Advisory Transaction Locking
--              - CRIT-20: Publisher Playback Policy Specification and Strict
--                Role Boundary Separation (No Parental Bypass)
-- ============================================================================

-- ============================================================================
-- 1. INTERNAL HELPER: get_effective_child_daily_watch_seconds (CRIT-19)
-- Calculates both finalized watch history sessions and currently active
-- (unfinalized) sessions started today, with clock-skew protection and safe ceilings.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_effective_child_daily_watch_seconds(
  p_user_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_today_start TIMESTAMPTZ;
  v_finalized_seconds BIGINT := 0;
  v_active_seconds BIGINT := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 0;
  END IF;

  v_today_start := DATE_TRUNC('day', NOW() AT TIME ZONE 'Europe/Istanbul');

  -- 1. Sum of completed/finalized sessions started today
  SELECT COALESCE(SUM(watched_seconds), 0) INTO v_finalized_seconds
  FROM public.watch_history_sessions
  WHERE user_id = p_user_id
    AND started_at >= v_today_start
    AND ended_at IS NOT NULL;

  -- 2. Sum of elapsed duration for currently active (unfinalized) sessions started today
  --    Guards:
  --      - GREATEST(0, ...): Prevents negative duration on future-skewed timestamps
  --      - LEAST(43200, ...): Caps at 12 hours to prevent stale unclosed sessions from exceeding realistic limits
  SELECT COALESCE(
    SUM(
      GREATEST(
        0,
        LEAST(
          43200,
          EXTRACT(EPOCH FROM (NOW() - started_at))::BIGINT
        )
      )
    ),
    0
  ) INTO v_active_seconds
  FROM public.watch_history_sessions
  WHERE user_id = p_user_id
    AND started_at >= v_today_start
    AND ended_at IS NULL;

  RETURN v_finalized_seconds + v_active_seconds;
END;
$$;


-- ============================================================================
-- 2. REVISE INTERNAL HELPER: check_child_video_play_policy (CRIT-19 & CRIT-20)
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
  v_effective_watched_seconds BIGINT := 0;
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

  -- If guest (unauthenticated), allow public video viewing
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

  -- Parents and Admins have unrestricted playback access on active videos
  IF v_user_role IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- CRIT-20: Publisher Role Playback Policy Specification
  -- Publishers are content creators who can watch active public videos for preview/quality.
  -- They do NOT have child parental restrictions, nor can they bypass parental rules on children.
  IF v_user_role = 'publisher' THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- 3. Child Role: Locate parental settings
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

    -- C) CRIT-19: Effective Daily Limit Check (Finalized + Active sessions elapsed)
    IF v_settings.daily_time_limit_minutes IS NOT NULL AND v_settings.daily_time_limit_minutes > 0 THEN
      v_effective_watched_seconds := public.get_effective_child_daily_watch_seconds(p_user_id);

      IF v_effective_watched_seconds >= (v_settings.daily_time_limit_minutes * 60) THEN
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
-- 3. REVISE RPC: start_watch_session (CRIT-19 Concurrency Guard & Atomic Enforcement)
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

  -- CRIT-19: Transaction-level advisory lock scoped to this specific user
  -- Serializes simultaneous start requests for the same child to prevent TOCTOU race conditions.
  PERFORM pg_advisory_xact_lock(hashtext('child_watch_session_' || v_user_id::text));

  -- 1. Server-Side Parental Authorization Enforcement (CRIT-18 & CRIT-19)
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

  -- 3. Create new watch session atomically
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
-- 4. DCL & PERMISSIONS HARDENING
-- ============================================================================
-- Revoke internal helpers from all client execution
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- Public & Authenticated RPC execution
REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated, anon;
