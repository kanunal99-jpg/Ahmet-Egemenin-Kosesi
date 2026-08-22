-- Internal SECURITY DEFINER helpers must not be directly callable through the public RPC surface.
REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_parent_pin_legacy_boolean(TEXT) FROM PUBLIC, anon, authenticated;
