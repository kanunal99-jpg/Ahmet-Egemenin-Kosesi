-- ============================================================================
-- Migration: 20260815000002_watch_session_heartbeat_and_accounting.sql
-- Description: CRIT-42 (Canonical active/finalized midnight overlap without arbitrary filters)
--              CRIT-43 (Watch session heartbeat model for real playback duration accounting)
--              CRIT-40 (Progress position vs watched duration semantic separation)
-- Mode: SOURCE CODE ONLY - NO LIVE EXECUTION
-- ============================================================================

-- 1. Add last_heartbeat_at column to watch_history_sessions
ALTER TABLE public.watch_history_sessions 
ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ DEFAULT NOW();

-- 2. CRIT-42 & CRIT-43: Canonical daily watch calculation with heartbeat-verified duration
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
  -- No arbitrary 12-hour filter; uses true verified watched_seconds accumulated via heartbeats.
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


-- 3. CRIT-43: Watch Session Heartbeat RPC
-- Client sends heartbeat only while video is actively PLAYING.
-- Server verifies auth, session ownership, active state, bounds elapsed delta, and increments watched_seconds.
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

  -- Verify session belongs to authenticated caller and is active (FOR UPDATE lock)
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
  -- to prevent arbitrary jump or unverified offline accumulation.
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


-- 4. CRIT-40 & CRIT-43: Finalize Watch Session RPC
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


-- 5. CRIT-39 & CRIT-42: Canonical Usage Report with single CTE overlap calculation
CREATE OR REPLACE FUNCTION public.get_parent_child_usage_report(
  p_child_id UUID,
  p_period TEXT DEFAULT 'daily'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_is_parent BOOLEAN := FALSE;
  v_start_time TIMESTAMPTZ;
  v_total_watch_seconds BIGINT := 0;
  v_watched_videos_count BIGINT := 0;
  v_completed_videos_count BIGINT := 0;
  v_category_stats JSONB := '[]'::jsonb;
  v_top_videos JSONB := '[]'::jsonb;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

  IF v_caller_role = 'parent' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.parent_children
      WHERE parent_id = v_caller_id AND child_id = p_child_id
    ) INTO v_is_parent;

    IF NOT v_is_parent THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'Bu çocuğun verilerini görüntüleme yetkiniz yok.');
    END IF;
  ELSIF v_caller_role = 'admin' THEN
    v_is_parent := TRUE;
  ELSIF v_caller_id = p_child_id THEN
    v_is_parent := TRUE;
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yetkisiz erişim.');
  END IF;

  -- Compute start time based on period with canonical Europe/Istanbul timezone alignment
  CASE LOWER(p_period)
    WHEN 'daily' THEN
      v_start_time := public.get_istanbul_day_start();
    WHEN 'weekly' THEN
      v_start_time := (DATE_TRUNC('week', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
    WHEN 'monthly' THEN
      v_start_time := (DATE_TRUNC('month', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
    ELSE
      v_start_time := NOW() - INTERVAL '7 days';
  END CASE;

  -- Canonical session overlap totals for daily/weekly/monthly periods
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

  -- Category distribution
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
        'categoryId', cat_sum.category_id,
        'categoryName', c.title,
        'categoryColor', COALESCE(c.icon_name, 'film'),
        'totalSeconds', cat_sum.total_sec,
        'videoCount', cat_sum.vid_count,
        'percentage', CASE
          WHEN v_total_watch_seconds > 0
          THEN ROUND((cat_sum.total_sec::NUMERIC / v_total_watch_seconds::NUMERIC) * 100, 1)
          ELSE 0
        END
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

  -- Top watched videos in period
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
        'videoId', top_v.video_id,
        'title', v.title,
        'thumbnailUrl', v.thumbnail_url,
        'duration', v.duration,
        'sessionCount', top_v.session_count,
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
    'success', TRUE,
    'report', jsonb_build_object(
      'childId', p_child_id,
      'period', p_period,
      'totalWatchTimeSeconds', v_total_watch_seconds,
      'watchedVideosCount', v_watched_videos_count,
      'completedVideosCount', v_completed_videos_count,
      'categoryStats', v_category_stats,
      'topWatchedVideos', v_top_videos
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;
