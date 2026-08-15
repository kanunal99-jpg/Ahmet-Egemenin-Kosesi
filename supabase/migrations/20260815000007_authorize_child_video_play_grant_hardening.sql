-- ============================================================================
-- AHMET EGEMEN'İN KÖŞESİ
-- Migration: 20260815000007_authorize_child_video_play_grant_hardening.sql
-- Purpose: Make authorize_child_video_play execute grants explicit and
--          self-contained after the consolidated live watch/security apply.
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authorize_child_video_play(UUID) TO anon, authenticated;
