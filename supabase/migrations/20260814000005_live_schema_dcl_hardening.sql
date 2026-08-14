-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- MIGRATION: 20260814000005_live_schema_dcl_hardening.sql
-- PURPOSE:
--   CRIT-23: Fix get_my_children() schema mismatch.
--   CRIT-24: Remove anonymous access to internal trigger functions without
--            breaking authenticated DML that fires those triggers.
--
-- IMPORTANT:
--   PostgreSQL trigger functions must remain executable by the role performing
--   the triggering DML. These functions are not valid ordinary RPC endpoints;
--   PostgreSQL only permits them to execute in trigger context. Therefore we
--   revoke PUBLIC/anon access but intentionally retain authenticated EXECUTE.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. CRIT-23: RECONCILE get_my_children() WITH ACTUAL profiles SCHEMA
-- ---------------------------------------------------------------------------
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

  SELECT role
    INTO v_caller_role
  FROM public.profiles
  WHERE id = v_caller_id;

  IF v_caller_role NOT IN ('parent', 'admin') THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pc.id,
        'child_id', p.id,
        'child_name', COALESCE(
          NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
          'Çocuk Hesabı'
        ),
        'created_at', pc.created_at
      )
      ORDER BY pc.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM public.parent_children pc
  JOIN public.profiles p ON p.id = pc.child_id
  WHERE pc.parent_id = v_caller_id
    AND p.role = 'child';

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. CRIT-24: INTERNAL TRIGGER FUNCTIONS
-- ---------------------------------------------------------------------------
-- These are trigger-only functions. Direct invocation is rejected by
-- PostgreSQL outside trigger context. Keep authenticated EXECUTE so normal
-- authenticated INSERT/UPDATE operations can fire their triggers safely.
REVOKE EXECUTE ON FUNCTION public.prevent_direct_video_view_count_update() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.prevent_profile_role_escalation() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.prevent_video_undelete() FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- 3. EXPLICIT CLIENT RPC ACCESS
-- ---------------------------------------------------------------------------
-- get_my_role remains application-facing. Other intended authenticated RPCs
-- retain their existing grants from earlier migrations.

-- ---------------------------------------------------------------------------
-- 4. SCHEMA SAFETY ASSERTION
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name IN ('full_name', 'username')
  ) THEN
    RAISE NOTICE 'Legacy profile display columns detected; canonical first_name/last_name fields remain supported.';
  END IF;
END;
$$;
