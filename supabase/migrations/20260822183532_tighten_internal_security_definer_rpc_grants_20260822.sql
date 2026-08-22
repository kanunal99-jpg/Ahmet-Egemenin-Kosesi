-- Reconcile the live 2026-08-22 RPC privilege hardening into the repository.
-- These RPCs remain callable by authenticated users because they are application-facing;
-- PUBLIC/anon execution is explicitly removed and service_role/postgres remain available.

REVOKE EXECUTE ON FUNCTION public.create_my_child_link_invite() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_my_child_link_invite() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_watch_session(UUID, INT, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_children() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_children() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_child_usage_report(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.heartbeat_watch_session(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.soft_delete_video(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_video(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.start_watch_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_watch_session(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
