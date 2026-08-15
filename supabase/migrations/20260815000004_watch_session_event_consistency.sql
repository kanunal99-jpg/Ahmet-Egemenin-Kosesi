-- ============================================================================
-- Migration: 20260815000004_watch_session_event_consistency.sql
-- Description: CRIT-48 (Event Ledger / Session Total Consistency Hardening)
--              Strictly guarantees SUM(events.watched_seconds) = session.watched_seconds
--              Clamps accepted delta BEFORE event insertion to prevent ledger divergence
--              Preserves CRIT-40, CRIT-42, CRIT-43, CRIT-44, CRIT-45, CRIT-46, CRIT-47
-- Mode: SOURCE CODE ONLY - NO LIVE SUPABASE EXECUTION
-- ============================================================================

-- 1. Heartbeat RPC with Delta Clamping & Invariant Synchronization (CRIT-43, CRIT-46, CRIT-48)
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

  -- 6. CRIT-48: Compute allowable headroom based on video duration and daily cap (43200)
  -- 6a. Network jitter limit: client sends every 6s, max allowed delta window is 10s
  v_accepted_delta := LEAST(v_raw_delta, 10);

  -- 6b. Session 12-hour cap (43200s) headroom
  v_remaining_session_cap := GREATEST(0, 43200::BIGINT - v_session.watched_seconds::BIGINT);
  v_accepted_delta := LEAST(v_accepted_delta, v_remaining_session_cap);

  -- 6c. Video duration headroom clamp (if duration > 0)
  SELECT duration INTO v_duration FROM public.videos WHERE id = v_session.video_id;
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_remaining_video_seconds := GREATEST(0, v_duration::BIGINT - v_session.watched_seconds::BIGINT);
    v_accepted_delta := LEAST(v_accepted_delta, v_remaining_video_seconds);
  END IF;

  -- 7. Insert temporal playback segment into event ledger only for strictly positive accepted delta
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

  -- 8. Invariant: session.watched_seconds increments by exact accepted delta (CRIT-48)
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


-- 2. Finalize RPC with Clamped Trailing Segment & Invariant Guarantee (CRIT-40, CRIT-44, CRIT-46, CRIT-48)
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

  -- 4. CRIT-44 & CRIT-48: Compute trailing accepted delta with all clamp boundaries BEFORE inserting
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
