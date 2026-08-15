-- ============================================================================
-- Migration: 20260815000001_live_reconciliation_bridge.sql
-- Description: Production Live DB to Canonical Architecture Reconciliation Bridge
--              - Bridges missing relational tables: parent_children, watch_history_sessions
--              - Installs constraints, performance indexes, and strict RLS policies
--              - Deploys canonical RPC chain:
--                  * create_parent_child_link (CRIT-06 / CRIT-17)
--                  * get_my_children (CRIT-06 / CRIT-23)
--                  * check_child_video_play_policy (CRIT-18 / CRIT-19 / CRIT-20)
--                  * authorize_child_video_play (CRIT-18 / CRIT-20)
--                  * start_watch_session (CRIT-18 / CRIT-19 pg_advisory_xact_lock)
--                  * finalize_watch_session (CRIT-08 / CRIT-19 duration sanitizer)
--                  * get_istanbul_day_start (CRIT-21 canonical Europe/Istanbul boundary)
--                  * get_effective_child_daily_watch_seconds (CRIT-19 / CRIT-21)
--                  * get_parent_child_usage_report (CRIT-21 / CRIT-22 c.title & c.icon_name)
--              - Implements 2-tier defense: validate_parent_child_roles_trigger (CRIT-17)
--              - Preserves existing hardened verify_parent_pin and get_my_role
--              - 100% IDEMPOTENT and RE-RUNNABLE on any live or fresh environment
-- ============================================================================

-- ============================================================================
-- 1. EXTENSIONS & PREREQUISITES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ============================================================================
-- 2. TABLES & SCHEMA RECONCILIATION
-- ============================================================================

-- 2.1 Table: parent_children (CRIT-06 & CRIT-17)
CREATE TABLE IF NOT EXISTS public.parent_children (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  child_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotent Constraints for parent_children
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'parent_children_unique'
  ) THEN
    ALTER TABLE public.parent_children ADD CONSTRAINT parent_children_unique UNIQUE (parent_id, child_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'parent_children_no_self'
  ) THEN
    ALTER TABLE public.parent_children ADD CONSTRAINT parent_children_no_self CHECK (parent_id <> child_id);
  END IF;
END;
$$;

-- Indexes for parent_children
CREATE INDEX IF NOT EXISTS idx_parent_children_parent_id ON public.parent_children(parent_id);
CREATE INDEX IF NOT EXISTS idx_parent_children_child_id ON public.parent_children(child_id);

-- Enable RLS
ALTER TABLE public.parent_children ENABLE ROW LEVEL SECURITY;

-- CRIT-37: Explicit table-level privilege revocation & restricted SELECT grant
REVOKE ALL ON public.parent_children FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.parent_children TO authenticated;

-- Idempotent RLS Policies on parent_children
DROP POLICY IF EXISTS "parent_children_select_parent" ON public.parent_children;
CREATE POLICY "parent_children_select_parent"
  ON public.parent_children FOR SELECT
  USING (auth.uid() = parent_id);

DROP POLICY IF EXISTS "parent_children_select_child" ON public.parent_children;
CREATE POLICY "parent_children_select_child"
  ON public.parent_children FOR SELECT
  USING (auth.uid() = child_id);

DROP POLICY IF EXISTS "parent_children_admin_all" ON public.parent_children;
CREATE POLICY "parent_children_admin_all"
  ON public.parent_children FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );


-- 2.2 Table: watch_history_sessions (CRIT-08, CRIT-18, CRIT-19, CRIT-37)
CREATE TABLE IF NOT EXISTS public.watch_history_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_heartbeat_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  watched_seconds INTEGER NOT NULL DEFAULT 0 CHECK (watched_seconds >= 0),
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotent column addition for existing tables
ALTER TABLE public.watch_history_sessions ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ DEFAULT NOW();

-- Idempotent Constraints for watch_history_sessions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_wh_sessions_ended_after_start'
  ) THEN
    ALTER TABLE public.watch_history_sessions ADD CONSTRAINT chk_wh_sessions_ended_after_start
      CHECK (ended_at IS NULL OR ended_at >= started_at);
  END IF;
END;
$$;

-- Indexes for watch_history_sessions (CRIT-33)
DROP INDEX IF EXISTS public.idx_wh_sessions_daily_limit;
DROP INDEX IF EXISTS public.idx_wh_sessions_active_lookup;
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_started ON public.watch_history_sessions(user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_video_started ON public.watch_history_sessions(video_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_video_active ON public.watch_history_sessions(user_id, video_id, started_at) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_active ON public.watch_history_sessions(user_id, started_at) WHERE ended_at IS NULL;

-- Enable RLS
ALTER TABLE public.watch_history_sessions ENABLE ROW LEVEL SECURITY;

-- CRIT-37: Explicit table-level privilege revocation & restricted SELECT grant
REVOKE ALL ON public.watch_history_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.watch_history_sessions TO authenticated;

-- Idempotent RLS Policies on watch_history_sessions
DROP POLICY IF EXISTS "watch_history_sessions_select_own" ON public.watch_history_sessions;
CREATE POLICY "watch_history_sessions_select_own"
  ON public.watch_history_sessions FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "watch_history_sessions_admin_select" ON public.watch_history_sessions;
CREATE POLICY "watch_history_sessions_admin_select"
  ON public.watch_history_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );


-- ============================================================================
-- 3. CRIT-17: 2ND LINE OF DEFENSE DATA INTEGRITY TRIGGER
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
  -- 1. Self-link check
  IF NEW.parent_id = NEW.child_id THEN
    RAISE EXCEPTION 'parent_id and child_id cannot be identical';
  END IF;

  -- 2. Parent role check (parent or admin allowed)
  SELECT role INTO v_parent_role FROM public.profiles WHERE id = NEW.parent_id;
  IF v_parent_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Parent must have role parent or admin, got %', v_parent_role;
  END IF;

  -- 3. Target role check: STRICTLY child (CRIT-17: admin->parent, admin->publisher, parent->parent DENIED)
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

REVOKE EXECUTE ON FUNCTION public.validate_parent_child_roles_trigger() FROM PUBLIC, anon;


-- ============================================================================
-- 4. CRIT-21: TIMEZONE HELPER (Europe/Istanbul Canonical Day Start)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_istanbul_day_start()
RETURNS TIMESTAMPTZ
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (DATE_TRUNC('day', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
$$;

REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 5. CRIT-19, CRIT-21, CRIT-38, CRIT-39, CRIT-42 & CRIT-43: EFFECTIVE CHILD DAILY WATCH CALCULATION
-- Calculates daily watch duration using canonical session overlap for both finalized
-- and active (heartbeat-tracked) sessions.
-- No arbitrary 12-hour filter; uses true verified watched_seconds accumulated via heartbeats.
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
  v_total_seconds BIGINT := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 0;
  END IF;

  -- Canonical Europe/Istanbul day start
  v_today_start := public.get_istanbul_day_start();

  -- Canonical session overlap for both finalized and active sessions (CRIT-39, CRIT-42 & CRIT-43):
  -- overlap_start = GREATEST(started_at, v_today_start)
  -- overlap_end   = LEAST(COALESCE(ended_at, NOW()), NOW())
  -- overlap_secs  = GREATEST(0, EXTRACT(EPOCH FROM overlap_end - overlap_start))
  -- contribution  = LEAST(watched_seconds, overlap_secs, 43200)
  SELECT COALESCE(
    SUM(
      LEAST(
        watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(COALESCE(ended_at, NOW()), NOW()) - GREATEST(started_at, v_today_start)
            )
          )::BIGINT
        ),
        43200
      )
    ),
    0
  ) INTO v_total_seconds
  FROM public.watch_history_sessions
  WHERE user_id = p_user_id
    AND COALESCE(ended_at, NOW()) >= v_today_start
    AND started_at <= NOW();

  RETURN v_total_seconds;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 6. CRIT-18, CRIT-19, CRIT-20, CRIT-35: INTERNAL POLICY HELPER
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
  -- 1. Check video existence and visibility (CRIT-35)
  IF p_video_id IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'VIDEO_NOT_FOUND',
      'message', 'Video kimliği belirtilmedi.'
    );
  END IF;

  SELECT id, title, category_id, is_deleted, visibility INTO v_video
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

  -- CRIT-35: Visibility enforcement BEFORE role checks
  -- For guests (anon): ONLY public non-deleted videos are allowed
  IF p_user_id IS NULL THEN
    IF v_video.visibility = 'public' THEN
      RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
    ELSE
      RETURN jsonb_build_object(
        'allowed', FALSE,
        'reason', 'VIDEO_NOT_PUBLIC',
        'message', 'Bu videoya erişim izniniz bulunmuyor.'
      );
    END IF;
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

  -- CRIT-35: Enforce visibility rules by role
  -- Parents and Admins have platform supervision playback access
  IF v_user_role IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- CRIT-20 & CRIT-35: Publishers can only view public active videos (cannot bypass private/unlisted)
  IF v_user_role = 'publisher' THEN
    IF v_video.visibility = 'public' THEN
      RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
    ELSE
      RETURN jsonb_build_object(
        'allowed', FALSE,
        'reason', 'VIDEO_NOT_PUBLIC',
        'message', 'Yayıncılar yalnızca herkese açık videoları izleyebilir.'
      );
    END IF;
  END IF;

  -- Child role: MUST be public video. Private/unlisted is strictly denied.
  IF v_video.visibility != 'public' THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'VIDEO_NOT_PUBLIC',
      'message', 'Bu video çocuk hesapları için erişime açık değildir.'
    );
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

    -- B) Bedtime Restriction Check (Europe/Istanbul canonical time format HH24:MI)
    IF v_settings.bedtime_start IS NOT NULL AND v_settings.bedtime_end IS NOT NULL
       AND TRIM(v_settings.bedtime_start) != '' AND TRIM(v_settings.bedtime_end) != '' THEN
      v_now_time_str := to_char(NOW() AT TIME ZONE 'Europe/Istanbul', 'HH24:MI');

      -- Standard daytime range vs overnight wrap (e.g. 21:00 to 07:00)
      IF v_settings.bedtime_start <= v_settings.bedtime_end THEN
        IF v_now_time_str >= v_settings.bedtime_start AND v_now_time_str < v_settings.bedtime_end THEN
          RETURN jsonb_build_object(
            'allowed', FALSE,
            'reason', 'BEDTIME',
            'message', '😴 Uyku vakti geldi (' || v_settings.bedtime_start || ' - ' || v_settings.bedtime_end || ')! Ahmet Egemen dinleniyor.'
          );
        END IF;
      ELSE
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

REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 7. RPC: authorize_child_video_play (CRIT-18)
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

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated, anon;


-- ============================================================================
-- 8. RPC: start_watch_session (CRIT-18 & CRIT-19 Atomic Locking)
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

  -- CRIT-19: Transaction-level advisory lock scoped to caller
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

  -- 2. CRIT-41 Playback-Surface Isolation:
  -- Create an isolated, dedicated watch session for this playback instance.
  -- Multi-tab / multi-device instances do not share or overwrite each other's sessions.
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

REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;


-- ============================================================================
-- 9. RPC: heartbeat_watch_session (CRIT-43)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.heartbeat_watch_session(
  p_session_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_session RECORD;
  v_now TIMESTAMPTZ := NOW();
  v_delta_seconds BIGINT;
  v_new_watched_seconds INT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  IF p_session_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz oturum kimliği.');
  END IF;

  -- Verify session belongs to caller and is active (FOR UPDATE lock)
  SELECT id, user_id, video_id, started_at, last_heartbeat_at, watched_seconds
  INTO v_session
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND ended_at IS NULL
  FOR UPDATE;

  IF v_session.id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Oturum bulunamadı veya sonlandırılmış.');
  END IF;

  -- Calculate elapsed time since last heartbeat or session start
  v_delta_seconds := GREATEST(
    0,
    EXTRACT(EPOCH FROM (v_now - COALESCE(v_session.last_heartbeat_at, v_session.started_at)))::BIGINT
  );

  -- Sanitize delta: client heartbeats are sent every 5-10 seconds; cap individual delta at 30 seconds
  v_delta_seconds := LEAST(v_delta_seconds, 30);

  v_new_watched_seconds := LEAST(
    (v_session.watched_seconds + v_delta_seconds)::BIGINT,
    43200::BIGINT
  )::INT;

  UPDATE public.watch_history_sessions
  SET watched_seconds = v_new_watched_seconds,
      last_heartbeat_at = v_now
  WHERE id = p_session_id AND user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'watched_seconds', v_new_watched_seconds
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) TO authenticated;


-- ============================================================================
-- 10. RPC: finalize_watch_session (CRIT-08, CRIT-19, CRIT-36, CRIT-40 & CRIT-43)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.finalize_watch_session(
  p_session_id UUID,
  p_watched_seconds INTEGER,
  p_completed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_video_id UUID;
  v_started_at TIMESTAMPTZ;
  v_last_heartbeat_at TIMESTAMPTZ;
  v_session_watched_seconds INT;
  v_duration INT;
  v_actual_elapsed_seconds BIGINT;
  v_trailing_delta BIGINT;
  v_accumulated_seconds BIGINT;
  v_sanitized_seconds INT;
  v_verified_completed BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  -- 1. Verify session belongs to caller and is not already finalized (FOR UPDATE)
  SELECT video_id, started_at, last_heartbeat_at, watched_seconds
  INTO v_video_id, v_started_at, v_last_heartbeat_at, v_session_watched_seconds
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND ended_at IS NULL
  FOR UPDATE;

  IF v_video_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz veya daha önce sonlandırılmış oturum.');
  END IF;

  -- 2. Authoritative DB elapsed time calculation
  IF v_started_at > NOW() THEN
    v_actual_elapsed_seconds := 0;
  ELSE
    v_actual_elapsed_seconds := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_started_at))::BIGINT);
  END IF;

  -- Trailing delta between last heartbeat and finalize (max 15s)
  v_trailing_delta := LEAST(
    GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(v_last_heartbeat_at, v_started_at)))::BIGINT),
    15
  );

  v_accumulated_seconds := GREATEST(
    v_session_watched_seconds + v_trailing_delta,
    COALESCE(p_watched_seconds, 0)::BIGINT
  );

  -- 3. Sanitize watched seconds against actual elapsed time, client claim, and video duration
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_video_id;

  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_sanitized_seconds := LEAST(
      v_accumulated_seconds,
      v_actual_elapsed_seconds,
      v_duration::BIGINT,
      43200::BIGINT
    )::INT;

    -- Completion integrity: completed requires client claim AND at least 90% watched
    IF p_completed IS TRUE AND v_sanitized_seconds >= (v_duration * 0.9) THEN
      v_verified_completed := TRUE;
    ELSE
      v_verified_completed := FALSE;
    END IF;
  ELSE
    v_sanitized_seconds := LEAST(
      v_accumulated_seconds,
      v_actual_elapsed_seconds,
      43200::BIGINT
    )::INT;

    v_verified_completed := COALESCE(p_completed, FALSE) AND (v_sanitized_seconds > 0);
  END IF;

  -- 4. Finalize session atomically
  UPDATE public.watch_history_sessions
  SET ended_at = NOW(),
      watched_seconds = v_sanitized_seconds,
      completed = v_verified_completed
  WHERE id = p_session_id AND user_id = v_user_id;

  -- 5. CRIT-40: Update cumulative completion state in watch_history WITHOUT overwriting progress_seconds
  INSERT INTO public.watch_history (user_id, video_id, progress_seconds, completed, updated_at)
  VALUES (v_user_id, v_video_id, 0, v_verified_completed, NOW())
  ON CONFLICT (user_id, video_id)
  DO UPDATE SET
    completed = CASE WHEN watch_history.completed THEN TRUE ELSE EXCLUDED.completed END,
    updated_at = NOW();

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;


-- ============================================================================
-- 10. RPC: create_parent_child_link (CRIT-06 & CRIT-17 1st Line of Defense)
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
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz çocuk hesabı (kendinize bağlanamazsınız).');
  END IF;

  -- Verify caller role (must be parent or admin)
  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca ebeveynler çocuk hesabı bağlayabilir.');
  END IF;

  -- Verify target profile existence and STRICT role check (CRIT-17)
  SELECT role INTO v_child_role FROM public.profiles WHERE id = p_child_id;
  IF v_child_role IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk profili bulunamadı.');
  END IF;

  -- STRICT: target MUST have role = 'child' (NO ADMIN BYPASS: admin->parent or admin->publisher is denied)
  IF v_child_role != 'child' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca çocuk rolündeki hesaplar bağlanabilir.');
  END IF;

  -- Insert link
  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_caller_id, p_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING
  RETURNING id INTO v_link_id;

  IF v_link_id IS NULL THEN
    SELECT id INTO v_link_id FROM public.parent_children
    WHERE parent_id = v_caller_id AND child_id = p_child_id;
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'link_id', v_link_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link(UUID) TO authenticated;


-- ============================================================================
-- 11. RPC: get_my_children (CRIT-06 & CRIT-23)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_children()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_result JSONB;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pc.id,
        'child_id', p.id,
        'child_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''), p.first_name, 'Çocuk Hesabı'),
        'created_at', pc.created_at
      )
      ORDER BY pc.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_result
  FROM public.parent_children pc
  JOIN public.profiles p ON p.id = pc.child_id
  WHERE pc.parent_id = v_caller_id
    AND p.role = 'child';

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;


-- ============================================================================
-- 12. RPC: get_parent_child_usage_report (CRIT-21 & CRIT-22 & CRIT-31 & CRIT-32)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_parent_child_usage_report(
  p_child_id UUID,
  p_period TEXT DEFAULT 'weekly'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_is_authorized BOOLEAN := FALSE;
  v_start_time TIMESTAMPTZ;
  
  v_total_watch_seconds BIGINT := 0;
  v_watched_videos_count INT := 0;
  v_completed_videos_count INT := 0;
  v_category_stats JSONB := '[]'::jsonb;
  v_top_videos JSONB := '[]'::jsonb;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

  -- Authorization check (CRIT-31 & CRIT-32):
  -- 1. If caller is admin -> ALLOW
  -- 2. If caller is parent AND child_id is in parent_children -> ALLOW
  -- 3. Publisher, child self, unrelated child, unauthenticated -> DENIED
  IF v_caller_role = 'admin' THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role = 'parent' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.parent_children
      WHERE parent_id = v_caller_id AND child_id = p_child_id
    ) INTO v_is_authorized;
  ELSE
    v_is_authorized := FALSE;
  END IF;

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object(
      'error', 'Yetkisiz erişim: Bu çocuğun verilerine erişim izniniz yok.',
      'period', p_period,
      'totalWatchTimeSeconds', 0,
      'watchedVideosCount', 0,
      'completedVideosCount', 0,
      'categoryStats', '[]'::jsonb,
      'topWatchedVideos', '[]'::jsonb
    );
  END IF;

  -- Compute start time based on period with canonical Europe/Istanbul timezone alignment (CRIT-21 & CRIT-39)
  CASE LOWER(p_period)
    WHEN 'daily' THEN
      v_start_time := public.get_istanbul_day_start();
    WHEN 'weekly' THEN
      v_start_time := NOW() - INTERVAL '7 days';
    WHEN 'monthly' THEN
      v_start_time := NOW() - INTERVAL '30 days';
    WHEN '3months' THEN
      v_start_time := NOW() - INTERVAL '90 days';
    WHEN '6months' THEN
      v_start_time := NOW() - INTERVAL '180 days';
    WHEN '9months' THEN
      v_start_time := NOW() - INTERVAL '270 days';
    WHEN '12months' THEN
      v_start_time := NOW() - INTERVAL '365 days';
    ELSE
      v_start_time := NOW() - INTERVAL '7 days';
  END CASE;

  -- 1. Canonical session overlap totals (CRIT-39 & CRIT-42):
  -- Ensures totalWatchTimeSeconds, categoryStats, and topWatchedVideos use the EXACT same
  -- period overlap calculation (e.g. midnight overlap for daily period: 23:59:30 -> 00:05:00 gets 300s).
  WITH period_sessions AS (
    SELECT
      s.id AS session_id,
      s.video_id,
      v.category_id,
      s.completed,
      LEAST(
        s.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(COALESCE(s.ended_at, NOW()), NOW()) - GREATEST(s.started_at, v_start_time)
            )
          )::BIGINT
        ),
        43200
      ) AS session_watch_seconds
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND COALESCE(s.ended_at, NOW()) >= v_start_time
      AND s.started_at <= NOW()
      AND v.is_deleted = FALSE
  )
  SELECT
    COALESCE(SUM(session_watch_seconds), 0),
    COUNT(DISTINCT video_id) FILTER (WHERE session_watch_seconds > 0),
    COUNT(DISTINCT video_id) FILTER (WHERE completed = TRUE)
  INTO
    v_total_watch_seconds,
    v_watched_videos_count,
    v_completed_videos_count
  FROM period_sessions;

  -- 2. Category distribution (CRIT-22, CRIT-39 & CRIT-42: Canonical overlap & correct category columns)
  WITH period_sessions AS (
    SELECT
      s.id AS session_id,
      s.video_id,
      v.category_id,
      s.completed,
      LEAST(
        s.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(COALESCE(s.ended_at, NOW()), NOW()) - GREATEST(s.started_at, v_start_time)
            )
          )::BIGINT
        ),
        43200
      ) AS session_watch_seconds
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND COALESCE(s.ended_at, NOW()) >= v_start_time
      AND s.started_at <= NOW()
      AND v.is_deleted = FALSE
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'categoryId', c.id,
        'categoryName', c.title,
        'categoryTitle', c.title,
        'categoryIcon', c.icon_name,
        'watchTimeSeconds', COALESCE(cat_sum.total_sec, 0),
        'percentage', CASE 
          WHEN v_total_watch_seconds > 0 
          THEN ROUND((COALESCE(cat_sum.total_sec, 0)::NUMERIC / v_total_watch_seconds::NUMERIC) * 100, 1)
          ELSE 0
        END,
        'videoCount', COALESCE(cat_sum.vid_count, 0)
      )
    ),
    '[]'::jsonb
  ) INTO v_category_stats
  FROM (
    SELECT
      category_id,
      SUM(session_watch_seconds) AS total_sec,
      COUNT(DISTINCT video_id) AS vid_count
    FROM period_sessions
    GROUP BY category_id
  ) cat_sum
  JOIN public.categories c ON c.id = cat_sum.category_id;

  -- 3. Top watched videos in period (CRIT-39 & CRIT-42: Canonical overlap contribution)
  WITH period_sessions AS (
    SELECT
      s.id AS session_id,
      s.video_id,
      v.category_id,
      s.completed,
      LEAST(
        s.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(COALESCE(s.ended_at, NOW()), NOW()) - GREATEST(s.started_at, v_start_time)
            )
          )::BIGINT
        ),
        43200
      ) AS session_watch_seconds
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND COALESCE(s.ended_at, NOW()) >= v_start_time
      AND s.started_at <= NOW()
      AND v.is_deleted = FALSE
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'videoId', v.id,
        'title', v.title,
        'thumbnailUrl', v.thumbnail_url,
        'watchCount', top_v.session_count,
        'totalSeconds', top_v.total_sec
      )
    ),
    '[]'::jsonb
  ) INTO v_top_videos
  FROM (
    SELECT
      video_id,
      COUNT(session_id) AS session_count,
      SUM(session_watch_seconds) AS total_sec
    FROM period_sessions
    GROUP BY video_id
    ORDER BY total_sec DESC
    LIMIT 5
  ) top_v
  JOIN public.videos v ON v.id = top_v.video_id;

  RETURN jsonb_build_object(
    'period', p_period,
    'totalWatchTimeSeconds', v_total_watch_seconds,
    'watchedVideosCount', v_watched_videos_count,
    'completedVideosCount', v_completed_videos_count,
    'categoryStats', v_category_stats,
    'topWatchedVideos', v_top_videos
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;
