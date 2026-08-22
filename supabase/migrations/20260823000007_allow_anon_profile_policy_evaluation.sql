-- The public videos SELECT policy references profiles for its admin branch.
-- Profiles RLS exposes no rows to anon, so this grant fixes policy evaluation
-- without exposing profile records.
GRANT SELECT ON public.profiles TO anon;
