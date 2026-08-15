-- CRIT-50 hardening: invite records are RPC-only; raw hashes are never directly readable.
DROP POLICY IF EXISTS parent_child_invites_no_direct_select ON public.parent_child_invites;
REVOKE SELECT ON TABLE public.parent_child_invites FROM authenticated, anon, PUBLIC;

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

  v_result := public.create_parent_child_link(v_invite.child_id);

  IF COALESCE((v_result->>'success')::BOOLEAN, false) THEN
    UPDATE public.parent_child_invites
    SET used_at = NOW()
    WHERE id = v_invite.id;
  END IF;

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'CHILD_LINK_FAILED');
END;
$function$;

REVOKE ALL ON FUNCTION public.redeem_parent_child_invite(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) TO authenticated;
