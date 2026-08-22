CREATE OR REPLACE FUNCTION public.update_parent_settings(
  p_daily_time_limit_minutes INTEGER DEFAULT NULL,
  p_allowed_categories TEXT[] DEFAULT NULL,
  p_bedtime_start TEXT DEFAULT NULL,
  p_bedtime_end TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN FALSE; END IF;

  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Sadece ebeveyn veya admin ayarları değiştirebilir.';
  END IF;

  IF p_daily_time_limit_minutes IS NOT NULL AND p_daily_time_limit_minutes < 0 THEN
    RAISE EXCEPTION 'Günlük süre sınırı negatif olamaz.';
  END IF;

  IF p_allowed_categories IS NOT NULL AND EXISTS (
    SELECT 1
    FROM unnest(p_allowed_categories) AS category_id
    WHERE category_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.id = category_id)
  ) THEN
    RAISE EXCEPTION 'İzin verilen kategori listesinde geçersiz kategori bulunuyor.';
  END IF;

  IF (p_bedtime_start IS NULL) <> (p_bedtime_end IS NULL) THEN
    RAISE EXCEPTION 'Uyku saati başlangıç ve bitiş birlikte belirtilmelidir.';
  END IF;

  IF p_bedtime_start IS NOT NULL AND (
    p_bedtime_start !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
    OR p_bedtime_end !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
  ) THEN
    RAISE EXCEPTION 'Uyku saatleri HH:MM biçiminde geçerli bir saat olmalıdır.';
  END IF;

  UPDATE public.parent_settings
  SET daily_time_limit_minutes = p_daily_time_limit_minutes,
      allowed_categories = p_allowed_categories,
      bedtime_start = p_bedtime_start,
      bedtime_end = p_bedtime_end,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (
      user_id, daily_time_limit_minutes, allowed_categories, bedtime_start, bedtime_end
    ) VALUES (
      v_user_id, p_daily_time_limit_minutes, p_allowed_categories, p_bedtime_start, p_bedtime_end
    );
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) TO authenticated;
