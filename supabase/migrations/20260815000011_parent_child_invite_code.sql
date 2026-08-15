-- ============================================================================
-- Migration: 20260815000011_parent_child_invite_code.sql
-- Description: Historical Parent Child Invite Code Generation & Redemption
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.child_link_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  used_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.child_link_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY child_link_codes_parent_select ON public.child_link_codes
  FOR SELECT TO authenticated
  USING (parent_id = auth.uid());

CREATE OR REPLACE FUNCTION public.create_child_link_code()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parent_id UUID := auth.uid();
  v_code TEXT;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF v_parent_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Kimlik doğrulaması yapılmadı.');
  END IF;

  v_code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));
  v_expires_at := NOW() + INTERVAL '24 hours';

  INSERT INTO public.child_link_codes (parent_id, code, expires_at)
  VALUES (v_parent_id, v_code, v_expires_at);

  RETURN jsonb_build_object(
    'success', TRUE,
    'code', v_code,
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_child_link_code() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_child_link_code() TO authenticated;
