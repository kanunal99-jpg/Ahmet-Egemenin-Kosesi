-- ============================================================================
-- Migration: 20260815000008_rls_and_index_hardening.sql
-- Description: Historical RLS and Performance Index Hardening
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_watch_history_user_video ON public.watch_history(user_id, video_id);
CREATE INDEX IF NOT EXISTS idx_watch_sessions_user_started ON public.watch_history_sessions(user_id, started_at);
CREATE INDEX IF NOT EXISTS idx_parent_settings_user_id ON public.parent_settings(user_id);
