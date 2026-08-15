-- CRIT-25 follow-up: legacy BOOLEAN PIN RPC is retained only as a rollback artifact.
REVOKE EXECUTE ON FUNCTION public.verify_parent_pin_legacy_boolean(TEXT) FROM PUBLIC, anon, authenticated;
