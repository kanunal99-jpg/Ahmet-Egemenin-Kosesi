-- CRIT-50: legacy email-based child linking is retired.
REVOKE EXECUTE ON FUNCTION public.create_parent_child_link_by_email(TEXT) FROM PUBLIC, anon, authenticated;
