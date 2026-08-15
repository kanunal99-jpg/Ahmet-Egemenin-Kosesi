-- ============================================================================
-- Migration: 20260815000013_disable_legacy_child_email_link.sql
-- Description: Historical Depreciation/Disabling of Legacy Child Email Link
-- ============================================================================

-- Disable legacy email linking function in favor of code-based linking
CREATE OR REPLACE FUNCTION public.create_parent_child_link_by_email(
  p_child_email TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN jsonb_build_object(
    'success', FALSE,
    'error', 'E-posta ile bağlama devre dışı bırakılmıştır. Lütfen davet kodunu kullanın.'
  );
END;
$$;
