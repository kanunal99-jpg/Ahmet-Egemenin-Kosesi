-- ============================================================================
-- Migration: 20260815000012_parent_child_invite_hardening.sql
-- Description: Historical Parent Child Invite Redemption & Hardening
-- ============================================================================

CREATE OR REPLACE FUNCTION public.redeem_child_link_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_child_id UUID := auth.uid();
  v_link_record RECORD;
BEGIN
  IF v_child_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  SELECT * INTO v_link_record
  FROM public.child_link_codes
  WHERE code = UPPER(TRIM(p_code)) AND used_at IS NULL AND expires_at > NOW()
  FOR UPDATE;

  IF v_link_record.id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Geçersiz veya süresi dolmuş davet kodu.');
  END IF;

  IF v_link_record.parent_id = v_child_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kendi kodunuzu kullanamazsınız.');
  END IF;

  INSERT INTO public.parent_children (parent_id, child_id)
  VALUES (v_link_record.parent_id, v_child_id)
  ON CONFLICT (parent_id, child_id) DO NOTHING;

  UPDATE public.child_link_codes
  SET used_at = NOW(), used_by = v_child_id
  WHERE id = v_link_record.id;

  RETURN jsonb_build_object('success', TRUE, 'parent_id', v_link_record.parent_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.redeem_child_link_code(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_child_link_code(TEXT) TO authenticated;
