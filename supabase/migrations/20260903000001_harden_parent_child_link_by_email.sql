BEGIN;

-- SECURITY FIX: create_parent_child_link_by_email is SECURITY DEFINER.
-- The historical function only checked authentication and could therefore
-- let any authenticated role create a parent-child relationship by email.
-- Keep the legacy RPC for compatibility, but enforce the same authorization
-- contract as create_parent_child_link: parent/admin caller + child target.

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
  v_parent_role TEXT;
  v_child_id UUID;
  v_child_role TEXT;
BEGIN
  IF v_parent_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  SELECT role INTO v_parent_role
  FROM public.profiles
  WHERE id = v_parent_id;

  IF v_parent_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca ebeveynler çocuk hesabı bağlayabilir.');
  END IF;

  IF p_child_email IS NULL OR NULLIF(TRIM(p_child_email), '') IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk e-posta adresi gereklidir.');
  END IF;

  SELECT p.id, p.role
    INTO v_child_id, v_child_role
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE lower(trim(u.email)) = lower(trim(p_child_email))
  LIMIT 1;

  IF v_child_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Çocuk hesabı bulunamadı.');
  END IF;

  IF v_child_id = v_parent_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kendi hesabınızı çocuk olarak ekleyemezsiniz.');
  END IF;

  IF v_child_role <> 'child' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Yalnızca çocuk rolündeki hesaplar bağlanabilir.');
  END IF;

  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_parent_id, v_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING;

  RETURN jsonb_build_object('success', TRUE, 'child_id', v_child_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) TO authenticated;

COMMIT;
