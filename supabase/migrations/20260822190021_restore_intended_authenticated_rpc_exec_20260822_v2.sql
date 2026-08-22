-- Final live 2026-08-22 RPC execution contract.
-- Application-facing RPCs remain callable by authenticated users.
-- PUBLIC/anon execution remains explicitly revoked by their preceding DCL migrations.

GRANT EXECUTE ON FUNCTION public.create_my_child_link_invite() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_parent_settings_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_video_view_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.soft_delete_video(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;

-- Internal helpers remain intentionally uncallable by authenticated clients.
REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_parent_pin_legacy_boolean(TEXT) FROM authenticated;
