-- Reconcile the live playback authorization contract with the frontend.
-- The client calls authorize_child_video_play() before starting a YouTube session.
-- The RPC itself derives auth.uid() and only exposes non-sensitive authorization state.

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO anon, authenticated;

-- Profile creation is trigger-owned; clients must not create profiles directly.
REVOKE INSERT ON public.profiles FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_result TEXT;
BEGIN
  SELECT pg_get_function_result(p.oid)
    INTO v_result
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'authorize_child_video_play'
    AND pg_get_function_identity_arguments(p.oid) = 'p_video_id uuid';

  IF v_result IS DISTINCT FROM 'jsonb' THEN
    RAISE EXCEPTION 'authorize_child_video_play(UUID) must return jsonb; found %', COALESCE(v_result, '<missing>');
  END IF;
END;
$$;
