-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- Migration: 20260815000008_rls_and_index_hardening.sql
-- Purpose: performance-safe RLS initplan hardening, policy consolidation,
--          and safe foreign-key/duplicate-index cleanup.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. RLS initplan hardening: wrap auth.uid() in SELECT so it is evaluated once
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Videos viewable by public or owner or admin" ON public.videos;
CREATE POLICY "Videos viewable by public or owner or admin"
  ON public.videos FOR SELECT
  USING (
    ((is_deleted = false) AND (visibility = 'public'))
    OR ((select auth.uid()) = owner_id)
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Publishers and Admins can insert videos" ON public.videos;
CREATE POLICY "Publishers and Admins can insert videos"
  ON public.videos FOR INSERT
  WITH CHECK (
    (select auth.uid()) = owner_id
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = ANY (ARRAY['publisher'::text, 'admin'::text])
    )
  );

DROP POLICY IF EXISTS "Publishers and Admins can update their own videos" ON public.videos;
CREATE POLICY "Publishers and Admins can update their own videos"
  ON public.videos FOR UPDATE
  USING (
    ((select auth.uid()) = owner_id AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = ANY (ARRAY['publisher'::text, 'admin'::text])
    ))
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Users can view their own watch history" ON public.watch_history;
CREATE POLICY "Users can view their own watch history"
  ON public.watch_history FOR SELECT
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert their own watch history" ON public.watch_history;
CREATE POLICY "Users can insert their own watch history"
  ON public.watch_history FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update their own watch history" ON public.watch_history;
CREATE POLICY "Users can update their own watch history"
  ON public.watch_history FOR UPDATE
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 2. Consolidate duplicate permissive SELECT policy on favorites
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view their own favorites" ON public.favorites;
DROP POLICY IF EXISTS "Users can manage their own favorites" ON public.favorites;
CREATE POLICY "Users can manage their own favorites"
  ON public.favorites FOR ALL
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 3. Consolidate parent_children SELECT policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS parent_children_select_parent ON public.parent_children;
DROP POLICY IF EXISTS parent_children_select_child ON public.parent_children;
DROP POLICY IF EXISTS parent_children_admin_all ON public.parent_children;
CREATE POLICY parent_children_select_authorized
  ON public.parent_children FOR SELECT TO authenticated
  USING (
    (select auth.uid()) = parent_id
    OR (select auth.uid()) = child_id
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- 4. Consolidate watch_history_sessions SELECT policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS watch_history_sessions_select_own ON public.watch_history_sessions;
DROP POLICY IF EXISTS watch_history_sessions_admin_select ON public.watch_history_sessions;
CREATE POLICY watch_history_sessions_select_authorized
  ON public.watch_history_sessions FOR SELECT TO authenticated
  USING (
    (select auth.uid()) = user_id
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (select auth.uid())
        AND profiles.role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Safe missing FK indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_favorites_video_id
  ON public.favorites(video_id);

CREATE INDEX IF NOT EXISTS idx_watch_history_video_id
  ON public.watch_history(video_id);

-- ---------------------------------------------------------------------------
-- 6. Remove exact duplicate indexes, retaining established primary names
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_favorites_user_id;
DROP INDEX IF EXISTS public.idx_videos_category_id;
DROP INDEX IF EXISTS public.idx_videos_deleted;
DROP INDEX IF EXISTS public.idx_videos_owner_id;
DROP INDEX IF EXISTS public.idx_watch_history_user_id;
