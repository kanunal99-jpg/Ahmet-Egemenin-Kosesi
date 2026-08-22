-- Reconcile the live 2026-08-22 SECURITY DEFINER execution boundary.
-- Application-facing RPCs are re-enabled for authenticated users by the immediately
-- following restore migration; internal SECURITY DEFINER helpers remain non-callable.

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.check_child_video_play_policy(UUID, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_my_child_link_invite() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_effective_child_daily_watch_seconds(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_istanbul_day_start() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_my_parent_settings_status() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_video_view_count(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.soft_delete_video(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_parent_pin_legacy_boolean(TEXT) FROM authenticated;
