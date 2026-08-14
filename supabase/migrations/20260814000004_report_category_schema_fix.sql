-- ============================================================================
-- Migration: 20260814000004_report_category_schema_fix.sql
-- Description: CRIT-22 Schema Mismatch Fix for get_parent_child_usage_report
--              - Replaces nonexistent c.name with c.title
--              - Replaces nonexistent c.color with c.icon_name (categoryIcon)
--              - Preserves canonical Europe/Istanbul day-start boundary and all metrics
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

  -- Compute start time based on period with canonical Europe/Istanbul timezone alignment
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

  -- 2. Category distribution (CRIT-22: Schema fix matching public.categories actual columns)
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
      v.category_id,
      SUM(s.watched_seconds) AS total_sec,
      COUNT(DISTINCT s.video_id) AS vid_count
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND s.started_at >= v_start_time
      AND v.is_deleted = FALSE
    GROUP BY v.category_id
  ) cat_sum
  JOIN public.categories c ON c.id = cat_sum.category_id;

  -- 3. Top watched videos in period
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
      s.video_id,
      COUNT(s.id) AS session_count,
      SUM(s.watched_seconds) AS total_sec
    FROM public.watch_history_sessions s
    JOIN public.videos v ON v.id = s.video_id
    WHERE s.user_id = p_child_id
      AND s.started_at >= v_start_time
      AND v.is_deleted = FALSE
    GROUP BY s.video_id
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

-- DCL Permissions
REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;
