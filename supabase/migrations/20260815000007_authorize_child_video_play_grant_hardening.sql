-- ============================================================================
-- Migration: 20260815000007_authorize_child_video_play_grant_hardening.sql
-- Description: Historical Child Video Play Authorization Hardening
-- ============================================================================

CREATE OR REPLACE FUNCTION public.authorize_child_video_play(
  p_video_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_video RECORD;
  v_effective_parent_id UUID;
  v_allowed_categories TEXT[];
  v_bedtime_start TEXT;
  v_bedtime_end TEXT;
  v_current_time_str TEXT;
  v_daily_limit INT;
  v_used_today_seconds INT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'auth_required');
  END IF;

  SELECT id, category_id, is_active, is_deleted
  INTO v_video
  FROM public.videos
  WHERE id = p_video_id;

  IF v_video.id IS NULL OR v_video.is_deleted IS TRUE OR v_video.is_active IS FALSE THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'video_unavailable');
  END IF;

  -- Get effective parent id (self if parent)
  SELECT COALESCE(
    (SELECT parent_id FROM public.parent_children WHERE child_id = v_user_id LIMIT 1),
    v_user_id
  ) INTO v_effective_parent_id;

  -- Check parent settings
  SELECT allowed_categories, bedtime_start, bedtime_end, daily_time_limit_minutes
  INTO v_allowed_categories, v_bedtime_start, v_bedtime_end, v_daily_limit
  FROM public.parent_settings
  WHERE user_id = v_effective_parent_id;

  -- 1. Category restriction
  IF v_allowed_categories IS NOT NULL AND array_length(v_allowed_categories, 1) > 0 THEN
    IF NOT (v_video.category_id = ANY(v_allowed_categories)) THEN
      RETURN jsonb_build_object('allowed', FALSE, 'reason', 'category_blocked');
    END IF;
  END IF;

  -- 2. Bedtime restriction
  IF v_bedtime_start IS NOT NULL AND v_bedtime_end IS NOT NULL AND v_bedtime_start <> '' AND v_bedtime_end <> '' THEN
    v_current_time_str := TO_CHAR(NOW() AT TIME ZONE 'Europe/Istanbul', 'HH24:MI');
    IF v_bedtime_start <= v_bedtime_end THEN
      IF v_current_time_str >= v_bedtime_start AND v_current_time_str < v_bedtime_end THEN
        RETURN jsonb_build_object('allowed', FALSE, 'reason', 'bedtime_active');
      END IF;
    ELSE
      IF v_current_time_str >= v_bedtime_start OR v_current_time_str < v_bedtime_end THEN
        RETURN jsonb_build_object('allowed', FALSE, 'reason', 'bedtime_active');
      END IF;
    END IF;
  END IF;

  -- 3. Daily time limit restriction
  IF v_daily_limit IS NOT NULL AND v_daily_limit > 0 THEN
    v_used_today_seconds := public.get_effective_child_daily_watch_seconds(v_user_id);
    IF v_used_today_seconds >= (v_daily_limit * 60) THEN
      RETURN jsonb_build_object('allowed', FALSE, 'reason', 'daily_limit_reached');
    END IF;
  END IF;

  RETURN jsonb_build_object('allowed', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated;
