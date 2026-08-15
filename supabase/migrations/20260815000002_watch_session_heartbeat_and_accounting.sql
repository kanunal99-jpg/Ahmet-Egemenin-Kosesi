-- ============================================================================
-- Migration: 20260815000002_watch_session_heartbeat_and_accounting.sql
-- Description: CRIT-42 (Canonical active/finalized midnight overlap calculation)
--              CRIT-43 (Server-authoritative watch session heartbeat model)
--              CRIT-44 (Eliminate client watched_seconds escalation in finalize)
--              CRIT-45 (Usage report period contract preservation and schema compatibility)
--              CRIT-40 (Playback progress vs watched duration separation preservation)
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
        s.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(COALESCE(s.ended_at, NOW()), NOW()) - GREATEST(s.started_at, v_today_start)
            )
          )::BIGINT
        ),
        43200
      )
    ),
    0
  ) INTO v_total_seconds
  FROM public.watch_history_sessions s
  WHERE s.user_id = p_user_id
    AND COALESCE(s.ended_at, NOW()) >= v_today_start
    AND s.started_at <= NOW();

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
  -- 1. Authentication check
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  -- 2. Input validation
  IF p_session_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz oturum kimliği.');
  END IF;

  -- 3. Row lock & ownership & active lifecycle check (FOR UPDATE)
  SELECT id, user_id, video_id, started_at, last_heartbeat_at, watched_seconds
  INTO v_session
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND ended_at IS NULL
  FOR UPDATE;

  IF v_session.id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Oturum bulunamadı veya daha önce sonlandırılmış.');
  END IF;

  -- 4. Session start timestamp sanity (cannot be in the future)
  IF v_session.started_at > v_now THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz oturum başlangıç zamanı.');
  END IF;

  -- 5. Calculate elapsed time since last heartbeat or session start
  v_delta_seconds := GREATEST(
    0,
    EXTRACT(EPOCH FROM (v_now - COALESCE(v_session.last_heartbeat_at, v_session.started_at)))::BIGINT
  );

  -- 6. Bound delta: Client interval is 6 seconds.
  -- Max allowed delta is 10 seconds (6s interval + 4s network jitter budget).
  -- Any gap larger than 10 seconds is strictly capped to 10s to prevent offline duration inflation.
  v_delta_seconds := LEAST(v_delta_seconds, 10);

  -- 7. Monotonic duration increment capped at max daily limit (43200s / 12 hours)
  v_new_watched_seconds := LEAST(
    (v_session.watched_seconds + v_delta_seconds)::BIGINT,
    43200::BIGINT
  )::INT;

  -- 8. Atomic update with last_heartbeat_at timestamp
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


-- 4. CRIT-40 & CRIT-43 & CRIT-44: Finalize Watch Session RPC (Server-Authoritative)
CREATE OR REPLACE FUNCTION public.finalize_watch_session(
  p_session_id UUID,
  p_watched_seconds INTEGER DEFAULT NULL,
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
  v_now TIMESTAMPTZ := NOW();
BEGIN
  -- 1. Authentication check
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  IF p_session_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz oturum kimliği.');
  END IF;

  -- 2. Verify session belongs to caller and is active (FOR UPDATE lock)
  SELECT video_id, started_at, last_heartbeat_at, watched_seconds
  INTO v_video_id, v_started_at, v_last_heartbeat_at, v_session_watched_seconds
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user_id AND ended_at IS NULL
  FOR UPDATE;

  IF v_video_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz veya daha önce sonlandırılmış oturum.');
  END IF;

  -- 3. Authoritative DB elapsed time calculation
  IF v_started_at > v_now THEN
    v_actual_elapsed_seconds := 0;
  ELSE
    v_actual_elapsed_seconds := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_started_at))::BIGINT);
  END IF;

  -- 4. CRIT-44: Server-Authoritative Duration Accumulation
  -- Trailing delta between last heartbeat and finalize (capped at 10s: 6s interval + 4s jitter budget)
  v_trailing_delta := LEAST(
    GREATEST(0, EXTRACT(EPOCH FROM (v_now - COALESCE(v_last_heartbeat_at, v_started_at)))::BIGINT),
    10
  );

  -- STRICTLY server-authoritative: client's p_watched_seconds is NEVER used to inflate watched duration!
  -- v_accumulated_seconds = v_session_watched_seconds + v_trailing_delta
  v_accumulated_seconds := v_session_watched_seconds + v_trailing_delta;

  -- 5. Sanitize watched seconds against actual elapsed wall-clock, video duration, and max cap (43200)
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_video_id;

  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_sanitized_seconds := LEAST(
      v_accumulated_seconds,
      v_actual_elapsed_seconds,
      v_duration::BIGINT,
      43200::BIGINT
    )::INT;

    -- Completion verification: requires client completed flag AND at least 90% verified watched duration
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

  -- 6. Finalize session atomically
  UPDATE public.watch_history_sessions
  SET ended_at = v_now,
      watched_seconds = v_sanitized_seconds,
      completed = v_verified_completed
  WHERE id = p_session_id AND user_id = v_user_id;

  -- 7. CRIT-40: Update cumulative completion state in watch_history WITHOUT overwriting progress_seconds
  -- If row exists, DO UPDATE only updates completed and updated_at; progress_seconds is preserved untouched.
  INSERT INTO public.watch_history (user_id, video_id, progress_seconds, completed, updated_at)
  VALUES (v_user_id, v_video_id, 0, v_verified_completed, v_now)
  ON CONFLICT (user_id, video_id)
  DO UPDATE SET
    completed = CASE WHEN watch_history.completed THEN TRUE ELSE EXCLUDED.completed END,
    updated_at = v_now;

  RETURN jsonb_build_object(
    'success', TRUE,
    'watched_seconds', v_sanitized_seconds
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;


-- 5. CRIT-39, CRIT-42 & CRIT-45: Canonical Usage Report with Full Period Support & Contract Preservation
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
  -- 1. Authentication check
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'Kimlik doğrulaması yapılmadı.',
      'period', p_period,
      'totalWatchTimeSeconds', 0,
      'watchedVideosCount', 0,
      'completedVideosCount', 0,
      'categoryStats', '[]'::jsonb,
      'topWatchedVideos', '[]'::jsonb
    );
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

  -- 2. Authorization check (CRIT-31 & CRIT-32)
  IF v_caller_role = 'admin' THEN
    v_is_authorized := TRUE;
  ELSIF v_caller_role = 'parent' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.parent_children
      WHERE parent_id = v_caller_id AND child_id = p_child_id
    ) INTO v_is_authorized;
  ELSIF v_caller_id = p_child_id THEN
    v_is_authorized := TRUE;
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

  -- 3. CRIT-45: Compute start time supporting all periods with canonical timezone alignment
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

  -- 4. Canonical session overlap totals (CRIT-39 & CRIT-42 & CRIT-43):
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

  -- 5. Category distribution (CRIT-22 & CRIT-45: Preserves exact contract fields)
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
        'categoryColor', COALESCE(c.icon_name, 'film'),
        'watchTimeSeconds', COALESCE(cat_sum.total_sec, 0),
        'totalSeconds', COALESCE(cat_sum.total_sec, 0),
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

  -- 6. Top watched videos in period (CRIT-39 & CRIT-45: Preserves exact contract fields)
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
        'duration', v.duration,
        'watchCount', top_v.session_count,
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

  -- 7. Return flat JSON matching UsageReportData frontend contract
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
