-- ============================================================================
-- Migration: 20260815000010_parent_child_link_by_email.sql
-- Description: Historical Parent Child Link by Email RPC
-- ============================================================================

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
  v_child_role TEXT;
BEGIN
  IF v_parent_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  SELECT id, role INTO v_child_id, v_child_role
  FROM public.profiles
  WHERE id IN (
    SELECT id FROM auth.users WHERE email = LOWER(TRIM(p_child_email))
  );

  IF v_child_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk hesabı bulunamadı.');
  END IF;

  IF v_child_id = v_parent_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kendi hesabınızı çocuk olarak ekleyemezsiniz.');
  END IF;

  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_parent_id, v_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING;

  RETURN jsonb_build_object('success', TRUE, 'child_id', v_child_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) TO authenticated;
