-- Canonical hardening: sensitive tables are RPC/trigger mediated only.
-- RLS remains enabled and explicit deny policies prevent direct authenticated access.

DROP POLICY IF EXISTS "parent_settings_no_direct_access" ON public.parent_settings;
CREATE POLICY "parent_settings_no_direct_access"
  ON public.parent_settings
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "parent_child_invites_no_direct_access" ON public.parent_child_invites;
CREATE POLICY "parent_child_invites_no_direct_access"
  ON public.parent_child_invites
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "video_view_cooldowns_no_direct_access" ON public.video_view_cooldowns;
CREATE POLICY "video_view_cooldowns_no_direct_access"
  ON public.video_view_cooldowns
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON TABLE public.parent_settings FROM anon, authenticated;
REVOKE ALL ON TABLE public.parent_child_invites FROM anon, authenticated;
REVOKE ALL ON TABLE public.video_view_cooldowns FROM anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_parent_pin(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_pin(TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_my_parent_settings_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_parent_settings_status() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_parent_settings(INT, TEXT[], TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_video_view_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_video_view_count(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_my_child_link_invite() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_my_child_link_invite() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_parent_child_invite(TEXT) TO authenticated;
