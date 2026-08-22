CREATE OR REPLACE FUNCTION public.get_my_effective_parental_settings()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_settings public.parent_settings%ROWTYPE;
  v_has_parent BOOLEAN := FALSE;
BEGIN
  IF v_user IS NULL THEN RETURN NULL; END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;

  IF v_role IN ('parent', 'admin') THEN
    SELECT * INTO v_settings FROM public.parent_settings WHERE user_id = v_user;
  ELSIF v_role = 'child' THEN
    SELECT ps.* INTO v_settings
    FROM public.parent_settings ps
    JOIN public.parent_children pc ON pc.parent_id = ps.user_id
    WHERE pc.child_id = v_user
    ORDER BY ps.updated_at DESC
    LIMIT 1;

    IF FOUND THEN
      v_has_parent := TRUE;
    ELSE
      SELECT * INTO v_settings FROM public.parent_settings WHERE user_id = v_user;
    END IF;
  ELSE
    RETURN NULL;
  END IF;

  IF NOT FOUND AND v_settings.user_id IS NULL THEN
    RETURN jsonb_build_object(
      'daily_time_limit_minutes', 0,
      'allowed_categories', NULL,
      'bedtime_start', NULL,
      'bedtime_end', NULL,
      'has_parent', v_has_parent
    );
  END IF;

  RETURN jsonb_build_object(
    'daily_time_limit_minutes', COALESCE(v_settings.daily_time_limit_minutes, 0),
    'allowed_categories', v_settings.allowed_categories,
    'bedtime_start', v_settings.bedtime_start,
    'bedtime_end', v_settings.bedtime_end,
    'has_parent', v_has_parent
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_effective_parental_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_effective_parental_settings() TO authenticated;
