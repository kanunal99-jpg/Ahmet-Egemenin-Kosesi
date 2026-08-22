CREATE OR REPLACE FUNCTION public.authorize_child_video_play(p_video_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_visibility TEXT;
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

  IF COALESCE(auth.role(), 'anon') = 'anon' OR auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'allowed', v_visibility = 'public',
      'reason', CASE WHEN v_visibility = 'public' THEN 'OK' ELSE 'VIDEO_NOT_PUBLIC' END
    );
  END IF;

  RETURN public.check_child_video_play_policy(auth.uid(), p_video_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO anon, authenticated;
