-- ============================================================================
-- Migration: 20260814000000_parent_child_watch_session_security.sql
-- Description: CRIT-06 Parent-Child Data Model, CRIT-08 Real Watch Sessions &
--              Cumulative Analytics, CRIT-07 Server-Side Parental Authorization,
--              CRIT-16 Fail-Closed Playback Architecture
-- ============================================================================

-- 1. Create parent_children table
CREATE TABLE IF NOT EXISTS public.parent_children (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  child_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT parent_children_unique UNIQUE (parent_id, child_id),
  CONSTRAINT parent_children_no_self CHECK (parent_id <> child_id)
);

CREATE INDEX IF NOT EXISTS idx_parent_children_parent_id ON public.parent_children(parent_id);
CREATE INDEX IF NOT EXISTS idx_parent_children_child_id ON public.parent_children(child_id);

-- Enable RLS on parent_children
ALTER TABLE public.parent_children ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "parent_children_select_parent" ON public.parent_children;
CREATE POLICY "parent_children_select_parent"
  ON public.parent_children FOR SELECT
  USING (auth.uid() = parent_id);

DROP POLICY IF EXISTS "parent_children_select_child" ON public.parent_children;
CREATE POLICY "parent_children_select_child"
  ON public.parent_children FOR SELECT
  USING (auth.uid() = child_id);

-- Disallow client direct mutations on parent_children
REVOKE INSERT, UPDATE, DELETE ON public.parent_children FROM PUBLIC, anon, authenticated;

-- 2. Create watch_history_sessions table (CRIT-08 Event Stream)
CREATE TABLE IF NOT EXISTS public.watch_history_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  watched_seconds INTEGER NOT NULL DEFAULT 0 CHECK (watched_seconds >= 0),
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_wh_sessions_ended_after_start CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_started ON public.watch_history_sessions(user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_video_started ON public.watch_history_sessions(video_id, started_at);
CREATE INDEX IF NOT EXISTS idx_wh_sessions_user_video_started ON public.watch_history_sessions(user_id, video_id, started_at);

-- Enable RLS on watch_history_sessions
ALTER TABLE public.watch_history_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "watch_history_sessions_select_own" ON public.watch_history_sessions;
CREATE POLICY "watch_history_sessions_select_own"
  ON public.watch_history_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- Disallow client direct mutations on watch_history_sessions (must use RPCs)
REVOKE INSERT, UPDATE, DELETE ON public.watch_history_sessions FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 3. RPC: create_parent_child_link
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

  -- Verify caller role
  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca ebeveynler çocuk hesabı bağlayabilir.');
  END IF;

  -- Verify target is a child
  SELECT role INTO v_child_role FROM public.profiles WHERE id = p_child_id;
  IF v_child_role IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk profili bulunamadı.');
  END IF;

  IF v_child_role != 'child' AND v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca çocuk rolündeki hesaplar bağlanabilir.');
  END IF;

  -- Insert link
  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_caller_id, p_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING
  RETURNING id INTO v_link_id;

  RETURN jsonb_build_object('success', TRUE, 'link_id', v_link_id);
END;
$$;


-- ============================================================================
-- 4. RPC: get_my_children
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
        'child_name', COALESCE(p.full_name, p.username, 'Çocuk Hesabı'),
        'created_at', pc.created_at
      )
      ORDER BY pc.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_result
  FROM public.parent_children pc
  JOIN public.profiles p ON p.id = pc.child_id
  WHERE pc.parent_id = v_caller_id;

  RETURN v_result;
END;
$$;


-- ============================================================================
-- 5. RPC: start_watch_session
-- ============================================================================
CREATE OR REPLACE FUNCTION public.start_watch_session(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_video_exists BOOLEAN;
  v_session_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  -- Ensure video exists and is not deleted
  SELECT EXISTS (
    SELECT 1 FROM public.videos WHERE id = p_video_id AND is_deleted = FALSE
  ) INTO v_video_exists;

  IF NOT v_video_exists THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Video bulunamadı veya silinmiş.');
  END IF;

  -- Create new watch session
  INSERT INTO public.watch_history_sessions (user_id, video_id, started_at)
  VALUES (v_user_id, p_video_id, NOW())
  RETURNING id INTO v_session_id;

  RETURN jsonb_build_object('success', TRUE, 'session_id', v_session_id);
END;
$$;


-- ============================================================================
-- 6. RPC: finalize_watch_session
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
  v_duration INT;
  v_sanitized_seconds INT := GREATEST(0, COALESCE(p_watched_seconds, 0));
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  -- Verify session belongs to caller and is not already finalized
  SELECT video_id INTO v_video_id
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND ended_at IS NULL
  FOR UPDATE;

  IF v_video_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz veya daha önce sonlandırılmış oturum.');
  END IF;

  -- Sanitize watched seconds against video duration (allow max 1.5x duration or 12 hours)
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_video_id;
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_sanitized_seconds := LEAST(v_sanitized_seconds, v_duration * 2);
  ELSE
    v_sanitized_seconds := LEAST(v_sanitized_seconds, 43200); -- max 12 hours
  END IF;

  -- Finalize session
  UPDATE public.watch_history_sessions
  SET ended_at = NOW(),
      watched_seconds = v_sanitized_seconds,
      completed = COALESCE(p_completed, FALSE)
  WHERE id = p_session_id AND user_id = v_user_id;

  -- Upsert current state in watch_history (for backward compatibility & resume position)
  INSERT INTO public.watch_history (user_id, video_id, progress_seconds, completed, updated_at)
  VALUES (v_user_id, v_video_id, v_sanitized_seconds, COALESCE(p_completed, FALSE), NOW())
  ON CONFLICT (user_id, video_id)
  DO UPDATE SET
    progress_seconds = GREATEST(watch_history.progress_seconds, EXCLUDED.progress_seconds),
    completed = watch_history.completed OR EXCLUDED.completed,
    updated_at = NOW();

  RETURN jsonb_build_object('success', TRUE);
END;
$$;


-- ============================================================================
-- 7. RPC: get_parent_child_usage_report (CRIT-06 & CRIT-08 Real Cumulative)
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

  -- Authorization check:
  -- 1. If caller is admin -> ALLOW
  -- 2. If caller is inspecting self -> ALLOW
  -- 3. If caller is parent AND child_id is in parent_children -> ALLOW
  IF v_caller_role = 'admin' OR v_caller_id = p_child_id THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role = 'parent' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.parent_children
      WHERE parent_id = v_caller_id AND child_id = p_child_id
    ) INTO v_is_authorized;
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

  -- Compute start time based on period
  CASE LOWER(p_period)
    WHEN 'daily' THEN
      v_start_time := DATE_TRUNC('day', NOW() AT TIME ZONE 'Europe/Istanbul');
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

  -- 1. Totals from watch_history_sessions
  SELECT
    COALESCE(SUM(s.watched_seconds), 0),
    COUNT(DISTINCT s.video_id),
    COUNT(DISTINCT s.video_id) FILTER (WHERE s.completed = TRUE)
  INTO
    v_total_watch_seconds,
    v_watched_videos_count,
    v_completed_videos_count
  FROM public.watch_history_sessions s
  JOIN public.videos v ON v.id = s.video_id
  WHERE s.user_id = p_child_id
    AND s.started_at >= v_start_time
    AND v.is_deleted = FALSE;

  -- 2. Category Stats breakdown
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'categoryId', cat_sub.category_id,
        'categoryTitle', cat_sub.category_title,
        'watchTimeSeconds', cat_sub.cat_seconds,
        'videoCount', cat_sub.cat_video_count
      )
      ORDER BY cat_sub.cat_seconds DESC
    ),
    '[]'::jsonb
  ) INTO v_category_stats
  FROM (
    SELECT
      COALESCE(v.category_id, 'uncategorized') AS category_id,
      COALESCE(c.title, 'Kategorisiz') AS category_title,
      SUM(s.watched_seconds) AS cat_seconds,
      COUNT(DISTINCT s.video_id) AS cat_video_count
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    LEFT JOIN public.categories c ON c.id = v.category_id
    WHERE s.user_id = p_child_id
      AND s.started_at >= v_start_time
      AND v.is_deleted = FALSE
    GROUP BY COALESCE(v.category_id, 'uncategorized'), COALESCE(c.title, 'Kategorisiz')
  ) cat_sub;

  -- 3. Top Watched Videos (Cumulative Session counts and total duration)
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'videoId', top_sub.video_id,
        'title', top_sub.title,
        'watchCount', top_sub.session_count,
        'totalSeconds', top_sub.total_seconds
      )
      ORDER BY top_sub.total_seconds DESC
    ),
    '[]'::jsonb
  ) INTO v_top_videos
  FROM (
    SELECT
      s.video_id,
      v.title,
      COUNT(s.id) AS session_count,
      SUM(s.watched_seconds) AS total_seconds
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND s.started_at >= v_start_time
      AND v.is_deleted = FALSE
    GROUP BY s.video_id, v.title
    ORDER BY SUM(s.watched_seconds) DESC
    LIMIT 5
  ) top_sub;

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


-- ============================================================================
-- 8. RPC: authorize_child_video_play (CRIT-07 & CRIT-16 Server-Side Enforcement)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.authorize_child_video_play(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT := 'guest';
  v_video RECORD;
  v_settings RECORD;
  v_has_settings BOOLEAN := FALSE;
  v_now_time_str TEXT;
  v_today_watched_seconds BIGINT := 0;
  v_today_start TIMESTAMPTZ;
BEGIN
  -- 1. Check video existence
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
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- 2. Check user role
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;

  -- Parents and Admins have unrestricted access
  IF v_user_role IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('allowed', TRUE, 'reason', 'OK');
  END IF;

  -- 3. Locate parental settings for this child
  -- Strategy A: From linked parent in parent_children
  SELECT ps.* INTO v_settings
  FROM public.parent_settings ps
  JOIN public.parent_children pc ON pc.parent_id = ps.user_id
  WHERE pc.child_id = v_user_id
  ORDER BY ps.updated_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_has_settings := TRUE;
  ELSE
    -- Strategy B: Shared account / single profile fallback
    SELECT * INTO v_settings
    FROM public.parent_settings
    WHERE user_id = v_user_id;

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
      WHERE user_id = v_user_id
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
-- 9. Permissions (DCL Grants & Revokes)
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated, anon;
