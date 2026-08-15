-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- Migration: 20260815000005_live_role_and_auth_reconciliation.sql
-- Purpose:
--   Reconcile legacy live profile roles with canonical lowercase role model.
--   Backfill missing profiles for existing auth.users using role metadata.
--   Restore canonical auth.users -> public.profiles bootstrap trigger.
-- Mode: SOURCE OF TRUTH / LIVE-RECONCILIATION SAFE / IDEMPOTENT
-- ============================================================================

-- 1. Canonical role constraint.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

UPDATE public.profiles
SET role = CASE UPPER(COALESCE(role, 'MEMBER'))
  WHEN 'MEMBER' THEN 'child'
  WHEN 'PUBLISHER' THEN 'publisher'
  WHEN 'ADMIN' THEN 'admin'
  WHEN 'CHILD' THEN 'child'
  WHEN 'PARENT' THEN 'parent'
  WHEN 'PUBLISHER' THEN 'publisher'
  WHEN 'ADMIN' THEN 'admin'
  ELSE 'child'
END;

ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'child';

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('child', 'parent', 'publisher', 'admin'));

-- 2. Backfill every existing auth user exactly once.
--    Role is derived only from auth.users.raw_user_meta_data and is restricted
--    to the canonical child/parent bootstrap roles.
INSERT INTO public.profiles (
  id,
  first_name,
  last_name,
  role,
  created_at,
  updated_at
)
SELECT
  u.id,
  NULLIF(TRIM(u.raw_user_meta_data->>'first_name'), ''),
  NULLIF(TRIM(u.raw_user_meta_data->>'last_name'), ''),
  CASE
    WHEN LOWER(TRIM(COALESCE(u.raw_user_meta_data->>'role', 'child'))) = 'parent'
      THEN 'parent'
    ELSE 'child'
  END,
  u.created_at,
  NOW()
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1
  FROM public.profiles p
  WHERE p.id = u.id
);

-- 3. Canonical new-user profile bootstrap.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first_name TEXT;
  v_last_name TEXT;
  v_raw_role TEXT;
  v_sanitized_role TEXT;
BEGIN
  v_first_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'first_name'), '');
  v_last_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'last_name'), '');
  v_raw_role := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'role', 'child')));

  IF v_raw_role = 'parent' THEN
    v_sanitized_role := 'parent';
  ELSE
    v_sanitized_role := 'child';
  END IF;

  INSERT INTO public.profiles (
    id,
    first_name,
    last_name,
    role,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    v_first_name,
    v_last_name,
    v_sanitized_role,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 4. Final invariant: every current auth user has a profile.
DO $$
DECLARE
  v_missing BIGINT;
BEGIN
  SELECT COUNT(*)
  INTO v_missing
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE p.id IS NULL;

  IF v_missing <> 0 THEN
    RAISE EXCEPTION 'Role/auth reconciliation failed: % auth.users rows have no profile', v_missing;
  END IF;
END;
$$;
