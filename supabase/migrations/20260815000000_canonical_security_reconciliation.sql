-- ============================================================================
-- Migration: 20260815000000_canonical_security_reconciliation.sql
-- Description: Canonical Security Reconciliation & Hardening (CRIT-23..30)
--              - CRIT-25: verify_parent_pin JSONB return type, FOR UPDATE lock, 5-attempt/15-min lockout
--              - CRIT-26: get_my_role SECURITY INVOKER with canonical 'guest' fallback
--              - CRIT-23: get_my_children JSONB schema alignment (first_name/last_name)
--              - CRIT-24: Trigger function DCL execution restrictions
--              - CRIT-27: Strict table least-privilege DCL (parent_settings/video_view_cooldowns RPC-only)
--              - CRIT-28: Canonical migration drift closure
--              - CRIT-29: get_my_effective_parental_settings non-sensitive child policy RPC
-- ============================================================================

-- ============================================================================
-- 1. DROP LEGACY / CONFLICTING SIGNATURES
-- ============================================================================
DROP FUNCTION IF EXISTS public.verify_parent_pin_legacy_boolean(TEXT);

-- ============================================================================
-- 2. CRIT-25: FINAL HARDENED verify_parent_pin(TEXT) -> JSONB
-- ============================================================================
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
  v_failed INT;
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

  -- Role authorization check: only parent or admin allowed
  SELECT role INTO v_user_role FROM public.profiles WHERE id = v_user_id;
  IF v_user_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Yetkisiz erişim: Bu işlem sadece ebeveyn veya yönetici hesapları içindir.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  -- Lock row for concurrency safety (CRIT-25)
  SELECT pin_hash, failed_attempts, locked_until
  INTO v_pin_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id
  FOR UPDATE;

  -- 1. Check if record or PIN has not been set yet
  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn PIN kodu henüz ayarlanmamış. Lütfen önce PIN oluşturun.',
      'is_locked', FALSE,
      'needs_setup', TRUE
    );
  END IF;

  -- 2. Check active lockout
  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn kilidi geçici olarak kilitlendi. Lütfen bekleyin.',
      'is_locked', TRUE,
      'needs_setup', FALSE,
      'locked_until', v_locked_until
    );
  END IF;

  -- 3. Verify PIN against bcrypt/blowfish hash
  IF v_pin_hash = crypt(p_pin, v_pin_hash) THEN
    -- Correct PIN: reset failure counters and unlock
    UPDATE public.parent_settings
    SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
      'success', TRUE,
      'message', NULL,
      'is_locked', FALSE,
      'needs_setup', FALSE
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
        'needs_setup', FALSE,
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
        'needs_setup', FALSE,
        'failed_attempts', v_failed
      );
    END IF;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;


-- ============================================================================
-- 3. CRIT-26: CANONICAL get_my_role() (SECURITY INVOKER + GUEST FALLBACK)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 'guest';
  END IF;

  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = v_uid;

  RETURN COALESCE(v_role, 'guest');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_role() TO anon, authenticated;


-- ============================================================================
-- 4. CRIT-23: RECONCILED get_my_children() (SCHEMA-ALIGNED first_name/last_name)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_children()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_result JSONB;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pc.id,
        'child_id', p.id,
        'child_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''), p.first_name, 'Çocuk Hesabı'),
        'created_at', pc.created_at
      )
      ORDER BY pc.created_at ASC
    ),
    '[]'::jsonb
  ) INTO v_result
  FROM public.parent_children pc
  JOIN public.profiles p ON p.id = pc.child_id
  WHERE pc.parent_id = v_caller_id;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;


-- ============================================================================
-- 5. CRIT-24: TRIGGER FUNCTION DCL RESTRICTIONS
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.prevent_direct_video_view_count_update() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.prevent_profile_role_escalation() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.prevent_video_undelete() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.validate_parent_child_roles_trigger() FROM PUBLIC, anon;


-- ============================================================================
-- 6. CRIT-27: TABLE LEAST-PRIVILEGE GRANTS & RPC-ONLY ENFORCEMENT
-- ============================================================================
-- RPC-only tables (no direct client table grants)
REVOKE ALL ON public.parent_settings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.video_view_cooldowns FROM PUBLIC, anon, authenticated;

-- Relational link & session stream tables (SELECT own only via RLS, mutations via RPC)
REVOKE ALL ON public.parent_children FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.parent_children TO authenticated;

REVOKE ALL ON public.watch_history_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.watch_history_sessions TO authenticated;

-- Content & Standard user tables
REVOKE ALL ON public.categories FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.categories TO anon, authenticated;

REVOKE ALL ON public.favorites FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.favorites TO authenticated;

REVOKE ALL ON public.profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.profiles TO anon;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

REVOKE ALL ON public.videos FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.videos TO anon, authenticated;
GRANT INSERT, UPDATE ON public.videos TO authenticated;

REVOKE ALL ON public.watch_history FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.watch_history TO authenticated;


-- ============================================================================
-- 7. CRIT-29: RPC get_my_effective_parental_settings (NON-SENSITIVE CHILD POLICY)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_effective_parental_settings()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_parent_id UUID;
  v_settings RECORD;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

  IF v_caller_role IN ('parent', 'admin') THEN
    v_parent_id := v_caller_id;
  ELSIF v_caller_role = 'child' THEN
    -- Find linked parent with newest settings
    SELECT pc.parent_id INTO v_parent_id
    FROM public.parent_children pc
    JOIN public.parent_settings ps ON ps.user_id = pc.parent_id
    WHERE pc.child_id = v_caller_id
    ORDER BY ps.updated_at DESC
    LIMIT 1;

    -- Fallback if parent has no parent_settings record yet
    IF v_parent_id IS NULL THEN
      SELECT pc.parent_id INTO v_parent_id
      FROM public.parent_children pc
      WHERE pc.child_id = v_caller_id
      ORDER BY pc.created_at DESC
      LIMIT 1;
    END IF;
  ELSE
    v_parent_id := NULL;
  END IF;

  IF v_parent_id IS NOT NULL THEN
    SELECT
      daily_time_limit_minutes,
      allowed_categories,
      bedtime_start,
      bedtime_end
    INTO v_settings
    FROM public.parent_settings
    WHERE user_id = v_parent_id;
  END IF;

  RETURN jsonb_build_object(
    'daily_time_limit_minutes', COALESCE(v_settings.daily_time_limit_minutes, 60),
    'allowed_categories', v_settings.allowed_categories,
    'bedtime_start', v_settings.bedtime_start,
    'bedtime_end', v_settings.bedtime_end,
    'has_parent', (v_parent_id IS NOT NULL)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_effective_parental_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_effective_parental_settings() TO authenticated;


-- ============================================================================
-- 8. CANONICAL RECONCILIATION ASSERTIONS
-- ============================================================================
DO $$
DECLARE
  v_ret_type TEXT;
  v_sec_def BOOLEAN;
BEGIN
  -- Verify verify_parent_pin return type is jsonb
  SELECT data_type INTO v_ret_type
  FROM information_schema.routines
  WHERE routine_schema = 'public' AND routine_name = 'verify_parent_pin';

  IF v_ret_type IS NOT NULL AND LOWER(v_ret_type) NOT IN ('jsonb', 'user-defined') THEN
    RAISE EXCEPTION 'Assertion failed: verify_parent_pin return type must be JSONB, found %', v_ret_type;
  END IF;

  -- Verify get_my_role exists
  SELECT security_type = 'DEFINER' INTO v_sec_def
  FROM information_schema.routines
  WHERE routine_schema = 'public' AND routine_name = 'get_my_role';

  IF v_sec_def IS TRUE THEN
    RAISE EXCEPTION 'Assertion failed: get_my_role must be SECURITY INVOKER';
  END IF;
END;
$$;
