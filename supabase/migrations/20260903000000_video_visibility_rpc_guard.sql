BEGIN;

-- SECURITY FIX: The video CRUD RPCs are SECURITY DEFINER and therefore bypass
-- videos RLS. The final RLS reconciliation requires only the designated
-- publisher (or admin) to create/update public or unlisted videos, while
-- parent/publisher accounts may still manage private videos.
-- Enforce the same invariant at the table boundary so future SECURITY DEFINER
-- write paths cannot accidentally bypass the visibility rule.

CREATE OR REPLACE FUNCTION public.enforce_video_visibility_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_role TEXT;
  v_email TEXT;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Kimlik doğrulaması gereklidir.';
  END IF;

  SELECT p.role INTO v_role
  FROM public.profiles p
  WHERE p.id = v_actor;

  IF v_role IS NULL OR v_role NOT IN ('parent', 'publisher', 'admin') THEN
    RAISE EXCEPTION 'Video görünürlüğünü değiştirme yetkiniz bulunmamaktadır.';
  END IF;

  IF v_role = 'admin' OR NEW.visibility = 'private' THEN
    RETURN NEW;
  END IF;

  SELECT lower(trim(u.email)) INTO v_email
  FROM auth.users u
  WHERE u.id = v_actor;

  IF v_email <> 'kan.vildan02@gmail.com' THEN
    RAISE EXCEPTION 'Public veya unlisted video oluşturma/yayınlama yetkisi yalnızca yetkili yayıncı hesabındadır.';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_video_visibility_policy() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_video_visibility_policy ON public.videos;
CREATE TRIGGER trg_enforce_video_visibility_policy
BEFORE INSERT OR UPDATE OF visibility ON public.videos
FOR EACH ROW
EXECUTE FUNCTION public.enforce_video_visibility_policy();

COMMIT;
