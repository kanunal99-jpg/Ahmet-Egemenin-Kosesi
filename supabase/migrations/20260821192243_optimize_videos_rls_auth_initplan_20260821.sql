-- ============================================================================
-- Migration: 20260821192243_optimize_videos_rls_auth_initplan_20260821.sql
-- Purpose: Reconstruct the live RLS optimization using init-plan-friendly
--          (select auth.uid()) expressions and preserve authorization semantics.
-- ============================================================================

DROP POLICY IF EXISTS "Authorized roles can insert videos" ON public.videos;
DROP POLICY IF EXISTS "Authorized roles can update videos" ON public.videos;
DROP POLICY IF EXISTS "Videos viewable by public or owner or admin" ON public.videos;

CREATE POLICY "Authorized roles can insert videos"
  ON public.videos
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = owner_id
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = ANY (ARRAY['parent'::text, 'publisher'::text, 'admin'::text])
    )
  );

CREATE POLICY "Authorized roles can update videos"
  ON public.videos
  FOR UPDATE
  TO authenticated
  USING (
    (
      owner_id = (SELECT auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = (SELECT auth.uid())
          AND profiles.role = ANY (ARRAY['parent'::text, 'publisher'::text, 'admin'::text])
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'::text
    )
  )
  WITH CHECK (
    (
      owner_id = (SELECT auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = (SELECT auth.uid())
          AND profiles.role = ANY (ARRAY['parent'::text, 'publisher'::text, 'admin'::text])
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'::text
    )
  );

CREATE POLICY "Videos viewable by public or owner or admin"
  ON public.videos
  FOR SELECT
  TO public
  USING (
    (is_deleted = false AND visibility = 'public'::text)
    OR (SELECT auth.uid()) = owner_id
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'::text
    )
  );
