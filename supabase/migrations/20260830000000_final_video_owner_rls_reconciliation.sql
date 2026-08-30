BEGIN;

-- Final reconciliation for video ownership and visibility.
-- Normal users can only keep ownership of their own videos.
-- Only the designated publisher can create/update public or unlisted videos.
DROP POLICY IF EXISTS "Authorized users can update own videos" ON public.videos;
DROP POLICY IF EXISTS "Authorized roles can update videos" ON public.videos;

CREATE POLICY "Authorized users can update own videos"
ON public.videos
FOR UPDATE
TO authenticated
USING (
  (owner_id = (SELECT auth.uid()))
  OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'admin'
  )
)
WITH CHECK (
  (
    owner_id = (SELECT auth.uid())
    AND (
      visibility = 'private'
      OR lower(trim((SELECT u.email FROM auth.users u WHERE u.id = (SELECT auth.uid())))) = 'kan.vildan02@gmail.com'
    )
  )
  OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'admin'
  )
);

-- Keep exactly one profile-role protection trigger.
DROP TRIGGER IF EXISTS trg_prevent_profile_role_escalation ON public.profiles;
DROP TRIGGER IF EXISTS tr_prevent_profile_role_escalation ON public.profiles;

CREATE TRIGGER tr_prevent_profile_role_escalation
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.prevent_profile_role_escalation();

COMMIT;
