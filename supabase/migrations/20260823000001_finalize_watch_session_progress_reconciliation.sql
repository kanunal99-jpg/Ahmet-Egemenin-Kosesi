-- Keep the canonical watch-session accounting contract aligned with playback resume state.
-- The server-calculated final session position is authoritative; the client-provided
-- p_watched_seconds is intentionally ignored for anti-tampering purposes.

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
  v_user UUID := auth.uid();
  v_video UUID;
  v_started TIMESTAMPTZ;
  v_last TIMESTAMPTZ;
  v_total INT;
  v_duration INT;
  v_elapsed BIGINT;
  v_start TIMESTAMPTZ;
  v_raw BIGINT;
  v_accept BIGINT;
  v_vremain BIGINT;
  v_sremain BIGINT;
  v_eremain BIGINT;
  v_final INT;
  v_completed BOOLEAN := FALSE;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF v_user IS NULL OR p_session_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz oturum');
  END IF;

  SELECT video_id, started_at, last_heartbeat_at, watched_seconds
    INTO v_video, v_started, v_last, v_total
  FROM public.watch_history_sessions
  WHERE id = p_session_id AND user_id = v_user AND ended_at IS NULL
  FOR UPDATE;

  IF v_video IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz veya daha önce sonlandırılmış oturum.');
  END IF;

  v_elapsed := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_started))::BIGINT);
  v_start := COALESCE(v_last, v_started);
  v_raw := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_start))::BIGINT);
  v_accept := LEAST(v_raw, 10);
  v_eremain := GREATEST(0, v_elapsed - v_total::BIGINT);
  v_accept := LEAST(v_accept, v_eremain);
  v_sremain := GREATEST(0, 43200::BIGINT - v_total::BIGINT);
  v_accept := LEAST(v_accept, v_sremain);

  SELECT duration INTO v_duration FROM public.videos WHERE id = v_video;
  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_vremain := GREATEST(0, v_duration::BIGINT - v_total::BIGINT);
    v_accept := LEAST(v_accept, v_vremain);
  END IF;

  IF v_accept > 0 THEN
    INSERT INTO public.watch_history_session_events(
      session_id, user_id, video_id, started_at, ended_at, watched_seconds
    ) VALUES (
      p_session_id, v_user, v_video, v_start,
      v_start + (v_accept || ' seconds')::INTERVAL, v_accept::INT
    );
  END IF;

  v_final := (v_total + v_accept)::INT;

  IF v_duration IS NOT NULL AND v_duration > 0 THEN
    v_completed := p_completed IS TRUE AND v_final >= (v_duration * 0.9);
  ELSE
    v_completed := COALESCE(p_completed, false) AND v_final > 0;
  END IF;

  UPDATE public.watch_history_sessions
  SET ended_at = v_now, watched_seconds = v_final, completed = v_completed
  WHERE id = p_session_id AND user_id = v_user;

  INSERT INTO public.watch_history(user_id, video_id, progress_seconds, completed, updated_at)
  VALUES (v_user, v_video, v_final, v_completed, v_now)
  ON CONFLICT (user_id, video_id) DO UPDATE
  SET progress_seconds = GREATEST(public.watch_history.progress_seconds, EXCLUDED.progress_seconds),
      completed = CASE WHEN public.watch_history.completed THEN TRUE ELSE EXCLUDED.completed END,
      updated_at = v_now;

  RETURN jsonb_build_object('success', true, 'watched_seconds', v_final);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INTEGER, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INTEGER, BOOLEAN) TO authenticated;
