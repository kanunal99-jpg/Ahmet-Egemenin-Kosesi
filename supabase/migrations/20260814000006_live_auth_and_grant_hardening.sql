-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- MIGRATION: 20260814000006_live_auth_and_grant_hardening.sql
-- PURPOSE:
--   CRIT-25: Reconcile verify_parent_pin() with JSONB + parent/admin auth +
--            bootstrap/lockout contract used by the frontend.
--   CRIT-26: Reconcile get_my_role() fallback to guest and remove unnecessary
--            SECURITY DEFINER usage.
--   CRIT-27: Minimize direct client table privileges; keep only privileges
--            required by the current frontend/RLS model and make parent_settings
--            + video_view_cooldowns RPC-only.
--
-- IMPORTANT:
--   This migration does not create the parent_children/watch_history_sessions
--   model. Those remain in the earlier pending migration chain.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. CRIT-26: get_my_role() — INVOKER + guest fallback
-- ---------------------------------------------------------------------------
-- The function only needs the caller's own profile row. RLS already limits
-- profiles SELECT to auth.uid() = id, so SECURITY INVOKER is sufficient and
-- removes an unnecessary elevated execution context.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 'guest';
  END IF;

  SELECT role
    INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  RETURN COALESCE(v_role, 'guest');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_role() TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. CRIT-25: verify_parent_pin() JSONB contract + authorization
-- ---------------------------------------------------------------------------
-- Return shape required by ParentService/ParentContext:
--   success, message, is_locked, needs_setup
-- Return type change BOOLEAN -> JSONB requires DROP + CREATE.
DROP FUNCTION IF EXISTS public.verify_parent_pin(TEXT);

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
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Oturum açılmadı.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  SELECT role
    INTO v_user_role
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_user_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Ebeveyn PIN doğrulaması için yetkiniz bulunmamaktadır.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

  SELECT pin_hash, failed_attempts, locked_until
    INTO v_pin_hash, v_failed, v_locked_until
  FROM public.parent_settings
  WHERE user_id = v_user_id;

  v_failed := COALESCE(v_failed, 0);

  IF v_locked_until IS NOT NULL AND v_locked_until > NOW() THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Çok fazla hatalı deneme. Lütfen kilit süresinin dolmasını bekleyin.',
      'is_locked', TRUE,
      'needs_setup', FALSE
    );
  END IF;

  IF v_pin_hash IS NULL OR v_pin_hash = '' THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Lütfen önce Ebeveyn PIN kodunuzu oluşturun.',
      'is_locked', FALSE,
      'needs_setup', TRUE
    );
  END IF;

  IF crypt(COALESCE(p_pin, ''), v_pin_hash) = v_pin_hash THEN
    UPDATE public.parent_settings
    SET failed_attempts = 0,
        locked_until = NULL,
        updated_at = NOW()
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
      'success', TRUE,
      'message', 'PIN doğrulandı.',
      'is_locked', FALSE,
      'needs_setup', FALSE
    );
  END IF;

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
      'message', 'Çok fazla hatalı PIN denemesi. 15 dakika boyunca kilitlendi.',
      'is_locked', TRUE,
      'needs_setup', FALSE
    );
  END IF;

  UPDATE public.parent_settings
  SET failed_attempts = v_failed,
      updated_at = NOW()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object(
    'success', FALSE,
    'message', 'Hatalı PIN.',
    'is_locked', FALSE,
    'needs_setup', FALSE
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. CRIT-27: MINIMIZE DIRECT CLIENT TABLE PRIVILEGES
-- ---------------------------------------------------------------------------
-- First remove broad legacy grants from anon/authenticated. Then restore only
-- privileges actually needed by the current direct-table frontend services.
REVOKE ALL ON TABLE
  public.categories,
  public.favorites,
  public.parent_settings,
  public.profiles,
  public.video_view_cooldowns,
  public.videos,
  public.watch_history
FROM anon, authenticated;

-- categories: public read only
GRANT SELECT ON TABLE public.categories TO anon, authenticated;

-- favorites: direct CRUD required by user favorites service; RLS limits rows
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.favorites TO authenticated;

-- profiles: registration/self-profile flows; RLS limits rows to auth.uid()
GRANT SELECT, INSERT, UPDATE ON TABLE public.profiles TO authenticated;

-- parent_settings: RPC-only
-- NO direct client table grants.

-- video_view_cooldowns: RPC-only
-- NO direct client table grants.

-- videos: public/owner/admin read plus publisher/admin write through RLS
GRANT SELECT, INSERT, UPDATE ON TABLE public.videos TO authenticated;
GRANT SELECT ON TABLE public.videos TO anon;

-- watch_history: direct resume/history service; RLS limits rows to auth.uid()
GRANT SELECT, INSERT, UPDATE ON TABLE public.watch_history TO authenticated;

-- Explicitly keep destructive/privileged table capabilities away from client roles.
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.categories,
  public.profiles,
  public.videos,
  public.watch_history
FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. ASSERTIONS
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_ret TEXT;
BEGIN
  SELECT pg_get_function_result(p.oid)
    INTO v_ret
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'verify_parent_pin'
    AND pg_get_function_identity_arguments(p.oid) = 'p_pin text';

  IF v_ret IS DISTINCT FROM 'jsonb' THEN
    RAISE EXCEPTION 'verify_parent_pin must return jsonb, found %', v_ret;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants
    WHERE grantee IN ('anon', 'authenticated')
      AND table_schema = 'public'
      AND table_name IN ('parent_settings', 'video_view_cooldowns')
  ) THEN
    RAISE EXCEPTION 'RPC-only tables still expose direct client grants';
  END IF;
END;
$$;
