-- ============================================================================
-- Migration: 20260821190949_security_dcl_hardening_20260821.sql
-- Purpose: Reconstruct live EXECUTE DCL for security-sensitive RPCs.
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public.get_my_parent_settings_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_parent_settings_status() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.increment_video_view_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_video_view_count(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_video(TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_video(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.soft_delete_video(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_video(UUID) TO authenticated;
