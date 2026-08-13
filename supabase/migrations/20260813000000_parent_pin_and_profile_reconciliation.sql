-- ==============================================================================
-- MIGRATION: 20260813000000_parent_pin_and_profile_reconciliation.sql
-- DESCRIPTION: Reconciles profile backfills, parent PIN RPC return contracts,
--              lockout policies (5 attempts / 15 mins), and missing-PIN handling.
-- ==============================================================================

-- 1. SAFE IDEMPOTENT BACKFILL FOR EXISTING ORPHAN AUTH USERS
-- Ensures any auth.users created prior to the handle_new_user trigger have a profile.
-- Existing profiles (admins, publishers, etc.) are 100% untouched via ON CONFLICT DO NOTHING.
INSERT INTO public.profiles (id, first_name, last_name, role, created_at, updated_at)
SELECT
  u.id,
  NULLIF(TRIM(u.raw_user_meta_data->>'first_name'), ''),
  NULLIF(TRIM(u.raw_user_meta_data->>'last_name'), ''),
  CASE
    WHEN LOWER(TRIM(COALESCE(u.raw_user_meta_data->>'role', ''))) = 'parent' THEN 'parent'
    ELSE 'child'
  END,
  COALESCE(u.created_at, NOW()),
  NOW()
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- 2. RECONCILED get_my_parent_settings_status()
-- Returns non-sensitive status object with explicit 'has_pin' boolean flag.
CREATE OR REPLACE FUNCTION public.get_my_parent_settings_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_rec RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_rec
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'id', NULL,
      'user_id', v_user_id,
      'failed_attempts', 0,
      'locked_until', NULL,
      'is_locked', FALSE,
      'has_pin', FALSE,
      'daily_time_limit_minutes', NULL,
      'allowed_categories', NULL,
      'bedtime_start', NULL,
      'bedtime_end', NULL,
      'created_at', NULL,
      'updated_at', NULL
    );
  END IF;

  RETURN jsonb_build_object(
    'id', v_rec.id,
    'user_id', v_rec.user_id,
    'failed_attempts', COALESCE(v_rec.failed_attempts, 0),
    'locked_until', v_rec.locked_until,
    'is_locked', (v_rec.locked_until IS NOT NULL AND v_rec.locked_until > NOW()),
    'has_pin', (v_rec.pin_hash IS NOT NULL AND v_rec.pin_hash != ''),
    'daily_time_limit_minutes', v_rec.daily_time_limit_minutes,
    'allowed_categories', v_rec.allowed_categories,
    'bedtime_start', v_rec.bedtime_start,
    'bedtime_end', v_rec.bedtime_end,
    'created_at', v_rec.created_at,
    'updated_at', v_rec.updated_at
  );
END;
$$;

-- 3. RECONCILED verify_parent_pin(p_pin TEXT)
-- Returns structured JSONB contract handling lockouts and missing PIN gracefully.
CREATE OR REPLACE FUNCTION public.verify_parent_pin(p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_pin_hash TEXT;
  v_failed INT;
  v_locked_until TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Kimlik doğrulaması yapılmadı.',
      'is_locked', FALSE
    );
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
  INTO v_pin_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  -- 1. Check active lockout
  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn kilidi geçici olarak kilitlendi. Lütfen bekleyin.',
      'is_locked', TRUE,
      'locked_until', v_locked_until
    );
  END IF;

  -- 2. Check if PIN has not been set yet
  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn PIN kodu henüz ayarlanmamış. Lütfen önce PIN oluşturun.',
      'is_locked', FALSE,
      'needs_setup', TRUE
    );
  END IF;

  -- 3. Verify PIN against bcrypt hash
  IF v_pin_hash = crypt(p_pin, v_pin_hash) THEN
    -- Correct PIN: reset counters
    UPDATE public.parent_settings
    SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
      'success', TRUE,
      'message', NULL,
      'is_locked', FALSE
    );
  ELSE
    -- Incorrect PIN: increment counter
    v_failed := COALESCE(v_failed, 0) + 1;
    IF v_failed >= 5 THEN
      v_locked_until := NOW() + INTERVAL '15 minutes';
      UPDATE public.parent_settings
      SET failed_attempts = v_failed, locked_until = v_locked_until, updated_at = NOW()
      WHERE user_id = v_user_id;

      RETURN jsonb_build_object(
        'success', FALSE,
        'message', 'Çok fazla hatalı deneme! 15 dakika boyunca kilitlendi.',
        'is_locked', TRUE,
        'failed_attempts', v_failed,
        'locked_until', v_locked_until
      );
    ELSE
      UPDATE public.parent_settings
      SET failed_attempts = v_failed, updated_at = NOW()
      WHERE user_id = v_user_id;

      RETURN jsonb_build_object(
        'success', FALSE,
        'message', 'Hatalı PIN!',
        'is_locked', FALSE,
        'failed_attempts', v_failed
      );
    END IF;
  END IF;
END;
$$;

-- 4. RECONCILED update_parent_pin(p_new_pin TEXT, p_old_pin TEXT)
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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Authorization check: only parent or admin can modify parent PIN
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RAISE EXCEPTION 'Sadece ebeveyn veya admin PIN değiştirebilir.';
  END IF;

  SELECT pin_hash INTO v_current_hash
  FROM public.parent_settings
  WHERE user_id = v_user_id
  FOR UPDATE;

  -- If PIN is already set, old PIN verification is mandatory
  IF v_current_hash IS NOT NULL AND v_current_hash != '' THEN
    IF p_old_pin IS NULL OR crypt(p_old_pin, v_current_hash) != v_current_hash THEN
      RAISE EXCEPTION 'Mevcut PIN doğrulaması başarısız.';
    END IF;
  END IF;

  UPDATE public.parent_settings
  SET pin_hash = crypt(p_new_pin, gen_salt('bf')),
      failed_attempts = 0,
      locked_until = NULL,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.parent_settings (user_id, pin_hash, failed_attempts, locked_until, updated_at)
    VALUES (v_user_id, crypt(p_new_pin, gen_salt('bf')), 0, NULL, NOW());
  END IF;

  RETURN TRUE;
END;
$$;
