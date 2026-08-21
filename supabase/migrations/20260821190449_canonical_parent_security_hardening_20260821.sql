-- ============================================================================
-- Migration: 20260821190449_canonical_parent_security_hardening_20260821.sql
-- Purpose: Reconstruct the live canonical parent-security definitions.
-- Source of truth: live production PostgreSQL definitions inspected 2026-08-21.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_parent_settings_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_rec RECORD;
BEGIN
  IF v_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN RETURN NULL; END IF;

  SELECT id, user_id, failed_attempts, locked_until, pin_hash,
         daily_time_limit_minutes, allowed_categories, bedtime_start,
         bedtime_end, created_at, updated_at
    INTO v_rec
    FROM public.parent_settings
   WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'id', NULL, 'user_id', v_user_id, 'failed_attempts', 0,
      'locked_until', NULL, 'is_locked', FALSE, 'has_pin', FALSE,
      'daily_time_limit_minutes', NULL, 'allowed_categories', NULL,
      'bedtime_start', NULL, 'bedtime_end', NULL,
      'created_at', NULL, 'updated_at', NULL
    );
  END IF;

  RETURN jsonb_build_object(
    'id', v_rec.id,
    'user_id', v_rec.user_id,
    'failed_attempts', COALESCE(v_rec.failed_attempts, 0),
    'locked_until', v_rec.locked_until,
    'is_locked', (v_rec.locked_until IS NOT NULL AND v_rec.locked_until > NOW()),
    'has_pin', (v_rec.pin_hash IS NOT NULL AND v_rec.pin_hash <> ''),
    'daily_time_limit_minutes', v_rec.daily_time_limit_minutes,
    'allowed_categories', v_rec.allowed_categories,
    'bedtime_start', v_rec.bedtime_start,
    'bedtime_end', v_rec.bedtime_end,
    'created_at', v_rec.created_at,
    'updated_at', v_rec.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_parent_pin(p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_pin_hash TEXT;
  v_failed INT := 0;
  v_locked_until TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Kimlik doğrulaması yapılmadı.', 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Yetkisiz erişim: Bu işlem sadece ebeveyn veya yönetici hesapları içindir.', 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
    INTO v_pin_hash, v_failed, v_locked_until
    FROM public.parent_settings
   WHERE user_id = v_user_id
   FOR UPDATE;

  v_failed := COALESCE(v_failed, 0);

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Ebeveyn kilidi geçici olarak kilitlendi. Lütfen bekleyin.', 'is_locked', TRUE, 'needs_setup', FALSE, 'locked_until', v_locked_until);
  END IF;

  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Ebeveyn PIN kodu henüz ayarlanmamış. Lütfen önce PIN oluşturun.', 'is_locked', FALSE, 'needs_setup', TRUE);
  END IF;

  IF extensions.crypt(COALESCE(p_pin, ''), v_pin_hash) = v_pin_hash THEN
    UPDATE public.parent_settings
       SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
     WHERE user_id = v_user_id;
    RETURN jsonb_build_object('success', TRUE, 'message', NULL, 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  v_failed := v_failed + 1;
  IF v_failed >= 5 THEN
    v_locked_until := NOW() + INTERVAL '15 minutes';
    UPDATE public.parent_settings
       SET failed_attempts = v_failed, locked_until = v_locked_until, updated_at = NOW()
     WHERE user_id = v_user_id;
    RETURN jsonb_build_object('success', FALSE, 'message', 'Çok fazla hatalı deneme! 15 dakika boyunca kilitlendi.', 'is_locked', TRUE, 'needs_setup', FALSE, 'failed_attempts', v_failed, 'locked_until', v_locked_until);
  END IF;

  UPDATE public.parent_settings
     SET failed_attempts = v_failed, updated_at = NOW()
   WHERE user_id = v_user_id;
  RETURN jsonb_build_object('success', FALSE, 'message', 'Hatalı PIN!', 'is_locked', FALSE, 'needs_setup', FALSE, 'failed_attempts', v_failed);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_parent_pin(p_new_pin TEXT, p_old_pin TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_current_hash TEXT;
  v_failed INT := 0;
  v_locked_until TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Kimlik doğrulaması yapılmadı.'; END IF;
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN RAISE EXCEPTION 'Sadece ebeveyn veya admin PIN değiştirebilir.'; END IF;
  IF p_new_pin IS NULL OR p_new_pin !~ '^[0-9]{4}$' THEN RAISE EXCEPTION 'Yeni PIN 4 haneli rakamlardan oluşmalıdır.'; END IF;

  SELECT pin_hash, failed_attempts, locked_until
    INTO v_current_hash, v_failed, v_locked_until
    FROM public.parent_settings WHERE user_id = v_user_id FOR UPDATE;
  v_failed := COALESCE(v_failed, 0);

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN RAISE EXCEPTION 'Ebeveyn kilidi aktifken PIN değiştirilemez.'; END IF;

  IF v_current_hash IS NOT NULL AND v_current_hash <> '' THEN
    IF p_old_pin IS NULL OR extensions.crypt(p_old_pin, v_current_hash) <> v_current_hash THEN
      v_failed := v_failed + 1;
      IF v_failed >= 5 THEN
        v_locked_until := NOW() + INTERVAL '15 minutes';
        UPDATE public.parent_settings SET failed_attempts = v_failed, locked_until = v_locked_until, updated_at = NOW() WHERE user_id = v_user_id;
        RAISE EXCEPTION 'Mevcut PIN doğrulaması başarısız. Hesap 15 dakika kilitlendi.';
      END IF;
      UPDATE public.parent_settings SET failed_attempts = v_failed, updated_at = NOW() WHERE user_id = v_user_id;
      RAISE EXCEPTION 'Mevcut PIN doğrulaması başarısız.';
    END IF;
  END IF;

  UPDATE public.parent_settings
     SET pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf')),
         failed_attempts = 0, locked_until = NULL, updated_at = NOW()
   WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (user_id, pin_hash, failed_attempts, locked_until, updated_at)
    VALUES (v_user_id, extensions.crypt(p_new_pin, extensions.gen_salt('bf')), 0, NULL, NOW());
  END IF;
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_parent_settings(
  p_daily_time_limit_minutes INT DEFAULT NULL,
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
  IF v_user_role NOT IN ('parent', 'admin') THEN RAISE EXCEPTION 'Sadece ebeveyn veya admin ayarları değiştirebilir.'; END IF;
  UPDATE public.parent_settings
     SET daily_time_limit_minutes = p_daily_time_limit_minutes,
         allowed_categories = p_allowed_categories,
         bedtime_start = p_bedtime_start,
         bedtime_end = p_bedtime_end,
         updated_at = NOW()
   WHERE user_id = v_user_id;
  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (user_id, daily_time_limit_minutes, allowed_categories, bedtime_start, bedtime_end)
    VALUES (v_user_id, p_daily_time_limit_minutes, p_allowed_categories, p_bedtime_start, p_bedtime_end);
  END IF;
  RETURN TRUE;
END;
$$;
