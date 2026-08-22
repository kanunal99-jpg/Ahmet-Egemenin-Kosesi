-- Guest playback is handled by the client through the public videos RLS policy.
-- The policy RPC is reserved for authenticated users because it is SECURITY DEFINER.
REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO authenticated;
