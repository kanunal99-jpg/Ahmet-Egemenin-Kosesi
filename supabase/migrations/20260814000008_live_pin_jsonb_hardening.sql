-- ============================================================================
-- CRIT-25: LIVE verify_parent_pin JSONB/auth hardening
-- ============================================================================
-- Rename the legacy BOOLEAN function instead of DROP so rollback/reference
-- inspection remains possible, then expose the frontend-compatible JSONB RPC.
ALTER FUNCTION public.verify_parent_pin(TEXT)
  RENAME TO verify_parent_pin_legacy_boolean;

CREATE FUNCTION public.verify_parent_pin(p_pin TEXT)
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
    RETURN jsonb_build_object('success', FALSE, 'message', 'Oturum açılmadı.', 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  SELECT role INTO v_user_role
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_user_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Ebeveyn PIN doğrulaması için yetkiniz bulunmamaktadır.', 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
    INTO v_pin_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  v_failed := COALESCE(v_failed, 0);

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Çok fazla hatalı deneme. Lütfen kilit süresinin dolmasını bekleyin.', 'is_locked', TRUE, 'needs_setup', FALSE);
  END IF;

  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Lütfen önce Ebeveyn PIN kodunuzu oluşturun.', 'is_locked', FALSE, 'needs_setup', TRUE);
  END IF;

  IF crypt(COALESCE(p_pin, ''), v_pin_hash) = v_pin_hash THEN
    UPDATE public.parent_settings
    SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
    WHERE user_id = v_user_id;
    RETURN jsonb_build_object('success', TRUE, 'message', 'PIN doğrulandı.', 'is_locked', FALSE, 'needs_setup', FALSE);
  END IF;

  v_failed := v_failed + 1;

  IF v_failed >= 5 THEN
    v_locked_until := NOW() + INTERVAL '15 minutes';
    UPDATE public.parent_settings
    SET failed_attempts = v_failed, locked_until = v_locked_until, updated_at = NOW()
    WHERE user_id = v_user_id;
    RETURN jsonb_build_object('success', FALSE, 'message', 'Çok fazla hatalı PIN denemesi. 15 dakika boyunca kilitlendi.', 'is_locked', TRUE, 'needs_setup', FALSE);
  END IF;

  UPDATE public.parent_settings
  SET failed_attempts = v_failed, updated_at = NOW()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', FALSE, 'message', 'Hatalı PIN.', 'is_locked', FALSE, 'needs_setup', FALSE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;
