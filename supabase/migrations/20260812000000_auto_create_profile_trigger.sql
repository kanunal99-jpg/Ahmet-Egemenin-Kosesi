-- Migration: 20260812000000_auto_create_profile_trigger.sql
-- Description: Automatically create public.profiles row when a new user is inserted into auth.users.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first_name text;
  v_last_name text;
  v_raw_role text;
  v_sanitized_role text;
BEGIN
  v_first_name := NULLIF(TRIM(new.raw_user_meta_data->>'first_name'), '');
  v_last_name := NULLIF(TRIM(new.raw_user_meta_data->>'last_name'), '');
  v_raw_role := LOWER(TRIM(COALESCE(new.raw_user_meta_data->>'role', 'child')));

  IF v_raw_role = 'parent' THEN
    v_sanitized_role := 'parent';
  ELSE
    v_sanitized_role := 'child';
  END IF;

  INSERT INTO public.profiles (
    id,
    first_name,
    last_name,
    role,
    created_at,
    updated_at
  ) VALUES (
    new.id,
    v_first_name,
    v_last_name,
    v_sanitized_role,
    NOW(),
    NOW()
  );

  RETURN new;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
