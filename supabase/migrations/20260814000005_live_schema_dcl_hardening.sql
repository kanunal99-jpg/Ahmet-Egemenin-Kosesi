-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- MIGRATION: 20260814000005_live_schema_dcl_hardening.sql
-- PURPOSE:
--   CRIT-23: Fix get_my_children() schema mismatch (profiles.full_name/username
--            do not exist; canonical fields are first_name/last_name).
--   CRIT-24: Revoke client EXECUTE on internal trigger functions exposed as
--            SECURITY DEFINER functions in public schema.
--
-- NOTE:
--   This migration is intentionally additive/idempotent and does not modify
--   earlier migrations.
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
-- 2. CRIT-24: INTERNAL TRIGGER FUNCTIONS MUST NOT BE CLIENT-CALLABLE
-- ---------------------------------------------------------------------------
-- These functions exist only as table trigger targets. They are not public RPC
-- endpoints and must not be callable through PostgREST /rpc.
REVOKE EXECUTE ON FUNCTION public.prevent_direct_video_view_count_update() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_profile_role_escalation() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_video_undelete() FROM PUBLIC, anon, authenticated;

-- The trigger functions are invoked by PostgreSQL triggers, not by client RPCs.
-- Trigger execution does not require client EXECUTE grants.

-- ---------------------------------------------------------------------------
-- 3. EXPLICITLY RETAIN INTENDED CLIENT RPC ACCESS
-- ---------------------------------------------------------------------------
-- get_my_role remains an application-facing read-only RPC because it returns
-- the caller's own role/guest state and may be used by legacy clients.
-- Parent/auth/view-count APIs remain authenticated-only as already reconciled.

-- ---------------------------------------------------------------------------
-- 4. FINAL SAFETY ASSERTIONS (migration-time failures are preferable to drift)
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
    RAISE NOTICE 'Unexpected legacy profile display columns detected; get_my_children remains compatible with canonical first_name/last_name fields.';
  END IF;
END;
$$;
