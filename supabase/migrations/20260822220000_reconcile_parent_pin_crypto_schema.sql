-- Reconcile the live parent PIN RPC with the Supabase pgcrypto extension schema.
-- Live database audit on 2026-08-22 confirmed pgcrypto functions live in extensions,
-- while update_parent_pin uses search_path = public, pg_temp.
-- Keep the live JSONB response contract and explicitly qualify crypt/gen_salt.

CREATE OR REPLACE FUNCTION public.update_parent_pin(
  p_new_pin TEXT,
  p_old_pin TEXT DEFAULT NULL
)
RETURNS JSONB
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
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Kimlik doğrulaması yapılmadı.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  SELECT role INTO v_user_role
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_user_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Yetkisiz erişim: Bu işlem sadece ebeveyn veya yönetici hesapları içindir.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  IF p_new_pin IS NULL OR p_new_pin !~ '^[0-9]{4}$' THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Yeni PIN 4 haneli rakamlardan oluşmalıdır.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
    INTO v_current_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id
  FOR UPDATE;

  v_failed := COALESCE(v_failed, 0);

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn kilidi aktifken PIN değiştirilemez.',
      'is_locked', TRUE,
      'needs_setup', FALSE,
      'locked_until', v_locked_until
    );
  END IF;

  IF v_current_hash IS NOT NULL AND v_current_hash <> '' THEN
    IF p_old_pin IS NULL OR extensions.crypt(p_old_pin, v_current_hash) <> v_current_hash THEN
      v_failed := v_failed + 1;

      IF v_failed >= 5 THEN
        v_locked_until := NOW() + INTERVAL '15 minutes';
        UPDATE public.parent_settings
        SET failed_attempts = v_failed,
            locked_until = v_locked_until,
            updated_at = NOW()
        WHERE user_id = v_user_id;

        RETURN jsonb_build_object(
          'success', FALSE,
          'message', 'Mevcut PIN doğrulaması başarısız. Hesap 15 dakika kilitlendi.',
          'is_locked', TRUE,
          'needs_setup', FALSE,
          'failed_attempts', v_failed,
          'locked_until', v_locked_until
        );
      END IF;

      UPDATE public.parent_settings
      SET failed_attempts = v_failed,
          updated_at = NOW()
      WHERE user_id = v_user_id;

      RETURN jsonb_build_object(
        'success', FALSE,
        'message', 'Mevcut PIN doğrulaması başarısız.',
        'is_locked', FALSE,
        'needs_setup', FALSE,
        'failed_attempts', v_failed
      );
    END IF;
  END IF;

  IF v_current_hash IS NULL OR v_current_hash = '' THEN
    INSERT INTO public.parent_settings (
      user_id,
      pin_hash,
      failed_attempts,
      locked_until,
      updated_at
    )
    VALUES (
      v_user_id,
      extensions.crypt(p_new_pin, extensions.gen_salt('bf')),
      0,
      NULL,
      NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
      SET pin_hash = EXCLUDED.pin_hash,
          failed_attempts = 0,
          locked_until = NULL,
          updated_at = NOW();
  ELSE
    UPDATE public.parent_settings
    SET pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf')),
        failed_attempts = 0,
        locked_until = NULL,
        updated_at = NOW()
    WHERE user_id = v_user_id;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'message', NULL,
    'is_locked', FALSE,
    'needs_setup', FALSE
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) TO authenticated;
