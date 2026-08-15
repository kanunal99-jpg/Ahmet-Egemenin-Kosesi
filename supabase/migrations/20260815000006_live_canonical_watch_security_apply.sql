-- ============================================================================
-- Migration: 20260815000006_live_canonical_watch_security_apply.sql
-- Description: Historical Canonical Watch Session Security Apply
-- ============================================================================

-- Ensure canonical RLS policies for watch history and sessions
ALTER TABLE IF EXISTS public.watch_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.watch_history_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'watch_history' AND policyname = 'watch_history_owner_select'
  ) THEN
    CREATE POLICY watch_history_owner_select ON public.watch_history
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'watch_history_sessions' AND policyname = 'watch_history_sessions_owner_select'
  ) THEN
    CREATE POLICY watch_history_sessions_owner_select ON public.watch_history_sessions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;
