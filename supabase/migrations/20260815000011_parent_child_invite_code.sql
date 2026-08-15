-- CRIT-50: parent-friendly child onboarding via one-time invite code
CREATE TABLE IF NOT EXISTS public.parent_child_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 minutes'),
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parent_child_invites_child_active
  ON public.parent_child_invites (child_id, expires_at)
  WHERE used_at IS NULL;

ALTER TABLE public.parent_child_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parent_child_invites_no_direct_select ON public.parent_child_invites;
CREATE POLICY parent_child_invites_no_direct_select
  ON public.parent_child_invites
  FOR SELECT TO authenticated
  USING (child_id = auth.uid());

REVOKE ALL ON TABLE public.parent_child_invites FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.parent_child_invites TO authenticated;

CREATE OR REPLACE FUNCTION public.create_my_child_link_invite()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_role TEXT;
  v_code TEXT;
  v_hash TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user_id;
  IF v_role <> 'child' THEN
    RETURN jsonb_build_object('success', false, 'error', 'CHILD_ROLE_REQUIRED');
  END IF;

  v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 10));
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  UPDATE public.parent_child_invites
  SET used_at = NOW()
  WHERE child_id = v_user_id AND used_at IS NULL;

  INSERT INTO public.parent_child_invites (child_id, code_hash, expires_at)
  VALUES (v_user_id, v_hash, NOW() + INTERVAL '30 minutes');

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'expires_at', NOW() + INTERVAL '30 minutes'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.redeem_parent_child_invite(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_parent_id UUID := auth.uid();
  v_parent_role TEXT;
  v_code TEXT := upper(regexp_replace(trim(COALESCE(p_code, '')), '[^A-Z0-9]', '', 'g'));
  v_hash TEXT;
  v_invite RECORD;
  v_result JSONB;
BEGIN
  IF v_parent_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT role INTO v_parent_role FROM public.profiles WHERE id = v_parent_id;
  IF v_parent_role NOT IN ('parent', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PARENT_ROLE_REQUIRED');
  END IF;

  IF length(v_code) < 8 OR length(v_code) > 16 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_INVITE_CODE');
  END IF;

  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  SELECT i.* INTO v_invite
  FROM public.parent_child_invites i
  WHERE i.code_hash = v_hash
    AND i.used_at IS NULL
    AND i.expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVITE_NOT_FOUND_OR_EXPIRED');
  END IF;

  IF v_invite.child_id = v_parent_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_LINK_DENIED');
  END IF;

  BEGIN
    v_result := public.create_parent_child_link(v_invite.child_id);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;

  IF COALESCE((v_result->>'success')::BOOLEAN, false) THEN
    UPDATE public.parent_child_invites
    SET used_at = NOW()
    WHERE id = v_invite.id;
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_my_child_link_invite() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_my_child_link_invite() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) TO authenticated;

COMMENT ON TABLE public.parent_child_invites IS 'One-time short-lived child-to-parent linking codes; raw codes are never stored.';
