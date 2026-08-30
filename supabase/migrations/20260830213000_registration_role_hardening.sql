BEGIN;

-- Registration role hardening:
-- - Public registration must always create a child profile.
-- - The designated publisher account remains the only automatic publisher.
-- - Non-admin users cannot self-promote to parent, publisher or admin.
-- - Existing parent accounts retain the parent role during ordinary profile updates.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first_name text;
  v_last_name text;
BEGIN
  v_first_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'first_name'), '');
  v_last_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'last_name'), '');

  INSERT INTO public.profiles (
    id,
    first_name,
    last_name,
    role,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    v_first_name,
    v_last_name,
    'child',
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.prevent_profile_role_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  target_email TEXT;
  actor_is_admin BOOLEAN;
BEGIN
  SELECT lower(trim(u.email))
    INTO target_email
  FROM auth.users u
  WHERE u.id = NEW.id;

  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'
  ) INTO actor_is_admin;

  -- The designated publisher account is the only account allowed to hold
  -- publisher role. This is enforced on both INSERT and UPDATE.
  IF target_email = 'kan.vildan02@gmail.com' THEN
    NEW.role := 'publisher';
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- A newly created profile can never choose an elevated role.
    NEW.role := 'child';
    RETURN NEW;
  END IF;

  -- Only an admin may grant a new elevated role on an existing profile.
  IF NEW.role = 'publisher' AND NOT actor_is_admin THEN
    NEW.role := OLD.role;
  END IF;

  IF NEW.role = 'admin' AND NOT actor_is_admin THEN
    NEW.role := OLD.role;
  END IF;

  IF NEW.role = 'parent' AND OLD.role <> 'parent' AND NOT actor_is_admin THEN
    NEW.role := OLD.role;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS trg_prevent_profile_role_escalation ON public.profiles;
DROP TRIGGER IF EXISTS tr_prevent_profile_role_escalation ON public.profiles;
CREATE TRIGGER tr_prevent_profile_role_escalation
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_profile_role_escalation();

COMMIT;
