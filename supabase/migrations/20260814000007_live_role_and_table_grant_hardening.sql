-- CRIT-26: get_my_role is caller-scoped and does not require SECURITY DEFINER.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 'guest'; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  RETURN COALESCE(v_role, 'guest');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_role() TO anon, authenticated;

-- CRIT-27: remove broad legacy client table grants and restore only required access.
REVOKE ALL ON TABLE public.categories, public.favorites, public.parent_settings,
  public.profiles, public.video_view_cooldowns, public.videos, public.watch_history
FROM anon, authenticated;

GRANT SELECT ON TABLE public.categories TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.videos TO authenticated;
GRANT SELECT ON TABLE public.videos TO anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.watch_history TO authenticated;

-- parent_settings and video_view_cooldowns are RPC-only.
-- No direct client table grants are restored.

REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.categories,
  public.profiles, public.videos, public.watch_history FROM anon, authenticated;
