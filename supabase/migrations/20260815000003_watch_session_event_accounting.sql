-- ============================================================================
-- Migration: 20260815000003_watch_session_event_accounting.sql
-- Description: CRIT-46 (Temporal Watched Duration Partitioning via Event Ledger)
--              CRIT-47 (Daily Limit & Usage Report Temporal Accounting from Event Ledger)
--              CRIT-40 (Playback Progress vs Duration Separation Preservation)
--              CRIT-43 (Server-Authoritative Playback Heartbeat Preservation)
--              CRIT-44 (Eliminate Client Watched Duration Escalation Preservation)
--              CRIT-45 (Full Report Period Contract & Category Schema Preservation)
-- Mode: SOURCE CODE ONLY - NO LIVE SUPABASE EXECUTION
-- ============================================================================

-- 1. Create Temporal Watch Events Table (CRIT-46)
CREATE TABLE IF NOT EXISTS public.watch_history_session_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.watch_history_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ NOT NULL,
  watched_seconds INT NOT NULL CHECK (watched_seconds >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_watch_event_chronology CHECK (ended_at >= started_at)
);

-- 2. Indexes for efficient temporal filtering and aggregation (CRIT-46 & CRIT-47)
CREATE INDEX IF NOT EXISTS idx_session_events_session_started
  ON public.watch_history_session_events (session_id, started_at);

CREATE INDEX IF NOT EXISTS idx_session_events_user_started
  ON public.watch_history_session_events (user_id, started_at);

CREATE INDEX IF NOT EXISTS idx_session_events_user_ended
  ON public.watch_history_session_events (user_id, ended_at);

CREATE INDEX IF NOT EXISTS idx_session_events_video_started
  ON public.watch_history_session_events (video_id, started_at);

-- 3. Row Level Security & DCL
ALTER TABLE public.watch_history_session_events ENABLE ROW LEVEL SECURITY;

-- Deny direct DML (INSERT, UPDATE, DELETE) for all client roles
DROP POLICY IF EXISTS "Session events viewable by owner" ON public.watch_history_session_events;
CREATE POLICY "Session events viewable by owner"
  ON public.watch_history_session_events
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON public.watch_history_session_events FROM PUBLIC, anon;
GRANT SELECT ON public.watch_history_session_events TO authenticated;


-- 4. Heartbeat RPC with Atomic Temporal Event Insertion & Headroom Clamping (CRIT-43, CRIT-46 & CRIT-48)
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
  v_event_start TIMESTAMPTZ;
  v_raw_delta BIGINT;
  v_accepted_delta BIGINT;
  v_event_end TIMESTAMPTZ;
  v_duration INT;
  v_remaining_video_seconds BIGINT;
  v_remaining_session_cap BIGINT;
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
  v_event_start := COALESCE(v_session.last_heartbeat_at, v_session.started_at);
  v_raw_delta := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_event_start))::BIGINT);

  -- 6. Bound delta & compute allowable headroom (CRIT-48)
  v_accepted_delta := LEAST(v_raw_delta, 10);

  -- 6a. Session cap (43200s) headroom
  v_remaining_session_cap := GREATEST(0, 43200::BIGINT - v_session.watched_seconds::BIGINT);
  v_accepted_delta := LEAST(v_accepted_delta, v_remaining_session_cap);

  -- 6b. Video duration headroom clamp (if duration > 0)
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_session.video_id;
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_remaining_video_seconds := GREATEST(0, v_duration::BIGINT - v_session.watched_seconds::BIGINT);
    v_accepted_delta := LEAST(v_accepted_delta, v_remaining_video_seconds);
  END IF;

  -- 7. Insert temporal playback segment into event ledger (CRIT-46 & CRIT-48)
  IF v_accepted_delta > 0 THEN
    v_event_end := v_event_start + (v_accepted_delta || ' seconds')::INTERVAL;

    INSERT INTO public.watch_history_session_events (
      session_id,
      user_id,
      video_id,
      started_at,
      ended_at,
      watched_seconds
    )
    VALUES (
      v_session.id,
      v_session.user_id,
      v_session.video_id,
      v_event_start,
      v_event_end,
      v_accepted_delta::INT
    );
  END IF;

  -- 8. Invariant: session metadata duration equals exact ledger increment (CRIT-48)
  v_new_watched_seconds := (v_session.watched_seconds + v_accepted_delta)::INT;

  -- 9. Atomic update with last_heartbeat_at timestamp
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


-- 5. Finalize RPC with Trailing Event Ledger Ingestion & Invariant Guarantee (CRIT-40, CRIT-44, CRIT-46, CRIT-48)
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
  v_event_start TIMESTAMPTZ;
  v_raw_trailing BIGINT;
  v_accepted_trailing BIGINT;
  v_event_end TIMESTAMPTZ;
  v_remaining_video_seconds BIGINT;
  v_remaining_session_cap BIGINT;
  v_remaining_elapsed_seconds BIGINT;
  v_final_watched_seconds INT;
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

  -- 4. CRIT-44, CRIT-46 & CRIT-48: Compute trailing accepted delta clamped BEFORE inserting
  v_event_start := COALESCE(v_last_heartbeat_at, v_started_at);
  v_raw_trailing := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_event_start))::BIGINT);
  v_accepted_trailing := LEAST(v_raw_trailing, 10);

  -- 4a. Actual wall-clock elapsed headroom
  v_remaining_elapsed_seconds := GREATEST(0, v_actual_elapsed_seconds - v_session_watched_seconds::BIGINT);
  v_accepted_trailing := LEAST(v_accepted_trailing, v_remaining_elapsed_seconds);

  -- 4b. Max session cap headroom (43200s)
  v_remaining_session_cap := GREATEST(0, 43200::BIGINT - v_session_watched_seconds::BIGINT);
  v_accepted_trailing := LEAST(v_accepted_trailing, v_remaining_session_cap);

  -- 4c. Video duration headroom clamp (if duration > 0)
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_video_id;
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_remaining_video_seconds := GREATEST(0, v_duration::BIGINT - v_session_watched_seconds::BIGINT);
    v_accepted_trailing := LEAST(v_accepted_trailing, v_remaining_video_seconds);
  END IF;

  -- 5. Insert trailing event segment into ledger only if accepted trailing delta > 0
  IF v_accepted_trailing > 0 THEN
    v_event_end := v_event_start + (v_accepted_trailing || ' seconds')::INTERVAL;

    INSERT INTO public.watch_history_session_events (
      session_id,
      user_id,
      video_id,
      started_at,
      ended_at,
      watched_seconds
    )
    VALUES (
      p_session_id,
      v_user_id,
      v_video_id,
      v_event_start,
      v_event_end,
      v_accepted_trailing::INT
    );
  END IF;

  -- 6. Invariant: session.watched_seconds is strictly equal to old_total + accepted_trailing (CRIT-48)
  v_final_watched_seconds := (v_session_watched_seconds + v_accepted_trailing)::INT;

  -- 7. Verified completion evaluation
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    IF p_completed IS TRUE AND v_final_watched_seconds >= (v_duration * 0.9) THEN
      v_verified_completed := TRUE;
    ELSE
      v_verified_completed := FALSE;
    END IF;
  ELSE
    v_verified_completed := COALESCE(p_completed, FALSE) AND (v_final_watched_seconds > 0);
  END IF;

  -- 8. Finalize session metadata atomically
  UPDATE public.watch_history_sessions
  SET ended_at = v_now,
      watched_seconds = v_final_watched_seconds,
      completed = v_verified_completed
  WHERE id = p_session_id AND user_id = v_user_id;

  -- 9. CRIT-40: Update cumulative completion state in watch_history WITHOUT overwriting progress_seconds
  INSERT INTO public.watch_history (user_id, video_id, progress_seconds, completed, updated_at)
  VALUES (v_user_id, v_video_id, 0, v_verified_completed, v_now)
  ON CONFLICT (user_id, video_id)
  DO UPDATE SET
    completed = CASE WHEN watch_history.completed THEN TRUE ELSE EXCLUDED.completed END,
    updated_at = v_now;

  RETURN jsonb_build_object(
    'success', TRUE,
    'watched_seconds', v_final_watched_seconds
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;


-- 6. CRIT-46 & CRIT-47: Daily Watch Accounting Calculated Strictly From Event Ledger
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

  -- Calculate true daily watch duration by intersecting individual verified playback segments
  -- with today's interval [v_today_start, NOW()].
  -- overlap_start = GREATEST(e.started_at, v_today_start)
  -- overlap_end   = LEAST(e.ended_at, NOW())
  -- overlap_secs  = GREATEST(0, EXTRACT(EPOCH FROM (overlap_end - overlap_start)))
  -- contribution  = LEAST(e.watched_seconds, overlap_secs)
  SELECT COALESCE(
    SUM(
      LEAST(
        e.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(e.ended_at, NOW()) - GREATEST(e.started_at, v_today_start)
            )
          )::BIGINT
        )
      )
    ),
    0
  ) INTO v_total_seconds
  FROM public.watch_history_session_events e
  WHERE e.user_id = p_user_id
    AND e.ended_at >= v_today_start
    AND e.started_at <= NOW();

  RETURN LEAST(v_total_seconds, 43200::BIGINT);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM PUBLIC, anon, authenticated;


-- 7. CRIT-46 & CRIT-47: Usage Report Strictly Calculated From Event Ledger
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

  -- 4. Temporal event overlap aggregations (CRIT-46 & CRIT-47):
  WITH period_events AS (
    SELECT
      e.id AS event_id,
      e.session_id,
      e.video_id,
      v.category_id,
      LEAST(
        e.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(e.ended_at, NOW()) - GREATEST(e.started_at, v_start_time)
            )
          )::BIGINT
        )
      ) AS event_watch_seconds
    FROM public.watch_history_session_events e
    JOIN public.videos v ON v.id = e.video_id
    WHERE e.user_id = p_child_id
      AND e.ended_at >= v_start_time
      AND e.started_at <= NOW()
      AND v.is_deleted = FALSE
  )
  SELECT
    COALESCE(SUM(event_watch_seconds), 0),
    COUNT(DISTINCT video_id) FILTER (WHERE event_watch_seconds > 0)
  INTO
    v_total_watch_seconds,
    v_watched_videos_count
  FROM period_events;

  -- Completed videos count in period (from watch_history_sessions)
  SELECT COUNT(DISTINCT video_id)
  INTO v_completed_videos_count
  FROM public.watch_history_sessions
  WHERE user_id = p_child_id
    AND completed = TRUE
    AND COALESCE(ended_at, NOW()) >= v_start_time;

  -- 5. Category distribution from Event Ledger (CRIT-22, CRIT-45, CRIT-46 & CRIT-47)
  WITH period_events AS (
    SELECT
      e.id AS event_id,
      e.video_id,
      v.category_id,
      LEAST(
        e.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(e.ended_at, NOW()) - GREATEST(e.started_at, v_start_time)
            )
          )::BIGINT
        )
      ) AS event_watch_seconds
    FROM public.watch_history_session_events e
    JOIN public.videos v ON v.id = e.video_id
    WHERE e.user_id = p_child_id
      AND e.ended_at >= v_start_time
      AND e.started_at <= NOW()
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
      SUM(event_watch_seconds) AS total_sec,
      COUNT(DISTINCT video_id) AS vid_count
    FROM period_events
    GROUP BY category_id
  ) cat_sum
  JOIN public.categories c ON c.id = cat_sum.category_id;

  -- 6. Top watched videos from Event Ledger (CRIT-45, CRIT-46 & CRIT-47)
  WITH period_events AS (
    SELECT
      e.session_id,
      e.video_id,
      LEAST(
        e.watched_seconds,
        GREATEST(
          0,
          EXTRACT(
            EPOCH FROM (
              LEAST(e.ended_at, NOW()) - GREATEST(e.started_at, v_start_time)
            )
          )::BIGINT
        )
      ) AS event_watch_seconds
    FROM public.watch_history_session_events e
    JOIN public.videos v ON v.id = e.video_id
    WHERE e.user_id = p_child_id
      AND e.ended_at >= v_start_time
      AND e.started_at <= NOW()
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
      COUNT(DISTINCT session_id) AS session_count,
      SUM(event_watch_seconds) AS total_sec
    FROM period_events
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
