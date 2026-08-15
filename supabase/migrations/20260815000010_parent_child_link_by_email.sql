-- ================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- 20260815000010_parent_child_link_by_email.sql
-- Parent-child linking UX hardening: no raw UUID required in UI.
-- ================================================================

CREATE OR REPLACE FUNCTION public.create_parent_child_link_by_email(
  p_child_email TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parent_id UUID := auth.uid();
  v_child_id UUID;
  v_email TEXT;
  v_result JSONB;
BEGIN
  IF v_parent_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'AUTH_REQUIRED');
  END IF;

  v_email := lower(trim(COALESCE(p_child_email, '')));

  IF v_email = '' OR position('@' IN v_email) <= 1 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'INVALID_CHILD_EMAIL');
  END IF;

  -- Resolve the child identity server-side. Do not expose auth.users to clients.
  SELECT au.id
    INTO v_child_id
  FROM auth.users AS au
  JOIN public.profiles AS p ON p.id = au.id
  WHERE lower(au.email) = v_email
    AND p.role = 'child'
  LIMIT 1;

  -- Fail closed and avoid account-enumeration detail.
  IF v_child_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'CHILD_ACCOUNT_NOT_FOUND');
  END IF;

  -- Reuse the canonical authorization/linking implementation.
  v_result := public.create_parent_child_link(v_child_id);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) TO authenticated;
