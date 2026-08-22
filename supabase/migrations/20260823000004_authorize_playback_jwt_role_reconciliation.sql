CREATE OR REPLACE FUNCTION public.authorize_child_video_play(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_visibility TEXT;
  v_request_role TEXT := current_setting('request.jwt.claim.role', true);
  v_request_sub TEXT := NULLIF(current_setting('request.jwt.claim.sub', true), '');
  v_user_id UUID;
BEGIN
  IF p_video_id IS NULL THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'VIDEO_NOT_FOUND');
  END IF;

  SELECT visibility INTO v_visibility
  FROM public.videos
  WHERE id = p_video_id AND is_deleted = FALSE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'VIDEO_NOT_FOUND');
  END IF;

  IF v_request_role = 'anon' OR v_request_sub IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', v_visibility = 'public',
      'reason', CASE WHEN v_visibility = 'public' THEN 'OK' ELSE 'VIDEO_NOT_PUBLIC' END
    );
  END IF;

  BEGIN
    v_user_id := v_request_sub::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('allowed', FALSE, 'reason', 'AUTHORIZATION_ERROR');
  END;

  RETURN public.check_child_video_play_policy(v_user_id, p_video_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO anon, authenticated;
